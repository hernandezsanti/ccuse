#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

DIR="${1:?uso: cc-usage.sh <configDir>}"
ccm_require_deps

emit_err() { printf '{"five_hour":null,"seven_day":null,"error":"%s"}\n' "$1"; exit 1; }

tok="$(ccm_read_token "$DIR")" || emit_err "no-auth"

resp="$(curl -sS --max-time 5 \
  -H "Authorization: Bearer $tok" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Content-Type: application/json" \
  https://api.anthropic.com/api/oauth/usage)" || emit_err "network"

# El endpoint /api/oauth/usage entrega utilization ya en escala 0-100 (verificado empíricamente).
printf '%s' "$resp" | jq -c '{
  five_hour:            (.five_hour.utilization // null),
  seven_day:            (.seven_day.utilization // null),
  five_hour_resets_at:  (.five_hour.resets_at // null),
  seven_day_resets_at:  (.seven_day.resets_at // null)
}' 2>/dev/null || emit_err "parse"
