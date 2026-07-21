# Diseño final — PoC Genius Assistant (fork corporativo de Goose Desktop)

> Documento de diseño y recomendación técnica. Fecha: 2026-07-18. **No incluye código.**
> Premisas fijadas por el piloto: secreto en Keychain/CredMan/Secret Service vía
> `Config`+`SecretStorage` de Goose (sin tocarlos); helper que nunca escribe al
> Keychain directamente; token nunca por argv; `crates/goose` intacto; fork de vida
> larga con actualizaciones de upstream infrecuentes; sin provisioning por terceros;
> **sin Apple Developer ID en esta fase** (requisito de producción, no de PoC).

---

## 1. Arquitectura recomendada

### 1.1 Vista general (sin cambios estructurales respecto a lo construido)

```
BUILD (CI interno)
  env horneadas por Vite define (provider Genius, locks, security overrides)
  → pnpm run make → .app con goose CONGELADO en Resources/bin/

INSTALACIÓN (una vez por máquina)
  install_genius.sh/.ps1 (no interactivo)
    1. copia la .app / binario
    2. coloca adversary.md
    3. printf '%s' "$TOKEN" | provision_secret.py  ──▶ goose acp (JSON-RPC stdio)
                                                        └─▶ _goose/unstable/config/upsert
                                                             └─▶ Config::set_secret()
                                                                  └─▶ Keychain / CredMan / Secret Service

RUNTIME
  primer arranque → auto-creación provider "Genius" + enlace del secreto ya provisionado
  goosed lee vía Config::get_secret() — sin env, sin disco, sin UI
```

Todo lo anterior ya existe y está probado en vivo (2026-07-17/18). La reevaluación
no cambia la arquitectura: cambia **tres decisiones operativas** (§1.2–§1.4).

### 1.2 Entrega del token al helper: **stdin** (decisión 3 — evaluación)

| Alternativa | Exposición | Veredicto |
|---|---|---|
| argv (`--token sk-…`) | `ps`, argv, historial | ❌ descartada (estado actual del helper; corregir cuando se reanude código) |
| **stdin** (`printf '%s' "$TOKEN" \| helper --token-stdin`) | ninguna visible: pipe anónimo entre procesos del mismo usuario | ✅ **recomendada** |
| env var del proceso helper | visible en `ps -Eww` para el mismo usuario/root; muere con el proceso | aceptable, inferior a stdin |
| archivo temporal 0600 + borrado | toca disco (viola el espíritu de "sin texto plano") | ❌ |
| descriptor dedicado (fd 3) | equivalente a stdin con más ceremonia | innecesario |

stdin es la opción correcta y además **ya es como viaja el token en el tramo
crítico**: helper → `goose acp` va por el stdin del proceso hijo (JSON-RPC), nunca
por argv de goose. El único tramo expuesto hoy es instalador → helper (argv), y se
cierra con un cambio de ~5 líneas **en el helper** (aceptar el valor por stdin),
sin tocar Goose. Usar `printf '%s'` (builtin, sin proceso visible) y no `echo` con
token literal tecleado (historial); en el instalador el token ya llega por env
del canal interno, no se teclea.

### 1.3 ¿`goose secret set` o seguir con ACP? (decisiones 5 y 6)

**Veredicto: NO implementarlo ahora. Seguir con `_goose/unstable/config/upsert`.**

