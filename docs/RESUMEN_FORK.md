# Resumen ejecutivo — Fork "Genius Assistant" sobre Goose

> Resumen de todos los cambios aplicados sobre Goose Desktop original para el
> piloto interno de Coppel. Para el detalle línea-por-línea ver `CHANGES_REVIEW.md`;
> para el diseño de credenciales `POC_DESIGN.md`; para el ciclo de vida del secreto
> `SECRET_LIFECYCLE.md`; para el blindaje de UI `LOCKDOWN.md`; para la política de
> seguridad `ADVERSARY_POLICY.md`. Fecha: 2026-07-20; actualizado 2026-07-21
> (instalables macOS arm64+Intel; token embebido ofuscado; **fix del 401**
> —provisioning robustecido—; default `gemini-3.5-flash`; skills CRUD; provider
> bloqueado en recetas; self-branding del agente vía override de `system.md`;
> postura de escritura del adversary = HOME permitido; whitelist de dominios;
> **instalable de Windows generado** (no-admin, wrapper `install.cmd`). Últ.: 2026-07-22.

## Principio de diseño (la regla que guió todo)

**Mínimo diff sobre upstream + reutilizar mecanismos oficiales.** Casi todo el
comportamiento corporativo se logra **horneando variables de entorno en el build**
(no editando lógica), aprovechando que Goose ya resuelve config con precedencia
*env-first*. Regla dura respetada: **cero cambios en `crates/goose`** (core, Config,
SecretStorage, registro de providers, resolución de secretos). Todo el diff vive en
`ui/desktop/` (TypeScript/assets) y en instaladores/scripts nuevos.

---

## Cambios por área

| Área | Qué cambió | Archivos | Tipo |
|---|---|---|---|
| **Marca** | "Genius Assistant" + paleta Coppel (azul `#1C42E8`, amarillo `#F0D224`) + logo de tres puntos, en textos/temas/iconos, 16 catálogos i18n; **identidad del agente** rebrandeada vía override de `system.md`; textos "Ask goose"/"ask goose" → "Genius Assistant" | `package.json`, `index.html`, `main.ts`, `theme-tokens.ts`, `main.css`, `icons/Goose.tsx`, `images/*`, `i18n/messages/*`, `toasts.tsx`, `apps/AppsView.tsx`, `installer/prompts/system.md` | Cosmético |
| **Provider fijo** | Provider "Genius" (OpenAI-compatible) auto-creado en el primer arranque, apuntando al gateway; onboarding omitido | `vite.main.config.mts`, `main.ts`, `ModelAndProviderContext.tsx` | Bundle/UI |
| **Bloqueo de config** | Provider y External Backend no editables; tabs Auth/Config ocultos; "managed by your organization"; **selector de provider en Opciones avanzadas de receta** también bloqueado | `SettingsView.tsx`, `ProviderGrid.tsx`, `SwitchModelModal.tsx`, `ModelSettingsButtons.tsx`, `ModelsSection.tsx`, `ExternalBackendSection.tsx`, `recipes/shared/RecipeModelSelector.tsx` | UI |
| **Seguridad** | Prompt-injection forzado ON + bloqueado; `adversary.md` distribuido en el instalable; **postura de escritura = HOME del usuario permitido** (bloquea solo sistema/credenciales/exfiltración/persistencia/código remoto) | `vite.main.config.mts`, `main.ts`, `forge.config.ts`, `installer/adversary.md` | Bundle/asset |
| **Credenciales** | API key provisionada vía ACP→Keychain (flujo oficial); token embebido ofuscado (`genius_token.enc`), listo en el instalable; **sin Python** (openssl/.NET + `goose acp`) | `installer/embed_token.sh`, `install_genius.sh`/`.ps1` | Instalador |
| **Updates/Telemetría** | UI de updates oculta + sin auto-descarga; telemetría off sin prompt; "Version" sin logo Block | `AppSettingsSection.tsx`, `main.ts`, `vite.main.config.mts` | Bundle/UI |
| **Modelos dinámicos** | Picker trae la lista viva del gateway (`/v1/models`) con fallback estático | `acp/providers.ts`, `modelInterface.ts` | UI |
| **Extensiones** | Modo "advertir" al conectar MCP externos | `vite.main.config.mts`, `installer/build_corporate.sh` | Bundle |
| **Skills** | Formulario para **crear, editar y eliminar** skills (nombre/cuándo/instrucciones) para usuarios no técnicos; builtins read-only con candado | `skills/SkillsView.tsx`, `acp/sources.ts` | UI |
| **Instaladores** | Wrappers corporativos + receta de build; repo apuntable por env; **instalación sin admin** (per-usuario) en macOS (`~/Applications`) y Windows (`%LOCALAPPDATA%`); wrapper `install.cmd` (doble clic, salta Execution Policy vía IEX) + acceso directo en menú Inicio | `installer/*`, `download_cli.sh`/`.ps1` | Scripts |

---

## Decisiones arquitectónicas complejas (el *porqué*)

### 1. Credenciales: ACP → Keychain (no env, no hardcode, no Keychain directo)

**Qué se hizo:** el instalador provisiona el API key ejecutando `goose acp` y
mandándole `_goose/unstable/config/upsert {isSecret:true}` por JSON-RPC; Goose lo
persiste en el Keychain con su propio `Config::set_secret()`.

**Por qué esta arquitectura y no las alternativas:**
- *No hardcode del token en el binario/en claro* → importante
  (API key en bruto/base64 extraíble del binario). El token **no** vive en el app
  bundle; viene en un archivo aparte **ofuscado** (`genius_token.enc`) que solo
  arma el dueño del token, y en reposo termina en el Keychain/CredMan.
- *No escribir al Keychain directo desde el helper* → romper compatibilidad con cómo
  Goose lee sus secretos (nombre del item, ACL). Reutilizar el flujo oficial
  garantiza que **quien crea el secreto es la misma identidad que luego lo lee**.
- *No parchear `from_env`/core* → viola la regla de no tocar `crates/`.

Verificado en vivo: upsert → lectura enmascarada → item `svce="goose"` en Keychain,
sin `secrets.yaml`. El token nunca aparece en argv/`ps`/consola (stdin o decode
in-memory; log **redactado**).

> **Matiz honesto:** `genius_token.enc` es **ofuscación, no cifrado** — con la clave
> dentro del blob, un insider decidido puede recuperarlo. 
> (fuera del binario, no aparece con `strings`/`grep`, va al almacén del SO), pero
> **no** es protección criptográfica. Riesgo aceptado del piloto: token único
> por-plataforma, monitoreado y revocable en el gateway. Detalle en
> `SECRET_LIFECYCLE.md` §2.1.

### 2. Firma de código: binario congelado + reset en updates (estrategia de PoC)

**El problema:** se demostró empíricamente (prueba A→B, dos builds de hash distinto)
que **con firma ad-hoc el Keychain re-pregunta autorización en cada actualización**
del binario — la ACL del secreto se ata al hash del binario. Sin Apple Developer ID,
esto rompería la experiencia en cada update.

**Por qué la estrategia elegida:** en vez de tratar la firma como bloqueo (no hay
Developer ID en la PoC), se aprovechó que **el 100% del diff del fork es no-Rust**.
El binario `goose` no necesita cambiar para iterar la PoC → se **congela** (se
archiva con checksum y se reutiliza; el `build_corporate.sh` lo verifica con un
guard I5). Para producción: Developer ID + notarización. Detalle y alternativas
evaluadas en `POC_DESIGN.md`.

### 3. Locks de UI: env-first en vez de forzar valores en el core

**Qué se hizo:** los bloqueos (provider, backend, seguridad) se activan con env vars
(`GOOSE_LOCK_PROVIDER`, `GOOSE_LOCK_BACKEND`, `SECURITY_PROMPT_ENABLED_OVERRIDE`).

**Por qué:** `Config::get_param/get_secret` ya resuelve **env antes que config.yaml**.
Consecuencia: lo horneado **gana en runtime aunque el usuario lo cambie** — el
bloqueo *funcional* es gratis, sin tocar el core. La UI solo agrega el bloqueo
*visual* (deshabilitar + "managed by your organization"), reutilizando el patrón
oficial `*_OVERRIDE` que ya existía para seguridad. En builds sin las env, cero
regresión.

### 4. Provider "Genius": auto-creación + enlace del token (el baile crear→actualizar)

**Qué se hizo:** en el primer arranque, si el bundle define `GOOSE_CUSTOM_PROVIDER`,
la app crea el custom provider vía el endpoint oficial del formulario y luego lo
**enlaza al secreto ya provisionado** (update con `requires_auth:true` sin api_key,
que reutiliza el secreto del Keychain).

**Por qué así:** el endpoint de crear custom providers **exige** el api_key cuando
`requires_auth:true`, pero la app **no tiene el token en claro** (está en el
Keychain). La solución oficial: crear con `requires_auth:false` y luego *actualizar*
a `true` sin api_key — el servidor detecta el secreto almacenado y lo enlaza. Con
protección **single-flight** porque en el arranque varios componentes disparan el
fallback en paralelo (sin ella se creaban providers duplicados).

> **Corregido (2026-07-21):** este baile **no** pierde el secreto. El wrapper de UI
> convierte `api_key:''` en `null`, así que el update con `requires_auth:true`
> **reutiliza** el secreto del Keychain (no lo pisa con vacío). El 401 "No api key
> passed in" que se veía en pruebas no venía de aquí, sino del **instalador**, que no
> alcanzaba a guardar el token. Ver §"Resuelto: fix del 401" abajo.

### 5. Modelos dinámicos: endpoint correcto, no el inventario

**El síntoma:** el picker mostraba solo el modelo tecleado, no la lista del gateway.

**La causa (probada con servidor mock):** el picker usaba `providers/list`
(inventario), que para custom providers es **estático por diseño** (gated por
`dynamic_models`, que el create ACP fija a `None`). El endpoint
`providers/supported-models/list` **sí** hace fetch en vivo a `/v1/models`.

**Por qué el fix:** se cambió el picker para preferir `supported-models` (lista viva)
con fallback al inventario/estático si el gateway no responde. Nunca queda más vacío
que antes. Cero cambios en `crates/` — el endpoint ya existía en el binario.

### 6. Adversary mode: cobertura de `write`/`edit` (hallazgo `unprefixed_tools`)

**Qué se hizo:** el frontmatter de `adversary.md` pasó de `shell,
computercontroller__automation_script` a incluir **`write, edit`**.

**Por qué:** se verificó en el código que la extensión `developer` tiene
`unprefixed_tools: true` → sus tools llegan al inspector como `shell`/`write`/`edit`
a secas. Sin `write`/`edit` en la lista, "escribe en `~/.ssh/authorized_keys`" vía la
tool `write` **esquivaba** la revisión que sí se aplicaba a `shell`. Se añadieron
además reglas de credenciales sin importar ubicación. Límite conocido:
**fail-open** si el LLM no responde (propiedad del mecanismo, no un bug).

**Postura de escritura re-encuadrada (2026-07-21).** La regla original "BLOCK si
escribe fuera del working dir" (heredada de goose-como-herramienta-de-código) bloqueaba
tareas legítimas de productividad: un tester recibía `security.action:BLOCK` al intentar
`mkdir ~/.local/share/goose/skills` (crear un skill). El mensaje que ve el modelo en ese
caso es `DECLINED_RESPONSE` ("The user has declined to run this tool"), lo que confunde:
parece confirmación humana, pero es el **bloqueo automático del adversary** (un `Deny`
del inspector cae en el bucket `denied` → ese texto; el modelo no distingue y confabula
"lo denegó el usuario"). Se cambió la postura a **permitir escritura en el HOME del
usuario** (proyectos, `~/.config/goose`, `~/.local/share/goose`, `~/.agents`…) y en
**directorios temporales** (`/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR`), y bloquear
solo: rutas de sistema, credenciales (sin importar ubicación), archivos de
startup/persistencia, exfiltración, código remoto y escalación de privilegios. El
`adversary.md` se re-lee **una vez por sesión** (`get_or_init`) → tras actualizarlo hay
que abrir un chat nuevo o reiniciar la app.

**Secretos de tareas (ej. API key de N8N) = env var, no archivo.** El patrón que dispara
el bloqueo es `cat ~/.n8n_api_key | curl` (leer un archivo de credencial y mandarlo por
red = forma de exfiltración; correcto que se bloquee). Solución: la key va como **variable
de entorno** (goosed hereda `process.env` de Electron → el shell del agente la ve como
`$N8N_API_KEY`). El override de `system.md` instruye al agente a usar env vars y nunca
`cat` de archivos secretos, y `adversary.md` aclara que autenticar con una env var a un
servicio conocido **no** es exfiltración (leer el archivo sí sigue bloqueado). En macOS la
env var se inyecta con `launchctl setenv N8N_API_KEY <valor>` + reiniciar la app.

**Whitelist de dominios (curl/HTTP).** La regla de exfiltración ("curl a URLs
desconocidas") hacía que gemini-3.5-flash bloqueara `curl` a servicios corporativos
legítimos por verlos como "desconocidos". Se reformuló a **destinos NO confiables** y se
agregó una lista blanca en `adversary.md`: `*.coppel.io`, `*.coppel.services`,
`*.coppel.com`, `coppelmx.atlassian.net`, `*.google.com`/`*.googleapis.com` (Workspace).
Requests a esos dominios (incluso con una API key de env var) = trabajo normal, no
exfiltración. Mandar datos a destinos fuera de la lista (IPs, pastebins, file-sharing
personal) sigue bloqueado, y **leer archivos de credencial sigue bloqueado**.

### 7. Extensiones: advertir, no bloquear (decisión consciente)

**Qué se hizo:** `GOOSE_ALLOWLIST_WARNING=true` — al conectar un MCP externo, se
muestra un aviso de consentimiento ("Install Anyway").

**Por qué advertir y no un allowlist estricto (todavía):** el allowlist estricto
(que sí bloquea) requiere hospedar un YAML con las URLs aprobadas — infraestructura
que aún no existe y URLs de MCP que aún no se definen. Además, el agente **ya está
acotado** por otra vía: `extension_manager` solo puede encender extensiones
**pre-configuradas**, no jalar MCP arbitrarios. El modo estricto + wildcard de
dominios (`*.coppel.io`) queda documentado como fase 2 para cuando exista el host y
las URLs.

---

## Lo que NO se tocó (y por qué importa)

- **`crates/goose`** (core, Config, SecretStorage, providers, resolución de secretos):
  **cero cambios**. Se leyó como referencia; nunca se editó. Esto mantiene el fork
  fácil de rebasear contra upstream.
- **Identificadores funcionales internos**: `KEYRING_SERVICE`, rutas `Block/goose`,
  esquema `goose://`, variables `GOOSE_*`, `appId` `io.github.block.Goose`, clases
  CSS `goose-*` — intactos, porque cambiarlos rompe compatibilidad y no son visibles
  al usuario.

## Resuelto en la revisión pre-build (2026-07-20)

- **Gate del provisioning re-encuadrado al invariante I5.** Antes el instalador
  omitía el provisioning salvo `GENIUS_SIGNING_READY=true` (postura vieja "firma =
  bloqueo") → en la PoC sin firma el token nunca se guardaba. Ahora
  `install_genius.sh` verifica el **hash del build bendecido**
  (`frozen_goose_darwin_{arm64,x64}.sha256`, generados por `build_corporate.sh`
  desde el binario ya empaquetado; el instalado debe coincidir con **alguno**) y
  provisiona si hay match. En Windows se quitó el gate: Credential Manager es
  por-usuario (sin ACL por-hash), provisionar es seguro.
- **Política corporativa unificada** en `installer/corporate_env.sh` (fuente única
  sourceada por macOS y por el CI de Windows → sin drift).
- **Red de seguridad del fallback**: `GOOSE_DEFAULT_PROVIDER=custom_genius` horneado
  (mitiga parcialmente la fragilidad del enlace §4 si el baile crear→enlazar falla).
- **Build de Windows**: `.github/workflows/bundle-desktop-genius-windows.yml`
  (adaptado de upstream; CI-only — goose.exe requiere cargo + MSVC). Produce ZIP
  portable con la política horneada; firma Azure opcional.

## Resuelto en la generación de instalables (2026-07-21)

- **Instalables macOS generados y verificados**: arm64 (`Genius Assistant.zip`,
  188 MB) e Intel/x64 (`Genius Assistant_intel_mac.zip`, 205 MB). Ambos con la
  política horneada (gateway, `custom_genius`, locks) y el backend `goose` v1.43.0
  del arch correcto (Intel = binario oficial x86_64 descargado de la release, no
  compilado). `build_corporate.sh` ahora recibe `arm64|x64` y hace stage desde
  `installer/frozen/goose-<triple>`.
- **Verificar cambios de UI en el bundle:** electron-forge empaqueta el código
  compilado del Desktop en `…/Genius Assistant.app/Contents/Resources/**app.asar**`
  (NO en `.vite`, que queda vacío). El asar es un archivo sin comprimir → se pueden
  buscar strings con `grep -a "<texto>" app.asar`. Útil para confirmar que un cambio
  de `ui/desktop/src` realmente entró al build (no fiarse del exit code).
- **Token embebido, ofuscado y listo en el instalable** (`genius_token.enc`): el
  usuario no teclea nada. `embed_token.sh` (lo corre el dueño del token, por stdin;
  AES-256-CBC con openssl). Es ofuscación (riesgo aceptado), no cifrado — ver
  `SECRET_LIFECYCLE.md` §2.1.
- **Provisioning SIN Python** (requisito: muchas máquinas no tienen Python):
  `install_genius.{sh,ps1}` descifran con **openssl** (macOS) / **.NET** (Windows) y
  provisionan manejando `goose acp` por pipe. Se eliminaron los helpers Python
  (`provision_secret.py`, `genius_token_codec.py`, `embed_token.py`).
- **Instalación en `~/Applications`** (macOS): evita el `Operation not permitted` de
  `/Applications` en Macs corporativas (sin permisos de admin).
- **Handoff de Windows**: `installer/build_corporate_windows.sh` — script
  llave-en-mano (Git Bash) para que alguien con Windows genere el ZIP sin CI. El
  app bundle no lleva token, así que es seguro compartir el repo con esa persona.

## Resuelto: fix del 401 "No api key passed in" (2026-07-21)

**Causa raíz (no era la generación ni el baile §4):** `provision_secret` en
`install_genius.sh`/`.ps1` mandaba el `upsert` a `goose acp` y luego hacía
**`sleep 2` + `kill`**. En el primer arranque el binario recién extraído tarda
(Gatekeeper) y el Keychain puede pedir la contraseña; si eso excedía 2s, el `kill`
**abortaba la escritura** → secreto vacío/ausente → chat sin `Authorization` → 401,
sin error visible. Explica el "a veces sí funcionaba": cuando el Keychain ya confiaba
en el binario, la escritura alcanzaba dentro de los 2s.

- **Fix:** el instalador ahora **espera la respuesta real** del upsert
  (`"id":2,"result"`, hasta ~60s dando tiempo a aprobar el Keychain) en vez de un
  `sleep` ciego, y **confirma/avisa** (`✓ token provisionado` o error accionable).
  Mismo cambio en Windows (cold-start también podía exceder 2s).
- **Validado end-to-end:** instalador → `✓ token provisionado` → el binario instalado
  lee el token de vuelta **sin prompt** → gateway responde **HTTP 200** con
  `gemini-3.5-flash`. **No requiere recompilar el bundle** (el diff es solo de
  scripts; basta re-empaquetar con `package_for_testers.sh`).
- **Diagnóstico útil:** verificar un secreto sin exponerlo con `goose acp` +
  `_goose/unstable/config/read` + `isSecret:true` (devuelve enmascarado o `null`). La
  ACL del Keychain es **por-binario**: `security …-w` desde la CLI no puede leer el
  item que creó goose, así que no sirve para verificar.

## Ajustes de UI escritos en el rebuild (2026-07-21)

- **Modelo default → `gemini-3.5-flash`** (`corporate_env.sh`), en vez del
  `gemini-3.1-pro-preview` inválido que hacía caer al fallback (opus).
- **Enlaces incompatibles a goose-docs quitados:** "Guía de inicio rápido" del modal
  de cambio de modelo (`SwitchModelModal.tsx`) y los links de troubleshooting del
  reporte de diagnóstico (`Diagnostics.tsx`). Se conservan los genéricos (crear
  extensión / recipe / goosehints).

## Skills CRUD, lock de receta y self-branding (2026-07-21)

- **Skills: crear + editar + eliminar.** El backend ya exponía
  `sourcesUpdate_unstable`/`sourcesDelete_unstable` (su doc interna incluso preveía
  "the skills editor"); solo faltaba conectarlo. `SkillsView.tsx` unifica un
  `SkillFormModal` (crear/editar), tarjetas clicables, borrado con confirmación, y
  respeta el flag `writable` (los builtins del bundle salen read-only con candado).
  El nombre es de solo lectura al editar (es la identidad en disco). Cero cambios en
  `crates/`.
- **Provider bloqueado en Opciones avanzadas de receta.** `RecipeModelSelector.tsx`
  era el único selector de provider que no aplicaba `GOOSE_LOCK_PROVIDER` → deshabilitado
  + nota "managed by your organization", mismo patrón que `SwitchModelModal`. El
  selector de **modelo** queda intacto (ya trae la lista viva del provider).
- **El agente se identifica como "Genius Assistant".** El system prompt vivía en
  `crates/goose/src/prompts/system.md` ("You are ... goose"), **compilado en el binario
  congelado** (I5) → no editable sin recompilar. Pero `prompt_template::render_template`
  **lee un override de runtime** en `<config_dir>/prompts/system.md` si existe (igual que
  `adversary.md`). Se hornea `installer/prompts/system.md` (snapshot de v1.43.0 con la
  identidad rebrandeada, resto de la plantilla minijinja idéntico) y los instaladores lo
  copian a `~/.config/goose/prompts/` (macOS) / `%APPDATA%\Block\goose\config\prompts\`
  (Windows). Verificado vía `_goose/unstable/config/prompts/get` → `isCustomized:true`.
  **No requiere recompilar el binario.** El override incluye una instrucción explícita
  de **nunca** llamarse "Goose"/"Goose Desktop" y usar el nombre correcto de la app
  (`open -a "Genius Assistant"`), porque el modelo tiende a filtrar "goose" (lo ve en el
  binario, `~/.config/goose`, nombres de tools y su propio entrenamiento). El `system.md`
  se **re-lee por turno** (sin caché, a diferencia de `adversary.md`) → aplica al
  siguiente mensaje sin reiniciar. Mitigación fuerte, no garantía del 100%.
  > Acoplamiento a documentar: el override es un snapshot del `system.md` de v1.43.0.
  > Si el binario deja de estar congelado, regenerar el snapshot desde el nuevo default.
- **Textos "Ask goose" → "Genius Assistant":** botón de recuperación de errores
  (`toasts.tsx`, sin i18n) y descripciones de `AppsView.tsx`.

## Instalable de Windows: sin admin + Execution Policy (2026-07-22)

- **Generado end-to-end.** `goose.exe` compilado en una máquina Windows (Git Bash,
  `build_corporate_windows.sh`; cargo MSVC + electron-forge win32). Baches típicos de
  primera compilación en máquina nueva: falta **libclang** (bindgen → `winget install
  LLVM.LLVM` + `LIBCLANG_PATH`), **CMake** (`winget install Kitware.CMake`), y Node/pnpm.
  El ZIP de electron-forge (`Genius Assistant-win32-x64-1.43.0.zip`) ya trae
  `resources\bin\goose.exe` → sirve igual que el "plano" del paso [4/4]; solo hay que
  **renombrarlo** a `GeniusAssistant-win32-x64.zip` (sin espacios) para `package_for_testers.sh`.
  El empaquetado final (agregar token + `_genius-setup.ps1` + adversary/prompts) se hace
  **en el Mac** porque `genius_token.enc` vive solo ahí (gitignoreado).
- **Sin permisos de administrador.** `_genius-setup.ps1` instala en `%LOCALAPPDATA%\
  GeniusAssistant`, config en `%APPDATA%\Block\goose\config`, token en Credential Manager
  — todo per-usuario. No toca `Program Files` ni `HKLM`. Se agregó **acceso directo en el
  menú Inicio del usuario** (`%APPDATA%\...\Start Menu\Programs`, sin admin) — antes el
  README decía "abre desde Inicio" pero no se creaba el shortcut.
- **Execution Policy: el riesgo real de Windows corporativo.** En equipos bloqueados la
  policy suele impedir correr `.ps1`. Se agregó **`install.cmd`** (doble clic) que corre
  el instalador con `Invoke-Expression (Get-Content -Raw …)` — la Execution Policy aplica a
  *archivos* `.ps1`, **no** a comandos vía `-Command`/IEX, así que funciona bajo
  Restricted/AllSigned, incluso por GPO, y sin admin. El `.ps1` se hizo robusto a
  `$ScriptDir` (usa `GENIUS_SCRIPT_DIR` que setea el `.cmd`, ya que corriendo como comandos
  `$MyInvocation.MyCommand.Path` es null).
  > **Caveat honesto:** el patrón `iex (gc …)` es justo lo que buscan los **antivirus/EDR**
  > corporativos (técnica común de malware) — un EDR agresivo podría marcarlo aunque la
  > Execution Policy lo permita. Bypass es por-proceso (cero riesgo de sistema; la Execution
  > Policy no es barrera de seguridad per Microsoft), pero **la solución limpia y definitiva
  > es firmar** (Azure Trusted Signing, ya en el workflow): quita SmartScreen, corre bajo
  > AllSigned sin trucos y no lo marca el EDR. **Pendiente probar en una máquina real de
  > Coppel** antes de repartir.

## Bugs del piloto resueltos (2026-08-18)

- **Selector de modelo muerto en chat nuevo.** Síntoma: en una conversación
  recién abierta no se podía cambiar el modelo; solo funcionaba tras la primera
  interacción. Causa raíz: en el Hub (chat sin sesión, `sessionId=null`) el cambio
  va por `defaults/save`, y `on_defaults_save` (`crates/.../acp/server/config.rs`)
  **valida el modelo contra el inventario estático** del provider — que para
  `custom_genius` solo contiene `gemini-3.5-flash` (los custom providers no
  refrescan inventario). El picker en cambio muestra la lista **viva** del gateway
  (`supported-models`), así que cualquier otro modelo era rechazado con "Model 'X'
  is not available". Con sesión activa el cambio usa `on_set_model`, que no valida
  → por eso funcionaba después del primer mensaje. Fix (solo UI, cero `crates/`):
  `saveDefaultsAcceptingLiveModel` en `ModelAndProviderContext.tsx` — si
  `defaults/save` rechaza el modelo, actualiza la lista `models` del custom
  provider vía el endpoint oficial de update (con `api_key:''` → conserva el
  secreto del Keychain) y reintenta. Cubre Hub y Settings para cualquier modelo
  que el gateway sirva.
- **Adversary sobre-restrictivo (terminal bloqueada).** Reescritura ALLOW-first de
  `installer/adversary.md` + formato de salida estricto (mitiga un hazard del
  parser que convertía ALLOWs verbosos en BLOCK falso) + dominios confiables
  ampliados (`*.services.coppel`, `*.atlassian.net`, `api.atlassian.com`,
  `*.googleusercontent.com`), y sección "Blocked Tool Calls" en
  `installer/prompts/system.md` para que el agente no confabule "el usuario lo
  rechazó". Detalle completo en `ADVERSARY_POLICY.md` §"Reescritura ALLOW-first".
  **Ambos fixes requieren re-empaquetar** (el diff es de UI/assets; el binario
  congelado no cambia).

- **El control de "Thinking effort" desaparecía al elegir modelo.** Síntoma: el
  selector de esfuerzo de razonamiento se veía con el modelo por defecto, pero
  desaparecía al seleccionar cualquier otro. Causa raíz: `showThinkingControl`
  exige `reasoning === true`, y ese flag se resolvía **solo** contra el inventario
  del provider (`fetchModelReasoning` → `acpListProviderModels`). Para
  `custom_genius` el inventario contiene únicamente los modelos tecleados al
  crearlo (`gemini-3.5-flash`) — el resto viene de la lista **viva** del gateway,
  que devuelve `string[]` **sin metadatos**. Resultado: modelo default → hay
  match → `reasoning=true` → control visible; cualquier otro → sin match →
  `null` → control oculto. Es una interacción directa con el fix de modelos
  dinámicos (adenda 2026-07-20b): al traer más modelos de los que el inventario
  conoce, se destapó el hueco de metadatos. Fix (solo UI): `fetchModelReasoning`
  cae al **registro canónico** (`providers/canonical-model-info`, ya expuesto por
  el binario congelado) cuando el inventario no sabe del modelo. Ese registro
  infiere el proveedor por el **nombre** (`gemini-*`→google, `claude*`→anthropic,
  `gpt-*`→openai, `name_builder.rs:168`), así que resuelve los modelos del
  gateway aunque vivan bajo `custom_genius`. Validado contra los datos embebidos
  (`canonical_models.json`): las nueve variantes `google/gemini-3.x` presentes
  traen `reasoning=true`.
  > **Corregido el 2026-08-20 (caso `claude-opus-5`):** el registro canónico que
  > trae el binario congelado v1.43.0 **está desactualizado** respecto al gateway
  > — conoce `claude-opus-4.1`…`4.8`, `claude-sonnet-5` y `claude-haiku-4-5`
  > (vía normalización de nombres), pero **no** `claude-opus-5` ni
  > `gemini-3.5-pro`. Probado contra el binario real: para esos modelos
  > `canonical-model-info` devuelve `null` → control oculto. **No es el
  > gateway**: la UI nunca le pregunta al gateway por el soporte de razonamiento.
  > Fix: replicar en la UI la heurística propia de upstream
  > `ModelConfig::is_reasoning_model` (`crates/goose-provider-types/src/model.rs:228`
  > + `is_openai_responses_model`, `formats/openai.rs:1507`) como último recurso
  > cuando el registro no conoce el modelo: nombres con `claude`, `gemini-3*`, y
  > el regex de OpenAI `o<N>`/`gpt-5`. Es la **misma** regla que el backend ya
  > aplica al construir las peticiones, así que la UI deja de contradecirlo (el
  > motor ya trataba a `claude-opus-5` como reasoning). Los modelos que el
  > registro sí conoce siguen mandando su valor real, así que un modelo sin
  > razonamiento no gana el control por error. Un alias corporativo que no
  > matchee ninguna regla sigue sin control; ahí la salida es declararlo en el
  > `models` del custom provider.

**Re-empaquetado (2026-08-18):** ambos instalables de macOS regenerados y
verificados — `dist-testers/macOS-AppleSilicon.zip` (187 MB) y
`dist-testers/macOS-Intel.zip` (205 MB). Verificación del bundle: el
`adversary.md` nuevo está en `Contents/Resources/`, y el fix de modelo se confirmó
en `app.asar` por su forma **minificada** (`models:[...r,t]`), presente en el build
nuevo y ausente en el de julio — el nombre `saveDefaultsAcceptingLiveModel` no
sirve para grep porque el build de producción mangla identificadores.
**Hallazgo útil (I5):** el hash del binario empaquetado es **idéntico** al del
binario congelado (electron-forge copia `goose` como `extraResource` sin
re-firmarlo) → `1a645dc3…f858e566` sin cambios, así que este update **no dispara
re-prompts del Llavero** ni invalida el token ya provisionado en las máquinas de
los testers (verificado en las dos arquitecturas: `1a645dc3…f858e566` arm64 y
`b55bc0d8…abd28370` x64, ambos sin cambio). Pendiente: **Windows** (requiere
máquina Windows para `goose.exe`; el ZIP de julio no lleva ninguno de los dos
fixes).

> **Trampa del empaquetado detectada en la práctica:** compilar con
> `build_corporate.sh <arch>` **no** actualiza `dist-testers/` — son dos pasos.
> Tras el build de Intel el `app.asar` de `out/` ya tenía el fix, pero
> `dist-testers/macOS-Intel.zip` seguía siendo el de julio. Verificar siempre el
> **mtime del zip en `dist-testers/`**, no el del build.

## Build sin acceso a github.com (2026-08-20)

En la máquina de dev, la red corporativa empezó a **bloquear `github.com` y
`api.github.com`** (timeout; `registry.npmjs.org`, Google y
`objects.githubusercontent.com` sí responden). Eso **rompe el empaquetado** de
Electron aunque el binario ya esté en caché: `@electron/get` re-descarga
**siempre** `SHASUMS256.txt` desde GitHub para validar el artefacto —
`cacheMode: Bypass`, con el comentario explícito *"Never use the cache for
loading checksums"* (`ui/node_modules/@electron/get/dist/cjs/index.js`). Falla
todo el paso `Packaging application` con `connect ETIMEDOUT 140.82.114.4:443`.

- **Solución (opt-in, cero cambio por defecto):** `GENIUS_OFFLINE_BUILD=true`
  activa `cfg.download = { unsafelyDisableChecksums: true }` en
  `forge.config.ts`, reutilizando el zip ya verificado de
  `~/Library/Caches/electron` (están cacheados `electron-v41.0.0-darwin-arm64.zip`
  y `-x64.zip`). Sin la variable, el build valida como siempre.
  Uso: `GENIUS_OFFLINE_BUILD=true bash installer/build_corporate.sh arm64`.
- **Trampa de diagnóstico (costó ~40 min):** lanzar el build con
  `... | tail -6` hace que el código de salida observado sea el de `tail` (0),
  no el del build (1) → un build fallido se reporta como exitoso y se queda uno
  esperando un zip que nunca llega. **Redirigir a un log y leer `$?`**:
  `bash installer/build_corporate.sh arm64 > build.log 2>&1; echo "EXIT=$?"`.

## Pendientes (para cerrar antes/durante el piloto)

1. **Firma de código (macOS y Windows)** — camino limpio para producción.
   - *macOS*: Apple Developer ID + notarización → updates del binario no re-preguntan en
     el Keychain. En la PoC se acepta binario congelado (I5) + reset del secreto en updates.
   - *Windows*: **Azure Trusted Signing** (input `signing` del workflow). No es solo
     cosmético: un `.exe`/`.ps1` firmado evita SmartScreen, corre bajo AllSigned **sin** el
     truco de `install.cmd`, y **no lo marca el EDR**. Es la solución definitiva al
     problema de Execution Policy/EDR del piloto.
2. **Allowlist estricto de extensiones** (fase 2: host del YAML + URLs de los MCP +
   wildcard de dominios) si se quiere bloqueo real, no solo aviso.
3. **Prueba E2E en VM limpia** contra el gateway real. Parcial hecho (2026-07-21):
   provisioning + lectura del token por el binario instalado + chat autenticado
   (HTTP 200) OK en la máquina de dev. Falta VM limpia + adversary bloqueando de
   verdad + modelos dinámicos.
4. **Validar el instalable de Windows en una máquina real de Coppel** — el ZIP ya se
   generó y empaquetó (ver "Instalable de Windows" arriba). Falta probar `install.cmd`
   en un equipo corporativo real para ver si la **Execution Policy por GPO** y el **EDR**
   lo dejan correr; si no, firmar (pendiente #1) o pedir excepción a TI.
