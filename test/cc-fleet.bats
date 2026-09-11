setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/bin/cc-fleet.sh"
  TMP="$BATS_TEST_TMPDIR/ccm"

  UNO="$TMP/.claude-uno"; DOS="$TMP/.claude-dos"
  mkdir -p "$UNO/daemon" "$DOS/daemon"
  echo '{"workers":{}}' > "$UNO/daemon/roster.json"
  echo '{"workers":{}}' > "$DOS/daemon/roster.json"

  export CCM_ACCOUNTS_FILE="$TMP/accounts.json"
  cat > "$CCM_ACCOUNTS_FILE" <<EOF
{"accounts":[{"label":"uno","configDir":"$UNO"},{"label":"dos","configDir":"$DOS"}],
 "threshold":95}
EOF
}

# job <configDir> <short> <state> <tempo> <name>
job() {
  mkdir -p "$1/jobs/$2"
  cat > "$1/jobs/$2/state.json" <<EOF
{"state":"$3","tempo":"$4","name":"$5","cwd":"/tmp/repo-$2",
 "daemonShort":"$2","detail":"detalle de $5"}
EOF
}

# vivo <configDir> <short> <pid> — mete el worker en el roster de esa cuenta
vivo() {
  local f="$1/daemon/roster.json" t="$1/daemon/roster.t"
  jq --arg s "$2" --argjson p "$3" '.workers[$s] = {"pid":$p}' "$f" > "$t" && mv "$t" "$f"
}

@test "lista jobs de varias cuentas etiquetados por cuenta" {
  job "$UNO" aaaaaaaa working active "tarea de uno"; vivo "$UNO" aaaaaaaa $$
  job "$DOS" bbbbbbbb working active "tarea de dos"; vivo "$DOS" bbbbbbbb $$
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uno"*"tarea de uno"* ]]
  [[ "$output" == *"dos"*"tarea de dos"* ]]
}

@test "marca muerta la que no tiene worker vivo en el roster" {
  job "$UNO" aaaaaaaa working active "viva"; vivo "$UNO" aaaaaaaa $$
  # pid 2^31-1: no existe, y el short ni figura en el roster
  job "$DOS" bbbbbbbb working active "colgada"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"colgada"* ]]
  echo "$output" | grep -q 'muerta.*colgada\|colgada'
  echo "$output" | grep 'colgada' | grep -q 'muerta'
  echo "$output" | grep 'viva'    | grep -vq 'muerta'
}

@test "un job terminado y sin proceso se oculta salvo --all" {
  # el nombre no puede contener "terminada": el propio aviso de ocultas la usa
  job "$UNO" aaaaaaaa done idle "ya-finalizo"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ya-finalizo"* ]]
  [[ "$output" == *"oculta"* ]]
  run "$SCRIPT" --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"ya-finalizo"* ]]
}

@test "un job que decia trabajar y esta muerto NO se oculta" {
  job "$UNO" aaaaaaaa working active "colgada"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"colgada"* ]]
  [[ "$output" == *"muerta"* ]]
}

@test "colapsa estado y tempo cuando son iguales" {
  job "$UNO" aaaaaaaa blocked blocked "trabada"; vivo "$UNO" aaaaaaaa $$
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep 'trabada' | grep -q 'blocked'
  echo "$output" | grep 'trabada' | grep -vq 'blocked/blocked'
}

@test "ordena de mas reciente a mas vieja" {
  job "$UNO" aaaaaaaa working active "vieja"; vivo "$UNO" aaaaaaaa $$
  touch -t 202001010000 "$UNO/jobs/aaaaaaaa/state.json"
  job "$DOS" bbbbbbbb working active "nueva"; vivo "$DOS" bbbbbbbb $$
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -n 'nueva' | cut -d: -f1)" -lt \
    "$(echo "$output" | grep -n 'vieja' | cut -d: -f1)" ]
}

@test "sin jobs avisa y sale limpio" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no hay sesiones en background"* ]]
}

@test "no escribe nada en los config dirs" {
  job "$UNO" aaaaaaaa working active "tarea"; vivo "$UNO" aaaaaaaa $$
  antes="$(find "$UNO" "$DOS" -type f | sort | xargs shasum | shasum)"
  "$SCRIPT" >/dev/null
  despues="$(find "$UNO" "$DOS" -type f | sort | xargs shasum | shasum)"
  [ "$antes" = "$despues" ]
}
