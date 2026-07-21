# Ciclo de vida del secreto (API token) — Genius Assistant

> Documenta alta, lectura, actualización del binario, reinstalación,
> desinstalación, revocación y casos de borde del token corporativo.
> Complementa `prompts/07_SECURITY_APIKEY.md`, `SPIKE_RESULTS.md` y
> `CHANGES_REVIEW.md`. Fecha: 2026-07-18.

## 1. Dónde vive el secreto

| Plataforma | Almacén | Identificador |
|---|---|---|
| macOS | Keychain (login) | item `svce="goose"`, `acct="secrets"` — **un solo item** con todos los secretos como blob JSON |
| Windows | Credential Manager | credencial genérica del servicio `goose` |
| Fallback | `~/.config/goose/secrets.yaml` | solo si el keyring está deshabilitado o falla (ver §8) |

- Clave del token del piloto: **`CUSTOM_GENIUS_API_KEY`** (bundle con `GOOSE_CUSTOM_PROVIDER`; deriva de `generate_api_key_name("custom_genius")`, `crates/goose/src/config/declarative_providers.rs:131-133`). Si el bundle usara el provider `openai` plano: `OPENAI_API_KEY`.
- Precedencia de lectura (`Config::get_secret`): **1) variable de entorno, 2) keyring/archivo** (`base.rs:100-102`). Una env var con el mismo nombre eclipsa al Keychain — útil para debugging, riesgo si un proceso hereda un valor stale.

## 2. Alta (provisioning — instalador)

```
installer → provision_secret.py → spawn "goose acp" (stdio JSON-RPC)
          → initialize
          → _goose/unstable/config/upsert {key, value, isSecret:true}
          → Config::set_secret() → Keychain/CredMan
```

- El helper **nunca** toca el Keychain directamente; siempre persiste Goose.
- **Orden crítico**: provisionar **antes del primer arranque** de la app — el
  primer arranque crea el provider "Genius" y enlaza el secreto solo si ya existe
  (update `requires_auth:true` sin `api_key`, `acp/server/providers.rs:612-623`).
- **Identidad crítica (macOS)**: el binario `goose` que ejecuta el upsert debe ser
  **el mismo** que luego lee (`Contents/Resources/bin/goose` de la .app instalada),
  porque la ACL del item queda atada a esa identidad de firma (§4).
- El upsert es **idempotente**: re-ejecutar sobrescribe el valor sin duplicar.

## 3. Lectura en runtime

`goosed` (mismo binario) lee vía `Config::get_secret(api_key_env)` cuando el engine
declarativo construye el `Authorization` del request al gateway. Sin env, sin
archivos intermedios. Cache de secretos en memoria con invalidación tras updates
de provider (`invalidate_secrets_cache`).

## 4. Actualización del binario — ⚠ el punto crítico (macOS)

**Prueba A→B ejecutada 2026-07-18** (repro del SPIKE_RESULTS §5.b con builds de este árbol):

| Paso | Binario | CDHash | Resultado |
|---|---|---|---|
| upsert `CORP_UPDATE_TEST_KEY` | build A (ad-hoc) | `99b2375c…` | OK |
| read con A (baseline) | build A | `99b2375c…` | ✅ valor enmascarado en **4.6 s**, sin diálogo |
| read con B (simula update) | build B (ad-hoc, `disable-update` para variar el hash) | `47459de0…` | 🔴 **bloqueado 45 s** (watchdog lo mató) — sin respuesta; consistente con prompt `SecurityAgent` esperando autorización |
| cleanup con A | build A | — | `remove` OK, relectura `null` |

**Conclusión (reconfirmada)**: con firma **ad-hoc**, la ACL del Keychain se ata al
hash del binario → **cada build nueva del fork re-pregunta autorización** (o
bloquea procesos headless indefinidamente, que es peor: `goosed` arranca sin UI
visible del prompt en algunos contextos).

