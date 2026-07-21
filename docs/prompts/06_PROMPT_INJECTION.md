# Prompt 06 — Forzar y bloquear "Enable Prompt Injection Detection"

> Pégalo a un agente de código en el clon limpio. Objetivo: que la detección de prompt injection quede **activada y no modificable** por el usuario, con cero cambios de código.

---

## Tarea

Deja la detección de prompt injection **forzada a ON** y el toggle **bloqueado** en la UI ("managed by your organization"), reutilizando el mecanismo de override que ya existe. **No** modifiques código de seguridad.

## Contexto (mecanismo oficial, ya en el código)

- Rust: `SecurityManager::is_prompt_injection_detection_enabled()` (`crates/goose/src/security/mod.rs:47-56`) consulta primero `get_override("SECURITY_PROMPT_ENABLED_OVERRIDE")` (`:48`) y **solo** si no hay override lee el config `SECURITY_PROMPT_ENABLED` (default `false`, `:54-55`). El override gana.
- UI: `SecurityToggle.tsx` lee `window.appConfig.get('SECURITY_PROMPT_ENABLED_OVERRIDE')` (`:187`); si está presente, el toggle queda `disabled` (`:337`) y muestra *"This setting is managed by your organization and cannot be changed."* (`:70`).
- El override llega al renderer y a `goosed` vía env, ya cableado en `src/main.ts:1269` (`SECURITY_PROMPT_ENABLED_OVERRIDE`) y `:1271` (`SECURITY_COMMAND_CLASSIFIER_ENABLED_OVERRIDE`).

⟹ **Basta con hornear `SECURITY_PROMPT_ENABLED_OVERRIDE=true` en el bundle** (mismo mecanismo que el provider, prompt 03). Cero cambios de código.

## Cambio exacto (build, no código)

En `ui/desktop/vite.main.config.mts`, añade `SECURITY_PROMPT_ENABLED_OVERRIDE` (y opcionalmente `SECURITY_COMMAND_CLASSIFIER_ENABLED_OVERRIDE`) al set de claves horneadas por `define` (junto a las del prompt 03), condicionado a presencia en el entorno de build.

Y el build corporativo exporta:
```bash
export SECURITY_PROMPT_ENABLED_OVERRIDE=true
# opcional (clasificador ML de comandos, si el piloto lo usa):
# export SECURITY_COMMAND_CLASSIFIER_ENABLED_OVERRIDE=true
```

> Si `vite.main.config.mts` ya lee estos overrides desde `process.env` en runtime (no horneados), verifica que en el build **empaquetado** lleguen: `main.ts:1269-1271` los pasa desde `process.env` del proceso main. Para un bundle sellado, hornearlos con `define` garantiza que estén sin depender del entorno del usuario.

## Verificación
- Abrir Settings → Security: el toggle **"Enable Prompt Injection Detection"** aparece **activado y deshabilitado**, con el texto "managed by your organization and cannot be changed."
- En logs de `goosed`: `Security scanner initialized …` y `prompt_injection_analysis_performed` (`security/mod.rs:105-140,219-223`).
- Un tool call malicioso de prueba se marca/bloquea según el threshold (`SECURITY_PROMPT_THRESHOLD`).
- `pnpm run typecheck` pasa.

## Opcional — clasificador ML externo
Si el piloto usa el clasificador ML (endpoint propio), esos valores también son config (`SECURITY_PROMPT_CLASSIFIER_ENDPOINT`, `SECURITY_PROMPT_CLASSIFIER_TOKEN`, etc., `SecurityToggle.tsx:91-101`). Se pueden pre-cargar por config/env con el mismo enfoque; el token del clasificador, si es sensible, debe tratarse como secreto (provisioning del prompt 07), **no** hornearse en claro.

## No hacer
- No cambiar el default de `SECURITY_PROMPT_ENABLED` en `crates/` — usar el override (no toca core, y bloquea la UI de paso).
- No implementar un toggle nuevo; el existente ya respeta el override.
