---
name: mission-kickoff
description: >-
  Kick-start a mission with a four-step bootstrap: (1) check the docs of record,
  (2) check workspace/git state, (3) find current goals and priorities,
  (4) propose and assign tasks to supervised workers. Use when the user says
  "kick off a mission", "start a mission", "mission kickoff", "bootstrap this
  work", "what should we work on next", or begins a multi-step task and wants the
  current state and a task plan before doing anything.
compatibility: >-
  Workspace-agnostic. Concrete paths come from a local profile (see Step 0), not
  from this file, so nothing here is tied to one project. Needs git and bash; the
  optional step-4 dispatch needs a worker CLI such as orca-ide, and the optional
  board lookup in step 3 needs a task-board client such as the deck skill.
  Read-only until the user approves task dispatch.
---

# Mission kickoff

A repeatable bootstrap to run **before most missions**. Gather state, surface the
current priority, then propose a task assignment. Steps 1–3 are read-only; step 4
only launches workers **after the user approves the plan**.

Resolve `<skill-dir>` from the path this `SKILL.md` was loaded from; do not assume
the current working directory.

## Step 0 — Load the workspace profile

This skill is generic; the specifics live in a **local, git-ignored profile**:

```bash
CFG="${MISSION_KICKOFF_CONFIG:-$HOME/.config/mission-kickoff/config.sh}"
[ -f "$CFG" ] && . "$CFG"
```

It may define: `MK_WORKSPACE_ROOT`, `MK_PROJECT_NAME`, `MK_DOCS_OF_RECORD` (array),
`MK_REPO_MAP_DOC`, `MK_AGENT_SPACE`, `MK_GOALS_FILE`, `MK_TODOS_DIR`,
`MK_TASK_BOARD_NAME`, `MK_TASK_BOARD_CMD`, `MK_INVENTORY_CMD`, `MK_SWEEP_LOG`,
`MK_ORCA` (worker CLI, e.g. `orca-ide`), `MK_AGENT` (preferred worker agent).

**If there is no profile, do not invent paths.** Ask the user for the workspace
root and where goals/todos live, or infer them from the repo layout and say what
you assumed. Every unset variable below means "skip that source and say so", never
"guess a plausible path". `$MK_ORCA` is written as `ORCA` in step 4; on Linux that
is `orca-ide`, never bare `orca` outside an Orca-managed terminal.

## Step 1 — Check the documents

Read the docs of record, in the profile's order (`MK_DOCS_OF_RECORD`) — typically a
roadmap or status page, a workspace overview, and a catalog of pointers
(`MK_REPO_MAP_DOC`) covering repos, remotes and layout.

**Verify, don't trust.** A roadmap can assert progress that never landed. Before
planning around a "done" claim, confirm it against git/disk (e.g. `git -C <repo>
log --oneline -5`, check the file/branch actually exists). Treat any doc status as
a hypothesis until checked — including the paths the profile itself names, which
drift when repos move.

## Step 2 — Check the workspaces

Run the bundled read-only survey (categorized git state + latest stewardship sweep):

```bash
bash <skill-dir>/scripts/scan-workspace.sh            # uses $MK_WORKSPACE_ROOT
bash <skill-dir>/scripts/scan-workspace.sh <root>     # or name a root explicitly
```

Interpret it: which repos have local changes or unpushed commits, which branch each
is on, and what the last stewardship sweep did (`MK_SWEEP_LOG`, if set). Rows are
grouped by the first path component under the root, so the categories are whatever
the workspace actually uses. `no-upstream` means "no tracking branch", which is not
the same as "in sync" — treat those repos as unbacked-up.

Only if the mission needs **live fleet state**, run the inventory tool
(`MK_INVENTORY_CMD`). Such a tool usually SSHes to hosts — keep concurrency low
(≤8) and never let it write.

## Step 3 — Find current goals

Cross-reference these sources, in order, to establish the current priority:

1. `MK_GOALS_FILE` — agreed long-term outcomes. May be uninitialized or empty; if
   so, say that and fall through rather than treating silence as "no goals".
2. `MK_TODOS_DIR` — shared list, per-agent lists, and any named plans. Collect open
   `[ ]` items with their owner/status/date.
3. The task board (`MK_TASK_BOARD_NAME` via `MK_TASK_BOARD_CMD`) — milestones and
   product cards across their columns. Read the board tool's own docs for its
   argument shape; do not assume flag names. A forge such as GitLab may have no
   milestones at all — do not go looking there if the board is the tracker.
4. The roadmap's top-priority items from Step 1.

Synthesize: what is the **single most important outcome** right now, what blocks it,
and which open tasks advance it. Respect todo ownership — only plan to edit items
you own; preserve other agents' in-progress work.

## Step 4 — Assign tasks

