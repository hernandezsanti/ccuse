#!/usr/bin/env bash
# cc-fleet.sh: one view of the background sessions of all accounts.
#
# FleetView (the TUI panel) reads jobs/ and daemon/roster.json from ONE config dir,
# and it cannot be shared: the roster lock is <configDir>/daemon.lock, outside
# daemon/, so sharing daemon/ leaves two supervisors that both think they are alone,
# and the orphan cleanup of one kills the workers of the other.
#
# This does not replace that panel: it reads the same files from outside. It is read
# only, takes no lock and writes nothing, which is what makes it safe.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: cc-fleet.sh [--all]

  Lists the background sessions of all accounts in accounts.json.

  --all   also include dead sessions (by default they are only listed if they
          said they were working, because a finished job without a process is normal)

  The status comes from jobs/<id>/state.json exactly as Claude Code writes it: `state`
  (done/working/blocked) and `tempo` (idle/active/blocked). They are not mapped to the
  TUI labels, which do not match one to one.

  "dead" = the job has no live worker in the roster of its account. A dead job in
  `working` is stuck; a dead job in `done` simply finished.
EOF
  return 1
}

ALL=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)     ALL=1; shift ;;
    -h|--help) usage ;;
    *)         ccm_die "unexpected argument: $1"; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || { ccm_die "jq is missing"; exit 1; }

now="$(date +%s)"

# ccm_age <epoch>: short age (45s, 12m, 3h, 2d)
ccm_age() {
  local s=$(( now - $1 ))
  [ "$s" -lt 0 ] && s=0
  if   [ "$s" -lt 60 ]    ; then printf '%ss' "$s"
  elif [ "$s" -lt 3600 ]  ; then printf '%sm' $(( s / 60 ))
  elif [ "$s" -lt 86400 ] ; then printf '%sh' $(( s / 3600 ))
  else                           printf '%sd' $(( s / 86400 ))
  fi
}

rows=""
shown=0
hidden=0

while IFS=$'\t' read -r label dir; do
  [ -n "$label" ] || continue
  roster="$dir/daemon/roster.json"
  for state_file in "$dir"/jobs/*/state.json; do
    [ -f "$state_file" ] || continue

    IFS=$'\t' read -r state tempo name cwd short detail < <(
      jq -r '[(.state//"?"), (.tempo//"?"), (.name//.sessionId//"?"),
              (.cwd//"?"), (.daemonShort//""), ((.detail//"")|gsub("\\s+";" "))]
             | @tsv' "$state_file" 2>/dev/null
    ) || continue

    # liveness: the job says what it says, but what counts is whether its worker is alive
    live=""
    if [ -n "$short" ]; then
      pid="$(jq -r --arg s "$short" '.workers[$s].pid // empty' "$roster" 2>/dev/null || true)"
      if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then live=1; fi
    fi

    # a finished job without a process is normal: it only matters if it said it was working
    if [ -z "$live" ] && [ -z "$ALL" ] && [ "$state" = "done" ]; then
      hidden=$((hidden + 1)); continue
    fi

    mark="·dead"; [ -n "$live" ] && mark=""
    [ "$tempo" = "$state" ] || state="$state/$tempo"

    age="$(ccm_age "$(stat -f %m "$state_file" 2>/dev/null || echo "$now")")"
    [ "${#detail}" -le 64 ] || detail="${detail:0:61}..."

    rows+="$(stat -f %m "$state_file" 2>/dev/null || echo 0)"
    rows+=$'\t'"$label"$'\t'"$state$mark"$'\t'"$age"$'\t'"$name"$'\t'"$(basename "$cwd")"$'\t'"$detail"$'\n'
    shown=$((shown + 1))
  done
done < <(ccm_accounts)

if [ "$shown" -eq 0 ]; then
  printf 'no background sessions\n'
  [ "$hidden" -gt 0 ] && printf '(%s finished session(s) hidden; use --all to show them)\n' "$hidden"
  exit 0
fi

{
  printf 'ACCOUNT\tSTATE\tAGE\tSESSION\tDIR\tDETAIL\n'
  printf '%s' "$rows" | sort -rn | cut -f2-
} | column -t -s $'\t'

[ "$hidden" -gt 0 ] && printf '\n(%s finished session(s) hidden; use --all to show them)\n' "$hidden"
exit 0
