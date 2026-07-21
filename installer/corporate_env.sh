#!/usr/bin/env bash
##############################################################################
# Genius Assistant — política corporativa horneada (FUENTE ÚNICA DE VERDAD).
#
# La sourcean tanto build_corporate.sh (macOS) como el workflow de Windows,
# para que ambas plataformas horneen EXACTAMENTE las mismas variables en el
# bundle de Electron. Este archivo NO ejecuta nada: solo exporta.
#
# Ver docs/POC_DESIGN.md y docs/SECRET_LIFECYCLE.md.
##############################################################################

# --- Provider corporativo fijo (valores del piloto) ---
export GOOSE_CUSTOM_PROVIDER='{"display_name":"Genius","api_url":"https://api.genius.coppel.services","models":["gemini-3.1-pro-preview"]}'
export GOOSE_DEFAULT_MODEL="gemini-3.1-pro-preview"

# Red de seguridad del fallback: id canónico del provider "Genius"
# (declarative_providers.rs::generate_id → custom_<slug>). Solo se usa si el
# enlace del custom provider falla en el arranque (ModelAndProviderContext §5).
export GOOSE_DEFAULT_PROVIDER="custom_genius"

# --- Políticas: locks de UI + seguridad forzada ---
export GOOSE_LOCK_PROVIDER=1
export GOOSE_LOCK_BACKEND=1
export SECURITY_PROMPT_ENABLED_OVERRIDE=true

# --- Updates: UI oculta (mecanismo oficial de bundles) + sin descargas (I5) ---
export GOOSE_VERSION="1.43.0-genius"
export GOOSE_DISABLE_AUTO_DOWNLOAD=true

# --- Telemetría: apagada y sin prompt de consentimiento (env-first) ---
export GOOSE_TELEMETRY_ENABLED=false

# --- Extensiones: advertir al conectar cualquier MCP externo (consentimiento
# informado). No bloquea; el agente ya está acotado a extensiones pre-configuradas.
export GOOSE_ALLOWLIST_WARNING=true

# --- Marca ---
export GOOSE_BUNDLE_NAME="Genius Assistant"
