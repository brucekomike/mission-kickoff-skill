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

Nothing in the skill is tied to one project. All concrete paths come from a local
**profile** that you write once:

```bash
bash install.sh                       # seeds ~/.config/mission-kickoff/config.sh
$EDITOR ~/.config/mission-kickoff/config.sh
```

```bash
MK_WORKSPACE_ROOT="$HOME/Workspace/<project>"     # what step 2 surveys
MK_DOCS_OF_RECORD=( "<roadmap>" "<overview>" )    # step 1, read in order
MK_GOALS_FILE="<long-term-goals.md>"              # step 3
MK_TODOS_DIR="<todos dir>"                        # step 3
MK_TASK_BOARD_CMD="<complete runnable command>"   # step 3, optional
MK_INVENTORY_CMD="<live host/container survey>"   # step 2, optional
MK_ORCA="orca-ide"; MK_AGENT="qwen-code"          # step 4
```

Every variable is optional, and the profile is git-ignored so a per-machine setup
is never committed. **An unset variable means "skip that source and say so"** — the
skill is instructed never to invent a plausible path. With no profile at all it
asks you for the workspace root instead of guessing. See `config.sh.example`.

## The survey script

```bash
bash scripts/scan-workspace.sh                  # uses $MK_WORKSPACE_ROOT
bash scripts/scan-workspace.sh <workspace-root> # or name a root explicitly
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
└── scripts/scan-workspace.sh    step 2 survey (read-only)
config.sh.example                profile template → ~/.config/mission-kickoff/config.sh
install.sh                       canonical copy + compatibility links + profile seed
AGENTS.md                        notes for agents working in this repo
```

`.claude/skills` and `.qwen/skills` entries are compatibility symlinks created by
`install.sh`; `.agents/skills/` is the canonical directory.
