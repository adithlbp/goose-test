# Revisión de cambios — Fork "Genius Assistant" (piloto Coppel)

> Documento de revisión de la ejecución de los prompts 01–08 (`docs/prompts/`).
> Fecha: 2026-07-17. Cada sección tiene checkbox `[ ]` para marcar lo ya revisado.
> Convención: los cambios marcados **[PREEXISTENTE]** ya estaban en el árbol al
> iniciar esta sesión (se auditaron y verificaron); los **[NUEVO]** se hicieron
> en esta sesión.

## Constraints globales — cumplimiento

- [ ] **Cero cambios en `crates/`** (core, Config, SecretStorage, providers, registro). Solo se leyó como evidencia.
- [ ] Identificadores funcionales intactos: `KEYRING_SERVICE`, rutas `Block/goose`, `goose://`, variables `GOOSE_*`, `appId` `io.github.block.Goose`, clases CSS `goose-*`.
- [ ] Todo lo horneable usa el patrón condicional de Vite `define` (`filter(key => process.env[key])`): sin la variable en el build, comportamiento upstream intacto.

---

## Prompt 01 — Build binario ligero ✅

**Sin cambios de archivos** (solo artefactos de build, git-ignored).

- Comando: `cargo build --release -p goose-cli --bin goose --no-default-features --features code-mode,tui,aws-providers,telemetry,nostr,otel,rustls-tls,system-keyring,update`
- Verificado antes de compilar: las 9 features existen en `crates/goose-cli/Cargo.toml` y `default` = esas + `local-inference`.
- Resultado: `Finished release in 5m 58s`; **0** menciones a `llama-cpp-sys-2` en el log (sin CMake).
- Copiado a `ui/desktop/src/bin/goose` (224 MB, git-ignored). `--version` → `1.43.0`.
- `system-keyring` incluido (requisito del prompt 07).

**Revisión:**
- [ ] El binario en `ui/desktop/src/bin/goose` responde `--version`.

---

## Prompt 02 — UI / Branding ✅ [PREEXISTENTE — auditado]

Todos los ítems 1–13 del prompt ya estaban aplicados. Auditoría completa:

| Ítem | Archivo | Estado |
|---|---|---|
| 1 | `ui/desktop/package.json` — `genius-assistant-app` / `Genius Assistant` / versión 1.43.0 intacta | [ ] |
| 2 | `ui/desktop/index.html` — `<title>Genius Assistant</title>` | [ ] |
| 3 | `ui/desktop/src/main.ts` — About (:757), notificación (:812), error (:1187), mapa zh-CN claves+valores (:98,102,128), `menuT(...)` coincidentes (:2650, :2759). "Hide" lo resuelve `translateMenuLabels` (:154-168) sobre la etiqueta que Electron genera con `productName` | [ ] |
| 4 | `OnboardingGuard.tsx` — bienvenida y error de conexión | [ ] |
| 5 | `forge.config.ts` — `NSMicrophoneUsageDescription` / `NSAppleEventsUsageDescription` | [ ] |
| 6 | `forge.deb.desktop` / `forge.rpm.desktop` — solo `Name=`; `Exec=/Icon=` intactos | [ ] |
| 7 | `defaultMessage` inline — 0 residuos de marca (solo `.goosehints`, `GOOSE_*`, nombres de archivo) | [ ] |
| 8 | 16 catálogos `src/i18n/messages/*.json` — 0 marca en valores; `.goosehints` ×176 y `goose://` ×80 preservados | [ ] |
| 9 | `theme-tokens.ts` — tokens `info`: `#1c42e8` (light) / `#1ca8f7` (dark) | [ ] |
| 10 | `main.css` — `--color-block-teal: #1c42e8`; highlights `rgba(240,210,36,…)` | [ ] |
| 11 | `Goose.tsx` — tres círculos `currentColor`; exports `Goose`/`Rain` conservados | [ ] |
| 12 | `icon.svg` (`#1C42E8`+`#F0D224`) / `glyph.svg` (`#101010`) | [ ] |
| 13 | Binarios de iconos regenerados (timestamps posteriores a los SVG) | [ ] |

Verificación corrida: `typecheck` 0 · `i18n:compile` 0 · grep de residuos limpio.

- [ ] **Pendiente visual**: `pnpm run start-gui` — título, About, onboarding, menús, colores, icono Dock.

