# ccuse

Switch Claude Code accounts when one runs out of quota, without losing the conversation.

Shell scripts for macOS. All accounts share one config directory, so an account is only a
credential.

![Terminal demo: the accounts file lists three accounts; "ccuse work -n demo" prints the launch command for the work account; the status line of a work session shows 5h 96% and a red warning "95%: switch account with ccswitch"; "ccswitch" then picks the client account and continues the conversation.](docs/demo.gif)

```bash
ccx          # open Claude Code with the account that has the lowest usage
ccuse work   # open the account with the label "work"
ccswitch     # move the current conversation to another account with quota left
```

The demo uses fake accounts and stubbed usage numbers. See [docs/demo.md](docs/demo.md)
for how it is recorded.

## Why this approach

Each Claude Code subscription has a 5 hour limit and a 7 day limit. If you have more
than one account, for example a personal one and a work one, there are two common ways
to switch between them:

- Log out and log in again with `/login`. This is slow, and you lose track of which
  account has quota left.
- Use one `CLAUDE_CONFIG_DIR` per account. This works, but then every account has its
  own history, settings, MCP servers, skills and background daemon. You have to keep
  them in sync by hand, and you cannot continue a conversation in another account.

This tool keeps one config directory (`~/.claude`) for all accounts. The only thing
that changes between accounts is the credential, which Claude Code reads from a
different Keychain entry. So history, settings, MCP servers and skills are shared,
and `ccswitch` can continue the same conversation in another account.

It also adds a status line that shows the usage of the current account, and a warning
with the `ccswitch` command when the account reaches a threshold (95% by default).

Do not use it if you are not on macOS, if you use an API key instead of a Claude
subscription, or if you only have one account.

## Status and limitations

This is a personal tool with one maintainer. There are no versioned releases. It
depends on two things that are not public, documented interfaces: how Claude Code
names its Keychain entries, and the `/api/oauth/usage` endpoint. A future Claude Code
version can break it. It is released under the [MIT license](LICENSE).

Other limitations:

- It only works on macOS. The credential lookup uses the Keychain through `security`,
  and the scripts use the BSD versions of `stat` and `date`.
- Because all accounts share one config directory, some things are shared that
  should not be. `/status` and the start banner show the last account that started,
  not the account of the current session. This is only cosmetic: billing and rate
  limits follow the credential, and the status line shows the correct account. The
  cache of MCP connectors that need authentication is also shared, so if a connector
  fails to authenticate in one account, the other account can skip it for a few
  minutes. Deleting `~/.claude/mcp-needs-auth-cache.json` fixes it.
- `ccx` and `ccswitch` make one network request per account before they start, with
  a 5 second timeout each.
- Logging in to a new account is a manual step.

## Install

You need:

- macOS. The scripts use the `security` command for the Keychain, and the BSD
  versions of `stat` and `date`.
