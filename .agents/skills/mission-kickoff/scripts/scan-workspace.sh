#!/usr/bin/env bash
# mission-kickoff step 2: quick git-state survey of a categorized workspace.
# Read-only. Unborn-HEAD safe.
#
# Usage: scan-workspace.sh [workspace-root]
#   -l [dir]   list which workspaces declare a profile (and which do not)
# With no root argument, the workspace comes from the profile that applies to the
# current directory: <workspace-root>/.config/.mission-kickoff.sh found by walking
# up, then the global fallback. See profile.sh.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROFILE="$HERE/profile.sh"

case "${1:-}" in
  -l|--list) exec bash "$PROFILE" --list "${2:-$HOME/Workspace}" ;;
esac

# Load whichever profile applies, so MK_SWEEP_LOG / MK_SWEEP_TAIL / MK_SCAN_DEPTH
# are set even when the root is passed explicitly on the command line.
CFG="$(bash "$PROFILE" --config 2>/dev/null || true)"
# shellcheck disable=SC1090
[ -n "$CFG" ] && [ -f "$CFG" ] && . "$CFG"

root="${1:-$(bash "$PROFILE" --root 2>/dev/null || true)}"
if [ -z "$root" ]; then
  echo "usage: $(basename "$0") <workspace-root>" >&2
  echo "   no workspace profile found from $(pwd)" >&2
  echo "   create one at <workspace-root>/.config/.mission-kickoff.sh, or pass the root explicitly" >&2
  exit 2
fi
# expand a leading ~ that arrived through a quoted variable
case "$root" in "~"/*) root="$HOME/${root#\~/}" ;; "~") root="$HOME" ;; esac
[ -d "$root" ] || { echo "no such workspace: $root" >&2; exit 1; }

printf '=== Workspace: %s ===\n' "$root"
[ -n "$CFG" ] && [ -f "$CFG" ] && printf '=== profile: %s ===\n' "$CFG"
printf '%-10s %-34s %-26s %6s %8s\n' CATEGORY REPO BRANCH DIRTY UNPUSHED
tot=0; dirtytot=0; unptot=0; noremote=0; counted=""
while IFS= read -r gitdir; do
  r=$(dirname "$gitdir"); rel=${r#"$root"/}
  counted="${counted}${r}
"
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
[ "$tot" -eq 0 ] && echo "   (no git repositories found under this root)"
printf '=== %s repos | %s with local changes | %s unpushed commits | %s without upstream ===\n' \
  "$tot" "$dirtytot" "$unptot" "$noremote"

# Repos reached through a symlink are invisible to `find -name .git`, so a repo
# living in another tree can be silently missing from this root's totals. Report
# only those whose target was NOT already surveyed, so a link that points at a
# sibling repo inside this same root does not show up as a phantom omission.
linked=""
while IFS= read -r l; do
  tgt="$(readlink -f "$l")"
  [ -d "$tgt/.git" ] || continue
  printf '%s' "$counted" | grep -qxF "$tgt" && continue
  linked="${linked:+$linked, }${l#"$root"/} -> ${tgt#"$HOME"/}"
done < <(find "$root" -maxdepth "${MK_SCAN_DEPTH:-5}" -type l 2>/dev/null | sort)
[ -n "$linked" ] && printf '=== symlinked repos outside this root, NOT counted above: %s ===\n' "$linked"

# Optional: tail the last stewardship/automation sweep for this workspace.
# `-` not `:-` so that an explicitly empty MK_SWEEP_LOG disables this section;
# only an unset variable should fall through to the default path.
log="${MK_SWEEP_LOG-$root/.qwen/tmp/hourly-repo-push.log}"
if [ -n "$log" ] && [ -f "$log" ]; then
  printf '\n=== latest stewardship sweep (tail %s) ===\n' "${MK_SWEEP_TAIL:-15}"
  tail -n "${MK_SWEEP_TAIL:-15}" "$log"
fi