---

## Prompt 03 — Provider corporativo por bundle ✅

### [PREEXISTENTE — auditado]
- `ui/desktop/vite.main.config.mts:5-22` — `CORPORATE_BUNDLE_KEYS` + `corporateBundleDefines` (patrón condicional).
- `main.ts` — `defaultProviderHost` en `BundledConfig` (:846), lectura con `?.trim() || undefined` (:859), `OPENAI_HOST` al env de `startGooseServe` (:1167). Bloque `//{env-macro-*}//` intacto (:852-854).

### [NUEVO] Cableado §5 "Genius" (BUNDLE_IMPLEMENTATION.md §5)
**Motivo**: la clave `GOOSE_CUSTOM_PROVIDER` estaba horneada en vite pero **nada la consumía** (código muerto). El doc §5 la describe como implementada; el cableado no estaba en este clon. Decisión del piloto: implementarla.

- [ ] `main.ts:847` — `customProvider?: string` en `BundledConfig`.
- [ ] `main.ts:860` — `customProvider: process.env.GOOSE_CUSTOM_PROVIDER?.trim() || undefined`.
- [ ] `main.ts:967` — expuesto al renderer como `GOOSE_CUSTOM_PROVIDER` en `appConfig`.
- [ ] `ModelAndProviderContext.tsx:70-146` — tipo `BundledCustomProviderSpec`; `getBundledCustomProvider()` con **single-flight** (:81-95, evita providers duplicados en arranque — bug documentado en §5.2); `setupBundledCustomProvider()` (:97-146):
  1. Parsea el JSON del bundle.
  2. Busca provider existente por `display_name` (`acpListProviderDetails`).
  3. Si no existe → `acpCreateCustomProviderFromRequest` con `requires_auth: false` (endpoint oficial del formulario "Add custom provider").
  4. **Enlace del token**: intenta `acpUpdateCustomProviderFromRequest(..., requires_auth: true)` **sin** `api_key` — el servidor solo lo acepta si `CUSTOM_GENIUS_API_KEY` ya está en el Keychain (provisionado por el instalador). Si no hay secreto → catch → provider queda sin auth.
  5. `acpSaveDefaults(providerId, model)` → `OnboardingGuard` salta el onboarding.
- [ ] `ModelAndProviderContext.tsx:210-220` — `getFallbackModelAndProvider` intenta primero el custom provider; si falla, resetea el single-flight (reintentos de OnboardingGuard) y cae al camino upstream `GOOSE_DEFAULT_PROVIDER`/`MODEL`.

**Evidencia core (solo lectura, sin modificar):**
- `crates/goose/src/config/declarative_providers.rs:83` → id `custom_genius`; `:131-133` → secreto `CUSTOM_GENIUS_API_KEY`.
- `crates/goose/src/acp/server/providers.rs:612-623` + `declarative_providers.rs:242-248` → update con auth sin api_key reutiliza el secreto almacenado (o error limpio).

**Decisión registrada**: el gateway (llm-gw) **sí** consume API token → se eligió "§5 + token Keychain" (no el modo sin auth del doc §5 tal cual, que dejaría los requests sin `Authorization`).

**Implicaciones**:
- [ ] El helper del prompt 07 se invoca con `--key CUSTOM_GENIUS_API_KEY` cuando el bundle usa `GOOSE_CUSTOM_PROVIDER`.
- [ ] El instalador **debe provisionar antes del primer arranque** (el enlace ocurre al crear el provider).

---

## Prompt 04 — Settings bloqueados ✅

### Nivel A (funcional) — sin cambios
Precedencia env-first de `Config::get_param/get_secret` (upstream). No se tocó.

### [NUEVO] Nivel B (visual) — `GOOSE_LOCK_BACKEND`
- [ ] `vite.main.config.mts:11` — clave horneable.
- [ ] `main.ts:1283` — pasada al renderer vía `additionalArguments`.
- [ ] `ExternalBackendSection.tsx:96` — `isLockedByOrg`; switch + 3 inputs `disabled` (:204 y `disabled={isSaving || isLockedByOrg}` en inputs); aviso *"This setting is managed by your organization…"* (:194-198, mensaje nuevo `externalBackendSection.managedNotice` :84-87). El panel se deshabilita, no se oculta.

