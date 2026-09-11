#!/usr/bin/env bash
# cc-fleet.sh — vista unificada de las sesiones en background de todas las cuentas.
#
# FleetView (el panel del TUI) lee jobs/ y daemon/roster.json de UN solo config dir, y
# no hay forma de unificarlo: el mutex del roster es <configDir>/daemon.lock, fuera de
# daemon/, así que compartir daemon/ deja dos supervisores creyéndose exclusivos y el
# barrido de huérfanos de uno mata los workers del otro (ver README).
#
# Esto no reemplaza esa pantalla: la lee desde afuera. Solo lectura, sin tomar ningún
# lock y sin escribir nada, que es lo que lo hace seguro.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

usage() {
  cat >&2 <<'EOF'
uso: cc-fleet.sh [--all]

  Lista las sesiones en background de todas las cuentas de accounts.json.

  --all   incluye también las muertas (por defecto solo se listan si decían estar
          trabajando, porque un job terminado y sin proceso es lo normal)

  El estado sale de jobs/<id>/state.json tal cual lo escribe Claude Code: `state`
  (done/working/blocked) y `tempo` (idle/active/blocked). No se reinterpretan a las
  etiquetas del TUI, que no mapean uno a uno.

  "muerta" = el job no tiene worker vivo en el roster de su cuenta. Un job en `working`
  y muerto quedó colgado; uno en `done` y muerto simplemente terminó.
EOF
  return 1
}

ALL=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)     ALL=1; shift ;;
    -h|--help) usage ;;
    *)         ccm_die "argumento inesperado: $1"; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || { ccm_die "falta jq"; exit 1; }

now="$(date +%s)"

# ccm_age <epoch> — antigüedad compacta (45s, 12m, 3h, 2d)
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

    # liveness: el job dice lo que dice, pero manda si su worker sigue vivo
    live=""
    if [ -n "$short" ]; then
      pid="$(jq -r --arg s "$short" '.workers[$s].pid // empty' "$roster" 2>/dev/null || true)"
      if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then live=1; fi
    fi

    # un job terminado y sin proceso es lo normal: solo molesta si decía estar trabajando
    if [ -z "$live" ] && [ -z "$ALL" ] && [ "$state" = "done" ]; then
      hidden=$((hidden + 1)); continue
    fi

    mark="·muerta"; [ -n "$live" ] && mark=""
    [ "$tempo" = "$state" ] || state="$state/$tempo"

    age="$(ccm_age "$(stat -f %m "$state_file" 2>/dev/null || echo "$now")")"
    [ "${#detail}" -le 64 ] || detail="${detail:0:61}..."

    rows+="$(stat -f %m "$state_file" 2>/dev/null || echo 0)"
    rows+=$'\t'"$label"$'\t'"$state$mark"$'\t'"$age"$'\t'"$name"$'\t'"$(basename "$cwd")"$'\t'"$detail"$'\n'
    shown=$((shown + 1))
  done
done < <(ccm_accounts)

if [ "$shown" -eq 0 ]; then
  printf 'no hay sesiones en background\n'
  [ "$hidden" -gt 0 ] && printf '(%s terminada(s) oculta(s) — vela con --all)\n' "$hidden"
  exit 0
fi

{
  printf 'CUENTA\tESTADO\tEDAD\tSESIÓN\tDIR\tDETALLE\n'
  printf '%s' "$rows" | sort -rn | cut -f2-
} | column -t -s $'\t'

[ "$hidden" -gt 0 ] && printf '\n(%s terminada(s) oculta(s) — vela con --all)\n' "$hidden"
exit 0
