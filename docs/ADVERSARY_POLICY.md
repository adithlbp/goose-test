# Política de seguridad — Adversary Mode

> Documenta la política `adversary.md` distribuida con Genius Assistant: qué cubre,
> cómo funciona el matching de tools, sus límites y el endurecimiento aplicado el
> 2026-07-20. **No modifica `crates/`** — reutiliza el mecanismo upstream
> (`crates/goose/src/security/adversary_inspector.rs`).

## Qué es

Revisión adversarial de tool calls antes de ejecutarlas. Por cada tool listada en
el frontmatter, el inspector consulta al LLM del provider activo con las reglas de
la política; `BLOCK` → la acción se deniega. Se activa con la sola presencia de
`adversary.md` en el config dir (distribuido por el instalable, ver `LOCKDOWN.md`).

## Cobertura de tools — el detalle que importa

El matching es por **igualdad exacta** del nombre de la tool
(`adversary_inspector.rs:199-205`: `config.tools.iter().any(|t| t == tool_name)`).
El nombre puede llegar **a secas** o **prefijado** según el tipo de extensión:

- **Extensiones platform con `unprefixed_tools: true`** → nombre a secas.
  La extensión `developer` (activa por defecto) lo tiene
  (`crates/goose/src/agents/platform_extensions/mod.rs:158`), así que sus tools
  llegan como `shell`, `write`, `edit` (no `developer__write`).
- **Extensiones MCP** → nombre prefijado, p.ej. `computercontroller__automation_script`.

Esto explica el default mixto de upstream
(`DEFAULT_TOOLS = ["shell", "computercontroller__automation_script"]`) y por qué la
política corporativa lista `write, edit` **a secas** (verificado en código, no por
suposición).

### Frontmatter corporativo

```
tools: shell, write, edit, computercontroller__automation_script
```

| Tool | Extensión | Antes | Ahora |
|---|---|---|---|
| `shell` | developer | ✅ revisada | ✅ |
| `write` | developer | ❌ **sin revisar** | ✅ revisada |
| `edit` | developer | ❌ **sin revisar** | ✅ revisada |
| `computercontroller__automation_script` | MCP | ✅ revisada | ✅ |

> **Gap cerrado (2026-07-20)**: `write`/`edit` son la vía más común por la que un
> agente escribe archivos. Sin ellas, "escribe en `~/.ssh/authorized_keys`" vía la
> tool `write` esquivaba la revisión que la política aplica a `shell`.

## Reglas (resumen)

BLOCK cuando el tool call:
- Escribe/edita/borra fuera del proyecto (shell o write/edit).
- Toca archivos de credenciales/secretos **sin importar la ubicación**: `~/.ssh/*`,
  `~/.aws/*`, `~/.config/gcloud/*`, `~/.netrc`, `.env`, `secrets.yaml`, claves
  privadas (`*.pem`, `id_rsa`).
- Exfiltra datos (POST a URLs desconocidas, pipes de secretos hacia afuera).
- Es destructivo para el sistema o edita archivos de arranque de shell
  (`.zshrc`/`.bashrc`/`.profile`).
- Instala/ejecuta código remoto no confiable, o escala privilegios.

ALLOW el trabajo de desarrollo normal (editar archivos del proyecto, instalar deps,
tests, git). El texto distingue explícitamente las dos formas de tool call (comando
shell vs write/edit con `path`) para que el LLM aplique las reglas a ambas.

## Cómo ve el LLM el tool call

`format_tool_call` (`adversary_inspector.rs:207-222`):
- `shell` → `Tool: shell — command: <cmd>`.
- `write`/`edit` → `Tool: write` + `Arguments:` con el JSON completo (incluye
  `path`), por eso las reglas basadas en ruta aplican.

## Límites conocidos (propiedades del mecanismo, no bugs)

