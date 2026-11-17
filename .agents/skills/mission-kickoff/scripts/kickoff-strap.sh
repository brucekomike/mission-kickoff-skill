#!/usr/bin/env bash
# kickoff-strap — bootstrap a workspace profile for the mission-kickoff skill.
#
# Creates <workspace-root>/.config/.mission-kickoff.sh by DETECTING what this tree
# actually contains, so onboarding a workspace is one command instead of three
# manual ones. Anything it cannot find is left commented out, because an unset
# variable means "skip that source and say so" while a guessed path means the
# skill quietly reads the wrong file.
#
# The file is written mode 600: the .config/ convention shares one directory per
# workspace across all skills and may hold credentials.
#
# Detection is a hypothesis, not a fact: review the result before trusting it,
# exactly as the skill says about the docs it points at.
#
# Usage:
#   kickoff-strap.sh [workspace-root]   # root defaults to the nearest one
#   kickoff-strap.sh --check [root]     # report only, write nothing
#   kickoff-strap.sh --force [root]     # replace an existing profile
#   kickoff-strap.sh --name <project>   # override the detected project name
#
# Does not touch git state, does not run network commands, never writes a secret.
set -uo pipefail

CFG_DIRNAME=".config"
SKILL_FILE=".mission-kickoff.sh"
check=0; force=0; want_name=""
root=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    --force) force=1 ;;
    --name)  want_name="${2:-}"; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) root="$1" ;;
  esac
  shift
done

# --- pick the workspace root -------------------------------------------------
# Already inside a declared workspace? Use it. Otherwise take the directory whose
# parent is the Workspace hub, else the current directory.
if [ -z "$root" ]; then
  d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/$CFG_DIRNAME/$SKILL_FILE" ]; then root="$d"; break; fi
    d="$(dirname "$d")"
  done
fi
if [ -z "$root" ]; then
  d="$PWD"
  while [ "$d" != "/" ]; do
    [ "$(dirname "$d")" = "$HOME/Workspace" ] && { root="$d"; break; }
    d="$(dirname "$d")"
  done
fi
[ -n "$root" ] || root="$PWD"
root="$(cd "$root" 2>/dev/null && pwd -P)" || { echo "no such directory: $root" >&2; exit 1; }
[ -d "$root" ] || { echo "no such directory: $root" >&2; exit 1; }

name="${want_name:-$(basename "$root")}"
out="$root/$CFG_DIRNAME/$SKILL_FILE"
inrepo="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)"

say() { printf '%s\n' "$*"; }
found() { printf '  found    : %s\n' "$*"; }
missing(){ printf '  missing  : %s  -> step will report it as unconfigured\n' "$*"; }

say "=== kickoff-strap: $name ($root) ==="
[ "$inrepo" = "$root" ] && say "  note     : the root IS a git worktree — add .config/ to .gitignore, or commit it deliberately"

