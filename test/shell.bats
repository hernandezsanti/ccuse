setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CCM_HOME="$ROOT"
  export CCM_ACCOUNTS_FILE="$ROOT/test/fixtures/accounts.sample.json"
  # cc-pick fake: siempre elige /tmp/cc-dos
  PICK="$BATS_TEST_TMPDIR/cc-pick.sh"
  printf '#!/usr/bin/env bash\necho /tmp/cc-dos\n' > "$PICK"; chmod +x "$PICK"
  export CCM_PICK_CMD="$PICK"
  export CCM_DRY_RUN=1
  unset CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR
  source "$ROOT/shell/claude-multi.sh"
}

@test "cc-label devuelve el label configurado" {
  run "$ROOT/bin/cc-label.sh" "/tmp/cc-dos"
  [ "$output" = "dos" ]
}

@test "ccx elige cuenta: sin CLAUDE_CONFIG_DIR y con la credencial de esa cuenta" {
  run ccx --version
  [[ "$output" == *"CLAUDE_CONFIG_DIR=<unset>"* ]]
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "ccx para la cuenta default pinea la credencial default" {
  printf '#!/usr/bin/env bash\necho %s/.claude\n' "$HOME" > "$CCM_PICK_CMD"
  run ccx
  [[ "$output" == *"CLAUDE_CONFIG_DIR=<unset>"* ]]
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=<default>"* ]]
}

@test "ccuse lanza la cuenta por su label (dry-run)" {
  run ccuse dos --version
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "ccuse falla con un label inexistente" {
  run ccuse noexiste
  [ "$status" -ne 0 ]
  [[ "$output" == *"no existe la cuenta 'noexiste'"* ]]
}

@test "ccswitch sin argumentos retoma la conversación anterior" {
  run ccswitch
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" == *"claude --continue"* ]]
}

@test "ccswitch excluye la cuenta actual leyendola de la variable de credencial" {
  # pick fake que imprime lo que le pasaron como exclusión
  printf '#!/usr/bin/env bash\necho "EXCL=$1" >&2; echo /tmp/cc-dos\n' > "$CCM_PICK_CMD"
  export CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-uno
  run ccswitch
  [[ "$output" == *"EXCL=/tmp/cc-uno"* ]]
}

@test "ccswitch con argumentos propios no inyecta --continue" {
  run ccswitch --version
  [[ "$output" == *"claude --version"* ]]
  [[ "$output" != *"--continue"* ]]
}

@test "CCM_NO_CONTINUE=1 hace que ccswitch abra una sesión nueva" {
  export CCM_NO_CONTINUE=1
  run ccswitch
  [[ "$output" == *"CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-dos"* ]]
  [[ "$output" != *"--continue"* ]]
}

@test "CCM_TMUX=1 envuelve claude en tmux usando el -n como nombre de sesión" {
  export CCM_TMUX=1
  unset TMUX
  run ccuse dos -n my.session "hola"
  [[ "$output" == *"tmux new-session -A -s my-session env -u CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR=/tmp/cc-dos claude -n my.session hola"* ]]
}

@test "dentro de tmux no se anida otra sesión" {
  export CCM_TMUX=1 TMUX=/tmp/tmux-fake,1,0
  run ccuse dos --version
  [[ "$output" != *"tmux new-session"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "sin CCM_TMUX no se usa tmux" {
  unset TMUX CCM_TMUX
  run ccuse dos --version
  [[ "$output" != *"tmux"* ]]
  [[ "$output" == *"claude --version"* ]]
}

@test "t ccuse activa tmux" {
  unset TMUX CCM_TMUX
  run t ccuse dos -n my.session
  [[ "$output" == *"tmux new-session -A -s my-session"* ]]
}

@test "CCM_TMUX=0 y el modo -p no usan tmux" {
  unset TMUX
  CCM_TMUX=0 run ccuse dos --version
  [[ "$output" != *"tmux"* ]]
  CCM_TMUX=1 run ccuse dos -p "hola"
  [[ "$output" != *"tmux"* ]]
}

@test "sin -n el nombre de sesión sale de la carpeta" {
  export CCM_TMUX=1
  unset TMUX
  cd "$BATS_TEST_TMPDIR"
  run ccuse dos
  [[ "$output" == *"tmux new-session -A -s cc-${PWD##*/}-"* ]]
}
