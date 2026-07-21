# SPIKE_HELPER_ACP.md — Provisioning del API key vía `goose acp` → `Config::set_secret` → Keychain

**Estado**: spike de validación. No es implementación de producción.
**Método**: toda afirmación cita `archivo:línea` de este árbol. Lo no verificable desde el repo se marca **[NO DEMOSTRADO]**.
**Arquitectura bajo prueba**:
```
Installer → Corporate Helper → spawn "goose acp"
          → JSON-RPC initialize
          → _goose/unstable/config/upsert (isSecret=true)
          → on_config_upsert → Config::set_secret()
          → Keychain / Credential Manager / Secret Service
          → (después) Goose Desktop normal lee vía Config::get_secret()
```
El helper **nunca** llama a la Security framework / Keychain API directamente. Siempre persiste Goose.

---

## H1 — El helper puede ejecutar Goose ACP sin intervención del usuario ✅ DEMOSTRADO

**Comando exacto**: `goose acp` (o `cargo run -p goose-cli -- acp`).
- Entry point: `cli.rs:2231` → `Some(Command::Acp { builtins }) => goose::acp::server::run(builtins).await`.
- `run()` (`crates/goose/src/acp/server.rs:3188-3204`): `info!("listening on stdio")`, usa `tokio::io::stdin()`/`stdout()`, crea `AcpServer::new(... goose_platform: GoosePlatform::GooseCli ...)` (`:3194-3202`) y `serve(agent, incoming, outgoing)` (`:3204`).

**Transporte**: JSON-RPC 2.0 **delimitado por saltos de línea** sobre stdin/stdout (NO framing LSP `Content-Length`). Evidencia: el cliente de ejemplo del propio repo `test_acp_client.py:55,62` escribe `request_str + '\n'` y lee `stdout.readline()`. No hay auth en el transporte stdio (a diferencia de `goose serve` HTTP, que exige `GOOSE_SERVER__SECRET_KEY`).

**Handshake `initialize`** (`test_acp_client.py:86-95`):
```json
{"jsonrpc":"2.0","id":1,"method":"initialize",
 "params":{"protocolVersion":"v1","clientCapabilities":{},
           "clientInfo":{"name":"corp-helper","version":"1.0.0"}}}
```
- Handler: `on_initialize` (`server.rs:2256-2307`). Devuelve `InitializeResponse::new(args.protocol_version)` (echo de la versión, `:2300`) con `agent_info(Implementation::new("goose", …))` (`:2301`), `agent_capabilities(...)` (`:2302`) y `auth_methods([...])` (`:2303`).
- Versión de protocolo: los tests usan `ProtocolVersion::LATEST` (`server.rs:4041,4061`; harness `tests/acp_fixtures/server.rs:278`). El ejemplo Python usa la string `"v1"`. **[NO DEMOSTRADO]** que `"v1"` sea idéntico al valor de wire de `ProtocolVersion::LATEST` sin ejecutarlo — el spike debe confirmar el string exacto ejecutando o inspeccionando el schema.

**Orden correcto de mensajes**: `initialize` (id=1) → esperar `initializeResult` → luego cualquier método custom. **NO se requiere `session/new`** para config/upsert (ver H2).

---

## H2 — Guardar `OPENAI_API_KEY` como secreto sin sesión de chat ✅ DEMOSTRADO

**Método wire**: `_goose/unstable/config/upsert` (`crates/goose-sdk-types/src/custom_requests.rs:521-529`):
```rust
#[request(method = "_goose/unstable/config/upsert", response = EmptyResponse)]
pub struct ConfigUpsertRequest { pub key: String, pub value: Value, #[serde(default)] pub is_secret: bool }
```
Mensaje (camelCase por `#[serde(rename_all="camelCase")]`, `:523`):
```json
{"jsonrpc":"2.0","id":2,"method":"_goose/unstable/config/upsert",
 "params":{"key":"OPENAI_API_KEY","value":"sk-corp-…","isSecret":true}}
```

