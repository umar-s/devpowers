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
