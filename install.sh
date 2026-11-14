#!/usr/bin/env bash
# install.sh — install the mission-kickoff skill for Agent Skills-compatible clients
#
# Installs the canonical skill to ~/.agents/skills/mission-kickoff, creates
# compatibility links at ~/.claude/skills and ~/.qwen/skills, and seeds
# ~/.config/mission-kickoff/config.sh from the bundled example when absent.
# The profile holds paths only — no credentials.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_SRC="${SCRIPT_DIR}/.agents/skills"
SKILLS_DST="${HOME}/.agents/skills"
LINK_ROOTS=("${HOME}/.claude/skills" "${HOME}/.qwen/skills")
CONFIG_DIR="${HOME}/.config/mission-kickoff"

[[ -d "$SKILLS_SRC" ]] || { echo "no skills to install in ${SKILLS_SRC}" >&2; exit 1; }

echo "==> Installing skill to ${SKILLS_DST}"
mkdir -p "$SKILLS_DST" "$CONFIG_DIR"

for skill in "$SKILLS_SRC"/*; do
  [[ -d "$skill" ]] || continue
  name="$(basename "$skill")"

  rm -rf "${SKILLS_DST:?}/$name"
  cp -r "$skill" "$SKILLS_DST/"
  chmod 755 "${SKILLS_DST}/$name/scripts/"*.sh 2>/dev/null || true

  for root in "${LINK_ROOTS[@]}"; do
    mkdir -p "$root"
    # rm -rf before ln -s: the destination may be a REAL directory (a hand-made
    # install), and `ln -sfn` would then nest the link inside it instead of
    # replacing it.
    rm -rf "${root:?}/$name"
    ln -s "${SKILLS_DST}/$name" "${root}/$name"
    echo "    linked ${root}/$name"
  done
done

if [[ ! -f "$CONFIG_DIR/config.sh" ]]; then
  cp "${SCRIPT_DIR}/config.sh.example" "$CONFIG_DIR/config.sh"
  echo "==> Seeded $CONFIG_DIR/config.sh — point MK_WORKSPACE_ROOT and the doc/goal"
  echo "    paths at your own workspace, or the skill will ask instead of guessing."
else
  echo "==> Kept existing $CONFIG_DIR/config.sh"
fi

echo
echo "==> Verify:"
for root in "$SKILLS_DST" "${LINK_ROOTS[@]}"; do
  printf '    %-40s %s\n' "$root/mission-kickoff" \
    "$(if [[ -f "$root/mission-kickoff/SKILL.md" ]]; then echo OK; else echo MISSING; fi)"
done
echo
echo "==> Smoke-test the bundled survey script (read-only):"
echo "    bash ${SKILLS_DST}/mission-kickoff/scripts/scan-workspace.sh"
