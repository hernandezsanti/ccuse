#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

input="$(cat)"
THR="$(ccm_threshold 2>/dev/null || echo 95)"
R='\033[0m'

jget() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

cfg="$(jget '.config_dir')"; cfg="${cfg:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
cfg="$(ccm_expand "$cfg")"
label="$(ccm_accounts 2>/dev/null | awk -F'\t' -v d="$cfg" '$2==d{print $1; f=1} END{if(!f) print "default"}' | head -1)"

fh="$(jget '.rate_limits.five_hour.used_percentage')"
sd="$(jget '.rate_limits.seven_day.used_percentage')"

pick_col() { # $1=pct -> stdout color ANSI (literal escapado)
  if awk "BEGIN{exit !($1>=$THR)}"; then printf '\\033[31m'
  elif awk "BEGIN{exit !($1>=75)}"; then printf '\\033[33m'
  else printf '\\033[32m'; fi
}

out="$label"
if [ -n "$fh" ]; then out="$out · $(pick_col "$fh")5h $(printf '%.0f' "$fh")%$R"; fi
if [ -n "$sd" ]; then out="$out · $(pick_col "$sd")7d $(printf '%.0f' "$sd")%$R"; fi

alert=0
[ -n "$fh" ] && awk "BEGIN{exit !($fh>=$THR)}" && alert=1
[ -n "$sd" ] && awk "BEGIN{exit !($sd>=$THR)}" && alert=1
[ "$alert" -eq 1 ] && out="$out  \\033[1;31m⚠️  ${THR}% — cambia de cuenta: ccswitch$R"

printf '%b' "$out"
