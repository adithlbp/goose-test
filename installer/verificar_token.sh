#!/usr/bin/env bash
set -eu
##############################################################################
# Diagnóstico: ¿qué token está usando Genius Assistant?
#
# NO imprime ningún token completo. Solo muestra:
#   - el valor ENMASCARADO que guarda el Llavero (lo enmascara el propio goose)
#   - una HUELLA (prefijo + sha256) del token embebido en genius_token.enc
# para poder compararlos e identificar cuál es cuál.
#
# Uso:  bash installer/verificar_token.sh
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${GENIUS_SECRET_KEY:-CUSTOM_GENIUS_API_KEY}"
APP_BIN="${GENIUS_APP_BIN:-$HOME/Applications/Genius Assistant.app/Contents/Resources/bin/goose}"
TOKEN_ENC="${1:-$SCRIPT_DIR/genius_token.enc}"

huella() {  # $1 = token en claro (llega por stdin del caller, nunca se imprime)
  local t="$1"
  printf '  longitud : %s caracteres\n' "${#t}"
  printf '  prefijo  : %s…\n' "${t:0:6}"
  printf '  sha256   : %s…\n' "$(printf '%s' "$t" | shasum -a 256 | cut -c1-16)"
}

echo "== 1) Token embebido en el instalador (genius_token.enc) =="
if [ -f "$TOKEN_ENC" ]; then
  IFS=: read -r k iv ct < "$TOKEN_ENC"
  tok="$(printf '%s' "$ct" | openssl enc -aes-256-cbc -d -K "$k" -iv "$iv" -a -A 2>/dev/null || true)"
  if [ -n "$tok" ]; then huella "$tok"; else echo "  [error] no se pudo descifrar"; fi
  unset tok
else
  echo "  (no existe $TOKEN_ENC)"
fi

echo
echo "== 2) Token que la app instalada tiene en el Llavero =="
if [ ! -x "$APP_BIN" ]; then
  echo "  [error] no encuentro el binario instalado: $APP_BIN"
  exit 1
fi
echo "  (si macOS pide la contraseña del Llavero, dale Permitir)"

# goose acp NO cierra con EOF: se maneja por FIFO y se termina explícitamente,
# igual que en install_genius.sh. Un pipeline simple se cuelga aquí.
init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}'
read_req="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"_goose/unstable/config/read\",\"params\":{\"key\":\"$KEY\",\"isSecret\":true}}"
defaults='{"jsonrpc":"2.0","id":3,"method":"_goose/unstable/defaults/read","params":{}}'

out="$(mktemp)"; fifo="$(mktemp -u)"; mkfifo "$fifo"
"$APP_BIN" acp <"$fifo" >"$out" 2>/dev/null &
gpid=$!
exec 3>"$fifo"
printf '%s\n%s\n%s\n' "$init" "$read_req" "$defaults" >&3
waited=0
# Esperar la respuesta del SECRETO (id 2): es la lenta, porque puede disparar
# el diálogo del Llavero. defaults/read (id 3) contesta al instante y si se
# cortara ahí se mataría el proceso antes de que el Llavero responda.
while [ "$waited" -lt 120 ]; do
  grep -q '"id":2' "$out" 2>/dev/null && break
  kill -0 "$gpid" 2>/dev/null || break
  sleep 0.5; waited=$((waited + 1))
done
exec 3>&-
kill "$gpid" 2>/dev/null || true
wait "$gpid" 2>/dev/null || true

masked="$(sed -n 's/.*"id":2,"result":{"value":\("[^"]*"\|null\)}.*/\1/p' "$out" | head -1)"
active="$(sed -n 's/.*"id":3,"result":\({[^}]*}\).*/\1/p' "$out" | head -1)"
if [ -n "$masked" ]; then
  echo "  valor en Llavero (enmascarado): $masked"
else
  echo "  [aviso] no hubo respuesta (¿se denegó el Llavero, o el binario no es el que creó el secreto?)"
  grep -o '"error":{[^}]*}' "$out" 2>/dev/null | head -1 | sed 's/^/  /'
fi
[ -n "$active" ] && echo "  provider/modelo activos       : $active"
rm -f "$fifo" "$out"

echo
echo "Compara el prefijo de (1) con el enmascarado de (2):"
echo "  - iguales  -> la app usa el token embebido en el instalador"
echo "  - distintos-> el Llavero tiene otro token (p.ej. uno provisionado a mano)"