- `bash`, `jq`, `curl` and `shasum`.
- Claude Code installed as `claude`, logged in with a Claude subscription.
- Optional: `gh` to show the pull request of the current branch in the status line,
  `tmux` for the tmux mode, and [bats-core](https://github.com/bats-core/bats-core)
  to run the tests.

Then:

1. Clone the repository. The shell functions expect it in
   `~/projects/claude-multi-account`. If you put it somewhere else, set `CCM_HOME`
   to that path before you source the shell file.

   ```bash
   git clone https://github.com/hernandezsanti/ccuse.git ~/projects/claude-multi-account
   ```

2. Create your accounts file from the example, and change the labels if you want:

   ```bash
   cd ~/projects/claude-multi-account
   cp accounts.example.json accounts.json
   ```

3. Add this line to `~/.zshrc` (or `~/.bashrc`) and open a new terminal:

   ```bash
   source ~/projects/claude-multi-account/shell/claude-multi.sh
   ```

4. Check that it works without starting Claude Code. `CCM_DRY_RUN=1` prints the
   launch command instead of running it:

   ```bash
   CCM_DRY_RUN=1 ccuse work
   ```

   The output looks like this:

   ```
   cc: using account [work] (/Users/you/.claude-work)
   DRY: CLAUDE_CONFIG_DIR=<unset> CLAUDE_SECURESTORAGE_CONFIG_DIR=/Users/you/.claude-work claude
   ```

5. Log in to each extra account once. See [Add an account](#add-an-account).

6. Configure the status line and the `Stop` hook in `~/.claude/settings.json`. Use
   the full path to the scripts:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/Users/you/projects/claude-multi-account/bin/statusline.sh"
     },
     "hooks": {
       "Stop": [
         { "hooks": [ { "type": "command", "command": "/Users/you/projects/claude-multi-account/bin/stop-notify.sh" } ] }
       ]
     }
   }
   ```

7. Optional: install the `/fleet` slash command. The file uses the path
   `~/projects/claude-multi-account`, so edit it if you cloned the repository in a
   different place.

   ```bash
   ln -s ~/projects/claude-multi-account/commands/fleet.md ~/.claude/commands/fleet.md
   ```

## Usage

```bash
ccx                  # open Claude Code with the account that has the lowest usage
ccuse work           # open a specific account by its label
claude-work          # alias for `ccuse work`, created for each account
ccswitch             # open another account and continue the same conversation
```

All these commands pass extra arguments to `claude`:

```bash
ccuse work -n my-session "initial prompt"
ccx --model opus
```

`ccx` checks the usage of every account and picks the one with the lowest 5 hour
usage, among the accounts that are below the threshold on both the 5 hour and the 7
day limit. If all accounts are over the threshold, it picks the one whose 5 hour
window resets first.

`ccswitch` does the same, but it skips the current account. Without arguments it adds
`--continue`, and since the history is shared, the conversation continues in the
other account. Use `CCM_NO_CONTINUE=1 ccswitch` to start a new session instead.

The `claude-<label>` aliases are created from `accounts.json` every time the shell
file is sourced. Claude Code starts in a subshell, so no variables stay in your
terminal.

To list the background sessions of all accounts, use `bin/cc-fleet.sh` or the
`/fleet` command. It reads `jobs/*/state.json` and `daemon/roster.json` from the
directory of each account and does not write anything. A session marked `·dead` has no live
worker. If it also says `working`, it is probably stuck. Use `--all` to include
finished sessions.

With one shared config directory, the built-in background sessions panel already
shows everything. This command is mostly useful for sessions that were started with
one config directory per account.

### tmux mode

With `CCM_TMUX=1`, the commands above run Claude Code inside a tmux session. If the
terminal crashes, the session keeps running and you can get it back with
`tmux attach -t <name>`. The session name is the `-n` value if you pass one,
otherwise `cc-<folder>-<hhmmss>`. tmux is not used if you are already inside tmux or
if you pass `-p`.

```bash
t ccuse work -n my-session   # same as CCM_TMUX=1 ccuse work -n my-session
ccsessions                   # list the tmux sessions, to find one after a crash
```

## Configure accounts

`accounts.json` lists your accounts and the warning threshold:

```json
{
  "accounts": [
    { "label": "personal", "configDir": "~/.claude" },
    { "label": "work",     "configDir": "~/.claude-work" }
  ],
  "threshold": 95
}
```

- `label` is the name you use with `ccuse` and the name shown in the status line.
- `configDir` is the credential directory. `~/.claude` is the default account. For
  the other accounts it is a separate directory that only holds the credential.
- `threshold` is the usage percentage that triggers the warning. The default is 95.
- An account can also have `keychainService` to force the name of the Keychain
  entry, if the derived name does not match.

### Add an account

Use `bin/cc-new-account.sh`. It creates the directory, adds the account to
`accounts.json` (and keeps a backup of the old file), and checks the Keychain. It is
safe to run more than once.

```bash
bin/cc-new-account.sh work                 # credential dir: ~/.claude-work
bin/cc-new-account.sh work ~/other/dir     # explicit credential dir
bin/cc-new-account.sh --check work         # only checks, does not write anything
```

If there is no credential yet, the script prints the login command. You have to run
it yourself, in a real terminal and not inside Claude Code:

```bash
CLAUDE_SECURESTORAGE_CONFIG_DIR="$HOME/.claude-work" claude    # then /login and /exit
```

Do not use `CLAUDE_CONFIG_DIR` to log in. If you log in with the wrong variable, you
can overwrite the credential of another account without any warning.

If you used one `CLAUDE_CONFIG_DIR` per account before, you do not need to log in
again. The Keychain entry is derived from the same string, so the same directory path
points to the same credential. Do not rename those directories, or the credential
will stop resolving.

## Status line

The status line shows everything in one row:

```
work · feature/login · 3 uncommitted · 1a2b3c4d · Opus 5 · xhigh · $1.42 · ctx 19% · 5h 12% ↻23:50 · 7d 44% ↻06/07 05:00
```

From left to right:

- The account label. It comes from the credential of the session, not from the config
  directory.
- A git segment, only inside a repository: the branch, `worktree` if it is a linked
  worktree, the number of uncommitted files, the number of unpushed commits, and
  `no upstream` if the branch has no upstream. On `main` or `master` the segment is
  shown in red with the word `PRODUCTION`.
- The pull request of the branch and its CI status, if `gh` is installed and the
  branch is pushed (not on `main` or `master`). The data comes from `gh pr view`, which runs in the background
  and is cached for 2 minutes in `state/`, so the status line never waits for the
  network.
- The first 8 characters of the session id, linked to the transcript file.
- The model, the effort level and the session cost.
- The context window usage.
- The 5 hour and 7 day usage, each with the time it resets.

Percentages are green below 75%, yellow from 75%, and red from the threshold. When
the 5 hour or the 7 day usage reaches the threshold, the line adds a red warning:
`⚠️  95%: switch account with ccswitch`.

The status line also saves the last usage of each account in `state/`. The `Stop`
hook (`bin/stop-notify.sh`) reads that file when a turn ends. If the current account
is over the threshold, it shows a message that suggests `ccswitch`. It does not call
the API. It ignores readings older than 10 minutes (`CCM_NOTIFY_FRESH`) and does not
repeat the warning within 5 minutes (`CCM_NOTIFY_COOLDOWN`).

## How it works

Claude Code reads its credential from the macOS Keychain. The name of the Keychain
entry is derived from the exact string in `CLAUDE_SECURESTORAGE_CONFIG_DIR`: it is
`Claude Code-credentials` followed by `-` and the first 8 characters of the SHA-256 of
that string. When the variable is empty, there is no suffix. When the variable is not
set, Claude Code uses `CLAUDE_CONFIG_DIR` instead.

So each extra account has an almost empty directory, for example `~/.claude-work`.
Its only job is to be a stable string that points to one Keychain entry. When you run
`ccuse work`, the tool starts Claude Code like this, inside a subshell:

```bash
unset CLAUDE_CONFIG_DIR
CLAUDE_SECURESTORAGE_CONFIG_DIR=~/.claude-work claude
```

The default account (`~/.claude`) is started with the variable set to an empty
string, not unset. An empty value selects the default credential even if
`CLAUDE_CONFIG_DIR` is exported in your shell.

Usage numbers come from two places:

- While a session runs, Claude Code passes `rate_limits.*.used_percentage` to the
  status line command. These values come from the API responses, so they belong to
  the credential of that session.
- Before a session starts, `bin/cc-usage.sh` calls
  `GET https://api.anthropic.com/api/oauth/usage` with the token of each account,
  which it reads from the Keychain. This is how `ccx` and `ccswitch` choose an
  account.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `CCM_HOME` | `~/projects/claude-multi-account` | Where the repository is. |
| `CCM_ACCOUNTS_FILE` | `$CCM_HOME/accounts.json` | The accounts file. |
| `CCM_BASE_DIR` | `~/.claude` | The default config directory. `cc-new-account.sh` refuses to add it as a new account. |
| `CCM_STATE_DIR` | `<repo>/state` | Where the usage and pull request caches are saved. |
| `CCM_TMUX` | not set | `1` runs Claude Code inside tmux. |
| `CCM_NO_CONTINUE` | not set | `1` makes `ccswitch` open a new session. |
| `CCM_NOTIFY_COOLDOWN` | `300` | Seconds between two warnings from the `Stop` hook. |
| `CCM_NOTIFY_FRESH` | `600` | Maximum age, in seconds, of a usage reading for the hook. |
| `CCM_DRY_RUN` | not set | Print the launch command instead of running it. |
| `CCM_USAGE_CMD` | `bin/cc-usage.sh` | The command that returns the usage of an account. The tests and the demo replace it. |
| `CCM_PICK_CMD` | `bin/cc-pick.sh` | The command that picks an account for `ccx` and `ccswitch`. |
| `CCM_DUMP_INPUT` | not set | A file where the status line writes the JSON it receives, for debugging. |

## Tests

The tests use [bats-core](https://github.com/bats-core/bats-core). They use stubs and
temporary directories, so they do not touch your real accounts or Keychain entries.

```bash
bats test/
```

## License

MIT. See [LICENSE](LICENSE).
