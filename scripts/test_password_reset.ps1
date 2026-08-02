# Pruebas del modulo de recuperacion de contrasena + correo + no-regresion.
# Requiere el servidor corriendo (python run.py) y APP_ENV=development.
# Crea usuarios temporales reset_test_*@example.com y los elimina al final.
$ErrorActionPreference = "Continue"
$base = "http://localhost:5000"
$python = ".\venv\Scripts\python.exe"
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

function Check {
    param($Name, $Expected, $Actual, $Extra = "")
    if ($Expected -eq $Actual) { Write-Host "[OK] $Name -> $Actual $Extra" }
    else { Write-Host "[FALLO] $Name -> esperado $Expected, obtenido $Actual $Extra"; $script:fallos++ }
}

# ---------------------------------------------------------------------------
# Snapshot de datos operativos (verificacion 28: no se tocan)
# ---------------------------------------------------------------------------
$countsCode = @"
import sys
sys.path.insert(0, '.')
from app import create_app
from app.extensions import db
from sqlalchemy import text
app = create_app()
with app.app_context():
    for t in ('products', 'categories', 'stock_movements', 'delivery_notes', 'delivery_note_items'):
        n = db.session.execute(text(f'SELECT COUNT(*) FROM {t}')).scalar()
        print(f'{t}={n}')
"@
$before = (($countsCode | & $python -) | Where-Object { $_ -match '=' }) -join ';'

# ---------------------------------------------------------------------------
# SETUP: usuarios temporales de esta corrida
# ---------------------------------------------------------------------------
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$activeEmail = "reset_test_a$stamp@example.com"
$inactiveEmail = "reset_test_i$stamp@example.com"
$oldPassword = "clave-original-123"
$newPassword = "clave-nueva-456"

Write-Host "=== SETUP: usuarios temporales ==="
$r = Invoke-Page -Url "/api/auth/register" -Method POST -Body @{ name = "Reset Test Activo"; email = $activeEmail; username = "reset_a$stamp"; password = $oldPassword }
Check "setup-a. registro usuario activo" 201 $r.code
$r = Invoke-Page -Url "/api/auth/register" -Method POST -Body @{ name = "Reset Test Inactivo"; email = $inactiveEmail; username = "reset_i$stamp"; password = $oldPassword }
Check "setup-b. registro usuario inactivo" 201 $r.code

$deactivateCode = @"
import sys
sys.path.insert(0, '.')
from app import create_app
from app.extensions import db
from app.models import User
app = create_app()
with app.app_context():
    user = User.query.filter_by(email='$inactiveEmail').first()
    user.is_active = False
    db.session.commit()
    print('inactivo-ok')
"@
$out = ($deactivateCode | & $python -) | Select-Object -Last 1
Check "setup-c. usuario desactivado en BD" "inactivo-ok" $out

# ---------------------------------------------------------------------------
# SOLICITUD DE RECUPERACION (tests 1, 3, 4, 5)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== API: SOLICITUD DE RECUPERACION ==="
$r = Invoke-Page -Url "/api/auth/password-reset/request" -Method POST -Body @{ email = $activeEmail }
$data = $r.content | ConvertFrom-Json
Check "1a. email activo -> 200" 200 $r.code
Check "1b. respuesta neutra" $true ($data.message -like "Si el correo est*")
Check "3.  dev_reset_link presente en development" $true ($null -ne $data.dev_reset_link)

$r2 = Invoke-Page -Url "/api/auth/password-reset/request" -Method POST -Body @{ email = "no_existe_$stamp@example.com" }
$data2 = $r2.content | ConvertFrom-Json
Check "4a. email inexistente -> 200" 200 $r2.code
Check "4b. misma respuesta neutra, sin enlace" $true (($data2.message -eq $data.message) -and ($null -eq $data2.dev_reset_link))

