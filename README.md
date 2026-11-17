# mission-kickoff-skill

Portable [Agent Skills](https://agentskills.io) package that gives an agent CLI
(Qwen Code, Claude Code, OpenCode, Qoder, ...) a repeatable **bootstrap
procedure** to run before starting a mission.

Unlike most skills this one ships no API client. It is a disciplined four-step
checklist that stops an agent from guessing its way into work:

1. **Check the documents** — read the docs of record, then *verify* their status
   claims against git and disk instead of trusting them.
2. **Check the workspaces** — run the bundled read-only survey to see which repos
   are dirty, which branch each is on, and what has unpushed commits.
3. **Find current goals** — cross-reference goal files, todo lists and the task
   board to establish the single most important outcome and its blockers.
4. **Assign tasks** — decompose into independent tasks, present a plan, and
   dispatch supervised workers **only after the owner approves**.

Steps 1–3 are strictly read-only. Step 4 is a shared-state action and is gated on
explicit approval.

## Workspace-agnostic by design

Nothing in the skill is tied to one project. Concrete paths come from a **profile
that lives in each workspace** — see Multiple workspaces below.

```bash
bash install.sh                        # copies the skill + links it; creates no profile
mkdir -p ~/Workspace/my-project/.mission-kickoff
cp config.sh.example ~/Workspace/my-project/.config/.mission-kickoff.sh
$EDITOR ~/Workspace/my-project/.config/.mission-kickoff.sh
```

```bash
MK_DOCS_OF_RECORD=( "<roadmap>" "<overview>" )    # step 1, read in order
MK_GOALS_FILE="<long-term-goals.md>"              # step 3
MK_TODOS_DIR="<todos dir>"                        # step 3
MK_TASK_BOARD_CMD="<complete runnable command>"   # step 3, optional
MK_INVENTORY_CMD="<live host/container survey>"   # step 2, optional
MK_ORCA="orca-ide"; MK_AGENT="qwen-code"          # step 4
```

## Multiple workspaces

Each workspace declares itself with a profile at its own root, and the resolver
finds it by walking **up from the current directory**. So you pick a workspace by
working inside it — there is no name to remember, no selector to pass, and no
central registry that can drift out of sync with the tree it describes. The root
itself is derived from where the marker was found, so it is never restated:

```
~/Workspace/alpha/.config/.mission-kickoff.sh     ← any cwd under alpha resolves it
~/Workspace/beta/.config/.mission-kickoff.sh      ← any cwd under beta resolves it
```

```bash
bash scripts/profile.sh --status    # which profile applies here, and its root
bash scripts/profile.sh --list      # every profiled and profile-less root
```

Resolution order, first hit wins: `$MISSION_KICKOFF_CONFIG` → nearest
`.config/.mission-kickoff.sh` above `$PWD` → `~/.config/mission-kickoff/config.sh`
(machine-wide fallback, the one place a root must be stated) → none.

This differs from the `DECK_SITE`/`MW_SITE` pattern in the sibling skills on
purpose: there the target is a remote server that nothing about your cwd identifies,
so a name is the only carrier. Here the target *is* the directory you are standing
in.

Every variable is optional. **An unset variable means "skip that source and say
so"** — the skill is instructed never to invent a plausible path, and with no
profile at all it asks you for the workspace root instead of guessing. Profiles are
written mode `600` and may hold credentials under the shared convention; a workspace
root is normally not a git worktree, so `.config/` sits above every repo. If a root
*is* a repo, gitignore `.config/` — do not let a token reach a remote.

## Requires the shared loader

The walk-up and the profile handling live in `~/.config/skill-config/loader.sh`,
owned by [bk-skills](https://github.com/brucekomike/bk-skills), so every skill
resolves "which workspace am I in?" the same way. `install.sh` checks for it first
and, if it is missing, prints how to install a bundle and exits without touching
anything:

```bash
gh release download --repo brucekomike/bk-skills --pattern '*.tar.gz'
bash scripts/install-bundle.sh ./bk-skills-*.tar.gz   # from a bk-skills checkout
```

Override the location with `SKILL_CONFIG_LOADER=/path/to/loader.sh`.

## The survey script

```bash
bash scripts/scan-workspace.sh                  # workspace from cwd's profile
bash scripts/scan-workspace.sh <workspace-root> # or name a root explicitly
bash scripts/scan-workspace.sh -l               # list profiled / profile-less roots
# === Workspace: /home/.../my-project ===
# CATEGORY   REPO                               BRANCH                    DIRTY UNPUSHED
# docs       docs-site                          main                          0        0
# apps       web-frontend                       feat/sso                      3        1
# === 12 repos | 4 with local changes | 2 unpushed commits | 1 without upstream ===
```

Read-only: `git status --porcelain`, `git rev-list --count '@{u}..HEAD'`, `find`.
Categories are simply the first path component under the root, so they are whatever
your workspace actually uses. Unborn-HEAD safe, and it reports `no-upstream`
rather than `0` so "no tracking branch" is never mistaken for "in sync".

## Requirements

- Bash 4+, `git`, `find`
- For step 4 only: a supervised-worker CLI such as [`orca-ide`](https://orca.id)
- For the step-3 board only: a task-board client such as the `deck` skill

## Layout

```
.agents/skills/mission-kickoff/
├── SKILL.md                     the procedure the agent loads
└── scripts/
    ├── profile.sh               resolves the applicable workspace profile
    └── scan-workspace.sh        step 2 survey (read-only)
config.sh.example                copy to <workspace-root>/.config/.mission-kickoff.sh
install.sh                       canonical copy + compatibility links; creates no profile
AGENTS.md                        notes for agents working in this repo
```

`.claude/skills` and `.qwen/skills` entries are compatibility symlinks created by
`install.sh`; `.agents/skills/` is the canonical directory.
