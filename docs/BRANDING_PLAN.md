# BRANDING_PLAN.md — Fork corporativo de Goose Desktop

**Objetivo**: rebrandear Goose Desktop con marca propia **sin modificar ningún comportamiento funcional**.
**Método**: inventario exhaustivo de touchpoints de marca con `archivo:línea` verificado en este árbol. No contiene código; ningún archivo fue modificado.
**Placeholder de marca**: en este documento la marca nueva se denota `<BRAND>` (nombre visible, p.ej. "Coppel AI") y `<brand>` (slug en minúsculas, p.ej. "coppelai").

---

## 0. Regla de oro: separar lo COSMÉTICO de lo FUNCIONAL

La palabra "goose" aparece en dos clases muy distintas de sitio. Confundirlas es el error que rompe el fork:

- **COSMÉTICO** (seguro de cambiar): nombre visible, títulos, iconos, textos, About, README. No afectan comportamiento.
- **FUNCIONAL / IDENTIDAD** (peligroso): nombre del servicio de Keychain, directorios de config/datos, esquema de protocolo `goose://`, `appId`, owner/repo del updater, variables `GOOSE_*`. Cambiarlos **rompe compatibilidad, migraciones, updates o el almacenamiento de secretos**.

**Recomendación de ingeniería senior**: para un piloto, cambia **solo lo cosmético** y **deja intactos los identificadores funcionales internos** (que el usuario nunca ve). Un usuario ve "Coppel AI" en la ventana, el dock y el About, mientras internamente el servicio de Keychain sigue llamándose `goose` y los datos viven en `.../Block/goose/`. Esto da branding completo con **cero riesgo funcional**. Los identificadores funcionales solo se tocan si hay una razón explícita (evitar colisión con una instalación oficial de Goose en la misma máquina), y en ese caso **con plan de migración**.

Las secciones §1-§11 son cosméticas (seguras). La §12 lista los identificadores funcionales y qué implica tocarlos.

---

## 1. Nombre de la aplicación

| # | Archivo | Línea | Valor actual | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|---|
| 1.1 | `ui/desktop/package.json` | 3 | `"productName": "Goose"` | Nombre del `.app`/ejecutable empaquetado por Forge | Bajo | No (cosmético) | `pnpm run make`; verificar que el bundle se llama `<BRAND>.app` |
| 1.2 | `ui/desktop/package.json` | 2 | `"name": "goose-app"` | Nombre npm interno del paquete | Muy bajo | No | `pnpm install` sin errores |
| 1.3 | `ui/desktop/package.json` | 5 | `"description": "Goose App"` | Metadato de descripción | Muy bajo | No | Inspección de metadatos del paquete |
| 1.4 | `ui/desktop/src/main.ts` | 757 | `applicationName: 'Goose'` (About panel macOS) | Nombre en el panel "Acerca de" | Bajo | No | Menú → About; ver `<BRAND>` |

**Nota**: `productName` (1.1) es el driver principal del nombre visible del bundle. `GOOSE_BUNDLE_NAME` (env de build, `package.json:22-24`) también controla el nombre del `.app`/zip en los scripts `bundle:*`; alinearlo con `<BRAND>` (ver §7 y §10).

---

## 2. Nombre del proceso / ejecutable

| # | Archivo | Línea | Valor actual | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|---|
| 2.1 | `ui/desktop/package.json` | 22-24 | `GOOSE_BUNDLE_NAME:-Goose` | Nombre del `.app` y del proceso en macOS (scripts `bundle:default`/`intel`/`debug`) | Medio | No (cosmético) pero afecta rutas de artefactos | `GOOSE_BUNDLE_NAME=<BRAND> pnpm run bundle:default`; `ps aux \| grep <BRAND>` |
| 2.2 | `ui/desktop/forge.config.ts` | 91, 107, 133 | `bin: 'Goose'` (deb/rpm/flatpak) | Nombre del binario ejecutable en Linux | Medio | No, si se alinea con el `.desktop` (§11) | Instalar `.deb`/`.rpm`; ejecutar `<BRAND>` desde terminal |

**Riesgo cruzado**: el `bin` de Linux (2.2) debe coincidir con `Exec=` del `.desktop` (§11) y con `prefix` (`/opt`). Si divergen, el lanzador no encuentra el binario.

---

## 3. Título de ventanas