$r3 = Invoke-Page -Url "/api/auth/password-reset/request" -Method POST -Body @{ email = $inactiveEmail }
$data3 = $r3.content | ConvertFrom-Json
Check "5.  usuario inactivo -> 200 neutro sin enlace" $true (($r3.code -eq 200) -and ($data3.message -eq $data.message) -and ($null -eq $data3.dev_reset_link))

$resetLink = [string]$data.dev_reset_link
$token = ($resetLink -split 'token=')[1]

# ---------------------------------------------------------------------------
# VALIDACIONES DE CONTRASENA (tests 12, 13) - no consumen el token
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== API: VALIDACIONES DE CONTRASENA ==="
$r = Invoke-Page -Url "/api/auth/password-reset/confirm" -Method POST -Body @{ token = $token; new_password = $newPassword; confirm_password = "otra-distinta" }
Check "12. contrasenas no coinciden -> 400" 400 $r.code
$r = Invoke-Page -Url "/api/auth/password-reset/confirm" -Method POST -Body @{ token = $token; new_password = "abc"; confirm_password = "abc" }
Check "13. contrasena corta -> 400" 400 $r.code

# ---------------------------------------------------------------------------
# CONFIRMACION Y LOGIN (tests 6, 7, 8, 9, 10)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== API: CONFIRMACION Y LOGIN ==="
$r = Invoke-Page -Url "/api/auth/password-reset/confirm" -Method POST -Body @{ token = $token; new_password = $newPassword; confirm_password = $newPassword }
Check "6a. token valido -> 200 cambia contrasena" 200 $r.code
Check "6b. respuesta no incluye password_hash" $true ($r.content -notlike "*password_hash*")

$s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$r = Invoke-Page -Url "/api/auth/login" -Method POST -Body @{ identifier = $activeEmail; password = $oldPassword } -Session $s
Check "7.  login con contrasena anterior -> 401" 401 $r.code

$s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$r = Invoke-Page -Url "/api/auth/login" -Method POST -Body @{ identifier = $activeEmail; password = $newPassword } -Session $s
Check "8.  login con contrasena nueva -> 200" 200 $r.code

$r = Invoke-Page -Url "/api/auth/password-reset/confirm" -Method POST -Body @{ token = $token; new_password = "otra-mas-789"; confirm_password = "otra-mas-789" }
Check "9.  reutilizar mismo token -> 401" 401 $r.code

$r = Invoke-Page -Url "/api/auth/password-reset/confirm" -Method POST -Body @{ token = "token-falso-123"; new_password = $newPassword; confirm_password = $newPassword }
Check "10. token falso -> 401" 401 $r.code

# ---------------------------------------------------------------------------
# TOKEN VENCIDO (test 11)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== API: TOKEN VENCIDO ==="
$r = Invoke-Page -Url "/api/auth/password-reset/request" -Method POST -Body @{ email = $activeEmail }
$token2 = ((($r.content | ConvertFrom-Json).dev_reset_link) -split 'token=')[1]
$expireCode = @"
import sys
sys.path.insert(0, '.')
from datetime import datetime, timedelta
from app import create_app
from app.extensions import db
from app.models import PasswordResetToken
app = create_app()
with app.app_context():
    PasswordResetToken.query.filter_by(email='$activeEmail').update(
        {PasswordResetToken.expires_at: datetime.utcnow() - timedelta(minutes=1)})
    db.session.commit()
    print('vencido-ok')
"@
$out = ($expireCode | & $python -) | Select-Object -Last 1
Check "11a. token forzado a vencido en BD" "vencido-ok" $out
$r = Invoke-Page -Url "/api/auth/password-reset/confirm" -Method POST -Body @{ token = $token2; new_password = "otra-mas-789"; confirm_password = "otra-mas-789" }
Check "11b. token vencido -> 401" 401 $r.code

