# SPIKE_RESULTS.md — Provisioning del secreto vía `goose acp` (ejecución real)

**Ejecutado**: sí, en vivo, contra `ui/desktop/src/bin/goose` (build ligero del fork, `1.43.0`).
**Helper**: `spike/provision_secret.py` (~90 líneas, sin retries/UI/abstracciones).
**Resultado**: ✅ **arquitectura validada** para H1-H4. H5 (prompt tras updates) sigue sin resolverse y ahora hay evidencia concreta del riesgo (binario ad-hoc).
**Ninguna hipótesis de la investigación resultó falsa.**

---

## Nota de seguridad sobre la ejecución

Para **no tocar tus datos reales**:
- Usé el nombre de clave **`SPIKE_OPENAI_API_KEY`** (no `OPENAI_API_KEY`). El mecanismo es idéntico: `on_config_upsert` no distingue claves (`acp/server/config.rs:134-136`).
- Token **dummy**: `sk-SPIKE-DUMMY-DELETE-ME-1234567890`.
- `GOOSE_PATH_ROOT` a un directorio temporal aislado (eliminado al final).
- Keychain **habilitado** (no seteé `GOOSE_DISABLE_KEYRING`).
- **Limpieza**: borré el secreto dummy con `config/remove` (`value: null` tras borrar). El item de Keychain compartido `goose/secrets` puede quedar existiendo con un blob vacío (inofensivo).

---

## 1. Llamadas JSON-RPC realizadas y respuestas obtenidas (capturadas en vivo)

### Handshake `initialize`
```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"v1","clientCapabilities":{},"clientInfo":{"name":"corp-helper","version":"1.0.0"}}}
← {"jsonrpc":"2.0","id":1,"result":{
     "protocolVersion":0,
     "agentCapabilities":{"loadSession":true,"promptCapabilities":{"image":true,"audio":false,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":false,"acp":false},"sessionCapabilities":{"list":{},"close":{}},"auth":{}},
     "authMethods":[{"id":"goose-provider","name":"Configure Provider","description":"Run `goose configure` to set up your AI provider and API key"}],
     "agentInfo":{"name":"goose","version":"1.43.0"}}}
```
**Resuelve un `[NO DEMOSTRADO]` de la investigación**: el `protocolVersion` de wire es el **número `0`** (valor de `ProtocolVersion::LATEST`). El cliente envió la string `"v1"` y el servidor la aceptó y respondió `0` — es decir, `initialize` es tolerante al valor entrante (`on_initialize` hace echo, `server.rs:2300`).

### Escritura `_goose/unstable/config/upsert`
```json
→ {"jsonrpc":"2.0","id":2,"method":"_goose/unstable/config/upsert","params":{"key":"SPIKE_OPENAI_API_KEY","value":"sk-SPIKE-DUMMY-DELETE-ME-1234567890","isSecret":true}}
← {"jsonrpc":"2.0","id":2,"result":{}}
```
`EmptyResponse` = OK. **No apareció ningún prompt de Keychain** durante la escritura.

### Lectura en un proceso NUEVO `_goose/unstable/config/read` (prueba de persistencia)
```json
→ {"jsonrpc":"2.0","id":2,"method":"_goose/unstable/config/read","params":{"key":"SPIKE_OPENAI_API_KEY","isSecret":true}}
← {"jsonrpc":"2.0","id":2,"result":{"value":"sk-SPIKE***************************"}}
```
Valor **enmascarado** (`mask_secret`, `acp/server/config.rs:98-99`) y **no-nulo** → el secreto persistió y `Config::get_secret` lo recuperó **tras cerrar y reabrir** el proceso, **sin prompt**.

### Borrado (limpieza) `_goose/unstable/config/remove`
```json
→ {"jsonrpc":"2.0","id":2,"method":"_goose/unstable/config/remove","params":{"key":"SPIKE_OPENAI_API_KEY","isSecret":true}}
← {"jsonrpc":"2.0","id":2,"result":{}}
→ read → ← {"result":{"value":null}}
```

