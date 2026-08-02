$ErrorActionPreference = "Continue"
$base = "http://localhost:5000/api"
$script:fallos = 0

function Invoke-Api {
    param($Method, $Url, $Body, $Session)
    $params = @{ Method = $Method; Uri = "$base$Url"; TimeoutSec = 25; UseBasicParsing = $true }
    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 8)
    }
    if ($Session) { $params.WebSession = $Session }
    try {
        $r = Invoke-WebRequest @params
        $parsed = $null
        if ($r.Content) { try { $parsed = $r.Content | ConvertFrom-Json } catch { $parsed = $r.Content } }
        return @{ code = [int]$r.StatusCode; body = $parsed }
    } catch {
        $resp = $_.Exception.Response
        $code = if ($resp) { [int]$resp.StatusCode } else { -1 }
        $content = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try { $content = $_.ErrorDetails.Message | ConvertFrom-Json } catch { $content = $_.ErrorDetails.Message }
        }
        return @{ code = $code; body = $content }
    }
}

function New-LoginSession {
    param($Identifier, $Password)
    $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $r = Invoke-Api -Method POST -Url "/auth/login" -Body @{ identifier = $Identifier; password = $Password } -Session $s
    if ($r.code -ne 200) { Write-Host "[SETUP-ERROR] login $Identifier -> HTTP $($r.code)"; $script:fallos++ }
    return $s
}

function Check {
    param($Name, $Expected, $Actual, $Extra = "")
    if ($Expected -eq $Actual) { Write-Host "[OK] $Name -> $Actual $Extra" }
    else { Write-Host "[FALLO] $Name -> esperado $Expected, obtenido $Actual $Extra"; $script:fallos++ }
}

Write-Host "=== SETUP: sesiones ==="
$admin = New-LoginSession "admin" "admin123"
Invoke-Api -Method POST -Url "/users" -Session $admin -Body @{
    name = "Vendedor Prueba"; email = "vendedor@elconejo.com"; username = "vendedor1"; password = "vendedor123"; role = "vendedor" } | Out-Null
Invoke-Api -Method POST -Url "/users" -Session $admin -Body @{
    name = "Inventario Prueba"; email = "inventario@elconejo.com"; username = "inventario1"; password = "inventario123"; role = "inventario" } | Out-Null
$vendedor = New-LoginSession "vendedor1" "vendedor123"
$inventario = New-LoginSession "inventario1" "inventario123"

Write-Host ""
Write-Host "=== AUTENTICACION Y ROLES ==="
$r = Invoke-Api -Method GET -Url "/reports/dashboard-summary"
Check "1. Reporte sin login" 401 $r.code
$r = Invoke-Api -Method GET -Url "/reports/dashboard-summary" -Session $vendedor
Check "2. Reporte como vendedor" 403 $r.code
$r = Invoke-Api -Method GET -Url "/reports/dashboard-summary" -Session $admin
Check "3. Reporte como admin" 200 $r.code
$r = Invoke-Api -Method GET -Url "/reports/dashboard-summary" -Session $inventario
Check "4. Reporte como inventario" 200 $r.code

Write-Host ""
Write-Host "=== DATOS: nota de entrega emitida temporal ==="
$prods = (Invoke-Api -Method GET -Url "/products" -Session $admin).body.items | Where-Object { $_.is_active -and $_.current_stock -gt 5 }
$p1 = $prods[0]; $p2 = $prods[1]
$stockInicialP1 = $p1.current_stock; $stockInicialP2 = $p2.current_stock
Write-Host "  producto A: id=$($p1.id) stock=$stockInicialP1 | producto B: id=$($p2.id) stock=$stockInicialP2"
$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{
    customer_name = "Cliente Reportes"
    items = @(@{ product_id = $p1.id; quantity = 2 }, @{ product_id = $p2.id; quantity = 1 })
}
Check "setup. Nota emitida para reportes" 201 $r.code "($($r.body.delivery_note.note_number))"
$notaReporte = $r.body.delivery_note

