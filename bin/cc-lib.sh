# cc-lib.sh — helpers compartidos. Sin shebang: se sourcea.
CCM_ROOT="${CCM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CCM_ACCOUNTS_FILE="${CCM_ACCOUNTS_FILE:-$CCM_ROOT/accounts.json}"

ccm_die() { printf 'cc: %s\n' "$*" >&2; return 1; }

ccm_require_deps() {
  local c missing=()
  for c in jq curl security shasum; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [ "${#missing[@]}" -eq 0 ] || ccm_die "faltan dependencias: ${missing[*]}"
}

ccm_expand() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

ccm_threshold() { jq -r '.threshold // 95' "$CCM_ACCOUNTS_FILE"; }

ccm_accounts() {
  jq -r '.accounts[] | "\(.label)\t\(.configDir)"' "$CCM_ACCOUNTS_FILE" \
  | while IFS=$'\t' read -r label dir; do
      printf '%s\t%s\n' "$label" "$(ccm_expand "$dir")"
    done
}
