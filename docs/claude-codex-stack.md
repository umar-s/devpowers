# Двухмодельный стек: Claude Code + Codex (GPT-6 Astra) — спека и мануал

Состояние на 2026-09-27. Проверено на этом хосте: Codex CLI **0.153.4** (бандл
ChatGPT-десктопа, `/usr/lib/chatgpt/resources/codex`), Claude Code **2.1.283**,
Codex Security CLI **0.1.31**; плагины линейки — task-flow 1.11.0,
prediction-protocol 1.0.3, loop-foundry 1.1.0, co-rar 1.0.1, premortem 1.0.0,
md2pdf 1.3.0. Официальный мануал Codex (learn.chatgpt.com, 41k строк) прочитан
по разделам plugins / hooks / skills / AGENTS.md / rules / exec / review /
Security CLI / GitLab.

Пометки в тексте: **✅** — проверено сегодня руками; **🔧 S<n>** — делается на
этапе n (§4); **⚠** — документировано, но на этом хосте не воспроизведено —
пункт приёмки (§10). Документ одновременно спека этапов и мануал; где он
разойдётся со `SKILL.md`/`references/` плагина — прав плагин.

---

## 0. Вывод коротко

1. **Совместимость почти бесплатна.** Codex читает `.claude-plugin/marketplace.json`
   devpowers как есть (`codex plugin marketplace add umar-s/devpowers` ✅),
   ставит плагины по `git-subdir`-источникам в свой кэш ✅, находит скиллы
   `SKILL.md` под `skills/` ✅ и грузит `hooks/hooks.json` плагина по тому же
   JSON-контракту, что Claude Code (событие, `matcher`, `hookSpecificOutput`,
   exit 2 + stderr). Формат скиллов общий (agentskills.io). Второй манифест
   не нужен; исключение — premortem (скилл не под `skills/`) — ему нужен
   3-строчный оверлей `.codex-plugin/plugin.json` ✅.
2. **Что реально нужно портировать** — четыре вещи, все маленькие:
   `permissionDecision: "ask"` в Codex **не поддерживается** (хук помечается
   failed, команда *выполняется*) → гейт prediction-protocol на Codex должен
   отвечать `deny` там, где на Claude спрашивал; `apply_patch` вместо
   `Edit/Write` (стейт-гард парсит патч, не `file_path`); нет `CLAUDE_ENV_FILE`
   (PREDICT доезжает через `additionalContext` + glob по кэшу); скиллы
   зовутся `$plugin:skill`, а не `/plugin:skill`, и «subagent через Agent tool»
   надо переформулировать в термины Codex (`spawn a subagent` /
   `.codex/agents/*.toml`) — либо, что лучше, отдать ревью другой модели.
3. **Схема Architect/Critic + Builder — да, но с двумя поправками.**
   (а) Роли назначаются **на тикет по tier/типу**, а не намертво по модели:
   инвариант линейки — «ревьюер ≠ автор», а не «Claude всегда думает, Codex
   всегда кодит». Жёсткое закрепление ролей сжигает половину одной подписки
   и делает вторую единой точкой отказа (лимит Codex → стройка встала).
   (б) **Оркестратор — раннер (shell/cron), а не интерактивная сессия одной
   модели.** Поверхность передачи между моделями — файлы в репо + git + трекер
   (`<TASK>.spec.md`, evidence block, MR, `REFUTED.md`) — это уже есть в
   task-flow; ничего «agent-to-agent» строить не надо. Claude готовит пул и
   спеки, раннер гоняет тики `codex exec`/`claude -p`, ревью — перекрёстное.
   Практическая причина: из интерактивной Claude-сессии в auto-режиме
   классификатор **запрещает** запуск `codex exec` с правом записи (получил
   отказ «Create Unsafe Agents» ✅), а из песочницы Claude вложенная
   песочница Codex (bwrap) не стартует. Раннер ни того, ни другого не имеет.
4. **Гетерогенное ревью — самая дешёвая и самая ценная часть.** Ничего не
   строить: `codex exec review --base <ветка>` (штатный ревьюер Codex +
   `## Code Review Rules` из AGENTS.md) и `claude -p` с бриф-шаблоном
   `code-review-prompt.md` из task-flow в read-only. Два детерминированных
   пола (ci-gate) + два LLM-прохода (task 6b одной моделью, Codex Security
   другой). Codex Security в GitLab CI — по **API-ключу** (отдельный счёт,
   не подписка) либо ChatGPT-логин раннер-пользователя на приватном
   self-hosted GitLab — выбор за вами (§6.3).
5. **Две ловушки хоста.** Ubuntu 24.04: `kernel.apparmor_restrict_unprivileged_userns=1`
   — Codex CLI вне десктоп-приложения не может поднять bwrap
   (`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted` ✅);
   лечится AppArmor-профилем для бинаря `codex`, по образцу штатного
   `/etc/apparmor.d/chatgpt` (§5.1, нужен sudo). И: хуки плагина в Codex не
   работают, пока вы их не «доверили» через `/hooks`; доверие — по хэшу
   определения, т.е. **после каждого обновления плагина — снова** (раннер
   вместо этого передаёт `--dangerously-bypass-hook-trust`, потому что он
   сам установил плагин и отвечает за источник).

---

## 1. Что проверено сегодня (факты, не документация)

