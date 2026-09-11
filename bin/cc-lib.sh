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

# ccm_base_dir — cuenta base de la que cuelgan los symlinks compartidos.
ccm_base_dir() { printf '%s' "${CCM_BASE_DIR:-$HOME/.claude}"; }

# ccm_shared_items — qué se comparte entre cuentas, uno por línea.
#
# sessions/ se comparte para que ListAgents y SendMessage vean las sesiones de
# todas las cuentas: el registro de peers es <configDir>/sessions, así que sin
# el link cada cuenta solo se ve a sí misma. No filtra credenciales — cada
# <pid>.json trae pid, cwd, nombre y estado, y cada <pid>.<hash>.key un token
# ligado a un socket concreto de /tmp/cc-socks. El transporte ya cruzaba
# cuentas (feature de peer "reply_across_default_dirs"); faltaba el descubrimiento.
#
# tasks/, file-history/ e image-cache/ van keyeados por sesión, igual que los
# transcripts de projects/ — que ya se comparte. Como ccswitch le inyecta
# --continue a claude, una sesión cruza de cuenta por diseño; sin estos links
# cruza sin su lista de tareas, su historial de undo ni sus imágenes pegadas, y
# queda con medio estado de cada lado (la misma clave en dos config dirs a la vez).
# paste-cache/ es lo mismo para el texto pegado, pero keyeado por hash de
# contenido, así que el merge entre cuentas no puede colisionar.
#
# Lo que NO está acá es deliberadamente propio de cada cuenta:
#   .claude.json (login/OAuth), history.jsonl (prompts del up-arrow),
#   shell-snapshots/, session-env/, cache/, backups/, telemetry/, y sobre todo
#   daemon/ y jobs/ — cada config dir corre su propio supervisor con su
#   control.key y su roster.json, y dos supervisores sobre un mismo roster se
#   pisan los workers. Por eso FleetView sigue separado por cuenta.
ccm_shared_items() {
  cat <<'EOF'
.env
agents
commands
file-history
hooks
image-cache
paste-cache
plugins
projects
rules
sessions
settings.json
settings.local.json
skills
tasks
EOF
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
