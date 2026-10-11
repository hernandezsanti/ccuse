setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_HOME="$ROOT"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  # fake cc-pick: always picks /tmp/cc-two
  PICK="$BATS_TEST_TMPDIR/cc-pick.sh"
  printf '#!/usr/bin/env bash\necho /tmp/cc-two\n' > "$PICK"; chmod +x "$PICK"
  export CCM_PICK_CMD="$PICK"
  export CCM_DRY_RUN=1
  unset CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR
  source "$ROOT/shell/claude-multi.sh"
}

@test "cc-label returns the configured label" {
  run "$ROOT/bin/cc-label.sh" "/tmp/cc-two"
  [ "$output" = "two" ]
}

@test "ccx picks an account: no CLAUDE_CONFIG_DIR and the credential of that account" {
  run ccx --version
  [[ "$output" == *"CLAUDE_CONFIG_DIR=<unset>"* ]]
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "ccx for the default account selects the default credential" {
  printf '#!/usr/bin/env bash\necho %s/.claude\n' "$HOME" > "$CCM_PICK_CMD"
  run ccx
  [[ "$output" == *"CLAUDE_CONFIG_DIR=<unset>"* ]]
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=<default>"* ]]
}

@test "ccuse starts the account by its label (dry-run)" {
  run ccuse two --version
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "ccuse fails with a label that does not exist" {
  run ccuse missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"account 'missing' does not exist"* ]]
}

@test "ccswitch without arguments continues the previous conversation" {
  run ccswitch
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two"* ]]
  [[ "$output" == *"claude --continue"* ]]
}

@test "ccswitch skips the current account, read from the credential variable" {
  # fake pick that prints what it received as the account to skip
  printf '#!/usr/bin/env bash\necho "EXCL=$1" >&2; echo /tmp/cc-two\n' > "$CCM_PICK_CMD"
  export CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-one
  run ccswitch
  [[ "$output" == *"EXCL=/tmp/cc-one"* ]]
}

@test "ccswitch with its own arguments does not add --continue" {
  run ccswitch --version
  [[ "$output" == *"claude --version"* ]]
  [[ "$output" != *"--continue"* ]]
}

@test "CCM_NO_CONTINUE=1 makes ccswitch open a new session" {
  export CCM_NO_CONTINUE=1
  run ccswitch
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two"* ]]
  [[ "$output" != *"--continue"* ]]
}

@test "CCM_TMUX=1 runs claude inside tmux, with -n as the session name" {
  export CCM_TMUX=1
  unset TMUX
  run ccuse two -n my.session "hello"
  [[ "$output" == *"tmux new-session -A -s my-session env -u CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-two claude -n my.session hello"* ]]
}

@test "inside tmux it does not nest another session" {
  export CCM_TMUX=1 TMUX=/tmp/tmux-fake,1,0
  run ccuse two --version
  [[ "$output" != *"tmux new-session"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "without CCM_TMUX tmux is not used" {
  unset TMUX CCM_TMUX
  run ccuse two --version
  [[ "$output" != *"tmux"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "t ccuse turns tmux on" {
  unset TMUX CCM_TMUX
  run t ccuse two -n my.session
  [[ "$output" == *"tmux new-session -A -s my-session"* ]]
}

@test "CCM_TMUX=0 and -p mode do not use tmux" {
  unset TMUX
  CCM_TMUX=0 run ccuse two --version
  [[ "$output" != *"tmux"* ]]
  CCM_TMUX=1 run ccuse two -p "hello"
  [[ "$output" != *"tmux"* ]]
}

@test "without -n the session name comes from the folder" {
  export CCM_TMUX=1
  unset TMUX
  cd "$BATS_TEST_TMPDIR"
  run ccuse two
  [[ "$output" == *"tmux new-session -A -s cc-${PWD##*/}-"* ]]
}
