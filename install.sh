#!/usr/bin/env bash
# install.sh — install the mission-kickoff skill for Agent Skills-compatible clients
#
# Installs the canonical skill to ~/.agents/skills/mission-kickoff and creates
# compatibility links at ~/.claude/skills and ~/.qwen/skills.
#
# It deliberately does NOT create any profile. Profiles live per workspace at
# <workspace-root>/.config/.mission-kickoff.sh, and only you know a workspace's
# real doc and goal paths. install.sh just reports what it can already resolve.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_SRC="${SCRIPT_DIR}/.agents/skills"
SKILLS_DST="${HOME}/.agents/skills"
LINK_ROOTS=("${HOME}/.claude/skills" "${HOME}/.qwen/skills")

[[ -d "$SKILLS_SRC" ]] || { echo "no skills to install in ${SKILLS_SRC}" >&2; exit 1; }

# The skill resolves workspaces through the shared loader, so installing without it
# would leave a skill that cannot answer "which workspace am I in?". Check first and
# say exactly how to get it — this script never downloads anything itself.
LOADER="${SKILL_CONFIG_LOADER:-${HOME}/.config/skill-config/loader.sh}"
if [[ ! -f "$LOADER" ]]; then
  cat >&2 <<EOF
install.sh: shared config loader not found at ${LOADER}

  Install a bk-skills bundle, which carries the loader and every skill at once:
    gh release download --repo brucekomike/bk-skills --pattern '*.tar.gz'
    # then, from a bk-skills checkout:
    bash scripts/install-bundle.sh ./bk-skills-*.tar.gz
    # or: bash scripts/install-bundle.sh --latest

  Nothing was installed. Override the loader location with SKILL_CONFIG_LOADER=...
EOF
  exit 3
fi

echo "==> Installing skill to ${SKILLS_DST}"
mkdir -p "$SKILLS_DST"

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

echo
echo "==> Verify:"
for root in "$SKILLS_DST" "${LINK_ROOTS[@]}"; do
  printf '    %-40s %s\n' "$root/mission-kickoff" \
    "$(if [[ -f "$root/mission-kickoff/SKILL.md" ]]; then echo OK; else echo MISSING; fi)"
done

echo
echo "==> Workspaces this machine can already resolve:"
bash "${SKILLS_DST}/mission-kickoff/scripts/profile.sh" --list || echo "    (none found)"

echo
echo "==> To add a workspace, give its root a profile — nothing else to edit:"
echo "    mkdir -p <workspace-root>/.config"
echo "    cp ${SCRIPT_DIR}/config.sh.example <workspace-root>/.config/.mission-kickoff.sh"
echo "    chmod 600 <workspace-root>/.config/.mission-kickoff.sh"
echo "    \$EDITOR <workspace-root>/.config/.mission-kickoff.sh"
echo "  Then start a kickoff from anywhere inside that tree. One .config/ dir per"
echo "  workspace holds one dot-file per skill. A machine-wide fallback at"
echo "  ~/.config/mission-kickoff/config.sh is consulted only when no workspace"
echo "  profile applies to the current directory."
