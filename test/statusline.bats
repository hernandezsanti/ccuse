setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  export CCM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # Dentro de una sesion de Claude la credencial ya viene fijada y taparia el label del fixture.
  unset CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CONFIG_DIR
}

# Repo git de juguete en $BATS_TEST_TMPDIR/repo, parado en la rama $1.
mkrepo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q -b "$1" "$REPO"
  git -C "$REPO" -c user.email=a@b -c user.name=a commit -q --allow-empty -m i
}

# Corre el statusline con current_dir=$1 y deja la salida, sin colores, en $output.
sl_in() {
  local json
  json="$(jq -cn --arg d "$1" '{workspace:{current_dir:$d},cost:{total_cost_usd:4.5123}}')"
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh' | sed \$'s/\\x1b\\\\[[0-9;]*m//g'"
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

@test "la cuenta sale de la variable de credencial, no del config_dir" {
  # config_dir es el default (label uno) pero la credencial es la de dos
  json='{"config_dir":"'"$HOME"'/.claude","rate_limits":{"five_hour":{"used_percentage":40}}}'
  run bash -c "CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-dos printf '%s' '$json' | CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-dos '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"dos"* ]]
  [[ "$output" != *"uno"* ]]
}

@test "la variable de credencial vacia significa cuenta default" {
  json='{"config_dir":"'"$HOME"'/.claude"}'
  run bash -c "printf '%s' '$json' | CLAUDE_SECURESTORAGE_CONFIG_DIR= '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"uno"* ]]
}

@test "no rompe si falta rate_limits" {
  json='{"config_dir":"'"$HOME"'/.claude"}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uno"* ]]
}

@test "muestra el costo de la sesion con dos decimales" {
  json='{"cost":{"total_cost_usd":4.5123}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *'$4.51'* ]]
}

@test "sin costo en el JSON no inventa uno" {
  run bash -c "printf '%s' '{}' | '$ROOT/bin/statusline.sh'"
  [[ "$output" != *'$'* ]]
}

@test "en main avisa PRODUCCION, en la misma fila" {
  mkrepo main
  sl_in "$REPO"
  [[ "$output" == *"PRODUCCIÓN main"* ]]
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
}

@test "en una rama de feature cuenta los archivos sin commitear" {
  mkrepo main
  git -C "$REPO" checkout -q -b feature/login
  echo x > "$REPO/a.txt"
  sl_in "$REPO"
  [[ "$output" == *"feature/login"* ]]
  [[ "$output" == *"1 sin commitear"* ]]
  [[ "$output" != *"PRODUCCIÓN"* ]]
}

@test "desde un subdirectorio de un repo normal no dice worktree" {
  mkrepo main
  mkdir -p "$REPO/sub/dir"
  sl_in "$REPO/sub/dir"
  [[ "$output" == *"main"* ]]
  [[ "$output" != *"worktree"* ]]
}

@test "en un worktree enlazado lo dice" {
  mkrepo main
  git -C "$REPO" worktree add -q "$BATS_TEST_TMPDIR/wt" -b feature/worktree-test
  sl_in "$BATS_TEST_TMPDIR/wt"
  [[ "$output" == *"feature/worktree-test"* ]]
  [[ "$output" == *"worktree"* ]]
}

@test "fuera de un repo no agrega segmento git" {
  mkdir -p "$BATS_TEST_TMPDIR/nada"
  sl_in "$BATS_TEST_TMPDIR/nada"
  [[ "$output" != *"sin commitear"* ]]
  [[ "$output" != *"PRODUCCIÓN"* ]]
}

@test "muestra el PR desde la cache, sin llamar a gh" {
  mkrepo main
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git -C "$REPO" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git -C "$REPO" checkout -q -b feature/login
  git -C "$REPO" push -q -u origin feature/login 2>/dev/null
  top="$(git -C "$REPO" rev-parse --show-toplevel)"
  key="$(printf '%s:%s' "$top" feature/login | cksum | awk '{print $1}')"
  mkdir -p "$CCM_STATE_DIR"
  echo '{"number":34,"url":"https://github.com/o/r/pull/34","state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' > "$CCM_STATE_DIR/pr-$key.json"
  sl_in "$REPO"
  [[ "$output" == *"PR #34"* ]]
  [[ "$output" == *"CI ok"* ]]
}