| # | Факт | Как проверено |
|---|---|---|
| 1 | Codex читает `.claude-plugin/marketplace.json` как «legacy-compatible marketplace»; все 9 записей devpowers видны в `codex plugin list --available --json` | изолированный `CODEX_HOME`, `marketplace add /home/…/devpowers` и `marketplace add umar-s/devpowers` (git) ✅ |
| 2 | `codex plugin add <name>@devpowers` ставит `git-subdir`- и `url`-источники в `$CODEX_HOME/plugins/cache/devpowers/<plugin>/<version>/`, версия берётся из `.claude-plugin/plugin.json` | task-flow 1.11.0, prediction-protocol 1.0.3, premortem 1.0.0, co-rar 1.0.1, loop-foundry 1.1.0, md2pdf 1.3.0 ✅ |
| 3 | Скиллы плагинов видны модели как `plugin:skill` с абсолютным путём к `SKILL.md`: `task-flow:task`, `task-flow:decompose`, `task-flow:ci-gate`, `prediction-protocol:prediction-protocol`, `loop-foundry:loop-foundry`, `co-rar:co-rar`, `md2pdf:md2pdf` | `codex exec -s read-only` «перечисли скиллы» ✅ |
| 4 | premortem (скилл в `./premortem/`, манифест `skills: ["./"]`) Codex **не** видит; симлинк `skills/premortem → ../premortem` не помогает; оверлей `.codex-plugin/plugin.json` с `"skills": "./premortem/"` — помогает | lab-маркетплейс с двумя вариантами ✅ |
| 5 | Хуки: тот же контракт, что в Claude Code — события `PreToolUse/PostToolUse/SessionStart/…`, `matcher` по имени тула (`Bash`; `apply_patch` откликается на `Edit\|Write`), stdin с `session_id/transcript_path/cwd/permission_mode/tool_name/tool_use_id/tool_input.command`, deny = `hookSpecificOutput.permissionDecision:"deny"` или exit 2 + stderr; плагинный `hooks/hooks.json` подхватывается по умолчанию; хук получает `PLUGIN_ROOT`/`PLUGIN_DATA` **и** `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` | официальный мануал (раздел Hooks) — живой прогон заблокирован классификатором, см. §10 ⚠ |
| 6 | `permissionDecision: "ask"`, `continue`, `stopReason` для PreToolUse **не поддерживаются**: hook run = failed, tool call продолжается | мануал, дословно ⚠ (следствие для гейта — §4.1) |
| 7 | `codex exec` не принимает `-a`; политика — `-c approval_policy=never` или профиль `-p <name>` (`$CODEX_HOME/<name>.config.toml`); stdin не-TTY → «Reading additional input from stdin» и ожидание EOF — в скриптах всегда `</dev/null` | ✅ (два зависших прогона) |
| 8 | `codex exec review --base <branch>` несовместим с позиционным промптом; кастомные инструкции — либо без `--base` (сам берёт `git diff`), либо через `## Code Review Rules` в AGENTS.md | ✅ |
| 9 | Песочница Codex (bwrap) на этом хосте падает: `kernel.apparmor_restrict_unprivileged_userns = 1`, профиль есть только у `/usr/lib/chatgpt/ChatGPT` (`flags=(unconfined) { userns, }`), у бинаря `codex` — нет | `codex sandbox linux -- echo` ✅; `use_legacy_landlock` — deprecated и сломан (panic) ✅ |
| 10 | `codex mcp-server` работает, но помечен deprecated («use the app server»); инструменты `codex` / `codex-reply` | probe по stdio ✅ — в стек **не** берём |
| 11 | `/import` в Codex CLI и Settings → Import в десктопе импортируют из Claude Code: `CLAUDE.md`→`AGENTS.md`, `settings.json`→`config.toml`, скиллы, плагины, хуки, MCP, subagents | мануал (Import from another agent) ⚠ |
| 12 | Codex Security CLI: `npx @openai/codex-security@0.1.31`, команды `scan --diff BASE --head HEAD`, `--working-tree`, `--fail-on-severity`, `--auth chatgpt\|api-key`, `export --export-format sarif`, exit 0/1/2; `--dry-run` требует чистого дерева | ✅ dry-run; сам скан — ⚠ (нужен доступ Codex Security / Trusted Access for Cyber на аккаунте) |
| 13 | В auto-режиме Claude Code классификатор отказывает в `codex exec -s workspace-write` и в `--dangerously-bypass-hook-trust` («Create Unsafe Agents»); read-only `codex exec` разрешён | ✅ |

---

## 2. Архитектура

### 2.1 Роли — на тикет, не на модель

```
                 пул тикетов / эпик
                        │
                 decompose (Claude)  ── спеки, DoD, волны, REFUTED.md
                        │
            ┌───────────┴───────────┐
       tier T1/T2, type routine   tier T3, архитектурные, hook/CI-файлы
            │                       │
     builder = Codex (Astra)   builder = Claude (Fable/Opus)
     reviewer = Claude         reviewer = Codex (+ Codex Security)
            └───────────┬───────────┘
                        │
       MR → GitLab CI: ci-gate (детерминированный пол) + codex-security (2-й security-pass)
                        │
                 merge (человек или гейтированный раннер)
```

- Инвариант — тот же, что в task-flow фазах 6/6b: **ревьюер не автор, чистый
  контекст, артефакты вместо транскрипта**. Другая модель другого вендора —
  самая сильная форма этой независимости (другие данные, другие привычки
  инструментов, другие слепые пятна).
- Назначение по умолчанию: T1/T2 «рутина» → Codex строит (headless-дружелюбен,
  своя песочница, дешевле по вашей квоте Claude), Claude ревьюит.
  T3/архитектура/правки CI, хуков, скиллов → Claude строит (линейка и её хуки
  доказаны на нём), Codex ревьюит + Security. Назначение — поле в тикете
  (`builder: codex|claude`), не догма; при лимите одной подписки роли
  меняются, флоу не меняется.
- **Ни одна модель не оценивает свою работу**: evidence block пишет автор,
  вердикт — ревьюер и детерминированные гейты (принцип loop-foundry §3).

### 2.2 Поверхность передачи — файлы, git, трекер

