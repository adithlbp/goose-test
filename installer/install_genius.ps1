# Genius Assistant — instalador corporativo (Windows)
#
# NO requiere Python: descifra el token con .NET (AES) y lo provisiona manejando
# `goose acp` (JSON-RPC) por stdin. Todo nativo de PowerShell.
#
# Flujo no interactivo:
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
    $AppDir = Join-Path $env:LOCALAPPDATA "GeniusAssistant"
    # Fuente del zip: archivo local (GENIUS_DESKTOP_ZIP, p.ej. bajado de Drive a
    # mano) o descarga por URL (GENIUS_DESKTOP_URL).
    if ($env:GENIUS_DESKTOP_ZIP) {
      $SrcZip = $env:GENIUS_DESKTOP_ZIP
      $CleanupZip = $false
      Write-Host "Instalando desde archivo local: $SrcZip"
    }
    elseif ($env:GENIUS_DESKTOP_URL) {
      $SrcZip = Join-Path $env:TEMP "genius-assistant.zip"
      $CleanupZip = $true
      Write-Host "Descargando Genius Assistant Desktop..."
      Invoke-WebRequest -Uri $env:GENIUS_DESKTOP_URL -OutFile $SrcZip
    }
    else {
      # Carpeta autocontenida: usar el zip que está junto a este script.
      $localZip = Get-ChildItem -Path $ScriptDir -Filter "GeniusAssistant*.zip" -File | Select-Object -First 1
      if (-not $localZip) { throw "No encontré el zip de la app junto al script, ni GENIUS_DESKTOP_URL/ZIP" }
      $SrcZip = $localZip.FullName
      $CleanupZip = $false
      Write-Host "Instalando desde el zip local: $SrcZip"
    }
    if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
    Expand-Archive -Path $SrcZip -DestinationPath $AppDir
    if ($CleanupZip) { Remove-Item -Force $SrcZip }
    # Quitar Mark-of-the-Web (evita SmartScreen si el zip vino de navegador/Drive).
    Get-ChildItem -Recurse $AppDir | Unblock-File -ErrorAction SilentlyContinue
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

# Branding del system prompt: override en <config>\prompts\system.md que goose lee
# en runtime → el agente se identifica como "Genius Assistant" sin recompilar el
# binario (snapshot del system.md de v1.43.0).
$PromptSrc = Join-Path $ScriptDir "prompts\system.md"
if (Test-Path $PromptSrc) {
  $PromptsDir = Join-Path $ConfigDir "prompts"
  New-Item -ItemType Directory -Force -Path $PromptsDir | Out-Null
  Copy-Item $PromptSrc (Join-Path $PromptsDir "system.md") -Force
}

# --- 3) Provisionar el token (ACP → Credential Manager), sin Python ---
# CredMan es por-usuario (no por-binario) → provisionar es seguro aunque el
# binario cambie. El token viene "listo" en genius_token.enc (keyhex:ivhex:ct_b64,
# AES-256-CBC); se descifra con .NET y se pasa a goose por stdin (nunca argv).
$TokenEnc = Join-Path $ScriptDir "genius_token.enc"

function ConvertFrom-HexString([string]$h) {
  $bytes = New-Object byte[] ($h.Length / 2)
  for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
  return ,$bytes
}

function Get-GeniusToken {
  if ($Token) { return $Token }
  $blob = (Get-Content -Raw $TokenEnc).Trim()
  $parts = $blob.Split(":")
  $aes = [System.Security.Cryptography.Aes]::Create()
  $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
  $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
  $aes.Key = ConvertFrom-HexString $parts[0]
  $aes.IV = ConvertFrom-HexString $parts[1]
  $ct = [Convert]::FromBase64String($parts[2])
  $plain = $aes.CreateDecryptor().TransformFinalBlock($ct, 0, $ct.Length)
  return [System.Text.Encoding]::UTF8.GetString($plain)
}

function Invoke-Provision([string]$tokenValue) {
  $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"v1","clientCapabilities":{},"clientInfo":{"name":"corp-helper","version":"1.0.0"}}}'
  $upsert = @{ jsonrpc = "2.0"; id = 2; method = "_goose/unstable/config/upsert";
               params = @{ key = $SecretKey; value = $tokenValue; isSecret = $true } } | ConvertTo-Json -Compress
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $GooseBin
  $psi.Arguments = "acp"
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  # goose acp no cierra al recibir EOF → lo terminamos nosotros. En lugar de un
  # sleep ciego (que abortaba la escritura si el binario recién extraído tardaba
  # en arrancar → secreto vacío → 401), esperamos la RESPUESTA del upsert.
  $p.StandardInput.WriteLine($init)
  $p.StandardInput.WriteLine($upsert)
  $ok = $false
  $deadline = (Get-Date).AddSeconds(60)
  while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
    $line = $p.StandardOutput.ReadLine()
    if ($null -eq $line) { break }
    if ($line -match '"id":2') {
      if ($line -match '"id":2,"result"') { $ok = $true }
      break
    }
  }
  $p.StandardInput.Close()
  if (-not $p.HasExited) { $p.Kill() }
  if ($ok) { Write-Host "  token provisionado en Credential Manager." }
  else { Write-Warning "  el token NO quedo guardado; vuelve a correr el instalador." }
}

if (-not $Token -and -not (Test-Path $TokenEnc)) {
  Write-Host "[aviso] sin token (ni GENIUS_TOKEN ni genius_token.enc) — provisioning omitido."
}
else {
  Invoke-Provision (Get-GeniusToken)
}

Write-Host "Instalación completada. Abre Genius Assistant desde el menú Inicio."
