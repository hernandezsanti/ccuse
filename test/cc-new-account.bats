setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/bin/cc-new-account.sh"
  TMP="$BATS_TEST_TMPDIR/ccm"
  mkdir -p "$TMP"

  export CCM_BASE_DIR="$TMP/base"; mkdir -p "$CCM_BASE_DIR"
  export CCM_ACCOUNTS_FILE="$TMP/accounts.json"
  printf '{"accounts":[{"label":"personal","configDir":"~/.claude"}],"threshold":95}\n' \
    > "$CCM_ACCOUNTS_FILE"

  # fake security: there is a credential only if the marker file exists
  BIN="$TMP/bin"; mkdir -p "$BIN"
  cat > "$BIN/security" <<EOF
#!/usr/bin/env bash
[ -f "$TMP/has-cred" ]
EOF
  chmod +x "$BIN/security"
  export PATH="$BIN:$PATH"

  NEW="$TMP/.claude-new"
}

@test "creates the credential dir and registers the account" {
  run "$SCRIPT" new "$NEW"
  [ "$status" -eq 0 ]
  [ -d "$NEW" ]
  run jq -r '.accounts[] | select(.label=="new") | .configDir' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "$NEW" ]
  ls "$CCM_ACCOUNTS_FILE".bak.* >/dev/null
}

@test "creates no symlinks: an account is only a credential" {
  run "$SCRIPT" new "$NEW"
  [ "$status" -eq 0 ]
  [ "$(find "$NEW" -type l | wc -l | tr -d ' ')" = "0" ]
}

@test "without a credential it prints the login command with the right variable" {
  run "$SCRIPT" new "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=\"$NEW\" claude"* ]]
  [[ "$output" == *"do NOT use CLAUDE_CONFIG_DIR"* ]]
}

@test "with a credential it does not ask to log in" {
  touch "$TMP/has-cred"
  run "$SCRIPT" new "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"credentials already in Keychain"* ]]
  [[ "$output" != *"/login"* ]]
}

@test "is idempotent and does not duplicate the entry" {
  "$SCRIPT" new "$NEW" >/dev/null
  "$SCRIPT" new "$NEW" >/dev/null
  run jq '[.accounts[] | select(.label=="new")] | length' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "1" ]
}

@test "--check fails when something is missing and writes nothing" {
  run "$SCRIPT" --check new "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING"* ]]
  [ ! -e "$NEW" ]
  run jq '[.accounts[] | select(.label=="new")] | length' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "0" ]
}

@test "--check passes on a complete account" {
  touch "$TMP/has-cred"
  "$SCRIPT" new "$NEW" >/dev/null
  run "$SCRIPT" --check new "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "rejects an invalid label" {
  run "$SCRIPT" 'bad label!'
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid label"* ]]
}

@test "refuses to add the default account" {
  run "$SCRIPT" base "$CCM_BASE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"default account"* ]]
}
