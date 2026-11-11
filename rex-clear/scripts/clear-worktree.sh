#!/usr/bin/env bash
# Delete the rex-flow worktree and branch behind a Rex tab, then close the tab.
set -euo pipefail

root=${REX_FLOW_WORKTREE_ROOT:-$HOME/.local/share/rex}
path=
slug=
window=
session=${REX_SESSION:-}
close_window=1
delay=3
force=1
dry_run=0
json=0

die() {
  printf 'clear-worktree: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: clear-worktree.sh [options]

Delete the worktree under <root>/<project>/<slug> and its rex/<slug> branch,
then close the Rex tab that owns it.

With no options, resolves the worktree from the current shell, falling back to
the working directory of the blocks in this tab ($REX_BLOCK).

Options:
  --path PATH          Worktree to delete
  --slug SLUG          Worktree name, as passed to new-worktree.sh
  --window WINDOW_ID   Rex tab to inspect and close
  --session SESSION_ID Rex session for --window (default: $REX_SESSION)
  --keep-window        Leave the tab open
  --delay SECONDS      Wait before closing this tab (default: 3)
  --no-force           Refuse when the worktree has uncommitted changes
  --dry-run            Print what would be deleted, delete nothing
  --json               Print one JSON object instead of plain lines
  -h, --help           Show this help

Environment:
  REX_FLOW_WORKTREE_ROOT   Override the worktree root (default ~/.local/share/rex)
  REX_SESSION              Rex session for the tab (default: rex whoami)
  REX_BLOCK                Block whose tab is cleared when no target is given
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --path) [ $# -ge 2 ] || die "--path needs a value"; path=$2; shift 2 ;;
    --path=*) path=${1#*=}; shift ;;
    --slug) [ $# -ge 2 ] || die "--slug needs a value"; slug=$2; shift 2 ;;
    --slug=*) slug=${1#*=}; shift ;;
    --window) [ $# -ge 2 ] || die "--window needs an id"; window=$2; shift 2 ;;
    --window=*) window=${1#*=}; shift ;;
    --session) [ $# -ge 2 ] || die "--session needs an id"; session=$2; shift 2 ;;
    --session=*) session=${1#*=}; shift ;;
    --keep-window) close_window=0; shift ;;
    --delay) [ $# -ge 2 ] || die "--delay needs seconds"; delay=$2; shift 2 ;;
    --delay=*) delay=${1#*=}; shift ;;
    --no-force) force=0; shift ;;
    --dry-run) dry_run=1; shift ;;
    --json) json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done

case $delay in ''|*[!0-9]*) die "--delay must be a whole number of seconds" ;; esac
# Compare real paths so /var and /private/var (macOS) never disagree.
[ -d "$root" ] && root=$(cd "$root" && pwd -P)
[ -n "$path" ] || [ -n "$slug" ] || [ -n "$window" ] || [ -n "${REX_BLOCK:-}" ] || [ -n "$session" ] ||
  die "no target: pass --path, --slug, or --window"

is_under_root() {
  case $1 in "$root"/*) return 0 ;; *) return 1 ;; esac
}

main_root_of() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$common"
}

top_of() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || true
}

# Resolve a session only when the tab id is needed.
resolve_session() {
  [ -n "$session" ] && return 0
  command -v rex >/dev/null || die "rex not found; pass --path to clear without a tab"
  session=$(rex whoami --json 2>/dev/null | jq -er '.session_id') ||
    die "cannot determine Rex session; pass --session"
}

own_window() {
  [ -n "${REX_BLOCK:-}" ] || return 1
  rex block inspect "$REX_BLOCK" --json 2>/dev/null | jq -er '.block.window_id' 2>/dev/null
}

window_exists() {
  rex session inspect "$session" --json 2>/dev/null |
    jq -e --arg w "$1" 'any(.windows[]; .window_id == $w)' >/dev/null 2>&1
}

window_owning_path() {
  local windows w cwd top
  windows=$(rex session inspect "$session" --json 2>/dev/null | jq -r '.windows[].window_id') || return 1
  for w in $windows; do
    for cwd in $(window_block_cwds "$w"); do
      top=$(top_of "$cwd")
      if [ -n "$top" ] && [ "$top" = "$1" ]; then
        printf '%s' "$w"
        return 0
      fi
    done
  done
  return 1
}

window_block_cwds() {
  local blocks block cwd
  blocks=$(rex session inspect "$session" --json 2>/dev/null |
    jq -r --arg w "$1" '.windows[] | select(.window_id == $w) | .layers[].blocks[].block_id') || return 0
  for block in $blocks; do
    cwd=$(rex block call -s "$session" -b "$block" process 2>/dev/null |
      jq -r '.foreground.cwd // .child.cwd // empty' 2>/dev/null) || cwd=
    [ -n "$cwd" ] && printf '%s\n' "$cwd"
  done
  return 0
}

# 1. Explicit path.
if [ -n "$path" ]; then
  path=$(cd "$path" 2>/dev/null && pwd -P) || die "path not found: $path"
fi
# 2. Explicit slug: locate the single worktree with that name.
if [ -z "$path" ] && [ -n "$slug" ]; then
  matches=
  count=0
  for candidate in "$root"/*/"$slug"; do
    [ -d "$candidate" ] || continue
    matches=$candidate
    count=$((count + 1))
  done
  case $count in
    0) die "no worktree named '$slug' under $root" ;;
    1) path=$matches ;;
    *) die "'$slug' matches $count worktrees under $root; pass --path" ;;
  esac
fi

