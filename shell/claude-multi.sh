# claude-multi.sh — sourcealo desde ~/.zshrc.  Compatible bash/zsh.
export CCM_HOME="${CCM_HOME:-$HOME/projects/claude-multi-account}"
# shellcheck source=../bin/cc-lib.sh
[ -r "$CCM_HOME/bin/cc-lib.sh" ] && source "$CCM_HOME/bin/cc-lib.sh"

# _ccm_launch <credDir> [args...] — lanza claude con la credencial de esa cuenta.
#
# Todas las cuentas corren sobre el mismo config dir (~/.claude): un solo daemon,
# un solo FleetView, todo compartido. Lo único que cambia por cuenta es de dónde
# sale la credencial, y eso lo elige CLAUDE_SECURESTORAGE_CONFIG_DIR: Claude Code
# deriva el servicio de Keychain del string exacto de esa variable (o de
# CLAUDE_CONFIG_DIR si no está), así que pasarle el mismo path que antes iba en
# CLAUDE_CONFIG_DIR apunta a la misma entrada de Keychain sin volver a loguear.
# La cuenta default se pinea con la variable VACÍA, no ausente: ausente hace que
# la derivación caiga en CLAUDE_CONFIG_DIR si alguien lo dejó exportado.
#
# El subshell evita dejar variables pegadas en tu terminal.
_ccm_launch() {
  local dir="$1"; shift
  local label; label="$("$CCM_HOME/bin/cc-label.sh" "$dir" 2>/dev/null || echo '?')"
  printf 'cc: usando cuenta [%s] (%s)\n' "$label" "$dir"
  local cred="$dir"; [ "$dir" != "$HOME/.claude" ] || cred=""
  if _ccm_use_tmux "$@"; then
    local session; session="$(_ccm_tmux_session_name "$@")"
    if [ -n "${CCM_DRY_RUN:-}" ]; then
      printf 'DRY: tmux new-session -A -s %s env -u CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR=%s claude %s\n' \
        "$session" "${cred:-<default>}" "$*"
      return 0
    fi
    printf 'cc: sesión tmux [%s] (si la terminal se cae: tmux attach -t %s)\n' "$session" "$session"
    # -A: si la sesión ya existe (por nombre -n), se engancha en vez de duplicarla.
    # El comando va como argv (sin shell) y con env explícito, porque el servidor
    # de tmux guarda el entorno del primer cliente que lo arrancó, no el tuyo.
    command tmux new-session -A -s "$session" -c "$PWD" \
      env -u CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR="$cred" claude "$@"
    return
  fi
  if [ -n "${CCM_DRY_RUN:-}" ]; then
    printf 'DRY: CLAUDE_CONFIG_DIR=<unset> CLAUDE_SECURESTORAGE_CONFIG_DIR=%s claude %s\n' \
      "${cred:-<default>}" "$*"
    return 0
  fi
  ( unset CLAUDE_CONFIG_DIR; export CLAUDE_SECURESTORAGE_CONFIG_DIR="$cred"; command claude "$@" )
}

# _ccm_use_tmux — ¿envolver claude en una sesión de tmux?
#
# Así, si la terminal (Warp) se cuelga o se cierra, claude sigue vivo en el
# servidor de tmux y se recupera con `tmux attach`, sin cortar nada a medias.
# Apagado por default: solo con CCM_TMUX=1. Nunca si ya estás dentro de tmux,
# ni en modo no interactivo (-p).
_ccm_use_tmux() {
  [ "${CCM_TMUX:-}" = "1" ] || return 1
  [ -n "${TMUX:-}" ] && return 1
  command -v tmux >/dev/null 2>&1 || return 1
  local a; for a in "$@"; do case "$a" in -p|--print) return 1 ;; esac; done
  return 0
}

# _ccm_tmux_session_name [args...] — el -n/--name de claude si viene; si no,
# cc-<carpeta>-<hhmmss>. tmux no acepta '.' ni ':' en nombres de sesión.
_ccm_tmux_session_name() {
  local name="" prev=""
  local a; for a in "$@"; do
    case "$prev" in -n|--name) name="$a"; break ;; esac
    case "$a" in --name=*) name="${a#--name=}"; break ;; esac
    prev="$a"
  done
  [ -n "$name" ] || name="cc-${PWD##*/}-$(date +%H%M%S)"
  printf '%s' "$name" | tr '.: ' '---'
}

# t <comando> [args...] — corre el comando con tmux activado: `t ccuse dos -n x`.
t() { CCM_TMUX=1 "$@"; }

# ccsessions — sesiones de claude que siguen vivas en tmux (p. ej. tras un
# crash de la terminal). Engancharse a una: tmux attach -t <nombre>
ccsessions() {
  command tmux list-sessions -F '#{session_name}  #{?session_attached,enganchada,SUELTA}  #{pane_current_path}' 2>/dev/null \
    || echo 'cc: no hay sesiones de tmux'
}

# ccx [args...] — abre claude eligiendo la cuenta con cupo
ccx() {
  local pick="${CCM_PICK_CMD:-$CCM_HOME/bin/cc-pick.sh}" dir
  dir="$("$pick")" || { echo 'cc: no pude elegir cuenta' >&2; return 1; }
  _ccm_launch "$dir" "$@"
}

# ccswitch [args...] — relanza en otra cuenta con cupo (distinta a la actual)
# Sin argumentos retoma la conversación del directorio actual: todas las cuentas
# usan el mismo ~/.claude/projects, así que --continue cruza cuentas.
# Con CCM_NO_CONTINUE=1, o pasando tus propios argumentos, abre sesión nueva.
ccswitch() {
  local pick="${CCM_PICK_CMD:-$CCM_HOME/bin/cc-pick.sh}" cur dir
  cur="$(ccm_current_dir)"
  dir="$("$pick" "$cur")" || { echo 'cc: no hay otra cuenta con cupo' >&2; return 1; }
  if [ "$#" -eq 0 ] && [ -z "${CCM_NO_CONTINUE:-}" ]; then set -- --continue; fi
  _ccm_launch "$dir" "$@"
}

# ccuse <label> [args...] — abre una cuenta puntual por su nombre
ccuse() {
  local want="${1:-}"; [ -n "$want" ] && shift
  local label dir found=""
  while IFS=$'\t' read -r label dir; do
    if [ "$label" = "$want" ]; then found="$dir"; break; fi
  done < <(ccm_accounts 2>/dev/null)
  [ -n "$found" ] || { echo "cc: no existe la cuenta '$want'" >&2; return 1; }
  _ccm_launch "$found" "$@"
}

# aliases claude-<label> por cada cuenta de accounts.json (p. ej. claude-work)
_ccm_mkaliases() {
  local label dir
  while IFS=$'\t' read -r label dir; do
    alias "claude-$label"="ccuse $label"
  done < <(ccm_accounts 2>/dev/null)
}
_ccm_mkaliases
