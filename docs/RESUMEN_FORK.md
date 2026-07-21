# Resumen ejecutivo — Fork "Genius Assistant" sobre Goose

> Resumen de todos los cambios aplicados sobre Goose Desktop original para el
> piloto interno de Coppel. Para el detalle línea-por-línea ver `CHANGES_REVIEW.md`;
> para el diseño de credenciales `POC_DESIGN.md`; para el ciclo de vida del secreto
> `SECRET_LIFECYCLE.md`; para el blindaje de UI `LOCKDOWN.md`; para la política de
> seguridad `ADVERSARY_POLICY.md`. Fecha: 2026-07-20.

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
| **Marca** | "Genius Assistant" + paleta Coppel (azul `#1C42E8`, amarillo `#F0D224`) + logo de tres puntos, en textos/temas/iconos, 16 catálogos i18n | `package.json`, `index.html`, `main.ts`, `theme-tokens.ts`, `main.css`, `icons/Goose.tsx`, `images/*`, `i18n/messages/*` | Cosmético |
| **Provider fijo** | Provider "Genius" (OpenAI-compatible) auto-creado en el primer arranque, apuntando al gateway; onboarding omitido | `vite.main.config.mts`, `main.ts`, `ModelAndProviderContext.tsx` | Bundle/UI |
| **Bloqueo de config** | Provider y External Backend no editables; tabs Auth/Config ocultos; "managed by your organization" | `SettingsView.tsx`, `ProviderGrid.tsx`, `SwitchModelModal.tsx`, `ModelSettingsButtons.tsx`, `ModelsSection.tsx`, `ExternalBackendSection.tsx` | UI |
| **Seguridad** | Prompt-injection forzado ON + bloqueado; `adversary.md` distribuido en el instalable | `vite.main.config.mts`, `main.ts`, `forge.config.ts`, `installer/adversary.md` | Bundle/asset |
| **Credenciales** | API key provisionada vía ACP→Keychain (flujo oficial); helper por stdin | `installer/provision_secret.py`, `install_genius.sh`/`.ps1` | Instalador |
| **Updates/Telemetría** | UI de updates oculta + sin auto-descarga; telemetría off sin prompt; "Version" sin logo Block | `AppSettingsSection.tsx`, `main.ts`, `vite.main.config.mts` | Bundle/UI |
| **Modelos dinámicos** | Picker trae la lista viva del gateway (`/v1/models`) con fallback estático | `acp/providers.ts`, `modelInterface.ts` | UI |
| **Extensiones** | Modo "advertir" al conectar MCP externos | `vite.main.config.mts`, `installer/build_corporate.sh` | Bundle |
| **Skills** | Formulario para crear skills (nombre/cuándo/instrucciones) para usuarios no técnicos | `skills/SkillsView.tsx`, `acp/sources.ts` | UI |
| **Instaladores** | Wrappers corporativos + receta de build; repo apuntable por env | `installer/*`, `download_cli.sh`/`.ps1` | Scripts |

---

## Decisiones arquitectónicas complejas (el *porqué*)

### 1. Credenciales: ACP → Keychain (no env, no hardcode, no Keychain directo)

**Qué se hizo:** el instalador provisiona el API key ejecutando `goose acp` y
mandándole `_goose/unstable/config/upsert {isSecret:true}` por JSON-RPC; Goose lo
persiste en el Keychain con su propio `Config::set_secret()`.

**Por qué esta arquitectura y no las alternativas:**
- *No hardcode/env en claro* → fue el error de "Genius Code" (API key extraíble del
  binario). Evitado por diseño.
- *No escribir al Keychain directo desde el helper* → romper compatibilidad con cómo
  Goose lee sus secretos (nombre del item, ACL). Reutilizar el flujo oficial
  garantiza que **quien crea el secreto es la misma identidad que luego lo lee**.
- *No parchear `from_env`/core* → viola la regla de no tocar `crates/`.

Verificado en vivo: upsert → lectura enmascarada → item `svce="goose"` en Keychain,
sin `secrets.yaml`. El token viaja por **stdin** (nunca argv) para no exponerse en
`ps`/historial.

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
horneadas (`GOOSE_LOCK_PROVIDER`, `GOOSE_LOCK_BACKEND`, `SECURITY_PROMPT_ENABLED_OVERRIDE`).

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

> Nota de fragilidad conocida: este baile perdió el secreto en ciertos
> reinicios durante pruebas. Pendiente de endurecer antes del piloto.

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
  (`frozen_goose_darwin.sha256`, generado por `build_corporate.sh` desde el binario
  ya empaquetado) y provisiona si coincide. En Windows se quitó el gate:
  Credential Manager es por-usuario (sin ACL por-hash), provisionar es seguro.
- **Política corporativa unificada** en `installer/corporate_env.sh` (fuente única
  sourceada por macOS y por el CI de Windows → sin drift).
- **Red de seguridad del fallback**: `GOOSE_DEFAULT_PROVIDER=custom_genius` horneado
  (mitiga parcialmente la fragilidad del enlace §4 si el baile crear→enlazar falla).
- **Build de Windows**: `.github/workflows/bundle-desktop-genius-windows.yml`
  (adaptado de upstream; CI-only — goose.exe requiere cargo + MSVC). Produce ZIP
  portable con la política horneada; firma Azure opcional.

## Pendientes (para cerrar antes/durante el piloto)

1. **Firma Apple Developer ID (macOS)** — requisito de producción para que updates del
   binario no re-pregunten en el Keychain. En la PoC se acepta binario congelado (I5)
   + reset del secreto en updates. Windows: firma Azure Trusted Signing opcional (solo
   evita SmartScreen; no bloquea provisioning), ZIP portable como upstream.
2. **Endurecer el enlace del token** en el primer arranque (perdió el secreto en
   pruebas; el `GOOSE_DEFAULT_PROVIDER` horneado lo mitiga pero no lo cierra).
3. **Allowlist estricto de extensiones** (fase 2: host del YAML + URLs de los MCP +
   wildcard de dominios) si se quiere bloqueo real, no solo aviso.
4. **Prueba E2E en VM limpia** contra el gateway real (chat autenticado, modelos
   dinámicos, adversary bloqueando de verdad).
5. **Correr el CI de Windows** en un runner real y **validar `install_genius.ps1`**
   (no reproducible en macOS).