| Артефакт | Кто пишет | Кто читает | Уже есть |
|---|---|---|---|
| `docs/decompose/<epic>.md`, тикеты в трекере | decompose (Claude) | builder любой модели | task-flow |
| `docs/specs/<TASK>.spec.md` (DoD → check table, premortem edges) | builder, фаза 1 | reviewer (слоты бриф-шаблона) | task-flow |
| ветка `feature/<TASK>` + MR | builder | reviewer, CI | git |
| `docs/reviews/<TASK>-<sha>-<model>.md` | reviewer другой модели | builder (fix(review): …) | 🔧 S2 |
| `docs/evidence/<TASK>.md`, `REFUTED.md` | `predict` (CLI) | оба | prediction-protocol |
| `loops/journal/<loop>.jsonl` | раннер | оператор | loop-foundry |

Никакого MCP «модель → модель»: `codex mcp-server` deprecated, а связь через
файлы переживает смену любой из моделей и читается человеком.

### 2.3 Оркестратор — раннер

Интерактивно вы работаете в **одной** из двух TUI и зовёте скилл
(`/task-flow:task` в Claude, `$task-flow:task` в Codex); вторая модель
приходит как ревьюер через `xreview.sh` (🔧 S2) — короткий headless-вызов из
скилла или из терминала. Пакетно — раннер loop-foundry, где исполнитель
тика — `codex exec` **или** `claude -p`, верификатор — другая модель
(🔧 S3). Причины не «оркестрировать из сессии Claude»: классификатор
auto-режима (факт 13) и вложенные песочницы; причина не оркестрировать из
сессии Codex: то же самое зеркально (`claude -p --dangerously-skip-permissions`
изнутри Codex-песочницы — плохая идея).

### 2.4 Слои защиты (сохраняем аксиому task-flow: два независимых слоя)

| Слой | Claude Code | Codex | Природа |
|---|---|---|---|
| prediction-protocol (PreToolUse, квитанции на one-way) | ✅ | 🔧 S1 (deny вместо ask) | fail-closed, недетерминирован по содержанию, детерминирован по механике |
| Песочница платформы | Claude sandbox / permission mode | `read-only` / `workspace-write` (сеть off по умолчанию, `.git` и `.codex` read-only) + execpolicy `.rules` | детерминированная |
| ci-gate (gitleaks, migration-guard, unicode-guard, diff-coverage) | ✅ | ✅ (в CI модель не участвует) | детерминированная |
| LLM-ревью (task 6/6b) | своё или другой модели | своё или другой модели | gameable, коррелирует с автором → поэтому **другая модель** |
| Codex Security (CI, `--diff`) | — | ✅ второй security-pass | LLM + валидация PoC |

---

## 3. Матрица совместимости плагинов

| Плагин | Компоненты | На Codex сегодня | Что меняется | Этап |
|---|---|---|---|---|
| **prediction-protocol** | hooks (PreToolUse×2, PostToolUse, SessionStart), CLI `bin/predict`, skill | хуки грузятся (после trust) ⚠, но `ask` → failed → **команда выполняется** — на Codex гейт сегодня fail-open в двух клетках таблицы; `PREDICT` не экспортируется (нет `CLAUDE_ENV_FILE`); стейт-гард не видит `apply_patch` | `ask`→`deny` на Codex; `apply_patch`-парсер; SessionStart `additionalContext`; glob по обоим кэшам в SKILL; таблица платформы Codex в `hook-engineering.md`; фикстуры Codex в `tests/run.sh`; `platform-probe.sh --codex` | **S1 → 1.1.0** |
| **task-flow** | 3 skills, `templates/ci-gate`, scripts | скиллы видны ✅; `ROOT` резолвится по пути SKILL.md (fallback уже есть) ✅; «Agent tool / subagent» и `/task` — Claude-термины | раздел Harness в 3 SKILL.md; фазы 6/6b: перекрёстное ревью как предпочтительный dispatch; `references/cross-review.md`; `templates/xreview/xreview.sh`; `templates/ci-gate/gitlab/codex-security.gitlab-ci.yml`; `templates/agents/` (AGENTS.md-скелет, `.codex/agents/reviewer.toml`, `.codex/rules/git.rules`); bindings читаются из `AGENTS.md`/`CLAUDE.md` | **S2 → 1.12.0** |
| **loop-foundry** | skill + references | скилл виден ✅; контракт раннера завязан на `claude -p --session-id` | `predictions.md`/`ladder.md`/SKILL: executor/verifier per harness (`codex exec -p builder --dangerously-bypass-hook-trust` + `PP_ENTRYPOINT=headless`), `PREDICT` по обоим кэшам, `gate_denies` из событий Codex, поле `model` на роль, гетерогенный verifier как норма | **S3 → 1.2.0** |
| **premortem** (форк) | skill в `./premortem/` | **не виден** ✅ | оверлей `.codex-plugin/plugin.json` (`skills: "./premortem/"`) — аддитивная упаковка, README форка не трогаем | **S4 → 1.0.1** |
| **co-rar** | skill | виден ✅, чистая рамка | одна строка в README/SKILL: `$co-rar:co-rar` | **S4 → 1.0.2** |
| **md2pdf** | skill + scripts | виден ✅; в Quick start захардкожен `~/.claude/skills/md2pdf/scripts/md2pdf.py` — на Codex путь другой | путь относительно SKILL.md (`<dir of SKILL.md>/scripts/md2pdf.py`) | **S4 → 1.3.1** |
| **devpowers** (каталог) | marketplace.json, README, docs | читается ✅ | README «Install → Codex», этот документ, CHANGELOG; второй манифест `.agents/plugins/marketplace.json` **не нужен** | **S0/S5** |
| **research-pipeline** | skills, `agents/*.md` (Claude subagents), `commands/`, `workflows/` | скиллы загрузятся; агенты — Claude-формат, у Codex агенты — `.codex/agents/*.toml` на уровне проекта, не плагина | отдельный этап: генерация `.codex/agents/*.toml` в проект пользователя + harness-раздел в manager-research | отложено (S6) |
| **voxscribe** | skills + python scripts | должен работать (скрипты запускаются из shell) | «fan out to subagents» → harness-заметка | отложено (S6) |
| **statusline** | Claude `statusLine` | **N/A** — у Codex TUI нет такого контракта | ничего; в README пометка «Claude Code only» | S5 |