### [NUEVO] Blindaje del provider — `GOOSE_LOCK_PROVIDER` (extensión aprobada)
**Motivo**: con §5, la URL del gateway vive en `custom_genius.json` (editable/borrable desde Settings) — env-first **no** la protege. Riesgo: usuario borra/edita el provider → estado roto.

- [ ] `vite.main.config.mts:12` + `main.ts:1284` — cableado de la política.
- [ ] `ProviderGrid.tsx:113` — `isLockedByOrg`.
- [ ] `:140-142` — `configureProviderViaModal` no-op (bloquea editar/borrar el custom provider **y** el modal de config de cualquier provider, que permitiría sobrescribir el API key provisionado).
- [ ] `:279-283` — tarjeta "Add Provider" no se renderiza.
- [ ] `:297` — `hasNoMatches` ajustado al conteo sin la tarjeta.
- [ ] `:321-324` — aviso *"Providers are managed by your organization and cannot be changed."* (mensaje `providerGrid.managedNotice` :55-58).
- **Deliberadamente NO bloqueado**: `SwitchModelModal` (elegir modelo) — bloquear ahí rompería el selector de modelos del gateway; cambiar a otro provider no configurado falla solo (sin key, y el modal de config está bloqueado).

---

## Prompt 05 — Adversary Mode ✅

**Cero código** — mecanismo upstream verificado (`adversary_inspector.rs:106-139`, `:386-388`).

- [ ] `installer/adversary.md` [NUEVO] — frontmatter `tools: shell, computercontroller__automation_script` (= `DEFAULT_TOOLS`) + reglas BLOCK/ALLOW del prompt.

**Matices a comunicar al piloto** (propiedades del mecanismo, no defectos):
1. Solo se revisan las tools del frontmatter; escrituras vía extensión `developer` sin `shell` no pasan por el inspector.
2. **Fail-open**: si el LLM no responde (red/rate limit), la acción se permite (`:472-490`). Es best-effort, no sandbox.

- [ ] **Pendiente runtime**: log `Adversary inspector enabled from …` + bloqueo real de un `shell` fuera del proyecto (requiere instalación + sesión con provider).

---

## Prompt 06 — Prompt Injection forzada ✅

- [ ] `vite.main.config.mts:13-14` [NUEVO] — `SECURITY_PROMPT_ENABLED_OVERRIDE` y `SECURITY_COMMAND_CLASSIFIER_ENABLED_OVERRIDE` horneables.
- [ ] `main.ts:1168-1172` [NUEVO — **fix crítico**] — overrides pasados como **literales** en el env de `startGooseServe`.

**Por qué el fix**: `buildGooseServeEnv` construye el env de `goosed` con `...process.env` (spread runtime, `gooseServe.ts:298`) que Vite `define` **no puede** reemplazar. Sin el fix, en el build sellado la UI mostraba el toggle bloqueado+ON (el literal de `:1280` sí se hornea) pero `goosed` (`env::var`, `security/mod.rs:18-24`) no veía el override → **detección realmente OFF con UI diciendo ON**. Con el fix, ambos literales se hornean; en builds normales quedan `undefined` y `buildGooseServeEnv` los descarta (regresión cero; único call site de producción `main.ts:1159`).

- [ ] **Pendiente visual**: Settings → Security con `SECURITY_PROMPT_ENABLED_OVERRIDE=true`: toggle ON + deshabilitado + texto managed-by-org; log `Security scanner initialized`.

---

## Prompt 07 — API Key vía ACP → Keychain 🔴 BLOQUEADO (mecanismo ✅ probado en vivo)

**Sin cambios de código** (arquitectura reutiliza el flujo oficial íntegro).

**Prueba en vivo (2026-07-17, binario del prompt 01):**

| Check | Resultado |
|---|---|
| `initialize` handshake | ✓ `goose 1.43.0` |
| `_goose/unstable/config/upsert {isSecret:true}` | ✓ `result: {}` |
| Lectura enmascarada | ✓ `"spike-te************"` |
| Item Keychain | ✓ `svce="goose", acct="secrets"` |
| Sin `~/.config/goose/secrets.yaml` | ✓ |
| `remove` + relectura | ✓ `value: null` |

- [ ] `installer/provision_secret.py` [NUEVO] — copia exacta de `spike/provision_secret.py` (93 líneas, sin cambios).

