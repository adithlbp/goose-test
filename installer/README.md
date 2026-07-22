# Instalador corporativo — Genius Assistant

Cómo armar y distribuir el instalable del piloto. El detalle de decisiones vive en
`docs/POC_DESIGN.md`, `docs/SECRET_LIFECYCLE.md` y `docs/RESUMEN_FORK.md`.

## Las dos capas (clave para no filtrar el token)

| Capa | Qué es | ¿Lleva token? | Quién la arma |
|---|---|---|---|
| **App bundle** | El `.zip`/`.app`/`.exe` de Electron + backend goose | **No** | Colega Windows / CI / build local |
| **Instalable final** | App bundle **+** scripts **+** `genius_token.enc` | **Sí** | Solo el dueño del token |

El app bundle no tiene secretos → es seguro compartir el repo con quien compile.
El token se agrega aparte (paso 2), nunca se comparte con quien compila.

---

## Requisitos

- **macOS** (para builds arm64/Intel): Node 24 + pnpm 10 vía hermit (`source bin/activate-hermit`).
- **Windows** (para el `.exe`): Rust+MSVC, Node 24, pnpm 10, Git Bash, 7-Zip. Ver
  `build_corporate_windows.sh`. Alternativa sin máquina Windows: el workflow de CI.
- **Máquina del usuario** (al instalar): **nada extra**. No requiere Python — el
  descifrado usa `openssl` (nativo en macOS) / .NET (nativo en Windows), y el
  provisioning maneja `goose acp` por stdin.

---

## Paso 1 — Compilar el app bundle (sin token)

### macOS (en esta Mac; usa los binarios congelados de `installer/frozen/`)

```bash
source bin/activate-hermit
bash installer/build_corporate.sh arm64   # → ui/desktop/out/Genius Assistant-darwin-arm64/Genius Assistant.zip
bash installer/build_corporate.sh x64     # → ui/desktop/out/Genius Assistant-darwin-x64/Genius Assistant_intel_mac.zip
```

Cada build también escribe `installer/frozen_goose_darwin_<arch>.sha256` (el hash
del binario empaquetado, que el instalador verifica).

### Windows (ZIP portable) — elige una

- **CI**: Actions → *"Bundle Desktop — Genius (Windows)"* → Run workflow → baja el
  artifact `GeniusAssistant-win32-x64`.
- **Máquina Windows** (o delegar en un colega): en Git Bash,
  `bash installer/build_corporate_windows.sh` → `ui/desktop/out/GeniusAssistant-win32-x64.zip`.

Hospeda cada `.zip` en el canal interno; su URL es el `GENIUS_DESKTOP_URL` **por arquitectura**.

---

## Paso 2 — Embeber el token (SOLO el dueño del token, una vez)

```bash
read -rs GENIUS_TOKEN                                            # se pega, no se ve
printf '%s\n' "$GENIUS_TOKEN" | bash installer/embed_token.sh    # → installer/genius_token.enc (chmod 600)
unset GENIUS_TOKEN
```

`genius_token.enc` (formato `keyhex:ivhex:ct_b64`, AES-256-CBC) queda **ofuscado**
(no aparece con `strings`/`grep`) y **gitignoreado**.
Ver la propiedad de seguridad real en `docs/SECRET_LIFECYCLE.md` §2.1 (es ofuscación,
no cifrado — riesgo aceptado del piloto).

---

## Paso 3 — Armar y distribuir el instalable final

Empaqueta y entrega (por plataforma) el app bundle **hospedado** + estos archivos juntos:

```
install_genius.sh          (macOS/Linux)   |  install_genius.ps1   (Windows)
adversary.md
frozen_goose_darwin_arm64.sha256           (solo macOS)
frozen_goose_darwin_x64.sha256             (solo macOS)
genius_token.enc           ◄── el token, listo y ofuscado
```

> Ya **no** se distribuyen los helpers de Python (`provision_secret.py`,
> `genius_token_codec.py`): el instalador descifra con openssl/.NET y provisiona
> por `goose acp` de forma nativa.

> El `.app`/`.exe` NO va en este paquete: se descarga desde `GENIUS_DESKTOP_URL`.
> `installer/frozen/` (binarios de 234–270 MB) es solo para rebuilds, **no** se distribuye.

### Atajo para testers (carpetas autocontenidas por SO)

Para pruebas vía Drive/AirDrop (sin hospedar), `package_for_testers.sh` arma una
carpeta por SO con **todo dentro** (app + scripts + `genius_token.enc`):

```bash
bash installer/package_for_testers.sh   # → dist-testers/{macOS-AppleSilicon,macOS-Intel,Windows}/ (+ .zip)
```

El tester descarga la carpeta de su SO, la descomprime y corre `bash install_genius.sh`
(o en Windows, `install_genius.ps1`) — el instalador **auto-detecta** el zip a su lado.
Requiere `genius_token.enc` ya generado (Paso 2).

---

## Instalación en la máquina del usuario (no interactiva)

```bash
# macOS — opción URL (curl):
GENIUS_DESKTOP_URL="https://interno/Genius Assistant.zip" ./install_genius.sh
# macOS — opción archivo local (p.ej. zip bajado de Drive a mano):
GENIUS_DESKTOP_ZIP="/ruta/Genius Assistant.zip" ./install_genius.sh
```

> Los links de **Google Drive no son descargables por `curl`** (>100 MB muestran
> página de confirmación). Para Drive: el tester baja el zip a mano y usa
> `GENIUS_DESKTOP_ZIP`. El instalador quita la cuarentena de Gatekeeper automáticamente.

```powershell
# Windows
$env:GENIUS_DESKTOP_URL="https://interno/GeniusAssistant-win32-x64.zip"; .\install_genius.ps1
```

Hace: instala la app en **`~/Applications`** (macOS, sin admin) → coloca `adversary.md`
→ **verifica el binario** contra el hash bendecido (macOS) → provisiona el token (desde
`genius_token.enc`) al Keychain/CredMan. El usuario no teclea nada ni necesita Python.
`GENIUS_TOKEN` (env) sobreescribe el `.enc`, solo para pruebas.

---

## Rotación / revocación del token

- **Rotar**: nuevo token en el gateway → repetir el **Paso 2** → redistribuir → reinstalar.
- **Revocar**: se hace en el gateway (efecto inmediato); el secreto local queda inofensivo.
- Detalle y runbook de fallos: `docs/SECRET_LIFECYCLE.md` §7 y §9.

---

## Seguridad — no romper esto

- **Nunca** subas `genius_token.enc` al repo ni lo compartas con quien compila.
- **Nunca** hardcodees el token en un script (lección "Genius Code").
- El token viaja siempre por stdin o decode in-memory; jamás por argv/`ps`/consola.
- `GOOSE_DISABLE_KEYRING` deja secretos en texto plano en disco — prohibido en el piloto.