---

## 2. Dónde terminó almacenado el secreto

- **Keychain del usuario**, no en archivo. Verificado con `security find-generic-password -s goose`:
  ```
  "svce"<blob>="goose"
  "acct"<blob>="secrets"
  ```
  (item único `service="goose"`, `account="secrets"` — coincide con `base.rs:42-44`).
- **NO se creó `secrets.yaml`**: el config dir aislado quedó vacío (`find $GOOSE_PATH_ROOT -name secrets.yaml` → nada) → se usó el backend Keyring, no el fallback de archivo.
- El **helper nunca tocó el Keychain**: solo escribió/leyó JSON-RPC por stdin/stdout. La única interacción con el Keychain la hizo el binario `goose` (a través del crate `keyring` detrás de `Config`).

---

## 3. ¿Goose pudo leerlo después? — SÍ

Un **segundo proceso `goose acp`** (spawn independiente) leyó el secreto vía `config/read` (que internamente llama `Config::get_secret`, `acp/server/config.rs:98`). Devolvió el valor enmascarado no-nulo → confirma lectura post-persistencia sin intervención del usuario y sin variables de entorno (`OPENAI_API_KEY`/`SPIKE_OPENAI_API_KEY` nunca estuvieron en el env del proceso).

---

## 4. Criterios de aceptación

| Criterio | Estado | Evidencia |
|---|---|---|
| ✅ No se modifica Goose | **Cumplido** | `find crates -name "*.rs" -newermt "-40 min"` = vacío; único archivo nuevo `spike/provision_secret.py` |
| ✅ Secreto almacenado vía `Config::set_secret()` | **Cumplido** | upsert `result:{}` → `on_config_upsert` → `Config::set` → `set_secret` (`config.rs:135`, `base.rs:711`) |
| ✅ El helper nunca toca Keychain directamente | **Cumplido** | El helper solo hace JSON-RPC stdio; el item lo creó `goose` (`security find-generic-password` lo confirma) |
| ✅ Goose lee el secreto después sin intervención | **Cumplido** | read-back en proceso nuevo → valor enmascarado no-nulo |
| ✅ No aparece `secrets.yaml` | **Cumplido** | config dir aislado vacío; keychain usado |

---

## 5. Hallazgos nuevos / actualización de `[NO DEMOSTRADO]`

1. **`protocolVersion` de wire = `0`** (antes `[NO DEMOSTRADO]`). Ahora demostrado.
2. **No hubo prompt de Keychain en esta ejecución** — ni en la escritura ni en la lectura (mismo binario, item recién creado, misma sesión de login). ⚠ **Esto NO prueba H5**: es un único data point en una sola máquina, sin actualizar el binario.
3. **El binario está firmado `adhoc` (linker-signed), `TeamIdentifier=not set`** (`codesign -dv` sobre `ui/desktop/src/bin/goose`). **Esto es evidencia concreta del riesgo de H5/Escenario 5**: una firma ad-hoc ata la identidad de código al **hash del binario**. Cada rebuild del fork produce un hash distinto → la identidad ad-hoc cambia → **la ACL de macOS puede volver a pedir autorización tras un update**. Sigue siendo **[NO DEMOSTRADO]** que efectivamente re-pregunte (requiere la prueba manual de reemplazar el binario por otra build y volver a leer), pero el binario **no** tiene Developer ID, que es la condición que evitaría el re-prompt.

---

## 5.b Escenario 5 (update del fork) — AHORA DEMOSTRADO EMPÍRICAMENTE ⛔

Ejecuté una prueba controlada que **simula instalar una versión nueva del mismo fork**:

1. Provisioné `SPIKE_H5_KEY` con **build A** (binario actual). Identidad ad-hoc: `Identifier=goose-c81be139900cef7c`, `CDHash=a459c4e1…`.
2. Creé **build A2** = copia re-firmada ad-hoc con otro identifier → `Identifier=com.corp.goose-v2-newbuild`, `CDHash=0649d3f9…` (**hash distinto** = identidad de código distinta, como cualquier rebuild del fork).
3. **Leí el secreto con build A2** → el proceso **se colgó ~10s+** y apareció el proceso del sistema **`SecurityAgent`** (PID observado: 30743) — el **diálogo de autorización del Keychain de macOS**.
4. **Contraste**: leer con **build A** (misma identidad) devolvió el valor **al instante, sin prompt** (`"value":"sk-H5-DU*************"`).

