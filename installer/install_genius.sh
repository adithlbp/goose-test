#!/usr/bin/env bash
set -eu

##############################################################################
# Genius Assistant — instalador corporativo (macOS / Linux)
#
# NO requiere Python en la máquina del usuario: descifra el token con openssl
# (nativo en macOS) y lo provisiona manejando `goose acp` (JSON-RPC) por pipe.
#
# Flujo no interactivo:
#   1. Instala el build corporativo en ~/Applications (no requiere admin).
#   2. Coloca la política adversary.md en el config dir del usuario.
#   3. Provisiona el API token vía ACP → Keychain (el script nunca toca el
#      Keychain; lo hace goose). GATEADO por el invariante I5 (binario congelado).
#
# Variables (todas por entorno; NUNCA hardcodear el token — lección "Genius Code"):
#   GENIUS_MODE           - desktop (default) | cli
#   GENIUS_REPO           - repo interno del fork (owner/name) [cli]
#   GENIUS_DESKTOP_URL    - URL del zip de la .app corporativa [desktop]
#   GENIUS_DESKTOP_ZIP    - ruta a un zip local ya descargado (alternativa al URL)
#   GENIUS_MODEL          - modelo del gateway [cli]
#   GENIUS_TOKEN          - token en claro (SOLO pruebas; en producción viene en
#                           genius_token.enc, generado con embed_token.sh)
#   GENIUS_SECRET_KEY     - nombre del secreto (default: CUSTOM_GENIUS_API_KEY)
#   GENIUS_ALLOW_UNVERIFIED - "true" para provisionar aunque el binario NO
#                           coincida con el hash bendecido (asume el riesgo)
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
    # ~/Applications (del usuario): no requiere permisos de admin y evita el
    # "Operation not permitted" de /Applications en Macs corporativas.
    APPS_DIR="$HOME/Applications"
    APP_DIR="$APPS_DIR/Genius Assistant.app"
    if [ -n "${GENIUS_DESKTOP_ZIP:-}" ]; then
      SRC_ZIP="$GENIUS_DESKTOP_ZIP"
      CLEANUP_ZIP=false
      echo "Instalando desde archivo local: $SRC_ZIP"
    elif [ -n "${GENIUS_DESKTOP_URL:-}" ]; then
      SRC_ZIP="$(mktemp -t genius-assistant).zip"
      CLEANUP_ZIP=true
      echo "Descargando Genius Assistant Desktop..."
      curl -fsSL "$GENIUS_DESKTOP_URL" -o "$SRC_ZIP"
    else
      # Carpeta autocontenida: usar el zip que está junto a este script.
      SRC_ZIP="$(find "$SCRIPT_DIR" -maxdepth 1 -name 'Genius Assistant*.zip' | head -1)"
      if [ -z "$SRC_ZIP" ]; then
        echo "[error] no encontré el zip de la app junto al script, ni GENIUS_DESKTOP_URL/ZIP." >&2
        exit 1
      fi
      CLEANUP_ZIP=false
      echo "Instalando desde el zip local: $SRC_ZIP"
    fi
    mkdir -p "$APPS_DIR"
    rm -rf "$APP_DIR"
    ditto -xk "$SRC_ZIP" "$APPS_DIR"
    [ "$CLEANUP_ZIP" = "true" ] && rm -f "$SRC_ZIP"
    # App firmada adhoc: quitar la cuarentena de Gatekeeper (si el zip vino de
    # navegador/Drive/AirDrop) para que abra sin "desarrollador no identificado".
    xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
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

# --- 2b) Branding del system prompt (override en <config>/prompts/system.md) ---
# goose lee este override en runtime (prompt_template.rs) → el agente se identifica
# como "Genius Assistant" sin recompilar el binario congelado (I5). El override es
# un snapshot del system.md de v1.43.0; regenerarlo si el binario deja de estar
# congelado.
if [ -f "$SCRIPT_DIR/prompts/system.md" ]; then
  mkdir -p "$GOOSE_CONFIG_DIR/prompts"
  cp "$SCRIPT_DIR/prompts/system.md" "$GOOSE_CONFIG_DIR/prompts/system.md"
