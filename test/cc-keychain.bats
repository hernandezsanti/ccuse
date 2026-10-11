setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  source "$ROOT/bin/cc-lib.sh"
}

@test "default Keychain service for HOME/.claude" {
  run ccm_keychain_service "$HOME/.claude"
  [ "$output" = "Claude Code-credentials" ]
}

@test "hashed Keychain service for a non-default config dir" {
  expected="Claude Code-credentials-$(printf '%s' "/tmp/cc-two" | shasum -a 256 | cut -c1-8)"
  run ccm_keychain_service "/tmp/cc-two"
  [ "$output" = "$expected" ]
}
