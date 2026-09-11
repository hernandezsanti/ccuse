setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_HOME="$ROOT"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  # cc-pick fake: siempre elige /tmp/cc-dos
  PICK="$BATS_TEST_TMPDIR/cc-pick.sh"
  printf '#!/usr/bin/env bash\necho /tmp/cc-dos\n' > "$PICK"; chmod +x "$PICK"
  export CCM_PICK_CMD="$PICK"
  export CCM_DRY_RUN=1
  source "$ROOT/shell/claude-multi.sh"
}

@test "cc-label devuelve el label configurado" {
  run "$ROOT/bin/cc-label.sh" "/tmp/cc-dos"
  [ "$output" = "dos" ]
}

@test "ccx elige cuenta y exporta CLAUDE_CONFIG_DIR (dry-run)" {
  run ccx --version
  [[ "$output" == *"CLAUDE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "ccx para la cuenta default NO exporta CLAUDE_CONFIG_DIR" {
  printf '#!/usr/bin/env bash\necho %s/.claude\n' "$HOME" > "$CCM_PICK_CMD"
  run ccx
  [[ "$output" == *"CLAUDE_CONFIG_DIR=<unset>"* ]]
}

@test "ccuse lanza la cuenta por su label (dry-run)" {
  run ccuse dos --version
  [[ "$output" == *"CLAUDE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "ccuse falla con un label inexistente" {
  run ccuse noexiste
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe la cuenta 'noexiste'"* ]]
}

@test "ccswitch sin argumentos retoma la conversación anterior" {
  run ccswitch
  [[ "$output" == *"CLAUDE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" == *"claude --continue"* ]]
}

@test "ccswitch con argumentos propios no inyecta --continue" {
  run ccswitch --version
  [[ "$output" == *"claude --version"* ]]
  [[ "$output" != *"--continue"* ]]
}

@test "CCM_NO_CONTINUE=1 hace que ccswitch abra una sesión nueva" {
  export CCM_NO_CONTINUE=1
  run ccswitch
  [[ "$output" == *"CLAUDE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" != *"--continue"* ]]
}
