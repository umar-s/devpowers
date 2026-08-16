# devpowers

A product line of Claude Code plugins by [umar-s](https://github.com/umar-s), served from one marketplace. Each plugin lives in its own repository; this repo is a thin catalog that references them — add the marketplace once, install any plugin, get updates as the plugins evolve.

## Plugins

| Plugin | What it does | Repo |
|--------|--------------|------|
| **[research-pipeline](https://github.com/umar-s/research-pipeline)** | Multi-phase parallel research pipeline: decompose a topic → research aspects in parallel → synthesize → quality gate → fully-cited report. Source tiering, slop detection, git-based checkpointing, WebSearch/Exa backends. | [umar-s/research-pipeline](https://github.com/umar-s/research-pipeline) |
| **[loop-foundry](https://github.com/umar-s/loop-foundry)** | Loop-engineering pipeline: applicability filter → YouTrack backlog triage → LOOP_SPECs → gap analysis → runners → staged autonomy ladder (shadow → gated → autonomous). Refuses to build loops where the approach does not apply. | [umar-s/loop-foundry](https://github.com/umar-s/loop-foundry) |
| **[co-rar](https://github.com/umar-s/co-rar)** | CO-RAR — Continuous Resilient Adversarial Reasoning in Codeless Design: diagnostic (N/S/A conditions), seven design principles, adversarial-critic and feedback-loop playbooks for systems that must mutate under pressure. Companion skill for loop-foundry's statistical-gate loops. | [umar-s/co-rar](https://github.com/umar-s/co-rar) |
| **[voxscribe](https://github.com/umar-s/research-pipeline)** | Russian-first audio/video → readable text via faster-whisper on CPU: lecture, dialogue (pyannote diarization) and folder fan-out modes. Idempotent, atomic writes, no-speech guard. Lives in the research-pipeline repo. | [umar-s/research-pipeline](https://github.com/umar-s/research-pipeline) |
| **[md2pdf](https://github.com/umar-s/md2pdf)** | Markdown → presentable PDF without LaTeX: pandoc → house-style HTML (GitHub typography, IBM Plex, A4) → headless Chromium print-to-pdf. Cyrillic everywhere, mushaf-style right-alignment for Arabic quotes, wide tables kept inside the page margin with per-column widths set from Markdown. | [umar-s/md2pdf](https://github.com/umar-s/md2pdf) |
| **[premortem](https://github.com/umar-s/premortem)** | Premortem advisor: finds the concrete ways a plan could fail before commitment — multi-agent silent scan, mitigation triplets, history snapshots, reverse-premortem (Klein 2007 + Kahneman outside view). Fork of [AndyShaman/premortem](https://github.com/AndyShaman/premortem). | [umar-s/premortem](https://github.com/umar-s/premortem) |
| **[task-flow](https://github.com/umar-s/task-flow)** | Three skills, one pipeline: **decompose** → **task** → **ci-gate**. `decompose` cuts an epic/feature/spec into dependency-linked tasks (DoD with truths, story points, graph, parallelism waves); `task` takes one ticket ingest → 2× premortem → TDD → adversarial code-review → conditional security-review → live verify → close; `ci-gate` scaffolds the deterministic merge floor — portable gitleaks secret-scan + tool-agnostic migration-guard + protected-branch — into any GitLab/GitHub repo. | [umar-s/task-flow](https://github.com/umar-s/task-flow) |

## Install

In Claude Code:

```
/plugin marketplace add umar-s/devpowers
/plugin install research-pipeline
/plugin install loop-foundry
/plugin install co-rar
/plugin install voxscribe
/plugin install premortem
/plugin install md2pdf
/plugin install task-flow
```

Or via the CLI:

```bash
claude plugin marketplace add umar-s/devpowers
claude plugin install loop-foundry@devpowers
```

After install, fully restart Claude Code (exit the session and start a new one — slash commands are only registered at session start).

## How this repo works

The catalog (`.claude-plugin/marketplace.json`) references each plugin's own repository via `git-subdir` sources pinned to `ref: main` — no version bookkeeping here. When a plugin repo pushes to `main`, the marketplace serves the new state; each plugin's version lives solely in its own `plugin.json`.

```
devpowers/                            # this repo — catalog only
└── .claude-plugin/marketplace.json   # entries point at external plugin repos

umar-s/research-pipeline              # plugin repo (ships two plugins)
├── plugins/research-pipeline/        # ← git-subdir path
└── plugins/voxscribe/                # ← git-subdir path

umar-s/loop-foundry                   # plugin repo
└── plugins/loop-foundry/             # ← git-subdir path

umar-s/premortem                      # forked plugin repo — plugin at repo root
└── .claude-plugin/plugin.json        # ← plain url source

umar-s/task-flow                      # plugin repo — plugin at repo root
├── .claude-plugin/plugin.json        # ← plain url source
├── skills/{decompose,task,ci-gate}/  # three skills, auto-discovered
└── templates/ci-gate/                # payload the ci-gate skill scaffolds
```

Forked repos are packaged additively: a single `.claude-plugin/plugin.json` is added on top of the upstream layout (with a `skills` path override if the skill does not live under `skills/`), so upstream merges stay conflict-free.

## Adding a plugin to the line

1. Create the plugin in its own repo following the layout above (`plugins/<name>/` with `.claude-plugin/plugin.json`).
2. Add one entry to `.claude-plugin/marketplace.json` here: `name`, `displayName`, `description`, `category`, `homepage`, and a `git-subdir` source with `path: plugins/<name>`, `ref: main`.
3. Validate and push:

```bash
claude plugin validate .
```

Catalog conventions follow [anthropics/knowledge-work-plugins](https://github.com/anthropics/knowledge-work-plugins): lean entries, no version duplication, `displayName` for presentation.

## License

MIT. Each plugin carries its own license in its repository.
