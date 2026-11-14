#!/usr/bin/env bash
# mission-kickoff step 2: quick git-state survey of a categorized workspace.
# Read-only. Unborn-HEAD safe.
#
# Usage: scan-workspace.sh [workspace-root]
# With no argument the root comes from MK_WORKSPACE_ROOT in the profile
# ($MISSION_KICKOFF_CONFIG, else ~/.config/mission-kickoff/config.sh).
set -uo pipefail

CFG="${MISSION_KICKOFF_CONFIG:-$HOME/.config/mission-kickoff/config.sh}"
# shellcheck disable=SC1090
[ -f "$CFG" ] && . "$CFG"

root="${1:-${MK_WORKSPACE_ROOT:-}}"
if [ -z "$root" ]; then
  echo "usage: $(basename "$0") <workspace-root>" >&2
  echo "   or set MK_WORKSPACE_ROOT in $CFG" >&2
  exit 2
fi
# expand a leading ~ that arrived through a quoted variable
case "$root" in "~"/*) root="$HOME/${root#\~/}" ;; "~") root="$HOME" ;; esac
[ -d "$root" ] || { echo "no such workspace: $root" >&2; exit 1; }

printf '=== Workspace: %s ===\n' "$root"
printf '%-10s %-34s %-26s %6s %8s\n' CATEGORY REPO BRANCH DIRTY UNPUSHED
tot=0; dirtytot=0; unptot=0; noremote=0
while IFS= read -r gitdir; do
  r=$(dirname "$gitdir"); rel=${r#"$root"/}
  cat=${rel%%/*}; [ "$cat" = "$rel" ] && cat="(root)"
  name=${rel#"$cat"/}; [ "$name" = "$rel" ] && name=$rel
  branch=$(git -C "$r" symbolic-ref --short -q HEAD 2>/dev/null || echo DETACHED)
  # `git rev-parse HEAD` prints the literal "HEAD" *and* exits non-zero on an
  # unborn branch, so test it separately rather than trusting $(...||fallback).
  git -C "$r" rev-parse --verify -q HEAD >/dev/null 2>&1 || branch="UNBORN"
  dirty=$(git -C "$r" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if git -C "$r" rev-parse --verify -q '@{u}' >/dev/null 2>&1; then
    unp=$(git -C "$r" rev-list --count '@{u}..HEAD' 2>/dev/null)
  else
    unp="no-upstream"; noremote=$((noremote+1))
  fi
  printf '%-10s %-34s %-26s %6s %8s\n' "$cat" "$name" "$branch" "$dirty" "$unp"
  tot=$((tot+1)); dirtytot=$((dirtytot+dirty))
  case "$unp" in ''|*[!0-9]*) ;; *) unptot=$((unptot+unp));; esac
done < <(find "$root" -maxdepth "${MK_SCAN_DEPTH:-5}" -name .git \
           -not -path '*/node_modules/*' 2>/dev/null | sort)
printf '=== %s repos | %s with local changes | %s unpushed commits | %s without upstream ===\n' \
  "$tot" "$dirtytot" "$unptot" "$noremote"

# Optional: tail the last stewardship/automation sweep for this workspace.
log="${MK_SWEEP_LOG:-$root/.qwen/tmp/hourly-repo-push.log}"
if [ -n "$log" ] && [ -f "$log" ]; then
  printf '\n=== latest stewardship sweep (tail %s) ===\n' "${MK_SWEEP_TAIL:-15}"
  tail -n "${MK_SWEEP_TAIL:-15}" "$log"
fi
