#!/usr/bin/env bash
set -eu

##############################################################################
# Embebe el token corporativo, OFUSCADO (AES-256-CBC), en genius_token.enc.
# Lo corre el DUEÑO del token, una vez, al armar el instalable. Solo usa openssl
# (nativo en macOS) — no requiere Python.
#
# Formato del blob:  keyhex:ivhex:ciphertext_base64
# La clave/IV aleatorios van embebidos en el blob → esto es OFUSCACIÓN, no
# cifrado fuerte (un insider con el archivo puede recuperar el token). Riesgo
# aceptado del piloto: token único por-plataforma, monitoreado y revocable.
# Ver docs/SECRET_LIFECYCLE.md §2.1.
#
# Uso (el token entra por stdin, jamás por argv/ps):
#   read -rs GENIUS_TOKEN
#   printf '%s\n' "$GENIUS_TOKEN" | bash installer/embed_token.sh
#   unset GENIUS_TOKEN
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$SCRIPT_DIR/genius_token.enc}"

IFS= read -r TOKEN || true
if [ -z "${TOKEN:-}" ]; then
  echo "!!! no llegó ningún token por stdin" >&2
  exit 1
fi

KEY="$(openssl rand -hex 32)"
IV="$(openssl rand -hex 16)"
CT="$(printf '%s' "$TOKEN" | openssl enc -aes-256-cbc -K "$KEY" -iv "$IV" -a -A)"
printf '%s:%s:%s\n' "$KEY" "$IV" "$CT" > "$OUT"
chmod 600 "$OUT"

echo "Token ofuscado escrito en $OUT"
echo "Distribúyelo junto a install_genius.sh/.ps1. NO lo subas al repo."
