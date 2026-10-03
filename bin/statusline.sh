#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=cc-lib.sh
source "$HERE/cc-lib.sh"

input="$(cat)"
[ -n "${CCM_DUMP_INPUT:-}" ] && printf '%s' "$input" > "$CCM_DUMP_INPUT" 2>/dev/null
THR="$(ccm_threshold 2>/dev/null || echo 95)"
R='\033[0m'
DIM='\033[2m'

jget() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

# OSC 8 hyperlink, built in the same escaped-text form as $R/$DIM (literal
# backslash sequences, not real escape bytes) because everything in $out goes
# through one `printf '%b'` at the very end. A real ESC byte here would still
# render, but the ST's raw backslash would sit next to plain label/color text
# and get reinterpreted by that final %b as the start of its own escape,
# corrupting whatever follows.
osc8() { printf '\\033]8;;%s\\033\\\\%s\\033]8;;\\033\\\\' "$1" "$2"; } # $1=url $2=label

# La cuenta la dice la credencial, no el config dir: con todas las cuentas sobre
# ~/.claude, .config_dir del JSON es siempre el mismo. La env var la hereda este
# proceso del claude que lo lanzó. Si no está (sesión del modelo viejo), cae al
# config_dir como antes.
cfg="${CLAUDE_SECURESTORAGE_CONFIG_DIR:-}"
[ -n "$cfg" ] || cfg="$(jget '.config_dir')"
cfg="${cfg:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
cfg="$(ccm_expand "$cfg")"
label="$(ccm_accounts 2>/dev/null | awk -F'\t' -v d="$cfg" '$2==d{print $1; f=1} END{if(!f) print "default"}' | head -1)"

sid="$(jget '.session_id')"
transcript="$(jget '.transcript_path')"

model="$(jget '.model.display_name')"
effort="$(jget '.effort.level')"
cost="$(jget '.cost.total_cost_usd')"
ctx="$(jget '.context_window.used_percentage')"
fh="$(jget '.rate_limits.five_hour.used_percentage')"
sd="$(jget '.rate_limits.seven_day.used_percentage')"
fhr="$(jget '.rate_limits.five_hour.resets_at')"
sdr="$(jget '.rate_limits.seven_day.resets_at')"

pick_col() { # $1=pct -> stdout color ANSI (literal escapado)
  if awk "BEGIN{exit !($1>=$THR)}"; then printf '\\033[31m'
  elif awk "BEGIN{exit !($1>=75)}"; then printf '\\033[33m'
  else printf '\\033[32m'; fi
}
reset_str() { # $1=epoch $2=fmt -> " ↻<hora>" en dim, o vacío
  local s; [ -n "$1" ] && s="$(date -r "$1" +"$2" 2>/dev/null)" || return 0
  [ -n "$s" ] && printf ' %s↻%s%s' "$DIM" "$s" "$R"
}

# --- Segmento git: rama, worktree, cambios, commits sin pushear y PR --------
# Solo dentro de un repo git. Todo es local y barato salvo el PR, que sale de
# `gh pr view` (red): se pide en segundo plano y se lee de una caché de 2 min,
# así la status bar nunca espera a la red.
CWD="$(jget '.workspace.current_dir')"
[ -n "$CWD" ] || CWD="$(jget '.cwd')"
PR_CACHE_DIR="${CCM_STATE_DIR:-$HERE/../state}"
PR_TTL=120

file_age() { # $1=archivo -> segundos desde su última modificación (enorme si no existe)
  local m; m="$(stat -f %m "$1" 2>/dev/null || echo 0)"
  echo $(( $(date +%s) - m ))
}

refresh_pr() { # $1=directorio $2=archivo de caché; corre desacoplado de la status bar
  (
    cd "$1" 2>/dev/null || exit 0
    tmp="$2.$$"
    if gh pr view --json number,url,state,isDraft,statusCheckRollup > "$tmp" 2>/dev/null; then :; else echo '{}' > "$tmp"; fi
    mv -f "$tmp" "$2"
  ) >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null || true
}