**Call stack completo (demostrado):**
1. Dispatch por nombre de método: `dispatch_custom_request` (`acp/server/custom_dispatch.rs:6-21`) → `handle_custom_request(method, params)` → matcher generado por macro (`JsonRpcMessage::matches_method`). **No hay gate de sesión en el dispatch.**
2. Handler: `dispatch_config_upsert` (`custom_dispatch.rs:406-412`) → `on_config_upsert` (`acp/server/config.rs:109-138`).
3. `on_config_upsert`: para `key` que no sea `GOOSE_PROVIDER`/`GOOSE_MODEL` (`config.rs:115-132`), cae a `config.set(&req.key, &req.value, req.is_secret)` (`config.rs:134-136`).
4. `self.config()` = **`Config::global()`** (`server.rs:976-978`) → no depende de sesión.
5. `Config::set(key, val, is_secret=true)` (`base.rs:706-715`) → `self.set_secret(key, value)` (`base.rs:711`) → `mutate_secrets` → `write_all_secrets` → backend Keyring (`base.rs:889-912`).

**Prueba de que NO requiere sesión**: el test `test_raw_config_and_secret_methods_are_removed` (`tests/acp_custom_requests_test.rs:1004-1022`) llama `send_custom(conn.cx(), "_goose/config/upsert", {})` **sin** `new_session()` — el dispatch responde (con error, porque ese nombre viejo fue removido), probando que la ruta de config se resuelve a nivel de conexión, no de sesión. El nombre vigente `_goose/unstable/config/upsert` llegaría a `on_config_upsert`. Además el Desktop llama `configUpsert_unstable` en onboarding **antes** de cualquier chat (`ui/desktop/src/acp/config.ts:24-28`).

**Verificación sin exponer el secreto**: `_goose/unstable/config/read` con `isSecret:true` devuelve el valor **enmascarado** (`config.rs:98-99`, `mask_secret`). Un valor enmascarado no-nulo prueba persistencia sin filtrar la key.

---

## H3 — Persistencia entre arranques; OpenAIProvider lo lee vía `Config::get_secret()` sin env ✅ DEMOSTRADO (lógica) / ⚠ (keyring real)

- Escritura: backend `SecretStorage::Keyring` serializa **todos** los secretos como un blob JSON bajo el item único `service="goose"`, `account="secrets"` (`base.rs:42-44`, `write_all_secrets` `:889-912`). Persiste en Keychain/CredMan/Secret Service.
- Lectura por el provider: `openai_def.rs:94` `config.get_secrets("OPENAI_API_KEY", &["OPENAI_CUSTOM_HEADERS"])` → `get_secret` (`base.rs:848-862`): **1º** env var; **2º** `all_secrets()` (keyring). Si `OPENAI_API_KEY` **no** está en env, lee del keyring. → `AuthMethod::BearerToken(key)` (`openai_def.rs:108-111`) → header `Authorization: Bearer` (`api_client.rs:451-452`).
- **Mismo almacén entre `goose acp` y `goose serve`**: ambos usan `Config::global()` con `KEYRING_SERVICE="goose"` constante (no depende de la ruta), así que el secreto escrito por `goose acp` es leído por `goose serve`. **Salvedad**: si el keyring está deshabilitado (fallback a `secrets.yaml`), la ruta sí importa — el helper debe ejecutar `goose acp` con el **mismo entorno/`GOOSE_PATH_ROOT`** que luego use el Desktop (`main.ts:1152` inyecta `GOOSE_PATH_ROOT` a `goose serve`). Documentar en el spike.

---

## H4 — El helper nunca toca Keychain/Security/CredMan/Secret Service ✅ DEMOSTRADO

El helper solo habla JSON-RPC por stdio. Toda interacción con el almacén seguro ocurre **dentro del binario goose**, vía el crate `keyring` detrás de `Config` (`base.rs:1050-1051` `Entry::new(service, KEYRING_USERNAME)`; features `apple-native`/`windows-native`/`sync-secret-service` en `crates/goose/Cargo.toml:234,240,243`). El helper no enlaza ni invoca ninguna de esas APIs.

---

## H5 — El item del Keychain lo crea Goose ⇒ ¿elimina el problema de ACL? ⚠ [NO DEMOSTRADO desde el repo]

