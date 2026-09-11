#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

input="$(cat)"
[ -n "${CCM_DUMP_INPUT:-}" ] && printf '%s' "$input" > "$CCM_DUMP_INPUT" 2>/dev/null
THR="$(ccm_threshold 2>/dev/null || echo 95)"
R='\033[0m'
DIM='\033[2m'

jget() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

# La cuenta la dice la credencial, no el config dir: con todas las cuentas sobre
# ~/.claude, .config_dir del JSON es siempre el mismo. La env var la hereda este
# proceso del claude que lo lanzó. Si no está (sesión del modelo viejo), cae al
# config_dir como antes.
cfg="${CLAUDE_SECURESTORAGE_CONFIG_DIR:-}"
[ -n "$cfg" ] || cfg="$(jget '.config_dir')"
cfg="${cfg:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
cfg="$(ccm_expand "$cfg")"
label="$(ccm_accounts 2>/dev/null | awk -F'\t' -v d="$cfg" '$2==d{print $1; f=1} END{if(!f) print "default"}' | head -1)"

model="$(jget '.model.display_name')"
effort="$(jget '.effort.level')"
ctx="$(jget '.context_window.used_percentage')"
fh="$(jget '.rate_limits.five_hour.used_percentage')"
sd="$(jget '.rate_limits.seven_day.used_percentage')"
fhr="$(jget '.rate_limits.five_hour.resets_at')"
sdr="$(jget '.rate_limits.seven_day.resets_at')"

pick_col() { # $1=pct -> stdout color ANSI (literal escapado)
  if awk "BEGIN{exit !($1>=$THR)}"; then printf '\\033[31m'
  elif awk "BEGIN{exit !($1>=75)}"; then printf '\\033[33m'
  else printf '\\033[32m'; fi
}
reset_str() { # $1=epoch $2=fmt -> " ↻<hora>" en dim, o vacío
  local s; [ -n "$1" ] && s="$(date -r "$1" +"$2" 2>/dev/null)" || return 0
  [ -n "$s" ] && printf ' %s↻%s%s' "$DIM" "$s" "$R"
}

out="$label"
[ -n "$model" ]  && out="$out · ${DIM}${model}${R}"
[ -n "$effort" ] && out="$out · ${DIM}${effort}${R}"
[ -n "$ctx" ]    && out="$out · $(pick_col "$ctx")ctx $(printf '%.0f' "$ctx")%$R"
[ -n "$fh" ]     && out="$out · $(pick_col "$fh")5h $(printf '%.0f' "$fh")%$R$(reset_str "$fhr" '%H:%M')"
[ -n "$sd" ]     && out="$out · $(pick_col "$sd")7d $(printf '%.0f' "$sd")%$R$(reset_str "$sdr" '%d/%m %H:%M')"

alert=0
[ -n "$fh" ] && awk "BEGIN{exit !($fh>=$THR)}" && alert=1
[ -n "$sd" ] && awk "BEGIN{exit !($sd>=$THR)}" && alert=1
[ "$alert" -eq 1 ] && out="$out  \\033[1;31m⚠️  ${THR}% — cambia de cuenta: ccswitch$R"

# Guarda el último uso para que el hook Stop lo lea sin llamar a la API.
STATE_DIR="${CCM_STATE_DIR:-$HERE/../state}"
if [ -n "$fh$sd" ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null && \
  jq -cn --arg l "$label" --arg cd "$cfg" \
     --argjson fh "${fh:-null}" --argjson sd "${sd:-null}" \
     --argjson ts "$(date +%s)" \
     '{label:$l,config_dir:$cd,five_hour:$fh,seven_day:$sd,ts:$ts}' \
     > "$STATE_DIR/usage-$(ccm_slug "$label").json" 2>/dev/null || true
fi

printf '%b' "$out"