**🔴 Bloqueo documentado**: firma de código **sin confirmar**. Con firma ad-hoc, la ACL del Keychain se ata al hash del binario → **cada update re-pregunta autorización** (SPIKE_RESULTS §5.b, demostrado). No se configuró `osxSign`/`osxNotarize` (requiere `APPLE_TEAM_ID` real). **Desbloqueo**: confirmar Apple Developer ID + cert Windows con Mauricio/organización, o aceptar formalmente piloto de instalación única sin updates.

**Nota menor**: el helper recibe `--token` por argv (visible en `ps` durante la ejecución). Mejorable a env/stdin si se desea.

---

## Prompt 08 — Instaladores corporativos ✅ (paso de token gateado)

### [NUEVO] Cambios mínimos a upstream
- [ ] `download_cli.sh:57` — `REPO="${GOOSE_REPO:-aaif-goose/goose}"` (era hardcoded; sin la env, idéntico a upstream).
- [ ] `download_cli.ps1:27` — mismo override.

### [NUEVO] `installer/` — assets corporativos
- [ ] `install_genius.sh` — macOS/Linux. Modo `desktop` (zip interno → `/Applications`; binario `Contents/Resources/bin/goose` = **misma identidad que crea y lee el item del Keychain**) o `cli` (delega en `download_cli.sh` con `CONFIGURE=false` — sin wizard — + `GOOSE_REPO` + `GOOSE_PROVIDER=openai`). Paso 2: `adversary.md` → `~/.config/goose/`. Paso 3: provisioning **gateado** por `GENIUS_SIGNING_READY=true` (mensaje explícito del bloqueo del 07); clave default `CUSTOM_GENIUS_API_KEY`.
- [ ] `install_genius.ps1` — Windows equivalente; `adversary.md` → `%APPDATA%\Block\goose\config\`.
- **Token**: nunca en los scripts; llega por `GENIUS_TOKEN` (env, canal interno controlado); el helper lo pasa por stdin JSON-RPC a `goose acp`; jamás se persiste en claro (lección Genius Code). Token único por plataforma (decisión reunión 2026-06-24).

**Verificado**: `bash -n` OK; dry-run en HOME aislado (fallo limpio sin URL ✓, adversary.md colocado ✓, gate `[GATED]` disparado ✓).
**Pendiente**: `.ps1` sin validar (no hay pwsh local); E2E en VM limpia (checks 1–6 del prompt; #3 y #6 requieren desbloquear firma).

---

## Decisiones tomadas en la sesión (con quién/cuándo)

1. **Implementar §5 "Genius"** (usuario, hoy) — el cableado no existía pese a que el doc lo daba por hecho.
2. **§5 + token del Keychain** (usuario: "se tiene un api token, se consume un llm-gw") — evita el conflicto §5-sin-auth vs prompt 07.
3. **Blindar provider en UI** (`GOOSE_LOCK_PROVIDER`) (usuario) — cierre del hueco que §5 abre en la premisa env-first del prompt 04.
4. **Firma: "no se sabe aún"** → bloqueo formal del 07 (memoria guardada).
5. **08 parcial con gate** (usuario, opción 1).

## Adenda 2026-07-18 — cierre de pendientes de la fase de diseño

- [ ] **Pin duro del provider** [NUEVO]: `ProviderGrid.tsx` — con `GOOSE_LOCK_PROVIDER`
  activo, la grid muestra **únicamente** el provider del bundle (filtro por
  `display_name` del JSON `GOOSE_CUSTOM_PROVIDER`); no se puede lanzar, configurar
  ni crear ningún otro. (Nota: la afirmación original "SwitchModelModal no
  necesitó cambios" resultó incompleta — ver adenda 2026-07-20.)
- [ ] **Helper stdin** [NUEVO]: `provision_secret.py` acepta `--token-stdin`
  (spike + installer sincronizados); `install_genius.sh`/`.ps1` pipean el token
  (`printf '%s\n' "$TOKEN" | … --token-stdin`) — cierra la exposición argv/ps.
  Probado en vivo: upsert por stdin → lectura enmascarada → remove, OK.
- [ ] **Receta de build corporativo** [NUEVO]: `installer/build_corporate.sh` —
  valores reales del piloto (Genius / `https://api.genius.coppel.services` /
  `gemini-3.1-pro-preview`), locks + security override, `GOOSE_BUNDLE_NAME`, y
  **guard I5**: verifica el sha256 del binario congelado
  (`1a645dc3…f858e566`) antes de empaquetar; aborta con instrucciones (P3) si cambió.
