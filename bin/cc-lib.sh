# cc-lib.sh — helpers compartidos. Sin shebang: se sourcea. Compatible bash/zsh.
if [ -z "${CCM_ROOT:-}" ]; then
  if [ -n "${CCM_HOME:-}" ]; then
    CCM_ROOT="$CCM_HOME"
  elif [ -n "${BASH_SOURCE:-}" ]; then
    CCM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  else
    # zsh: $0 apunta al archivo sourceado
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

# ccm_base_dir — el único config dir. Todas las cuentas corren sobre él.
ccm_base_dir() { printf '%s' "${CCM_BASE_DIR:-$HOME/.claude}"; }

# ccm_current_dir — el dir de credencial de la sesión actual, para saber qué
# cuenta es. Con el modelo nuevo viene en CLAUDE_SECURESTORAGE_CONFIG_DIR
# (vacío = cuenta default); CLAUDE_CONFIG_DIR queda como fallback para las
# sesiones que arrancaron con el modelo viejo y siguen vivas.
ccm_current_dir() {
  printf '%s' "${CLAUDE_SECURESTORAGE_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
}

# ccm_slug <texto> — normaliza a un nombre de archivo seguro
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
    || { ccm_die "sin credenciales en Keychain ($svc)"; return 1; }
  tok="$(printf '%s' "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)"
  [ -n "$tok" ] || { ccm_die "token vacío ($svc)"; return 1; }
  printf '%s' "$tok"
}
