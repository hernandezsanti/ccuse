# demo-setup.sh: prepares a fake environment for the demo GIF. Source it from the
# repository root (docs/demo.tape does this for you):
#
#   source docs/demo-setup.sh
#
# It never touches your real accounts, your Keychain or your ~/.claude:
# - HOME points to a new temporary directory with three fake accounts.
# - `security`, `curl`, `gh` and `claude` are stubs that come first on PATH.
# - Usage numbers come from a stub script (CCM_USAGE_CMD), not from the API.
# - CCM_DRY_RUN=1, so ccuse, ccx and ccswitch print the launch command instead of
#   starting Claude Code.

CCM_HOME="$(pwd)"
[ -f "$CCM_HOME/shell/claude-multi.sh" ] || { echo "run this from the repository root" >&2; return 1; }
export CCM_HOME

DEMO_HOME="${CCM_DEMO_HOME:-/tmp/ccm-demo}"
if [ -e "$DEMO_HOME" ] && [ ! -f "$DEMO_HOME/.ccm-demo" ]; then
  echo "$DEMO_HOME exists and was not created by this script; set CCM_DEMO_HOME" >&2
  return 1
fi
rm -rf "$DEMO_HOME"
mkdir -p "$DEMO_HOME/bin" "$DEMO_HOME/.claude" "$DEMO_HOME/.claude-work" "$DEMO_HOME/.claude-client"
touch "$DEMO_HOME/.ccm-demo"
export HOME="$DEMO_HOME"

cat > "$HOME/accounts.json" <<'EOF'
{
  "accounts": [
    { "label": "personal", "configDir": "~/.claude" },
    { "label": "work",     "configDir": "~/.claude-work" },
    { "label": "client",   "configDir": "~/.claude-client" }
  ],
  "threshold": 95
}
EOF

# Stubs. None of them reads or writes anything real.
for cmd in security curl gh; do
  printf '#!/usr/bin/env bash\necho "%s stub: not available in the demo" >&2\nexit 1\n' "$cmd" > "$HOME/bin/$cmd"
done
printf '#!/usr/bin/env bash\necho "claude stub: $*"\n' > "$HOME/bin/claude"

# Fake usage per account, in the same format as bin/cc-usage.sh.
cat > "$HOME/bin/fake-usage.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  */.claude)        echo '{"five_hour":40,"seven_day":22,"five_hour_resets_at":"2026-10-11T21:00:00Z"}' ;;
  */.claude-work)   echo '{"five_hour":96,"seven_day":61,"five_hour_resets_at":"2026-10-11T20:30:00Z"}' ;;
  */.claude-client) echo '{"five_hour":12,"seven_day":30,"five_hour_resets_at":"2026-10-11T23:00:00Z"}' ;;
esac
EOF
chmod +x "$HOME/bin/"*

# The JSON that Claude Code sends to the status line command, for a session of
# the work account that is close to its 5 hour limit.
now="$(date +%s)"
cat > "$HOME/session.json" <<EOF
{"model":{"display_name":"Opus 5"},
 "cost":{"total_cost_usd":1.42},"context_window":{"used_percentage":19},
 "workspace":{"current_dir":"$HOME/project"},
 "rate_limits":{"five_hour":{"used_percentage":96,"resets_at":$((now + 2400))},
                "seven_day":{"used_percentage":61,"resets_at":$((now + 260000))}}}
EOF

# A small git repository on a feature branch with an upstream, for the git segment.
git init -q --bare "$HOME/remote.git"
git init -q -b main "$HOME/project"
git -C "$HOME/project" -c user.name=demo -c user.email=demo@example.com commit -q --allow-empty -m init
git -C "$HOME/project" remote add origin "$HOME/remote.git"
git -C "$HOME/project" checkout -q -b feature/login
git -C "$HOME/project" push -q -u origin feature/login 2>/dev/null

export PATH="$HOME/bin:$CCM_HOME/bin:$PATH"
export CCM_ACCOUNTS_FILE="$HOME/accounts.json"
export CCM_STATE_DIR="$HOME/state"
export CCM_USAGE_CMD="$HOME/bin/fake-usage.sh"
export CCM_DRY_RUN=1
unset CLAUDE_CONFIG_DIR CCM_TMUX TMUX
# The demo shell plays the role of a running session of the work account.
export CLAUDE_SECURESTORAGE_CONFIG_DIR="$HOME/.claude-work"
export PS1='$ '

# shellcheck source=../shell/claude-multi.sh
source "$CCM_HOME/shell/claude-multi.sh"
cd "$HOME/project" || return 1