| Pregunta | Respuesta |
|---|---|
| ¿Vale la pena hoy? | **No.** El único beneficio inmediato real (argv en `ps`) se resuelve en el helper (§1.2) sin tocar goose-cli. El beneficio de estabilidad de contrato es proporcional a la frecuencia de rebases — y la premisa es que serán **infrecuentes**. |
| ¿Qué costo tiene? | ~60 líneas en `crates/goose-cli` que se convierten en **diff permanente del fork durante años**: acarrearlo en cada rebase, testearlo en vivo, documentarlo, y mantener dos vías de provisioning (la ACP no desaparece: la usa la app internamente). Contradice el objetivo #1 (mínima distancia a upstream). |
| ¿Qué beneficio real aporta? | Contrato propio estable + instalador sin JSON-RPC + exit codes limpios. Todos son beneficios de **conveniencia**, no de necesidad: hay exactamente **un** consumidor (nuestro instalador), controlado por nosotros, ya probado end-to-end. |
| ¿Cuándo implementarlo? | Por **trigger**, no preventivamente: (a) un rebase futuro elimina/cambia el método `unstable` — ese es el momento natural, con el mismo arnés de prueba; (b) aparece provisioning por terceros/MDM que no pueda hablar JSON-RPC (la premisa dice que no existe); (c) la política cambia a rebases frecuentes. |

Mitigación del riesgo `unstable` sin código: **pin de facto** — el fork no rebasea
frecuentemente, así que el método no puede cambiar "por debajo"; y añadir al
checklist de rebase: *"verificar `_goose/unstable/config/upsert` con
`provision_secret.py --read-only`"* (30 segundos, detecta la ruptura en el momento
correcto).

### 1.4 Firma en la PoC sin Developer ID — análisis de alternativas

Contexto demostrado (2026-07-18, prueba A→B en este árbol): con firma ad-hoc, la
ACL del item del Keychain se ata al **CDHash** (hash del contenido del binario).
Lectura con el binario creador: 4.6 s, silenciosa. Lectura con un binario de hash
distinto: **bloqueada 45 s** (sin UI visible del prompt para un proceso headless
— peor que el diálogo: cuelga).

**Dato decisivo para esta PoC**: el 100% del diff del fork es no-Rust
(`ui/desktop` TS/assets + instaladores). El binario `goose` compilado el
2026-07-17 no necesita cambiar para iterar la PoC. Además, el único item de
Keychain en juego es el de `goose` (la app Electron no usa `safeStorage`), así que
la identidad de Electron es irrelevante para este problema.

| Alternativa | Ventajas | Limitaciones | ¿Elimina o reduce? | ¿Aceptable para PoC? |
|---|---|---|---|---|
| **A. Congelar el binario `goose`; iterar solo recursos** (app.asar/JS/assets; el binario archivado una vez con checksum y reutilizado en cada empaquetado) | Cero prompts mientras el binario no cambie; compatible con la forma real del fork (todo el diff es UI); cero infraestructura nueva | Cualquier cambio Rust (nuestro o bump de upstream) rompe la congelación; los builds de Rust **no son bit-idénticos garantizados** entre máquinas → hay que archivar el artefacto, no recompilarlo | **Elimina** (condicionado a la disciplina de no tocar el binario) | ✅ **Sí — recomendada como primaria** |
| **B. "Reutilizar la misma firma ad-hoc"** | — | **No existe técnicamente**: la firma ad-hoc *es* el CDHash del contenido; no hay nada transplantable entre binarios distintos | No aplica | ❌ (descartar la idea; ver B′) |
| **B′. Certificado interno/self-signed** (identidad de firma propia, confiada en las máquinas del piloto vía MDM/admin) | Designated Requirement estable entre builds **sin** Apple; lo más parecido a Developer ID | Requiere desplegar confianza del cert en cada máquina (admin/MDM); fricción Gatekeeper en distribución (app "no verificada"); **no demostrado** — exigiría su propia prueba A→B firmada | Potencialmente **elimina** (pendiente de validación) | ⚠️ Solo si ya existe MDM que despliegue el cert; si no, el costo supera a la alternativa A |
| **C. Versión única, sin updates durante la PoC** | La más simple; provisionar una vez y no tocar | No permite iterar nada del bundle si se interpreta estrictamente (aunque con A, los recursos sí pueden iterar) | **Elimina** por definición | ✅ Sí — es el caso degenerado de A |
| **D. Reset programado del secreto en cada update del binario** (`security delete-generic-password -s goose` + re-provisionar con el binario nuevo, dentro del propio flujo de update) | Convierte el prompt impredecible en un paso determinístico y silencioso del instalador; el binario nuevo crea el item → ACL correcta desde cero | Borra **todos** los secretos de goose de la máquina (en el piloto solo existe el nuestro); el token debe re-entregarse en cada update (el canal del instalador ya lo tiene); usa la herramienta `security` (excepción puntual y justificada al principio "solo Goose escribe": es *borrado*, no escritura, y ocurre en mantenimiento, no en operación) | **Elimina** el prompt (a costa de un paso extra por update) | ✅ Sí — **válvula de escape** para cuando el binario sí deba cambiar |
| **E. "Permitir siempre" manual por build** | Cero ingeniería | Un prompt por update por máquina; y el riesgo demostrado del cuelgue headless si el diálogo pasa desapercibido; educación de usuarios ("hagan clic en Permitir" es un mal hábito de seguridad) | Solo **reduce** | ⚠️ Último recurso, no como plan |
| ~~F. `GOOSE_DISABLE_KEYRING` → secrets.yaml~~ | — | Texto plano en disco | — | ❌ Viola la decisión #1 (anti-patrón Genius Code) |

