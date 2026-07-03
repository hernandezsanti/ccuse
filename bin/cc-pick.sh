#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"
ccm_require_deps

EXCLUDE="${1:-}"
USAGE="${CCM_USAGE_CMD:-$HERE/cc-usage.sh}"
THR="$(ccm_threshold)"

best_dir=""; best_use=""
fb_dir=""; fb_reset=""

lt() { awk "BEGIN{exit !($1 < $2)}"; }   # $1 < $2 ?

while IFS=$'\t' read -r _label dir; do
  [ -n "$EXCLUDE" ] && [ "$dir" = "$(ccm_expand "$EXCLUDE")" ] && continue
  u="$("$USAGE" "$dir" 2>/dev/null || true)"
  fh="$(printf '%s' "$u" | jq -r '.five_hour // empty' 2>/dev/null)"
  sd="$(printf '%s' "$u" | jq -r '.seven_day // empty' 2>/dev/null)"
  rs="$(printf '%s' "$u" | jq -r '.five_hour_resets_at // empty' 2>/dev/null)"

  # fallback: reset más cercano (comparación lexicográfica de ISO8601)
  if [ -n "$rs" ]; then
    if [ -z "$fb_reset" ] || [[ "$rs" < "$fb_reset" ]]; then fb_reset="$rs"; fb_dir="$dir"; fi
  fi
  [ -z "$fb_dir" ] && fb_dir="$dir"

  # candidato válido bajo umbral
  [ -n "$fh" ] || continue
  maxu="$(printf '%s\n%s\n' "$fh" "${sd:-0}" | sort -nr | head -1)"
  lt "$maxu" "$THR" || continue
  if [ -z "$best_use" ] || lt "$fh" "$best_use"; then best_use="$fh"; best_dir="$dir"; fi
done < <(ccm_accounts)

if [ -n "$best_dir" ]; then
  printf '%s\n' "$best_dir"
else
  printf 'cc: todas las cuentas al %s%%+; uso la de reset más cercano\n' "$THR" >&2
  printf '%s\n' "$fb_dir"
fi
