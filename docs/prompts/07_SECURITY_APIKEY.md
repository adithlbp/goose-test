# Prompt 07 — Provisioning del API Key vía ACP → Keychain (arquitectura elegida)

> Pégalo a un agente de código en el clon limpio. Objetivo: que el instalador provisione el token corporativo reutilizando **exclusivamente** el flujo oficial de Goose, sin tocar core.

---

## Arquitectura (decisión del piloto — no cambiar sin bloqueo documentado)

```
Helper (instalador) → spawn "goose acp" (stdio JSON-RPC)
   → initialize
   → _goose/unstable/config/upsert {key:"OPENAI_API_KEY", value:"<TOKEN>", isSecret:true}
   → on_config_upsert → Config::set_secret() → Keychain / Credential Manager
   → cerrar
Después: goosed lee el secreto vía Config::get_secret() (sin env), sin intervención.
```

El helper **nunca** toca el Keychain/Security framework/CredMan directamente: siempre persiste Goose. **Token único por plataforma** (no por usuario), embebido en el instalador (riesgo aceptado del piloto), monitoreado y revocable.

## Cero cambios en Goose — está demostrado y probado en vivo

- El método `_goose/unstable/config/upsert` ya existe (`crates/goose-sdk-types/src/custom_requests.rs:521-529`), despacha a `on_config_upsert` (`crates/goose/src/acp/server/config.rs:109-138`) → `Config::set` → `set_secret` → backend Keyring (`base.rs:889-912`).
- No requiere sesión: `self.config()` = `Config::global()` (`server.rs:976-978`). Transporte: JSON-RPC 2.0 newline-delimited sobre stdio de `goose acp` (`server.rs:3188`), sin auth.
- Prueba funcional real (mensajes capturados, secreto persistido en Keychain, sin `secrets.yaml`, lectura posterior OK) en [`SPIKE_RESULTS.md`](../SPIKE_RESULTS.md).

## El helper — reutiliza `spike/provision_secret.py`

Copia `spike/provision_secret.py` (ya existe en este repo; ~90 líneas, sin abstracciones) al fork. Hace exactamente: spawn `goose acp` → `initialize` → `config/upsert` (isSecret) → cerrar. Mensajes exactos:

```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"v1","clientCapabilities":{},"clientInfo":{"name":"corp-helper","version":"1.0.0"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":0,"agentInfo":{"name":"goose","version":"…"},"agentCapabilities":{…},"authMethods":[…]}}
→ {"jsonrpc":"2.0","id":2,"method":"_goose/unstable/config/upsert","params":{"key":"OPENAI_API_KEY","value":"<TOKEN>","isSecret":true}}
← {"jsonrpc":"2.0","id":2,"result":{}}
```
Uso:
```bash
python3 provision_secret.py --goose <ruta-al-goose-instalado> --key OPENAI_API_KEY --token <TOKEN>
# verificar (valor enmascarado, sin exponer): --read-only
```

> El instalador invoca esto una vez tras copiar el binario (ver prompt 08). El `<TOKEN>` viene embebido/ofuscado en el instalador, no tecleado por el usuario.

## ⚠ CONDICIÓN CRÍTICA — firma de código (no es opcional para eliminar re-prompts)

**Demostrado empíricamente** ([`SPIKE_RESULTS.md`](../SPIKE_RESULTS.md) §5.b): el binario de este repo está firmado **ad-hoc** (`codesign -dv` → `Signature=adhoc`, `TeamIdentifier=not set`). Con firma ad-hoc, la ACL del item del Keychain se ata al **hash del binario**. Se probó: un binario con hash distinto (= cualquier build nueva del fork) **disparó el prompt de autorización del Keychain** (`SecurityAgent`) al leer el secreto; el mismo binario leyó sin prompt.

**Consecuencia**: sin firma estable, **cada actualización del fork re-pregunta** en macOS. Para que la arquitectura funcione limpia en el piloto:
- **macOS**: firmar con **Apple Developer ID** (el Designated Requirement pasa a Team ID + bundle id, constante entre versiones). Configurar `osxSign`/`osxNotarize` en `forge.config.ts` (activados vía `APPLE_TEAM_ID` en CI) y variables `APPLE_ID`/`APPLE_ID_PASSWORD`/`APPLE_TEAM_ID`.
- **Windows**: firmar el ejecutable. **Corrección (2026-07-20)**: upstream **no** usa `WINDOWS_CERTIFICATE_FILE` en `forge.config.ts` — firma con **Azure Trusted Signing** vía CI (`.github/workflows/bundle-desktop-windows.yml`, `azure/trusted-signing-action`), firmando `Goose.exe` y `resources/bin/goose.exe`. Credential Manager no tiene el problema de ACL por-app; la firma es buena práctica para evitar SmartScreen. Nota: Windows se distribuye como **ZIP portable** (no instalador), igual que upstream.
- **[NO DEMOSTRADO]** que con Developer ID el prompt desaparezca entre versiones — hay que confirmarlo con un binario firmado real (prueba manual: build A firmado → provisionar → build B firmado con el mismo Developer ID → leer → observar que NO aparece `SecurityAgent`).

Si el piloto **no** tendrá firma, escalar como **bloqueo técnico documentado** antes de continuar con esta arquitectura (era la condición de la decisión).

## Verificación
- Tras provisionar: `provision_secret.py --read-only` devuelve valor enmascarado no-nulo.
- `security find-generic-password -s goose` (macOS) muestra el item `svce="goose", acct="secrets"` creado por goose.
- **No** aparece `~/.config/goose/secrets.yaml` (se usó Keychain).
- Abrir la app → chatea contra el gateway → autentica sin que el usuario ingrese nada.
- `OPENAI_API_KEY` **no** está en `process.env` de `goosed`.

## No hacer
- No implementar env-only, patch de `from_env` (Option E), ni un helper que escriba directo al Keychain — quedaron descartados (ver `_archive/`).
- No modificar `Config`/`SecretStorage`/`acp/server/config.rs`.
- No dejar el token en texto plano en disco ni en el bundle sin ofuscar (evitar el error de "Genius Code": API key en bruto/base64 fácilmente extraíble).
