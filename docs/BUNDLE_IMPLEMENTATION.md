# BUNDLE_IMPLEMENTATION — Bundle corporativo de Goose Desktop

Implementación de [CORPORATE_BUNDLE_PLAN.md](CORPORATE_BUNDLE_PLAN.md), ampliada con el provider corporativo con marca propia ("Genius", §6). Alcance ejecutado:

| Cambio del plan | Estado |
|---|---|
| C1 — Hornear `GOOSE_DEFAULT_PROVIDER` / `GOOSE_DEFAULT_MODEL` en build | ✅ Implementado (Opción A, `define` de Vite) |
| C2 — base_url corporativa hacia `goosed` | ✅ Implementado |
| C3 — Onboarding omitido | ✅ Automático (sin código, por diseño) |
| C4 — Provider bloqueado en UI | ❌ **No implementado** — excluido por restricción "no modificar providers" |
| C5 — Sin API key | ✅ Sin código (por diseño); el bundle no contiene ni escribe credenciales |

Restricciones respetadas: **cero cambios en `crates/goose`**, cero cambios en código de providers (Rust o UI), ninguna gestión de API key.

---

## 1. Archivos modificados

### 1.1 [`ui/desktop/vite.main.config.mts`](../ui/desktop/vite.main.config.mts) — C1

Nuevo bloque `corporateBundleDefines`: hornea en el bundle del proceso main las claves

- `GOOSE_DEFAULT_PROVIDER`
- `GOOSE_DEFAULT_MODEL`
- `GOOSE_DEFAULT_PROVIDER_HOST` (nueva, ver C2)
- `GOOSE_PREDEFINED_MODELS`

**Solo se hornean las que estén presentes y no vacías en el entorno de build** (`filter((key) => process.env[key])`). Diferencia deliberada frente al patrón previo de `GITHUB_OWNER` (que siempre reemplaza con un default):

- Build corporativo (CI exporta las variables) → los valores quedan **grabados en el binario**; el entorno del usuario final es irrelevante.
- Build normal (variables ausentes) → la expresión `process.env.X` **no se reemplaza** y se conserva el comportamiento actual de leer el entorno en runtime. Sin regresión para desarrollo ni para despliegues gestionados por MDM/env.

### 1.2 [`ui/desktop/src/main.ts`](../ui/desktop/src/main.ts) — C2

Tres ediciones puntuales:

