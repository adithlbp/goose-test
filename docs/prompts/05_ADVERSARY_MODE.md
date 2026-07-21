# Prompt 05 — Adversary Mode (revisión adversarial de tool calls)

> Pégalo a un agente de código en el clon limpio. Objetivo: distribuir y activar el "adversary mode" que exige validación antes de acciones riesgosas.

---

## Tarea

Distribuye un archivo `adversary.md` con la instalación y confirma su activación. **No** requiere cambios de código — el mecanismo ya existe en upstream.

## Contexto (mecanismo oficial, ya en el código)

- Implementado en `crates/goose/src/security/adversary_inspector.rs`. Se activa colocando `~/.config/goose/adversary.md` (`Paths::config_dir().join("adversary.md")`, `adversary_inspector.rs:106-139`). **Si el archivo no existe, el inspector está deshabilitado** (`is_enabled` → `get_config().is_some()`, `:386-388`).
- Formato: frontmatter opcional `tools:` + `---` + reglas en lenguaje natural para un LLM (`adversary_inspector.rs:141-197`). Por cada tool call que aplica, consulta al LLM del provider activo si es `ALLOW`/`BLOCK` (`consult_llm`, `:273-373`); `BLOCK` → `InspectionAction::Deny`.

## Contenido a distribuir — `adversary.md`

Crea el archivo (contenido de ejemplo; ajústalo a la política del piloto). El frontmatter `tools:` decide **qué** herramientas se revisan; por defecto solo `shell` y `computercontroller__automation_script` (`DEFAULT_TOOLS`, `:14`):

```markdown
tools: shell, computercontroller__automation_script
---
BLOCK if the command:
- Writes to the filesystem outside the current project directory
- Exfiltrates data (curl/wget POST a URLs desconocidas, pipes de secretos hacia afuera)
- Is destructive (rm -rf fuera del proyecto, modifica archivos del sistema)
- Installs o ejecuta código remoto no confiable
- Escala privilegios innecesariamente

ALLOW normal development operations (editar archivos del proyecto, instalar deps, correr tests, git).
Err on the side of BLOCK for anything that writes outside the project or toca el sistema.
```

> Alineado con la reunión: el objetivo es que el sistema **pida confirmación / bloquee** antes de escribir en el sistema de archivos sin validación.

## Distribución (elige según el instalador — ver prompt 08)

- **Opción recomendada**: el instalador (`.sh`/`.ps1`) escribe `adversary.md` en el config dir del usuario:
  - macOS/Linux: `~/.config/goose/adversary.md`
  - Windows: `%APPDATA%\Block\goose\config\adversary.md`
- El archivo es texto plano no sensible → puede vivir en el instalador o descargarse del repo interno.

## Verificación
- Con `adversary.md` presente, en los logs aparece `Adversary inspector enabled from …` (`adversary_inspector.rs:131-135`).
- Un tool call `shell` que intente escribir fuera del proyecto es bloqueado (`🛡️ Adversary blocked: …`).
- Sin el archivo, no hay overhead (inspector deshabilitado).

## Matices a reportar al piloto (NO son bloqueos, son propiedades del mecanismo)
1. **Alcance por tool**: solo se revisan las tools listadas en `tools:`. Si los flujos usan la extensión `developer` para escribir archivos **sin pasar por `shell`**, hay que añadir esas tools al frontmatter o no se revisan.
2. **Fail-open**: si la llamada al LLM falla (red, rate limit, provider caído), el resultado es `Allow` con `confidence: 0.0` (`adversary_inspector.rs:472-490`) — la acción **se permite**. Es control de mejor esfuerzo apoyado en el LLM, no un sandbox determinístico. Complementar con permisos de SO si se requiere garantía dura.

## No hacer
- No modificar `adversary_inspector.rs` (el mecanismo ya hace lo pedido).
- No hornear el `adversary.md` dentro del binario; distribúyelo como archivo (editable/versionable por la organización).
