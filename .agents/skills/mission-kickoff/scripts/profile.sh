#!/usr/bin/env bash
# Resolve the mission-kickoff workspace profile.
#
# This is a thin wrapper: the walk-up, the resolution order and the root derivation
# all live in the shared skill-config loader, so every skill answers "which
# workspace am I in?" the same way. mission-kickoff has no sites — its profile is
# scalar MK_* variables — so it never calls skillconf_apply.
#
# A workspace declares itself with <workspace-root>/.config/.mission-kickoff.sh.
# Finding that file by walking up from $PWD yields the profile AND the root, so the
# root is derived, never restated, and there is no registry or selector to drift.
#
# Usage:
#   profile.sh --config     path of the resolved profile (empty if none)
#   profile.sh --source     which rule matched: env | workspace | global | none
#   profile.sh --root       workspace root the profile belongs to
#   profile.sh --status     human-readable provenance
#   profile.sh --list [dir] workspaces declaring one, plus repo-holding roots that do not
# Read-only. Never writes, never creates a profile, never runs a profile command.
set -uo pipefail

LOADER="${SKILL_CONFIG_LOADER:-$HOME/.config/skill-config/loader.sh}"
if [ ! -f "$LOADER" ]; then
  cat >&2 <<EOF
mission-kickoff: shared config loader not found at $LOADER

  Get it by installing a bk-skills bundle:
    gh release download --repo brucekomike/bk-skills --pattern '*.tar.gz'
    bash scripts/install-bundle.sh ./bk-skills-*.tar.gz
  (or: bash scripts/install-bundle.sh --latest, from a bk-skills checkout)

  Override the location with SKILL_CONFIG_LOADER=/path/to/loader.sh
EOF
  exit 3
fi
# shellcheck disable=SC1090
. "$LOADER"

SEARCH_PATH="${MK_SEARCH_PATH:-${HOME}/Workspace}"

# Which rule matched, and the path it chose. The loader owns the order; this only
# reports it, because "it silently used another workspace's profile" is the failure
# worth being able to see.
resolve() {
  local cfg src="none"
  if [ -n "${MISSION_KICKOFF_CONFIG:-}" ] && [ -f "${MISSION_KICKOFF_CONFIG:-}" ]; then
    printf 'env\t%s\n' "$MISSION_KICKOFF_CONFIG"; return 0
  fi
  if cfg="$(skillconf_find MK)"; then
    # A path under <root>/.config/ is a workspace profile; anything else is the
    # machine-wide fallback the loader fell through to.
    if skillconf_rootof "$cfg" >/dev/null 2>&1; then src=workspace; else src=global; fi
    printf '%s\t%s\n' "$src" "$cfg"; return 0
  fi
  printf 'none\t\n'; return 1
}

# Roots holding repos but declaring no profile: steps 1 and 3 have nothing to read
# there, so the gap is reported instead of hidden behind a successful-looking run.
list_workspaces() {
  local base="${1:-$SEARCH_PATH}" n=0 root p name
  [ -d "$base" ] || { echo "no such search path: $base" >&2; return 1; }
  printf '%-12s %-26s %s\n' STATUS WORKSPACE ROOT
  while IFS= read -r root; do
    printf '%-12s %-26s %s\n' profile "$(basename "$root")" "$root"
    n=$((n+1))
  done < <(skillconf_workspaces "$base" MK)
  for p in "$base"/*/; do
    [ -d "$p" ] || continue
    name="$(basename "$p")"
    [ "$name" = "Agents" ] && continue
    [ -f "$p/.config/.mission-kickoff.sh" ] && continue
    find "$p" -maxdepth 3 -name .git -not -path '*/.git/*' 2>/dev/null | grep -q . || continue
    printf '%-12s %-26s %s\n' "NO CONFIG" "$name" "${p%/}"
    n=$((n+1))
  done
  printf '=== %s roots listed; NO CONFIG ones fall through to steps that ask ===\n' "$n"
}

cmd="${1:---status}"
case "$cmd" in
  --config) resolve | cut -f2 ;;
  --source) resolve | cut -f1 ;;
  --root)   IFS=$'\t' read -r _ c <<<"$(resolve)"; skillconf_rootof "$c" ;;
  --list)   list_workspaces "${2:-$SEARCH_PATH}" ;;
  --status)
    IFS=$'\t' read -r s c <<<"$(resolve)"
    printf 'loader    : %s\n' "$LOADER"
    printf 'source    : %s\n' "$s"
    printf 'profile   : %s\n' "${c:-<none>}"
    printf 'root      : %s\n' "$(skillconf_rootof "$c" 2>/dev/null || true)"
    printf 'search    : %s\n' "$SEARCH_PATH"
    [ "$s" = none ] && printf 'note      : no profile found — ask the owner, never invent paths\n'
    ;;
  *) echo "usage: $(basename "$0") [--config|--source|--root|--status|--list [path]]" >&2; exit 2 ;;
esac
