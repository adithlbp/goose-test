#!/usr/bin/env bash
set -eu

##############################################################################
# Genius Assistant — instalador corporativo (macOS / Linux)
#
# Flujo no interactivo (prompt 08):
#   1. Instala el build corporativo (Desktop .app o CLI vía download_cli.sh).
#   2. Coloca la política adversary.md en el config dir del usuario.
#   3. Provisiona el API token vía ACP → Keychain (goose acp; el helper nunca
#      toca el Keychain). GATEADO por el invariante I5 (binario congelado): la
#      ACL del Keychain se ata al hash del binario, así que solo se provisiona
#      si el binario instalado ES el build bendecido — ver
#      docs/prompts/07_SECURITY_APIKEY.md y docs/SECRET_LIFECYCLE.md (I5).
#
# Variables (todas por entorno; NUNCA hardcodear el token en este archivo —
# lección "Genius Code"):
#   GENIUS_MODE           - desktop (default) | cli
#   GENIUS_REPO           - repo interno del fork (owner/name) [cli]
#   GENIUS_DESKTOP_URL    - URL del zip de la .app corporativa [desktop]
#   GENIUS_MODEL          - modelo del gateway [cli]
#   GENIUS_TOKEN          - token único por plataforma (canal seguro)
#   GENIUS_SECRET_KEY     - nombre del secreto (default: CUSTOM_GENIUS_API_KEY;
#                           usar OPENAI_API_KEY si el bundle no usa
#                           GOOSE_CUSTOM_PROVIDER)
#   GENIUS_ALLOW_UNVERIFIED - "true" para provisionar aunque el binario NO
#                           coincida con el hash bendecido (escape hatch: asume
#                           el riesgo de re-prompt del Keychain a conciencia)
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GENIUS_MODE="${GENIUS_MODE:-desktop}"
GENIUS_SECRET_KEY="${GENIUS_SECRET_KEY:-CUSTOM_GENIUS_API_KEY}"
GENIUS_ALLOW_UNVERIFIED="${GENIUS_ALLOW_UNVERIFIED:-false}"
GENIUS_TOKEN="${GENIUS_TOKEN:-}"

# --- 1) Instalar el build corporativo ---
case "$GENIUS_MODE" in
  desktop)
    if [[ "$OSTYPE" != darwin* ]]; then
      echo "[error] GENIUS_MODE=desktop solo soporta macOS en este script." >&2
      exit 1
    fi
    : "${GENIUS_DESKTOP_URL:?Set GENIUS_DESKTOP_URL to the internal .app zip URL}"
    APP_DIR="/Applications/Genius Assistant.app"
    TMP_ZIP="$(mktemp -t genius-assistant).zip"
    echo "Descargando Genius Assistant Desktop..."
    curl -fsSL "$GENIUS_DESKTOP_URL" -o "$TMP_ZIP"
    rm -rf "$APP_DIR"
    ditto -xk "$TMP_ZIP" "/Applications"
    rm -f "$TMP_ZIP"
    GOOSE_BIN="$APP_DIR/Contents/Resources/bin/goose"
    ;;
  cli)
    : "${GENIUS_REPO:?Set GENIUS_REPO to the internal fork repo (owner/name)}"
    CONFIGURE=false \
    GOOSE_REPO="$GENIUS_REPO" \
    GOOSE_PROVIDER=openai \
    GOOSE_MODEL="${GENIUS_MODEL:-}" \
      bash "$SCRIPT_DIR/../download_cli.sh"
    GOOSE_BIN="${GOOSE_BIN_DIR:-$HOME/.local/bin}/goose"
    ;;
  *)
    echo "[error] GENIUS_MODE inválido: '$GENIUS_MODE' (desktop|cli)" >&2
    exit 1
    ;;
esac

if [ ! -x "$GOOSE_BIN" ]; then
  echo "[error] No se encontró el binario goose instalado en: $GOOSE_BIN" >&2
  exit 1
fi

# --- 2) Política adversary.md ---
GOOSE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/goose"
mkdir -p "$GOOSE_CONFIG_DIR"
cp "$SCRIPT_DIR/adversary.md" "$GOOSE_CONFIG_DIR/adversary.md"
echo "adversary.md instalado en $GOOSE_CONFIG_DIR"

# --- 3) Provisionar el token (ACP → Keychain) ---
# Gate = invariante I5 (binario congelado), NO la firma: la ACL del Keychain se
# ata al hash del binario, así que solo provisionamos si el binario instalado es
# EXACTAMENTE un build bendecido (mismo hash → sin re-prompt en lecturas
# futuras). El binario que provisiona DEBE ser el mismo que luego lee
# (creador == consumidor de la ACL). build_corporate.sh genera un hash por
# arquitectura: frozen_goose_darwin_arm64.sha256 / _x64.sha256. El instalado
# debe coincidir con ALGUNO (así el mismo instalador sirve para arm64 e Intel).
provision_secret() {
  # El token viaja por stdin (nunca argv: invisible a ps/historial).
  printf '%s\n' "$GENIUS_TOKEN" | python3 "$SCRIPT_DIR/provision_secret.py" \
    --goose "$GOOSE_BIN" --key "$GENIUS_SECRET_KEY" --token-stdin
  echo "Secreto '$GENIUS_SECRET_KEY' provisionado vía ACP → Keychain."
}

ACTUAL_HASH="$(shasum -a 256 "$GOOSE_BIN" | cut -d' ' -f1)"
BLESSED_MATCH=false
BLESSED_ANY=false
for hf in "$SCRIPT_DIR"/frozen_goose_darwin_*.sha256; do
  [ -f "$hf" ] || continue
  BLESSED_ANY=true
  if [ "$ACTUAL_HASH" = "$(tr -d ' \n' < "$hf")" ]; then
    BLESSED_MATCH=true
    break
  fi
done

if [ -z "$GENIUS_TOKEN" ]; then
  echo "[aviso] GENIUS_TOKEN vacío — provisioning omitido."
elif [ "$BLESSED_MATCH" = "true" ]; then
  provision_secret
elif [ "$GENIUS_ALLOW_UNVERIFIED" = "true" ]; then
  echo "[aviso] binario NO coincide con ningún build bendecido, pero" >&2
  echo "  GENIUS_ALLOW_UNVERIFIED=true → provisionando de todos modos." >&2
  provision_secret
elif [ "$BLESSED_ANY" = "false" ]; then
  echo "[GATED] No hay hashes bendecidos (frozen_goose_darwin_*.sha256) junto al" >&2
  echo "  instalador → no se puede verificar el binario, provisioning omitido." >&2
  echo "  Genéralos con installer/build_corporate.sh (arm64/x64) y redistribúyelos," >&2
  echo "  o exporta GENIUS_ALLOW_UNVERIFIED=true para asumir el riesgo a conciencia." >&2
else
  echo "[GATED] El binario instalado NO coincide con ningún build bendecido (I5)." >&2
  echo "  actual: $ACTUAL_HASH" >&2
  echo "  Provisioning omitido para evitar re-prompts del Keychain / binario" >&2
  echo "  alterado. Si el cambio de binario es intencional, regenera el hash y" >&2
  echo "  aplica el reset del secreto (docs/SECRET_LIFECYCLE.md §9.2), o exporta" >&2
  echo "  GENIUS_ALLOW_UNVERIFIED=true." >&2
fi

echo "Instalación completada."
