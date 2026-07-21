# Prompts de implementación — Fork corporativo de Goose Desktop ("Genius Assistant")

Serie de prompts para aplicar, sobre un **clon limpio de goose upstream**, todos los cambios pactados con el **mínimo diff posible**. Cada archivo es un prompt autocontenido: pégalo a un agente de código (goose / Claude Code) trabajando en el clon limpio.

## Orden recomendado de aplicación

| # | Prompt | Qué hace | Toca `crates/`? |
|---|---|---|---|
| 01 | [`01_BUILD.md`](01_BUILD.md) | Compilar el binario `goose` ligero (sin `local-inference`) y copiarlo al Desktop | No |
| 02 | [`02_UI_BRANDING.md`](02_UI_BRANDING.md) | Marca "Genius Assistant" + paleta Coppel + logo | No |
| 03 | [`03_PROVIDERS.md`](03_PROVIDERS.md) | Pinear el provider/gateway corporativo vía bundle (env horneado) | No |
| 04 | [`04_SETTINGS.md`](04_SETTINGS.md) | Bloquear settings críticos ("managed by your organization") | No |
| 05 | [`05_ADVERSARY_MODE.md`](05_ADVERSARY_MODE.md) | Distribuir y activar `adversary.md` | No |
| 06 | [`06_PROMPT_INJECTION.md`](06_PROMPT_INJECTION.md) | Forzar + bloquear "Enable Prompt Injection Detection" | No |
| 07 | [`07_SECURITY_APIKEY.md`](07_SECURITY_APIKEY.md) | Provisionar el API key vía ACP → Keychain (arquitectura elegida) | No |
| 08 | [`08_INSTALLER.md`](08_INSTALLER.md) | Instaladores `.sh`/`.ps1`: descarga + branding + provisioning | No |

**Ninguno de los cambios pactados modifica `crates/goose` (core), `Config`, `SecretStorage` ni el registro de providers.** Todo se logra reutilizando mecanismos oficiales ya presentes en upstream.

## Arquitectura de credenciales elegida (decisión del piloto)

**Provisioning ACP → Keychain.** El instalador/helper provisiona el secreto reutilizando **exclusivamente** el flujo oficial:

```
Helper → spawn "goose acp" → JSON-RPC initialize
       → _goose/unstable/config/upsert {key,value,isSecret:true}
       → Config::set_secret() → Keychain/Credential Manager
```

No implementar alternativas (env-only, patch de `from_env`/Option E, helper que escriba directo al Keychain) **salvo bloqueo técnico documentado**. Detalle y prueba funcional en [`SPIKE_HELPER_ACP.md`](../SPIKE_HELPER_ACP.md) y [`SPIKE_RESULTS.md`](../SPIKE_RESULTS.md).

> **Restricción documentada (no es bloqueo, es condición)**: se demostró empíricamente ([`SPIKE_RESULTS.md`](../SPIKE_RESULTS.md) §5.b) que **sin Developer ID / firma estable, macOS re-pregunta autorización del Keychain tras cada actualización del fork** (la identidad ad-hoc = hash del binario cambia en cada build). Para eliminar el re-prompt, el piloto debe **firmar el binario con Developer ID (macOS) y cert de code-signing (Windows)**. El prompt 07 lo trata explícitamente.

## Constraints globales para el agente (incluir en cada tarea)

- **Idempotencia**: cada prompt empieza con una verificación de "¿ya está aplicado?". Si lo está, **omítelo** — no dupliques ni revuelvas. Los sweeps de branding usan reglas (reemplazan la marca solo si existe), así que re-ejecutarlos hace 0 cambios.
- **Ubica por contenido, no por número de línea**: el upstream evoluciona. Busca el string/estructura a cambiar, no confíes en líneas fijas de la doc.
- **No copiar archivos completos entre clones de distinta versión**: solo los *assets autocontenidos* (iconos/SVG) son seguros de copiar si la versión coincide; la lógica/estructura puede diferir por drift de upstream — reaplica por edición, no por `cp`.
- **Minimizar el diff** respecto a upstream. Preferir hornear valores por build/env sobre editar lógica.
- **No tocar** `crates/goose` (Config, SecretStorage, providers), Electron core no relacionado, ni el registro de providers.
- **No renombrar** identificadores funcionales internos que contienen "goose": `KEYRING_SERVICE`, rutas `Block/goose`, esquema `goose://`, variables `GOOSE_*`. Son invisibles al usuario y romperlos rompe compatibilidad (ver [`BRANDING_PLAN.md`](../BRANDING_PLAN.md) §12).
- Tras cada cambio: `cd ui/desktop && pnpm run typecheck` y, si aplica, `cargo fmt` + `cargo clippy`.
- Verificar visualmente con `pnpm run start-gui` cuando el cambio tenga superficie de UI.

## Docs de referencia (vigentes)

- [`BRANDING_PLAN.md`](../BRANDING_PLAN.md) / [`BRANDING_IMPLEMENTATION.md`](../BRANDING_IMPLEMENTATION.md) — marca (cosmético vs funcional).
- [`CORPORATE_BUNDLE_PLAN.md`](../CORPORATE_BUNDLE_PLAN.md) / [`BUNDLE_IMPLEMENTATION.md`](../BUNDLE_IMPLEMENTATION.md) — provider preconfigurado por bundle.
- [`SPIKE_HELPER_ACP.md`](../SPIKE_HELPER_ACP.md) / [`SPIKE_RESULTS.md`](../SPIKE_RESULTS.md) — provisioning del secreto (arquitectura elegida, con prueba funcional).
- [`PROVIDER_DIAGNOSTICS.md`](../PROVIDER_DIAGNOSTICS.md) — diagnóstico de arranque del provider.

### Estado actual de la implementación (fases posteriores a los prompts)

- [`RESUMEN_FORK.md`](../RESUMEN_FORK.md) — **resumen ejecutivo** de todos los cambios vs Goose original, con el *porqué* de las decisiones complejas (punto de entrada).
- [`CHANGES_REVIEW.md`](../CHANGES_REVIEW.md) — inventario de todos los cambios aplicados, con checkboxes de revisión (fuente de verdad del estado).
- [`POC_DESIGN.md`](../POC_DESIGN.md) — diseño final de la PoC: arquitectura de credenciales, riesgos, qué cambia para producción, estrategia sin firma de Apple.
- [`SECRET_LIFECYCLE.md`](../SECRET_LIFECYCLE.md) — ciclo de vida del secreto + runbook de recuperación (§9) + prueba A→B del Keychain (§4).
- [`LOCKDOWN.md`](../LOCKDOWN.md) — blindaje de UI y comportamiento (locks de provider/backend, updates, telemetría) con archivo:línea.
- [`ADVERSARY_POLICY.md`](../ADVERSARY_POLICY.md) — política de seguridad `adversary.md`: cobertura de tools, límites (fail-open), endurecimiento.

`_archive/` contiene investigación superseded (comparativa A-F, Option E, investigación exhaustiva) — histórico, no accionable.