**Mitigación** (condición del piloto, prompt 07):
- macOS: firmar con **Apple Developer ID** — el Designated Requirement pasa a
  Team ID + identifier, constante entre versiones. **[PENDIENTE DEMOSTRAR]** con
  dos builds firmados reales (A firmado → provisionar → B firmado → leer sin prompt).
- Windows: CredMan **no** tiene ACL por-app (no aplica el problema), pero firmar
  sigue siendo requisito de distribución. Upstream firma con **Azure Trusted
  Signing** vía CI (no un cert `.pfx` en `forge.config.ts`); Windows se distribuye
  como **ZIP portable**, no instalador.

**Nota operativa**: si un usuario hace clic en "Permitir siempre" en el prompt,
esa build queda en la ACL — pero la siguiente build vuelve a preguntar. No es
solución, es fricción por update, y "Denegar" deja la app sin token (fallos 401).

## 5. Reinstalación (misma versión)

- El item del Keychain **sobrevive** a borrar/reinstalar la .app (el secreto no
  vive en el bundle).
- Reinstalar el **mismo** binario (mismo CDHash) → lectura silenciosa (ACL intacta,
  la identidad no cambió). Verificado implícitamente: build A leyó tras múltiples
  copias del binario (la ACL sigue el contenido, no la ruta).
- Re-ejecutar el instalador completo es seguro: upsert idempotente + `adversary.md`
  se sobrescribe + el provider "Genius" existente se detecta por `display_name`
  (no se duplica; single-flight + búsqueda previa).

## 6. Desinstalación

Borrar la .app **no** borra el secreto ni la config. Limpieza completa:

```bash
# macOS
python3 provision_secret.py --goose <binario> --key CUSTOM_GENIUS_API_KEY --remove   # antes de borrar la app
# o, si la app ya no está:
security delete-generic-password -s goose            # borra TODOS los secretos de goose
rm -rf ~/.config/goose "~/Library/Application Support/Goose"
```

```powershell
# Windows: Credential Manager → quitar la credencial genérica "goose"
# o vía helper --remove antes de desinstalar; config en %APPDATA%\Block\goose
```

> `security delete-generic-password -s goose` elimina el item completo (todos los
> secretos de goose, no solo el del piloto). Correcto para offboarding; excesivo si
> el usuario tiene otros secretos de goose — preferir el helper `--remove`.

## 7. Revocación y rotación

El token es **único por plataforma** (decisión 2026-06-24), monitoreado y revocable:

1. **Revocación** (compromiso/fin del piloto): se revoca **en el gateway (llm-gw)**
   — efecto inmediato en todos los clientes (401), sin tocar los endpoints.
   El secreto local queda huérfano (inofensivo); limpiar en el siguiente ciclo.
2. **Rotación**: emitir token nuevo en el gateway → re-ejecutar el paso de
   provisioning (mismo comando, nuevo `GENIUS_TOKEN`) en cada máquina — upsert
   sobrescribe. Ventana de convivencia de ambos tokens en el gateway recomendada.
   Mientras el binario no cambie, la rotación **no** dispara prompts (misma identidad).
3. **Detección**: el gateway debe alertar sobre uso anómalo del token de plataforma
   (volumen, IPs fuera de rango corporativo).

## 8. Casos de borde

- **`GOOSE_DISABLE_KEYRING`** (env o config): fuerza `secrets.yaml` **en claro** en
  disco (`base.rs:190-194`). Prohibir en el piloto (es exactamente el anti-patrón
  Genius Code).
- **Fallo del keyring**: ciertos errores degradan silenciosamente a
  `secrets.yaml` (`base.rs:641-649`). Señal de auditoría: **la existencia de
  `~/.config/goose/secrets.yaml` en una máquina del piloto indica que algo falló**
  — incluirlo en el checklist de soporte.
- **Binario sin feature `system-keyring`**: todo va a archivo (`base.rs:385-390`).
  El build corporativo DEBE incluir `system-keyring` (prompt 01 ya lo exige).
