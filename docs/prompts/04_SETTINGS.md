# Prompt 04 — Settings: que el usuario no pueda romper la configuración

> Pégalo a un agente de código en el clon limpio. Objetivo: garantizar que la configuración corporativa (provider/host, seguridad) no se pueda romper desde la UI, con el mínimo cambio.

---

## Principio: el bloqueo funcional ya es gratis (precedencia env-first)

`Config::get_param`/`get_secret` (`crates/goose/src/config/base.rs`) resuelven **variables de entorno ANTES** que `config.yaml`/keyring, sin caché que sobreviva. Consecuencia: **lo que el bundle hornea como env (prompt 03) gana siempre en runtime**, aunque el usuario "cambie" el valor en Settings. No hay que escribir código para el bloqueo *funcional*.

> Esto NO cambia — no lo modifiques. Es la base de que "el usuario no pueda romper la config".

Lo único que queda es, **opcionalmente**, el bloqueo *visual* para evitar confusión (que la UI no ofrezca cambiar algo que no tendrá efecto).

## Bloqueo visual — reutiliza el patrón oficial "managed by your organization"

Goose ya tiene un patrón de settings bloqueados por la organización: cuando un `*_OVERRIDE` está presente en el entorno, la UI **deshabilita** el control y muestra *"This setting is managed by your organization and cannot be changed."* (`ui/desktop/src/components/settings/security/SecurityToggle.tsx:70,187,337`). El override llega al renderer vía `additionalArguments` en `src/main.ts` (ver `SECURITY_PROMPT_ENABLED_OVERRIDE`, `main.ts:1269`).

**Aprovecha ese patrón** para lo que el piloto quiera fijar. Dos niveles, elige según necesidad:

### Nivel A (recomendado, cero/mínimo código) — seguridad
- Forzar y bloquear la detección de prompt injection: **ver prompt 06** (usa `SECURITY_PROMPT_ENABLED_OVERRIDE`, ya soportado).

### Nivel B (opcional, UI) — provider / external backend
Si además se quiere que el **selector de provider** y el **External Backend** no sean editables:
- `src/components/settings/app/ExternalBackendSection.tsx`: envolver el control en `disabled` cuando exista una env de política (p.ej. `GOOSE_LOCK_BACKEND`), replicando el patrón de `SecurityToggle` (input `disabled` + mensaje "managed by your organization"). Inyecta esa env por `additionalArguments` en `main.ts` (junto a las `SECURITY_*_OVERRIDE`), horneada por el bundle (prompt 03).
- Selector de provider en onboarding/settings: como el onboarding **se salta** (prompt 03), el usuario normalmente no lo ve. Si se quiere blindar el cambio posterior, deshabilitar el control de cambio de provider en Settings con el mismo patrón `disabled` + mensaje. **Marcar claramente como cambio de UI, no de core.**

## Verificación
- Cambiar el provider/host en Settings y reiniciar → el request sigue yendo al gateway corporativo (env-first gana). *(Bloqueo funcional.)*
- Con la env de política activa, el control aparece deshabilitado con el texto "managed by your organization". *(Bloqueo visual, si se implementó Nivel B.)*
- `pnpm run typecheck` pasa.

## No hacer
- No tocar `Config`/`SecretStorage` para "forzar" valores — la precedencia env-first ya lo hace.
- No inventar un sistema de políticas nuevo; reutiliza el patrón `*_OVERRIDE` + `disabled` que ya existe.
- No ocultar settings de forma que rompan flujos (p.ej. no elimines el panel de seguridad; solo deshabilítalo cuando aplique la política).