git_line() {
  [ -n "$CWD" ] && [ -d "$CWD" ] || return 0
  local st; st="$(git -C "$CWD" status --porcelain=v2 --branch 2>/dev/null)" || return 0
  [ -n "$st" ] || return 0

  local branch ahead has_up changes
  branch="$(printf '%s\n' "$st" | awk '/^# branch.head /{print $3}')"
  [ -n "$branch" ] || return 0
  ahead="$(printf '%s\n' "$st" | awk '/^# branch.ab /{gsub(/\+/,"",$3); print $3}')"
  has_up="$(printf '%s\n' "$st" | grep -c '^# branch.upstream ' || true)"
  changes="$(printf '%s\n' "$st" | grep -cE '^[12u?] ' || true)"
  [ "$branch" = "(detached)" ] && branch="HEAD suelto"

  # Rutas absolutas: desde un subdirectorio git-dir sale absoluto y
  # git-common-dir relativo, y comparados así un checkout parece un worktree.
  local gd cd_ is_wt=0
  { read -r gd; read -r cd_; } < <(git -C "$CWD" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) || true
  [ -n "$gd" ] && [ "$gd" != "$cd_" ] && is_wt=1

  local prod=0
  case "$branch" in main|master) prod=1 ;; esac

  local seg="$branch"
  [ "$is_wt" -eq 1 ] && seg="$seg · worktree"
  [ "${changes:-0}" -gt 0 ] && seg="$seg · $changes sin commitear"
  if [ "${ahead:-0}" -gt 0 ]; then seg="$seg · $ahead sin pushear"
  elif [ "${has_up:-0}" -eq 0 ] && [ "$prod" -eq 0 ]; then seg="$seg · sin upstream"; fi

  if [ "$prod" -eq 1 ]; then printf '\\033[1;31mPRODUCCIÓN %s%s' "$seg" "$R"
  else printf '%s%s%s' "$DIM" "$seg" "$R"; fi

  # PR de la rama: solo si ya está pusheada, no es producción y hay gh.
  [ "$prod" -eq 0 ] && [ "${has_up:-0}" -gt 0 ] && command -v gh >/dev/null 2>&1 || return 0
  local top key cache
  top="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || return 0
  key="$(printf '%s:%s' "$top" "$branch" | cksum | awk '{print $1}')"
  cache="$PR_CACHE_DIR/pr-$key.json"
  mkdir -p "$PR_CACHE_DIR" 2>/dev/null || return 0

  if [ "$(file_age "$cache")" -gt "$PR_TTL" ] && [ "$(file_age "$cache.lock")" -gt 30 ]; then
    touch "$cache.lock" 2>/dev/null || true
    refresh_pr "$CWD" "$cache"
  fi

  [ -s "$cache" ] || return 0
  local info; info="$(jq -r '
    def o: (if (.conclusion // "") != "" then .conclusion elif (.state // "") != "" then .state else (.status // "") end) | ascii_upcase;
    select(.number != null) |
    (.statusCheckRollup // []) as $r |
    (if ($r | length) == 0 then "none"
     elif any($r[]; o | IN("FAILURE","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE","ERROR")) then "fail"
     elif all($r[]; if (.status // "") != "" then (.status | ascii_upcase) == "COMPLETED" else o != "PENDING" end) then "ok"
     else "pending" end) as $c |
    [.number, ((if .isDraft then "borrador" elif .state == "OPEN" then "-" else (.state | ascii_downcase) end)), $c, .url] | @tsv
  ' "$cache" 2>/dev/null)" || return 0
  [ -n "$info" ] || return 0

  local num state checks url label col
  # El estado vacío (PR abierto) viaja como "-": con un campo vacío, `read` juntaría los tabuladores.
  IFS=$'\t' read -r num state checks url <<< "$info"
  [ "$state" = "-" ] && state=""
  case "$checks" in
    ok) label="CI ok"; col='\033[32m' ;;
    fail) label="CI falla"; col='\033[31m' ;;
    pending) label="CI corriendo"; col='\033[33m' ;;
    *) label="sin CI"; col="$DIM" ;;
  esac
  printf ' · %s%s%s%s · %s%s%s' "$DIM" "$(osc8 "$url" "PR #$num")" "${state:+ $state}" "$R" "$col" "$label" "$R"
}

gl="$(git_line || true)"

out="$label"
[ -n "$gl" ] && out="$out · $gl"
if [ -n "$sid" ]; then
  short_sid="${sid:0:8}"
  if [ -n "$transcript" ]; then
    # Spaces are the only character in a stock Claude Code path likely to
    # break a file:// URI; anything fancier is not worth pulling in a URL
    # encoder for a link that only ever points at a local path.
    id_seg="$(osc8 "file://${transcript// /%20}" "$short_sid")"
  else
    id_seg="$short_sid"
  fi
  out="$out · ${DIM}${id_seg}${R}"
fi
[ -n "$model" ]  && out="$out · ${DIM}${model}${R}"
[ -n "$effort" ] && out="$out · ${DIM}${effort}${R}"
[ -n "$cost" ]   && out="$out · ${DIM}\$$(printf '%.2f' "$cost")${R}"
[ -n "$ctx" ]    && out="$out · $(pick_col "$ctx")ctx $(printf '%.0f' "$ctx")%$R"
[ -n "$fh" ]     && out="$out · $(pick_col "$fh")5h $(printf '%.0f' "$fh")%$R$(reset_str "$fhr" '%H:%M')"
[ -n "$sd" ]     && out="$out · $(pick_col "$sd")7d $(printf '%.0f' "$sd")%$R$(reset_str "$sdr" '%d/%m %H:%M')"

alert=0
[ -n "$fh" ] && awk "BEGIN{exit !($fh>=$THR)}" && alert=1
[ -n "$sd" ] && awk "BEGIN{exit !($sd>=$THR)}" && alert=1
[ "$alert" -eq 1 ] && out="$out  \\033[1;31m⚠️  ${THR}% — cambia de cuenta: ccswitch$R"

# Guarda el último uso para que el hook Stop lo lea sin llamar a la API.
STATE_DIR="${CCM_STATE_DIR:-$HERE/../state}"
if [ -n "$fh$sd" ]; then
  mkdir -p "$STATE_DIR" 2>/dev/null && \
  jq -cn --arg l "$label" --arg cd "$cfg" \
     --argjson fh "${fh:-null}" --argjson sd "${sd:-null}" \
     --argjson ts "$(date +%s)" \
     '{label:$l,config_dir:$cd,five_hour:$fh,seven_day:$sd,ts:$ts}' \
     > "$STATE_DIR/usage-$(ccm_slug "$label").json" 2>/dev/null || true
fi

printf '%b' "$out"