- **Env shadowing**: `CUSTOM_GENIUS_API_KEY` como variable de entorno del proceso
  eclipsa al Keychain (precedencia §1). No usar salvo debugging puntual.
- **Prompt denegado / bloqueado**: la lectura falla o cuelga (ver §4) → requests al
  gateway sin auth → 401. Soporte: verificar firma del binario vs ACL.

## 9. Recuperación ante fallos del provisioning (runbook)

> Decisión de diseño 2026-07-18: única pieza operativa que faltaba cerrar.
> Principio rector: **el secreto y la configuración local son siempre
> reconstruibles** — ningún fallo de provisioning es terminal; el peor caso se
> resuelve con P4+P1 (~2 minutos por máquina).

### 10.0 Invariantes del sistema (qué debe ser cierto en una máquina sana)

| # | Invariante | Cómo verificarlo |
|---|---|---|
| I1 | Secreto presente y enmascarable | `provision_secret.py --read-only` → valor enmascarado **no nulo** |
| I2 | Secreto en el almacén del SO, no en disco | `~/.config/goose/secrets.yaml` **no existe**; `security find-generic-password -s goose` → item presente (macOS) |
| I3 | Provider enlazado al secreto | `custom_providers/custom_genius.json` contiene `"requires_auth": true` y `"api_key_env": "CUSTOM_GENIUS_API_KEY"` |
| I4 | Provider activo correcto | `config.yaml` con provider activo `custom_genius` |
| I5 | Binario esperado (PoC: congelado) | checksum del `Resources/bin/goose` == checksum archivado del build congelado |
| I6 | Orden respetado | provisioning ejecutado **antes** del primer arranque (si no: síntoma S4) |

### 10.1 Matriz síntoma → diagnóstico → recuperación

| Síntoma | Diagnóstico probable | Recuperación |
|---|---|---|
| **S1.** El helper imprime `!!! EOF (stdout cerrado)` inmediatamente | No pudo arrancar `goose acp`: ruta errónea, binario ausente, o cuarentena Gatekeeper | Verificar ruta (debe ser el binario **del bundle instalado**); `xattr -d com.apple.quarantine <binario>` si aplica; reintentar **P1** |
| **S2.** El helper se cuelga en el upsert (>60 s sin respuesta) | Escritura bloqueada por ACL del Keychain: el item existente fue creado por **otro binario** (update sin procedimiento, o binario no congelado — violación de I5) | **P3** (reset del item) y revisar por qué cambió el binario |
| **S3.** Upsert responde `result: {}` pero I2 falla (**existe `secrets.yaml`**) | Degradación silenciosa a archivo (`base.rs:641-649`): keyring falló y Goose escribió a disco en claro | Tratar como incidente: borrar `secrets.yaml`, diagnosticar el keyring (sesión/keychain bloqueado, Secret Service ausente en Linux), luego **P3** + **P1**; verificar I1–I2 |
| **S4.** Chat responde 401 del gateway con secreto presente (I1 ✓ pero I3 ✗: `"requires_auth": false`) | **Violación de orden** (I6): la app arrancó antes del provisioning → el provider se creó sin enlace y el enlace solo ocurre en la creación | **P2** (reset del enlace) — no requiere re-provisionar |
| **S5.** 401 con I1 ✓ e I3 ✓ | Token inválido/revocado en el gateway (no es fallo de provisioning) | **P5** (rotación): re-provisionar el token nuevo; sin prompts si I5 se mantiene |
| **S6.** I1 devuelve valor pero el enlace falla / secreto "invisible" para la app | Nombre de clave equivocado (p.ej. se provisionó `OPENAI_API_KEY` con bundle §5, que espera `CUSTOM_GENIUS_API_KEY`) | **P1** con la clave correcta + `--remove` de la clave errónea + **P2** para re-enlazar |
| **S7.** La app abre onboarding (no debería) o error de provider desconocido | Estado local inconsistente (provider borrado a mano, config corrupta) | **P4** (reset total de config) + relanzar |
| **S8.** Lectura del secreto se cuelga en runtime (goosed sin respuesta al chatear) | El binario cambió tras el provisioning (I5 ✗) — cuelgue headless demostrado §4 | **P3** con el binario actual, o restaurar el binario congelado |

