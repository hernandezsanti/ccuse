#!/usr/bin/env bash
# cc-mcp-sync.sh — replica los MCP server de scope user entre todas las cuentas.
#
# Los MCP de scope user viven en <configDir>/.claude.json, que es lo único que no
# se puede compartir por symlink porque ahí está el OAuth de la cuenta. Así que un
# `claude mcp add` hecho en una cuenta es invisible desde las otras. Esto empareja.
#
# Escribe con `claude mcp add-json --scope user`, nunca tocando .claude.json a mano:
# son ~160 KB de estado que las sesiones vivas reescriben solas, y editarlo por
# afuera se pisa con ellas. La clave `mcpServers` de settings.json NO sirve para
# esto: está en el esquema pero `claude mcp` no la lee.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

usage() {
  cat >&2 <<'EOF'
uso: cc-mcp-sync.sh [--check] [--dry-run] [--from <label>]

  Sin --from, arma la unión de los MCP de todas las cuentas y le agrega a cada una
  los que le falten. Con --from, replica solo los de esa cuenta.

  --check      solo diagnostica, no escribe nada (exit 1 si falta algo)
  --dry-run    muestra los comandos que correría
EOF
  return 1
}

CHECK=""; DRY=""; FROM=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)   CHECK=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --from)    FROM="${2:-}"; [ -n "$FROM" ] || usage; shift 2 ;;
    -h|--help) usage ;;
    *)         ccm_die "argumento inesperado: $1"; usage ;;
  esac
done

CLAUDE_BIN="${CCM_CLAUDE_BIN:-claude}"
command -v jq >/dev/null 2>&1 || { ccm_die "falta jq"; exit 1; }

say() { printf '%s\n' "$*"; }

# ccm_mcp_servers <configDir> — los MCP de scope user de una cuenta, como objeto.
# Lee .claude.json directo: leer no puede pisar a una sesión viva, escribir sí.
ccm_mcp_servers() {
  jq -c '.mcpServers // {}' "$1/.claude.json" 2>/dev/null || printf '{}'
}

# --- 1. armar la unión ---------------------------------------------------------
# Ante el mismo nombre con distinta definición gana la primera cuenta de
# accounts.json, y se avisa: emparejar a ciegas pisaría una diferencia deliberada.
union='{}'
conflicts=0
while IFS=$'\t' read -r label dir; do
  [ -n "$label" ] || continue
  [ -z "$FROM" ] || [ "$label" = "$FROM" ] || continue
  servers="$(ccm_mcp_servers "$dir")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    incoming="$(printf '%s' "$servers" | jq -c --arg n "$name" '.[$n]')"
    existing="$(printf '%s' "$union" | jq -c --arg n "$name" '.[$n] // empty')"
    if [ -n "$existing" ]; then
      if [ "$existing" != "$incoming" ]; then
        say "OJO  '$name' está definido distinto en [$label]; se respeta el primero"
        conflicts=$((conflicts + 1))
      fi
      continue
    fi
    union="$(printf '%s' "$union" | jq -c --arg n "$name" --argjson v "$incoming" '.[$n] = $v')"
  done < <(printf '%s' "$servers" | jq -r 'keys[]')
done < <(ccm_accounts)

total="$(printf '%s' "$union" | jq -r 'keys | length')"
if [ "$total" -eq 0 ]; then
  say "no hay MCP de scope user para replicar"
  exit 0
fi
say "union $total server(s): $(printf '%s' "$union" | jq -r 'keys | join(", ")')"

# --- 2. agregar a cada cuenta lo que le falte -----------------------------------
missing=0
while IFS=$'\t' read -r label dir; do
  [ -n "$label" ] || continue
  have="$(ccm_mcp_servers "$dir")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if printf '%s' "$have" | jq -e --arg n "$name" 'has($n)' >/dev/null; then
      continue
    fi
    missing=$((missing + 1))
    def="$(printf '%s' "$union" | jq -c --arg n "$name" '.[$n]')"
    if [ -n "$CHECK" ]; then
      say "FALTA $label: $name"
    elif [ -n "$DRY" ]; then
      say "  DRY: CLAUDE_CONFIG_DIR=$dir $CLAUDE_BIN mcp add-json --scope user $name '$def'"
    elif CLAUDE_CONFIG_DIR="$dir" "$CLAUDE_BIN" mcp add-json --scope user "$name" "$def" >/dev/null 2>&1; then
      say "add   $label: $name"
    else
      say "ERROR $label: no pude agregar '$name'"
    fi
  done < <(printf '%s' "$union" | jq -r 'keys[]')
done < <(ccm_accounts)

if [ "$missing" -eq 0 ]; then
  say ""
  say "todas las cuentas ya tienen los $total server(s)"
  exit 0
fi

if [ -n "$CHECK" ]; then
  say ""
  ccm_die "faltan $missing definición(es) — corré: cc-mcp-sync.sh"
  exit 1
fi
