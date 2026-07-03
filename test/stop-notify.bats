setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  export CCM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$CCM_STATE_DIR"
  # la cuenta activa: HOME/.claude -> label "uno" en el fixture
  unset CLAUDE_CONFIG_DIR
  NOW="$(date +%s)"
}

write_state() { # $1=fh $2=sd $3=ts
  printf '{"label":"uno","config_dir":"%s/.claude","five_hour":%s,"seven_day":%s,"ts":%s}' \
    "$HOME" "$1" "$2" "$3" > "$CCM_STATE_DIR/usage-uno.json"
}

@test "avisa cuando el uso supera el umbral (fixture=90)" {
  write_state 96 40 "$NOW"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("poco cupo")' >/dev/null
}

@test "no avisa cuando el uso está por debajo del umbral" {
  write_state 20 40 "$NOW"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]
}

@test "no avisa si no hay estado" {
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]
}

@test "no avisa si la lectura es vieja" {
  write_state 96 40 "$((NOW - 5000))"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]
}

@test "respeta el cooldown (segundo aviso silenciado)" {
  write_state 96 40 "$NOW"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  echo "$output" | jq -e '.systemMessage' >/dev/null   # primer aviso sale
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]                                       # segundo, silenciado
}
