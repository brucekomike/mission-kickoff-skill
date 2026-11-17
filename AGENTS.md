# mission-kickoff-skill

This repository provides a portable Agent Skill (`mission-kickoff`): a four-step
bootstrap procedure an agent runs before starting a mission — check docs, check
workspaces, find current goals, assign tasks. The canonical skill directory is
`.agents/skills/mission-kickoff/`; `~/.claude/skills` and `~/.qwen/skills` are
compatibility symlinks created by `install.sh`.

## What this skill is

A **procedure**, not an API client. It ships two helpers (`profile.sh` resolves the
workspace profile, `scan-workspace.sh` surveys git state), one instruction file
(`SKILL.md`) and one profile template (`config.sh.example`). It holds no
credentials and has no network client of its own.

## Workspace-specifics live in the workspace, never here

`SKILL.md` must stay generic: concrete paths, board ids, inventory commands and
preferred agents come from `<workspace-root>/.config/.mission-kickoff.sh`, which the
shared skill-config loader finds by walking up from the current directory;
`scripts/profile.sh` is only a wrapper around it. A workspace declares itself by
containing that file; there is no registry to update and no selector to pass. **Do not add a real project's paths, repo names, board names or
host layout back into `SKILL.md`, `README.md`, this file, `config.sh.example` or
either script** — that is the one rule that keeps the package portable and
publishable. Use `<placeholder>` form in prose and a `MK_*` variable in code.

Because the profile lives at a workspace root, it can sit inside a git tree. It
must never hold credentials, and `config.sh.example` says to gitignore
`.config/` when the root is a repo. Do not weaken that into "just put the
paths in SKILL.md so it works everywhere".

An unset `MK_*` variable means "skip that source and say so". The skill must never
invent a plausible path to fill a gap; with no profile at all it asks the owner.

## Runtime requirements

- Bash 4+, `git`, `find`
- `MK_ORCA` (e.g. `orca-ide`) only for step 4 dispatch. On Linux that is
  `orca-ide`, never bare `orca` outside an Orca-managed terminal — bare `orca`
  resolves to a shim here and to the GNOME screen reader elsewhere.
- A task-board client only if the profile sets `MK_TASK_BOARD_CMD`.

## Invariants when editing

- **Steps 1–3 stay read-only.** Never add a write, commit, push or dispatch to
  them. That boundary is the skill's main safety property.
- **Step 4 stays gated.** Dispatch only after the owner approves a presented plan.
- **`SKILL.md` must stay self-contained.** Resolve `<skill-dir>` from the path the
  file was loaded from; never assume the agent's cwd. Invoke bundled scripts by
  absolute path.
- **"Verify, don't trust" is load-bearing**, not decoration: doc status claims are
  hypotheses until checked against `git log` / disk — including the paths the
  profile names, which drift when repos move.
- Keep the guardrail block in every worker brief: no force-push; no secrets in
  output or commits; verify `git remote get-url origin` is the real remote
  immediately before pushing (never a proxy-substituted URL); unsigned Conventional
  Commits, no co-author trailer; no commits to the protected branch, no merges, no
  merge request unless asked; no production writes or live-system logins without
  explicit owner approval in the brief; work only in the assigned worktree; capture
  real exit codes and verify against git/disk before claiming done.

## Orca behaviours encoded in step 4 (measured, not guessed)

These are the reasons the gotcha section reads the way it does — keep them:

- A launch succeeding does **not** prove the brief was delivered — reproduced with
  both `--spec` and `--spec-file`. The `worker-start` receipt has **no**
  delivery-outcome field (keys: `dispatchId`, `taskId`, `runId`, `runCreated`,
  `state`, `agent`, `mode`, `terminal`, `workspace`, `keptOpen`, `next`), and
  `state: ready` is the suspicious signature, not a success. `result.launch.prompt
  .outcome` belongs to the different `agent launch` command — never cite it for
  `worker-start`. Verify with `terminal read --screen` (idle banner = not
  delivered) plus `worker-list --json` (`outcome=in_progress`, `liveness=live`),
  then re-deliver with `orchestration send --type dispatch --subject ... --body ...`
  (there is no `--text` flag).
- Completion must be a **typed** `worker_done` event. Prose reading "worker_done:"
  inside a `--type status` message leaves the dispatch open and triggers a
  "worker stopped without reporting" escalation. Because a `send`-delivered brief
  carries no task/dispatch preamble, the exact completion command with both ids
  resolved must be pasted into the brief.