**Demostrable desde el código**: el `SecItemAdd`/escritura la hace el binario `goose` (a través del crate `keyring`, `base.rs:889-912`). Por tanto, **el creador del item es `goose`**, no el helper. Como `goose serve` (el mismo binario) es quien luego lee, creador == consumidor a nivel de "qué ejecutable toca el item".

**NO demostrable desde este repo**:
- El crate `keyring` **no está vendorizado** (`~/.cargo/registry` vacío; `vendor/` solo tiene `v8`). El comportamiento exacto de la ACL de macOS (si el ACL se ata a la *code signature*/Team ID del binario, y si un binario ad-hoc/sin firma produce una ACL estable entre lecturas) **es comportamiento de la Security framework de Apple, no código de Goose**.
- No hay en el repo ninguna mención, test ni mitigación del prompt de Keychain (grep de "Always Allow"/"SecItem"/"code sign" = 0).

**Prueba manual requerida** (ver Escenario 5/6). Hipótesis a validar empíricamente: *si el mismo binario `goose` (mismo path, misma firma) crea y luego lee el item, macOS no muestra el prompt de ACL en la lectura.*

---

## Prueba funcional — pasos del spike

> El binario ligero ya está compilado y copiado (`ui/desktop/src/bin/goose`, sin `local-inference`). El spike puede usarlo directamente.

1. **Compilar** (ya hecho): `cargo build --release -p goose-cli --bin goose --no-default-features --features code-mode,tui,aws-providers,telemetry,nostr,otel,rustls-tls,system-keyring,update`.
2. **Spawn** `goose acp` como hijo (stdin/stdout pipes).
3. **initialize** (id=1) → esperar `result`.
4. **`_goose/unstable/config/upsert`** (id=2) con `{key:"OPENAI_API_KEY", value:"sk-…", isSecret:true}` → esperar `result: {}`.
5. **Cerrar** `goose acp` (terminate).
6. **(Verificación A)** relanzar `goose acp`, `initialize`, **`_goose/unstable/config/read`** `{key:"OPENAI_API_KEY", isSecret:true}` → debe devolver valor **enmascarado** no-nulo (`config.rs:98-99`) ⇒ persistió en el keyring.
7. **(Verificación B — provider real)** ejecutar un chat mínimo contra el gateway (o `goose serve` + una petición) para confirmar que `OpenAIProvider` autentica leyendo del keyring.
8. **Demostrar auth**: la petición al gateway responde 200 (header `Authorization: Bearer` construido en `api_client.rs:451`).
9. **Verificar ausencia en env**: en el proceso `goose serve`, `OPENAI_API_KEY` **no** está en `process.env` (el helper nunca lo exportó).
10. **Verificar `get_secret`**: la verificación A (config/read enmascarado) ya lo prueba sin exponer la key.

**Mensajes JSON-RPC exactos** (solo estos tres son necesarios para el provisioning):
```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"v1","clientCapabilities":{},"clientInfo":{"name":"corp-helper","version":"1.0.0"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":…,"agentInfo":{"name":"goose","version":"1.43.0"},"agentCapabilities":{…},"authMethods":[{"type":"agent","id":"goose-provider","name":"Configure Provider",…}]}}

→ {"jsonrpc":"2.0","id":2,"method":"_goose/unstable/config/upsert","params":{"key":"OPENAI_API_KEY","value":"sk-corp-…","isSecret":true}}
← {"jsonrpc":"2.0","id":2,"result":{}}

→ {"jsonrpc":"2.0","id":3,"method":"_goose/unstable/config/read","params":{"key":"OPENAI_API_KEY","isSecret":true}}   (verificación)
← {"jsonrpc":"2.0","id":3,"result":{"value":"sk-…masked…"}}
```
Formato/ids: JSON-RPC 2.0, `id` entero incremental, notificaciones = `method` sin `id` (`test_acp_client.py:71`). Campos de `initialize` tomados de `test_acp_client.py:88-94`; forma de `initializeResult` de `server.rs:2300-2306`; params de config de `custom_requests.rs:524-528`. **[NO DEMOSTRADO]** el string exacto de `protocolVersion` y la forma completa de `agentCapabilities` sin ejecutar — confirmar en el spike.