| # | Archivo | Línea | Valor actual | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|---|
| 3.1 | `ui/desktop/index.html` | 9 | `<title>Goose</title>` | Título HTML base de la ventana renderer | Bajo | No | Abrir app; título de ventana = `<BRAND>` |
| 3.2 | `ui/desktop/src/main.ts` | 1181 | `title: 'Goose Failed to Start'` | Título del diálogo de error de arranque | Bajo | No | Forzar fallo de arranque; ver título |
| 3.3 | `ui/desktop/src/main.ts` | 812 | `title: 'Goose'` (Notification de open-file) | Título de notificación | Muy bajo | No | Drag-and-drop de carpeta inválida al dock |

**Nota**: la ventana principal toma su título de `index.html` (3.1) salvo override dinámico. Los títulos 1012/1034/1083/1120 (`External Backend…`) y 2196 (`Import session`) no contienen la marca; no requieren cambio.

---

## 4. Iconos

Todos en `ui/desktop/src/images/` (empaquetados vía `extraResource: ['src/bin', 'src/images', 'src/app-update.yml']`, `forge.config.ts:9`). Referencias en `forge.config.ts`: `icon: 'src/images/icon'` (:10), `icon.ico` (:13, :83), `icon.png` (:97, :113), `icon.svg`/`icon-512.png` (:127-128).

| # | Archivo (asset) | Uso | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|
| 4.1 | `src/images/icon.icns` | Icono app macOS | Alto (visible) | Bajo | No | Bundle macOS; ver icono en Finder/Dock |
| 4.2 | `src/images/icon.ico` | Icono app Windows | Alto | Bajo | No | Bundle Windows; ver icono del `.exe` |
| 4.3 | `src/images/icon.png` / `icon-512.png` | Icono Linux (deb/rpm/flatpak) | Alto | Bajo | No | Instalar en Linux; ver icono en el menú |
| 4.4 | `src/images/icon.svg` / `Union@2x.svg` / `glyph.svg` | Vectoriales / flatpak scalable | Medio | Bajo | No | Render flatpak |
| 4.5 | `src/images/icon-light.icns` / `icon-light.png` | Variante clara | Medio | Bajo | No | Tema claro |
| 4.6 | `src/images/iconTemplate.png` / `@2x` | Icono **tray/menubar macOS** (template = monocromo) | Medio | Bajo (debe seguir siendo template B/N con alfa) | No | Ver icono en la barra de menú macOS |
| 4.7 | `src/images/iconTemplateUpdate.png` / `@2x` | Tray con badge de update | Bajo | Bajo | No | Simular update disponible |

**Riesgo específico 4.6**: los `*Template.png` deben permanecer como imágenes *template* de macOS (negro + alfa) o el tray se verá mal en modo claro/oscuro. Reemplazar con el glifo de `<BRAND>` respetando ese formato.

---

## 5. Logos y splash (loading)

| # | Archivo | Uso | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|
| 5.1 | `src/images/loading-goose/1.svg … 7.svg` | Animación de carga/splash (7 frames) | Alto (visible en cada arranque) | Bajo | No | Arrancar app; ver animación = `<BRAND>` |
| 5.2 | `ui/desktop/src/components/icons/Goose.tsx` | Componente React `<Goose/>` (logo en onboarding y UI) | Alto | Medio (usado en varios sitios) | No | Onboarding y cabeceras; ver logo |

**Nota 5.2**: `Goose.tsx` exporta `function Goose(...)` usado por `OnboardingGuard.tsx` (`import { Goose } from '../icons'`) y otros. Puedes reemplazar el contenido SVG conservando el **nombre del export** `Goose` para no tocar los imports (mínimo diff), o renombrar y actualizar imports (más invasivo). Recomendado: conservar el nombre del símbolo, cambiar solo el SVG.

---

## 6. Onboarding y textos de UI

| # | Archivo | Línea | Valor actual | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|---|
| 6.1 | `src/components/onboarding/OnboardingGuard.tsx` | 22 | `'Welcome to goose'` | Título de bienvenida | Bajo | No | Primer arranque limpio; ver texto |
| 6.2 | `src/components/onboarding/OnboardingGuard.tsx` | 26 | `'Your local AI agent…'` | Subtítulo | Bajo | No | Idem |
| 6.3 | `src/i18n/messages/en.json` | (múltiples, ~126 ocurrencias de "oose") | Cadenas con "Goose" | Medio (texto en toda la UI) | Medio (hay que revisar cada cadena) | No | Cambiar idioma a EN; buscar "Goose" residual en la UI |
| 6.4 | `src/i18n/messages/{es,de,fr,ja,zh-CN,…}.json` | varias | "Goose" en traducciones | Medio | Medio | No | Cada locale; buscar residuales |