### 10.2 Procedimientos

**P1 — Re-provisioning (idempotente, seguro repetir siempre):**
ejecutar el paso 3 del instalador tal cual (`provision_secret.py` con la clave y
el binario del bundle). El upsert sobrescribe sin duplicar. Verificar I1 e I2.

**P2 — Reset del enlace del provider (secreto intacto):**
1. Cerrar la app. 2. Borrar `~/.config/goose/custom_providers/custom_genius.json`.
3. Limpiar el provider activo en `~/.config/goose/config.yaml` (o borrar el archivo
si la máquina no tiene otra config que preservar). 4. Relanzar: el primer arranque
recrea el provider y, como el secreto **ya existe**, esta vez sí lo enlaza
(`requires_auth: true`). Verificar I3–I4.

**P3 — Reset del item de Keychain (= procedimiento D del `POC_DESIGN.md` §1.4):**
1. Cerrar la app. 2. `security delete-generic-password -s goose` (borra TODOS los
secretos de goose de la máquina — en el piloto solo existe el nuestro).
3. **P1** con el binario vigente (el item nuevo nace con la ACL correcta).
4. Si I3 estaba en `false`, encadenar **P2**. Verificar I1–I3.
> Excepción documentada al principio "solo Goose toca el Keychain": es un borrado
> de mantenimiento, no una escritura de secretos.

**P4 — Reset total de configuración local (no toca el secreto):**
1. Cerrar la app. 2. Borrar `config.yaml` y `custom_providers/` del config dir
(**preservar `adversary.md`**, o re-copiarlo del instalador). 3. Relanzar y dejar
que el primer arranque reconstruya. 4. Si tras esto I1 falla → **P1**.

**P5 — Rotación de token:**
emitir token nuevo en el gateway → **P1** con el valor nuevo. El enlace (I3) no
cambia (mismo `api_key_env`); sin prompts mientras I5 se mantenga. Revocar el
token anterior en el gateway tras la ventana de convivencia.

### 10.3 Verificación post-recuperación (siempre, en este orden)

1. I1: `--read-only` → enmascarado no nulo.
2. I2: sin `secrets.yaml`.
3. I3: `grep '"requires_auth": true' custom_providers/custom_genius.json`.
4. Humo funcional: abrir la app → chat de una línea contra el gateway → respuesta 200.

### 10.4 Qué NO hacer durante una recuperación

- No exportar el token como variable de entorno "para probar" (eclipsa al Keychain
  — §8 — y queda en el historial del shell).
- No editar `custom_genius.json` a mano para poner `requires_auth: true` sin pasar
  por P2: el archivo quedaría bien pero el secreto podría no existir bajo el
  nombre esperado; P2 valida el enlace por el camino real del servidor.
- No usar `GOOSE_DISABLE_KEYRING` como workaround (§8 — texto plano).
- No hacer clic en "Permitir siempre" para "arreglar" un S2/S8: enmascara la
  violación de I5 y volverá en el siguiente update; usar P3.

## 10. Posible evolución: `goose secret set` (CLI estable)

Evaluación 2026-07-18: el método ACP `_goose/unstable/config/upsert` funciona y está
probado en vivo, pero su namespace `unstable` implica que upstream puede cambiarlo
sin aviso (riesgo en cada rebase del fork). Alternativa: subcomando
`goose secret set <KEY>` (valor por **stdin**, nunca argv) en `crates/goose-cli`
(~60 líneas, **no** toca `crates/goose` core), llamando al mismo
`Config::global().set_secret()`. Beneficios: contrato propio del fork, instalador
sin JSON-RPC, elimina la exposición del token en `ps` (argv), exit codes limpios.
Coste: diff propio a mantener en rebases. Estado: **pendiente de decisión**.