fi

# --- 3) Provisionar el token (ACP → Keychain), sin Python ---
# Gate = invariante I5 (binario congelado), NO la firma: la ACL del Keychain se
# ata al hash del binario → solo provisionamos si el binario instalado coincide
# con ALGÚN hash bendecido (frozen_goose_darwin_{arm64,x64}.sha256). El token
# viene "listo" en genius_token.enc (keyhex:ivhex:ct_b64, AES-256-CBC); se
# descifra con openssl y se pasa a goose por stdin (nunca argv/ps).
TOKEN_ENC="$SCRIPT_DIR/genius_token.enc"
token_available() { [ -n "$GENIUS_TOKEN" ] || [ -f "$TOKEN_ENC" ]; }

decode_token() {  # imprime el token; se captura en variable, nunca en argv
  if [ -n "$GENIUS_TOKEN" ]; then
    printf '%s' "$GENIUS_TOKEN"
    return 0
  fi
  local key iv ct
  IFS=: read -r key iv ct < "$TOKEN_ENC" || true
  printf '%s' "$ct" | openssl enc -aes-256-cbc -d -K "$key" -iv "$iv" -a -A
}

provision_secret() {
  local token esc init upsert fifo out gpid ok waited
  token="$(decode_token)"
  if [ -z "$token" ]; then
    echo "[error] no se pudo obtener el token (¿genius_token.enc corrupto?)." >&2
    return 1
  fi
  esc=${token//\\/\\\\}; esc=${esc//\"/\\\"}   # escape JSON
  init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"v1","clientCapabilities":{},"clientInfo":{"name":"corp-helper","version":"1.0.0"}}}'
  upsert="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"_goose/unstable/config/upsert\",\"params\":{\"key\":\"$GENIUS_SECRET_KEY\",\"value\":\"$esc\",\"isSecret\":true}}"
  # goose acp no cierra al recibir EOF → lo terminamos nosotros. NO usamos un
  # `sleep` ciego: en el primer arranque el binario recién extraído tarda
  # (Gatekeeper) y el Llavero puede pedir la contraseña; matar a los 2s abortaba
  # la escritura → secreto vacío → 401. Esperamos la RESPUESTA del upsert
  # (hasta ~60s, dando tiempo a aprobar el Llavero) y confirmamos que se guardó.
  out="$(mktemp)"; fifo="$(mktemp -u)"; mkfifo "$fifo"
  "$GOOSE_BIN" acp <"$fifo" >"$out" 2>/dev/null &
  gpid=$!
  exec 3>"$fifo"                                   # mantener stdin abierto mientras esperamos
  printf '%s\n%s\n' "$init" "$upsert" >&3
  ok=false; waited=0
  while [ "$waited" -lt 120 ]; do
    if grep -q '"id":2' "$out" 2>/dev/null; then
      grep -q '"id":2,"result"' "$out" 2>/dev/null && ok=true
      break
    fi
    kill -0 "$gpid" 2>/dev/null || break
    sleep 0.5; waited=$((waited + 1))
  done
  exec 3>&-
  kill "$gpid" 2>/dev/null || true
  wait "$gpid" 2>/dev/null || true
  rm -f "$fifo" "$out"
  if [ "$ok" = true ]; then
    echo "  ✓ token provisionado en el Llavero."
  else
    echo "[error] el token NO quedó guardado (timeout, o se denegó el Llavero)." >&2
    echo "  Vuelve a correr el instalador y dale 'Permitir' cuando pida la contraseña." >&2
    return 1
  fi
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

if ! token_available; then
  echo "[aviso] sin token (ni GENIUS_TOKEN ni genius_token.enc) — provisioning omitido."
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

echo "Instalación completada. Abre 'Genius Assistant' desde ~/Applications (Launchpad)."
