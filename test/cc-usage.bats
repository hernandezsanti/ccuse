setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  # fake security: devuelve un blob con accessToken
  cat > "$BIN/security" <<'EOF'
#!/usr/bin/env bash
echo '{"claudeAiOauth":{"accessToken":"tok-fake"}}'
EOF
  # fake curl: respuesta de /api/oauth/usage (utilization en escala 0-100)
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"five_hour":{"utilization":50,"resets_at":"2026-07-03T20:00:00Z"},"seven_day":{"utilization":10,"resets_at":"2026-07-10T00:00:00Z"}}'
EOF
  chmod +x "$BIN/security" "$BIN/curl"
  export PATH="$BIN:$PATH"
}

@test "cc-usage devuelve utilization como porcentaje 0-100" {
  run "$ROOT/bin/cc-usage.sh" "/tmp/cc-dos"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.five_hour == 50' >/dev/null
  echo "$output" | jq -e '.seven_day == 10' >/dev/null
  echo "$output" | jq -e '.five_hour_resets_at == "2026-07-03T20:00:00Z"' >/dev/null
}

@test "cc-usage no imprime el token" {
  run "$ROOT/bin/cc-usage.sh" "/tmp/cc-dos"
  [[ "$output" != *"tok-fake"* ]]
}