---

## 4. Что меняется по этапам (спека)

Порядок — по CLAUDE.md каталога: плагин → каталог → потребители. Каждый этап
— свой релиз по ритуалу (supply-chain self-check, бамп, CHANGELOG через
`Edit`, аннотированный тег, `gh release create --verify-tag`); task-flow —
через PR + `gh pr merge --auto --squash` (защищённый main, локальный CLAUDE.md).

### 4.1 S1 — prediction-protocol 1.1.0: «второй харнесс»

- `lib/common.sh`: `pp_harness()` → `claude|codex` — приоритет `PP_HARNESS`
  (env оператора), затем `PLUGIN_DATA` в окружении (Codex-only) или поле
  `model` в stdin (Codex-specific extension), иначе `claude`. `pp_mode()`
  без изменений: `PP_ENTRYPOINT=headless` ставит раннер; Codex TUI/десктоп —
  `interactive`; `pp_delegated` уже читает `permission_mode` из stdin
  (`dontAsk`/`bypassPermissions` в Codex приходят полем, транскрипт не нужен).
- `hooks/predict-gate.sh`: `ask()` на Codex → `deny` с тем же текстом плюс
  «this harness cannot ask (PreToolUse `ask` is unsupported in Codex);
  run the command yourself from a plain shell, or `predict on` + a receipt».
  Обе клетки таблицы (вне протокола интерактивно; с квитанцией интерактивно)
  становятся deny/silent соответственно: **с квитанцией — silent pass**
  (квитанция и есть свидетель, как в делегированной сессии), **без —
  deny**. Слово `allow` по-прежнему не появляется.
- `hooks/predict-state-guard.sh`: `tool_name == apply_patch` → пути из
  `*** Add File:` / `*** Update File:` / `*** Delete File:` / `*** Move to:`
  внутри `tool_input.command`; та же проверка на `…/prediction-protocol/sessions/`.
- `hooks/session-env.sh`: если `CLAUDE_ENV_FILE` не задан и харнесс Codex —
  печатать `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"prediction-protocol: PREDICT=<abs path>; export it before calling predict"}}`.
- `SKILL.md` «Resolve the CLI once»: fallback-glob по обоим кэшам
  (`~/.codex/plugins/cache/*/prediction-protocol/*/bin/predict`,
  `~/.claude/plugins/cache/*/prediction-protocol/*/bin/predict`, `sort -V | tail -1`);
  таблица контекстов получает строку Codex; заметка про `/hooks` trust.
- `references/hook-engineering.md`: вторая таблица платформы «Codex 0.153.x
  (документировано / проверено)», раздел trust, `--dangerously-bypass-hook-trust`
  для раннеров, `PLUGIN_ROOT`, отсутствие `CLAUDE_ENV_FILE`.
- `tests/run.sh`: фикстуры со `"model":"gpt-6-astra"` (→ deny там, где
  Claude ask), `apply_patch` в стейт-гарде, `PP_HARNESS=codex` override;
  `tests/platform-probe.sh --codex`: канарейка через
  `codex exec --dangerously-bypass-hook-trust -s workspace-write` в пустом репо
  (force-push в пустой origin должен быть denied) — запускается **вами**
  (классификатор auto-режима мне это не даёт).
- Версия 1.1.0 (`plugin.json` + `PP_VERSION`), CHANGELOG, тег, релиз;
  каталог — запись в CHANGELOG devpowers.

### 4.2 S2 — task-flow 1.12.0: «dual-harness + cross-review»

- Каждый `SKILL.md` получает раздел **Harness** (≤ 12 строк): имя вызова
  (`/task-flow:task` ↔ `$task-flow:task`), где лежит `ROOT` (уже есть
  fallback по пути SKILL.md), что означает «fresh subagent» в каждом харнессе
  (Claude: Agent tool; Codex: `spawn a subagent`/`.codex/agents/reviewer.toml`,
  read-only), и что предпочтительный независимый ревьюер — **другая модель**.
- `task` фазы 6/6b: dispatch-варианты дополняются `xreview` (другая модель,
  headless, read-only) как первым выбором при наличии второго CLI; правило
  «модель не слабее сессии» остаётся; вердикт `Reviewed: <sha>` и
  `docs/reviews/<TASK>-<sha>-<model>.md` в evidence block.
- `references/cross-review.md`: команды обеих направлений (§7.4), слоты
  бриф-шаблона, что делать с расхождениями двух ревью (независимое совпадение
  = приоритет; расхождение = тикет ревьюеру-человеку, не «усреднение»).
- `templates/xreview/xreview.sh`: заполняет `code-review-prompt.md` из
  `<TASK>.spec.md` и git-диапазона, запускает `codex exec -p reviewer -` или
  `claude -p …` (read-only tools), пишет отчёт в `docs/reviews/`, exit 0/1/2.
- `templates/ci-gate/gitlab/codex-security.gitlab-ci.yml`: scan-only джобы
  `codex-security` + `codex-security-gate` по официальному шаблону (MR между
  защищёнными ветками, `GIT_DEPTH: 0`, `--diff <merge-base> --head $CI_COMMIT_SHA`,
  SARIF в `reports: sarif`, exit-код в отдельном гейте), вариант для
  shell-раннера (без `image:`, node из хоста) — ci-gate SKILL шаг «second
  security pass (optional)».