**Nota 6.3/6.4**: `en.json` es la fuente base (define IDs de mensajes). Estrategia recomendada: buscar/reemplazar "Goose"→`<BRAND>` y "goose"→`<brand>` **solo en las cadenas de texto visible**, respetando IDs de mensaje y placeholders `{var}`. No tocar claves. Verificar con `pnpm run i18n-validate-locale` si existe (hay scripts `i18n-*.js` en `scripts/`).

---

## 7. About / Acerca de

| # | Archivo | Línea | Valor actual | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|---|
| 7.1 | `src/main.ts` | 757 | `applicationName: 'Goose'` | Nombre en About panel (macOS) | Bajo | No | Menú → About `<BRAND>` |
| 7.2 | `src/main.ts` | 2753 | `label: menuT('About Goose')` | Label del ítem de menú "About" | Bajo | No | Ver menú de la app |
| 7.3 | `src/main.ts` | 102 | `'About Goose': '关于 Goose'` (mapa i18n de menú) | Traducción del label de menú | Bajo | No | Menú en zh-CN |
| 7.4 | `src/i18n/messages/*.json` | varias | Entradas de menú "About Goose" | Bajo | Bajo | No | Idem por locale |

---

## 8. Colores / tema

| # | Archivo | Línea | Observación | Impacto | Riesgo | ¿Rompe compat? |
|---|---|---|---|---|---|---|
| 8.1 | `src/styles/main.css` | 407, 592, 677, 688-689 | Clases con prefijo `goose-*` (`.goose-icon-entrance`, `.goose-message`, keyframe `goose-icon-entrance`, `.goose-icon-animation`) | Ninguno visual si no se renombran | Muy bajo | No |

**Recomendación**: **no renombrar** las clases CSS `goose-*`. Son identificadores internos sin marca visible; renombrarlas obliga a tocar CSS + TSX que las referencian, con riesgo de romper estilos, a cambio de cero beneficio de marca. Para colores de marca (paleta), la vía correcta es el sistema de tokens de tema (variables CSS) — no encontré un color hardcodeado ligado al nombre "Goose"; los colores son tokens neutrales. **[NO DEMOSTRADO]** que exista un color de marca específico a cambiar; el branding de color se hace ajustando los tokens de tema, no buscando "goose".

---

## 9. package.json (resumen consolidado)

| Campo | Línea | Cambiar a | Riesgo |
|---|---|---|---|
| `name` | 2 | `<brand>-app` | Muy bajo |
| `productName` | 3 | `<BRAND>` | Bajo (driver del nombre del bundle) |
| `description` | 5 | `<BRAND> App` | Muy bajo |
| `version` | 4 | — (no tocar por branding) | — |
| Scripts `bundle:*` / `debug` | 22-24 | usan `GOOSE_BUNDLE_NAME:-Goose` → exportar `GOOSE_BUNDLE_NAME=<BRAND>` en build | Medio (rutas de artefactos) |

---

## 10. electron-forge / makers / publisher / updater

| # | Archivo | Línea | Valor actual | Clase | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|---|---|
| 10.1 | `forge.config.ts` | 90, 106 | `name: 'Goose'` (deb/rpm) | Cosmético | Nombre del paquete Linux | Bajo | No | `pnpm run make`; nombre del `.deb`/`.rpm` |
| 10.2 | `forge.config.ts` | 92, 108 | `maintainer: 'AAIF …'` | Cosmético | Metadato | Muy bajo | No | Inspección del paquete |
| 10.3 | `forge.config.ts` | 93, 109, 130 | `homepage: 'https://goose-docs.ai/'` | Cosmético | Metadato | Muy bajo | No | Idem |
| 10.4 | `forge.config.ts` | 10, 13, 83, 97, 113, 127-128 | rutas `src/images/icon*` | Cosmético | Iconos empaquetados | Bajo | No | Ver §4 |
| 10.5 | `forge.config.ts` | 38-41 | `NSMicrophoneUsageDescription` / `NSAppleEventsUsageDescription` ("Goose needs…") | Cosmético | Textos de permisos macOS (TCC) | Bajo | No | Disparar prompt de micrófono/AppleEvents |
| 10.6 | `forge.config.ts` | 68-69 | `owner: 'aaif-goose'`, `name: 'goose'` (publisher GitHub) | **FUNCIONAL** | Repo de publicación de releases | **Alto** | **Sí, si no apunta al repo del fork** | Publicar release de prueba al repo del fork |
| 10.7 | `src/app-update.yml` | 1-4 | `owner: aaif-goose`, `repo: goose`, `updaterCacheDirName: goose-updater` | **FUNCIONAL** | Origen de auto-updates | **Alto** | **Sí** — si no se cambia, el fork buscaría updates en el repo oficial (o fallaría) | Ver §12.5 |
| 10.8 | `src/utils/autoUpdater.ts` | 374-375 | `owner: 'aaif-goose'`, `repo: 'goose'` | **FUNCIONAL** | Consulta de releases del updater | **Alto** | **Sí** | Ver §12.5 |
| 10.9 | `src/utils/autoUpdater.ts` | 298, 678, 769, 777 | Textos "Goose"/"Goose.app" en diálogos/tooltip de update | Cosmético | Texto visible | Bajo | No | Simular update; ver diálogos |
| 10.10 | `scripts/generate-mac-update-manifest.js` | 68-73 | `Goose.zip`, `Goose-darwin-arm64.zip`, `Goose_intel_mac.zip` | **FUNCIONAL** | Nombres de assets del manifiesto de update macOS | **Alto** | **Sí** — deben coincidir con los artefactos reales (`GOOSE_BUNDLE_NAME`) | Generar manifiesto; verificar que los nombres casan con los zips producidos |