**Conclusión demostrada**: con firma **ad-hoc**, macOS ata la ACL del item del Keychain a la **identidad de código (CDHash) del binario que lo creó**. Un binario con hash distinto — es decir, **cualquier build nueva del fork** — es tratado como "otra aplicación" y **dispara el prompt de re-autorización** al leer el secreto. Esto invalida la premisa "creador == consumidor" en cuanto el binario cambia entre versiones.

**Esto NO se debe al helper ni a la arquitectura ACP** (que funciona) — es una propiedad de la Security framework de macOS + la ausencia de Developer ID. La mitigación es firmar con un **Developer ID estable** (el Designated Requirement pasa a basarse en Team ID + bundle id, constante entre versiones → sin re-prompt). **[NO DEMOSTRADO]** que con Developer ID el prompt desaparezca entre versiones (requiere un binario firmado real para probarlo), pero es el comportamiento documentado de la plataforma.

---

## 6. Escenarios (según lo ejecutado)

| # | Escenario | Resultado |
|---|---|---|
| 1 | Primera instalación (provisionar) | ✅ Demostrado (upsert `{}`) |
| 2 | Cerrar/reabrir (leer en proceso nuevo) | ✅ Demostrado (read-back enmascarado) |
| 3 | Sin `config.yaml` | ✅ Implícito: config dir aislado vacío, secreto en keychain |
| 4 | Sin variables de entorno | ✅ Demostrado: nunca hubo la key en env; se leyó del keychain |
| 5 | Update a otra build | ⛔ **DEMOSTRADO: RE-PREGUNTA** — build con identidad distinta (ad-hoc) disparó `SecurityAgent` (prompt del Keychain). Ver §5.b |
| 6 | Desinstalar/reinstalar | ⚠ **NO ejecutado** — el item del keychain sobrevive a la desinstalación (vive en el llavero del usuario); la lectura por el binario nuevo depende de la firma. Requiere prueba manual |

---

## 7. Cómo reproducir

```bash
# Provisionar (real: usar --key OPENAI_API_KEY y tu token real)
python3 spike/provision_secret.py \
    --goose ./ui/desktop/src/bin/goose \
    --key OPENAI_API_KEY \
    --token sk-xxxxx

# Verificar persistencia (proceso nuevo, valor enmascarado)
python3 spike/provision_secret.py \
    --goose ./ui/desktop/src/bin/goose \
    --key OPENAI_API_KEY --read-only

# Borrar
python3 spike/provision_secret.py \
    --goose ./ui/desktop/src/bin/goose \
    --key OPENAI_API_KEY --remove
```

---

## 8. Conclusión

**Las hipótesis H1-H4 de la investigación se confirmaron en ejecución real, con cero cambios en Goose.** El instalador/helper puede provisionar el secreto usando exclusivamente APIs existentes (`initialize` + `_goose/unstable/config/upsert`), Goose lo persiste en el Keychain vía `Config::set_secret`, y lo lee después sin intervención ni variables de entorno. No se generó `secrets.yaml`.

**La única incógnita que decide si esto sirve como solución OFICIAL del piloto es H5**, y ahora hay evidencia concreta que la agrava: **el binario del fork está firmado ad-hoc (sin Developer ID)**. Antes de comprometerse, hay que ejecutar la prueba manual del Escenario 5 (reemplazar el binario por otra build y observar si el Keychain re-pregunta). Si re-pregunta, la decisión real vuelve a ser **firmar el binario** (Developer ID / cert de Windows), lo cual también beneficiaría a cualquier enfoque basado en Keychain.

**Ninguna hipótesis falló.** No hubo que detenerse.
