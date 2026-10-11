setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  source "$ROOT/bin/cc-lib.sh"
}

@test "ccm_expand expands ~ to HOME" {
  run ccm_expand "~/x"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/x" ]
}

@test "ccm_threshold reads the threshold from the file" {
  run ccm_threshold
  [ "$output" = "90" ]
}

@test "ccm_accounts prints the label and the expanded configDir" {
  run ccm_accounts
  [ "${lines[0]}" = "one	$HOME/.claude" ]
  [ "${lines[1]}" = "two	/tmp/cc-two" ]
}