**Recomendación PoC**: **A como régimen normal + D como procedimiento de update**
cuando el binario `goose` deba cambiar. Complemento obligatorio: **desactivar el
auto-updater** en el build de la PoC (o apuntarlo a un release interno vacío) —
hoy apunta por defecto a `aaif-goose` público; un update automático reemplazaría
el binario y reintroduciría el problema por la puerta de atrás.

---

## 2. Riesgos conocidos

1. **ACL del Keychain por CDHash con firma ad-hoc** (demostrado). Forma peligrosa:
   no es solo un diálogo — un `goosed` headless se **cuelga** esperando
   autorización (45 s observados, indefinido sin watchdog).
2. **Método ACP `unstable`**: upstream puede cambiarlo sin aviso. Materializable
   solo en rebases (infrecuentes por premisa). Detección: checklist de rebase (§1.3).
3. **Token único por plataforma**: radio de explosión total si se filtra; mitigado
   por monitoreo/revocación en el gateway (decisión de la reunión 2026-06-24).
4. **Fallback silencioso a `secrets.yaml`**: ciertos fallos del keyring degradan a
   archivo en claro (`base.rs:641-649`). Señal de auditoría: la existencia de ese
   archivo en una máquina del piloto = incidente a revisar.
5. **Eclipse por variable de entorno**: `CUSTOM_GENIUS_API_KEY` en el entorno del
   proceso eclipsa al Keychain (precedencia env-first). Vector de confusión más
   que de ataque local.
6. **Adversary mode es fail-open y por-tool**: si el LLM no responde, permite; solo
   revisa las tools del frontmatter. Es control de mejor esfuerzo, no sandbox.
7. **Gatekeeper/cuarentena sin firma**: la .app sin notarizar requiere
   click-derecho-Abrir o excepción MDM en cada máquina del piloto.

## 3. Riesgos aceptados para la PoC (explícitos y temporales)

- **Firma ad-hoc** con disciplina de binario congelado (A) + reset en updates (D).
  Aceptado porque el piloto es interno y la premisa lo permite.
- **Token embebido en el canal del instalador interno** (no en el binario, no en
  texto plano en repos públicos): riesgo aceptado en la reunión 2026-06-24,
  compensado por revocabilidad.
- ~~Exposición argv del helper~~ — **cerrado 2026-07-18**: el helper acepta
  `--token-stdin` y los instaladores pipean el token (probado en vivo).
- **Fricción Gatekeeper** (apertura manual / excepción) en la instalación.
- **Un solo token para toda la plataforma** durante toda la PoC.

## 4. Qué cambiaría antes de pasar a producción

