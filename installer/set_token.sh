#!/usr/bin/env bash
set -eu
##############################################################################
# Regenera genius_token.enc con el token de la aplicación Genius Assistant.
#
# Pide el token de forma interactiva y OCULTA (no se muestra al teclear, no
# queda en el historial del shell ni en `ps`). Envuelve a embed_token.sh, que
# es quien ofusca (AES-256-CBC) y escribe el archivo.
#
# Uso:  bash installer/set_token.sh
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf 'Pega el token de la app Genius Assistant y presiona Enter\n'
printf '(no se mostrará en pantalla): '

stty -echo 2>/dev/null || true
IFS= read -r TOKEN || true
stty echo 2>/dev/null || true
printf '\n'

if [ -z "${TOKEN:-}" ]; then
  echo "[error] no se recibió ningún token." >&2
  exit 1
fi

printf '%s\n' "$TOKEN" | bash "$SCRIPT_DIR/embed_token.sh"
unset TOKEN

echo
echo "Huella del token recién embebido (para comparar, sin exponerlo):"
bash "$SCRIPT_DIR/verificar_token.sh" 2>/dev/null | sed -n '1,6p' || true
echo
echo "Siguiente paso: reinstala para que el Llavero tome el token nuevo:"
echo "  cd dist-testers/macOS-AppleSilicon && bash install_genius.sh"
