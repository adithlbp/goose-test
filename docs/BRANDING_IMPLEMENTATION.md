# BRANDING_IMPLEMENTATION.md — Genius Assistant (cambios cosméticos)

**Marca aplicada**: `Genius Assistant` (nombre visible) — paleta Coppel.
**Alcance**: solo cambios **cosméticos** de `BRANDING_PLAN.md` (Fase 1). **No** se tocó lógica, providers, `Config`, networking, ni identificadores funcionales (Keychain, rutas de datos, esquema `goose://`, `appId`, owner/repo del updater, variables `GOOSE_*`).
**Paleta usada** (del brandbook):
- Coppel Blue `#1C42E8` — acento/interactivo (light) + outline de foco.
- Light Blue `#1CA8F7` — acento en tema oscuro (mejor contraste).
- Coppel Yellow `#F0D224` — logo/app icon + highlights de búsqueda.
- Dark Blue `#081754`, Medium Blue `#05297A` — disponibles, no aplicados en esta fase (reservados para refinamiento).

---

## 1. Archivos modificados

### 1.a Chrome / branding base (11 archivos)
| # | Archivo | Tipo de cambio |
|---|---|---|
| 1 | `ui/desktop/package.json` | `name`, `productName`, `description` |
| 2 | `ui/desktop/index.html` | `<title>` |
| 3 | `ui/desktop/src/main.ts` | About panel, notificación, diálogo de error, 4 labels de menú (About/Focus/Hide + map zh) |
| 4 | `ui/desktop/src/components/onboarding/OnboardingGuard.tsx` | Título de bienvenida + error de conexión |
| 5 | `ui/desktop/forge.config.ts` | Textos de permisos macOS (NSMicrophone / NSAppleEvents) |
| 6 | `ui/desktop/forge.deb.desktop` | `Name=` (label visible del lanzador) |
| 7 | `ui/desktop/forge.rpm.desktop` | `Name=` |
| 8 | `ui/desktop/src/theme/theme-tokens.ts` | Tokens `info` (bg/text/border/ring) light+dark → paleta Coppel |
| 9 | `ui/desktop/src/styles/main.css` | Outline de foco (`--color-block-teal`) + highlights → paleta Coppel |
| 10 | `ui/desktop/src/components/icons/Goose.tsx` | Glifo del mark → tres puntos (currentColor) |
| 11 | `ui/desktop/src/images/icon.svg` + `glyph.svg` | Fuentes de iconos → tres puntos (app: azul+amarillo; menubar: monocromo) |

### 1.b Textos de UI en inglés — `defaultMessage` en el código fuente (~20 archivos, ~55 cadenas)
El texto en inglés visible **vive en los `defaultMessage` inline** (para `en`, `loadMessages` devuelve `{}` y react-intl usa el `defaultMessage` como fuente — ver `src/i18n/index.ts:104-108`). Rebrandeadas todas las cadenas de marca (`Goose`/`goose` → `Genius Assistant`), preservando `{placeholders}` y **sin** tocar términos funcionales (`.goosehints`, `goose://`):

`LauncherView`, `ElicitationRequest`, `ImagePreview`, `GroupedExtensionLoadingToast`, `ToolCallConfirmation`, `TelemetryConsentPrompt`, `ErrorBoundary`, `LoadingGoose` (5), `settings/app/ExternalBackendSection`, `settings/app/TelemetrySettings`, `settings/app/AppSettingsSection` (10), `settings/mode/ConversationLimitsDropdown`, `settings/chat/ChatSettingsSection`, `settings/config/ConfigSettings` (2), `settings/auth/AuthSettingsSection`, `settings/providers/.../DefaultCardButtons`, `settings/providers/.../ProviderConfigurationModal` (2), `settings/keyboard/KeyboardShortcutsSection` (5), `sessions/SessionViewComponents`, `sessions/SessionListView` (2), `recipes/ImportRecipeForm`, `skills/SkillsView`, `onboarding/OnboardingSuccess` (2), `onboarding/PrivacyInfoModal` (2), `hooks/useChatSession` (2).

