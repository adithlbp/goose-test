# Prompt 01 — Build del binario `goose` (ligero, sin `local-inference`)

> Pégalo a un agente de código en el clon limpio de goose. Objetivo: obtener un binario `goose` funcional para el Desktop sin compilar llama.cpp.

---

## Tarea

Compila el binario `goose` del workspace **sin la feature `local-inference`** y cópialo a la ruta que el Desktop espera. No modifiques ningún archivo del repo para esto — es solo build.

## Contexto (por qué)

- El `default` de `goose-cli` incluye `local-inference` (`crates/goose-cli/Cargo.toml`, sección `[features]`), que arrastra `llama-cpp-sys-2` → compila llama.cpp vía **CMake** (lento y con dependencias pesadas). Para el Desktop corporativo **no se necesita inferencia local**.
- El Desktop busca el binario en `ui/desktop/src/bin/goose`, y como fallback en `target/release/goose` y `target/debug/goose` (`ui/desktop/src/gooseServe.ts`, `findGooseBinaryPath`).

## Pasos

1. Activar el toolchain (hermit provee `cargo`, `pnpm`, `node`, `just`):
   ```bash
   source bin/activate-hermit
   ```
2. Compilar el binario ligero = **`default` menos `local-inference`**:
   ```bash
   cargo build --release -p goose-cli --bin goose \
     --no-default-features \
     --features code-mode,tui,aws-providers,telemetry,nostr,otel,rustls-tls,system-keyring,update
   ```
   > `system-keyring` es **obligatorio** aquí: la arquitectura de credenciales elegida (prompt 07) persiste el secreto en el Keychain vía `Config::set_secret`, que requiere esa feature.
3. Copiar al Desktop (equivale a `just copy-binary`):
   ```bash
   rm -f ui/desktop/src/bin/goosed ui/desktop/src/bin/goose
   cp -p target/release/goose ui/desktop/src/bin/
   ```
4. Instalar deps del Desktop (primera vez):
   ```bash
   cd ui/desktop && pnpm install
   ```

## Verificación

- `./ui/desktop/src/bin/goose --version` responde la versión (ej. `1.43.0`).
- El build **no** compiló `llama-cpp-sys-2` (no aparece en el log; no requirió CMake).
- `cd ui/desktop && pnpm run typecheck` pasa.
- `cd ui/desktop && pnpm run start-gui` levanta la app sin el error "Goose binary not found".

## No hacer

- No añadir `local-inference`, `cuda`, `vulkan`, `mlx` (arrastran llama.cpp).
- No modificar `Cargo.toml` para "arreglar" el build — el problema se resuelve con flags, no con cambios de código.
- No commitear el binario (224 MB); es artefacto de build.