- `templates/agents/`: `AGENTS.md.skeleton` (bindings task-flow + `## Code Review Rules`),
  `CLAUDE.md.skeleton` (`@AGENTS.md` + Claude-специфика),
  `.codex/config.toml.skeleton`, `.codex/agents/reviewer.toml`,
  `.codex/rules/git.rules`.
- Bindings: «read the project's `CLAUDE.md`» → «the project's instruction
  file: `AGENTS.md` (Codex, and the recommended single source) or `CLAUDE.md`».
- README.md ↔ README.ru.md lockstep, `scripts/lint.sh`, `release-check.sh`, PR.

### 4.3 S3 — loop-foundry 1.2.0: «executor per harness»

- `references/predictions.md`, runner contract: строка исполнителя становится
  вариантной —
  `PP_ENTRYPOINT=headless codex exec -p builder -C "$CHECKOUT" --dangerously-bypass-hook-trust --json -o "$TICK/last.md" - < "$TICK/executor.prompt" > "$TICK/executor.jsonl"`
  или прежний `claude -p --session-id "$PP_SESSION"`; `PREDICT` — glob по
  обоим кэшам; `gate_denies` — grep `prediction-protocol v` по событиям
  Codex (`item.completed` / `command_execution`), не только по stream-json Claude.
- `ladder.md`: поле `model` журнала — на роль (`executor_model`,
  `verifier_model`); гетерогенный verifier — норма для gated и выше;
  «смена версии модели» → демоушен считается по каждой роли.
- `loop-spec.md` §3.1: «отдельная сессия/модель» → «другая модель, если
  доступна» с явным полем. `gaps.md`: канарейка платформы для Codex, trust
  хуков у раннер-пользователя, AppArmor-профиль на раннер-хосте, `codex login`
  раннер-пользователя (auth.json как пароль).
- `SKILL.md` фаза 5: генерируемый раннер выбирает исполнителя из спеки §4.

### 4.4 S4 — premortem 1.0.1, co-rar 1.0.2, md2pdf 1.3.1

- premortem: `.codex-plugin/plugin.json` с `name/version/description/author`
  и `"skills": "./premortem/"` — только наши файлы, апстрим не трогаем.
- co-rar: строка про `$co-rar:co-rar` в README/SKILL.
- md2pdf: путь скрипта относительно SKILL.md; заметка про зависимости
  (pandoc, Chromium) — они хостовые, а не харнесса.

### 4.5 S0/S5 — devpowers

- S0 (этот коммит): документ, CHANGELOG-запись, README «Install → in Codex».
- S5 (после S1–S4): README-матрица «Claude Code / Codex», пометка statusline
  «Claude Code only», описания записей с именами `$plugin:skill`.

---

## 5. Пошагово: хост (один раз)

### 5.1 Codex CLI из терминала

```bash
# 1. бинарь десктоп-бандла в PATH (или поставьте standalone CLI: chatgpt.com/codex/install.sh → ~/.local/bin/codex)
ln -sfn /usr/lib/chatgpt/resources/codex ~/.local/bin/codex
codex --version                        # codex-cli 0.153.4
sudo apt install ripgrep               # codex doctor: "search command could not be verified" — rg нужен модели

# 2. песочница: Ubuntu 24.04 запрещает userns непрофилированным бинарям — дать codex тот же профиль, что у ChatGPT
sudo tee /etc/apparmor.d/codex-cli >/dev/null <<'APP'
abi <abi/4.0>,
include <tunables/global>

profile codex-cli "/usr/lib/chatgpt/resources/codex" flags=(unconfined) {
  userns,
  include if exists <local/codex-cli>
}
APP
sudo apparmor_parser -r /etc/apparmor.d/codex-cli
codex sandbox linux -- echo SANDBOX_OK   # ожидание: SANDBOX_OK (сегодня: bwrap: loopback: Failed RTM_NEWADDR)  ⚠
codex doctor
```

Без профиля Codex CLI **не выполнит ни одну команду** ни в `read-only`, ни в
`workspace-write` (обе идут через bwrap); работал бы только
`--dangerously-bypass-approvals-and-sandbox`, что для билдера неприемлемо.
Альтернатива системная (`sysctl kernel.apparmor_restrict_unprivileged_userns=0`)
ослабляет весь хост — не рекомендую.

### 5.2 Маркетплейс и плагины в Codex

```bash
codex plugin marketplace add umar-s/devpowers            # ✅ читает .claude-plugin/marketplace.json
codex plugin add task-flow@devpowers
codex plugin add prediction-protocol@devpowers
codex plugin add loop-foundry@devpowers
codex plugin add co-rar@devpowers
codex plugin add md2pdf@devpowers
codex plugin add premortem@devpowers                     # скилл появится с premortem 1.0.1 (S4)
codex plugin list
```

Затем **в интерактивном Codex**: `/hooks` → просмотреть хуки prediction-protocol
(4 определения: `session-env.sh`, `predict-gate.sh`, `predict-state-guard.sh`,
`predict-fired.sh`) → Trust. Новая сессия. Проверка: `/skills` показывает
`task-flow:task` и остальные; `$prediction-protocol:prediction-protocol` в
промпте подхватывает скилл.

Обновление плагина после релиза: `codex plugin marketplace upgrade devpowers`
и повторный `codex plugin add <name>@devpowers` (кэш версионный:
`…/cache/devpowers/<plugin>/<version>/`) ⚠; после обновления — снова `/hooks`
→ Trust (хэш изменился).

### 5.3 Личные настройки Codex

