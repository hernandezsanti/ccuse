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

ccm_keychain_service() {
  local dir raw override h
  raw="$1"; dir="$(ccm_expand "$1")"
  override="$(jq -r --arg a "$raw" --arg b "$dir" \
    '.accounts[] | select(.configDir==$a or .configDir==$b) | .keychainService // empty' \
    "$CCM_ACCOUNTS_FILE" 2>/dev/null | head -1)"
  if [ -n "$override" ]; then printf '%s' "$override"; return 0; fi
  if [ "$dir" = "$HOME/.claude" ]; then printf 'Claude Code-credentials'; return 0; fi
  h="$(printf '%s' "$dir" | shasum -a 256 | cut -c1-8)"
  printf 'Claude Code-credentials-%s' "$h"
}

ccm_read_token() {
  local dir="$1" svc blob tok
  svc="$(ccm_keychain_service "$dir")"
  blob="$(security find-generic-password -s "$svc" -w 2>/dev/null)" \
    || { ccm_die "sin credenciales en Keychain ($svc)"; return 1; }
  tok="$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)"
  [ -n "$tok" ] || { ccm_die "token vacío ($svc)"; return 1; }
  printf '%s' "$tok"
}
