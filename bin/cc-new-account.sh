#!/usr/bin/env bash
# cc-new-account.sh: adds an account, which means its credential dir and its entry
# in accounts.json. Idempotent: running it on an existing account breaks nothing.
#
# An account is only a credential. All accounts run on the same config dir
# (~/.claude). What makes them different is CLAUDE_SECURESTORAGE_CONFIG_DIR: Claude
# Code derives the Keychain entry from the exact string of that variable. The dir
# holds almost nothing (the token refresh lock, and .credentials.json on Linux):
# it exists so the path is stable and the credential has a place to live.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: cc-new-account.sh [--check] <label> [credDir]

  <label>      account name (for example: work)
  [credDir]    defaults to ~/.claude-<label>

  --check      only checks, does not write anything (exit 1 if something is missing)
EOF
  return 1
}

CHECK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)   CHECK=1; shift ;;
    -h|--help) usage ;;
    -*)        ccm_die "unknown option: $1"; usage ;;
    *)         break ;;
  esac
done

LABEL="${1:-}"; [ -n "$LABEL" ] || usage
case "$LABEL" in
  *[!A-Za-z0-9_-]*) ccm_die "invalid label: '$LABEL' (only A-Za-z0-9_-)"; exit 1 ;;
esac

RAW_DIR="${2:-~/.claude-$LABEL}"
DIR="$(ccm_expand "$RAW_DIR")"
BASE="$(ccm_base_dir)"
TS="$(date +%Y%m%d-%H%M%S)"

[ "$DIR" != "$BASE" ] || { ccm_die "$BASE is the default account; there is no need to add it"; exit 1; }

say() { printf '%s\n' "$*"; }
missing=0

# --- 1. credential dir ---------------------------------------------------------
if [ -d "$DIR" ]; then
  say "dir   $DIR (already exists)"
elif [ -n "$CHECK" ]; then
  missing=1; say "MISSING dir   $DIR"
else
  mkdir -p "$DIR"; say "dir   $DIR (created)"
fi

# --- 2. entry in accounts.json -------------------------------------------------
if jq -e --arg l "$LABEL" 'any(.accounts[]; .label == $l)' "$CCM_ACCOUNTS_FILE" >/dev/null; then
  say "json  '$LABEL' is already in $(basename "$CCM_ACCOUNTS_FILE")"
elif [ -n "$CHECK" ]; then
  missing=1; say "MISSING json  '$LABEL' is not in $(basename "$CCM_ACCOUNTS_FILE")"
else
  tmp="$CCM_ACCOUNTS_FILE.tmp.$$"
  jq --arg l "$LABEL" --arg d "$RAW_DIR" \
    '.accounts += [{label: $l, configDir: $d}]' "$CCM_ACCOUNTS_FILE" > "$tmp"
  cp "$CCM_ACCOUNTS_FILE" "$CCM_ACCOUNTS_FILE.bak.$TS"
  mv "$tmp" "$CCM_ACCOUNTS_FILE"
  say "json  '$LABEL' added (backup: accounts.json.bak.$TS)"
fi

# --- 3. credential --------------------------------------------------------------
svc="$(ccm_keychain_service "$DIR")"
if security find-generic-password -s "$svc" >/dev/null 2>&1; then
  say "login credentials already in Keychain ($svc)"
else
  missing=1
  if [ -n "$CHECK" ]; then
    say "MISSING login  no credentials in Keychain ($svc)"
  else
    say ""
    say "The account is not logged in yet. In a real terminal (not inside Claude Code), run:"
    say ""
    say "  CLAUDE_SECURESTORAGE_CONFIG_DIR=\"$DIR\" claude    # then /login and /exit"
    say ""
    say "Warning: do NOT use CLAUDE_CONFIG_DIR for this. Logging in with the wrong"
    say "variable overwrites the credential of another account without any warning."
    say ""
    say "Then: ccuse $LABEL   (or the alias claude-$LABEL, after you reopen the terminal)"
  fi
fi

if [ -n "$CHECK" ]; then
  [ "$missing" -eq 0 ] && { say ""; say "account '$LABEL' OK"; exit 0; }
  say ""; ccm_die "account '$LABEL' is incomplete; run: cc-new-account.sh $LABEL $RAW_DIR"
  exit 1
fi