`~/.codex/AGENTS.md` — ваш глобальный `~/.claude/CLAUDE.md` (те же правила
работы: автономность, память, санитизация). Быстрый путь — `/import` в Codex
CLI (Claude Code → выбрать instruction files, skills, MCP) ⚠; ручной —
скопировать текст, убрав Claude-специфику (имена тулов, `/compact`).

`~/.codex/config.toml` — добавить (не заменяя ваши секции):

```toml
project_doc_fallback_filenames = ["CLAUDE.md"]   # репо только с CLAUDE.md читается как AGENTS.md

[sandbox_workspace_write]
network_access = true                             # builder: git push / glab / pip — иначе каждая сеть = escalation
```

Профили ролей (`-p <name>` в `codex exec`):

```toml
# ~/.codex/builder.config.toml
model = "gpt-6-astra"
model_reasoning_effort = "high"
approval_policy = "never"          # headless: что не разрешено — падает, а не висит
sandbox_mode = "workspace-write"

# ~/.codex/reviewer.config.toml
model = "gpt-6-astra"
model_reasoning_effort = "xhigh"
approval_policy = "never"
sandbox_mode = "read-only"
```

Правила эскалации (`~/.codex/rules/git.rules`, Starlark): в `workspace-write`
`.git/` защищён как read-only, т.е. `git commit`/`git push` требуют
эскалации; под `approval_policy = "never"` без правила они просто падают.
Разрешаем ровно эти префиксы **вне** песочницы — one-way остаётся за гейтом
prediction-protocol (PreToolUse срабатывает раньше execpolicy):

```python
prefix_rule(pattern=["git", "commit"], decision="allow", justification="builder commits; .git is read-only inside the sandbox")
prefix_rule(pattern=["git", "push"],   decision="allow", justification="plain push; --force is denied by the prediction gate without a receipt")
prefix_rule(pattern=["glab", "mr", "create"], decision="allow", justification="the builder opens the MR")
```

```bash
codex execpolicy check --pretty --rules ~/.codex/rules/git.rules -- git push --force origin main   # allow по правилу — и deny гейтом ⚠
```

### 5.4 Сторона Claude Code

Ничего нового не ставится. Для headless-ревью используется существующее:
`claude -p` с `--allowedTools`/`--disallowedTools`, промпт из stdin,
`--output-format text|json`. Auto-режим для оркестрации Codex **не годится**
(факт 13) — оркестрирует раннер.

---

## 6. Пошагово: проект (один раз на репозиторий)

### 6.1 Инструкции: один источник — `AGENTS.md`

```
AGENTS.md            # полный текст правил проекта (то, что сейчас в CLAUDE.md) + "## Code Review Rules"
CLAUDE.md            # @AGENTS.md  + только Claude-специфика (плагинные скиллы Claude, имена MCP, /compact-политика)
```

Codex читает `AGENTS.md` (цепочка: `~/.codex/AGENTS.md` → корень → cwd, лимит
32 KiB `project_doc_max_bytes`); Claude Code разворачивает `@AGENTS.md` при
загрузке `CLAUDE.md`. Сегодняшняя схема ваших репо (AGENTS.md-указатель «прочитай
CLAUDE.md», либо симлинк `AGENTS.md → CLAUDE.md`) работает, но стоит вызова
инструмента на каждую сессию Codex и не даёт `Code Review Rules`. Переворот —
одноразовый `git mv CLAUDE.md AGENTS.md` + новый `CLAUDE.md` из двух строк.

`## Code Review Rules` в AGENTS.md — то, что штатный ревьюер Codex
(`codex exec review`, `@codex review` в GitLab-облаке) применяет и цитирует:
2–3 инварианта проекта с «safe path», не стиль/линт (это в CI).

### 6.2 `.codex/` проекта (грузится только для trusted project)

```toml
# .codex/config.toml
[plugins."prediction-protocol@devpowers"]
enabled = true
[plugins."task-flow@devpowers"]
enabled = true
[agents]
max_concurrent_threads_per_session = 4
```

```toml
# .codex/agents/reviewer.toml — «fresh reviewer subagent» из task фазы 6, если ревьюит сам Codex
name = "reviewer"
description = "Read-only adversarial reviewer for task-flow phase 6/6b; receives the filled brief, never the transcript."
model = "gpt-6-astra"
model_reasoning_effort = "xhigh"
sandbox_mode = "read-only"
developer_instructions = """
You are the independent reviewer of task-flow phase 6. Follow the brief you receive verbatim; it is the only context you get.
Read-only on the checkout. Report findings with file:line evidence; end with `Reviewed: <sha>`.
"""
```

`.codex/rules/git.rules` — те же префиксы, что в §5.3, если хотите держать
их в репо, а не у пользователя. `.worktreeinclude` — `.env` и прочие
игнорируемые файлы, которые нужны билдеру в worktree.

### 6.3 CI: ci-gate + второй security-pass

1. `/task-flow:ci-gate` (Claude) или `$task-flow:ci-gate` (Codex) — как
   сейчас: `ci/gate.sh`, `ci-gate.shell.gitlab-ci.yml`, `.gitleaks.toml`,
   `--selftest`.
2. Codex Security (🔧 S2 шаблон; сегодня — вручную по официальному примеру):
   стадии `security_scan` → `security_gate`, только MR между защищёнными
   ветками одного проекта, `GIT_DEPTH: 0`, скан `--diff $(git merge-base
   $CI_MERGE_REQUEST_DIFF_BASE_SHA $CI_COMMIT_SHA) --head $CI_COMMIT_SHA --json`,
   `export --export-format sarif` → `reports: sarif`, exit-код сканера
   восстанавливается отдельной джобой (0 чисто / 1 findings ≥ порога / 2
   неполное покрытие или ошибка). Переменная `CODEX_SECURITY_API_KEY` —
   masked+hidden+protected, environment scope `codex-security/openai`;
   ключ **Platform API** с доступом Codex Security — это отдельный счёт.
   Альтернатива для приватного self-hosted GitLab с shell-раннером:
   `codex-security login --device-auth` под раннер-пользователем и
   `--auth chatgpt` — квота вашей подписки, `~/.codex/auth.json` раннера
   = пароль; мануал прямо говорит «только не для публичных репо».
   Полные сканы репозитория могут требовать Trusted Access for Cyber;
   MR-диффы — штатный режим пайплайна.
