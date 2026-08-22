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
[premortem](https://github.com/umar-s/premortem/releases).

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
