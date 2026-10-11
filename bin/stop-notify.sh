#!/usr/bin/env bash
# Stop hook: when a turn ends, warn if the active account is close to running out
# of quota. It reads the state saved by statusline.sh (it does not call the API).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

cat >/dev/null 2>&1 || true   # consume the hook's input JSON

STATE_DIR="${CCM_STATE_DIR:-$HERE/../state}"
THR="$(ccm_threshold 2>/dev/null || echo 95)"
COOLDOWN="${CCM_NOTIFY_COOLDOWN:-300}"     # do not repeat the warning before N seconds
FRESH="${CCM_NOTIFY_FRESH:-600}"           # ignore readings older than N seconds

dir="$(ccm_current_dir)"
label="$("$HERE/cc-label.sh" "$dir" 2>/dev/null || echo default)"
slug="$(ccm_slug "$label")"
f="$STATE_DIR/usage-$slug.json"
[ -r "$f" ] || exit 0

now="$(date +%s)"
fh="$(jq -r '.five_hour // empty' "$f" 2>/dev/null)"
sd="$(jq -r '.seven_day // empty' "$f" 2>/dev/null)"
ts="$(jq -r '.ts // 0' "$f" 2>/dev/null)"

# An old reading is not reliable, so do not warn.
[ $((now - ts)) -le "$FRESH" ] || exit 0

over=0
[ -n "$fh" ] && awk "BEGIN{exit !($fh>=$THR)}" && over=1
[ -n "$sd" ] && awk "BEGIN{exit !($sd>=$THR)}" && over=1
[ "$over" -eq 1 ] || exit 0

# Cooldown: do not repeat the warning if we warned recently.
nf="$STATE_DIR/last-notify-$slug"
if [ -r "$nf" ]; then
  last="$(cat "$nf" 2>/dev/null || echo 0)"
  [ $((now - last)) -ge "$COOLDOWN" ] || exit 0
fi
mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s' "$now" > "$nf" 2>/dev/null

msg="⚠️ Account [$label] is low on quota (5h ${fh:-?}%, 7d ${sd:-?}%). Exit with /exit and continue this conversation in another account with: ccswitch"
jq -cn --arg m "$msg" '{systemMessage:$m}'