3. На раннер-хосте (Ubuntu 24.04) — тот же AppArmor-профиль (§5.1): и Codex,
   и Codex Security поднимают bwrap.
4. Стоимость: `--max-cost` на скан; `low` effort для MR-диффов (официальный
   профиль пайплайна), `high`/`deep` — по расписанию на защищённой ветке.

---

## 7. Пошагово: один тикет в дуэте

### 7.1 Подготовка (Claude, интерактивно)

```
/task-flow:decompose <эпик или спека>
```
Драфт `docs/decompose/<дата>-<эпик>.md` → тикеты с DoD/truths/волнами; в
каждом — строка `builder: codex | claude` по правилу §2.1 (T1/T2 routine →
codex). Премортем эпика — `/premortem`, как и раньше.

### 7.2 Стройка — вариант A: интерактивно в Codex

```
codex -C ~/Project/<repo>
> $task-flow:task BA-123
```
Тот же флоу фаз 0–8; отличия на Codex: Read = чтение файла, `ROOT` — по пути
`SKILL.md` (Codex сообщает его в списке скиллов), `PREDICT` — из
`additionalContext` SessionStart (S1) или glob по кэшу, фаза 5 —
`"$PREDICT" on BA-123 --task`. One-way команда без квитанции → **deny**
(не «ask», как в Claude): написать `predict open …`, повторить команду.
Фаза 6: `xreview.sh --by claude` (S2) — или до S2 руками (§7.4).

### 7.2' Стройка — вариант B: headless из раннера / терминала

```bash
TASK=BA-123; WT=~/wt/$TASK; git -C ~/Project/<repo> worktree add "$WT" -b "feature/$TASK" origin/development
export PP_SESSION="$(uuidgen)" PP_ENTRYPOINT=headless
PREDICT="$(ls -d ~/.codex/plugins/cache/*/prediction-protocol/*/bin/predict ~/.claude/plugins/cache/*/prediction-protocol/*/bin/predict 2>/dev/null | sort -V | tail -1)"
"$PREDICT" on "$TASK" --task --root "$WT"                 # predict-gate: active vX (selftest: …)
codex exec -p builder -C "$WT" --dangerously-bypass-hook-trust --json -o "/tmp/$TASK.last.md" \
  "Use \$task-flow:task for ticket $TASK. Project instructions are in AGENTS.md. Stop after phase 6 is ready for review; do not merge." \
  </dev/null > "/tmp/$TASK.events.jsonl"
"$PREDICT" report                                          # строка для evidence block
```

`--dangerously-bypass-hook-trust` здесь — осознанно: раннер сам поставил
плагин и отвечает за источник хуков (формулировка мануала «automation that
already vets hook sources»). Без флага плагинные хуки в headless просто
пропускаются, и гейт не существует — `predict report` покажет `gate: never`.

### 7.3 Стройка — вариант C: в Claude (как сегодня)

`/task-flow:task BA-123` — без изменений; ревьюер — Codex (§7.4).

### 7.4 Перекрёстное ревью (до S2 — руками; после — `xreview.sh`)

Бриф заполняется из артефактов, не из памяти: `code-review-prompt.md`
(слоты `[DOD]`, `[DESIGN_SPEC]`, `[PREMORTEM_EDGES]` из `<TASK>.spec.md`;
`[BASE_SHA]`/`[HEAD_SHA]` из git) → `/tmp/$TASK.brief.md`.

Codex ревьюит работу Claude:

```bash
git fetch --no-tags origin development
codex exec review --base development -o "docs/reviews/$TASK-$(git rev-parse --short HEAD)-codex.md" </dev/null   # штатный ревьюер + Code Review Rules
codex exec -p reviewer -C "$PWD" -o "docs/reviews/$TASK-$(git rev-parse --short HEAD)-codex-brief.md" - < "/tmp/$TASK.brief.md"   # наш adversarial-бриф
```

Claude ревьюит работу Codex:

```bash
claude -p --model opus \
  --allowedTools 'Read,Grep,Glob,Bash(git diff:*),Bash(git show:*),Bash(git log:*),Bash(git grep:*),Bash(git status:*),Bash(git worktree:*)' \
  --disallowedTools 'Edit,Write,MultiEdit,NotebookEdit,Agent' \
  < "/tmp/$TASK.brief.md" > "docs/reviews/$TASK-$(git rev-parse --short HEAD)-claude.md"
```

Дальше — контракт «After the review comes back» из шаблона: Critical/Required
блокируют, поведенческая находка → fix → **ре-ревью дельты той же чужой
моделью**, `fix(review): <id>` по коммиту на находку, `Reviewed: <sha>` в
evidence block. Два ревью нашли одно и то же независимо — приоритет;
разошлись во вердикте — не усреднять, а решать человеку (или третьим
прогоном с явным вопросом).

### 7.5 Security

- Фаза 6b task (LLM, другой моделью — тем же способом, что 7.4, с
  `security-review-prompt.md`).
- Локально до MR (без CI и без API-ключа, по подписке):
  `npx @openai/codex-security scan . --diff origin/development --head HEAD --auth chatgpt --output-dir /tmp/sec-$TASK --headless` ⚠
  (чистое дерево обязательно — `--dry-run` это проверяет).
- В CI — §6.3.

