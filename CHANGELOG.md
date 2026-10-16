# Changelog

This repository is a **catalog**, not a plugin: it carries no version of its own
and pins no plugin versions — each entry points at a plugin repository's default
branch, and the single source of truth for a plugin's version is that plugin's
own `plugin.json`. So the log below is dated rather than numbered, and there are
no release tags here. Per-plugin release history lives in each plugin's repo:
[task-flow](https://github.com/umar-s/task-flow/releases) ·
[md2pdf](https://github.com/umar-s/md2pdf/releases) ·
[research-pipeline / voxscribe](https://github.com/umar-s/research-pipeline/releases) ·
[loop-foundry](https://github.com/umar-s/loop-foundry/releases) ·
[co-rar](https://github.com/umar-s/co-rar/releases) ·
[prediction-protocol](https://github.com/umar-s/prediction-protocol/releases) ·
[premortem](https://github.com/umar-s/premortem/releases) ·
[statusline](https://github.com/umar-s/claude-statusline/releases).

## 2026-10-16 — loop-foundry 1.2.0 and prediction-protocol 1.2.0: executor per harness, the deny record (S3 of the two-model stack)

- **loop-foundry** entry unchanged in form; the plugin's 1.2.0 release lets a
  loop's executor run in either harness (`claude -p` or `codex exec`, a spec
  field) and makes the verifier the other model through task-flow's
  `xreview.sh` — read-only and isolated, so outside the prediction protocol by
  construction (the verifier's own session of 1.1.0 is gone, and the verifier
  gets no grants: a Claude reviewer has no shell, a Codex one a read-only,
  offline one). Journal fields per role (`executor_model`,
  `verifier_model`), a clean checkout for every tick, a loop checkout that is
  never a trusted Codex project, a Codex executor with `--ignore-rules` and no
  write path to the prediction state. Codex reviewed the release through
  `xreview.sh`; its first round removed a `--add-dir` to that state (the
  model could switch the gate off by a computed path, unseen), a
  command-capable verifier variant and a globbed `PREDICT`; the second moved
  the stream capture out of the executor's reach and the record parsing into
  one shipped parser, `scripts/tick_record.py`, tested on real platform
  records; later rounds turned that parser into a whitelist of observed
  shapes, which also surfaced a second deny the record carries — the state
  guard's refusal of an edit of the protocol's own state; the fifth showed
  no parser can frame Codex's multi-line stderr safely, so the deny moved
  into the tool.
- **prediction-protocol** entry unchanged in form; its 1.2.0 release records
  every deny its hooks issue (class, base64 of the exact command; the state
  guard's refused path; `gate-error`) in the session's state, out of a
  sandboxed model's reach, and `predict status --json` returns them as
  `denies` — loop-foundry's `gate_denies` comes from there. Reviewed by Codex
  on its own over twelve rounds (trailing newlines, damaged lines, an early
  deny, JSON whitespace in the state guard — the last also closed a
  compact-JSON assumption in the guard's path match; recorders that ran
  external processes before a deny printed; one appended file that
  interleaved concurrent long records, now one file per deny; a reader that
  overwrote `gate_seen`). The deny path — both hooks and both libraries the
  gate sources — is pinned whole by sha256 in lint: a pin of a function's text
  or a snapshot after sourcing was each shown bypassable by a redefinition.
- Facts that moved into `docs/claude-codex-stack.md` §1/§9 (rows 24–29): an
  exported `PP_SESSION` keys the gate in `codex exec` (no `--session-id`
  needed); **a hook deny is absent from `codex exec --json`** — it is only in
  Codex's stderr log, the model only in the rollout; `~/.local/state` is
  read-only inside `workspace-write` and must stay so — prediction-protocol
  1.1.0 catches a state write by its literal path only, so a model-writable
  state is a gate the model can switch off; a project's `.codex/` loads only
  when the project is trusted; `claude -p --output-format stream-json` needs
  `--verbose` (the 1.1.0 runner line lacked it), and a CLI under `env -i`
  without the host's proxy variables hangs after `init`; the state guard's
  deny has its own shape on each harness (no version in its marker), and a
  failing command cannot pose as a gate deny in `stream-json` (`Exit code N`
  comes first). The §4.3 plan was
  wrong twice and says so: `PREDICT` is pinned from the executor harness's
  install record, never globbed (`sort -V` over paths orders caches and
  marketplaces before versions — §7.2' had the same bug), and `gate_denies` on
  Codex cannot come from the events. No source or ref change.

## 2026-10-16 — task-flow 1.12.0: two harnesses and cross-review (S2 of the two-model stack)

- **task-flow** entry unchanged in form; the plugin's 1.12.0 release runs the
  three skills in Codex CLI (Harness sections, bindings from `AGENTS.md` or
  `CLAUDE.md`, `ci-gate` no longer reads its payload through a bare
  `${CLAUDE_PLUGIN_ROOT}`) and sends phases 6 / 6b to the model that did not
  write the diff: `templates/xreview/xreview.sh`, headless, read-only by
  construction, isolated from the author's session, with the verdict as a
  separate channel the script renders into the report header. Also: optional
  Codex Security GitLab includes (an LLM layer, not the gate) and
  `templates/agents/` (AGENTS.md / CLAUDE.md skeletons, a read-only reviewer
  role, `git.rules` where a push prompts). The release was reviewed by Codex
  through `xreview.sh` itself — eight rounds, the last `Ready to merge`.
- Facts that moved into `docs/claude-codex-stack.md` §1/§9 (rows 19–23): a
  `claude -p` reviewer runs the hooks and the `apiKeyHelper` of a
  `.claude/settings.json` or `settings.local.json` committed in the diff
  under review unless no settings file loads; `--tools` limits only the
  built-in tools (MCP stays); `codex exec --ignore-user-config` still loads
  user `.rules`, and an `allow` there runs the command outside the read-only
  sandbox; memory plugins replay the author's session into a reviewer (9 and
  4 SessionStart hooks by default); prefix rules match exact tokens; the
  official Codex Security GitLab example cannot run on its own image and
  never fails without a threshold. The §5.3 and §7.4 commands that relied on
  an allowed `git push` and an allowlisted `git diff` are replaced. No
  source or ref change.

## 2026-10-15 — prediction-protocol 1.1.0: the second harness (S1 of the two-model stack)

- **prediction-protocol** entry unchanged in form; the plugin's 1.1.0 release
  closes the Codex gaps the 2026-09-27 spec named: Codex has no PreToolUse
  `ask` (a hook that asks is marked failed and the command runs — observed
  through the new `platform-probe.sh --codex`), so the gate decides the
  harness per call (`turn_id`/`model` on stdin, `PLUGIN_ROOT` in the hook's
  environment, `PP_HARNESS` override) and **denies where it asked**, passing a
  matching receipt silently; file edits arrive as `apply_patch` with the patch
  in `tool_input.command` and the state guard reads its headers; `PREDICT`
  reaches the session as SessionStart `additionalContext` where there is no
  `CLAUDE_ENV_FILE`; `predict` resolves the session from `CODEX_SESSION_ID`
  as well as `CLAUDE_CODE_SESSION_ID`. Facts that moved into
  `docs/claude-codex-stack.md` §1/§9: `codex exec` always runs with approval
  `never` (every exec session is the delegated row; `default` exists only in
  the TUI/app), a Codex started from a Claude Code shell inherits the
  `CLAUDE_*` environment into its hooks and its model's shell, and the hook
  trust hash is reproducible (normalised identity → TOML → sorted JSON →
  SHA-256). No source or ref change.

## 2026-09-27 — docs: Claude Code + Codex, the two-model stack (spec + manual)

- `docs/claude-codex-stack.md` — what was verified today and what the plan is
  for running the line on both harnesses. Verified on this host: Codex CLI
  0.153.4 reads this catalog's `.claude-plugin/marketplace.json` as a
  legacy-compatible marketplace (`codex plugin marketplace add umar-s/devpowers`),
  installs the `git-subdir`/`url` entries into its own cache with the version
  from each plugin's `.claude-plugin/plugin.json`, and lists the skills as
  `plugin:skill` (`task-flow:task`, …) — no second manifest is needed.
  Documented gaps that become plugin releases: Codex does not support
  `permissionDecision: "ask"` (prediction-protocol must deny where it asks),
  `apply_patch` instead of `Edit/Write`, no `CLAUDE_ENV_FILE`, the premortem
  fork's skill outside `skills/` is invisible to Codex (needs a
  `.codex-plugin/plugin.json` overlay), hook trust by hash, the Ubuntu 24.04
  AppArmor userns restriction that stops Codex's bwrap sandbox outside the
  desktop app. The stages (prediction-protocol 1.1.0 → task-flow 1.12.0 →
  loop-foundry 1.2.0 → premortem/co-rar/md2pdf → catalog), the host and
  project setup, the per-ticket duet with cross-model review and the runner
  variant are written as step-by-step commands; the acceptance list names
  what a live Codex session still has to confirm.
- README: "Install → in Codex CLI". No source or ref change.

## 2026-08-24 — statusline moves to its own repository (1.0.2)

- The entry now points at **`umar-s/statusline`** (`plugins/statusline`,
  `ref: main`). 1.0.0 and 1.0.1 were served from a GitHub *fork* of
  `AndyShaman/claude-statusline` — a form chosen here without asking, which put
  the owner's own work under someone else's repository, history and README. It
  is a status line written for its own sake that reuses parts of upstream's
  script, so the licence obligation is met the ordinary way instead: both MIT
  notices in the repo's `LICENSE`, an itemised `NOTICE.md`, and a description
  that says "parts of the script come from …" rather than "fork of …".
- Tags in that repo follow the normal `vX.Y.Z` scheme (the fork's
  `plugin-vX.Y.Z` tags belonged to the fork convention).

## 2026-08-24 — statusline 1.0.1: the command is `/statusline:setup`

- Plugin commands are registered under a `plugin-name:command` namespace, so
  1.0.0's `commands/statusline.md` became `/statusline:statusline` — while bare
  `/statusline`, which the catalog entry and every document named, is **Claude
  Code's own built-in command**: it reports on the status line and never reaches
  the plugin. Renamed to `/statusline:setup` in plugin 1.0.1; the entry and the
  README row here now name the namespaced form. No source or ref change.

## 2026-08-23 — statusline added

- New entry **statusline** (`umar-s/claude-statusline`, `plugins/statusline`,
  `ref: main`): the owner's status line packaged as a plugin — model, context
  bar, 5-hour and 7-day limits, project, branch, MCP count, session time.
  The repo is a **fork** of `AndyShaman/claude-statusline` (MIT), so upstream's
  root files stay untouched and the plugin's releases are tagged
  `plugin-vX.Y.Z`, like `premortem`. Claude Code takes its main `statusLine`
  from `settings.json` only, so the plugin ships `/statusline install`, which
  writes a version-agnostic launcher and refuses to replace a `statusLine` it
  did not write. First release `plugin-v1.0.0`.
- README: badge count corrected to 9 (it still said 7 after
  prediction-protocol), table row, install list and repo tree.

## 2026-08-23 — docs: how the line works

- `docs/how-the-line-works.md` — a manual of the line as of task-flow 1.11.0,
  prediction-protocol 1.0.3, loop-foundry 1.1.0, co-rar 1.0.1: who calls whom,
  the cross-cutting invariants, every phase of `decompose` / `task` / `ci-gate`,
  the gate matrix of prediction-protocol, loop-foundry's filter, spec, runner
  contract and ladder, co-rar's diagnostic and principles, a usage section
  with the actual commands and prompts (project bindings, `/decompose` →
  `/task`, a headless `claude -p` run, a ticket pool fed to loop-foundry so
  each ticket runs through `task`, the operator's acts), the August 2026
  chronology and the known traps. No source or ref change.

## 2026-08-22 — loop-foundry 1.1.0 names its companion

- **loop-foundry** description (table and catalog entry) now names
  prediction-protocol as the companion: receipts for one-way commands in every
  tick, required past shadow. Plugin release v1.1.0 carries the contract
  (`references/predictions.md`); prediction-protocol v1.0.2 carries the plugin
  side (loop operator-only `ack`/`withdraw`/`off`, `ungated` counted, state
  guard by path). No source or ref change.

## 2026-08-22 — prediction-protocol added

- New entry **prediction-protocol** (`umar-s/prediction-protocol`,
  `plugins/prediction-protocol`, `ref: main`): a fail-closed PreToolUse gate on
  one-way shell commands plus a `predict` CLI that grades HIT / MISS /
  INCONCLUSIVE itself; consumers call `"${PREDICT:?}" on`. First release
  v1.0.0. README table and install list updated.

## 2026-08-17

- **task-flow** entry rewritten for 1.7.0: the declared blast-radius tier
  (ceremony scales, gates don't), the diff-scoped mutation check, the
  changed-line coverage layer in `ci-gate`, and the evidence block that closes a
  ticket with numbers and a reproduction command.

## 2026-08-16

- **task-flow** entry corrected to describe three skills — `decompose` had been
  missing from the catalog since it shipped in 1.2.0.

## 2026-07-30

- **md2pdf** added to the line: Markdown → presentable PDF without LaTeX
  (pandoc → house-style HTML → headless Chromium), Cyrillic and Arabic/RTL.

## 2026-07-17

- **task-flow** added to the line: per-task quality flow plus the deterministic
  `ci-gate` it lands behind.

## 2026-07-07

- **devpowers** created as the umbrella marketplace for the product line, with
  catalog conventions borrowed from `anthropics/knowledge-work-plugins`:
  concise entries, no duplicated versions, one repository per plugin.
- **research-pipeline**, **voxscribe**, **loop-foundry**, **co-rar** and
  **premortem** (a fork of `AndyShaman/premortem`, packaged additively) listed
  as the initial line-up.
