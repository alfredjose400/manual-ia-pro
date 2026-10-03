# Sube los cambios de MANUAL IA (manual-ia-pro) a GitHub.
# Uso: doble clic en "actualizar_github.bat"  (o en PowerShell:  .\actualizar_github.ps1 "Mensaje del cambio")
param([string]$mensaje = "Actualización de MANUAL IA")
# Git escribe su avance por el canal de errores: no debe detener el script.
$ErrorActionPreference = "Continue"
$repoUrl = "https://github.com/alfredjose400/manual-ia-pro.git"
$origen = $PSScriptRoot

function Salir($texto, $color) {
    Write-Host ""
    Write-Host $texto -ForegroundColor $color
    Write-Host ""
    Read-Host "Presiona Enter para cerrar"
    exit
}

function Invoke-Git([string[]]$argumentos) {
    & git.exe @argumentos 2>&1 | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Salir "Falta instalar Git: https://git-scm.com/download/win  (luego cierra y vuelve a abrir)" Red
}
if (-not (git.exe config --global user.name)) { git.exe config --global user.name (Read-Host "Tu nombre para GitHub") }
if (-not (git.exe config --global user.email)) { git.exe config --global user.email (Read-Host "Tu correo de GitHub") }

if (Test-Path (Join-Path $origen ".git")) {
    # Esta carpeta ya es el repositorio
    $repo = $origen
    Set-Location $repo
    Write-Host "1/3 Trayendo lo último de GitHub..." -ForegroundColor Cyan
    if ((Invoke-Git @("pull", "--rebase", "origin", "main")) -ne 0) { Salir "No se pudo traer lo último de GitHub." Red }
} else {
    # Carpeta descomprimida de un zip: se descarga el repositorio y se copian los archivos encima
    $repo = Join-Path $env:TEMP "manual-ia-pro-repo"
    if (Test-Path $repo) { Remove-Item -Recurse -Force $repo }
    Write-Host "1/3 Descargando el repositorio de GitHub (si se abre el navegador, autoriza GitHub)..." -ForegroundColor Cyan
    if ((Invoke-Git @("clone", $repoUrl, $repo)) -ne 0) {
        # Suele pasar cuando Windows guardó un acceso viejo (u otra cuenta) de GitHub: se borra y se pide iniciar sesión de nuevo.
        Write-Host ""
        Write-Host "GitHub no reconoció tu cuenta. Borrando el acceso guardado y pidiendo iniciar sesión de nuevo..." -ForegroundColor Yellow
        "protocol=https`nhost=github.com`n`n" | git.exe credential reject
        cmdkey /delete:git:https://github.com 2>&1 | Out-Null
        if (Test-Path $repo) { Remove-Item -Recurse -Force $repo }
        Write-Host "Se abrirá una ventana de GitHub: inicia sesión con la cuenta alfredjose400 y pulsa Authorize." -ForegroundColor Cyan
        if ((Invoke-Git @("clone", $repoUrl, $repo)) -ne 0) {
            Salir "No se pudo descargar el repositorio. Asegúrate de iniciar sesión con la cuenta alfredjose400 (dueña del repositorio)." Red
        }
    }
    Write-Host "2/3 Copiando los archivos nuevos..." -ForegroundColor Cyan
    robocopy $origen $repo /E /XD .git /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Salir "Error al copiar los archivos." Red }
    Set-Location $repo
}

Invoke-Git @("add", "-A") | Out-Null
if (-not (git.exe status --porcelain)) { Salir "No hay cambios para subir: GitHub ya está al día." Green }

Write-Host "3/3 Subiendo a GitHub..." -ForegroundColor Cyan
Invoke-Git @("commit", "-m", $mensaje) | Out-Null
# Rama principal "main" (también en un repositorio nuevo y vacío)
Invoke-Git @("branch", "-M", "main") | Out-Null
if ((Invoke-Git @("push", "origin", "main")) -ne 0) { Salir "No se pudo subir. Revisa el mensaje de arriba." Red }

Salir "Listo: cambios subidos. Los APK se crean en GitHub > Actions y aparecen en Releases en unos 10 minutos." Green
