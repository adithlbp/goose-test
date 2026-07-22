#!/usr/bin/env bash
set -eu

##############################################################################
# Genius Assistant — build corporativo para WINDOWS (x86_64, ZIP portable).
#
# CORRE EN WINDOWS, dentro de Git Bash. Replica el job de CI
# (.github/workflows/bundle-desktop-genius-windows.yml) como script local, por
# si prefieres que alguien con Windows lo genere a mano en vez de usar Actions.
#
# NO lleva secretos: el token se provisiona por-máquina al instalar
# (install_genius.ps1), no se hornea. Por eso es seguro compartir el repo.
#
# En Windows NO se congela el binario (a diferencia de I5 en macOS): Credential
# Manager es por-usuario y no ata ACL al hash → goose.exe se compila fresco.
#
# Requisitos (instalar una vez):
#   - Rust (rustup) con toolchain MSVC  → https://rustup.rs
#       + Visual Studio Build Tools (C++), que rustup pide al instalar
#   - Node.js 24.x  y  pnpm 10.x        (npm install -g pnpm@10.30.3)
#   - Git (trae Git Bash)  y  7-Zip (7z en el PATH)
#   (El instalador install_genius.ps1 NO requiere Python: descifra con .NET.)
#
# Uso (en Git Bash, desde cualquier carpeta):
#   bash /ruta/al/repo/installer/build_corporate_windows.sh
# Resultado:
#   ui/desktop/out/GeniusAssistant-win32-x64.zip   (súbelo a GENIUS_DESKTOP_URL)
##############################################################################

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- 1) Compilar el backend goose.exe (MSVC) ---
echo "[1/4] Compilando goose.exe (x86_64-pc-windows-msvc)..."
rustup target add x86_64-pc-windows-msvc
cd "$REPO_ROOT"
cargo build --release --target x86_64-pc-windows-msvc -p goose-cli --bin goose
BACKEND="$REPO_ROOT/target/x86_64-pc-windows-msvc/release/goose.exe"
if [ ! -f "$BACKEND" ]; then
  echo "[error] no se generó $BACKEND" >&2
  exit 1
fi

# --- 2) Stage: colocar goose.exe + scripts de plataforma en el slot de build ---
echo "[2/4] Preparando ui/desktop/src/bin..."
rm -rf "$REPO_ROOT/ui/desktop/src/bin"
mkdir -p "$REPO_ROOT/ui/desktop/src/bin"
cp -f "$BACKEND" "$REPO_ROOT/ui/desktop/src/bin/goose.exe"
if [ -d "$REPO_ROOT/ui/desktop/src/platform/windows/bin" ]; then
  for f in "$REPO_ROOT"/ui/desktop/src/platform/windows/bin/*; do
    bn="$(basename "$f")"
    [ "$bn" = "goose.exe" ] && continue
    [ "$bn" = "README.md" ] && continue
    cp -rf "$f" "$REPO_ROOT/ui/desktop/src/bin/"
  done
fi

# --- 3) Política corporativa horneada + empaquetado win32 ---
echo "[3/4] Empaquetando Electron (win32) con la política corporativa..."
# Forzar HTTPS para dependencias git de npm (evita fallos de SSH en una máquina
# recién configurada, igual que hace el workflow de CI).
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
git config --global url."https://github.com/".insteadOf "git@github.com:"
git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/"
# shellcheck source=corporate_env.sh
. "$REPO_ROOT/installer/corporate_env.sh"
export ELECTRON_PLATFORM=win32
cd "$REPO_ROOT/ui/desktop"
pnpm install --frozen-lockfile
node scripts/build-main.js
node scripts/prepare-platform-binaries.js
pnpm run make --platform=win32 --arch=x64

# --- 4) Distribución plana + ZIP (contenido en la raíz para install_genius.ps1) ---
echo "[4/4] Armando el ZIP portable..."
APP_DIR="out/Genius Assistant-win32-x64"
mkdir -p "$APP_DIR/resources/bin"
cp -rf src/bin/* "$APP_DIR/resources/bin/"
rm -rf dist-windows && mkdir -p dist-windows
cp -rf "$APP_DIR"/* dist-windows/
rm -f "out/GeniusAssistant-win32-x64.zip"
( cd dist-windows && 7z a -tzip "../out/GeniusAssistant-win32-x64.zip" . >/dev/null )

echo ""
echo "Listo: $REPO_ROOT/ui/desktop/out/GeniusAssistant-win32-x64.zip"
echo "El ZIP tiene 'Genius Assistant.exe' + 'resources/bin/goose.exe' en la raíz."
echo "Súbelo al canal interno y apunta GENIUS_DESKTOP_URL (Windows) a esa URL."
