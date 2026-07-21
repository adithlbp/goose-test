#!/usr/bin/env bash
set -eu

##############################################################################
# Genius Assistant — receta de build corporativo (PoC)
#
# Uso: build_corporate.sh [arm64|x64]        (default: arm64)
#
# Hornea el provider fijo + políticas en el bundle de Electron y empaqueta para
# la arquitectura macOS indicada. Ver docs/POC_DESIGN.md y SECRET_LIFECYCLE.md.
#
# Requisito PoC (I5): el binario goose está CONGELADO — se archiva una vez en
# installer/frozen/goose-<triple> y se reutiliza; NO se recompila por build (los
# prompts/cuelgues del Keychain se disparan si cambia el hash del binario).
##############################################################################

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-arm64}"

case "$ARCH" in
  arm64) TRIPLE="aarch64-apple-darwin"; BUNDLE_SCRIPT="bundle:default"; OUT_SUBDIR="darwin-arm64" ;;
  x64)   TRIPLE="x86_64-apple-darwin";  BUNDLE_SCRIPT="bundle:intel";   OUT_SUBDIR="darwin-x64"   ;;
  *) echo "uso: $(basename "$0") [arm64|x64]" >&2; exit 1 ;;
esac

FROZEN_BIN="$REPO_ROOT/installer/frozen/goose-$TRIPLE"
FROZEN_SHA_FILE="$FROZEN_BIN.sha256"
GOOSE_BIN="$REPO_ROOT/ui/desktop/src/bin/goose"

# --- Invariante I5: el binario congelado archivado debe existir e íntegro ---
if [ ! -f "$FROZEN_BIN" ] || [ ! -f "$FROZEN_SHA_FILE" ]; then
  echo "[error] falta el binario congelado o su hash para $ARCH:" >&2
  echo "  $FROZEN_BIN(.sha256)" >&2
  echo "  Restáuralo desde la release v1.43.0 (goose-$TRIPLE.tar.bz2)." >&2
  exit 1
fi
EXPECTED_SHA256="$(tr -d ' \n' < "$FROZEN_SHA_FILE")"
ACTUAL_SHA256="$(shasum -a 256 "$FROZEN_BIN" | cut -d' ' -f1)"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "[error] I5 violado: el binario congelado $ARCH no coincide con su hash." >&2
  echo "  esperado: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  exit 1
fi
echo "I5 OK ($ARCH): binario congelado íntegro ($ACTUAL_SHA256)"

# --- Stage: colocar el binario del arch correcto en el slot de build ---
cp "$FROZEN_BIN" "$GOOSE_BIN"

# --- Política corporativa (fuente única, compartida con el CI de Windows) ---
# shellcheck source=corporate_env.sh
. "$REPO_ROOT/installer/corporate_env.sh"

# --- Empaquetar (zip listo para GENIUS_DESKTOP_URL) ---
cd "$REPO_ROOT/ui/desktop"
pnpm run "$BUNDLE_SCRIPT"

# --- Registrar el hash del binario YA EMPAQUETADO para el instalador ---
# install_genius.sh verifica este hash (invariante I5) antes de provisionar el
# secreto: la ACL del Keychain se ata al hash, así que solo debe provisionarse
# para el build bendecido. Se recomputa desde el .app porque el empaquetado
# puede re-firmar (adhoc) el binario y cambiar su hash respecto al de src/bin.
SHIPPED_GOOSE="$REPO_ROOT/ui/desktop/out/${GOOSE_BUNDLE_NAME}-${OUT_SUBDIR}/${GOOSE_BUNDLE_NAME}.app/Contents/Resources/bin/goose"
HASH_FILE="$REPO_ROOT/installer/frozen_goose_darwin_${ARCH}.sha256"
if [ -f "$SHIPPED_GOOSE" ]; then
  shasum -a 256 "$SHIPPED_GOOSE" | cut -d' ' -f1 > "$HASH_FILE"
  echo "Hash del binario empaquetado ($ARCH) → installer/frozen_goose_darwin_${ARCH}.sha256 ($(cat "$HASH_FILE"))"
else
  echo "[aviso] no se encontró el binario empaquetado en:" >&2
  echo "  $SHIPPED_GOOSE" >&2
  echo "  install_genius.sh no podrá verificar el binario — revisa el bundle." >&2
fi

echo ""
echo "Bundle $ARCH listo en ui/desktop/out/${GOOSE_BUNDLE_NAME}-${OUT_SUBDIR}/."
echo "Publica el .zip en el canal interno y apunta GENIUS_DESKTOP_URL a ese zip."
