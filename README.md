# rex-flow

Two [agent skills](https://skills.sh) that turn a git repository into isolated Rex
tabs — one worktree, one branch, one tab per task — and clean them up afterwards.

Both skills are human-invoked (`disable-model-invocation: true`). The agent only loads
them when you ask for `@rex-flow-new-worktree` or `@rex-clear`.

| Skill | What it does | Invoke |
| --- | --- | --- |
| [`rex-flow-new-worktree`](#rex-flow-new-worktree) | Creates a git worktree, a `rex/<slug>` branch, and a Rex tab running `pi` on your task | `@rex-flow-new-worktree` |
| [`rex-clear`](#rex-clear) | Deletes that worktree, force-deletes its branch, and closes its tab | `@rex-clear` |

```
@rex-flow-new-worktree "add login redirect"
        │
        ├─ git worktree add -b rex/add-login-redirect  ~/.local/share/rex/<project>/add-login-redirect
        └─ rex window new ... pi -- "add login redirect"
                    │
                    ▼   work happens in the new tab, not the coordinator tab
@rex-clear
        ├─ git worktree remove --force <path>
        ├─ git branch -D rex/add-login-redirect
        └─ rex window close <tab>
```

## Installation

Requires Node.js 22.20+ for the CLI.

```bash
npx skills add jungai/rex-flow
```

The interactive picker lets you choose skills, agents (OpenCode, Claude Code, Codex, …),
and scope. Skills install into the current project by default.

List what the repo provides without installing:

```bash
npx skills add jungai/rex-flow --list
```

Install non-interactively:

```bash
# one skill, into OpenCode, project scope
npx skills add jungai/rex-flow --skill rex-flow-new-worktree -a opencode -y

# both skills, all detected agents
npx skills add jungai/rex-flow --all

# both skills, globally (~/<agent>/skills)
npx skills add jungai/rex-flow --all -g
```

Install from a local checkout instead of GitHub:

```bash
npx skills add ./
```

Maintain the install:

```bash
npx skills list
npx skills update rex-flow-new-worktree rex-clear
npx skills remove rex-clear
```

The repository is private, so the CLI reuses your existing git credentials (git
credential helper → GitHub CLI → SSH) to clone it.

## Skill map

```
rex-flow/
├── rex-flow-new-worktree/
│   ├── SKILL.md                  @rex-flow-new-worktree
│   └── scripts/
│       └── new-worktree.sh       entry point: create worktree + branch + tab
└── rex-clear/
    ├── SKILL.md                  @rex-clear
    └── scripts/
        └── clear-worktree.sh     entry point: remove worktree + branch + tab
```

Each skill is a directory with a `SKILL.md` plus the script it drives. The scripts are
plain bash and work on their own without an agent:

```bash
rex-flow-new-worktree/scripts/new-worktree.sh --help
rex-clear/scripts/clear-worktree.sh --help
```

## rex-flow-new-worktree

Creates an isolated worktree for the repository you are in and opens a Rex tab there.
Default settings:

| Setting | Value |
| --- | --- |
| Target branch | `master`, falling back to `main` |
| Branch | `rex/<slug>` |
| Worktree path | `~/.local/share/rex/<project>/<slug>` |
| Tab | New window in the current Rex session (`$REX_SESSION`) |
| Agent | Same as the coordinator (`pi` or `opencode`), task submitted as the first prompt with `--task`; plain shell without it |

The new window uses the coordinator's agent: Pi → Pi, OpenCode → OpenCode. No fixed agent default.

### Options

| Option | Description |
| --- | --- |
| `SLUG` | Worktree name and branch suffix. Letters, digits, `.`, `_`, `-` |
| `--target BRANCH` | Base ref instead of `master`/`main` |
| `--title TITLE` | Rex tab title (default: the slug) |
| `--agent NAME` | `auto` (default, match coordinator), `pi`, or `opencode` |
| `--provider NAME` | Pi provider; requires `--model` |
| `--model ID` | Pi model, to match the coordinator explicitly |
| `--task TEXT` | Start `pi` in the tab and submit `TEXT` |
| `--task-file PATH` | Read the task prompt from a file |
| `--auto` | OpenCode only: pass `--auto` (approve permissions) |
| `--no-window` | Create the worktree only |
| `--fetch` | `git fetch --prune origin` before branching |
| `--json` | Print one JSON object |

### Agent selection

Match the coordinator agent: when running in Pi, pass `--agent pi`; when running in OpenCode, pass `--agent opencode`. Never choose a fixed default or infer the harness from the model provider. The script's `--agent auto` default also checks the process ancestry and Pi/generic agent markers, but explicit selection by the coordinator avoids ambiguous inherited environments. If the harness is unsupported or cannot be identified, stop and report that rather than launching a different agent. Currently supported launchers are Pi and OpenCode.

The spawned agent starts a fresh session, not a copy of the coordinator conversation. Pi model selection remains optional via `--provider <provider> --model <model-id>`; `--auto` is OpenCode-only.

### Examples

```bash
# default: branch from master, hand the task to Pi in a new tab
scripts/new-worktree.sh add-login-redirect \
  --task "Add a login redirect after auth and cover it with a test" --json

# explicit base branch
scripts/new-worktree.sh fix-auth-cookie --target develop --task "Fix the expired auth cookie path"

# OpenCode, unattended
scripts/new-worktree.sh billing-retry --agent opencode --fetch --auto --task "Retry billing webhooks on 5xx"

# worktree only, no tab
scripts/new-worktree.sh scratch-spike --no-window
```

### JSON output

```json
{
  "project": "app",
  "slug": "add-login-redirect",
  "branch": "rex/add-login-redirect",
  "target": "master",
  "path": "/Users/me/.local/share/rex/app/add-login-redirect",
  "session_id": "…",
  "window_id": "…",
  "block_id": "…",
  "agent": "pi",
  "task": "Add a login redirect after auth and cover it with a test"
}
```

`session_id`, `window_id`, and `block_id` appear only when a tab was opened.
`agent` and `task` appear only when `--task`/`--task-file` was used.
Check progress with `rex capture -s <session_id> -b <block_id> --trim`.

### Guards

The script refuses existing branches, existing paths, invalid slugs, missing target
branches, missing Rex sessions, and a missing selected agent when `--task` is used. It
surfaces the error instead of retrying. Work always happens in the new worktree; the
coordinator tab only creates and reports.

## rex-clear

Removes the worktree created by `new-worktree.sh`, force-deletes its `rex/<slug>`
branch, and closes the tab that owns it. Closing the tab is the default; pass
`--keep-window` to leave it open.

### Target resolution

First match wins:

| Source | When |
| --- | --- |
| `--path` | You name a worktree path |
| `--slug` | You name the worktree or tab label |
| Current directory | The script runs inside `~/.local/share/rex/<project>/<slug>` |
| This tab | Working directory of the blocks in `$REX_BLOCK`'s window |

A resolved target must be a registered linked worktree under `~/.local/share/rex`,
checked out on a `rex/*` branch, and not the primary checkout. Anything else is a hard
error, never a guess.

### Options

| Option | Description |
| --- | --- |
| `--path PATH` | Worktree to delete |
| `--slug SLUG` | Worktree name, as passed to `new-worktree.sh` |
| `--window WINDOW_ID` | Rex tab to inspect and close |
| `--session SESSION_ID` | Rex session for `--window` (default: `$REX_SESSION`) |
| `--keep-window` | Leave the tab open |
| `--delay SECONDS` | Wait before closing the agent's own tab (default: 3) |
| `--no-force` | Refuse when the worktree has uncommitted changes |
| `--dry-run` | Print what would be deleted, delete nothing |
| `--json` | Print one JSON object |

### Examples

```bash
# clear the worktree of the tab you are in, then close it
scripts/clear-worktree.sh --json

# preview
scripts/clear-worktree.sh --slug add-login-redirect --dry-run --json

# remove the worktree but keep the tab
scripts/clear-worktree.sh --path ~/.local/share/rex/app/add-login-redirect --keep-window

# refuse to touch uncommitted work
scripts/clear-worktree.sh --slug add-login-redirect --no-force
```

### JSON output

```json
{
  "project": "app",
  "slug": "add-login-redirect",
  "branch": "rex/add-login-redirect",
  "path": "/Users/me/.local/share/rex/app/add-login-redirect",
  "main": "/Users/me/src/app",
  "dirty": false,
  "removed": true,
  "branch_deleted": true,
  "dry_run": false,
  "tab": "closed",
  "session_id": "…",
  "window_id": "…"
}
```

`tab` is one of `closed`, `pending` (this tab closes after `--delay`), `would-close`
(`--dry-run`), `kept` (`--keep-window`), or `no-tab` (no Rex tab owns the worktree).

### Safety

- The branch is always force-deleted. Unmerged commits are lost.
- Uncommitted changes are discarded by default; `--no-force` stops instead.
- Refuses paths outside `~/.local/share/rex`, the primary checkout, non-`rex/*`
  branches, and paths git does not list as worktrees of that repository.
- When the cleared worktree lives in the agent's own tab, the close is detached and
  delayed so the reply can finish first.

## Requirements

| Tool | Needed by |
| --- | --- |
| Node.js 22.20+ | `npx skills` |
| git | both scripts |
| rex | opening/closing tabs (`--no-window`/`--keep-window` aside) |
| jq | `--json` output and tab resolution |
| pi or opencode (same as coordinator) | `new-worktree.sh --task` |

## Environment

| Variable | Used by | Meaning |
| --- | --- | --- |
| `REX_FLOW_WORKTREE_ROOT` | both | Worktree root (default `~/.local/share/rex`) |
| `REX_SESSION` | both | Rex session for new/closed tabs |
| `REX_BLOCK` | `rex-clear` | Block whose tab is cleared when no target is given |