**Publisher/updater (10.6-10.8, 10.10)**: son **funcionales**. Para el fork **debes** apuntar a tu propio `GITHUB_OWNER`/`GITHUB_REPO` (`forge.config.ts:68-69` ya leen esas env vars) y alinear `app-update.yml` + `autoUpdater.ts` + los nombres de assets del manifiesto. Si no, el auto-updater consulta el repo oficial de Goose → en el mejor caso no encuentra tu versión, en el peor **instala binarios ajenos** (riesgo de seguridad). Ver §12.5.

---

## 11. Linux desktop files

| # | Archivo | Línea | Valor actual | Impacto | Riesgo | ¿Rompe compat? | Cómo probar |
|---|---|---|---|---|---|---|---|
| 11.1 | `ui/desktop/forge.deb.desktop` | 2 | `Name=Goose` | Nombre en el menú de apps | Bajo | No | Instalar `.deb`; buscar `<BRAND>` en el lanzador |
| 11.2 | `forge.deb.desktop` | 3 | `Exec=/usr/lib/goose/Goose %U` | Ruta del ejecutable | **Medio** | **Sí, si no casa con `prefix`+`bin`** | Lanzar desde el menú |
| 11.3 | `forge.deb.desktop` | 4 | `Icon=/usr/share/pixmaps/goose.png` | Ruta del icono | Bajo | Sí, si el nombre no casa | Ver icono en el menú |
| 11.4 | `forge.deb.desktop` | 8 | `MimeType=x-scheme-handler/goose;` | **FUNCIONAL** (deeplink) | Registro del esquema `goose://` | **Alto** | **Sí** — cambiarlo rompe deeplinks; ver §12.3 | Ver §12.3 |
| 11.5 | `forge.rpm.desktop` | 2-8 | Igual que deb pero rutas `Goose` (mayúscula: `/usr/lib/Goose/Goose`, `/usr/share/pixmaps/Goose.png`) | Idem | Medio/Alto | Idem | Instalar `.rpm` |

**Inconsistencia detectada (heredada de upstream)**: `forge.deb.desktop` usa rutas en minúscula (`/usr/lib/goose/`, `goose.png`) mientras `forge.rpm.desktop` usa mayúscula (`/usr/lib/Goose/`, `Goose.png`). Al rebrandear, **unifica** ambas con el mismo casing que produzca el `bin`/`prefix` de `forge.config.ts` (§2.2). Este es el punto más propenso a "instala pero no lanza".

---

## 12. Identificadores FUNCIONALES (⚠ cambiar solo con plan; por defecto NO tocar)

Estos contienen "goose" pero **no son branding visible**. Cambiarlos rompe comportamiento. Para un piloto, la recomendación es **dejarlos como `goose`** salvo que exista una razón explícita.

### 12.1 Nombre del servicio de Keychain / Credential Manager — **NO CAMBIAR**
- `crates/goose/src/config/base.rs:42` — `const KEYRING_SERVICE: &str = "goose"` (y `KEYRING_USERNAME = "secrets"`, :44).
- **Impacto si se cambia**: los secretos ya guardados quedan huérfanos (Goose los buscaría bajo el nuevo nombre y no los encontraría). Riesgo: **Alto**. Rompe compat: **Sí**.
- **Recomendación**: no tocar. Es invisible al usuario. (Además, en la estrategia de API key por env, el keyring ni se usa — ver `DESIGN_REVIEW_APIKEY.md`.)

