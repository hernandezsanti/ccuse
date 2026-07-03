setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  export CCM_STATE_DIR="$BATS_TEST_TMPDIR/state"
}

@test "muestra modelo, effort y contexto" {
  json='{"model":{"display_name":"Opus 4.8"},"effort":{"level":"xhigh"},"context_window":{"used_percentage":19},"rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":31}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"Opus 4.8"* ]]
  [[ "$output" == *"xhigh"* ]]
  [[ "$output" == *"ctx 19%"* ]]
  [[ "$output" == *"5h 5%"* ]]
  [[ "$output" == *"7d 31%"* ]]
}

@test "muestra la hora de reset de 5h y 7d" {
  fhr=1783133400; sdr=1783324800
  json='{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$fhr"'},"seven_day":{"used_percentage":31,"resets_at":'"$sdr"'}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  exp5="$(date -r $fhr +'%H:%M')"
  exp7="$(date -r $sdr +'%d/%m %H:%M')"
  [[ "$output" == *"$exp5"* ]]
  [[ "$output" == *"$exp7"* ]]
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
