# Prompt 08 — Instaladores corporativos (`.sh` / `.ps1`)

> Pégalo a un agente de código en el clon limpio. Objetivo: instaladores que detecten SO, instalen el build corporativo, provisionen el secreto y activen las políticas — sin intervención del usuario.

---

## Tarea

Adapta los instaladores existentes (`download_cli.sh`, `download_cli.ps1` en la raíz) o crea wrappers corporativos que hagan, de forma **no interactiva**:

1. Detectar el sistema operativo/arquitectura.
2. Descargar e instalar el **build corporativo** (desde el repo/release interno del fork).
3. **Provisionar el API Key** vía ACP → Keychain (prompt 07).
4. Colocar `adversary.md` (prompt 05).
5. **No** lanzar el wizard interactivo.

## Reutilizar lo que ya existe

`download_cli.sh` ya resuelve la mayor parte y documenta sus variables (cabecera, `download_cli.sh:16-25`):
- Detección de SO/arch (`download_cli.sh:88-142`).
- `GOOSE_PROVIDER`, `GOOSE_MODEL` — provider por defecto.
- `CONFIGURE=false` — **desactiva `goose configure` interactivo** (`download_cli.sh:344-360`). Úsalo siempre en corporativo (es justo lo que evita el wizard que "se abre solo").
- `REPO`/release: apuntar al repo interno del fork (no `aaif-goose/goose`).

`download_cli.ps1` replica el mismo contrato (`$env:CONFIGURE`, `$env:GOOSE_PROVIDER`, …).

## Flujo del instalador corporativo (pseudo)

```sh
# 1. detectar SO/arch  (ya en download_cli.sh)
# 2. descargar + instalar el build corporativo del fork
CONFIGURE=false \
GOOSE_PROVIDER=openai \
GOOSE_MODEL=<modelo> \
  bash download_cli.sh          # o el instalador del Desktop (.app/.zip/.exe)

# 3. provisionar el secreto vía ACP → Keychain (prompt 07)
python3 provision_secret.py --goose "<ruta-al-goose-instalado>" \
  --key OPENAI_API_KEY --token "<TOKEN>"

# 4. colocar adversary.md (prompt 05)
mkdir -p "$HOME/.config/goose"
cp adversary.md "$HOME/.config/goose/adversary.md"   # Windows: %APPDATA%\Block\goose\config\
```

> Para el **Desktop** (no CLI), el binario `goose` vive dentro del bundle (`Resources/bin/goose` en la `.app`, o `resources/bin/goose.exe` en Windows). El paso 3 debe invocar ESE binario para que el item del Keychain lo cree la misma identidad que luego lee `goosed` (creador == consumidor — ver prompt 07 y la condición de firma).

## Manejo del token (lección "Genius Code")

- **No** dejar el token en texto plano ni base64 trivial dentro de un script público/de acceso amplio (ese fue el error de Genius Code).
- Opciones, de menor a mayor infraestructura (elige según lo disponible):
  1. Hospedar el wrapper con el token en un **repo/sitio interno** con control de acceso (no público).
  2. **Ofuscación + secreto partido**: el token no viaja completo; un fragmento llega por un canal separado y se combina en runtime.
  3. Si más adelante hay endpoint/SSO/MDM, sustituir el token embebido por aprovisionamiento dinámico (sin cambiar el paso 3: el `provision_secret.py` sigue igual, solo cambia de dónde sale `<TOKEN>`).
- **Token único por plataforma** (no por usuario), monitoreado y revocable — como se acordó.

## Verificación (en máquina/VM limpia)
1. Ejecutar el instalador → app instalada, **sin prompts de configuración**.
2. Abrir la app → **sin onboarding** → chatea contra el gateway (provider pineado, prompt 03).
3. `provision_secret.py --read-only` → valor enmascarado no-nulo; **sin** `secrets.yaml`.
4. `adversary.md` presente en el config dir; inspector activo en logs.
5. Prompt injection detection **ON y bloqueado** en Settings (prompt 06).
6. **Update**: instalar una build nueva del fork y confirmar que el Keychain **no** re-pregunta — requiere binario **firmado** (prompt 07). Si re-pregunta, falta la firma.

## No hacer
- No dejar `CONFIGURE` en su default (lanzaría el wizard interactivo).
- No apuntar el updater/descarga a `aaif-goose/goose`; usar el repo interno del fork.
- No escribir el secreto a un archivo intermedio en disco (el paso 3 lo pasa por stdin del proceso, nunca lo persiste en claro).