Write-Host ""
Write-Host "=== 1. DASHBOARD SUMMARY ==="
$r = Invoke-Api -Method GET -Url "/reports/dashboard-summary" -Session $admin
$d = $r.body
Check "5a. Devuelve conteos de productos" $true ($d.total_products -ge 1) "(total=$($d.total_products), activos=$($d.active_products), inactivos=$($d.inactive_products))"
Check "5b. Conteos de notas" $true (($d.issued_delivery_notes -ge 1) -and ($d.cancelled_delivery_notes -ge 2)) "(emitidas=$($d.issued_delivery_notes), canceladas=$($d.cancelled_delivery_notes))"
Check "5c. Montos de notas emitidas" $true (($d.total_amount_issued_delivery_notes -gt 0) -and ($d.average_amount_issued_delivery_notes -gt 0)) "(total=$($d.total_amount_issued_delivery_notes), promedio=$($d.average_amount_issued_delivery_notes))"
Check "5d. Otros conteos" $true (($d.total_categories -ge 1) -and ($d.total_inventory_movements -ge 1) -and ($d.low_stock_products -ge 0)) "(categorias=$($d.total_categories), movimientos=$($d.total_inventory_movements), bajo_stock=$($d.low_stock_products))"

Write-Host ""
Write-Host "=== 2-3. STOCK VS MINIMO Y BAJO STOCK ==="
$r = Invoke-Api -Method GET -Url "/reports/stock-vs-minimum" -Session $admin
$primera = $r.body.items | Select-Object -First 1
Check "6. stock-vs-minimum devuelve productos" $true (($r.code -eq 200) -and ($r.body.count -ge 1)) "(count=$($r.body.count), primero: $($primera.name) dif=$($primera.difference))"
$r = Invoke-Api -Method GET -Url "/reports/low-stock-products" -Session $inventario
Check "7. low-stock-products responde" $true (($r.code -eq 200) -and ($r.body.count -ge 0)) "(count=$($r.body.count))"

Write-Host ""
Write-Host "=== 4. PRODUCTOS SIN MOVIMIENTO ==="
$r = Invoke-Api -Method GET -Url "/reports/products-without-movement" -Session $admin
Check "8a. Sin days (default 30)" $true (($r.code -eq 200) -and ($r.body.days -eq 30)) "(count=$($r.body.count))"
$r = Invoke-Api -Method GET -Url "/reports/products-without-movement?days=1" -Session $admin
Check "8b. Con days=1" 200 $r.code "(count=$($r.body.count))"
$r = Invoke-Api -Method GET -Url "/reports/products-without-movement?days=abc" -Session $admin
Check "9a. days no numerico" 400 $r.code "($($r.body.error))"
$r = Invoke-Api -Method GET -Url "/reports/products-without-movement?days=0" -Session $admin
Check "9b. days menor que 1" 400 $r.code

Write-Host ""
Write-Host "=== 5. EXCESO DE STOCK ==="
$r = Invoke-Api -Method GET -Url "/reports/excess-stock-products" -Session $admin
Check "10a. Sin multiplier (default 3)" $true (($r.code -eq 200) -and ($r.body.multiplier -eq 3)) "(count=$($r.body.count))"
$r = Invoke-Api -Method GET -Url "/reports/excess-stock-products?multiplier=1.5" -Session $admin
Check "10b. Con multiplier=1.5" 200 $r.code "(count=$($r.body.count))"
$r = Invoke-Api -Method GET -Url "/reports/excess-stock-products?multiplier=abc" -Session $admin
Check "11a. multiplier no numerico" 400 $r.code
$r = Invoke-Api -Method GET -Url "/reports/excess-stock-products?multiplier=0.5" -Session $admin
Check "11b. multiplier menor que 1" 400 $r.code

