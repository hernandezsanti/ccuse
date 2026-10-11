# Demo

`demo.gif` is a real terminal session recorded with [VHS](https://github.com/charmbracelet/vhs)
from `demo.tape`. It does not use real accounts:

- `demo-setup.sh` sets `HOME` to a temporary directory (`/tmp/ccm-demo` by default,
  or `CCM_DEMO_HOME`) with three fake accounts and a small git repository.
- `security`, `curl`, `gh` and `claude` are stubs, so nothing reads the Keychain or
  calls the API.
- Usage numbers come from a stub script set in `CCM_USAGE_CMD`.
- `CCM_DRY_RUN=1` makes `ccuse`, `ccx` and `ccswitch` print the launch command
  instead of starting Claude Code.

## Regenerate it

Install VHS (it needs `ttyd` and `ffmpeg`), then run this from the repository root:

```bash
brew install vhs
vhs docs/demo.tape
rm -rf /tmp/ccm-demo
```

The tape uses bash, a 1200 x 400 window and font size 14, so the status line fits in
one row. If you change what the status line shows, check that it still fits.

To try the same setup by hand, run `source docs/demo-setup.sh` from the repository
root in a new bash shell. It changes `HOME` and `PATH` in that shell, so close the
shell when you are done.
