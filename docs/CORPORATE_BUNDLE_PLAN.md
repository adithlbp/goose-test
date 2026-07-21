# CORPORATE_BUNDLE_PLAN — Goose Desktop preconfigurado

**Objetivo**: distribuir Goose Desktop de forma que arranque ya configurado con:

| Requisito | Estado actual |
|---|---|
| Provider OpenAI por defecto | ✅ Mecanismo existe (`GOOSE_DEFAULT_PROVIDER`) |
| base_url corporativa | ⚠️ Funciona vía env del SO; falta vía bundle |
| Modelo por defecto | ✅ Mecanismo existe (`GOOSE_DEFAULT_MODEL`) |
| Onboarding omitido | ✅ Automático si el provider queda "configured" |
| Provider bloqueado | ❌ No existe mecanismo; requiere cambio de UI |
| Sin API key en el bundle | ✅ Nada del flujo exige API key si hay host corporativo |

**Alcance**: solo análisis y plan. No implementa nada.

---

## 1. Cómo funciona hoy

### 1.1 `getBundledConfig()` — origen de los valores

[`ui/desktop/src/main.ts:850-860`](../ui/desktop/src/main.ts#L850-L860):

```ts
const getBundledConfig = (): BundledConfig => {
  //{env-macro-start}//
  //needed when goose is bundled for a specific provider
  //{env-macro-end}//
  return {
    defaultProvider: process.env.GOOSE_DEFAULT_PROVIDER,
    defaultModel: process.env.GOOSE_DEFAULT_MODEL,
    predefinedModels: process.env.GOOSE_PREDEFINED_MODELS,
    version: process.env.GOOSE_VERSION,
  };
};
```

Dos hechos clave:

1. **Hoy lee `process.env` en runtime** del proceso main de Electron. Si el usuario final arranca la app con esas variables en su entorno, funciona sin tocar nada.
2. Los marcadores `//{env-macro-start}// … //{env-macro-end}//` son el punto de anclaje pensado para inyectar asignaciones en build-time ("needed when goose is bundled for a specific provider"), **pero no existe en este árbol ningún script que los reemplace** (ya verificado en [DESIGN_REVIEW_APIKEY.md](DESIGN_REVIEW_APIKEY.md)). El patrón hermano que sí hornea valores en build es [`ui/desktop/vite.main.config.mts:5-9`](../ui/desktop/vite.main.config.mts#L5-L9), que usa `define` de Vite para `GITHUB_OWNER`, `GITHUB_REPO` y `GOOSE_BUNDLE_NAME`.

### 1.2 Propagación al renderer

- Los valores se destructuran en [`main.ts:862`](../ui/desktop/src/main.ts#L862) y entran al objeto `appConfig` ([`main.ts:953-965`](../ui/desktop/src/main.ts#L953-L965)) como `GOOSE_DEFAULT_PROVIDER`, `GOOSE_DEFAULT_MODEL`, `GOOSE_PREDEFINED_MODELS`.
- `appConfig` viaja a cada ventana vía `webPreferences.additionalArguments` ([`main.ts:1248`](../ui/desktop/src/main.ts#L1248), [`main.ts:1525`](../ui/desktop/src/main.ts#L1525), [`main.ts:3001`](../ui/desktop/src/main.ts#L3001)).
- El preload lo expone como `window.appConfig.get(key)` ([`ui/desktop/src/preload.ts:348-355`](../ui/desktop/src/preload.ts#L348-L355)).

### 1.3 `GOOSE_DEFAULT_PROVIDER` / `GOOSE_DEFAULT_MODEL` — el fallback

[`ui/desktop/src/components/ModelAndProviderContext.tsx:145-156`](../ui/desktop/src/components/ModelAndProviderContext.tsx#L145-L156):

```ts
const getFallbackModelAndProvider = useCallback(async () => {
  const provider = window.appConfig.get('GOOSE_DEFAULT_PROVIDER') as string;
  const model = window.appConfig.get('GOOSE_DEFAULT_MODEL') as string;
  if (provider && model) {
    await acpSaveDefaults(provider, model);  // persiste en config.yaml vía ACP
  }
  return { model, provider };
}, []);
```

`acpSaveDefaults` ([`ui/desktop/src/acp/providers.ts:177-180`](../ui/desktop/src/acp/providers.ts#L177-L180)) llama a `defaultsSave_unstable`, atendido en el servidor por `on_defaults_save` ([`crates/goose/src/acp/server/config.rs:183-241`](../crates/goose/src/acp/server/config.rs#L183-L241)), que **valida antes de persistir**:

1. El provider debe existir en el inventario.
2. El provider debe estar **`configured`** — si no: error `"Provider is not configured"`.
3. El modelo debe ser el `default_model` del provider **o estar en su lista de modelos** — si no: error `"Model '…' is not available"`.
4. Si pasa, `set_active_provider` ([`crates/goose/src/config/providers.rs:89-97`](../crates/goose/src/config/providers.rs#L89-L97)) escribe en `config.yaml` el provider activo y su entrada `{enabled, model, configured}`.

### 1.4 Cuándo OpenAI cuenta como "configured" (la pieza crítica sin API key)

[`crates/goose/src/providers/inventory/registrations.rs:56-66`](../crates/goose/src/providers/inventory/registrations.rs#L56-L66):

```rust
.with_configured(|| {
    if let Ok(host) = config.get_param::<String>("OPENAI_HOST") {
        if host != "https://api.openai.com" {
            return true;   // host corporativo ⇒ configurado SIN API key
        }
    }
    config.get_secret::<serde_json::Value>("OPENAI_API_KEY").is_ok()
})
```

**Un `OPENAI_HOST` distinto del default hace que OpenAI cuente como configurado sin API key.** Y `Config::get_param` consulta primero la variable de entorno del proceso `goosed` y después `config.yaml` ([`crates/goose/src/config/base.rs:733-735`](../crates/goose/src/config/base.rs#L733-L735)).

⚠️ **Matiz importante**: este check mira **solo `OPENAI_HOST`**, no `OPENAI_BASE_URL`. La resolución de URL en runtime ([`crates/goose/src/providers/openai_def.rs:254-282`](../crates/goose/src/providers/openai_def.rs#L254-L282)) tiene prioridad `OPENAI_HOST` (env) → `OPENAI_BASE_URL` (env/config) → `OPENAI_HOST` (config) → default. Para lograr *a la vez* la URL corporativa y el estado "configured", la variable correcta es **`OPENAI_HOST`** (opcionalmente con `OPENAI_BASE_PATH` si el gateway no usa `v1/chat/completions`).

### 1.5 `OnboardingGuard` — cómo se decide omitir el onboarding

[`ui/desktop/src/components/onboarding/OnboardingGuard.tsx:65-101`](../ui/desktop/src/components/onboarding/OnboardingGuard.tsx#L65-L101), envuelve la app en [`App.tsx:639`](../ui/desktop/src/App.tsx#L639). Secuencia de `checkProvider()`:

1. `acpReadDefaults()` — si `config.yaml` ya tiene provider activo → `hasProvider = true` → **renderiza la app, onboarding omitido**.
2. Si no, `getFallbackModelAndProvider()` — lee los defaults del bundle e **intenta persistirlos** (§1.3).
3. Relee `acpReadDefaults()`; si ahora hay provider **y** modelo → onboarding omitido.
4. Si algo falló (típicamente el check `configured` de §1.4, o modelo no válido) → muestra la pantalla de bienvenida con `ProviderSelector`.

Conclusión: **el onboarding se omite solo cuando la cadena completa funciona** — defaults presentes *y* provider "configured" *y* modelo válido. No hace falta ningún flag adicional "skip onboarding".

### 1.6 `GOOSE_PREDEFINED_MODELS` (relacionado, ya existente)

JSON de `Model[]` (`{name, alias?, subtext?}`) parseado en [`predefinedModelsUtils.ts:4-18`](../ui/desktop/src/components/settings/models/predefinedModelsUtils.ts#L4-L18). Cuando está presente, el selector de modelos ([`SwitchModelModal.tsx`](../ui/desktop/src/components/settings/models/subcomponents/SwitchModelModal.tsx)) muestra esa lista cerrada. Es un **bloqueo parcial de modelos a nivel UI** que ya existe y sirve al caso corporativo.

### 1.7 Entorno del backend `goosed`

El main de Electron lanza `goosed` heredando **todo** `process.env` ([`ui/desktop/src/gooseServe.ts:297-298`](../ui/desktop/src/gooseServe.ts#L297-L298)) más un objeto `env` explícito que hoy solo lleva `GOOSE_PATH_ROOT` ([`main.ts:1149-1153`](../ui/desktop/src/main.ts#L1149-L1153)). Por eso `OPENAI_HOST` puesto en el entorno del SO ya llega a `goosed` hoy; pero un bundle autocontenido no puede depender del entorno del usuario.

---

## 2. Lo que ya funciona sin tocar código

Si IT puede controlar el entorno o el filesystem del usuario, **cero cambios**:

- **Vía variables de entorno del SO** (MDM/GPO/launchd): `GOOSE_DEFAULT_PROVIDER=openai`, `GOOSE_DEFAULT_MODEL=<modelo>`, `OPENAI_HOST=https://llm.corp.example.com` → primer arranque salta onboarding y persiste los defaults.
- **Vía `config.yaml` pre-sembrado** (`~/.config/goose/config.yaml`): con el provider activo y `OPENAI_HOST` ya escritos, el paso 1 de §1.5 corta de inmediato.

Ambas requieren gestión externa de la máquina. El resto del documento cubre el caso "el instalador ya lo trae todo".

---

## 3. Cambios mínimos requeridos (bundle autocontenido)

### C1 — Hornear `GOOSE_DEFAULT_PROVIDER` y `GOOSE_DEFAULT_MODEL` en el build

No existe el script que rellene el bloque env-macro. Dos opciones, ambas mínimas:

- **Opción A (recomendada)**: añadir dos entradas `define` en [`vite.main.config.mts`](../ui/desktop/vite.main.config.mts), siguiendo el patrón ya existente de `GOOSE_BUNDLE_NAME`:
  `'process.env.GOOSE_DEFAULT_PROVIDER': JSON.stringify(process.env.GOOSE_DEFAULT_PROVIDER || '')` (ídem para modelo). El CI corporativo exporta las variables al compilar. Cero cambios en `main.ts`.
- **Opción B**: commitear asignaciones dentro del bloque `//{env-macro-start}//…//{env-macro-end}//` de `getBundledConfig()` en el fork corporativo (los marcadores actúan como cerca de merge).

Archivos: `ui/desktop/vite.main.config.mts` **o** `ui/desktop/src/main.ts`. Nada más.

### C2 — base_url corporativa hacia `goosed`

La pieza que falta: el bundle debe hacer llegar `OPENAI_HOST` al proceso `goosed`.

- Extender `BundledConfig` con un campo (p. ej. `defaultProviderHost`, leído de `process.env.GOOSE_DEFAULT_PROVIDER_HOST` y horneado igual que C1).
- Añadirlo al objeto `env` de la llamada a `startGooseServe` en [`main.ts:1149-1153`](../ui/desktop/src/main.ts#L1149-L1153) como `OPENAI_HOST` (y opcional `OPENAI_BASE_PATH`).

Efecto doble sin más cambios: `resolve_base_url` usa ese host (prioridad 1) **y** el check `configured` de §1.4 devuelve `true` sin API key. Si el gateway exige cabeceras propias, existe `OPENAI_CUSTOM_HEADERS` (secreto ya soportado por el provider) — fuera de alcance aquí porque no se incluye credencial en el bundle.

Archivos: `ui/desktop/src/main.ts` (2 puntos). **Cero cambios en `crates/goose`.**

### C3 — Onboarding omitido

**Sin cambios.** Con C1 + C2, la secuencia de §1.5 lo omite automáticamente en el primer arranque.

### C4 — Provider bloqueado ("si aplica")

Hoy **no existe** ningún mecanismo: `ProviderSelector` (onboarding) y la sección de providers de Settings listan todo lo que devuelve `acpListProviderDetails()`. Cambio mínimo, solo UI:

- Nueva variable horneada (p. ej. `GOOSE_LOCKED_PROVIDER=openai`) expuesta vía `appConfig` como las demás.
- Filtrar por ella la lista en [`ProviderSelector.tsx:74`](../ui/desktop/src/components/onboarding/ProviderSelector.tsx#L74) y en la vista de providers de Settings; opcionalmente ocultar el cambio de provider en `SwitchModelModal`.
- Complementar con `GOOSE_PREDEFINED_MODELS` (§1.6), que ya restringe el selector de modelos sin código nuevo.

⚠️ Esto es **bloqueo de UI, no enforcement**: el usuario con acceso a `config.yaml` o a la CLI puede cambiar de provider. Un bloqueo real exigiría validación en `goosed` (fuera del alcance "mínimo").

### C5 — Sin API key

**Sin cambios y sin acción.** Ningún punto del flujo escribe ni requiere `OPENAI_API_KEY` cuando el host corporativo está presente (§1.4). El bundle no contiene credenciales; la autenticación queda del lado del gateway corporativo.

---

## 4. Riesgos y validaciones

| Riesgo | Detalle | Mitigación |
|---|---|---|
| Modelo rechazado | `on_defaults_save` exige que `GOOSE_DEFAULT_MODEL` exista en el catálogo del provider (§1.3, punto 3). Un nombre de modelo interno desconocido rompe el auto-skip y aparece el onboarding. | Usar un nombre de modelo del catálogo OpenAI, o verificar en el gateway que expone nombres canónicos. |
| Usar `OPENAI_BASE_URL` en vez de `OPENAI_HOST` | La URL funcionaría, pero el provider **no** contaría como "configured" sin API key (§1.4) → onboarding aparece. | Usar siempre `OPENAI_HOST` para el bundle. |
| Refactor mueve el bloque env-macro | Solo afecta a la Opción B de C1. | Preferir Opción A (`define` de Vite). |
| Bloqueo de provider percibido como seguridad | C4 es cosmético. | Documentarlo así ante IT; enforcement real = cambio de servidor. |

## 5. Resumen de archivos a tocar

| Cambio | Archivo | Naturaleza |
|---|---|---|
| C1 | `ui/desktop/vite.main.config.mts` (o `main.ts` bloque env-macro) | 2 líneas `define` |
| C2 | `ui/desktop/src/main.ts` (`BundledConfig` + `env` de `startGooseServe`) | ~4 líneas |
| C3 | — | ninguno |
| C4 | `ProviderSelector.tsx`, vista providers de Settings, (`SwitchModelModal.tsx`) | filtro UI |
| C5 | — | ninguno |

`crates/goose` no se toca en ningún caso.

---
*Documentos relacionados: [DESIGN_REVIEW_APIKEY.md](DESIGN_REVIEW_APIKEY.md), [INVESTIGACION_APIKEY_ARQUITECTURA.md](INVESTIGACION_APIKEY_ARQUITECTURA.md).*
