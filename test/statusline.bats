setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  export CCM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # Inside a Claude session the credential is already set and would hide the fixture label.
  unset CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CONFIG_DIR
}

# Toy git repo in $BATS_TEST_TMPDIR/repo, on branch $1.
mkrepo() {
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q -b "$1" "$REPO"
  git -C "$REPO" -c user.email=a@b -c user.name=a commit -q --allow-empty -m i
}

# Runs the status line with current_dir=$1 and leaves the output, without colors, in $output.
sl_in() {
  local json
  json="$(jq -cn --arg d "$1" '{workspace:{current_dir:$d},cost:{total_cost_usd:4.5123}}')"
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh' | sed \$'s/\\x1b\\\\[[0-9;]*m//g'"
}

@test "shows model, effort and context" {
  json='{"model":{"display_name":"Opus 4.8"},"effort":{"level":"xhigh"},"context_window":{"used_percentage":19},"rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":31}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"Opus 4.8"* ]]
  [[ "$output" == *"xhigh"* ]]
  [[ "$output" == *"ctx 19%"* ]]
  [[ "$output" == *"5h 5%"* ]]
  [[ "$output" == *"7d 31%"* ]]
}

@test "shows the 5h and 7d reset time" {
  fhr=1783133400; sdr=1783324800
  json='{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$fhr"'},"seven_day":{"used_percentage":31,"resets_at":'"$sdr"'}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  exp5="$(date -r $fhr +'%H:%M')"
  exp7="$(date -r $sdr +'%d/%m %H:%M')"
  [[ "$output" == *"$exp5"* ]]
  [[ "$output" == *"$exp7"* ]]
}

@test "shows label and percentages" {
  json='{"config_dir":"'"$HOME"'/.claude","rate_limits":{"five_hour":{"used_percentage":40},"seven_day":{"used_percentage":10}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"one"* ]]
  [[ "$output" == *"5h 40%"* ]]
  [[ "$output" == *"7d 10%"* ]]
  [[ "$output" != *"⚠"* ]]
}

@test "warns at 95 (fixture threshold=90)" {
  json='{"config_dir":"'"$HOME"'/.claude","rate_limits":{"five_hour":{"used_percentage":95},"seven_day":{"used_percentage":10}}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"ccswitch"* ]]
}

@test "the account comes from the credential variable, not from config_dir" {
  # config_dir is the default (label one) but the credential belongs to two
  json='{"config_dir":"'"$HOME"'/.claude","rate_limits":{"five_hour":{"used_percentage":40}}}'
  run bash -c "CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two printf '%s' '$json' | CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"two"* ]]
  [[ "$output" != *"one"* ]]
}

@test "an empty credential variable means the default account" {
  json='{"config_dir":"'"$HOME"'/.claude"}'
  run bash -c "printf '%s' '$json' | CLAUDE_SECURESTORAGE_CONFIG_DIR= '$ROOT/bin/statusline.sh'"
  [[ "$output" == *"one"* ]]
}

@test "does not fail when rate_limits is missing" {
  json='{"config_dir":"'"$HOME"'/.claude"}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"one"* ]]
}

@test "shows the session cost with two decimals" {
  json='{"cost":{"total_cost_usd":4.5123}}'
  run bash -c "printf '%s' '$json' | '$ROOT/bin/statusline.sh'"
  [[ "$output" == *'$4.51'* ]]
}

@test "does not show a cost when the JSON has none" {
  run bash -c "printf '%s' '{}' | '$ROOT/bin/statusline.sh'"
  [[ "$output" != *'$'* ]]
}

@test "on main it shows PRODUCTION, on the same line" {
  mkrepo main
  sl_in "$REPO"
  [[ "$output" == *"PRODUCTION main"* ]]
  [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" -eq 0 ]
}

@test "on a feature branch it counts uncommitted files" {
  mkrepo main
  git -C "$REPO" checkout -q -b feature/login
  echo x > "$REPO/a.txt"
  sl_in "$REPO"
  [[ "$output" == *"feature/login"* ]]
  [[ "$output" == *"1 uncommitted"* ]]
  [[ "$output" != *"PRODUCTION"* ]]
}

@test "from a subdirectory of a normal repo it does not say worktree" {
  mkrepo main
  mkdir -p "$REPO/sub/dir"
  sl_in "$REPO/sub/dir"
  [[ "$output" == *"main"* ]]
  [[ "$output" != *"worktree"* ]]
}

@test "in a linked worktree it says worktree" {
  mkrepo main
  git -C "$REPO" worktree add -q "$BATS_TEST_TMPDIR/wt" -b feature/worktree-test
  sl_in "$BATS_TEST_TMPDIR/wt"
  [[ "$output" == *"feature/worktree-test"* ]]
  [[ "$output" == *"worktree"* ]]
}

@test "outside a repo there is no git segment" {
  mkdir -p "$BATS_TEST_TMPDIR/nada"
  sl_in "$BATS_TEST_TMPDIR/nada"
  [[ "$output" != *"uncommitted"* ]]
  [[ "$output" != *"PRODUCTION"* ]]
}

@test "shows the PR from the cache, without calling gh" {
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
