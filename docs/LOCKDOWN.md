# Blindaje de la UI y del comportamiento (fase piloto)

> Documenta la fase de "lockdown" del fork Genius Assistant (2026-07-18 → 2026-07-20):
> ocultar/deshabilitar todo lo que permita a un usuario romper la configuración
> corporativa o degradar la seguridad, más la política de seguridad por defecto.
> Complementa `CHANGES_REVIEW.md` (estado general), `POC_DESIGN.md` (arquitectura)
> y `SECRET_LIFECYCLE.md` (secreto). **No modifica `crates/`.**

## Principio

Todo se activa con **env vars horneadas por bundle** (`vite.main.config.mts` →
`getBundledConfig` → `additionalArguments` → `window.appConfig`), reutilizando el
patrón oficial `*_OVERRIDE`/`appConfig.get(...)`. En builds normales (sin las env)
el comportamiento es idéntico a upstream — regresión cero.

## Banderas de política (horneadas en el build corporativo)

| Env var | Efecto | Mecanismo |
|---|---|---|
| `GOOSE_CUSTOM_PROVIDER` | Provider "Genius" fijo (JSON) | auto-creación + pin |
| `GOOSE_DEFAULT_MODEL` | Modelo por defecto | oficial |
| `GOOSE_LOCK_PROVIDER` | Bloquea toda gestión/cambio de provider | UI (este doc) |
| `GOOSE_LOCK_BACKEND` | Bloquea External Backend | UI (este doc) |
| `SECURITY_PROMPT_ENABLED_OVERRIDE=true` | Prompt-injection ON + toggle bloqueado | oficial `*_OVERRIDE` |
| `GOOSE_VERSION` | Oculta la sección de updates; muestra "Version" | oficial (bundles) |
| `GOOSE_DISABLE_AUTO_DOWNLOAD=true` | Motor de updates no descarga binarios | oficial (env updater) |
| `GOOSE_TELEMETRY_ENABLED=false` | Telemetría off + sin prompt de consentimiento | env-first (config) |

Todas viven en `installer/build_corporate.sh` y en `CORPORATE_BUNDLE_KEYS`
(`vite.main.config.mts`).

## Provider fijo (`GOOSE_LOCK_PROVIDER`) — dónde se blinda

El provider corporativo es un **custom provider** editable/borrable desde varias
superficies; la precedencia env-first NO lo protege (su URL vive en
`custom_genius.json`). Por eso el pin es de UI, en cada punto de entrada:

| Superficie | Archivo:línea | Comportamiento con lock |
|---|---|---|
| Grid de providers | `providers/ProviderGrid.tsx:116,274-277` | Filtra a **solo** el provider del bundle (por `display_name`) |
| Crear provider | `providers/ProviderGrid.tsx` (tarjeta "Add") | No se renderiza |
| Editar/borrar provider | `providers/ProviderGrid.tsx` (`configureProviderViaModal`) | no-op |
| Aviso managed-by-org | `providers/ProviderGrid.tsx` | Texto "managed by your organization" |
| Selector en "Switch models" | `models/subcomponents/SwitchModelModal.tsx:262,836-837` | `isDisabled`, sin botón limpiar |
| "Use other provider" | `models/subcomponents/SwitchModelModal.tsx:491` | Opción omitida |
| Botón "Configure providers" | `models/subcomponents/ModelSettingsButtons.tsx:27,46` | Oculto |
| Card "Reset Provider and Model" | `models/ModelsSection.tsx:29,114` | Oculta |
| Tab Auth (Provider Credentials) | `SettingsView.tsx:229,295` | Oculto — permitía **borrar la credencial** del Keychain |
| Configuration Editor | `SettingsView.tsx:309` | Oculto — permitía sobrescribir config del provider |

> El tab **Auth** era el hueco más peligroso: dejaba borrar la credencial
> provisionada con un clic, rompiendo la auth. Con el lock desaparece.

## External Backend (`GOOSE_LOCK_BACKEND`)

- Tab "External Backend" oculto (`SettingsView.tsx:203,270`).
- Complementa el bloqueo visual dentro del panel (`app/ExternalBackendSection.tsx`,
  añadido en la fase anterior) por si el panel se alcanza por deep-link.
- Guard de tab activo: si un deep-link apunta a un tab oculto, se cae a Models
  (`SettingsView.tsx:130-138`).

## Updates (`GOOSE_VERSION` + `GOOSE_DISABLE_AUTO_DOWNLOAD`)

- **UI**: upstream oculta toda la sección de updates cuando `GOOSE_VERSION` está
  definida (comportamiento oficial de bundles); en su lugar muestra "Version".
- **Version**: se quitó el logo de Block (imports + observer de tema eliminados,
  menos código que upstream); ahora muestra el texto "Genius Assistant "
  `GOOSE_VERSION` (`app/AppSettingsSection.tsx:533-536`).
- **Motor**: `GOOSE_DISABLE_AUTO_DOWNLOAD=true` (env oficial del updater) impide
  descargar/reemplazar el binario — además protege el invariante I5 (binario
  congelado, `POC_DESIGN.md` §1.4).

## Telemetría (`GOOSE_TELEMETRY_ENABLED=false`)

- El prompt "Help improve…" aparece solo cuando `GOOSE_TELEMETRY_ENABLED` está sin
  definir. Horneando el valor al env de `goosed` (`main.ts:1211`), la lectura
  env-first pre-responde el consentimiento: sin prompt, telemetría off, y el
  toggle de Settings queda funcionalmente pineado.

## Adversary mode por defecto en el instalable

- `installer/adversary.md` se empaca como recurso del `.app`
  (`forge.config.ts:9`, `extraResource`).
- `main.ts:886` (`syncBundledAdversaryPolicy`) sincroniza ese recurso al config
  dir del usuario en cada arranque de la app empaquetada (macOS `~/.config/goose`,
  Windows `%APPDATA%\Block\goose\config`, respetando `GOOSE_PATH_ROOT`).
  Idempotente; la organización es la fuente de verdad (restaura ediciones locales).
- Detalle de la política y su cobertura: ver `ADVERSARY_POLICY.md`.

## Verificación

- `pnpm run typecheck`, `eslint`, `prettier` — OK en todos los archivos tocados.
- Visual (dev): relanzar con las env vars (ver `build_corporate.sh` o el comando
  de prueba) → Settings solo con **Models · Chat · Prompts · Keyboard · App**;
  sin diálogo de telemetría; Version = "Genius Assistant <version>"; provider fijo.
- Pendiente E2E (requiere gateway alcanzable): chat autenticado y lista dinámica
  de modelos. `api.genius.coppel.services` no es alcanzable desde la red de
  desarrollo — verificar en VPN corporativa.