# 3. The current directory, when it sits inside a rex-flow worktree.
if [ -z "$path" ]; then
  here=$(top_of "$PWD")
  if [ -n "$here" ] && is_under_root "$here"; then
    path=$here
  fi
fi

# 4. The tab's blocks, so the agent's own tab works from any subdirectory.
if [ -z "$path" ]; then
  resolve_session
  [ -n "$window" ] || window=$(own_window) || die "cannot tell which Rex tab to clear; pass --window or --path"
  window_exists "$window" || die "tab not found in $session: $window"
  for cwd in $(window_block_cwds "$window"); do
    top=$(top_of "$cwd")
    if [ -n "$top" ] && is_under_root "$top"; then
      path=$top
      break
    fi
  done
  [ -n "$path" ] || die "no rex-flow worktree is open in tab $window; pass --path"
fi

# Validate the target before touching anything.
[ -d "$path" ] || die "path not found: $path"
path=$(cd "$path" && pwd -P) || die "path not found: $path"
[ "$path" != "$root" ] && is_under_root "$path" || die "refusing path outside $root: $path"

top=$(top_of "$path")
[ -n "$top" ] || die "not a git worktree: $path"
[ "$top" = "$path" ] || die "$path is not a worktree root (it is inside $top)"

main=$(main_root_of "$path") || die "cannot find the main checkout for $path"
[ -n "$main" ] && [ "$main" != "$path" ] || die "refusing to remove the main checkout: $path"

git -C "$main" worktree list --porcelain 2>/dev/null | grep -Fxq "worktree $path" ||
  die "$path is not a registered worktree of $main"

branch=$(git -C "$path" symbolic-ref --short -q HEAD) || die "worktree is on a detached HEAD: $path"
case $branch in
  rex/*) ;;
  *) die "refusing branch outside rex/: $branch" ;;
esac
[ -n "$slug" ] || slug=${branch#rex/}

cd "$main"
dirty=$(git -C "$path" status --porcelain 2>/dev/null || true)
if [ -n "$dirty" ] && [ "$force" -eq 0 ]; then
  die "worktree has uncommitted changes; rerun with --force (default) to discard them"
fi

# Resolve the tab before deleting, while its blocks still answer.
if [ "$close_window" -eq 1 ]; then
  close_state=no-tab
  if [ -z "$window" ] && [ -n "${REX_BLOCK:-}" ] && command -v rex >/dev/null; then
    resolve_session
    window=$(window_owning_path "$path") || window=
  fi
  if [ -n "$window" ]; then
    resolve_session
    window_exists "$window" || die "tab not found in $session: $window"
    if [ "$dry_run" -eq 1 ]; then
      close_state=would-close
    elif [ "$window" = "$(own_window 2>/dev/null || true)" ]; then
      close_state=pending
    else
      close_state=closing
    fi
  fi
else
  close_state=kept
fi

if [ "$dry_run" -eq 1 ]; then
  removed=0
  branch_deleted=0
else
  git -C "$main" worktree remove --force "$path" >&2 ||
    die "git worktree remove failed for $path"
  removed=1
  if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$main" branch -D "$branch" >&2
    branch_deleted=1
  else
    branch_deleted=0
  fi
  git -C "$main" worktree prune >&2 || true
  project_dir=$(dirname "$path")
  rmdir "$project_dir" 2>/dev/null || true
fi

# Close the tab last. Closing this tab must not kill the cleanup, so detach.
if [ "$close_state" = closing ]; then
  rex window close -s "$session" "$window" >/dev/null 2>&1 ||
    die "worktree cleared but closing tab $window failed"
  close_state=closed
elif [ "$close_state" = pending ]; then
  log=${TMPDIR:-/tmp}/rex-clear-${slug:-worktree}.log
  nohup bash -c 'sleep "$1"; rex window close -s "$2" "$3" >"$4" 2>&1' \
    rex-clear "$delay" "$session" "$window" "$log" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

if [ "$json" -eq 1 ]; then
  jq -n \
    --arg project "$(basename "$main")" \
    --arg slug "$slug" \
    --arg branch "$branch" \
    --arg path "$path" \
    --arg main "$main" \
    --arg session "$session" \
    --arg window "$window" \
    --arg close "$close_state" \
    --argjson removed "$removed" \
    --argjson branch_deleted "$branch_deleted" \
    --argjson dirty "$([ -n "$dirty" ] && echo true || echo false)" \
    --argjson dry_run "$dry_run" \
    '{project: $project, slug: $slug, branch: $branch, path: $path, main: $main, dirty: $dirty, removed: ($removed == 1), branch_deleted: ($branch_deleted == 1), dry_run: ($dry_run == 1), tab: $close}
     + (if $window == "" then {} else {session_id: $session, window_id: $window} end)'
else
  printf 'project: %s\n' "$(basename "$main")"
  printf 'branch:  %s\n' "$branch"
  printf 'path:    %s\n' "$path"
  if [ "$dry_run" -eq 1 ]; then
    printf 'action:  would remove the worktree and force-delete %s\n' "$branch"
  else
    printf 'action:  removed the worktree and force-deleted %s\n' "$branch"
  fi
  if [ -n "$dirty" ] && [ "$removed" -eq 1 ]; then
    printf 'discard: uncommitted changes dropped\n'
  fi
  case $close_state in
    closed) printf 'tab:     closed %s\n' "$window" ;;
    pending) printf 'tab:     closing %s in %ss\n' "$window" "$delay" ;;
    would-close) printf 'tab:     would close %s\n' "$window" ;;
    kept) printf 'tab:     left open (--keep-window)\n' ;;
    no-tab) printf 'tab:     no tab owns this worktree; left open\n' ;;
  esac
fi