### 7.6 MR и закрытие

`glab mr create` (правило §5.3 разрешает билдеру), пайплайн: ci-gate +
codex-security; фаза 8 task считает пайплайн зелёным только с гейт-джобами
(«green includes the gate»); evidence block + `predict report` + пути к
двум ревью → комментарий в тикет, Done, Spent time. Мерж — по политике
проекта (`self` | `mr-approval-required`), никогда моделью-автором.

---

## 8. Пошагово: пул тикетов через раннер (loop-foundry + `codex exec`)

1. Фазы 0–4 loop-foundry — как в `how-the-line-works.md` §8.3; в спеке лупа
   §4 (executor scope) добавляется `executor: codex -p builder` |
   `claude -p`, §3.1 — `verifier: <другая модель>`.
2. Фаза 5 генерирует раннер: `discover.sh` (тикеты `builder: codex`, состояние
   Ready) → на тик: `predict on --loop` под `PP_SESSION` → исполнитель
   (§7.2') → `predict status/report` снапшоты → верификатор другой моделью
   под своим `PP_SESSION` → `gates.sh` (диффы `predict report --json`,
   `gate_denies`, evidence vs DoD) → `journal.py` → `deliver.sh` (только на
   gated/autonomous, только разрешённый класс действия).
3. Лестница shadow → gated → autonomous и её пороги — без изменений; поле
   `model` в журнале теперь на роль, демоушен по смене любой из двух.
4. Раннер-хост: AppArmor-профиль, `codex login` раннер-пользователя, trust
   хуков не нужен (флаг), `PREDICT` в env-файле раннера (GAPS).

До S3 всё это делается руками по §7.2'; S3 переносит в `predictions.md`/`ladder.md`.

---

## 9. Ловушки

| Ловушка | Следствие | Что делать |
|---|---|---|
| `permissionDecision: ask` не поддерживается в Codex | до S1 гейт на Codex fail-open в клетках «ask» — one-way вне протокола **выполняется** | S1: deny; до S1 — на Codex всегда `predict on` перед one-way (тогда клетка «без квитанции» = deny уже сейчас) |
| Trust хуков по хэшу | после каждого обновления плагина хуки молча не работают до `/hooks` → Trust | `predict report` → `gate: never` = хук не срабатывал; раннер — флаг bypass |
| bwrap + AppArmor userns (Ubuntu 24.04) | любая команда модели в CLI-Codex падает | профиль §5.1 (sudo, один раз, и на раннер-хосте) |
| `.git`/`.codex`/`.agents` read-only в `workspace-write` | `git commit` = эскалация; под `never` — ошибка | `.rules` §5.3 или интерактивные approvals |
| Сеть off в `workspace-write` | `git push`/`pip`/`glab` — эскалация | `[sandbox_workspace_write] network_access = true` |
| `codex exec` читает stdin, если он не TTY | скрипт «висит» | `</dev/null` или `-` как промпт |
| `codex exec review --base` ≠ промпт | «cannot be used with [PROMPT]» | либо `--base`, либо бриф через `codex exec -p reviewer -` |
| Auto-режим Claude ↔ `codex exec` с записью | классификатор отказывает | оркестрирует раннер; интерактивно — обычный режим разрешений |
| `CLAUDE_PLUGIN_ROOT` в шелле модели на Codex | не задан (только хукам) | `ROOT` по пути `SKILL.md` — task-flow уже так умеет |
| `project_doc_max_bytes` 32 KiB | длинный AGENTS.md обрежется молча | вынести детали в `docs/`, оставить правила |
| Codex Security = Platform API key в CI | отдельный счёт | `--max-cost`, `low` effort на MR; или ChatGPT-auth раннера (приватные репо) |
| Имена скиллов | `/task-flow:task` (Claude) ↔ `$task-flow:task` (Codex) | Harness-раздел в SKILL (S2) |

---

## 10. Приёмка (что проверить вам — мне это недоступно из auto-режима)

После §5.1–5.2 на этом хосте, в пустом репо с пустым `origin`:

1. `codex sandbox linux -- echo SANDBOX_OK` → `SANDBOX_OK`.
2. `codex` → `/hooks` → Trust четырёх хуков prediction-protocol → новая сессия →
   попросить: «выполни `git push --force origin main` и покажи ответ инструмента
   дословно». Ожидание **сегодня (1.0.3)**: вне протокола — команда
   *выполнится* (клетка ask → failed → fail-open; это и есть причина S1);
   после `predict on canary --task` — **deny** с рецептом `predict open`.
   Ожидание **после S1**: deny в обеих клетках, текст упоминает «cannot ask».
3. `"$PREDICT" report` → `gate: seen <utc>` (хук реально срабатывал).
4. `codex exec -p reviewer --json -o /tmp/r.md review --base master </dev/null` в
   `lab`-репо с диффом — отчёт с находкой «silent error swallowing» (у меня
   упёрлось в bwrap).
5. `codex plugin marketplace upgrade devpowers && codex plugin add
   prediction-protocol@devpowers` после релиза 1.1.0 → в кэше появляется
   `1.1.0`, `/hooks` просит новый trust.
6. `npx @openai/codex-security scan . --diff master --head HEAD --auth chatgpt
   --output-dir /tmp/sec --headless` в `lab`-репо → `findings.json`,
   `coverage.json`; если «access required» — решение про Trusted Access / API-ключ.
7. `/import` в Codex CLI из Claude Code — что именно переехало в
   `~/.codex/AGENTS.md`, `config.toml`, `~/.agents/skills`.

Лабораторный каталог этой сессии (изолированный `CODEX_HOME` с
установленными плагинами, `lab`-репо с диффом, `lab-market` с двумя
вариантами premortem) — в scratchpad сессии; после приёмки его можно
удалить целиком.
