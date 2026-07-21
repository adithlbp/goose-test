# Prompt 02 — UI / Branding ("Genius Assistant" + paleta Coppel)

> Pégalo a un agente de código en el clon limpio. Objetivo: rebrandear la marca visible sin cambiar comportamiento funcional. **Método idempotente y robusto al upstream** (reglas, no pares de strings exactos): re-ejecutarlo no rompe nada ni duplica.

---

## Idempotencia (léelo primero)
- Los sweeps de texto usan una **regla** (reemplazar la marca "Goose"/"goose" → "Genius Assistant" protegiendo `.goosehints`/`goose://`). Si ya está aplicado, hacen **0 reemplazos**. Seguro re-ejecutar.
- Antes de cada bloque, verifica si ya está hecho (los comandos de "Verificación" sirven de guard). Si `productName` ya es "Genius Assistant" y `Goose.tsx` ya tiene `<circle>`, no repitas.

## Paleta Coppel
| Rol | Color |
|---|---|
| Acento/interactivo (light) + outline de foco | Coppel Blue `#1C42E8` |
| Acento en tema oscuro | Light Blue `#1CA8F7` |
| Logo / app icon / highlights | Coppel Yellow `#F0D224` |

---

## A. Texto de marca — archivos discretos (`ui/desktop/`)
Ediciones puntuales (idempotentes: si ya dicen "Genius Assistant", omite):
1. `package.json`: `name`→`genius-assistant-app`, `productName`→`Genius Assistant`, `description`→`Genius Assistant App`. **No** cambiar `version`.
2. `index.html`: `<title>Genius Assistant</title>`.
3. `src/main.ts`:
   - `applicationName: 'Genius Assistant'` (About panel).
   - Notificación open-file `title: 'Genius Assistant'`.
   - Diálogo de error `title: 'Genius Assistant Failed to Start'`.
   - Mapa de traducción de menú zh-CN: cambiar las **claves + valores** de `'Focus Goose Window'`/`'About Goose'`/`'Hide Goose'` a `Genius Assistant`, **y** las llamadas `menuT('Focus Genius Assistant Window')`/`menuT('About Genius Assistant')` para que coincidan (si no coinciden, `menuT` cae a inglés). `'Hide Genius Assistant'` debe coincidir con el label que macOS auto-genera desde `productName`.
4. `forge.config.ts`: `NSMicrophoneUsageDescription` / `NSAppleEventsUsageDescription` → `Genius Assistant needs…`.
5. `forge.deb.desktop` y `forge.rpm.desktop`: **solo** `Name=Genius Assistant`. NO tocar `Exec=`/`Icon=`/`bin`/`prefix` (rutas funcionales; deb usa minúscula, rpm mayúscula — inconsistencia de upstream).

## B. Texto de marca — sweeps por regla (idempotentes)

### B.1 `defaultMessage` en componentes
El inglés visible vive en los `defaultMessage` inline (`src/i18n/index.ts` → para `en`, `loadMessages` devuelve `{}` y react-intl usa el `defaultMessage`). Reemplaza la marca **solo dentro de líneas `defaultMessage:`**, protegiendo `.goosehints`/`goose://`:

```bash
cd ui/desktop
node -e '
const fs=require("fs"),{execSync}=require("child_process");
const files=execSync("grep -rl \"defaultMessage:\" src --include=*.tsx --include=*.ts",{encoding:"utf8"})
  .split("\n").filter(Boolean).filter(f=>!/\.test\.|__tests__|\/i18n\/messages\//.test(f));
const re=/(?<![.\w])[Gg]oose(?![\w:])/g;
let repl=0;
for(const f of files){const L=fs.readFileSync(f,"utf8").split("\n");let t=false;
  for(let i=0;i<L.length;i++){ if(L[i].includes("defaultMessage:")&&re.test(L[i])){repl+=(L[i].match(re)||[]).length;L[i]=L[i].replace(re,"Genius Assistant");t=true;} }
  if(t)fs.writeFileSync(f,L.join("\n"));}
console.log("defaultMessage reemplazos:",repl);'
```