---

## Escenarios

| # | Escenario | Resultado esperado | Evidencia / cómo comprobar |
|---|---|---|---|
| 1 | Primera instalación | Funciona | H2+H3 (código). Prueba: pasos 2-8 |
| 2 | Cerrar y reabrir Goose | Sigue funcionando | Keyring persiste (`base.rs:889-912`); `get_secret` lee (`base.rs:857`). Prueba: verificación A tras reinicio |
| 3 | Borrar `config.yaml` | Sigue funcionando | Los secretos **no** viven en `config.yaml` (`get_secret` nunca lee `config_paths`, `base.rs:848-862`); viven en keyring. Prueba: `rm config.yaml`, relanzar, verificación A |
| 4 | Borrar variables de entorno | Sigue funcionando | `get_secret` cae al keyring cuando no hay env (`base.rs:850-857`). Prueba: sin `OPENAI_API_KEY` en env, verificación A/B |
| 5 | **Actualizar a otra build del fork** | ¿Re-prompt del Keychain? | **[NO DEMOSTRADO]** — depende de firma. Ver prueba manual abajo |
| 6 | **Desinstalar y reinstalar** | ¿Sigue leyendo el secreto? ¿Depende de firma? | **[NO DEMOSTRADO]** — el item del keyring sobrevive a la desinstalación de la app (vive en el llavero del usuario), pero la **lectura** por el binario nuevo depende de la ACL/firma. Ver prueba manual |

**Prueba manual para Escenarios 5 y 6 (macOS)** — no automatizable desde el repo:
1. Provisionar con `goose acp` (build A). Abrir Keychain Access → confirmar item `goose` (cuenta `secrets`).
2. Leer una vez con `goose serve` (build A) → observar si aparece prompt. (Esperado: prompt la 1ª vez o "Always Allow" según ACL.)
3. Reemplazar el binario por build B (recompilar el fork) **con la misma firma** (o ambas sin firmar/ad-hoc). Leer de nuevo.
4. **Observar**: ¿macOS re-pregunta? Anotar si el binario está firmado (Developer ID) o ad-hoc (`codesign -dv --verbose=4 ui/desktop/src/bin/goose`).
5. Repetir tras `Always Allow` para ver si persiste el permiso entre builds.
- **Windows [NO DEMOSTRADO]**: Credential Manager (`wincred`) típicamente no usa ACL por-aplicación; una credencial genérica del usuario es legible por cualquier proceso de la misma sesión. Confirmar ejecutando el spike en Windows.

---

## Riesgos

### Riesgos DEMOSTRADOS (con código)
1. **El método es explícitamente `_unstable`** (`custom_requests.rs:522`). Evidencia dura de churn: el test `acp_custom_requests_test.rs:1004-1022` confirma que los nombres **anteriores** `_goose/config/upsert`, `_goose/secret/upsert`, etc. **fueron removidos**. El API se ha renombrado/movido → **alto riesgo de romperse entre versiones de upstream**. Mitigación: la distro corporativa **fija (pin) la versión de goose** que empaqueta y revalida el spike en cada bump.
2. **Salvedad de almacén compartido** (H3): con keyring deshabilitado, `goose acp` y `goose serve` deben usar el mismo `GOOSE_PATH_ROOT`/config_dir o el secreto no se comparte (`base.rs:371-389`, `main.ts:1152`).

### Riesgos NO DEMOSTRADOS (comportamiento de OS, crate no vendorizado)
3. **ACL de macOS creador==consumidor elimina el prompt** (H5): no verificable desde el repo (crate `keyring` no vendorizado; es Security framework de Apple).
4. **Comportamiento del Keychain tras updates** (Escenario 5): depende de si la ACL se ata a la firma del binario.
5. **Impacto de no tener código firmado**: sin Developer ID, cada reemplazo del binario puede invalidar la ACL y re-preguntar. No demostrable desde el repo.
6. **Windows/Linux**: comportamiento de CredMan/Secret Service no verificable desde el código (features del crate, no lógica de Goose).

