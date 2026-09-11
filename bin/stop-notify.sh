#!/usr/bin/env bash
# Hook Stop: al terminar el turno, avisa si la cuenta activa está por quedarse
# sin cupo. Lee el estado que deja statusline.sh (sin llamar a la API).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

cat >/dev/null 2>&1 || true   # consumir el JSON de entrada del hook

STATE_DIR="${CCM_STATE_DIR:-$HERE/../state}"
THR="$(ccm_threshold 2>/dev/null || echo 95)"
COOLDOWN="${CCM_NOTIFY_COOLDOWN:-300}"     # no repetir el aviso antes de N segundos
FRESH="${CCM_NOTIFY_FRESH:-600}"           # ignorar lecturas más viejas que N segundos

dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
label="$("$HERE/cc-label.sh" "$dir" 2>/dev/null || echo default)"
slug="$(ccm_slug "$label")"
f="$STATE_DIR/usage-$slug.json"
[ -r "$f" ] || exit 0

now="$(date +%s)"
fh="$(jq -r '.five_hour // empty' "$f" 2>/dev/null)"
sd="$(jq -r '.seven_day // empty' "$f" 2>/dev/null)"
ts="$(jq -r '.ts // 0' "$f" 2>/dev/null)"

# Lectura vieja => no es confiable, no avisar.
[ $((now - ts)) -le "$FRESH" ] || exit 0

over=0
[ -n "$fh" ] && awk "BEGIN{exit !($fh>=$THR)}" && over=1
[ -n "$sd" ] && awk "BEGIN{exit !($sd>=$THR)}" && over=1
[ "$over" -eq 1 ] || exit 0

# Cooldown: no repetir el aviso si ya avisamos hace poco.
nf="$STATE_DIR/last-notify-$slug"
if [ -r "$nf" ]; then
  last="$(cat "$nf" 2>/dev/null || echo 0)"
  [ $((now - last)) -ge "$COOLDOWN" ] || exit 0
fi
mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s' "$now" > "$nf" 2>/dev/null

msg="⚠️ Cuenta [$label] con poco cupo (5h ${fh:-?}%, 7d ${sd:-?}%). Sal con /exit y retoma esta conversación en la otra cuenta con: ccswitch"
jq -cn --arg m "$msg" '{systemMessage:$m}'