- Diseño final y runbook: ver `POC_DESIGN.md` y `SECRET_LIFECYCLE.md` §9.

## Adenda 2026-07-20 — blindaje de UI y política de seguridad

> Detalle completo con archivo:línea en **`LOCKDOWN.md`** y **`ADVERSARY_POLICY.md`**.
> Todo por env horneadas; cero cambios en `crates/`.

- [ ] **Pin del provider — superficies que faltaban** [NUEVO]: el pin del 18/07 solo
  cubría la grid. Se completó en: `SwitchModelModal` (selector `isDisabled`, sin
  "Use other provider"), `ModelSettingsButtons` (botón "Configure providers"
  oculto), `ModelsSection` (card "Reset Provider and Model" oculta), `SettingsView`
  (tabs **Auth** y **Configuration Editor** ocultos). El tab Auth era el hueco más
  grave: permitía borrar la credencial del Keychain.
- [ ] **External Backend oculto** [NUEVO]: tab fuera con `GOOSE_LOCK_BACKEND`
  (`SettingsView.tsx`), + guard de deep-link a tab oculto → Models.
- [ ] **Updates** [NUEVO]: UI oculta con `GOOSE_VERSION` (mecanismo oficial de
  bundles) + `GOOSE_DISABLE_AUTO_DOWNLOAD=true` (motor no descarga; protege I5).
  Sección "Version" sin logo de Block → texto "Genius Assistant <version>".
- [ ] **Telemetría** [NUEVO]: `GOOSE_TELEMETRY_ENABLED=false` horneada → sin diálogo
  de consentimiento, telemetría off (env-first).
- [ ] **Adversary por defecto en el instalable** [NUEVO]: `adversary.md` empacado
  como recurso (`forge.config.ts:9`) + sync al config dir en cada arranque
  (`main.ts:886`, `syncBundledAdversaryPolicy`). La organización es fuente de verdad.
- [ ] **Adversary endurecido** [NUEVO]: frontmatter ahora
  `shell, write, edit, computercontroller__automation_script` — cierra el gap de
  `write`/`edit` (verificado: `developer` tiene `unprefixed_tools: true` → nombres a
  secas hacen match). Reglas nuevas: credenciales sin importar ubicación, archivos
  de arranque de shell. Ver `ADVERSARY_POLICY.md`.
- Verificado: typecheck/eslint/prettier OK. Límite conocido: adversary es
  **fail-open** con el gateway caído (permite) — propiedad del mecanismo.

## Adenda 2026-07-20b — modelos dinámicos en el picker (corrección)

