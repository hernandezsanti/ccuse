setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/bin/cc-new-account.sh"
  TMP="$BATS_TEST_TMPDIR/ccm"
  mkdir -p "$TMP"

  export CCM_BASE_DIR="$TMP/base"; mkdir -p "$CCM_BASE_DIR"
  export CCM_ACCOUNTS_FILE="$TMP/accounts.json"
  printf '{"accounts":[{"label":"personal","configDir":"~/.claude"}],"threshold":95}\n' \
    > "$CCM_ACCOUNTS_FILE"

  # fake security: hay credencial solo si existe el archivo marcador
  BIN="$TMP/bin"; mkdir -p "$BIN"
  cat > "$BIN/security" <<EOF
#!/usr/bin/env bash
[ -f "$TMP/has-cred" ]
EOF
  chmod +x "$BIN/security"
  export PATH="$BIN:$PATH"

  NEW="$TMP/.claude-nueva"
}

@test "crea el dir de credencial y registra la cuenta" {
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  [ -d "$NEW" ]
  run jq -r '.accounts[] | select(.label=="nueva") | .configDir' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "$NEW" ]
  ls "$CCM_ACCOUNTS_FILE".bak.* >/dev/null
}

@test "no crea ningun symlink: la cuenta es solo la credencial" {
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  [ "$(find "$NEW" -type l | wc -l | tr -d ' ')" = "0" ]
}

@test "sin credencial imprime el comando de login con la variable correcta" {
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=\"$NEW\" claude"* ]]
  [[ "$output" == *"NO uses CLAUDE_CONFIG_DIR"* ]]
}

@test "con credencial no pide login" {
  touch "$TMP/has-cred"
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ya hay credenciales"* ]]
  [[ "$output" != *"/login"* ]]
}

@test "es idempotente y no duplica el registro" {
  "$SCRIPT" nueva "$NEW" >/dev/null
  "$SCRIPT" nueva "$NEW" >/dev/null
  run jq '[.accounts[] | select(.label=="nueva")] | length' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "1" ]
}

@test "--check falla si falta algo y no escribe" {
  run "$SCRIPT" --check nueva "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALTA"* ]]
  [ ! -e "$NEW" ]
  run jq '[.accounts[] | select(.label=="nueva")] | length' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "0" ]
}

@test "--check pasa en una cuenta completa" {
  touch "$TMP/has-cred"
  "$SCRIPT" nueva "$NEW" >/dev/null
  run "$SCRIPT" --check nueva "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "rechaza un label inválido" {
  run "$SCRIPT" 'mal label!'
  [ "$status" -ne 0 ]
  [[ "$output" == *"label inválido"* ]]
}

@test "rechaza dar de alta la cuenta default" {
  run "$SCRIPT" base "$CCM_BASE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cuenta default"* ]]
}
