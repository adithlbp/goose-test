# Genius Assistant — instalador corporativo (Windows)
#
# Flujo no interactivo (prompt 08):
#   1. Instala el build corporativo (Desktop o CLI vía download_cli.ps1).
#   2. Coloca la política adversary.md en %APPDATA%\Block\goose\config.
#   3. Provisiona el API token vía ACP → Credential Manager (goose acp).
#      SIN gate de firma: Credential Manager es por-usuario, NO tiene ACL
#      atada al hash del binario, así que un cambio de binario NO dispara
#      re-prompts (a diferencia del Keychain de macOS). La firma en Windows
#      solo evita SmartScreen — no es requisito para provisionar.
#
# Variables (entorno; NUNCA hardcodear el token — lección "Genius Code"):
#   GENIUS_MODE, GENIUS_REPO, GENIUS_DESKTOP_URL, GENIUS_MODEL,
#   GENIUS_TOKEN, GENIUS_SECRET_KEY
#   (mismo contrato que install_genius.sh)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Mode = if ($env:GENIUS_MODE) { $env:GENIUS_MODE } else { "desktop" }
$SecretKey = if ($env:GENIUS_SECRET_KEY) { $env:GENIUS_SECRET_KEY } else { "CUSTOM_GENIUS_API_KEY" }
$Token = $env:GENIUS_TOKEN

# --- 1) Instalar el build corporativo ---
switch ($Mode) {
  "desktop" {
    if (-not $env:GENIUS_DESKTOP_URL) { throw "Set GENIUS_DESKTOP_URL to the internal Desktop package URL" }
    $AppDir = Join-Path $env:LOCALAPPDATA "GeniusAssistant"
    $TmpZip = Join-Path $env:TEMP "genius-assistant.zip"
    Write-Host "Descargando Genius Assistant Desktop..."
    Invoke-WebRequest -Uri $env:GENIUS_DESKTOP_URL -OutFile $TmpZip
    if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
    Expand-Archive -Path $TmpZip -DestinationPath $AppDir
    Remove-Item -Force $TmpZip
    $GooseBin = Join-Path $AppDir "resources\bin\goose.exe"
  }
  "cli" {
    if (-not $env:GENIUS_REPO) { throw "Set GENIUS_REPO to the internal fork repo (owner/name)" }
    $env:CONFIGURE = "false"
    $env:GOOSE_REPO = $env:GENIUS_REPO
    $env:GOOSE_PROVIDER = "openai"
    if ($env:GENIUS_MODEL) { $env:GOOSE_MODEL = $env:GENIUS_MODEL }
    & (Join-Path $ScriptDir "..\download_cli.ps1")
    $BinDir = if ($env:GOOSE_BIN_DIR) { $env:GOOSE_BIN_DIR } else { Join-Path $env:USERPROFILE "goose" }
    $GooseBin = Join-Path $BinDir "goose.exe"
  }
  default { throw "GENIUS_MODE inválido: '$Mode' (desktop|cli)" }
}

if (-not (Test-Path $GooseBin)) { throw "No se encontró el binario goose instalado en: $GooseBin" }

# --- 2) Política adversary.md ---
$ConfigDir = Join-Path $env:APPDATA "Block\goose\config"
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
Copy-Item (Join-Path $ScriptDir "adversary.md") (Join-Path $ConfigDir "adversary.md") -Force
Write-Host "adversary.md instalado en $ConfigDir"

# --- 3) Provisionar el token (ACP → Credential Manager) ---
# Sin gate: CredMan es por-usuario (no por-binario) → provisionar es seguro
# aunque el binario cambie entre updates. El binario que provisiona es el mismo
# que luego lee (creador == consumidor).
if (-not $Token) {
  Write-Host "[aviso] GENIUS_TOKEN vacío — provisioning omitido."
}
else {
  # El token viaja por stdin (nunca argv: invisible al listado de procesos).
  $Token | python3 (Join-Path $ScriptDir "provision_secret.py") --goose $GooseBin --key $SecretKey --token-stdin
  Write-Host "Secreto '$SecretKey' provisionado vía ACP → Credential Manager."
}

Write-Host "Instalación completada."
