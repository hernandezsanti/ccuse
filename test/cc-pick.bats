bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  FAKE="$BATS_TEST_TMPDIR/usage.sh"
  cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
# $1 = configDir. HOME/.claude -> 96%; /tmp/cc-two -> 20%
case "$1" in
  *"/.claude") echo '{"five_hour":96,"seven_day":30,"five_hour_resets_at":"2026-07-03T20:00:00Z"}' ;;
  *"cc-two")   echo '{"five_hour":20,"seven_day":10,"five_hour_resets_at":"2026-07-03T19:00:00Z"}' ;;
esac
EOF
  chmod +x "$FAKE"
  export CCM_USAGE_CMD="$FAKE"
}

@test "picks the account with the lowest usage below the threshold" {
  run "$ROOT/bin/cc-pick.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/cc-two" ]
}

@test "skips the configDir passed as an argument" {
  # only HOME/.claude is left (96% >= 90) -> fallback by reset; the warning goes to stderr
  run --separate-stderr "$ROOT/bin/cc-pick.sh" "/tmp/cc-two"
  [ "$output" = "$HOME/.claude" ]
  [[ "$stderr" == *"nearest reset"* ]]
}