### Riesgos que REQUIEREN prueba manual
- Escenarios 5 y 6 (procedimiento arriba).
- Confirmar el string exacto de `protocolVersion` y la forma de `agentCapabilities` ejecutando el spike (H1/mensajes).
- Confirmar que `on_config_upsert` acepta `OPENAI_API_KEY` sin validación de provider (código sugiere que sí — `config.rs:134-136` no valida claves arbitrarias — pero confirmar end-to-end).

---

## Entregables

### 1. Este documento (`SPIKE_HELPER_ACP.md`).

### 2. Archivos mínimos para implementar el spike (CERO cambios en Goose)
- `spike/provision_secret.py` (~50 líneas) — reutiliza el patrón de `test_acp_client.py`: spawnea `goose acp`, envía `initialize`, luego `_goose/unstable/config/upsert` (isSecret=true), luego `_goose/unstable/config/read` para verificar, y cierra. **No modifica `crates/`**.
- (Opcional) `spike/verify_provider.sh` — lanza una petición mínima contra el gateway para confirmar auth (paso 7-8), y un check de que `OPENAI_API_KEY` no está en el env del proceso.
- **No se requiere ningún archivo nuevo en `crates/goose` ni `crates/goose-cli`** — el mecanismo ya existe. (Si se quisiera evitar que el helper hable ACP crudo, la alternativa sería un subcomando CLI de ~20 líneas — fuera del alcance del spike.)

### 3. Pruebas manuales
1. Escenarios 1-4: automatizables con `provision_secret.py` + relanzar y `config/read` enmascarado.
2. Escenario 5 (update → re-prompt): procedimiento macOS de 5 pasos arriba + `codesign -dv`.
3. Escenario 6 (reinstall): borrar la app, reinstalar, `config/read` con el binario nuevo; anotar dependencia de firma.
4. Confirmar strings de protocolo ejecutando y capturando el `initializeResult` real.
5. Repetir en Windows (CredMan) y Linux (Secret Service/D-Bus).

### 4. Conclusión objetiva

**La arquitectura es funcionalmente sólida y está demostrada en el código para H1-H4**: `goose acp` expone `_goose/unstable/config/upsert` sobre stdio JSON-RPC sin auth ni sesión (`server.rs:3188`, `custom_dispatch.rs:6`, `config.rs:109-138`, `server.rs:976`), persiste vía `Config::set_secret` en el keyring (`base.rs:889-912`), y `OpenAiProvider` lo lee env-first→keyring (`openai_def.rs:94`, `base.rs:848-862`) sin variables de entorno. El helper nunca toca la Security framework (H4). **Todo esto con cero cambios en Goose.**

**Pero la idoneidad como solución OFICIAL del piloto está condicionada a dos incógnitas no demostrables desde el repo**, que deben resolverse con la prueba manual antes de comprometerse:
1. **H5 / Escenarios 5-6 (el punto crítico)**: que "creador==consumidor" realmente elimine el prompt de macOS **y que sobreviva a updates sin firma**. Si sin Developer ID el Keychain re-pregunta tras cada actualización del fork, se pierde la ventaja principal frente a la Opción C (env) o E (constante compilada). Esta es la variable que decide.
2. **Estabilidad de `_unstable`**: el propio repo prueba que estos métodos ya se renombraron una vez (`acp_custom_requests_test.rs:1004`). Es aceptable **solo** si el piloto fija la versión de goose y revalida en cada bump.

**Recomendación**: **proceder con el spike** para resolver empíricamente H5/Escenarios 5-6 (es barato: ~50 líneas de Python, cero cambios en Goose). Si el prompt de Keychain **no** reaparece tras un update con la firma que use el piloto, esta arquitectura es la de menor costo arquitectónico total que cumple todas las restricciones (usa Keychain, sin plaintext, sin tocar core, sin admin, desde instalador). Si **sí** reaparece sin firma, entonces la decisión real vuelve a ser "firmar el binario" (que arregla también B′/E) o aceptar la Opción C/E — y este spike habrá dado la evidencia para decidirlo con datos, no con suposiciones.
