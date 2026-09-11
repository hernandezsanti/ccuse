#!/usr/bin/env bash
# cc-new-account.sh — da de alta (o repara) una cuenta: crea el config dir con los
# symlinks compartidos a la cuenta base y la registra en accounts.json.
#
# Es idempotente: correrlo sobre una cuenta existente repara los links que falten.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

usage() {
  cat >&2 <<'EOF'
uso: cc-new-account.sh [--check] [--dry-run] <label> [configDir]

  <label>      nombre de la cuenta (p. ej. cliente)
  [configDir]  por defecto ~/.claude-<label>

  --check      solo diagnostica, no escribe nada (exit 1 si falta algo)
  --dry-run    muestra lo que haría, sin tocar el disco
EOF
  return 1
}

CHECK=""; DRY=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)   CHECK=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage ;;
    -*)        ccm_die "opción desconocida: $1"; usage ;;
    *)         break ;;
  esac
done

LABEL="${1:-}"; [ -n "$LABEL" ] || usage
case "$LABEL" in
  *[!A-Za-z0-9_-]*) ccm_die "label inválido: '$LABEL' (solo A-Za-z0-9_-)"; exit 1 ;;
esac

RAW_DIR="${2:-~/.claude-$LABEL}"
DIR="$(ccm_expand "$RAW_DIR")"
BASE="$(ccm_base_dir)"
TS="$(date +%Y%m%d-%H%M%S)"

[ -d "$BASE" ]      || { ccm_die "no existe la cuenta base: $BASE"; exit 1; }
[ "$DIR" != "$BASE" ] || { ccm_die "el config dir no puede ser la cuenta base ($BASE)"; exit 1; }

# run — ejecuta, salvo en --check (nunca escribe) o --dry-run (solo muestra).
run() {
  [ -n "$CHECK" ] && return 0
  if [ -n "$DRY" ]; then printf '  DRY: %s\n' "$*"; else "$@"; fi
}
say() { printf '%s\n' "$*"; }

