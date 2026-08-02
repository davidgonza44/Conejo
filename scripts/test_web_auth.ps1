$ErrorActionPreference = "Continue"
$base = "http://localhost:5000"
$script:fallos = 0

function Invoke-Page {
    param($Url, $Session, [switch]$NoRedirect, $Method = "GET", $Body)
    $params = @{ Method = $Method; Uri = "$base$Url"; TimeoutSec = 25; UseBasicParsing = $true }
    if ($Session) { $params.WebSession = $Session }
    if ($NoRedirect) { $params.MaximumRedirection = 0 }
    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 5)
    }
    try {
        $r = Invoke-WebRequest @params
        return @{ code = [int]$r.StatusCode; content = [string]$r.Content; location = [string]$r.Headers["Location"] }
    } catch {
        $resp = $_.Exception.Response
        $code = if ($resp) { [int]$resp.StatusCode } else { -1 }
        $loc = ""
        if ($resp) { try { $loc = [string]$resp.Headers["Location"] } catch { } }
        $content = ""
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $content = $_.ErrorDetails.Message }
        return @{ code = $code; content = $content; location = $loc }
    }
}

function New-LoginSession {
    param($Identifier, $Password)
    $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $r = Invoke-Page -Url "/api/auth/login" -Method POST -Body @{ identifier = $Identifier; password = $Password } -Session $s
    if ($r.code -ne 200) { Write-Host "[SETUP-ERROR] login $Identifier -> HTTP $($r.code)"; $script:fallos++ }
    return $s
}

function Check {
    param($Name, $Expected, $Actual, $Extra = "")
    if ($Expected -eq $Actual) { Write-Host "[OK] $Name -> $Actual $Extra" }
    else { Write-Host "[FALLO] $Name -> esperado $Expected, obtenido $Actual $Extra"; $script:fallos++ }
}

Write-Host "=== PAGINA DE LOGIN ==="
$r = Invoke-Page -Url "/login"
Check "1a. GET /login" 200 $r.code
Check "1b. Contiene titulo y subtitulo" $true (($r.content -like "*El Conejo*") -and ($r.content -like "*control de inventario y reabastecimiento*"))
Check "9a. Contiene boton de Google" $true ($r.content -like "*/api/auth/google/login*")

Write-Host ""
Write-Host "=== LOGIN TRADICIONAL ==="
$admin = New-LoginSession "admin" "admin123"
$r = Invoke-Page -Url "/dashboard" -Session $admin
Check "2. Admin llega al dashboard de reportes" $true (($r.code -eq 200) -and ($r.content -like "*Dashboard de reportes*"))

$s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$r = Invoke-Page -Url "/api/auth/login" -Method POST -Body @{ identifier = "admin"; password = "clave-mala" } -Session $s
Check "3. Password incorrecta -> JSON 401" $true (($r.code -eq 401) -and ($r.content -like "*error*"))

Write-Host ""
Write-Host "=== LOGOUT ==="
$r = Invoke-Page -Url "/api/auth/logout" -Method POST -Session $admin
Check "4a. Logout" 200 $r.code
$r = Invoke-Page -Url "/dashboard" -Session $admin -NoRedirect
Check "4b. Tras logout /dashboard redirige a /login" $true (($r.code -eq 302) -and ($r.location -like "*/login*")) "(Location=$($r.location))"

Write-Host ""
Write-Host "=== PROTECCION DE /dashboard ==="
$r = Invoke-Page -Url "/dashboard" -NoRedirect
Check "5. Sin sesion -> 302 a /login" $true (($r.code -eq 302) -and ($r.location -like "*/login*")) "(Location=$($r.location))"

$vendedor = New-LoginSession "vendedor1" "vendedor123"
$r = Invoke-Page -Url "/dashboard" -Session $vendedor -NoRedirect
Check "6a. Vendedor -> 302 a /access-denied" $true (($r.code -eq 302) -and ($r.location -like "*/access-denied*")) "(Location=$($r.location))"
$r = Invoke-Page -Url "/access-denied" -Session $vendedor
Check "6b. Pagina acceso denegado" $true (($r.code -eq 200) -and ($r.content -like "*No tiene permisos para acceder*"))

$admin = New-LoginSession "admin" "admin123"
$r = Invoke-Page -Url "/dashboard" -Session $admin
Check "7. Admin accede" 200 $r.code

$inventario = New-LoginSession "inventario1" "inventario123"
$r = Invoke-Page -Url "/dashboard" -Session $inventario
Check "8. Inventario accede" 200 $r.code

Write-Host ""
Write-Host "=== GOOGLE ==="
$r = Invoke-Page -Url "/api/auth/google/login" -NoRedirect
Check "9b. /api/auth/google/login redirige a Google" $true (($r.code -eq 302) -and ($r.location -like "*accounts.google.com*")) "(Location=$($r.location.Substring(0, [Math]::Min(60, $r.location.Length))))"

Write-Host ""
Write-Host "=== PASSWORDLESS ==="
$r = Invoke-Page -Url "/api/auth/passwordless/request" -Method POST -Body @{ email = "admin@elconejo.com" }
$pwlData = $null
if ($r.content) { try { $pwlData = $r.content | ConvertFrom-Json } catch { } }
Check "10. Request -> 200 con mensaje y dev_token (desarrollo)" $true (($r.code -eq 200) -and ($null -ne $pwlData.dev_token)) "(mensaje='$($pwlData.message)')"

$pwlSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$r = Invoke-Page -Url "/api/auth/passwordless/verify" -Method POST -Session $pwlSession -Body @{ email = "admin@elconejo.com"; token = $pwlData.dev_token }
Check "11a. Verify -> 200" 200 $r.code
$r = Invoke-Page -Url "/dashboard" -Session $pwlSession
Check "11b. Sesion passwordless entra al dashboard" 200 $r.code

Write-Host ""
Write-Host "=== API SIGUE SIENDO JSON (Postman intacto) ==="
$r = Invoke-Page -Url "/api/auth/me" -NoRedirect
Check "12. /api/auth/me sin sesion -> JSON 401 (no redirect)" $true (($r.code -eq 401) -and ($r.content -like "*{*error*"))
$r = Invoke-Page -Url "/api/reports/dashboard-summary" -NoRedirect
Check "13. /api/reports/dashboard-summary sin sesion -> JSON 401" $true (($r.code -eq 401) -and ($r.content -like "*{*error*"))

Write-Host ""
Write-Host "=== /login CON SESION ACTIVA ==="
$r = Invoke-Page -Url "/login" -Session $admin -NoRedirect
Check "14a. Admin en /login -> 302 a /dashboard" $true (($r.code -eq 302) -and ($r.location -like "*/dashboard*")) "(Location=$($r.location))"
$r = Invoke-Page -Url "/login" -Session $vendedor -NoRedirect
Check "14b. Vendedor en /login -> 302 a /access-denied" $true (($r.code -eq 302) -and ($r.location -like "*/access-denied*")) "(Location=$($r.location))"

Write-Host ""
if ($script:fallos -eq 0) { Write-Host "RESULTADO FINAL: TODAS LAS PRUEBAS PASARON" }
else { Write-Host "RESULTADO FINAL: $script:fallos PRUEBAS FALLARON" }
