setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/bin/cc-new-account.sh"
  TMP="$BATS_TEST_TMPDIR/ccm"

  # cuenta base falsa con los items compartidos
  export CCM_BASE_DIR="$TMP/base"
  mkdir -p "$CCM_BASE_DIR"
  local d
  for d in agents commands file-history hooks image-cache paste-cache plugins \
           rules sessions skills tasks; do
    mkdir -p "$CCM_BASE_DIR/$d"
  done
  printf 'X=1\n' > "$CCM_BASE_DIR/.env"
  printf '{"statusLine":{"command":"real.sh"}}\n' > "$CCM_BASE_DIR/settings.json"
  printf '{}\n' > "$CCM_BASE_DIR/settings.local.json"
  mkdir -p "$CCM_BASE_DIR/projects/-proj-viejo"
  printf '{"old":1}\n' > "$CCM_BASE_DIR/projects/-proj-viejo/vieja.jsonl"

  export CCM_ACCOUNTS_FILE="$TMP/accounts.json"
  printf '{"accounts":[{"label":"personal","configDir":"~/.claude"}],"threshold":95}\n' \
    > "$CCM_ACCOUNTS_FILE"

  NEW="$TMP/.claude-nueva"
  UUID="036e4404-2775-4b9c-bebe-63b92be6e4a0"
}

# arma un config dir roto como el que deja un alta a medias:
# settings.json stub propio, plugins/ y projects/ reales, sin ningún symlink
mk_rota() {
  ROTA="$TMP/.claude-rota"
  mkdir -p "$ROTA/projects/-proj-nuevo" "$ROTA/plugins" "$ROTA/sessions"
  printf '{"theme":"dark"}\n' > "$ROTA/settings.json"
  printf '{"session":"importante"}\n' > "$ROTA/projects/-proj-nuevo/chat.jsonl"
  printf '{"pid":4242,"name":"viva"}\n' > "$ROTA/sessions/4242.json"
  printf '{"peerToken":"deadbeef"}\n' > "$ROTA/sessions/4242.abc.key"

  # split-brain: el uuid compartido ya tiene tareas en la base (1.json) y la
  # cuenta le agregó otras (2.json) al resumir la sesión del otro lado
  mkdir -p "$CCM_BASE_DIR/tasks/$UUID" "$ROTA/tasks/$UUID" "$ROTA/file-history/$UUID"
  printf '{"id":"1","subject":"de la base"}\n' > "$CCM_BASE_DIR/tasks/$UUID/1.json"
  printf '{"id":"1","subject":"pisaria la base"}\n' > "$ROTA/tasks/$UUID/1.json"
  printf '{"id":"2","subject":"solo en la cuenta"}\n' > "$ROTA/tasks/$UUID/2.json"
  : > "$ROTA/tasks/$UUID/.lock"
  # la base venía marcando 1 y la cuenta 2: quedarse con la de la base haría que
  # la próxima tarea se numere 2 y pise la que ya existe
  printf '1' > "$CCM_BASE_DIR/tasks/$UUID/.highwatermark"
  printf '2' > "$ROTA/tasks/$UUID/.highwatermark"
  printf 'v1\n' > "$ROTA/file-history/$UUID/abc@v1"

  mkdir -p "$ROTA/image-cache/$UUID" "$ROTA/paste-cache"
  printf 'PNG\n' > "$ROTA/image-cache/$UUID/1.png"
  printf 'pegado\n' > "$ROTA/paste-cache/deadbeef12345678.txt"
}

@test "crea el config dir con los 15 symlinks a la base" {
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  local item
  while IFS= read -r item; do
    [ -L "$NEW/$item" ]
    [ "$(readlink "$NEW/$item")" = "$CCM_BASE_DIR/$item" ]
  done < <(cat <<'EOF'
.env
agents
commands
file-history
hooks
image-cache
paste-cache
plugins
projects
rules
sessions
settings.json
settings.local.json
skills
tasks
EOF
)
}

@test "la cuenta nueva ve el historial de la base" {
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  [ -f "$NEW/projects/-proj-viejo/vieja.jsonl" ]
}

@test "registra la cuenta en accounts.json y deja backup" {
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  run jq -r '.accounts[] | select(.label=="nueva") | .configDir' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "$NEW" ]
  ls "$CCM_ACCOUNTS_FILE".bak.* >/dev/null
}

@test "no duplica la cuenta si ya está registrada" {
  "$SCRIPT" nueva "$NEW" >/dev/null
  "$SCRIPT" nueva "$NEW" >/dev/null
  run jq '[.accounts[] | select(.label=="nueva")] | length' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "1" ]
}

