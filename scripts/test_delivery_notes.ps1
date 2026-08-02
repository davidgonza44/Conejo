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

Write-Host "=== SETUP: sesiones y usuarios de prueba ==="
$admin = New-LoginSession "admin" "admin123"

# Crea usuarios vendedor e inventario si no existen (409 = ya existian)
$r = Invoke-Api -Method POST -Url "/users" -Session $admin -Body @{
    name = "Vendedor Prueba"; email = "vendedor@elconejo.com"; username = "vendedor1"; password = "vendedor123"; role = "vendedor" }
Write-Host "  crear vendedor1 -> HTTP $($r.code)"
$r = Invoke-Api -Method POST -Url "/users" -Session $admin -Body @{
    name = "Inventario Prueba"; email = "inventario@elconejo.com"; username = "inventario1"; password = "inventario123"; role = "inventario" }
Write-Host "  crear inventario1 -> HTTP $($r.code)"

$vendedor = New-LoginSession "vendedor1" "vendedor123"
$inventario = New-LoginSession "inventario1" "inventario123"

# Productos activos con stock para las pruebas
$prods = (Invoke-Api -Method GET -Url "/products" -Session $admin).body.items | Where-Object { $_.is_active -and $_.current_stock -gt 5 }
$p1 = $prods[0]; $p2 = $prods[1]
Write-Host "  producto A: id=$($p1.id) '$($p1.name)' stock=$($p1.current_stock) precio=$($p1.sale_price)"
Write-Host "  producto B: id=$($p2.id) '$($p2.name)' stock=$($p2.current_stock) precio=$($p2.sale_price)"

# Producto inactivo desechable para la prueba 409
$catId = $p1.category_id
$r = Invoke-Api -Method POST -Url "/products" -Session $admin -Body @{
    code = "TEST-NE-INACTIVO"; name = "Producto inactivo para prueba NE"; category_id = $catId
    unit = "unidad"; current_stock = 10; minimum_stock = 1; purchase_price = 1; sale_price = 2 }
if ($r.code -eq 201) { $inactivoId = $r.body.id }
else {
    $inactivoId = ((Invoke-Api -Method GET -Url "/products?search=TEST-NE-INACTIVO&include_inactive=1" -Session $admin).body.items | Select-Object -First 1).id
}
Invoke-Api -Method DELETE -Url "/products/$inactivoId" -Session $admin | Out-Null
Write-Host "  producto inactivo de prueba: id=$inactivoId"

$notaBody = @{
    customer_name = "Juan Perez"; customer_document = "V-12345678"
    customer_phone = "0414-0000000"; customer_address = "Acarigua"
    items = @(
        @{ product_id = $p1.id; quantity = 2 },
        @{ product_id = $p2.id; quantity = 1 }
    )
}

Write-Host ""
Write-Host "=== CREACION ==="
$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body $notaBody
Check "1. Crear nota como vendedor" 201 $r.code "($($r.body.delivery_note.note_number), total=$($r.body.delivery_note.total_amount))"
$notaVendedor = $r.body.delivery_note

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $admin -Body $notaBody
Check "2. Crear nota como admin" 201 $r.code "($($r.body.delivery_note.note_number))"
$notaAdmin = $r.body.delivery_note

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Body $notaBody
Check "3. Crear nota sin login" 401 $r.code

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $inventario -Body $notaBody
Check "4. Crear nota como inventario" 403 $r.code

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{ items = @(@{ product_id = $p1.id; quantity = 1 }) }
Check "5. Crear nota sin customer_name" 400 $r.code "($($r.body.error))"

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{ customer_name = "Juan" }
Check "6. Crear nota sin items" 400 $r.code "($($r.body.error))"

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{ customer_name = "Juan"; items = @(@{ product_id = $p1.id; quantity = 0 }) }
Check "7a. Crear nota con quantity 0" 400 $r.code
$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{ customer_name = "Juan"; items = @(@{ product_id = $p1.id; quantity = -3 }) }
Check "7b. Crear nota con quantity negativa" 400 $r.code

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{ customer_name = "Juan"; items = @(@{ product_id = 999999; quantity = 1 }) }
Check "8. Crear nota con producto inexistente" 404 $r.code

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{ customer_name = "Juan"; items = @(@{ product_id = $inactivoId; quantity = 1 }) }
Check "9. Crear nota con producto inactivo" 409 $r.code "($($r.body.error))"

$r = Invoke-Api -Method POST -Url "/delivery-notes" -Session $vendedor -Body @{ customer_name = "Juan"; items = @(@{ product_id = $p1.id; quantity = 999999 }) }
Check "10. Crear nota con stock insuficiente" 409 $r.code "($($r.body.error))"

