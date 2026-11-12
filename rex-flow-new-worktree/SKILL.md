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
| Agent | Same as the coordinator (`pi` or `opencode`) in the left pane, task submitted with `--task`; plain shell without it |

## Workflow

1. Derive a short slug from the user's task: lowercase, hyphens, no spaces, no slashes. Example: task "add login redirect" → `add-login-redirect`.
2. Confirm the project is a git repository. Run the script from anywhere inside it; `--target` defaults to `master`.
3. Identify your current harness (Pi or OpenCode) and pass it explicitly as `--agent pi` or `--agent opencode`. Run the script with the user's task passed verbatim through `--task`:

```bash
/path/to/rex-flow-new-worktree/scripts/new-worktree.sh <slug> --agent <current-agent> --task "<user's task>" --json
```

4. Read the JSON and report the worktree path, branch, base ref, and Rex window. The new window opens the coordinator’s agent in the left pane, submits the task as its first prompt, and splits a shell terminal on the right. Without `--task` the window is a single plain shell.

Use `--no-terminal` when the user wants only the agent pane.

Non-negotiable: the script is the only way to create the worktree. It refuses existing branches, existing paths, invalid slugs, missing target branches, missing Rex sessions, and missing selected agent when `--task` is used, so surface its error instead of retrying blindly.

Do not do the task in the coordinator session. The work runs in the new window's matching agent. Coordinator only creates, reports, and stays available.

## Agent selection

Match the coordinator agent: when running in Pi, pass `--agent pi`; when running in OpenCode, pass `--agent opencode`. Never choose a fixed default or infer the harness from the model provider. The script's `--agent auto` default also checks the process ancestry and Pi/generic agent markers, but explicit selection by the coordinator avoids ambiguous inherited environments. If the harness is unsupported or cannot be identified, stop and report that rather than launching a different agent. Currently supported launchers are Pi and OpenCode.

The spawned agent starts a fresh session, not a copy of the coordinator conversation. Pi model selection remains optional via `--provider <provider> --model <model-id>`; `--auto` is OpenCode-only.

## Examples

From a Pi coordinator (use `--agent opencode` from OpenCode):

```bash
scripts/new-worktree.sh add-login-redirect --agent pi --task "Add a login redirect after auth and cover it with a test" --json
```

Explicit target branch:

```bash
scripts/new-worktree.sh fix-auth-cookie --target develop --task "Fix the expired auth cookie path" --json
```

Use OpenCode with auto-approved permissions:

```bash
scripts/new-worktree.sh billing-retry --agent opencode --fetch --auto --task "Retry billing webhooks on 5xx" --json
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
- With `--task`, the selected agent submits the prompt itself. Do not `rex send` the task again.
- The terminal pane is a shell in the worktree, split right and focused away from the agent. Use `terminal_block_id` from the JSON to capture or target it.
- To check progress, capture the returned `block_id`:
  `rex capture -s <session_id> -b <block_id> --trim`
- A branch already named `rex/<slug>` means the work exists: report it and ask whether to open the existing worktree instead of creating a duplicate.
- To remove a worktree later: `git worktree remove <path>` from the main checkout, then delete the branch with `git branch -D rex/<slug>` if it is merged.

## Requirements

- git
- rex, unless `--no-window`
- pi or opencode, matching the coordinator, when `--task` is used
- jq, for `--json` output and Rex window IDs

