setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/bin/cc-fleet.sh"
  TMP="$BATS_TEST_TMPDIR/ccm"

  ONE="$TMP/.claude-one"; TWO="$TMP/.claude-two"
  mkdir -p "$ONE/daemon" "$TWO/daemon"
  echo '{"workers":{}}' > "$ONE/daemon/roster.json"
  echo '{"workers":{}}' > "$TWO/daemon/roster.json"

  export CCM_ACCOUNTS_FILE="$TMP/accounts.json"
  cat > "$CCM_ACCOUNTS_FILE" <<EOF
{"accounts":[{"label":"one","configDir":"$ONE"},{"label":"two","configDir":"$TWO"}],
 "threshold":95}
EOF
}

# job <configDir> <short> <state> <tempo> <name>
job() {
  mkdir -p "$1/jobs/$2"
  cat > "$1/jobs/$2/state.json" <<EOF
{"state":"$3","tempo":"$4","name":"$5","cwd":"/tmp/repo-$2",
 "daemonShort":"$2","detail":"detail of $5"}
EOF
}

# alive <configDir> <short> <pid>: adds the worker to the roster of that account
alive() {
  local f="$1/daemon/roster.json" t="$1/daemon/roster.t"
  jq --arg s "$2" --argjson p "$3" '.workers[$s] = {"pid":$p}' "$f" > "$t" && mv "$t" "$f"
}

@test "lists jobs from several accounts, labeled by account" {
  job "$ONE" aaaaaaaa working active "task of one"; alive "$ONE" aaaaaaaa $$
  job "$TWO" bbbbbbbb working active "task of two"; alive "$TWO" bbbbbbbb $$
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"one"*"task of one"* ]]
  [[ "$output" == *"two"*"task of two"* ]]
}

@test "marks as dead a job with no live worker in the roster" {
  job "$ONE" aaaaaaaa working active "running"; alive "$ONE" aaaaaaaa $$
  # the short id is not in the roster at all
  job "$TWO" bbbbbbbb working active "stuck"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stuck"* ]]
  echo "$output" | grep 'stuck'   | grep -q 'dead'
  echo "$output" | grep 'running' | grep -vq 'dead'
}

@test "a finished job without a process is hidden unless --all" {
  # the name cannot contain "finished": the hidden notice itself uses that word
  job "$ONE" aaaaaaaa done idle "already-over"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"already-over"* ]]
  [[ "$output" == *"hidden"* ]]
  run "$SCRIPT" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"already-over"* ]]
}

@test "a dead job that said it was working is NOT hidden" {
  job "$ONE" aaaaaaaa working active "stuck"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stuck"* ]]
  [[ "$output" == *"dead"* ]]
}

@test "merges state and tempo when they are equal" {
  job "$ONE" aaaaaaaa blocked blocked "waiting"; alive "$ONE" aaaaaaaa $$
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep 'waiting' | grep -q 'blocked'
  echo "$output" | grep 'waiting' | grep -vq 'blocked/blocked'
}

@test "sorts from newest to oldest" {
  job "$ONE" aaaaaaaa working active "older"; alive "$ONE" aaaaaaaa $$
  touch -t 202001010000 "$ONE/jobs/aaaaaaaa/state.json"
  job "$TWO" bbbbbbbb working active "newer"; alive "$TWO" bbbbbbbb $$
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -n 'newer' | cut -d: -f1)" -lt \
    "$(echo "$output" | grep -n 'older' | cut -d: -f1)" ]
}

@test "with no jobs it says so and exits cleanly" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no background sessions"* ]]
}

@test "writes nothing in the config dirs" {
  job "$ONE" aaaaaaaa working active "task"; alive "$ONE" aaaaaaaa $$
  before="$(find "$ONE" "$TWO" -type f | sort | xargs shasum | shasum)"
  "$SCRIPT" >/dev/null
  after="$(find "$ONE" "$TWO" -type f | sort | xargs shasum | shasum)"
  [ "$before" = "$after" ]
}
