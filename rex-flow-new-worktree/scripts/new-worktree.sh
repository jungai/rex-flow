#!/usr/bin/env bash
# Create a git worktree for the current repository under ~/.local/share/rex,
# then open a Rex window in that worktree.
set -euo pipefail

root=${REX_FLOW_WORKTREE_ROOT:-$HOME/.local/share/rex}
target=
target_explicit=0
slug=
title=
task=
task_file=
auto=0
open_window=1
json=0
fetch=0

die() {
  printf 'new-worktree: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: new-worktree.sh SLUG [options]

Create <root>/<project>/<slug> from a target branch and open a Rex window there.

Arguments:
  SLUG                 Worktree name, also the branch suffix. Letters, digits,
                       dots, underscores, hyphens. Example: add-login-redirect

Options:
  --target BRANCH      Branch or ref to base on (default: master, then main)
  --title TITLE        Rex window title (default: SLUG)
  --task TEXT          Start opencode in the new window and submit TEXT as its
                       first prompt
  --task-file PATH     Read the task prompt from PATH
  --auto               Pass --auto to opencode (approve permissions)
  --no-window          Create the worktree without opening a Rex window
  --fetch              Run git fetch --prune origin before creating
  --json               Print one JSON object instead of plain lines
  -h, --help           Show this help

Environment:
  REX_FLOW_WORKTREE_ROOT   Override the worktree root (default ~/.local/share/rex)
  REX_SESSION              Rex session for the new window (default: rex whoami)
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --target) [ $# -ge 2 ] || die "--target needs a branch"; target=$2; target_explicit=1; shift 2 ;;
    --target=*) target=${1#*=}; target_explicit=1; shift ;;
    --title) [ $# -ge 2 ] || die "--title needs text"; title=$2; shift 2 ;;
    --title=*) title=${1#*=}; shift ;;
    --task) [ $# -ge 2 ] || die "--task needs text"; task=$2; shift 2 ;;
    --task=*) task=${1#*=}; shift ;;
    --task-file) [ $# -ge 2 ] || die "--task-file needs a path"; task_file=$2; shift 2 ;;
    --task-file=*) task_file=${1#*=}; shift ;;
    --auto) auto=1; shift ;;
    --no-window) open_window=0; shift ;;
    --fetch) fetch=1; shift ;;
    --json) json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)
      [ -z "$slug" ] || die "unexpected argument: $1"
      slug=$1
      shift
      ;;
  esac
done

[ -n "$slug" ] || { usage >&2; exit 2; }
case $slug in
  *[!A-Za-z0-9._-]* | .* | *..*) die "invalid slug '$slug': use letters, digits, dots, underscores, hyphens" ;;
esac

if [ -n "$task_file" ]; then
  [ -z "$task" ] || die "use --task or --task-file, not both"
  [ -r "$task_file" ] || die "cannot read task file: $task_file"
  task=$(cat "$task_file")
fi
if [ -n "$task" ] && [ "$open_window" -eq 0 ]; then
  die "--task needs a Rex window; drop --no-window"
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
command -v git >/dev/null || die "git not found"

common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
repo_root=$(dirname "$common_dir")
project=$(basename "$repo_root")
[ -n "$project" ] && [ "$project" != "/" ] || die "cannot determine project name from $repo_root"

# Resolve the base ref before touching anything.
resolve_ref() {
  git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1 && printf '%s' "$1" && return 0
  return 1
}

if [ "$target_explicit" -eq 1 ]; then
  [ -n "$target" ] || die "--target needs a branch"
  resolved=$(resolve_ref "$target" || resolve_ref "origin/$target") ||
    die "target branch '$target' not found in $project"
else
  resolved=
  for candidate in master origin/master main origin/main; do
    if r=$(resolve_ref "$candidate"); then resolved=$r; break; fi
  done
  [ -n "$resolved" ] || die "no default branch found (tried master, main); pass --target"
fi

branch="rex/$slug"
path="$root/$project/$slug"

git show-ref --verify --quiet "refs/heads/$branch" && die "branch '$branch' already exists"
[ -e "$path" ] && die "path already exists: $path"

session=
block_id=
window_id=
if [ "$open_window" -eq 1 ]; then
  command -v rex >/dev/null || die "rex not found; use --no-window to create the worktree only"
  if [ -n "$task" ]; then
    command -v opencode >/dev/null || die "opencode not found; omit --task to open a plain shell"
  fi
  session=${REX_SESSION:-}
  if [ -z "$session" ]; then
    session=$(rex whoami --json 2>/dev/null | jq -er '.session_id') ||
      die "cannot determine Rex session; use --no-window or set REX_SESSION"
  fi
fi

if [ "$fetch" -eq 1 ]; then
  git -C "$repo_root" fetch --prune origin
fi

mkdir -p "$root/$project"
git -C "$repo_root" worktree add -b "$branch" "$path" "$resolved" >&2

title=${title:-$slug}
if [ "$open_window" -eq 1 ]; then
  if [ -n "$task" ]; then
    window_cmd=(opencode)
    [ "$auto" -eq 1 ] && window_cmd+=(--auto)
    window_cmd+=(--prompt "$task")
    created=$(rex window new -s "$session" "$title" -c "$path" --json -- "${window_cmd[@]}") ||
      die "worktree created at $path but Rex window failed"
  else
    created=$(rex window new -s "$session" "$title" -c "$path" --json) ||
      die "worktree created at $path but Rex window failed"
  fi
  window_id=$(printf '%s' "$created" | jq -r '.window_id // empty')
  block_id=$(printf '%s' "$created" | jq -r '.block_ids[0] // empty')
fi

if [ "$json" -eq 1 ]; then
  jq -n \
    --arg project "$project" \
    --arg slug "$slug" \
    --arg branch "$branch" \
    --arg target "$resolved" \
    --arg path "$path" \
    --arg session "$session" \
    --arg window "$window_id" \
    --arg block "$block_id" \
    --arg task "$task" \
    '{project: $project, slug: $slug, branch: $branch, target: $target, path: $path}
     + (if $window == "" then {} else {session_id: $session, window_id: $window, block_id: $block} end)
     + (if $task == "" then {} else {agent: "opencode", task: $task} end)'
else
  printf 'project: %s\n' "$project"
  printf 'branch:  %s (from %s)\n' "$branch" "$resolved"
  printf 'path:    %s\n' "$path"
  if [ -n "$window_id" ]; then
    printf 'window:  %s (session %s)\n' "$window_id" "$session"
  fi
  if [ -n "$task" ]; then
    printf 'agent:   opencode (task submitted)\n'
  fi
fi