- Check `worker-list` `state` before re-emitting a completion. The inbox can hold a
  rejected first attempt *and* the later accepted one, so "still open" may be stale;
  re-sending over a settled dispatch duplicates the report.
- `orca repo list --json` nests results under `.result.repos`, not the top level.
- Only `worker-start` workers report back; `worktree create --prompt` is
  fire-and-forget and appears in no worker list.

## install.sh notes

- Installs to `~/.agents/skills/<name>` and links into `~/.claude/skills` and
  `~/.qwen/skills`. It **creates no profile**: only the owner knows a workspace's
  real doc and goal paths, so seeding one would fabricate config. It ends by
  printing `profile.sh --list` and the two commands to add a workspace.
- It runs `rm -rf "$root/$name"` **before** `ln -s`. This is deliberate: a hand-made
  install leaves a *real directory* at that path, and `ln -sfn` would nest the new
  link inside it (`.../mission-kickoff/mission-kickoff`) instead of replacing it.
  Do not "simplify" this back to `ln -sfn`.
- The `rm -rf` targets are guarded with `${root:?}` so an unset variable cannot
  expand to a destructive path.

## profile.sh notes

- **It is a wrapper, not a resolver.** The walk-up, the resolution order and the
  root derivation all live in the shared `~/.config/skill-config/loader.sh` (owned
  by bk-skills). Do not reintroduce a second implementation here: two resolvers
  drift, and a skill that resolves a different workspace than its siblings is worse
  than one that fails. If the loader is absent, exit `3` with the install note.
- mission-kickoff has **no sites** — its profile is scalar `MK_*` variables — so it
  calls `skillconf_find MK` / `skillconf_rootof` / `skillconf_workspaces` and never
  `skillconf_apply`. The loader has no slot table for `MK` on purpose.
- The profile file and the declaration are the same object: finding
  `.config/.mission-kickoff.sh` yields the profile *and* the root in one step.
  Deriving the root from the path is what stops it drifting, so a workspace profile
  must not hardcode `MK_WORKSPACE_ROOT` — it self-locates with `${BASH_SOURCE[0]}`,
  and only the global fallback states a root.
- Resolution is `env → workspace → global → none`. `--source` reports which rule
  matched, because "it silently used the wrong profile" is the failure to be able
  to see.
- `--list` reports roots with **no** profile too. Hiding unconfigured workspaces
  would make a missing profile look like a successful one.
- Read-only: it never writes, creates, or executes a profile command.

## scan-workspace.sh notes

- Sources whichever profile applies before surveying, so `MK_SWEEP_LOG`,
  `MK_SWEEP_TAIL` and `MK_SCAN_DEPTH` work even when the root is given as an
  argument.
- Unborn-HEAD safe — checks `git rev-parse --verify -q HEAD` before treating a repo
  as having commits. (`git rev-parse HEAD` on an empty repo prints the literal
  string `HEAD` *and* exits non-zero, which corrupts `$(... || echo fallback)`
  measurements.)
- Prints `no-upstream` and counts those repos separately, so "no tracking branch"
  is never reported as "in sync".
- Expands a leading `~` in the root, since a quoted variable does not undergo
  tilde expansion.
- When nothing resolves it exits 2 and says which directory it searched, rather
  than surveying a guessed root.

## Validation

```bash
bash -n install.sh .agents/skills/mission-kickoff/scripts/*.sh
cd <workspace> && bash .../scripts/profile.sh --status     # expect source=workspace
cd <workspace>/<some-repo> && bash .../scripts/scan-workspace.sh   # walks up to the marker
cd /tmp && bash .../scripts/scan-workspace.sh              # expect exit 2, no guessing
bash .../scripts/profile.sh --list                         # profiled + NO PROFILE rows
grep -rniE '<your own project name>|<internal repo names>' . && echo LEAK || echo clean
```

The leak grep matters more with per-workspace profiles: profiles now live outside
this repo, so a real path appearing *here* means someone pasted one in rather than
configured one. Check the resolution matrix after any change to `profile.sh` — a
resolver bug silently picks the wrong project's board and goals, which is worse
than an error.

A `SKILL.md` change is only really validated by loading it in an agent client and
running a kickoff. Failure modes worth watching: step 4 dispatching without
approval, a worker brief missing the guardrails or the typed `worker_done` command,
and the skill inventing paths when the profile is unset.
