setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  source "$ROOT/bin/cc-lib.sh"
}

@test "servicio Keychain default para HOME/.claude" {
  run ccm_keychain_service "$HOME/.claude"
  [ "$output" = "Claude Code-credentials" ]
}

@test "servicio Keychain hasheado para config dir no-default" {
  expected="Claude Code-credentials-$(printf '%s' "/tmp/cc-dos" | shasum -a 256 | cut -c1-8)"
  run ccm_keychain_service "/tmp/cc-dos"
  [ "$output" = "$expected" ]
}