### 1.c Catálogos de traducción — `src/i18n/messages/*.json` (16 locales)
Rebrandeadas **1126 cadenas** de marca en los 16 idiomas (de, en, es, fr, hi, id, it, ja, ko, ms, pt, ru, tr, vi, zh-CN, zh-TW) vía script `node` que transforma **solo valores** (`JSON.parse`→walk→`JSON.stringify`), dejando claves intactas y protegiendo `.goosehints`/`goose://` con regex `/(?<![.\w])[Gg]oose(?![\w:])/g`. Verificado: 0 marca en valores, `.goosehints`(12)/`goose://`(5) preservados por archivo, JSON válido. **Requiere `pnpm run i18n:compile`** para regenerar `src/i18n/compiled/*.json` (lo hace `start-gui`/`make` automáticamente).

---

## 2. Diff esperado (por archivo)

### 2.1 `package.json` (líneas 2-5)
```diff
- "name": "goose-app",
- "productName": "Goose",
+ "name": "genius-assistant-app",
+ "productName": "Genius Assistant",
  "version": "1.43.0",
- "description": "Goose App",
+ "description": "Genius Assistant App",
```
`version` intacto (no es branding).

### 2.2 `index.html` (línea 9)
```diff
- <title>Goose</title>
+ <title>Genius Assistant</title>
```

### 2.3 `src/main.ts`
```diff
# Mapa de traducción de menú (zh-CN)
- 'Focus Goose Window': '聚焦 Goose 窗口',
+ 'Focus Genius Assistant Window': '聚焦 Genius Assistant 窗口',
- 'About Goose': '关于 Goose',
+ 'About Genius Assistant': '关于 Genius Assistant',
- 'Hide Goose': '隐藏 Goose',
+ 'Hide Genius Assistant': '隐藏 Genius Assistant',
# About panel (macOS)
- applicationName: 'Goose',
+ applicationName: 'Genius Assistant',
# Notificación open-file
- title: 'Goose',
+ title: 'Genius Assistant',
# Diálogo de error de arranque
- title: 'Goose Failed to Start',
+ title: 'Genius Assistant Failed to Start',
# Llamadas a menuT (deben coincidir con las claves del mapa)
- label: menuT('Focus Goose Window'),
+ label: menuT('Focus Genius Assistant Window'),
- label: menuT('About Goose'),
+ label: menuT('About Genius Assistant'),
```
**Nota de correctitud**: `'Hide Genius Assistant'` es el label que macOS **auto-genera** a partir de `productName`; por eso la clave del mapa debe coincidir exactamente con el nuevo nombre, o la traducción zh no aplicaría. Las claves del mapa y las llamadas `menuT(...)` se cambiaron en conjunto para no romper el lookup (`menuT` hace fallback al inglés si no encuentra la clave, así que un desajuste degradaría a inglés, no rompería).

### 2.4 `OnboardingGuard.tsx` (línea 22)
```diff
- defaultMessage: 'Welcome to goose',
+ defaultMessage: 'Welcome to Genius Assistant',
```

### 2.5 `forge.config.ts` (líneas 38-41)
```diff
- 'Goose needs access to your microphone for voice dictation.',
+ 'Genius Assistant needs access to your microphone for voice dictation.',
- 'Goose needs access to send Apple Events to control other apps on your behalf.',
+ 'Genius Assistant needs access to send Apple Events to control other apps on your behalf.',
```

### 2.6 `forge.deb.desktop` / `forge.rpm.desktop` (línea 2)
```diff
- Name=Goose
+ Name=Genius Assistant
```
Solo el label visible. `Exec=`/`Icon=`/`bin`/`prefix` **no** se tocaron (identificadores de ruta funcionales; cambiarlos sin alinear todo rompe el lanzamiento en Linux — ver §5).

### 2.7 `theme-tokens.ts` (tokens `info`)
```diff
# Light theme
- '--color-background-info': '#5c98f9',   → '#1c42e8'   (Coppel Blue)
- '--color-text-info':       '#5c98f9',   → '#1c42e8'
- '--color-border-info':     '#5c98f9',   → '#1c42e8'
- '--color-ring-info':       '#5c98f9',   → '#1c42e8'
# Dark theme
- '--color-background-info': '#7cacff',   → '#1ca8f7'   (Light Blue)
- '--color-text-info':       '#7cacff',   → '#1ca8f7'
- '--color-border-info':     '#7cacff',   → '#1ca8f7'
- '--color-ring-info':       '#7cacff',   → '#1ca8f7'
```
Se cambió **solo** el grupo `info` (acento/interactivo). Backgrounds, text-primary, danger/success/warning intactos → sin riesgo de contraste en superficies principales.

