bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  FAKE="$BATS_TEST_TMPDIR/usage.sh"
  cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
# $1 = configDir. HOME/.claude -> 96%; /tmp/cc-dos -> 20%
case "$1" in
  *"/.claude") echo '{"five_hour":96,"seven_day":30,"five_hour_resets_at":"2026-07-03T20:00:00Z"}' ;;
  *"cc-dos")   echo '{"five_hour":20,"seven_day":10,"five_hour_resets_at":"2026-07-03T19:00:00Z"}' ;;
esac
EOF
  chmod +x "$FAKE"
  export CCM_USAGE_CMD="$FAKE"
}

@test "elige la cuenta con menor uso bajo umbral" {
  run "$ROOT/bin/cc-pick.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/cc-dos" ]
}

@test "excluye el configDir pasado como argumento" {
  # queda solo HOME/.claude (96% >= 90) -> fallback por reset; el warning va a stderr
  run --separate-stderr "$ROOT/bin/cc-pick.sh" "/tmp/cc-dos"
  [ "$output" = "$HOME/.claude" ]
  [[ "$stderr" == *"reset más cercano"* ]]
}
