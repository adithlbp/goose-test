# Resumen ejecutivo — Fork "Genius Assistant" sobre Goose

> Resumen de todos los cambios aplicados sobre Goose Desktop original para el
> piloto interno de Coppel. Para el detalle línea-por-línea ver `CHANGES_REVIEW.md`;
> para el diseño de credenciales `POC_DESIGN.md`; para el ciclo de vida del secreto
> `SECRET_LIFECYCLE.md`; para el blindaje de UI `LOCKDOWN.md`; para la política de
> seguridad `ADVERSARY_POLICY.md`. Fecha: 2026-07-20; actualizado 2026-07-21
> (instalables macOS arm64+Intel; token embebido ofuscado; **fix del 401**
> —provisioning robustecido—; default `gemini-3.5-flash`; skills CRUD; provider
> bloqueado en recetas; self-branding del agente vía override de `system.md`;
> postura de escritura del adversary = HOME permitido; handoff Windows).

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
| **Instaladores** | Wrappers corporativos + receta de build; repo apuntable por env | `installer/*`, `download_cli.sh`/`.ps1` | Scripts |

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

## Pendientes (para cerrar antes/durante el piloto)

1. **Firma Apple Developer ID (macOS)** — requisito de producción para que updates del
   binario no re-pregunten en el Keychain. En la PoC se acepta binario congelado (I5)
   + reset del secreto en updates. Windows: firma Azure Trusted Signing opcional (solo
   evita SmartScreen; no bloquea provisioning), ZIP portable como upstream.
2. **Allowlist estricto de extensiones** (fase 2: host del YAML + URLs de los MCP +
   wildcard de dominios) si se quiere bloqueo real, no solo aviso.
3. **Prueba E2E en VM limpia** contra el gateway real. Parcial hecho (2026-07-21):
   provisioning + lectura del token por el binario instalado + chat autenticado
   (HTTP 200) OK en la máquina de dev. Falta VM limpia + adversary bloqueando de
   verdad + modelos dinámicos.
4. **Generar el ZIP de Windows** — en CI (`bundle-desktop-genius-windows.yml`), en
   una VM, o con `installer/build_corporate_windows.sh` (Git Bash) delegando a
   alguien con Windows — y **validar `install_genius.ps1`** (no reproducible en macOS).