### 2.8 `main.css`
```diff
- --color-block-teal: #13bbaf;                 → #1c42e8   (outline de foco, Coppel Blue)
- --highlight-color:   rgba(255, 213, 0, 0.5); → rgba(240, 210, 36, 0.5)   (Coppel Yellow)
- --highlight-current: rgba(252, 213, 3, 0.6); → rgba(240, 210, 36, 0.6)
```
El nombre del token `--color-block-teal` se conserva (renombrarlo obligaría a tocar todos sus usos); solo cambió su **valor**.

### 2.9 `Goose.tsx` (componente del mark)
```diff
- <g clipPath=...><path d="M20.9..." fill="currentColor" /></g> (glifo ganso)
+ <circle cx="6"    cy="12" r="4"    fill="currentColor" />
+ <circle cx="14.5" cy="12" r="3"    fill="currentColor" />
+ <circle cx="21"   cy="12" r="2.25" fill="currentColor" />
```
Se conservó el **nombre del export** `Goose` → cero cambios en los ~7 imports (`OnboardingGuard`, `BaseChat`, `GooseLogo`, `LoadingGoose`, `RecipeActivities`, etc.). `fill="currentColor"` → el mark **se adapta** al color del contexto (evita problemas de contraste). El export `Rain` (animación) quedó intacto.

### 2.10 `icon.svg` (app) y `glyph.svg` (menubar)
- `icon.svg`: fondo rounded-rect **Coppel Blue `#1C42E8`** + tres puntos **Coppel Yellow `#F0D224`** (alto contraste, ambos colores de marca).
- `glyph.svg`: tres puntos monocromo `#101010` (formato *template* de macOS; el SO lo recolorea).

---

## 3. Decisiones y su justificación

1. **Nombre del color acento**: se usó el grupo semántico `info` como acento de marca (es el token interactivo/enlace). No se tiñó `inverse` (botones primarios/sidebar) ni fondos → opción **conservadora**, sin riesgo de contraste de texto. (La respuesta a la pregunta de estrategia de color quedó ambigua; se tomó la conservadora como default y se documenta aquí.)
2. **Logo in-app en `currentColor`**, no amarillo fijo: el mark aparece en contextos claros y oscuros; `currentColor` garantiza legibilidad. El **amarillo de marca** vive donde corresponde: el **app icon** (`icon.svg`), sobre fondo azul de alto contraste.
3. **Identificadores funcionales intactos**: Keychain (`base.rs:42`), rutas `Block/goose` (`paths.rs`), esquema `goose://`, `appId` (`forge.config.ts:123`), owner/repo del updater y variables `GOOSE_*` **no** se tocaron → cero cambios de comportamiento, config y secretos previos siguen accesibles.

---

## 4. Estado de los pendientes

### 4.a Completados en esta sesión
- ✅ **Textos de UI en inglés** (`defaultMessage` en fuente, ~55 cadenas) — §1.b.
- ✅ **Catálogos i18n de los 16 locales** (1126 cadenas, solo valores, verificado) — §1.c.
- ✅ **`loading-goose/*.svg` confirmado SIN uso**: `grep -rn "loading-goose" src/` = 0 referencias → son assets muertos, **no requieren rebranding**. (El loader real usa `GooseLogo` → `Goose.tsx`, ya rebrandeado.)

### 4.b Pendientes que requieren herramientas externas (no ejecutables aquí)
| Pendiente | Motivo | Cómo completarlo |
|---|---|---|
| Regenerar iconos binarios (`icon.png`, `icon@2x.png`, `icon.ico`, `icon.icns`, `iconTemplate*.png`) | Requieren ImageMagick `convert` (no instalado en este entorno; solo `iconutil` disponible) | Ejecutar `ui/desktop/src/images/prepare.sh` en una máquina con ImageMagick. Ya regenera todo desde `icon.svg` y `glyph.svg` (ya rebrandeados) |
| `icon-light.icns` / `icon-light.png` | Variante clara; no la cubre `prepare.sh` | Regenerar manualmente si se usa una variante clara del icono |
| Recompilar catálogos i18n (`src/i18n/compiled/*.json`) | Necesita `@formatjs/cli` (node_modules) | Automático en `pnpm run start-gui` / `make` (corren `i18n:compile`); o `pnpm run i18n:compile` |
| Regenerar `en.json` extraído | `formatjs extract` necesita node_modules | `pnpm run i18n:extract` (opcional; `en.json` ya fue rebrandeado por el script, y en runtime el inglés usa `defaultMessage`, no `en.json`) |

---

## 5. Notas de riesgo / lo que deliberadamente NO se cambió