Write-Host ""
Write-Host "=== EFECTOS EN INVENTARIO ==="
# Se crearon 2 notas (vendedor y admin), cada una resta 2 de p1 y 1 de p2
$p1Ahora = (Invoke-Api -Method GET -Url "/products/$($p1.id)" -Session $admin).body
$p2Ahora = (Invoke-Api -Method GET -Url "/products/$($p2.id)" -Session $admin).body
Check "11a. Stock producto A descontado" ($p1.current_stock - 4) $p1Ahora.current_stock "(antes $($p1.current_stock))"
Check "11b. Stock producto B descontado" ($p2.current_stock - 2) $p2Ahora.current_stock "(antes $($p2.current_stock))"

$movs = (Invoke-Api -Method GET -Url "/inventory/products/$($p1.id)/movements?limit=5" -Session $admin).body.items
$movVendedor = $movs | Where-Object { $_.reason -eq "Nota de entrega #$($notaVendedor.note_number)" } | Select-Object -First 1
$okMov = ($null -ne $movVendedor) -and ($movVendedor.movement_type -eq "salida") -and ($movVendedor.user -eq "Vendedor Prueba")
Check "12. Movimiento salida asociado al usuario" $true $okMov "(tipo=$($movVendedor.movement_type), user=$($movVendedor.user), reason='$($movVendedor.reason)')"

Write-Host ""
Write-Host "=== LISTADO Y DETALLE ==="
$r = Invoke-Api -Method GET -Url "/delivery-notes" -Session $inventario
Check "13a. Listar notas (inventario)" 200 $r.code "(count=$($r.body.count))"
$r = Invoke-Api -Method GET -Url "/delivery-notes?status=issued&customer_name=Juan" -Session $vendedor
Check "13b. Listar con filtros (vendedor)" 200 $r.code "(count=$($r.body.count))"
$resumen = $r.body.items | Select-Object -First 1
Write-Host "     resumen: $(($resumen | ConvertTo-Json -Compress))"

$r = Invoke-Api -Method GET -Url "/delivery-notes/$($notaVendedor.id)" -Session $vendedor
$nItems = if ($r.body.items) { @($r.body.items).Count } else { 0 }
Check "14. Ver detalle de nota" 200 $r.code "(items=$nItems, total=$($r.body.total_amount))"

Write-Host ""
Write-Host "=== CANCELACION ==="
$r = Invoke-Api -Method POST -Url "/delivery-notes/$($notaVendedor.id)/cancel" -Session $vendedor
Check "15. Cancelar como vendedor" 403 $r.code

$r = Invoke-Api -Method POST -Url "/delivery-notes/$($notaVendedor.id)/cancel" -Session $inventario
Check "16a. Cancelar como inventario" 200 $r.code "(status=$($r.body.delivery_note.status), cancelled_by=$($r.body.delivery_note.cancelled_by))"

$r = Invoke-Api -Method POST -Url "/delivery-notes/$($notaAdmin.id)/cancel" -Session $admin
Check "16b. Cancelar como admin" 200 $r.code "(status=$($r.body.delivery_note.status))"

$p1Final = (Invoke-Api -Method GET -Url "/products/$($p1.id)" -Session $admin).body
$p2Final = (Invoke-Api -Method GET -Url "/products/$($p2.id)" -Session $admin).body
Check "17a. Stock producto A devuelto" $p1.current_stock $p1Final.current_stock
Check "17b. Stock producto B devuelto" $p2.current_stock $p2Final.current_stock

$movs = (Invoke-Api -Method GET -Url "/inventory/products/$($p1.id)/movements?limit=5" -Session $admin).body.items
$movCancel = $movs | Where-Object { $_.reason -eq "Cancelacion de nota de entrega #$($notaVendedor.note_number)" -or $_.reason -like "Cancelaci*n de nota de entrega #$($notaVendedor.note_number)" } | Select-Object -First 1
$okCancel = ($null -ne $movCancel) -and ($movCancel.movement_type -eq "entrada") -and ($movCancel.user -eq "Inventario Prueba")
Check "17c. Movimiento entrada por cancelacion" $true $okCancel "(tipo=$($movCancel.movement_type), user=$($movCancel.user))"

$r = Invoke-Api -Method POST -Url "/delivery-notes/$($notaVendedor.id)/cancel" -Session $admin
Check "18. Cancelar dos veces" 409 $r.code "($($r.body.error))"

Write-Host ""
if ($script:fallos -eq 0) { Write-Host "RESULTADO FINAL: TODAS LAS PRUEBAS PASARON" }
else { Write-Host "RESULTADO FINAL: $script:fallos PRUEBAS FALLARON" }
