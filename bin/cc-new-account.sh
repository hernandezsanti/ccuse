#!/usr/bin/env bash
# cc-new-account.sh — da de alta una cuenta: su dir de credencial y el registro en
# accounts.json. Idempotente: correrlo sobre una cuenta existente no rompe nada.
#
# Una cuenta es solo una credencial. Todas corren sobre el mismo config dir
# (~/.claude); lo que las distingue es CLAUDE_SECURESTORAGE_CONFIG_DIR, de cuyo
# string exacto Claude Code deriva la entrada de Keychain. El dir casi no tiene
# contenido propio (el lock del refresh de token, y .credentials.json en Linux):
# existe para que el path sea estable y la credencial tenga dónde vivir.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

usage() {
  cat >&2 <<'EOF'
uso: cc-new-account.sh [--check] <label> [credDir]

  <label>      nombre de la cuenta (p. ej. cliente)
  [credDir]    por defecto ~/.claude-<label>

  --check      solo diagnostica, no escribe nada (exit 1 si falta algo)
EOF
  return 1
}

CHECK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)   CHECK=1; shift ;;
    -h|--help) usage ;;
    -*)        ccm_die "opción desconocida: $1"; usage ;;
    *)         break ;;
  esac
done

LABEL="${1:-}"; [ -n "$LABEL" ] || usage
case "$LABEL" in
  *[!A-Za-z0-9_-]*) ccm_die "label inválido: '$LABEL' (solo A-Za-z0-9_-)"; exit 1 ;;
esac

RAW_DIR="${2:-~/.claude-$LABEL}"
DIR="$(ccm_expand "$RAW_DIR")"
BASE="$(ccm_base_dir)"
TS="$(date +%Y%m%d-%H%M%S)"

[ "$DIR" != "$BASE" ] || { ccm_die "$BASE es la cuenta default; no hace falta darla de alta"; exit 1; }

say() { printf '%s\n' "$*"; }
missing=0

# --- 1. dir de credencial ------------------------------------------------------
if [ -d "$DIR" ]; then
  say "dir   $DIR (ya existe)"
elif [ -n "$CHECK" ]; then
  missing=1; say "FALTA dir   $DIR"
else
  mkdir -p "$DIR"; say "dir   $DIR (creado)"
fi

# --- 2. registro en accounts.json ---------------------------------------------
if jq -e --arg l "$LABEL" 'any(.accounts[]; .label == $l)' "$CCM_ACCOUNTS_FILE" >/dev/null; then
  say "json  '$LABEL' ya está en $(basename "$CCM_ACCOUNTS_FILE")"
elif [ -n "$CHECK" ]; then
  missing=1; say "FALTA json  '$LABEL' no está en $(basename "$CCM_ACCOUNTS_FILE")"
else
  tmp="$CCM_ACCOUNTS_FILE.tmp.$$"
  jq --arg l "$LABEL" --arg d "$RAW_DIR" \
    '.accounts += [{label: $l, configDir: $d}]' "$CCM_ACCOUNTS_FILE" > "$tmp"
  cp "$CCM_ACCOUNTS_FILE" "$CCM_ACCOUNTS_FILE.bak.$TS"
  mv "$tmp" "$CCM_ACCOUNTS_FILE"
  say "json  '$LABEL' agregado (backup: accounts.json.bak.$TS)"
fi

# --- 3. credencial ---------------------------------------------------------------
svc="$(ccm_keychain_service "$DIR")"
if security find-generic-password -s "$svc" >/dev/null 2>&1; then
  say "login ya hay credenciales en Keychain ($svc)"
else
  missing=1
  if [ -n "$CHECK" ]; then
    say "FALTA login  sin credenciales en Keychain ($svc)"
  else
    say ""
    say "Falta loguear la cuenta. En una terminal real (no dentro de Claude Code):"
    say ""
    say "  CLAUDE_SECURESTORAGE_CONFIG_DIR=\"$DIR\" claude    # adentro: /login, luego /exit"
    say ""
    say "Ojo: NO uses CLAUDE_CONFIG_DIR para esto. Loguear con la variable equivocada"
    say "pisa la credencial de otra cuenta sin avisar."
    say ""
    say "Después: ccuse $LABEL   (o el alias claude-$LABEL, tras reabrir la terminal)"
  fi
fi

if [ -n "$CHECK" ]; then
  [ "$missing" -eq 0 ] && { say ""; say "cuenta '$LABEL' OK"; exit 0; }
  say ""; ccm_die "cuenta '$LABEL' incompleta — corré: cc-new-account.sh $LABEL $RAW_DIR"
  exit 1
fi
