---
name: rex-clear
description: Delete the rex-flow worktree and its rex branch behind a Rex tab, then close that tab. Human-invoked only, load with @rex-clear. Mirrors rex-flow-new-worktree.
disable-model-invocation: true
metadata:
  opencode/autoinvoke: false
---

# Rex Flow: Clear

Human-invoked skill. The model does not see it unless the user mentions `@rex-clear`.

One command removes the worktree created by `new-worktree.sh`, force-deletes its
`rex/<slug>` branch, and closes the Rex tab that owns it. **Closing the tab is the
default**; pass `--keep-window` to leave it open.

The owning tab is found by matching the worktree path against the working
directory of every block in the session, so the skill works from any tab. When
the target is the tab the agent runs in, the script detaches the close and waits
`--delay` seconds: answer in one line, because the tab can vanish with the reply.

## Workflow

1. Run the script, usually from the tab being cleared, with no arguments:

```bash
/path/to/rex-clear/scripts/clear-worktree.sh --json
```

2. Report the JSON: project, branch, path, the `tab` state, and `branch_deleted`.
3. Never pass safety overrides on your own. Uncommitted changes are discarded by
   default; surface `--no-force` only when the user asks to be careful.

Target resolution, in order:

| Source | When |
| --- | --- |
| `--path` | User names a worktree path |
| `--slug` | User names the worktree or window label |
| Current directory | Script runs inside `~/.local/share/rex/<project>/<slug>` |
| This tab | Working directory of the blocks in `$REX_BLOCK`'s window |

A resolved target must be a registered linked worktree under
`~/.local/share/rex`, with a `rex/*` branch, in a non-primary checkout. Anything
else is a hard error, never a guess.

## Commands the script runs

```bash
git -C <main> worktree remove --force <path>
git -C <main> branch -D rex/<slug>
git -C <main> worktree prune
rex window close -s <session> <window>
```

The last one is skipped with `--keep-window`, and deferred for the agent's own
tab so the command can finish. Auto-close only applies when the script runs inside
a Rex tab (`$REX_BLOCK` set); with no owning tab it reports `tab: no-tab`.

## Examples

Clear the worktree of the tab you are in, then close it:

```bash
scripts/clear-worktree.sh --json
```

Preview without deleting:

```bash
scripts/clear-worktree.sh --slug add-login-redirect --dry-run --json
```

Remove the worktree but keep the tab open:

```bash
scripts/clear-worktree.sh --path ~/.local/share/rex/app/add-login-redirect --keep-window
```

Refuse to touch uncommitted work:

```bash
scripts/clear-worktree.sh --slug add-login-redirect --no-force
```

Give the tab a moment before it closes:

```bash
scripts/clear-worktree.sh --delay 10 --json
```

## Safety

- The branch is always force-deleted. Unmerged commits are lost; say so before
  running when the user might still need them.
- Uncommitted changes are discarded by default. `--no-force` makes the script
  stop and report instead.
- Refuses paths outside `~/.local/share/rex`, the primary checkout, non-`rex/*`
  branches, and paths git does not list as worktrees of that repository.
- `--window` closes that tab even when it does not own the worktree; it also
  deletes the worktree. Confirm both when the user named a tab.
- The empty `<project>` folder is removed; the worktree root itself is left.

## Requirements

- git
- rex, unless `--keep-window` is used and no target needs the tab
- jq, for resolving tabs and for `--json` output
