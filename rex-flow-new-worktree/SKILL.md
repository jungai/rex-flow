---
name: rex-flow-new-worktree
description: Create an isolated git worktree for a repository and open a Rex window in it. Human-invoked only, load with @rex-flow-new-worktree. Creates project/slug folders under ~/.local/share/rex with branch rex/slug by default.
disable-model-invocation: true
metadata:
  opencode/autoinvoke: false
---

# Rex Flow: New Worktree

Human-invoked skill. The model does not see it unless the user mentions `@rex-flow-new-worktree`.

One command creates the worktree, the branch, and the Rex window. Defaults:

| Setting | Value |
| --- | --- |
| Target branch | `master`, falling back to `main` |
| Branch | `rex/<slug>` |
| Path | `~/.local/share/rex/<project>/<slug>` |
| Window | New window in the current Rex session (`$REX_SESSION`) |
| Layout | Agent on the left, shell terminal split on the right (50/50) |
| Agent | `opencode` in the left pane, task submitted with `--task`; plain shell without it |

## Workflow

1. Derive a short slug from the user's task: lowercase, hyphens, no spaces, no slashes. Example: task "add login redirect" → `add-login-redirect`.
2. Confirm the project is a git repository. Run the script from anywhere inside it; `--target` defaults to `master`.
3. Run the script with the user's task passed verbatim through `--task`:

```bash
/path/to/rex-flow-new-worktree/scripts/new-worktree.sh <slug> --task "<user's task>" --json
```

4. Read the JSON and report the worktree path, branch, base ref, and Rex window. The new window opens `opencode` in the left pane, submits the task as its first prompt, and splits a shell terminal on the right. Without `--task` the window is a single plain shell.

Use `--no-terminal` when the user wants only the agent pane.

Non-negotiable: the script is the only way to create the worktree. It refuses existing branches, existing paths, invalid slugs, missing target branches, missing Rex sessions, and missing `opencode` when `--task` is used, so surface its error instead of retrying blindly.

Do not do the task in the coordinator session. The work runs in the new window's opencode. Coordinator only creates, reports, and stays available.

## Examples

Default, from master, hand the task to a new opencode:

```bash
scripts/new-worktree.sh add-login-redirect --task "Add a login redirect after auth and cover it with a test" --json
```

Explicit target branch:

```bash
scripts/new-worktree.sh fix-auth-cookie --target develop --task "Fix the expired auth cookie path" --json
```

Auto-approve opencode permissions for unattended work:

```bash
scripts/new-worktree.sh billing-retry --fetch --auto --task "Retry billing webhooks on 5xx" --json
```

Agent pane only, no terminal split:

```bash
scripts/new-worktree.sh solo-agent --no-terminal --task "Add structured logging" --json
```

Long task from a file:

```bash
scripts/new-worktree.sh spike-vector-search --task-file /tmp/task.md
```

Worktree only, plain shell, no agent:

```bash
scripts/new-worktree.sh scratch-spike --no-window
```

Custom window title:

```bash
scripts/new-worktree.sh refactor-router --title "Router refactor" --task "Refactor route registration" --json
```

## After creation

- Work happens in the returned `path`; never reuse the original checkout.
- With `--task`, opencode submits the prompt itself. Do not `rex send` the task again.
- The terminal pane is a shell in the worktree, split right and focused away from the agent. Use `terminal_block_id` from the JSON to capture or target it.
- To check progress, capture the returned `block_id`:
  `rex capture -s <session_id> -b <block_id> --trim`
- A branch already named `rex/<slug>` means the work exists: report it and ask whether to open the existing worktree instead of creating a duplicate.
- To remove a worktree later: `git worktree remove <path>` from the main checkout, then delete the branch with `git branch -D rex/<slug>` if it is merged.

## Requirements

- git
- rex, unless `--no-window`
- opencode, when `--task` is used
- jq, for `--json` output and Rex window IDs

