# Prompt 03 — Provider corporativo preconfigurado (bundle por env, sin tocar core)

> Pégalo a un agente de código en el clon limpio. Objetivo: que la app arranque ya apuntando al gateway OpenAI-compatible corporativo, sin onboarding, sin tocar providers.

---

## Tarea

Preconfigura el provider corporativo **horneando valores en el bundle del proceso main de Electron** (mecanismo oficial `getBundledConfig`), de modo que:
- `GOOSE_PROVIDER` = `openai` (engine OpenAI-compatible).
- El host apunte al **gateway corporativo** (no a `api.openai.com`).
- El onboarding se **salte automáticamente** (por diseño, sin código).

**Cero cambios en `crates/`, cero cambios en el registro de providers, ninguna gestión de API key aquí** (el secreto lo provisiona el prompt 07).

## Idempotencia (léelo primero)
Antes de editar, verifica si ya está aplicado:
```bash
cd ui/desktop
grep -c 'corporateBundleDefines' vite.main.config.mts   # 0 = falta aplicar; >0 = ya está
grep -c 'defaultProviderHost' src/main.ts               # 0 = falta; 4 = ya está
```
Si ya están, **no repitas**. Los cambios de abajo son puntuales sobre estructura de upstream; si el upstream movió las líneas, ubícalas por contenido (no por número de línea).

## Contexto (mecanismo oficial)

- `getBundledConfig()` (`ui/desktop/src/main.ts`) ya expone `GOOSE_DEFAULT_PROVIDER`/`GOOSE_DEFAULT_MODEL`/`GOOSE_PREDEFINED_MODELS` desde `process.env`, y hay un patrón de build-time `define` en `vite.main.config.mts` (usado hoy para `GITHUB_OWNER`).
- Con `GOOSE_DEFAULT_PROVIDER`/`GOOSE_DEFAULT_MODEL` presentes, `getFallbackModelAndProvider` (`ModelAndProviderContext.tsx`) llama `acpSaveDefaults` y `OnboardingGuard` (`OnboardingGuard.tsx`) **salta el onboarding** — sin código nuevo.
- El provider `openai` cuenta como **"configured"** cuando `OPENAI_HOST` ≠ `https://api.openai.com`, **sin API key** (`crates/goose/src/providers/inventory/registrations.rs`, `openai_inventory().with_configured(...)`). Por eso basta pinear el host.

## Cambios exactos (2 archivos, `ui/desktop/`)

### 1. `vite.main.config.mts` — hornear valores en build
Añade un bloque que hornee en el bundle del main (solo si están presentes en el entorno de build, para no romper builds normales):
- `GOOSE_DEFAULT_PROVIDER`
- `GOOSE_DEFAULT_MODEL`
- `GOOSE_DEFAULT_PROVIDER_HOST` (nueva)
- `GOOSE_PREDEFINED_MODELS` (opcional)

Patrón: `define` de Vite con `filter((key) => process.env[key])` — si la variable no está en el build, la expresión `process.env.X` **no** se reemplaza y se conserva el comportamiento upstream (lee env en runtime). Sin regresión para dev/MDM.

### 2. `src/main.ts` — inyectar el host a `goosed`
- `interface BundledConfig`: nuevo campo `defaultProviderHost?: string`.
- `getBundledConfig()`: `defaultProviderHost: process.env.GOOSE_DEFAULT_PROVIDER_HOST?.trim() || undefined` (el `trim() || undefined` es **crítico**: un host vacío haría pasar el check `configured` con un valor inválido).
- Objeto `env` de la llamada a `startGooseServe(...)`: añade `OPENAI_HOST: defaultProviderHost`.

**No** tocar el bloque `//{env-macro-start}//…//{env-macro-end}//` (queda como ancla alternativa). `gooseServe.ts` **no** necesita cambios (`buildGooseServeEnv` ya descarta entradas `undefined`).

## Build corporativo

El CI/instalador exporta antes de `pnpm run make`:
```bash
export GOOSE_DEFAULT_PROVIDER=openai
export GOOSE_DEFAULT_MODEL=<modelo-del-gateway>
export GOOSE_DEFAULT_PROVIDER_HOST=https://gateway.interno.coppel.com   # sin /v1 final; ver nota
```
> Nota sobre el host: `OPENAI_HOST` se combina con `OPENAI_BASE_PATH` (default `v1/chat/completions`). Si el gateway usa una ruta distinta, considerar `OPENAI_BASE_URL` en su lugar (`openai_def.rs` `resolve_base_url`). Los modelos dinámicos vía `/v1/models` funcionan por defecto (`goose-providers/src/openai.rs` `fetch_supported_models`).

## Verificación
- Build corporativo → abrir app en perfil limpio → **no aparece onboarding**; el provider activo es `openai` apuntando al gateway.
- El model picker lista modelos del gateway (`/v1/models`).
- Build normal (sin las env vars) → comportamiento idéntico a upstream (lee env en runtime).
- `pnpm run typecheck` pasa.

## No hacer
- No crear un provider declarativo nuevo ni tocar `provider_registry`/`init.rs` (innecesario; el bundle basta).
- No hornear el API key aquí (va por el prompt 07).
- No implementar el bloqueo del selector de provider en la UI (excluido por "no modificar providers"; si se requiere, es un cambio de UI aparte — ver prompt 04).

Referencia con diffs: [`CORPORATE_BUNDLE_PLAN.md`](../CORPORATE_BUNDLE_PLAN.md) y [`BUNDLE_IMPLEMENTATION.md`](../BUNDLE_IMPLEMENTATION.md).
