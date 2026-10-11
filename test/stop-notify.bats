setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  export CCM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$CCM_STATE_DIR"
  # the active account: HOME/.claude -> label "one" in the fixture
  unset CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR
  NOW="$(date +%s)"
}

@test "the active account comes from the credential variable" {
  # the state over the threshold belongs to "one"; the session runs as "two": no warning
  write_state 96 40 "$NOW"
  run bash -c "echo '{}' | CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]
}

write_state() { # $1=fh $2=sd $3=ts
  printf '{"label":"one","config_dir":"%s/.claude","five_hour":%s,"seven_day":%s,"ts":%s}' \
    "$HOME" "$1" "$2" "$3" > "$CCM_STATE_DIR/usage-one.json"
}

@test "warns when usage is over the threshold (fixture=90)" {
  write_state 96 40 "$NOW"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("low on quota")' >/dev/null
}

@test "does not warn when usage is below the threshold" {
  write_state 20 40 "$NOW"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]
}

@test "does not warn when there is no state" {
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]
}

@test "does not warn when the reading is old" {
  write_state 96 40 "$((NOW - 5000))"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]
}

@test "respects the cooldown (second warning is silent)" {
  write_state 96 40 "$NOW"
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  echo "$output" | jq -e '.systemMessage' >/dev/null   # first warning is shown
  run bash -c "echo '{}' | '$ROOT/bin/stop-notify.sh'"
  [ -z "$output" ]                                       # second one is silent
}
