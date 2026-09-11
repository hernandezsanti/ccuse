setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/bin/cc-mcp-sync.sh"
  TMP="$BATS_TEST_TMPDIR/ccm"

  UNO="$TMP/.claude-uno"; DOS="$TMP/.claude-dos"
  mkdir -p "$UNO" "$DOS"

  export CCM_ACCOUNTS_FILE="$TMP/accounts.json"
  cat > "$CCM_ACCOUNTS_FILE" <<EOF
{"accounts":[{"label":"uno","configDir":"$UNO"},{"label":"dos","configDir":"$DOS"}],
 "threshold":95}
EOF

  # fake claude: registra la llamada y mete el server en el .claude.json que
  # apunte CLAUDE_CONFIG_DIR, igual que haría `claude mcp add-json`
  BIN="$TMP/bin"; mkdir -p "$BIN"
  cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
# claude mcp add-json --scope user <name> <json>
name="${5:-}"; json="${6:-}"
echo "$*" >> "$CCM_CALLS"
f="$CLAUDE_CONFIG_DIR/.claude.json"
[ -f "$f" ] || echo '{}' > "$f"
tmp="$f.t"
jq --arg n "$name" --argjson v "$json" '.mcpServers[$n] = $v' "$f" > "$tmp" && mv "$tmp" "$f"
EOF
  chmod +x "$BIN/claude"
  export CCM_CLAUDE_BIN="$BIN/claude"
  export CCM_CALLS="$TMP/calls.log"
  : > "$CCM_CALLS"
}

mk() { printf '%s\n' "$2" > "$1/.claude.json"; }

@test "replica a la cuenta que no tiene el server" {
  mk "$UNO" '{"mcpServers":{"codegraph":{"type":"stdio","command":"codegraph"}}}'
  mk "$DOS" '{"mcpServers":{}}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run jq -r '.mcpServers.codegraph.command' "$DOS/.claude.json"
  [ "$output" = "codegraph" ]
}

@test "la union junta los de las dos cuentas en ambas" {
  mk "$UNO" '{"mcpServers":{"a":{"command":"a"}}}'
  mk "$DOS" '{"mcpServers":{"b":{"command":"b"}}}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  run jq -r '[.mcpServers|keys[]]|join(",")' "$UNO/.claude.json"
  [ "$output" = "a,b" ]
  run jq -r '[.mcpServers|keys[]]|join(",")' "$DOS/.claude.json"
  [ "$output" = "a,b" ]
}

@test "es idempotente: la segunda corrida no llama a claude" {
  mk "$UNO" '{"mcpServers":{"a":{"command":"a"}}}'
  mk "$DOS" '{"mcpServers":{}}'
  "$SCRIPT" >/dev/null
  : > "$CCM_CALLS"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ya tienen"* ]]
  [ ! -s "$CCM_CALLS" ]
}

@test "ante definiciones distintas avisa y no pisa la existente" {
  mk "$UNO" '{"mcpServers":{"a":{"command":"viejo"}}}'
  mk "$DOS" '{"mcpServers":{"a":{"command":"nuevo"}}}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OJO"* ]]
  run jq -r '.mcpServers.a.command' "$DOS/.claude.json"
  [ "$output" = "nuevo" ]
}

@test "--from replica solo los de esa cuenta" {
  mk "$UNO" '{"mcpServers":{"a":{"command":"a"}}}'
  mk "$DOS" '{"mcpServers":{"b":{"command":"b"}}}'
  run "$SCRIPT" --from uno
  [ "$status" -eq 0 ]
  run jq -r '[.mcpServers|keys[]]|join(",")' "$DOS/.claude.json"
  [ "$output" = "a,b" ]
  run jq -r '[.mcpServers|keys[]]|join(",")' "$UNO/.claude.json"
  [ "$output" = "a" ]
}

@test "--check falla y no escribe nada" {
  mk "$UNO" '{"mcpServers":{"a":{"command":"a"}}}'
  mk "$DOS" '{"mcpServers":{}}'
  run "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALTA dos: a"* ]]
  run jq -r '.mcpServers | length' "$DOS/.claude.json"
  [ "$output" = "0" ]
}

@test "--dry-run muestra el comando y no escribe" {
  mk "$UNO" '{"mcpServers":{"a":{"command":"a"}}}'
  mk "$DOS" '{"mcpServers":{}}'
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"add-json --scope user a"* ]]
  [ ! -s "$CCM_CALLS" ]
}

@test "sin MCP en ninguna cuenta no hace nada" {
  mk "$UNO" '{}'
  mk "$DOS" '{}'
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no hay MCP"* ]]
}
