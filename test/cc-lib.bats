setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  source "$ROOT/bin/cc-lib.sh"
}

@test "ccm_expand expande ~ a HOME" {
  run ccm_expand "~/x"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/x" ]
}

@test "ccm_threshold lee el umbral del archivo" {
  run ccm_threshold
  [ "$output" = "90" ]
}

@test "ccm_accounts imprime label y configDir expandido" {
  run ccm_accounts
  [ "${lines[0]}" = "uno	$HOME/.claude" ]
  [ "${lines[1]}" = "dos	/tmp/cc-dos" ]
}
