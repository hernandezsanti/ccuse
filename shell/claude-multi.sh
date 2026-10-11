# claude-multi.sh: source it from ~/.zshrc. Works in bash and zsh.
export CCM_HOME="${CCM_HOME:-$HOME/projects/claude-multi-account}"
# shellcheck source=../bin/cc-lib.sh
[ -r "$CCM_HOME/bin/cc-lib.sh" ] && source "$CCM_HOME/bin/cc-lib.sh"

# _ccm_launch <credDir> [args...]: starts claude with the credential of that account.
#
# All accounts run on the same config dir (~/.claude): one daemon, one FleetView,
# everything shared. The only thing that changes per account is where the
# credential comes from, and CLAUDE_SECURESTORAGE_CONFIG_DIR chooses it: Claude Code
# derives the Keychain service from the exact string of that variable (or from
# CLAUDE_CONFIG_DIR if it is not set). So passing the same path that used to go in
# CLAUDE_CONFIG_DIR points to the same Keychain entry, with no new login.
# The default account is selected with the variable set to EMPTY, not unset: when it
# is unset, the lookup falls back to CLAUDE_CONFIG_DIR if someone left it exported.
#
# The subshell keeps these variables out of your terminal.
_ccm_launch() {
  local dir="$1"; shift
  local label; label="$("$CCM_HOME/bin/cc-label.sh" "$dir" 2>/dev/null || echo '?')"
  printf 'cc: using account [%s] (%s)\n' "$label" "$dir"
  local cred="$dir"; [ "$dir" != "$HOME/.claude" ] || cred=""
  if _ccm_use_tmux "$@"; then
    local session; session="$(_ccm_tmux_session_name "$@")"
    if [ -n "${CCM_DRY_RUN:-}" ]; then
      printf 'DRY: tmux new-session -A -s %s env -u CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR=%s claude %s\n' \
        "$session" "${cred:-<default>}" "$*"
      return 0
    fi
    printf 'cc: tmux session [%s] (if the terminal crashes: tmux attach -t %s)\n' "$session" "$session"
    # -A: if the session already exists (by its -n name), attach to it instead of
    # creating a second one. The command is passed as argv (no shell) with an explicit
    # env, because the tmux server keeps the environment of the first client that
    # started it, not yours.
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

# _ccm_use_tmux: should claude run inside a tmux session?
#
# If it does and the terminal hangs or closes, claude keeps running in the tmux
# server and you get it back with `tmux attach`, without losing work.
# Off by default: only with CCM_TMUX=1. Never when you are already inside tmux,
# and never in non-interactive mode (-p).
_ccm_use_tmux() {
  [ "${CCM_TMUX:-}" = "1" ] || return 1
  [ -n "${TMUX:-}" ] && return 1
  command -v tmux >/dev/null 2>&1 || return 1
  local a; for a in "$@"; do case "$a" in -p|--print) return 1 ;; esac; done
  return 0
}

# _ccm_tmux_session_name [args...]: the claude -n/--name value if there is one;
# otherwise cc-<folder>-<hhmmss>. tmux does not accept '.' or ':' in session names.
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

# t <command> [args...]: runs the command with tmux on: `t ccuse work -n x`.
t() { CCM_TMUX=1 "$@"; }

# ccsessions: claude sessions that are still alive in tmux (for example after a
# terminal crash). To attach to one: tmux attach -t <name>
ccsessions() {
  command tmux list-sessions -F '#{session_name}  #{?session_attached,attached,DETACHED}  #{pane_current_path}' 2>/dev/null \
    || echo 'cc: no tmux sessions'
}

# ccx [args...]: opens claude with an account that has quota left
ccx() {
  local pick="${CCM_PICK_CMD:-$CCM_HOME/bin/cc-pick.sh}" dir
  dir="$("$pick")" || { echo 'cc: could not choose an account' >&2; return 1; }
  _ccm_launch "$dir" "$@"
}

# ccswitch [args...]: starts again in another account with quota left (not the current one).
# Without arguments it continues the conversation of the current directory: all
# accounts use the same ~/.claude/projects, so --continue works across accounts.
# With CCM_NO_CONTINUE=1, or with your own arguments, it opens a new session.
ccswitch() {
  local pick="${CCM_PICK_CMD:-$CCM_HOME/bin/cc-pick.sh}" cur dir
  cur="$(ccm_current_dir)"
  dir="$("$pick" "$cur")" || { echo 'cc: no other account with quota left' >&2; return 1; }
  if [ "$#" -eq 0 ] && [ -z "${CCM_NO_CONTINUE:-}" ]; then set -- --continue; fi
  _ccm_launch "$dir" "$@"
}

# ccuse <label> [args...]: opens a specific account by its label
ccuse() {
  local want="${1:-}"; [ -n "$want" ] && shift
  local label dir found=""
  while IFS=$'\t' read -r label dir; do
    if [ "$label" = "$want" ]; then found="$dir"; break; fi
  done < <(ccm_accounts 2>/dev/null)
  [ -n "$found" ] || { echo "cc: account '$want' does not exist" >&2; return 1; }
  _ccm_launch "$found" "$@"
}

# claude-<label> aliases for each account in accounts.json (for example claude-work)
_ccm_mkaliases() {
  local label dir
  while IFS=$'\t' read -r label dir; do
    alias "claude-$label"="ccuse $label"
  done < <(ccm_accounts 2>/dev/null)
}
_ccm_mkaliases