1. **Apple Developer ID + notarización** (y firma Windows con **Azure Trusted
   Signing** vía CI, como upstream — no un cert en `forge.config.ts`; Windows sale
   como ZIP portable, no instalador), con la **prueba A→B firmada** como criterio de
   aceptación (verificar que el DR por Team ID elimina el re-prompt entre versiones
   — hoy [NO DEMOSTRADO]).
2. **Auto-update firmado** apuntando a releases internos (hoy: updater desactivado).
3. **Rotación de token institucionalizada** (calendario + procedimiento §7 del
   `SECRET_LIFECYCLE.md`), y reevaluar token por-usuario o binding adicional en el
   gateway (mTLS de red corporativa, IP allowlist) — el token único es aceptable
   para PoC, débil para producción.
4. **Telemetría de salud del secreto**: detección centralizada de `secrets.yaml`
   presente, de 401 sostenidos (token revocado/roto) y de cuelgues de keychain.
5. **Decisión formal sobre `goose secret set`** en el primer rebase que toque el
   área ACP (trigger de §1.3), no antes.
6. **Endurecer el instalador**: helper con stdin (§1.2), verificación de checksum
   del binario congelado, y firma del propio script de instalación.

## 5. Qué NO implementaría todavía — y por qué

| No implementar | Por qué |
|---|---|
| `goose secret set` en goose-cli | Sin beneficio técnico neto hoy (§1.3): su única ventaja inmediata se resuelve en el helper; el resto es elegancia que cuesta un diff permanente de años. Implementar por trigger, no por estética. |
| `osxSign`/`osxNotarize` en `forge.config.ts` | Sin identidad real que configurar; un bloque especulativo es código muerto que da falsa sensación de "firma lista". Se añade el día que exista el cert (cambio de ~10 líneas, bien documentado por Electron Forge). |
| Certificado interno (B′) | Solo tiene sentido si el MDM ya existe y lo despliega; añade una prueba A→B propia que hoy no podemos amortizar. Reevaluar si la PoC se alarga y los updates de binario se vuelven frecuentes. |
| Provisioning dinámico (SSO/endpoint de tokens) | La premisa dice que no hay terceros automatizando; el `provision_secret.py` no cambia cuando esto llegue — solo cambia de dónde sale `$TOKEN`. Diseñado para enchufarse después sin retrabajo. |
| Tokens por usuario | Decisión explícita de la reunión (control centralizado); revisitar en producción con datos del piloto. |
| Cualquier cambio en `crates/goose` o `crates/goose-cli` | Decisiones 4 y 5: la infraestructura existente cubre el 100% del flujo, demostrado en vivo dos días consecutivos. |

---

### Operación: recuperación ante fallos del provisioning

Cerrado el 2026-07-18 (era la última pieza operativa abierta): runbook completo en
`SECRET_LIFECYCLE.md` §9 — 6 invariantes verificables (I1–I6), matriz de 8
síntomas → diagnóstico → recuperación (S1–S8), 5 procedimientos (P1
re-provisioning idempotente, P2 reset de enlace, P3 reset de item Keychain, P4
reset de config, P5 rotación), verificación post-recuperación y anti-patrones
("Permitir siempre", env vars de prueba, `GOOSE_DISABLE_KEYRING`). Propiedad
clave: **ningún fallo es terminal** — el peor caso se resuelve con P4+P1 en ~2
minutos por máquina, porque el secreto y la config local son siempre
reconstruibles desde el canal del instalador.

### Apéndice — evidencia que sustenta este diseño

- Prueba en vivo provisioning ACP→Keychain: 2026-07-17 (upsert/read/remove, item
  `svce="goose"`, sin `secrets.yaml`).
- Prueba A→B (update ad-hoc): 2026-07-18 — baseline 4.6 s vs bloqueo 45 s; CDHash
  `99b2375c…` vs `47459de0…`. Detalle en `SECRET_LIFECYCLE.md` §4.
- Forma del diff del fork: exclusivamente `ui/desktop` + instaladores (auditable
  en `CHANGES_REVIEW.md`) — habilita la alternativa A.