### 12.2 Directorios de config/datos — **NO CAMBIAR sin migración**
- `crates/goose/src/config/paths.rs:23-25` — `top_level_domain/author: "Block"`, `app_name: "goose"` → `~/Library/Application Support/Block/goose/`, `~/.config/goose/`, etc. El comentario `:19-20` advierte que cambiarlo "orphans existing installations".
- **Impacto si se cambia**: config, sesiones y datos existentes se pierden (quedan en la ruta vieja). Riesgo: **Alto**. Rompe compat: **Sí**.
- **Recomendación**: no tocar para el piloto. Si se cambia, requiere script de migración de directorios.

### 12.3 Esquema de protocolo `goose://` — **FUNCIONAL**
- `forge.config.ts:20-24` (`GooseProtocol`, `schemes: ['goose']`), `src/main.ts:413,428` (`setAsDefaultProtocolClient('goose')`), `:442,505` (parsing `goose://`), `.desktop` MimeType (§11.4), flatpak `mimeType: ['x-scheme-handler/goose']` (`forge.config.ts:125`).
- **Impacto si se cambia** a `<brand>://`: coherente para el fork, pero rompe cualquier deeplink `goose://` existente y **colisiona** con Goose oficial si ambos registran `goose`. Riesgo: **Medio**. Rompe compat: **Sí** (deeplinks viejos).
- **Recomendación**: cambiar a `<brand>` **solo si** el fork usa deeplinks propios o coexiste con Goose oficial; si no, dejar `goose`. Debe cambiarse en **todos** los sitios a la vez o los deeplinks se rompen a medias.

### 12.4 `appId` macOS/flatpak — **FUNCIONAL (identidad de app)**
- `forge.config.ts:123` — `id: 'io.github.block.Goose'` (comentario: "kept for backwards compat with existing installs").
- **Impacto si se cambia**: macOS/flatpak lo tratan como una **app distinta** (nueva identidad de LaunchServices, nueva entrada de updates). Riesgo: **Alto**. Rompe compat: **Sí** (no "actualiza" la instalación oficial; se instala en paralelo).
- **Recomendación**: para un fork corporativo **independiente**, **sí** usar un `appId` propio (`com.<org>.<brand>`) — es lo correcto para no colisionar con Goose oficial. Es un cambio de identidad **deseado**, no un accidente. Debe fijarse desde el primer release (cambiarlo después rompe la cadena de updates del propio fork).

### 12.5 Owner/repo del updater — **FUNCIONAL (seguridad)**
- `forge.config.ts:68-69`, `src/app-update.yml:1-4`, `src/utils/autoUpdater.ts:374-375`, nombres de assets en `scripts/generate-mac-update-manifest.js:68-73`.
- **Impacto si no se cambia**: el fork buscaría/instalaría updates desde `aaif-goose/goose` (repo ajeno). Riesgo: **Alto (seguridad + funcional)**. Rompe compat: **Sí**.
- **Recomendación**: **obligatorio** apuntar a tu repo (`GITHUB_OWNER`/`GITHUB_REPO` + `app-update.yml` + `autoUpdater.ts` + nombres de assets alineados con `GOOSE_BUNDLE_NAME`). Sin esto el updater es incorrecto o inseguro.

### 12.6 Variables de entorno `GOOSE_*` — **NO RENOMBRAR**
- `GOOSE_PROVIDER`, `GOOSE_MODEL`, `GOOSE_DEFAULT_*`, `GOOSE_BUNDLE_NAME`, `GOOSE_SERVER__SECRET_KEY`, `GOOSE_PATH_ROOT`, etc. (múltiples en `main.ts`, `gooseServe.ts`, `crates/`).
- **Impacto si se renombran**: el binario Rust y el core esperan esos nombres exactos (`Config::get_param` upper-casea la clave). Renombrarlos rompe la resolución de config. Riesgo: **Alto**. Rompe compat: **Sí**.
- **Recomendación**: **no tocar**. No son branding; son la API de configuración. Son invisibles al usuario final.

### 12.7 README y docs — cosmético pero fuera del binario
- `README.md:3` (`# goose`), `crates/goose-cli`/docs varios. No afectan la app empaquetada. Cambiar solo si el fork publica su propio README. Riesgo: nulo. Rompe compat: No.

---