1. `interface BundledConfig` ([main.ts:843-849](../ui/desktop/src/main.ts#L843-L849)): nuevo campo `defaultProviderHost?: string`.
2. `getBundledConfig()` ([main.ts:851-864](../ui/desktop/src/main.ts#L851-L864)): lee `process.env.GOOSE_DEFAULT_PROVIDER_HOST?.trim() || undefined`. El `trim() || undefined` normaliza cadena vacía/espacios a `undefined` — crítico, porque un `OPENAI_HOST=""` en el entorno de `goosed` haría pasar el check `configured` del servidor con un host inválido.
3. Objeto `env` de `startGooseServe` ([main.ts:1153-1159](../ui/desktop/src/main.ts#L1153-L1159)): añade `OPENAI_HOST: defaultProviderHost`.

No se tocó el bloque `//{env-macro-start}//…//{env-macro-end}//` (sigue disponible como ancla para forks que prefieran la Opción B del plan).

**Ningún otro archivo cambió.** `gooseServe.ts` no necesitó cambios: `buildGooseServeEnv` ya descarta las entradas `undefined` ([gooseServe.ts:309-313](../ui/desktop/src/gooseServe.ts#L309-L313)), así que en builds no corporativos la variable simplemente no se inyecta y un `OPENAI_HOST` del entorno del usuario sigue pasando intacto.

---

## 2. Cómo funciona la cadena completa (post-implementación)

```
Build CI corporativo
  exporta GOOSE_DEFAULT_PROVIDER / GOOSE_DEFAULT_MODEL / GOOSE_DEFAULT_PROVIDER_HOST
        │  (vite define — C1)
        ▼
main de Electron (valores literales en el bundle)
  ├─► appConfig → window.appConfig (renderer)          [flujo preexistente]
  └─► env de goosed: OPENAI_HOST=<host corporativo>    [C2, nuevo]
        │
        ▼
goosed: OpenAI cuenta como "configured" sin API key
  (OPENAI_HOST ≠ default — registrations.rs, sin cambios)
        │
        ▼
Primer arranque — OnboardingGuard (sin cambios):
  acpReadDefaults() vacío
   → getFallbackModelAndProvider() lee los defaults horneados
   → acpSaveDefaults(openai, <modelo>) — pasa la validación del servidor
   → config.yaml persiste provider activo + modelo
   → hasProvider = true → ONBOARDING OMITIDO
        │
        ▼
Peticiones LLM → resolve_base_url: OPENAI_HOST (env) tiene prioridad 1
   → todo el tráfico va al gateway corporativo. Sin API key en cliente.
```

Arranques posteriores cortan en el paso 1 (`config.yaml` ya tiene provider activo).

---

## 3. Cómo producir el bundle corporativo

En el job de CI que compila la app de escritorio, exportar antes del build de Electron/Forge:

```bash
export GOOSE_DEFAULT_PROVIDER="openai"
export GOOSE_DEFAULT_MODEL="gpt-4o"                                # debe existir en el catálogo del provider
export GOOSE_DEFAULT_PROVIDER_HOST="https://llm.corp.example.com"  # gateway corporativo
# Opcional: lista cerrada de modelos en el selector de la UI
export GOOSE_PREDEFINED_MODELS='[{"name":"gpt-4o","alias":"Corp GPT-4o","subtext":"Gateway corporativo"}]'
```

y ejecutar el empaquetado habitual (`ui/desktop`). Sin esas variables, el build resultante es idéntico al estándar.

Prueba local en desarrollo (mismas variables, modo runtime):

```bash
GOOSE_DEFAULT_PROVIDER=openai \
GOOSE_DEFAULT_MODEL=gpt-4o \
GOOSE_DEFAULT_PROVIDER_HOST=https://llm.corp.example.com \
just run-ui
```

## 4. Verificación sugerida (no ejecutada aquí)

1. `cd ui/desktop && pnpm run typecheck`
2. Arranque en limpio (sin `~/.config/goose/config.yaml` o con perfil temporal vía `GOOSE_PATH_ROOT`) con las variables del §3 → la app debe abrir directa al chat, sin pantalla de bienvenida.
3. `config.yaml` resultante debe contener el provider activo `openai` con el modelo corporativo, y **ningún** `OPENAI_API_KEY` en secretos.
4. Una petición de chat debe salir hacia el host corporativo (verificable en logs del gateway).
5. Arranque **sin** las variables y sin hornear → onboarding normal (regresión cero).

## 5. Provider con marca propia: `GOOSE_CUSTOM_PROVIDER` ("Genius")

Extensión posterior al plan: el provider visible debe llamarse **"Genius"** (OpenAI-compatible), no "OpenAI". Se reutiliza íntegro el mecanismo de **custom providers** existente — el mismo que el formulario "Add a custom provider" del onboarding: mismo endpoint ACP (`providersCustomCreate_unstable` → [`on_create_custom_provider`](../crates/goose/src/acp/server/providers.rs#L551)), mismo archivo resultante (`<config>/custom_providers/custom_genius.json`), mismo motor declarativo OpenAI. La única pieza nueva es el auto-rellenado en el primer arranque.

### 5.1 Variable nueva

`GOOSE_CUSTOM_PROVIDER` — JSON horneable/inyectable con la definición del provider:

```json
{"display_name":"Genius","api_url":"https://llm.corp.example.com","models":["genius-4"]}
```

Campos opcionales: `engine` (default `"openai"`), `base_path`, `headers`. Reglas del servidor (preexistentes): `api_url` debe ser URL http(s) válida y `models` no puede ir vacío. Se crea con `requires_auth: false` → **sin API key**, y por ello el provider cuenta como `configured` de inmediato.

### 5.2 Flujo en el primer arranque

1. `getFallbackModelAndProvider` ([`ModelAndProviderContext.tsx`](../ui/desktop/src/components/ModelAndProviderContext.tsx)) detecta `GOOSE_CUSTOM_PROVIDER`.
2. Busca un provider existente con ese `display_name`; si no está, lo crea vía el endpoint del formulario. Protección **single-flight**: en el arranque varios componentes disparan el fallback en paralelo y sin ella se creaban providers duplicados (bug detectado y corregido en prueba en vivo).
3. Fija como defaults el id devuelto (`custom_genius`) + `GOOSE_DEFAULT_MODEL` (o el primer modelo de la lista si no se define).
4. `OnboardingGuard` encuentra defaults persistidos → onboarding omitido.

En este modo **no se necesitan** `GOOSE_DEFAULT_PROVIDER` ni `GOOSE_DEFAULT_PROVIDER_HOST` (la base_url viaja dentro del JSON del provider). Ambos caminos coexisten: sin `GOOSE_CUSTOM_PROVIDER`, aplica el flujo OpenAI de §2.

### 5.3 Verificado en vivo

Arranque limpio con la variable → en ~2 s, sin intervención: `custom_providers/custom_genius.json` (único), `active_provider: custom_genius`, modelo `genius-4`, cero secretos. La UI muestra "Genius" como provider.

### 5.4 Receta de bundle "Genius"

```bash
cd ui/desktop
GOOSE_BUNDLE_NAME="Genius Assistant" \
GOOSE_CUSTOM_PROVIDER='{"display_name":"Genius","api_url":"https://gateway.corp.com","models":["genius-4"]}' \
pnpm run bundle:default
```

### 5.5 Bloqueo de UI en modo bundle

Cuando `GOOSE_CUSTOM_PROVIDER` está presente (`isProviderLockedByBundle()` en [`predefinedModelsUtils.ts`](../ui/desktop/src/components/settings/models/predefinedModelsUtils.ts)), Settings → Models oculta:

- la card **"Reset Provider and Model"** ([`ModelsSection.tsx`](../ui/desktop/src/components/settings/models/ModelsSection.tsx)) — evita que el usuario borre la selección y caiga al onboarding;
- el botón **"Configure providers"** ([`ModelSettingsButtons.tsx`](../ui/desktop/src/components/settings/models/subcomponents/ModelSettingsButtons.tsx)) — se suma a la condición de ocultación ya existente de `shouldShowPredefinedModels()`.

Además, en el modal **"Switch models"** ([`SwitchModelModal.tsx`](../ui/desktop/src/components/settings/models/subcomponents/SwitchModelModal.tsx)) el selector de **provider** queda `isDisabled` y no-clearable (el de modelo sigue activo).

En builds estándar (sin la variable) todos estos elementos siguen visibles/activos. Es bloqueo de UI, no enforcement (ver §6).

### 5.6 Modelos por fetch dinámico

No requiere código: el provider Genius se crea con `dynamic_models: None`, y `fetch_supported_models` ([`goose-providers/src/openai.rs`](../crates/goose-providers/src/openai.rs#L619)) con ese valor llama a `GET {base_url}/models` del gateway y solo usa la lista estática como **fallback ante 404**. Contra el gateway corporativo real, el selector de modelos se puebla con lo que responde el endpoint; el `models` del JSON (`["genius-4"]`) es únicamente el respaldo cuando el endpoint no existe.

### 5.7 Archivos tocados por §5

| Archivo | Cambio |
|---|---|
| [`vite.main.config.mts`](../ui/desktop/vite.main.config.mts) | +1 clave en `CORPORATE_BUNDLE_KEYS` |
| [`main.ts`](../ui/desktop/src/main.ts) | +1 campo `BundledConfig` / lectura / entrada `appConfig` |
| [`ModelAndProviderContext.tsx`](../ui/desktop/src/components/ModelAndProviderContext.tsx) | helpers de parseo + creación single-flight y rama inicial del fallback |
| [`predefinedModelsUtils.ts`](../ui/desktop/src/components/settings/models/predefinedModelsUtils.ts) | helper `isProviderLockedByBundle()` |
| [`ModelsSection.tsx`](../ui/desktop/src/components/settings/models/ModelsSection.tsx) | card de reset condicional |
| [`ModelSettingsButtons.tsx`](../ui/desktop/src/components/settings/models/subcomponents/ModelSettingsButtons.tsx) | botón "Configure providers" condicional |
| [`SwitchModelModal.tsx`](../ui/desktop/src/components/settings/models/subcomponents/SwitchModelModal.tsx) | selector de provider `isDisabled` en modo bundle |

Sin cambios en `crates/goose` ni en providers Rust. El fetch dinámico de modelos (§5.6) es comportamiento existente del provider declarativo.

## 6. Límites conocidos (heredados del plan)

- **Modelo fuera de catálogo**: si `GOOSE_DEFAULT_MODEL` no existe en el catálogo del provider, el guardado servidor lo rechaza y aparece el onboarding. Usar nombres canónicos.
- **El host horneado prevalece** sobre un `OPENAI_HOST` del entorno del usuario final (el `env` explícito de `startGooseServe` se aplica después de heredar `process.env`). Es el comportamiento deseado para un bundle corporativo.
- **Sin bloqueo de provider (C4)**: el usuario puede añadir/cambiar providers desde Settings. Quedó explícitamente fuera de este alcance; si se necesita, ver §3-C4 del plan (filtro de UI, no enforcement).
- `GOOSE_PREDEFINED_MODELS` debe ser JSON válido; si no lo es, el renderer lo ignora con un warning (comportamiento preexistente).