# --- detection ---------------------------------------------------------------
count_repos() { find "$1" -maxdepth "${3:-7}" -name .git -not -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ''; }
# Depth must cover the DEEPEST repo, or the survey silently under-counts: a fixed
# 3 would miss <root>/x/repos/<ns>/<repo>/.git entirely.
depth=3
while IFS= read -r g; do
  rel=${g#"$root"/}
  d=$(printf '%s' "$rel" | tr -cd '/' | wc -c); d=$((d+1))
  [ "$d" -gt "$depth" ] && depth=$d
done < <(find "$root" -maxdepth 7 -name .git -not -path '*/node_modules/*' 2>/dev/null)
repos=$(count_repos "$root")
first_repo=$(find "$root" -maxdepth 7 -name .git -not -path '*/node_modules/*' 2>/dev/null | head -1 | xargs -r dirname)
say "  repos    : $repos at maxdepth $depth$( [ -n "$first_repo" ] && printf '  (e.g. %s)' "${first_repo#"$root"/}" )"

# docs of record: status/roadmap/overview first, then a docs-site root index
pick_docs() {
  local p
  for p in \
    "$1"/*docs*/docs/source/manual/roadmap.md "$1"/docs/*roadmap.md "$1"/*roadmap.md \
    "$1"/*docs*/docs/source/manual/workspace-overview.md "$1"/docs/*overview.md \
    "$1"/*docs*/docs/source/index.md "$1"/docs/source/index.md \
    "$1"/*STATUS*.md "$1"/*status*.md "$1"/README.md; do
    # shellcheck disable=SC2086
    for f in $p; do [ -f "$f" ] && printf '      "%s"\n' "$f"; done
  done | awk '!seen[$0]++' | head -4
}
docs="$(pick_docs "$root")"
if [ -n "$docs" ]; then found "docs of record:"; printf '%s\n' "$docs" | sed 's/^/             /'
else missing "docs of record (no roadmap/status/index under a docs tree)"; fi

repo_map=$(find "$root" -maxdepth 7 \( -name 'reorganization.md' -o -name 'repos.md' \) -not -path '*/.git/*' 2>/dev/null | head -1)
[ -n "$repo_map" ] && found "repo/layout map : ${repo_map#"$root"/}" || missing "repo/layout map"

sweep=$(find "$root/.qwen/tmp" -maxdepth 2 -name '*repo-push*.log' 2>/dev/null | head -1)
[ -n "$sweep" ] && found "stewardship log  : ${sweep#"$root"/}" || missing "stewardship sweep log"

# agent space: inside the tree (often a symlink) or the Workspace-level store
agentspace=""
for c in "$root/agents" "$HOME/Workspace/Agents/$name"; do
  if [ -d "$c" ]; then agentspace="$c"; break; fi
done
goals=""; todos=""; knowledge=""
if [ -n "$agentspace" ]; then
  goals="$(find "$agentspace/goals" -maxdepth 1 -name '*.md' 2>/dev/null | head -1)"
  todos="$( [ -d "$agentspace/todos" ] && echo "$agentspace/todos" )"
  knowledge="$(find "$agentspace/knowledge" -maxdepth 1 -name '*index*.md' 2>/dev/null | head -1)"
  found "agent space      : ${agentspace/#$HOME/\$HOME}"
  [ -n "$goals" ]     && found "goals file     : ${goals/#$HOME/\$HOME}"     || missing "goals file (no goals/*.md)"
  [ -n "$todos" ]     && found "todos dir      : ${todos/#$HOME/\$HOME}"     || missing "todos dir (no todos/)"
  [ -n "$knowledge" ] && found "knowledge index: ${knowledge/#$HOME/\$HOME}"
else missing "agent space (no $root/agents and no ~/Workspace/Agents/$name)"; fi

inventory=""
for c in "$root"/*/bin/survey "$root"/*/bin/inventory; do
  [ -x "$c" ] && { inventory="$c"; break; }
done
[ -n "$inventory" ] && found "inventory tool   : ${inventory#"$root"/}" || missing "live inventory tool (fine to leave unset)"

board_cmd=""
if [ -x "$HOME/.agents/skills/deck/scripts/deck.sh" ]; then
  board_cmd="bash \$HOME/.agents/skills/deck/scripts/deck.sh boards"
  found "board client     : deck.sh present — pick a board id by hand (not run: this script never goes online)"
else missing "task-board client (deck skill not installed)"; fi

orca_bin="$(command -v orca-ide 2>/dev/null || true)"
[ -n "$orca_bin" ] && found "worker CLI       : $orca_bin" || missing "worker CLI (step 4 unavailable)"

# --- emit ---------------------------------------------------------------------
body=$(cat <<EOF
# mission-kickoff workspace profile — $name
# Generated by kickoff-strap.sh on $(date '+%Y-%m-%d'). Paths below were DETECTED,
# not verified as current: read step 1's files before trusting any status claim in
# them, and delete anything this script guessed wrong.
# Written mode 600: this .config/ dir is shared by every skill in the workspace
# and may hold credentials, so keep it out of any git worktree.

# Self-locate: two levels up from this file is the workspace root.
: "\${MK_WORKSPACE_ROOT:=\$(dirname "\$(dirname "\${BASH_SOURCE[0]}")")}"
MK_PROJECT_NAME="$name"
MK_SCAN_DEPTH=$depth

# --- step 1: docs of record ------------------------------------------------
EOF
)
# Command substitution strips the heredoc's final newline; restore exactly one so
# the next append cannot land on the same line as this comment.
body+=$'\n'
if [ -n "$docs" ]; then
  body+=$'MK_DOCS_OF_RECORD=(\n'"$docs"$'\n)\n'
  body+=$'# If anything above is not the status truth for this workspace, replace it:\n# reading a stale roadmap as authoritative is worse than having none.\n'
else
  body+="# MK_DOCS_OF_RECORD=( \"\$MK_WORKSPACE_ROOT/docs/roadmap.md\" )   # TODO: none detected"$'\n'
fi
[ -n "$repo_map" ] && body+="MK_REPO_MAP_DOC=\"\$MK_WORKSPACE_ROOT/${repo_map#"$root"/}\""$'\n' \
                  || body+="# MK_REPO_MAP_DOC=\"\"   # none detected"$'\n'
[ -n "$sweep" ]   && body+="MK_SWEEP_LOG=\"\$MK_WORKSPACE_ROOT/${sweep#"$root"/}\""$'\nMK_SWEEP_TAIL=15\n' \
                  || body+="# MK_SWEEP_LOG=\"\"      # no stewardship sweep in this workspace"$'\n'
body+=$'\n# --- step 3: goals --------------------------------------------------------\n'
if [ -n "$agentspace" ]; then
  body+="MK_AGENT_SPACE=\"${agentspace/#$HOME/\$HOME}\""$'\n'
  [ -n "$goals" ] && body+="MK_GOALS_FILE=\"${goals/#$HOME/\$HOME}\""$'\n' || body+="# MK_GOALS_FILE=\"\"   # no goals/ here yet"$'\n'
  [ -n "$todos" ] && body+="MK_TODOS_DIR=\"${todos/#$HOME/\$HOME}\""$'\n' || body+="# MK_TODOS_DIR=\"\"     # no todos/ here yet"$'\n'
else
  body+="# No agent space was found. Steps 1 and 3 have nothing to read in this"$'\n'
  body+="# workspace until you create one (~/Workspace/Agents/$name, or a symlink at"$'\n'
  body+="# $root/agents) — leave these unset rather than pointing at another project."$'\n'
fi
body+=$'\n# --- milestone board ------------------------------------------------------\n'
if [ -n "$board_cmd" ]; then
  body+="# Unset on purpose: this script never lists boards over the network."$'\n'
  body+="# MK_TASK_BOARD_NAME=\"\""$'\n'
  body+="# MK_TASK_BOARD_CMD=\"bash \$HOME/.agents/skills/deck/scripts/deck.sh cards <boardId>\""$'\n'
else
  body+="# MK_TASK_BOARD_NAME=\"\""$'\n'
  body+="# MK_TASK_BOARD_CMD=\"\""$'\n'
fi
body+=$'\n# --- step 4: dispatch ------------------------------------------------------\n'
body+="MK_ORCA=\"${orca_bin:-orca-ide}\"   # never bare \`orca\` outside an Orca terminal"$'\n'
body+="MK_AGENT=\"qwen-code\""
body+=$'\n'

if [ "$check" = 1 ]; then
  say ""; say "--- would write $out ---"; printf '%s\n' "$body" | sed 's/^/  | /'
  [ -f "$out" ] && say "--- an existing profile is already there; --force would replace it ---"
  exit 0
fi

if [ -f "$out" ] && [ "$force" != 1 ]; then
  say ""; say "REFUSING to overwrite an existing profile: $out"
  say "  edit it directly, or re-run with --force to replace it (a backup is kept)"
  exit 1
fi

mkdir -p "$root/$CFG_DIRNAME"
chmod 700 "$root/$CFG_DIRNAME" 2>/dev/null || true
[ -f "$out" ] && cp -p "$out" "$out.bak-$(date +%Y%m%d-%H%M%S)" && say "  backed up the previous profile"
printf '%s\n' "$body" > "$out"
chmod 600 "$out"
say ""; say "Wrote $out"
say "Now verify it, from anywhere inside this tree:"
say "  bash <skill-dir>/scripts/profile.sh --status"
say "  bash <skill-dir>/scripts/scan-workspace.sh"
say "Then read every MK_DOCS_OF_RECORD file once and correct anything misdetected."