# rescue_flat <item> — rescata <DIR>/<item>/<archivo> hacia la base antes de que el
# paso 3 mande el dir al .bak. Para los items sin subdirectorios, donde el nombre del
# archivo ya es la clave (pid en sessions/, hash de contenido en paste-cache/) y por
# eso no puede colisionar entre cuentas.
rescue_flat() {
  local item="$1" src="$DIR/$1" n=0 f
  [ -d "$src" ] && [ ! -L "$src" ] && [ -d "$BASE/$item" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    run mv -n "$f" "$BASE/$item/"
    n=$((n + 1))
  done < <(find "$src" -mindepth 1 -maxdepth 1 -type f 2>/dev/null)
  [ "$n" -gt 0 ] || return 0
  if [ -n "$CHECK" ]; then say "resc  $item: $n archivo(s) en $src (se moverían a la base)"
  else say "resc  $item: $n archivo(s) movidos a $BASE/$item"; fi
}

# rescue_nested <item> — rescata <DIR>/<item>/<uuid>/<archivo> hacia la base antes
# de que el paso 3 mande el dir al .bak. Mergea por archivo en vez de mover el dir
# entero porque el mismo uuid puede existir de los dos lados: una sesión resumida
# en otra cuenta parte su estado. Ante colisión gana lo que ya estaba en la base.
# Saltea .lock, que pertenece al proceso que lo tenga abierto ahora.
rescue_nested() {
  local item="$1" src="$DIR/$1" n=0 f uuid
  [ -d "$src" ] && [ ! -L "$src" ] && [ -d "$BASE/$item" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    uuid="$(basename "$(dirname "$f")")"
    run mkdir -p "$BASE/$item/$uuid"
    run mv -n "$f" "$BASE/$item/$uuid/"
    n=$((n + 1))
  done < <(find "$src" -mindepth 2 -maxdepth 2 -type f \
             ! -name '.lock' ! -name '.highwatermark' 2>/dev/null)
  [ "$n" -gt 0 ] || return 0
  if [ -n "$CHECK" ]; then say "resc  $item: $n archivo(s) en $src (se moverían a la base)"
  else say "resc  $item: $n archivo(s) movidos a $BASE/$item"; fi
}

write_file() { printf '%s' "$2" > "$1"; }

# fix_highwatermarks — deja el .highwatermark de cada dir de tareas en la base
# por encima del mayor <N>.json que haya. Es el único archivo que no se puede
# resolver con "gana la base" como el resto del merge: es el último id de tarea
# entregado, así que quedarse con la marca de una cuenta y las tareas de la otra
# hace que el próximo id pise una tarea existente. Subirla siempre es seguro.
fix_highwatermarks() {
  local dir="$BASE/tasks" d hw mx n=0
  [ -d "$dir" ] || return 0
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    mx="$(ls -A "$d" 2>/dev/null | sed -n 's/^\([0-9][0-9]*\)\.json$/\1/p' | sort -n | tail -1)"
    [ -n "$mx" ] || continue
    hw="$(cat "$d/.highwatermark" 2>/dev/null || true)"
    case "$hw" in ''|*[!0-9]*) hw=0 ;; esac
    [ "$hw" -lt "$mx" ] || continue
    run write_file "$d/.highwatermark" "$mx"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || return 0
  if [ -n "$CHECK" ]; then say "hwm   $n dir(s) de tareas con la marca por debajo del mayor id (se corregirían)"
  else say "hwm   $n dir(s) de tareas con la marca corregida"; fi
}

missing=0

# --- 1. config dir ------------------------------------------------------------
if [ -d "$DIR" ]; then
  say "dir   $DIR (ya existe)"
else
  missing=1
  if [ -n "$CHECK" ]; then say "FALTA dir   $DIR"
  elif [ -n "$DRY" ]; then say "dir   $DIR (se crearía)"; run mkdir -p "$DIR"
  else say "dir   $DIR (creado)"; run mkdir -p "$DIR"; fi
fi

# --- 2. rescatar sesiones sueltas antes de reemplazar projects/ ----------------
# Si projects/ es un dir real con transcripts, se pierden al symlinkear: los
# movemos a la cuenta base primero (mv preserva el inodo, no rompe sesiones vivas).
if [ -d "$DIR/projects" ] && [ ! -L "$DIR/projects" ]; then
  n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    proj="$(basename "$(dirname "$f")")"
    run mkdir -p "$BASE/projects/$proj"
    run mv -n "$f" "$BASE/projects/$proj/"
    n=$((n + 1))
  done < <(find "$DIR/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' 2>/dev/null)
  if [ "$n" -gt 0 ]; then
    if [ -n "$CHECK" ]; then say "chats $n transcript(s) sueltos en $DIR/projects (se moverían a la base)"
    else say "chats $n transcript(s) movidos a $BASE/projects"; fi
  fi
fi

# --- 2b. rescatar el resto del estado antes de que el paso 3 lo mande al .bak --
# sessions/ es el más urgente: tiene el registro de cada sesión viva (<pid>.json)
# y su clave de socket (<pid>.<hash>.key), así que perderlo deja a las sesiones
# que estén corriendo sin responder a SendMessage hasta reiniciarlas.
rescue_flat sessions
rescue_flat paste-cache
rescue_nested tasks
rescue_nested file-history
rescue_nested image-cache
fix_highwatermarks

# --- 3. symlinks compartidos --------------------------------------------------
while IFS= read -r item; do
  [ -n "$item" ] || continue
  target="$BASE/$item"
  link="$DIR/$item"

  if [ ! -e "$target" ]; then
    say "skip  $item (no existe en la base: $target)"
    continue
  fi

  if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
    say "ok    $item"
    continue
  fi

  missing=1
  if [ -n "$CHECK" ]; then
    if [ -e "$link" ] || [ -L "$link" ]; then say "MAL   $item (existe pero no apunta a $target)"
    else say "FALTA $item"; fi
    continue
  fi

  if [ -e "$link" ] || [ -L "$link" ]; then
    run mv "$link" "$link.bak.$TS"
    say "link  $item -> $target (lo previo quedó en $item.bak.$TS)"
  else
    say "link  $item -> $target"
  fi
  run ln -s "$target" "$link"
done < <(ccm_shared_items)

# --- 4. registro en accounts.json ---------------------------------------------
if jq -e --arg l "$LABEL" 'any(.accounts[]; .label == $l)' "$CCM_ACCOUNTS_FILE" >/dev/null; then
  say "json  '$LABEL' ya está en $(basename "$CCM_ACCOUNTS_FILE")"
else
  missing=1
  if [ -n "$CHECK" ]; then
    say "FALTA json  '$LABEL' no está en $(basename "$CCM_ACCOUNTS_FILE")"
  else
    tmp="$CCM_ACCOUNTS_FILE.tmp.$$"
    jq --arg l "$LABEL" --arg d "$RAW_DIR" \
      '.accounts += [{label: $l, configDir: $d}]' "$CCM_ACCOUNTS_FILE" > "$tmp"
    if [ -n "$DRY" ]; then
      rm -f "$tmp"; say "  DRY: agregar {label:$LABEL, configDir:$RAW_DIR} a accounts.json"
    else
      cp "$CCM_ACCOUNTS_FILE" "$CCM_ACCOUNTS_FILE.bak.$TS"
      mv "$tmp" "$CCM_ACCOUNTS_FILE"
      say "json  '$LABEL' agregado (backup: accounts.json.bak.$TS)"
    fi
  fi
fi

# --- 5. login ------------------------------------------------------------------
if [ -n "$CHECK" ]; then
  [ "$missing" -eq 0 ] && { say ""; say "cuenta '$LABEL' OK"; exit 0; }
  say ""; ccm_die "cuenta '$LABEL' incompleta — corré: cc-new-account.sh $LABEL $RAW_DIR"
  exit 1
fi

svc="$(ccm_keychain_service "$DIR")"
if security find-generic-password -s "$svc" >/dev/null 2>&1; then
  say "login ya hay credenciales en Keychain ($svc)"
else
  say ""
  say "Falta loguear la cuenta. En una terminal real (no dentro de Claude Code):"
  say ""
  say "  CLAUDE_CONFIG_DIR=\"$DIR\" claude    # adentro: /login, luego /exit"
  say ""
  say "Después: ccuse $LABEL   (o el alias claude-$LABEL, tras reabrir la terminal)"
fi