1. **Fail-open**: si el LLM no responde (red caída, rate limit, gateway
   inalcanzable), el resultado es `Allow` con confidence 0.0
   (`adversary_inspector.rs:472-490`). Con el gateway corporativo caído, **toda
   revisión se permite automáticamente**. Es control de mejor esfuerzo, no un
   sandbox determinístico. Señal operativa: "adversary silencioso" puede significar
   gateway caído, no que todo sea seguro.
2. **Allowlist**: solo se revisan las tools del frontmatter. Cualquier tool nueva
   (extensión añadida, MCP de terceros) queda fuera hasta añadirla.
3. **Depende del criterio del LLM**: no hay garantía determinística; complementar
   con permisos de SO si se requiere garantía dura.

## Balance seguridad / fricción

- **Fricción**: baja — la sección ALLOW es explícita y las reglas BLOCK son casos
  claros; no debería frustrar trabajo legítimo.
- **Cobertura**: buena para el vector principal (escritura/borrado y shell), con el
  gap de `write`/`edit` ya cerrado. El fail-open y el alcance por-allowlist son los
  límites estructurales a comunicar al piloto.

## Verificación pendiente (requiere gateway alcanzable)

La lógica de matching está probada en el código (`unprefixed_tools`, tests de
`should_review`). El **comportamiento vivo** —que el LLM efectivamente bloquee una
escritura a `~/.ssh`— solo se confirma con la app corriendo contra un provider
alcanzable (VPN corporativa). Registrar el resultado aquí cuando se ejecute.

## Reescritura ALLOW-first (2026-08-18)

Feedback del piloto: el adversary bloqueaba prácticamente todo el trabajo de
terminal (Jira/Confluence/Workspace por curl, crear carpetas, editar archivos).
Dos causas atacadas en la reescritura de `installer/adversary.md`:

1. **Juez pequeño y conservador**: gemini-3.5-flash con reglas encabezadas por
   BLOCK sobre-bloquea. La política ahora abre con `DEFAULT VERDICT: ALLOW`,
   ejemplos explícitos de trabajo normal (mkdir/edit en HOME, curl a dominios
   corporativos con token de env var) y cierra con "si ninguna regla BLOCK aplica
   claramente: ALLOW". Las reglas BLOCK quedan numeradas y acotadas (credenciales,
   sistema, persistencia, exfiltración a destinos no confiables, destructivo,
   código remoto/escalación).
2. **Hazard del parser** (`adversary_inspector.rs:349`): el veredicto se parsea
   con `starts_with("BLOCK") || contains("\nBLOCK")` sobre el texto en mayúsculas.
   Una respuesta ALLOW cuya explicación empiece una línea con "Block…" (p.ej.
   "ALLOW\nBlocking rules not matched") se interpreta como **BLOCK falso**. La
   política ahora impone formato estricto de salida: exactamente dos líneas,
   verdicto en la 1, `Reason:` en la 2, y prohíbe la palabra BLOCK fuera del
   verdicto. (Fix real sería en el parser, pero es `crates/` — fuera del fork.)

Dominios confiables ampliados: se añadieron `*.services.coppel` (variante interna),
`*.atlassian.net` + `api.atlassian.com` (las APIs de Jira/Confluence Cloud usan
`api.atlassian.com`, no solo `coppelmx.atlassian.net`) y `*.googleusercontent.com`
(descarga de contenido de Drive).

Complemento en `installer/prompts/system.md` (sección "Blocked Tool Calls"): ante
`"The user has declined to run this tool"`, el agente debe explicar que fue la
política de seguridad corporativa —no el usuario— y ofrecer alternativa, en vez de
confabular "lo cancelaste" (ver memoria del incidente 2026-07-21).

Despliegue: `adversary.md` viaja como recurso del bundle y se re-sincroniza al
config dir en cada arranque (`main.ts::syncBundledAdversaryPolicy`, solo app
empaquetada) → **requiere re-empaquetar** los instalables. Se re-lee una vez por
sesión → chat nuevo o reinicio tras actualizar. `system.md` se copia por el
instalador y se re-lee por turno.
