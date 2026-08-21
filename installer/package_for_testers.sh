#!/usr/bin/env bash
set -eu

##############################################################################
# Arma carpetas AUTOCONTENIDAS por SO para que los testers instalen con un solo
# comando. Cada carpeta lleva TODO lo necesario (app + scripts + token) → el
# tester descarga su carpeta de Drive, la descomprime y corre `bash install_genius.sh`.
#
# Requisito: haber generado installer/genius_token.enc (embed_token.sh).
# Salida: dist-testers/<SO>/  y  dist-testers/<SO>.zip
##############################################################################

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INST="$REPO_ROOT/installer"
OUT="$REPO_ROOT/dist-testers"

if [ ! -f "$INST/genius_token.enc" ]; then
  echo "[error] falta $INST/genius_token.enc" >&2
  echo "  Genéralo con: printf '%s\\n' \"\$TOKEN\" | bash installer/embed_token.sh" >&2
  exit 1
fi

COMMON=(adversary.md genius_token.enc)
ARM_ZIP="$REPO_ROOT/ui/desktop/out/Genius Assistant-darwin-arm64/Genius Assistant.zip"
X64_ZIP="$REPO_ROOT/ui/desktop/out/Genius Assistant-darwin-x64/Genius Assistant_intel_mac.zip"
WIN_ZIP="$REPO_ROOT/ui/desktop/out/GeniusAssistant-win32-x64.zip"

rm -rf "$OUT"; mkdir -p "$OUT"

readme_macos() {
  cat > "$1/README.md" <<'EOF'
# Genius Assistant — Instalación (macOS)

> ⚠️ **Versión de prueba (piloto interno).** Esta build **todavía no está firmada**
> digitalmente — por eso macOS mostrará avisos de seguridad y pedirá la contraseña del
> Llavero. Es **esperado** en esta fase; se resuelve cuando la app esté firmada.

> 🔄 **¿Ya tenías Genius Assistant instalada?** No borres nada: el instalador
> reemplaza la versión anterior y conserva tu configuración. Solo **cierra la app**
> si la tienes abierta (el instalador intentará cerrarla por ti).

1. Descomprime esta carpeta (doble clic en el `.zip`).
2. Abre la app **Terminal**.
3. Escribe `cd ` (con un espacio) y **arrastra esta carpeta** a la ventana; presiona **Enter**.
4. Escribe y presiona **Enter**:
   ```
   bash install_genius.sh
   ```
5. Abre **Genius Assistant** desde Launchpad / Aplicaciones.

> 🔑 **Contraseña del Llavero (es normal, estamos en fase de pruebas):** macOS te
> pedirá la **contraseña de tu Mac** para leer la configuración de forma segura del
> Llavero. **Escríbela y dale "Permitir" — NUNCA "Denegar".** En esta fase puede
> pedírtela varias veces (al abrir y al cambiar de modelo); es esperado. ⚠️ Si le das
> "Denegar", la app **no podrá cargar la lista de modelos**. Se quita del todo cuando
> la app esté firmada.

Si macOS bloquea la app la primera vez: clic derecho en la app → **Abrir** → **Abrir**.
EOF
}

pack_macos() {  # $1=carpeta destino  $2=zip de la app  $3=sha256 file
  local d="$1"
  mkdir -p "$d"
  cp "$2" "$d/"
  cp "$INST/install_genius.sh" "$d/"
  cp "$INST/$3" "$d/"
  for f in "${COMMON[@]}"; do cp "$INST/$f" "$d/"; done
  [ -d "$INST/prompts" ] && cp -R "$INST/prompts" "$d/"
  readme_macos "$d"
}

if [ -f "$ARM_ZIP" ]; then
  pack_macos "$OUT/macOS-AppleSilicon" "$ARM_ZIP" "frozen_goose_darwin_arm64.sha256"
  echo "✓ macOS Apple Silicon"
else
  echo "· (falta el build arm64: installer/build_corporate.sh arm64)"
fi

if [ -f "$X64_ZIP" ]; then
  pack_macos "$OUT/macOS-Intel" "$X64_ZIP" "frozen_goose_darwin_x64.sha256"
  echo "✓ macOS Intel"
else
  echo "· (falta el build Intel: installer/build_corporate.sh x64)"
fi

if [ -f "$WIN_ZIP" ]; then
  d="$OUT/Windows"; mkdir -p "$d"
  cp "$WIN_ZIP" "$d/"
  cp "$INST/_genius-setup.ps1" "$d/"
  cp "$INST/install.cmd" "$d/"
  for f in "${COMMON[@]}"; do cp "$INST/$f" "$d/"; done
  [ -d "$INST/prompts" ] && cp -R "$INST/prompts" "$d/"
  cat > "$d/README.md" <<'EOF'
# Genius Assistant — Instalación (Windows)

> ⚠️ **Versión de prueba (piloto interno).** Esta build **todavía no está firmada**
> digitalmente — por eso Windows puede mostrar un aviso de **SmartScreen** (*Más
> información → Ejecutar de todas formas*). Es **esperado** en esta fase; se resuelve
> cuando la app esté firmada.

> 🔄 **¿Ya tenías Genius Assistant instalada?** No borres nada: el instalador
> reemplaza la versión anterior y conserva tu configuración. Solo **cierra la app**
> si la tienes abierta (el instalador intentará cerrarla por ti).

1. Descomprime esta carpeta (clic derecho → **Extraer todo**).
2. **Doble clic en `install.cmd`.** (Si Windows muestra un aviso de SmartScreen:
   *Más información → Ejecutar de todas formas*.)
3. Espera a que diga **"Instalación completada"** y cierra la ventana.
4. Abre **Genius Assistant** desde el **menú Inicio**.

> ✅ **No necesitas permisos de administrador** — todo se instala en tu carpeta de
> usuario. **No** te pedirá contraseña (Windows guarda la configuración de forma
> segura en el Administrador de credenciales).

**¿`install.cmd` no hace nada o se cierra solo?** Abre **PowerShell** en esta carpeta
y corre:
```
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (gc -Raw _genius-setup.ps1)"
```
Si aun así falla, tu equipo tiene scripts bloqueados por política de dominio (GPO) —
avísale al equipo de Genius Assistant para firmar el instalador o pedir excepción a TI.
EOF
  echo "✓ Windows"
else
  echo "· (falta el ZIP de Windows: build_corporate_windows.sh en una máquina Windows)"
fi

# Zips por carpeta (Drive-friendly: subir un solo archivo por SO)
for dir in "$OUT"/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  ( cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent "$name" "$name.zip" )
done

echo ""
echo "Carpetas y zips en: $OUT/"
ls -1 "$OUT"