> Corrige una conclusión errónea previa ("los custom providers son estáticos por
> diseño"). El mecanismo dinámico **sí existe**; nuestra UI llamaba el endpoint
> equivocado. Probado empíricamente con binario real + mock `/v1/models`.

- **Hallazgo** (probado, `scratchpad/mock_models_test.py`): para un custom provider,
  `providers/list` (inventario) devuelve solo los modelos tecleados —está gated por
  `dynamic_models`, que el create ACP fija a `None`—, **pero**
  `providers/supported-models/list` hace fetch en vivo a `/v1/models` y devuelve la
  lista real del gateway. El binario 1.43.0 ya expone ese endpoint.
- **Causa del síntoma**: `fetchModelsForProviders` (UI) usaba solo la vía de
  inventario (estática). Por eso el picker mostraba únicamente el modelo por defecto.
- **Fix** [NUEVO, UI, cero `crates/`]: `acpListProviderSupportedModels`
  (`acp/providers.ts`) + `fetchModelsForProviders` (`modelInterface.ts`) ahora
  prefiere el fetch en vivo y cae al inventario/estático ante error (offline-safe).
- **URL del bundle**: `https://api.genius.coppel.services` (sin `/v1`) es correcta —
  probado que goose añade `/v1/models` solo; con o sin `/v1` resuelve igual.
- Requiere gateway alcanzable (VPN). Sin red, cae limpio a la lista estática.

## Adenda 2026-07-21 — instalables generados, gate re-encuadrado y token embebido

> Corrige afirmaciones de los prompts 07/08 arriba (gate por firma, token por env,
> `provision_secret.py` "sin cambios"). El estado vigente es este.

- **Gate del provisioning re-encuadrado (corrige `:168`)**: ya **no** se gatea por
  `GENIUS_SIGNING_READY`. `install_genius.sh` verifica el **hash del build bendecido**
  (`frozen_goose_darwin_{arm64,x64}.sha256`, generados por `build_corporate.sh`); el
  binario instalado debe coincidir con **alguno**. Escape hatch
  `GENIUS_ALLOW_UNVERIFIED=true`. En Windows se quitó el gate (CredMan sin ACL por-hash).
- **Token embebido ofuscado (corrige `:170`)**: por defecto viene en
  `genius_token.enc` (junto al instalador), no por `GENIUS_TOKEN` env (que ahora es
  solo para pruebas). `embed_token.py` (dueño del token, stdin) + `genius_token_codec.py`
  (SHA256-keystream XOR + HMAC, stdlib) + `provision_secret.py --token-enc` (decode
  in-memory). Ofuscación, no cifrado — riesgo aceptado (SECRET_LIFECYCLE §2.1).
- **`provision_secret.py` ya NO es copia exacta del spike (corrige `:153`)**: añade
  `--token-enc` y **redacta** el token en el log del upsert (antes lo imprimía en claro).
- **Build multi-arch**: `build_corporate.sh [arm64|x64]` + `corporate_env.sh` (política
  única). Generados y verificados: `Genius Assistant.zip` (arm64, 188 MB) y
  `Genius Assistant_intel_mac.zip` (x64, 205 MB). Intel usa el binario oficial x86_64
  v1.43.0 (descargado, no compilado). Config horneada verificada en ambos `app.asar`.
- **Handoff Windows**: `build_corporate_windows.sh` (Git Bash) + workflow de CI. El
  app bundle no lleva token → seguro compartir el repo con quien compila.

## Adenda 2026-07-21b — provisioning sin Python y `~/Applications`

> Feedback del piloto: (1) `ditto: /Applications: Operation not permitted` en Macs
> corporativas; (2) muchos usuarios no tienen Python. Ambos resueltos.

- **Instalación en `~/Applications`** (no `/Applications`): evita el EPERM por TCC/
  permisos de admin en Macs gestionadas. La ACL del Keychain sigue atada al hash del
  binario, no a la ruta → sin efecto en el gate I5.
- **Provisioning nativo, sin Python** — se eliminaron `provision_secret.py`,
  `genius_token_codec.py`, `embed_token.py`:
  - **Descifrado**: `openssl` (macOS, nativo) / `.NET Aes` (Windows PowerShell, nativo).
  - **Guardado**: se maneja `goose acp` (JSON-RPC) por pipe — bash con FIFO + kill,
    PowerShell con `System.Diagnostics.Process` + stdin. `goose` no tiene comando CLI
    de secreto (`goose --help` solo expone `configure`/`acp`/…), así que el ACP sigue
    siendo la vía oficial; solo cambió el cliente (shell nativo en vez de Python).
  - **Formato del blob**: `genius_token.enc` pasó de XOR+HMAC (Python) a
    `keyhex:ivhex:ct_b64` **AES-256-CBC** (openssl ⇄ .NET compatibles). Generado por
    `embed_token.sh`. Sigue siendo ofuscación (riesgo aceptado, §2.1).
- **Verificado end-to-end en macOS** (HOME aislado + `GOOSE_DISABLE_KEYRING`): embed →
  decode (openssl) → upsert por pipe → secreto guardado idéntico al original.

## Pendientes globales

- [ ] Decisión Developer ID (macOS) → firma estable + `osxSign`/`osxNotarize` (ya gated tras `APPLE_TEAM_ID`) + prueba build-A→build-B firmados. **Nota**: el gate del 08 ya NO depende de esto (se re-encuadró al hash I5, ver adenda 2026-07-21).
- [ ] `pnpm run start-gui` — verificación visual (branding, locks, toggle seguridad).
- [ ] E2E en VM limpia contra gateway real (onboarding saltado, chat autenticado, model picker con `/v1/models`).
- [ ] Validar `install_genius.ps1` en Windows/pwsh.
- [x] Receta de build corporativo: **hecha** — `installer/corporate_env.sh` (política única) + `build_corporate.sh [arm64|x64]` (macOS) + `build_corporate_windows.sh`/workflow (Windows). Ver adenda 2026-07-21.