@test "es idempotente: la segunda corrida no crea backups nuevos" {
  "$SCRIPT" nueva "$NEW" >/dev/null
  "$SCRIPT" nueva "$NEW" >/dev/null
  run bash -c "find '$NEW' -maxdepth 1 -name '*.bak.*' | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "repara una cuenta rota y respalda lo previo" {
  mk_rota
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  [ -L "$ROTA/settings.json" ]
  run cat "$ROTA/settings.json"
  [[ "$output" == *"real.sh"* ]]
  ls "$ROTA"/settings.json.bak.* >/dev/null
  ls "$ROTA"/plugins.bak.* >/dev/null
}

@test "al reparar rescata los transcripts sueltos hacia la base" {
  mk_rota
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  [ -f "$CCM_BASE_DIR/projects/-proj-nuevo/chat.jsonl" ]
  run cat "$CCM_BASE_DIR/projects/-proj-nuevo/chat.jsonl"
  [[ "$output" == *"importante"* ]]
}

@test "al reparar rescata el registro de sesiones vivas hacia la base" {
  mk_rota
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  # el .json y la .key siguen alcanzables por el path de la cuenta (vía symlink)
  [ -f "$ROTA/sessions/4242.json" ]
  [ -f "$ROTA/sessions/4242.abc.key" ]
  [ -f "$CCM_BASE_DIR/sessions/4242.json" ]
  [ -f "$CCM_BASE_DIR/sessions/4242.abc.key" ]
}

@test "al reparar mergea tasks/ del mismo uuid sin pisar lo de la base" {
  mk_rota
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  # 1.json existía de los dos lados: gana la base
  run cat "$CCM_BASE_DIR/tasks/$UUID/1.json"
  [[ "$output" == *"de la base"* ]]
  # 2.json solo estaba en la cuenta: se rescata
  [ -f "$CCM_BASE_DIR/tasks/$UUID/2.json" ]
  # y la cuenta ve las dos por el symlink
  [ -f "$ROTA/tasks/$UUID/1.json" ]
  [ -f "$ROTA/tasks/$UUID/2.json" ]
}

@test "el merge deja la marca de tareas por encima del mayor id" {
  mk_rota
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  run cat "$CCM_BASE_DIR/tasks/$UUID/.highwatermark"
  [ "$output" = "2" ]
}

@test "la marca se corrige tambien si falta y ya hay tareas" {
  mk_rota
  rm -f "$CCM_BASE_DIR/tasks/$UUID/.highwatermark" "$ROTA/tasks/$UUID/.highwatermark"
  printf '{"id":"9"}\n' > "$ROTA/tasks/$UUID/9.json"
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  run cat "$CCM_BASE_DIR/tasks/$UUID/.highwatermark"
  [ "$output" = "9" ]
}

@test "al reparar rescata file-history y no se lleva el .lock" {
  mk_rota
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  [ -f "$CCM_BASE_DIR/file-history/$UUID/abc@v1" ]
  [ ! -e "$CCM_BASE_DIR/tasks/$UUID/.lock" ]
}

@test "al reparar rescata image-cache y paste-cache" {
  mk_rota
  run "$SCRIPT" rota "$ROTA"
  [ "$status" -eq 0 ]
  [ -f "$CCM_BASE_DIR/image-cache/$UUID/1.png" ]
  [ -f "$CCM_BASE_DIR/paste-cache/deadbeef12345678.txt" ]
  # y la cuenta los sigue viendo por el symlink
  [ -f "$ROTA/image-cache/$UUID/1.png" ]
  [ -f "$ROTA/paste-cache/deadbeef12345678.txt" ]
}

@test "--check falla en una cuenta rota sin escribir nada" {
  mk_rota
  run "$SCRIPT" --check rota "$ROTA"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FALTA"* ]]
  # no movió el transcript ni tocó accounts.json
  [ -f "$ROTA/projects/-proj-nuevo/chat.jsonl" ]
  run jq '[.accounts[] | select(.label=="rota")] | length' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "0" ]
}

@test "--check pasa en una cuenta sana" {
  "$SCRIPT" nueva "$NEW" >/dev/null
  run "$SCRIPT" --check nueva "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "--dry-run no toca el disco" {
  run "$SCRIPT" --dry-run nueva "$NEW"
  [ "$status" -eq 0 ]
  [ ! -e "$NEW" ]
  run jq '[.accounts[] | select(.label=="nueva")] | length' "$CCM_ACCOUNTS_FILE"
  [ "$output" = "0" ]
}

@test "rechaza un label inválido" {
  run "$SCRIPT" 'mal label!'
  [ "$status" -ne 0 ]
  [[ "$output" == *"label inválido"* ]]
}

@test "rechaza usar la cuenta base como config dir" {
  run "$SCRIPT" base "$CCM_BASE_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no puede ser la cuenta base"* ]]
}

@test "no crea symlinks rotos si falta el item en la base" {
  rm -rf "$CCM_BASE_DIR/rules"
  run "$SCRIPT" nueva "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip  rules"* ]]
  [ ! -e "$NEW/rules" ]
  [ ! -L "$NEW/rules" ]
}