Write-Host ""
Write-Host "=== 6. ENTRADAS VS SALIDAS ==="
$r = Invoke-Api -Method GET -Url "/reports/entries-vs-exits" -Session $admin
$dia = $r.body.items | Select-Object -Last 1
Check "12a. Agrupa por dia" $true (($r.code -eq 200) -and ($r.body.count -ge 1)) "(dias=$($r.body.count); ultimo: $($dia.date) ent=$($dia.total_entries_quantity)/$($dia.entries_count) sal=$($dia.total_exits_quantity)/$($dia.exits_count))"
$r = Invoke-Api -Method GET -Url "/reports/entries-vs-exits?date_from=2100-01-01&date_to=2100-01-31" -Session $admin
Check "12b. Rango sin datos -> lista vacia" $true (($r.code -eq 200) -and ($r.body.count -eq 0))

Write-Host ""
Write-Host "=== 7. MOVIMIENTOS POR CATEGORIA ==="
$r = Invoke-Api -Method GET -Url "/reports/movements-by-category" -Session $admin
$cat = $r.body.items | Select-Object -First 1
Check "13. Agrupa por categoria" $true (($r.code -eq 200) -and ($r.body.count -ge 1)) "(categorias=$($r.body.count); primera: $($cat.category_name) mov=$($cat.total_movements_count))"

Write-Host ""
Write-Host "=== 8-9. TOP Y MENOS SALIDAS ==="
$r = Invoke-Api -Method GET -Url "/reports/top-products-by-exits?limit=5" -Session $admin
$tp = @($r.body.items)
$ordenDesc = $true
for ($i = 1; $i -lt $tp.Count; $i++) { if ($tp[$i].total_quantity -gt $tp[$i-1].total_quantity) { $ordenDesc = $false } }
Check "14. top-products-by-exits" $true (($r.code -eq 200) -and ($r.body.count -ge 1) -and $ordenDesc) "(count=$($r.body.count); 1ro: $($tp[0].product_name) qty=$($tp[0].total_quantity))"

$r = Invoke-Api -Method GET -Url "/reports/least-products-by-exits" -Session $admin
$lp = @($r.body.items)
$ordenAsc = $true
for ($i = 1; $i -lt $lp.Count; $i++) { if ($lp[$i].total_quantity -lt $lp[$i-1].total_quantity) { $ordenAsc = $false } }
$incluyeCero = ($lp | Where-Object { $_.total_quantity -eq 0 }).Count -ge 0
Check "15. least-products-by-exits" $true (($r.code -eq 200) -and ($r.body.count -ge 1) -and $ordenAsc) "(count=$($r.body.count); 1ro: $($lp[0].product_name) qty=$($lp[0].total_quantity); con 0 salidas=$((@($lp | Where-Object { $_.total_quantity -eq 0 })).Count))"

Write-Host ""
Write-Host "=== 10. AJUSTES DE INVENTARIO ==="
$r = Invoke-Api -Method GET -Url "/reports/inventory-adjustments" -Session $admin
$tieneResumen = ($null -ne $r.body.summary) -and ($null -ne $r.body.summary.total_adjustments) -and ($null -ne $r.body.summary.adjusted_products_count)
Check "16. Resumen y detalle de ajustes" $true (($r.code -eq 200) -and $tieneResumen) "(total=$($r.body.summary.total_adjustments), productos=$($r.body.summary.adjusted_products_count))"

Write-Host ""
Write-Host "=== 11. NOTAS POR PERIODO ==="
$r = Invoke-Api -Method GET -Url "/reports/delivery-notes-by-period" -Session $admin
$diaNotas = $r.body.items | Where-Object { $_.issued_count -ge 1 } | Select-Object -First 1
$agrupaBien = ($r.body.count -ge 1) -and ($null -ne $diaNotas) -and ($diaNotas.issued_amount -gt 0)
Check "17. Agrupa emitidas y canceladas por dia" $true (($r.code -eq 200) -and $agrupaBien) "(dias=$($r.body.count); $($diaNotas.date): emitidas=$($diaNotas.issued_count)/$($diaNotas.issued_amount), canceladas=$($diaNotas.cancelled_count)/$($diaNotas.cancelled_amount))"

