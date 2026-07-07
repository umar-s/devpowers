# devpowers

A product line of Claude Code plugins by [umar-s](https://github.com/umar-s), served from one marketplace. Each plugin lives in its own repository; this repo is a thin catalog that references them — add the marketplace once, install any plugin, get updates as the plugins evolve.

## Plugins

| Plugin | What it does | Repo |
|--------|--------------|------|
| **[research-pipeline](https://github.com/umar-s/research-pipeline)** | Multi-phase parallel research pipeline: decompose a topic → research aspects in parallel → synthesize → quality gate → fully-cited report. Source tiering, slop detection, git-based checkpointing, WebSearch/Exa backends. | [umar-s/research-pipeline](https://github.com/umar-s/research-pipeline) |
| **[loop-foundry](https://github.com/umar-s/loop-foundry)** | Loop-engineering pipeline: applicability filter → YouTrack backlog triage → LOOP_SPECs → gap analysis → runners → staged autonomy ladder (shadow → gated → autonomous). Refuses to build loops where the approach does not apply. | [umar-s/loop-foundry](https://github.com/umar-s/loop-foundry) |

## Install

In Claude Code:

```
/plugin marketplace add umar-s/devpowers
/plugin install research-pipeline
/plugin install loop-foundry
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

umar-s/research-pipeline              # plugin repo
└── plugins/research-pipeline/        # ← git-subdir path

umar-s/loop-foundry                   # plugin repo
└── plugins/loop-foundry/             # ← git-subdir path
```

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