- **Linux `.desktop` `Exec=`/`Icon=` y maker `name`/`bin`**: se dejaron como `Goose`/`goose`. Motivo: son rutas funcionales; el `.desktop` de deb usa minúscula (`/usr/lib/goose/`) y el de rpm mayúscula (`/usr/lib/Goose/`) — inconsistencia heredada de upstream. Cambiar solo el label (`Name=`) es seguro; cambiar rutas exige alinear `bin`+`prefix`+`Exec`+`Icon` a la vez o la app **instala pero no lanza**. Queda como decisión de packaging Linux si se quiere el binario también rebrandeado.
- **`appId`, owner/repo del updater, `app-update.yml`**: son **funcionales/identidad** (Fase 2 del plan), fuera del alcance "cosmético". Para un fork independiente deben fijarse (appId propio, updater al repo del fork) **antes del primer release** — ver `BRANDING_PLAN.md` §12.
- **`homepage: 'https://goose-docs.ai/'`** en `forge.config.ts`: se dejó (no hay URL corporativa definida; es metadato, no nombre de marca visible en la app).
- **Comentarios de código** que dicen "About Goose menu item" (`main.ts:2751,2757`): son comentarios internos, no visibles; sin impacto de marca.

---

## 6. Checklist de pruebas

### 6.1 Verificación estática (sin build)
- [x] `grep -rn "Genius Assistant"` confirma branding en chrome base. ✅ (verificado)
- [x] No quedan `menuT('...Goose...')` sin su clave correspondiente en el mapa zh. ✅ (verificado)
- [x] `Goose.tsx` conserva los exports `Goose` y `Rain` (imports intactos). ✅ (verificado)
- [x] `defaultMessage` de marca en fuente = 0 restantes (solo `.goosehints`/`goose://`). ✅ (verificado)
- [x] Catálogos i18n: 0 marca en valores, JSON válido, `.goosehints`(12)/`goose://`(5) intactos por locale. ✅ (verificado con node)
- [ ] `cd ui/desktop && pnpm install && pnpm run typecheck` sin errores. ⛔ (no ejecutable aquí — sin deps; **pendiente en entorno con deps**)
- [ ] `pnpm run lint` sin errores nuevos.
- [ ] `pnpm run i18n:compile` regenera `compiled/*.json` sin errores.

### 6.2 Verificación visual (requiere build/run)
- [ ] Título de ventana = "Genius Assistant".
- [ ] Menú → About muestra "About Genius Assistant" + versión; panel About (macOS) dice "Genius Assistant".
- [ ] Menú de app macOS: "Hide Genius Assistant".
- [ ] Onboarding (perfil limpio): "Welcome to Genius Assistant".
- [ ] Icono del mark (chat/onboarding/loader) = tres puntos, color adaptado al contexto.
- [ ] Acentos interactivos (enlaces/info, focus outline) en Coppel Blue (light) / Light Blue (dark).
- [ ] Highlights de búsqueda en amarillo Coppel.
- [ ] Tema claro y oscuro: sin regresiones de contraste en texto principal.

### 6.3 Iconos de app (tras `prepare.sh`)
- [ ] Ejecutar `ui/desktop/src/images/prepare.sh` (con ImageMagick).
- [ ] Bundle macOS: icono = puntos amarillos sobre azul en Finder/Dock.
- [ ] Bundle Windows: `.exe` con el nuevo icono.
- [ ] Menubar macOS (tray): glifo de tres puntos correcto en claro/oscuro (template).

### 6.4 Regresión funcional (crítico — confirmar que NO cambió comportamiento)
- [ ] Config/sesiones/secretos previos siguen accesibles (identificadores funcionales intactos).
- [ ] Deeplinks `goose://` siguen funcionando (esquema intacto).
- [ ] Chat de punta a punta idéntico a upstream (solo cambió la marca).
- [ ] Auto-updater sin cambios de comportamiento (owner/repo intactos — o rediridos en Fase 2).

---

## 7. Resumen

11 archivos modificados, todos de UI/branding. **Cero** cambios en `crates/`, en lógica de providers, `Config` o networking. Los identificadores funcionales que contienen "goose" (invisibles al usuario) se preservaron intactos para garantizar cero cambios de comportamiento. Los únicos pasos que faltan para el rebranding visual completo son la regeneración de iconos binarios vía `prepare.sh` (herramienta externa) y el barrido i18n locale por locale — ambos documentados en §4.
