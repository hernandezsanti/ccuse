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
  if [ -n "${CCM_DRY_RUN:-}" ]; then
    printf 'DRY: CLAUDE_CONFIG_DIR=<unset> CLAUDE_SECURESTORAGE_CONFIG_DIR=%s claude %s\n' \
      "${cred:-<default>}" "$*"
    return 0
  fi
  ( unset CLAUDE_CONFIG_DIR; export CLAUDE_SECURESTORAGE_CONFIG_DIR="$cred"; command claude "$@" )
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
