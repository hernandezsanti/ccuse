# claude-multi.sh — sourcealo desde ~/.zshrc.  Compatible bash/zsh.
export CCM_HOME="${CCM_HOME:-$HOME/projects/claude-multi-account}"

_ccm_launch() {
  local dir="$1"; shift
  local label; label="$("$CCM_HOME/bin/cc-label.sh" "$dir" 2>/dev/null || echo '?')"
  printf 'cc: usando cuenta [%s] (%s)\n' "$label" "$dir"
  if [ "$dir" = "$HOME/.claude" ]; then unset CLAUDE_CONFIG_DIR
  else export CLAUDE_CONFIG_DIR="$dir"; fi
  if [ -n "${CCM_DRY_RUN:-}" ]; then
    printf 'DRY: CLAUDE_CONFIG_DIR=%s claude %s\n' "${CLAUDE_CONFIG_DIR:-<unset>}" "$*"
    return 0
  fi
  command claude "$@"
}

ccx() {
  local pick="${CCM_PICK_CMD:-$CCM_HOME/bin/cc-pick.sh}" dir
  dir="$("$pick")" || { echo 'cc: no pude elegir cuenta' >&2; return 1; }
  _ccm_launch "$dir" "$@"
}

ccswitch() {
  local pick="${CCM_PICK_CMD:-$CCM_HOME/bin/cc-pick.sh}" cur dir
  cur="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  dir="$("$pick" "$cur")" || { echo 'cc: no hay otra cuenta con cupo' >&2; return 1; }
  _ccm_launch "$dir" "$@"
}