### B.2 Catálogos i18n (`src/i18n/messages/*.json`, 16 locales)
Transforma **solo valores** (JSON.parse→walk→stringify) para no tocar claves:

```bash
node -e '
const fs=require("fs"),path=require("path"),dir="src/i18n/messages";
const re=/(?<![.\w])[Gg]oose(?![\w:])/g;let repl=0;
const tr=v=>typeof v==="string"?(repl+=(v.match(re)||[]).length,v.replace(re,"Genius Assistant"))
  :Array.isArray(v)?v.map(tr):v&&typeof v==="object"?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,tr(x)])):v;
for(const f of fs.readdirSync(dir).filter(f=>f.endsWith(".json"))){const p=path.join(dir,f);
  fs.writeFileSync(p,JSON.stringify(tr(JSON.parse(fs.readFileSync(p,"utf8"))),null,2)+"\n");}
console.log("i18n reemplazos:",repl);'
```

## C. Colores (tokens de tema — data, no lógica)
6. `src/theme/theme-tokens.ts`: en `lightColorTokens` los tokens `info` (`--color-background-info`, `--color-text-info`, `--color-border-info`, `--color-ring-info`) → `#1c42e8`; en `darkColorTokens` los mismos → `#1ca8f7`. NO tocar otros tokens.
7. `src/styles/main.css`: `--color-block-teal` → `#1c42e8` (focus outline); `--highlight-color`/`--highlight-current` → `rgba(240, 210, 36, …)`. Conservar nombres de token, cambiar solo valores.

## D. Logo (tres puntos)
8. `src/components/icons/Goose.tsx`: reemplaza el glifo por tres círculos `fill="currentColor"`. **Conserva los exports `Goose` y `Rain`** (no toques imports).
9. `src/images/icon.svg`: fondo rounded-rect `#1C42E8` + tres círculos `#F0D224`. `src/images/glyph.svg`: tres círculos `#101010` (template monocromo).
10. **Iconos binarios** (`icon.png/@2x`, `icon.ico`, `icon.icns`, `iconTemplate.png/@2x`): dos opciones —
    - **(a) Regenerar** desde los SVG: `sh src/images/prepare.sh` (requiere ImageMagick `convert` + `iconutil`). Si no hay ImageMagick, instálalo temporalmente y desinstálalo al terminar.
    - **(b) Copiar desde un clon de referencia ya rebrandeado** (MISMA versión de goose): `cp` de esos 6 binarios + `icon.svg`/`glyph.svg`. Es **seguro solo si la versión coincide** (los assets son autocontenidos). Verifica tamaños: los rebrandeados pesan ~281 KB (icns), ~83 KB (png), ~370 KB (ico).

## Verificación (sirve de guard de idempotencia)
```bash
cd ui/desktop
grep '"productName"' package.json                     # → "Genius Assistant"
grep -rc "defaultMessage:.*[Gg]oose" src | grep -v ':0' # solo .goosehints/goose://
grep -c '1c42e8' src/theme/theme-tokens.ts             # > 0
grep -c '<circle' src/components/icons/Goose.tsx        # = 3
pnpm run typecheck && pnpm run i18n:compile             # ambos pasan (requiere node_modules)
```
`pnpm run start-gui`: título/About/onboarding/menús "Genius Assistant" en cualquier idioma; acentos azules; highlights amarillos; logo de tres puntos; icono del Dock rebrandeado (si se regeneró/copió).

## No hacer
- No renombrar clases CSS `goose-*` ni identificadores funcionales (Keychain, rutas Block/goose, `goose://`, `GOOSE_*`, `appId`, owner/repo del updater).
- No tocar `crates/`.

Referencia con diffs originales: [`BRANDING_IMPLEMENTATION.md`](../BRANDING_IMPLEMENTATION.md).
