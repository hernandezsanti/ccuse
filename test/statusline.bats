setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
}

@test "muestra label y porcentajes" {
  json='{"config_dir":"'"$HOME"'/.claude","rate_limits":{"five_hour":{"used_percentage":40},"seven_day":{"used_percentage":10}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"uno"* ]]
  [[ "$output" == *"5h 40%"* ]]
  [[ "$output" == *"7d 10%"* ]]
  [[ "$output" != *"⚠"* ]]
}

@test "alerta al cruzar 95 (umbral fixture=90)" {
  json='{"config_dir":"'"$HOME"'/.claude","rate_limits":{"five_hour":{"used_percentage":95},"seven_day":{"used_percentage":10}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"ccswitch"* ]]
}

@test "no rompe si falta rate_limits" {
  json='{"config_dir":"'"$HOME"'/.claude"}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uno"* ]]
}
