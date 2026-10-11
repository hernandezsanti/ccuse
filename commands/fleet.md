---
description: Background sessions of ALL Claude Code accounts (what the esc panel cannot show). Optional: --all to include finished ones.
allowed-tools: Bash(~/projects/claude-multi-account/bin/cc-fleet.sh:*)
---

Background sessions of all accounts right now:

```
!`~/projects/claude-multi-account/bin/cc-fleet.sh $ARGUMENTS`
```

Show the table as it is, without summarizing or reordering it. If there are rows marked
`·dead` with state `working`, point them out separately: they are stuck jobs (they say they
are working, but their process no longer exists). Do nothing else unless you are asked to.
