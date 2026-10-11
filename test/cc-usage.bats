setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  # fake security: returns a blob with accessToken
  cat > "$BIN/security" <<'EOF'
#!/usr/bin/env bash
echo '{"claudeAiOauth":{"accessToken":"tok-fake"}}'
EOF
  # fake curl: response of /api/oauth/usage (utilization on a 0-100 scale)
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"five_hour":{"utilization":50,"resets_at":"2026-07-03T20:00:00Z"},"seven_day":{"utilization":10,"resets_at":"2026-07-10T00:00:00Z"}}'
EOF
  chmod +x "$BIN/security" "$BIN/curl"
  export PATH="$BIN:$PATH"
}

@test "cc-usage returns utilization as a 0-100 percentage" {
  run "$ROOT/bin/cc-usage.sh" "/tmp/cc-two"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.five_hour == 50' >/dev/null
  echo "$output" | jq -e '.seven_day == 10' >/dev/null
  echo "$output" | jq -e '.five_hour_resets_at == "2026-07-03T20:00:00Z"' >/dev/null
}

@test "cc-usage does not print the token" {
  run "$ROOT/bin/cc-usage.sh" "/tmp/cc-two"
  [[ "$output" != *"tok-fake"* ]]
}