Decompose the mission into **independent** tasks. Present a short plan to the user
(task → target repo/worktree → agent → expected outcome) and **get approval before
launching anything**. Dispatch is a shared-state action.

On approval, use the supervised-worker pattern of your worker CLI (`ORCA` =
`$MK_ORCA`):

```bash
ORCA orchestration worker-start --spec "<task brief + guardrails>" \
  --worktree current --agent "$MK_AGENT"
```

- Prefer the owner's chosen agent (`MK_AGENT`). Add `--model` only if the user named
  one.
- `--worktree current` shares your workspace; use `--worktree new-child --name <n>`
  to isolate, or `--worktree new-top-level --repo id:<repoId> --name <n>` for a
  standalone checkout (`ORCA repo list --json` gives ids — they are under
  `.result.repos`, not the top level). Let `worker-start` make the checkout; never
  create it yourself.
- For a hand-off with **nothing expected back**, use the plain worktree route
  instead: `ORCA worktree create --name <n> --no-parent --agent <a> --prompt "<brief>" --json`.
- Start every independent worker, then **end your turn** — the supervisor wakes you
  when they report. Do not poll or run watch scripts. Answer worker questions with
  `ORCA orchestration reply --id <message_id> --body "<answer>"`; steer with
  `ORCA orchestration send --to dispatch:<id> --subject ... --body ...`.
- Track milestone-level items on the task board as they progress.

### Worker-dispatch gotchas

**A successful launch does not prove the task was delivered.** `worker-start` can
create the worktree and start the CLI but never hand over the prompt — reproduced
with both `--spec` and `--spec-file`. The agent then sits at a fresh idle prompt and
the worktree is `dirty=0` at the base commit. `ok:true` plus a dispatch id is **not**
evidence the work began, and the receipt will not tell you either way: its keys are
`dispatchId`, `taskId`, `runId`, `runCreated`, `state`, `agent`, `mode`, `terminal`,
`workspace`, `keptOpen`, `next` — there is **no** delivery-outcome field. (`agent
launch`, a different command, does report `result.launch.prompt.outcome`; do not go
looking for that here.) `state: ready` is the *suspicious* signature, not a success.

Verify delivery out of band, then confirm the agent actually started:

```bash
ORCA terminal read --terminal <handle> --screen     # idle "Type your message" banner = NOT delivered
ORCA orchestration worker-list --json               # want outcome=in_progress AND liveness=live
```

Rising `Context …% used`, thinking/tool output on screen, or new commits all confirm
it began. If it is idle, deliver the brief with `send` (do not edit the worktree
yourself or type into its terminal):

```bash
ORCA orchestration send --to dispatch:<id> --type dispatch \
  --subject "<title>" --body "<full task brief>"
```

Flags are `--subject` + `--body` + `--type`; there is no `--text`. Diagnose with
`ORCA orchestration worker-list --json` (dispatchId / state / liveness / workspace)
and `ORCA terminal read --terminal <handle> --screen`.

**Completion must be a typed event, not prose.** A worker that merely writes
"worker_done: ..." into a `--type status` message has *not* reported: the dispatch
stays open and the supervisor later escalates "worker stopped without reporting".
Only the typed event closes it. So when you deliver a brief by `send` — which
carries no task/dispatch preamble — **paste the exact completion command into the
brief**, with both ids resolved:

```bash
ORCA orchestration send --to coordinator --type worker_done \
  --outcome succeeded --task-id <task_id> --dispatch-id <dispatch_id>
```

**Check dispatch state before re-emitting a completion.** The worker list's `state`
(`succeeded` vs `in_progress`) is authoritative; an inbox can hold both a rejected
first attempt and the corrected event that later landed. A coordinator's claim that
"the dispatch is still open" may rest on the stale rejection, and re-sending over a
settled task creates a duplicate report and misattributes the outcome. Look up
`state` first; only re-emit while it is genuinely `in_progress`.

**Reporting route:** only `worker-start` workers report back and appear in the
worker list. `worktree create --prompt` is fire-and-forget — tracked nowhere,
reports nothing — so use it only for true hand-offs where the user works in that
chat.

**Guardrails to embed in every worker brief:** no force-push; no secrets in output
or commits; push only to the repo's configured real origin — verify
`git remote get-url origin` immediately before pushing, never a proxy-substituted
remote; unsigned Conventional Commits with no co-author trailer; no commits to the
protected branch, no merges, no merge request unless asked; no production writes or
live-system logins without explicit owner approval in the brief; work only in the
assigned worktree; capture real exit codes (`cmd >log 2>&1; echo EXIT=$?`) and verify
against git/disk before claiming done — a piped log is not proof.

## Output

End with a concise **kickoff brief**: docs state (verified), workspace state
(dirty/unpushed highlights), the current goal/priority and its blockers, and the
approved task assignment (worker handles + expected outcomes). If nothing is
actionable, say so and stop rather than inventing work.
