# cc-lib.sh: shared helpers. No shebang: this file is sourced. Works in bash and zsh.
if [ -z "${CCM_ROOT:-}" ]; then
  if [ -n "${CCM_HOME:-}" ]; then
    CCM_ROOT="$CCM_HOME"
  elif [ -n "${BASH_SOURCE:-}" ]; then
    CCM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  else
    # zsh: $0 points to the sourced file
    CCM_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  fi
fi
CCM_ACCOUNTS_FILE="${CCM_ACCOUNTS_FILE:-$CCM_ROOT/accounts.json}"

ccm_die() { printf 'cc: %s\n' "$*" >&2; return 1; }

ccm_require_deps() {
  local c missing=()
  for c in jq curl security shasum; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [ "${#missing[@]}" -eq 0 ] || ccm_die "missing dependencies: ${missing[*]}"
}

ccm_expand() {
  case "$1" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

ccm_threshold() { jq -r '.threshold // 95' "$CCM_ACCOUNTS_FILE"; }

# ccm_base_dir: the single config dir. All accounts run on top of it.
ccm_base_dir() { printf '%s' "${CCM_BASE_DIR:-$HOME/.claude}"; }

# ccm_current_dir: the credential dir of the current session, used to know which
# account it is. With the current setup it comes from CLAUDE_SECURESTORAGE_CONFIG_DIR
# (empty means the default account). CLAUDE_CONFIG_DIR is a fallback for sessions
# that started with the old setup (one config dir per account) and are still alive.
ccm_current_dir() {
  printf '%s' "${CLAUDE_SECURESTORAGE_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
}

# ccm_slug <text>: turns text into a safe file name
ccm_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }

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
    || { ccm_die "no credentials in Keychain ($svc)"; return 1; }
  tok="$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)"
  [ -n "$tok" ] || { ccm_die "empty token ($svc)"; return 1; }
  printf '%s' "$tok"
}