## 13. Resumen: orden de ejecución recomendado

**Fase 1 — Cosmético (cero riesgo funcional):**
1. `package.json` productName/name/description (§1, §9).
2. Iconos y assets (§4, §5) — conservar nombres de archivo y del export `Goose.tsx`.
3. Títulos y About (§3, §7).
4. Onboarding + i18n (§6) — solo cadenas visibles.
5. Textos de permisos macOS y de update (§10.5, §10.9).
6. Nombres de paquete Linux + `.desktop` (§10.1, §11) — unificar casing con `bin`/`prefix`.
7. `GOOSE_BUNDLE_NAME=<BRAND>` en el pipeline de build (§2, §9).

**Fase 2 — Identidad (deseada para un fork independiente, fijar desde el 1er release):**
8. `appId` propio (§12.4).
9. Updater apuntando al repo del fork + assets alineados (§12.5, §10.6-10.10).

**Fase 3 — No tocar (salvo razón explícita + migración):**
10. Keychain service (§12.1), directorios Paths (§12.2), esquema `goose://` (§12.3), variables `GOOSE_*` (§12.6).

---

## 14. Plan de pruebas end-to-end del rebranding

| Prueba | Comando / acción | Criterio de éxito |
|---|---|---|
| Bundle macOS | `GOOSE_BUNDLE_NAME=<BRAND> pnpm run bundle:default` | Se produce `<BRAND>.app`; Finder muestra icono y nombre `<BRAND>` |
| Nombre de proceso | Abrir app; `ps aux \| grep <BRAND>` | El proceso aparece como `<BRAND>`, no `Goose` |
| Ventana / título | Abrir app | Título de ventana = `<BRAND>` (§3.1) |
| About | Menú → About | `<BRAND>` + versión (§7) |
| Tray macOS | Ver barra de menú | Glifo `<BRAND>` template correcto en claro/oscuro (§4.6) |
| Onboarding | Primer arranque limpio (perfil nuevo) | "Welcome to `<BRAND>`" (§6.1) |
| i18n residual | Cambiar idioma; buscar "Goose" en la UI | Cero ocurrencias de "Goose" visibles (§6.3-6.4) |
| Deeplink (si NO se cambió el esquema) | Abrir `goose://…` | Sigue funcionando (no se rompió §12.3) |
| Secretos (regresión funcional) | Abrir app tras rebrand cosmético | Config/secretos previos siguen accesibles (§12.1-12.2 intactos) |
| Linux launch | Instalar `.deb`/`.rpm`; lanzar desde el menú | La app abre (Exec/prefix/bin casan, §11) |
| Windows | Bundle Windows; ver `.exe` | Icono y nombre `<BRAND>` (§4.2) |
| Updater (staging) | Publicar release de prueba al repo del fork; forzar chequeo | El updater consulta el **repo del fork**, no `aaif-goose/goose` (§12.5) |
| Regresión funcional global | Ejecutar un chat de punta a punta | Comportamiento idéntico a upstream (solo cambió la marca) |

---

## 15. Marcado explícito de lo NO demostrado desde el código

- **[NO DEMOSTRADO]** que exista un color de marca hardcodeado ligado a "Goose": los colores observados son tokens de tema neutrales; el branding de paleta se hace sobre los tokens CSS, no buscando "goose" (§8).
- **[NO DEMOSTRADO]** la lista completa de cadenas "Goose" en cada uno de los ~10 locales de `src/i18n/messages/*.json` (conté 126 ocurrencias de "oose" solo en `en.json`); el rebrand de i18n requiere un barrido locale por locale, no una sola edición.
- **[NO DEMOSTRADO]** que Windows tenga un maker Squirrel/MSI con nombre de setup a rebrandear: en `forge.config.ts` los makers son zip/deb/rpm/flatpak; no hay `maker-squirrel` ni WiX (el Windows se distribuye como zip). Si se añade un instalador Windows, tendrá sus propios campos de marca.
- **[NO DEMOSTRADO]** rutas exactas de instalación final en Windows/macOS firmados — dependen del pipeline de firma real, no deducibles del árbol.

---

**Conclusión**: el rebranding cosmético completo (Fases 1) toca ~15 archivos, todos de bajo riesgo y **sin** impacto funcional. La identidad (Fase 2: `appId` + updater) es un cambio deseado y obligatorio para un fork independiente, a fijar desde el primer release. Los identificadores funcionales internos (Fase 3) deben permanecer como `goose` para el piloto, garantizando "cero cambios de comportamiento".