Write-Host ""
Write-Host "=== 12. TOP PRODUCTOS ENTREGADOS ==="
$r = Invoke-Api -Method GET -Url "/reports/top-delivered-products" -Session $admin
$td = @($r.body.items)
Check "18. Solo notas emitidas" $true (($r.code -eq 200) -and ($r.body.count -ge 1) -and ($td[0].total_quantity -gt 0)) "(count=$($r.body.count); 1ro: $($td[0].product_name) qty=$($td[0].total_quantity) monto=$($td[0].total_amount) notas=$($td[0].notes_count))"

Write-Host ""
Write-Host "=== 13-14. NOTAS POR USUARIO Y CLIENTE ==="
$r = Invoke-Api -Method GET -Url "/reports/delivery-notes-by-user" -Session $admin
$filaVend = $r.body.items | Where-Object { $_.user_name -eq "Vendedor Prueba" } | Select-Object -First 1
Check "19. delivery-notes-by-user" $true (($r.code -eq 200) -and ($null -ne $filaVend) -and ($filaVend.notes_count -ge 1)) "(usuarios=$($r.body.count); vendedor: notas=$($filaVend.notes_count) monto=$($filaVend.total_amount))"

$r = Invoke-Api -Method GET -Url "/reports/delivery-notes-by-customer" -Session $admin
$filaCli = $r.body.items | Where-Object { $_.customer_name -eq "Cliente Reportes" } | Select-Object -First 1
Check "20. delivery-notes-by-customer" $true (($r.code -eq 200) -and ($null -ne $filaCli) -and ($filaCli.total_amount -gt 0)) "(clientes=$($r.body.count); Cliente Reportes: notas=$($filaCli.notes_count) monto=$($filaCli.total_amount))"

Write-Host ""
Write-Host "=== VALIDACIONES DE FECHAS Y LIMIT ==="
$r = Invoke-Api -Method GET -Url "/reports/entries-vs-exits?date_from=2026-13-99" -Session $admin
Check "21. date_from invalido" 400 $r.code "($($r.body.error))"
$r = Invoke-Api -Method GET -Url "/reports/entries-vs-exits?date_from=2026-07-10&date_to=2026-07-01" -Session $admin
Check "22. date_from mayor que date_to" 400 $r.code "($($r.body.error))"
$r = Invoke-Api -Method GET -Url "/reports/top-products-by-exits?limit=0" -Session $admin
Check "23a. limit menor que 1" 400 $r.code
$r = Invoke-Api -Method GET -Url "/reports/top-products-by-exits?limit=abc" -Session $admin
Check "23b. limit no numerico" 400 $r.code
$r = Invoke-Api -Method GET -Url "/reports/delivery-notes-by-customer?date_to=01-07-2026" -Session $admin
Check "24. date_to formato invalido" 400 $r.code

Write-Host ""
Write-Host "=== LIMPIEZA: cancelar nota temporal y verificar solo-lectura ==="
$r = Invoke-Api -Method POST -Url "/delivery-notes/$($notaReporte.id)/cancel" -Session $admin
Check "25. Cancelar nota temporal" 200 $r.code
$p1Final = (Invoke-Api -Method GET -Url "/products/$($p1.id)" -Session $admin).body
$p2Final = (Invoke-Api -Method GET -Url "/products/$($p2.id)" -Session $admin).body
Check "26a. Stock producto A intacto" $stockInicialP1 $p1Final.current_stock
Check "26b. Stock producto B intacto" $stockInicialP2 $p2Final.current_stock

Write-Host ""
if ($script:fallos -eq 0) { Write-Host "RESULTADO FINAL: TODAS LAS PRUEBAS PASARON" }
else { Write-Host "RESULTADO FINAL: $script:fallos PRUEBAS FALLARON" }
