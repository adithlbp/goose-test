# PROVIDER_DIAGNOSTICS — Plan de trazabilidad de provider/modelo/credenciales

**Objetivo**: logs que respondan, en cualquier instalación (estándar o bundle corporativo):

1. ¿Qué provider quedó seleccionado?
2. ¿Qué modelo?
3. ¿De dónde salió el provider? (env / config / bundle / selección manual)
4. ¿De dónde salió la API key? (env / keyring / archivo de secretos / ausente)
5. ¿Qué base_url efectiva se está usando y de dónde salió?

**Restricciones**: cero cambio de comportamiento (solo lecturas + emisión de logs), **nunca** imprimir valores de secretos. Documento de plan — no implementa nada.

Relacionado: [CORPORATE_BUNDLE_PLAN.md](CORPORATE_BUNDLE_PLAN.md), [BUNDLE_IMPLEMENTATION.md](BUNDLE_IMPLEMENTATION.md).

---

## 1. Dónde se resuelve hoy cada dato (anatomía)

La resolución está repartida en tres capas. Cada dato tiene un punto único donde el origen es conocible; ahí es donde hay que loguear.

### 1.1 Provider seleccionado y su origen

[`crates/goose/src/config/providers.rs:64-72`](../crates/goose/src/config/providers.rs#L64-L72) — `get_active_provider`, prioridad:

| Prioridad | Fuente | Valor de `provider_source` propuesto |
|---|---|---|
| 1 | env `GOOSE_PROVIDER` | `env` |
| 2 | `config.yaml` clave `active_provider` | `config:active_provider` |
| 3 | `config.yaml` clave legacy `GOOSE_PROVIDER` | `config:legacy_key` |

Aguas arriba, quién escribió `active_provider` (capa desktop):

- **Bundle corporativo**: `getFallbackModelAndProvider` ([`ModelAndProviderContext.tsx:145-156`](../ui/desktop/src/components/ModelAndProviderContext.tsx#L145-L156)) persiste los defaults horneados → origen `bundled_default`.
- **Onboarding manual**: `handleConfigured` ([`OnboardingGuard.tsx:115-125`](../ui/desktop/src/components/onboarding/OnboardingGuard.tsx#L115-L125)) → origen `user_onboarding`.
- **Settings**: cambio de modelo/provider en la UI → origen `user_settings`.

Una vez persistido, el servidor ya no distingue estos tres casos — por eso el origen "quién lo escribió" debe loguearse **en el renderer en el momento de escribirlo**, y el origen "de dónde se leyó" en el servidor.

### 1.2 Modelo y su origen

[`providers.rs:74-87`](../crates/goose/src/config/providers.rs#L74-L87) — `get_active_model`: env `GOOSE_MODEL` → `providers.<name>.model` de `config.yaml` → clave legacy `GOOSE_MODEL`. Mismos tres valores de origen que §1.1.

### 1.3 Origen de la API key (sin imprimir jamás su valor)

[`openai_def.rs:93-96`](../crates/goose/src/providers/openai_def.rs#L93-L96) llama a `Config::get_secrets` ([`base.rs:865-878`](../crates/goose/src/config/base.rs#L865-L878)): si `OPENAI_API_KEY` está en el entorno, **todos** los secretos salen del entorno; si no, de secret storage. El secret storage es keyring del SO **o** archivo `secrets.yaml` cuando el keyring está deshabilitado (`GOOSE_DISABLE_KEYRING`, [`base.rs:190-194`](../crates/goose/src/config/base.rs#L190-L194)).

`get_secrets` **no expone** de dónde sacó el valor. Para no cambiar comportamiento, el origen se determina en el *call site* con lecturas puras:

| `api_key_source` | Condición (solo lecturas) |
|---|---|
| `env` | `env::var("OPENAI_API_KEY").is_ok()` |
| `keyring` | hay valor, no vino de env, keyring habilitado |
| `secrets_file` | hay valor, no vino de env, keyring deshabilitado |
| `absent` | sin valor → el provider queda en `AuthMethod::NoAuth` ([`openai_def.rs:110-113`](../crates/goose/src/providers/openai_def.rs#L110-L113)) — el caso del bundle corporativo |

### 1.4 base_url efectiva y su origen

[`openai_def.rs:254-282`](../crates/goose/src/providers/openai_def.rs#L254-L282) — `resolve_base_url`, cuatro ramas excluyentes que son exactamente los valores de `base_url_source`:

| Prioridad | Rama | `base_url_source` |
|---|---|---|
| 1 | env `OPENAI_HOST` | `env:OPENAI_HOST` (así llega el host del bundle corporativo) |
| 2 | `OPENAI_BASE_URL` (env o config) | `openai_base_url` |
| 3 | config `OPENAI_HOST` | `config:OPENAI_HOST` |
| 4 | `https://api.openai.com` | `default` |

`base_path` se resuelve justo después ([`openai_def.rs:77-90`](../crates/goose/src/providers/openai_def.rs#L77-L90)) y conviene incluirlo en la misma línea de log.

---

## 2. Puntos de log propuestos

Principio: **una línea estructurada por evento de resolución**, no logging por petición. Cuatro puntos, uno por capa donde el dato es conocible.

### P1 — `goosed`: construcción del provider (el punto más valioso)

En `from_env` de [`openai_def.rs`](../crates/goose/src/providers/openai_def.rs#L50), tras resolver host, base_path y secretos — un único `tracing::info!` estructurado:

```
tracing::info!(
    target: "provider_diagnostics",
    provider = "openai",
    host = %redact_url(&parsed.host),
    base_path = %base_path,
    base_url_source = %base_url_source,
    api_key_source = %api_key_source,
    auth_mode = if api_key_present { "bearer" } else { "no_auth" },
    custom_headers = custom_headers.as_ref().map_or(0, |h| h.len()),
    "provider resolved"
);
```

- `base_url_source`: recomputable en el call site con los mismos checks de `resolve_base_url` (solo lecturas), **o** —variante preferible— añadiendo un campo informativo `source` a `ParsedBaseUrl` (struct interna del módulo; añadir un campo que nadie más lee no altera comportamiento).
- `api_key_source`: según la tabla de §1.3. **Solo el enum, jamás el valor ni su longitud ni prefijo.**
- `custom_headers`: solo el número de cabeceras (los nombres pueden ser sensibles en gateways; el valor seguro es el count).

### P2 — `goosed`: lectura/escritura de defaults (ACP)

En [`acp/server/config.rs`](../crates/goose/src/acp/server/config.rs#L172-L241):

- `on_defaults_read`: `info!(target: "provider_diagnostics", provider, model, provider_source, model_source, "defaults read")` — con los orígenes de §1.1/§1.2, recomputados con los mismos checks de `get_active_provider`/`get_active_model` (solo lecturas de env/config).
- `on_defaults_save`: `info!(..., provider, model, "defaults saved")` — deja rastro de *cuándo* cambió la selección persistida.

### P3 — `goosed`: sesión

En `update_provider` ([`agent.rs:2905`](../crates/goose/src/agents/agent.rs#L2905)): `info!(target: "provider_diagnostics", session_id, provider = %provider_name, model = %model_config.model_name, "session provider set")`. Ata provider+modelo a cada sesión concreta.

### P4 — Desktop: quién escribió la selección

- **Main de Electron** ([`main.ts`](../ui/desktop/src/main.ts), logger `electron-log` ya presente): al arrancar, una línea con la config de bundle efectiva: `defaultProvider`, `defaultModel`, `defaultProviderHost` (redactada según §3) y si se inyectó `OPENAI_HOST` al spawn de `goosed`.
- **Renderer**:
  - `getFallbackModelAndProvider` ([`ModelAndProviderContext.tsx:145`](../ui/desktop/src/components/ModelAndProviderContext.tsx#L145)): `console.info('[provider_diagnostics] applying bundled defaults', { provider, model })` antes del `acpSaveDefaults` → marca origen `bundled_default`.
  - `handleConfigured` ([`OnboardingGuard.tsx:115`](../ui/desktop/src/components/onboarding/OnboardingGuard.tsx#L115)): línea equivalente con origen `user_onboarding`.
  - `checkProvider` ([`OnboardingGuard.tsx:65-101`](../ui/desktop/src/components/onboarding/OnboardingGuard.tsx#L65-L101)): una línea con la ruta tomada: `already_configured` | `bundled_fallback_applied` | `onboarding_shown`.

---

## 3. Reglas de seguridad (obligatorias)

1. **Prohibido loguear**: valor de `OPENAI_API_KEY` (ni longitud, ni prefijo, ni hash), valores de `OPENAI_CUSTOM_HEADERS`, cualquier campo marcado `secret` en config keys, el `GOOSE_SERVER__SECRET_KEY`.
2. **Redacción de URLs** (`redact_url`, helper nuevo): eliminar `userinfo` (`https://user:pass@host` → `https://host`) y **valores** de query params (`?api-version=2024&token=abc` → `?api-version=…&token=…` o solo nombres). `parse_base_url` ya separa `query_params` — algunos gateways ponen tokens en la query, así que se loguean solo los nombres.
3. Los orígenes se loguean como **enums cerrados** (tablas de §1), nunca interpolando valores de entorno arbitrarios.
4. Nivel `INFO` con `target: "provider_diagnostics"` — greppable (`grep provider_diagnostics`) y filtrable por `RUST_LOG=provider_diagnostics=off` si algún despliegue lo exige, sin tocar el resto del logging.
5. Frecuencia acotada: P1 solo en construcción de provider, P2 en lectura/guardado de defaults, P3 por sesión, P4 en arranque/onboarding. Nada en el hot path de peticiones LLM.

## 4. Ejemplo de traza completa (bundle corporativo, primer arranque)

```
[main]     provider_diagnostics bundle: provider=openai model=gpt-4o host=https://llm.corp.example.com injected=OPENAI_HOST
[renderer] [provider_diagnostics] onboarding route: bundled_fallback_applied
[renderer] [provider_diagnostics] applying bundled defaults {provider: openai, model: gpt-4o}
[goosed]   provider_diagnostics defaults saved provider=openai model=gpt-4o
[goosed]   provider_diagnostics provider resolved provider=openai host=https://llm.corp.example.com
           base_path=v1/chat/completions base_url_source=env:OPENAI_HOST api_key_source=absent
           auth_mode=no_auth custom_headers=0
[goosed]   provider_diagnostics session provider set session_id=… provider=openai model=gpt-4o
```

Con esta traza, "¿por qué está pegando a api.openai.com?" o "¿de dónde salió esta key?" se responde con un grep, sin exponer un solo secreto.

## 5. Cambios por archivo (resumen)

| Punto | Archivo | Naturaleza |
|---|---|---|
| P1 | `crates/goose/src/providers/openai_def.rs` (+ helper `redact_url`) | 1 log + campo informativo opcional en `ParsedBaseUrl` |
| P2 | `crates/goose/src/acp/server/config.rs` | 2 logs |
| P3 | `crates/goose/src/agents/agent.rs` | 1 log |
| P4 | `ui/desktop/src/main.ts`, `ModelAndProviderContext.tsx`, `OnboardingGuard.tsx` | 4 logs |

## 6. Notas y decisiones abiertas

- **P1–P3 tocan `crates/goose`.** La restricción "no tocar crates/goose" era del alcance del bundle ([BUNDLE_IMPLEMENTATION.md](BUNDLE_IMPLEMENTATION.md)); esta tarea no puede cumplir los puntos 4 y 5 del objetivo sin entrar ahí, porque la API key y la base_url **solo** se resuelven en `goosed`. Desde Electron solo se puede loguear lo que se *inyecta*, no lo que se *resolvió*. Si la restricción sigue vigente, el alcance queda limitado a P4 (parcial).
- Providers no-OpenAI: mismo patrón replicable en cada `*_def.rs`; este plan cubre OpenAI por ser el provider del bundle corporativo. Extensión posterior = copiar el patrón P1.
- `AGENTS.md` pide no añadir logging salvo errores o eventos de seguridad: la línea `provider_diagnostics` califica como evento de seguridad/auditoría (qué endpoint recibe el tráfico y qué credencial se usa), y §3.4 da la vía para apagarla.