# ---------------------------------------------------------------------------
# PAGINAS WEB (tests 14-20)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== PAGINAS WEB ==="
$r = Invoke-Page -Url "/forgot-password"
Check "14a. GET /forgot-password -> 200" 200 $r.code
Check "14b. contiene campo email y boton" $true (($r.content -like "*fp-email*") -and ($r.content -like "*Enviar enlace de recuperaci*"))
Check "14c. contiene caja dev_reset_link" $true ($r.content -like "*fp-dev-box*")
Check "14d. boton volver al login" $true ($r.content -like "*Volver al inicio de sesi*")

$r = Invoke-Page -Url "/login"
Check "15. /login contiene enlace a /forgot-password" $true ($r.content -like "*/forgot-password*")

$r = Invoke-Page -Url "/reset-password?token=cualquiera"
Check "16a. GET /reset-password?token=... -> 200" 200 $r.code
Check "16b. contiene campos de nueva contrasena" $true (($r.content -like "*rp-password*") -and ($r.content -like "*rp-confirm*"))
Check "16c. contiene alerta de error para token invalido" $true ($r.content -like "*rp-error*")
Check "16d. contiene boton ir al login" $true ($r.content -like "*Ir al login*")

$r = Invoke-Page -Url "/static/js/forgot_password.js"
Check "17. JS forgot_password.js servido" 200 $r.code
$r = Invoke-Page -Url "/static/js/reset_password.js"
Check "18. JS reset_password.js servido" 200 $r.code

# ---------------------------------------------------------------------------
# NO REGRESION /api (tests 26, 27)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== NO REGRESION /api ==="
$admin = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$r = Invoke-Page -Url "/api/auth/login" -Method POST -Body @{ identifier = "admin"; password = "admin123" } -Session $admin
Check "26a. login admin sigue OK y es JSON" $true (($r.code -eq 200) -and ($r.content.TrimStart().StartsWith("{")))
$r = Invoke-Page -Url "/api/auth/me" -Session $admin
Check "26b. /api/auth/me sigue JSON" $true (($r.code -eq 200) -and ($r.content.TrimStart().StartsWith("{")))
$r = Invoke-Page -Url "/api/products" -Session $admin
Check "26c. /api/products sigue JSON" $true (($r.code -eq 200) -and (($r.content.TrimStart().StartsWith("{")) -or ($r.content.TrimStart().StartsWith("["))))
$r = Invoke-Page -Url "/api/auth/passwordless/request" -Method POST -Body @{ email = $activeEmail }
$pwl = $r.content | ConvertFrom-Json
Check "26d. passwordless request sigue OK con dev_token" $true (($r.code -eq 200) -and ($null -ne $pwl.dev_token))
$r = Invoke-Page -Url "/api/auth/logout" -Method POST -Session $admin
Check "26e. logout sigue OK" 200 $r.code

# ---------------------------------------------------------------------------
# LIMPIEZA de usuarios temporales y verificacion de datos operativos
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== LIMPIEZA Y DATOS OPERATIVOS ==="
$cleanupCode = @"
import sys
sys.path.insert(0, '.')
from app import create_app
from app.extensions import db
from app.models import PasswordResetToken, PasswordlessToken, User
app = create_app()
with app.app_context():
    users = User.query.filter(User.email.like('reset_test_%@example.com')).all()
    for u in users:
        PasswordResetToken.query.filter_by(user_id=u.id).delete()
        PasswordlessToken.query.filter_by(user_id=u.id).delete()
        db.session.delete(u)
    db.session.commit()
    print(f'limpieza-ok:{len(users)}')
"@
$out = ($cleanupCode | & $python -) | Select-Object -Last 1
Check "limpieza. usuarios temporales eliminados" $true ($out -like "limpieza-ok:*")

$after = (($countsCode | & $python -) | Where-Object { $_ -match '=' }) -join ';'
Check "28. productos/stock/notas sin cambios" $before $after

Write-Host ""
if ($script:fallos -eq 0) { Write-Host "RESULTADO: TODAS LAS PRUEBAS PASARON" }
else { Write-Host "RESULTADO: $($script:fallos) PRUEBAS FALLARON" }
