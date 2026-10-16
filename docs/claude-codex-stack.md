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
   не нужен, в том числе premortem (скилл не под `skills/`): оверлей
   `.codex-plugin/plugin.json` не понадобился, хватило поправить `skills` в его
   же манифесте на `["./premortem/"]`. Эту форму читают оба харнесса, и версия
   осталась в одном файле (S4, факт 30) ✅.
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
4. **Гетерогенное ревью — самая дешёвая и самая ценная часть.** Готово в
   task-flow 1.12.0: `xreview.sh` отдаёт бриф `code-review-prompt.md` другой
   модели headless — read-only по построению и в изоляции от сессии автора
   (что для этого нужно, оказалось нетривиальным: §1, факты 19–20), плюс
   штатный `codex exec review --base <ветка>` с `## Code Review Rules` из
   AGENTS.md как дополнительное мнение. Два детерминированных
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
   определения, т.е. **после каждой смены определения хука в `hooks.json` —
   снова** (обновление без такой смены доверие сохраняет, §9) (раннер
   вместо этого передаёт `--dangerously-bypass-hook-trust`, потому что он
   сам установил плагин и отвечает за источник — при checkout'е лупа, который
   никогда не trusted: проектный `.codex/` тогда не грузится, факт 27).

---

## 1. Что проверено сегодня (факты, не документация)

| # | Факт | Как проверено |
|---|---|---|
| 1 | Codex читает `.claude-plugin/marketplace.json` как «legacy-compatible marketplace»; все 9 записей devpowers видны в `codex plugin list --available --json` | изолированный `CODEX_HOME`, `marketplace add /home/…/devpowers` и `marketplace add umar-s/devpowers` (git) ✅ |
| 2 | `codex plugin add <name>@devpowers` ставит `git-subdir`- и `url`-источники в `$CODEX_HOME/plugins/cache/devpowers/<plugin>/<version>/`, версия берётся из `.claude-plugin/plugin.json` | task-flow 1.11.0, prediction-protocol 1.0.3, premortem 1.0.0, co-rar 1.0.1, loop-foundry 1.1.0, md2pdf 1.3.0 ✅ |
| 3 | Скиллы плагинов видны модели как `plugin:skill` с абсолютным путём к `SKILL.md`: `task-flow:task`, `task-flow:decompose`, `task-flow:ci-gate`, `prediction-protocol:prediction-protocol`, `loop-foundry:loop-foundry`, `co-rar:co-rar`, `md2pdf:md2pdf` | `codex exec -s read-only` «перечисли скиллы» ✅ |
| 4 | premortem (скилл в `./premortem/`, манифест `skills: ["./"]`) Codex **не** видит; симлинк `skills/premortem → ../premortem` не помогает; оверлей `.codex-plugin/plugin.json` с `"skills": "./premortem/"` — помогает. Уточнено в S4: оверлей не нужен, `["./premortem/"]` в самом `.claude-plugin/plugin.json` видят оба харнесса (факт 30) | lab-маркетплейс с двумя вариантами ✅ |
| 5 | Хуки: тот же контракт, что в Claude Code — события `PreToolUse/PostToolUse/SessionStart/…`, `matcher` по имени тула (`Bash`; `apply_patch` откликается на `Edit\|Write`), stdin с `session_id/transcript_path/cwd/permission_mode/tool_name/tool_use_id/tool_input.command`, deny = `hookSpecificOutput.permissionDecision:"deny"` или exit 2 + stderr; плагинный `hooks/hooks.json` подхватывается по умолчанию; хук получает `PLUGIN_ROOT`/`PLUGIN_DATA` **и** `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` | официальный мануал (раздел Hooks) — живой прогон заблокирован классификатором, см. §10 ⚠ |
| 6 | `permissionDecision: "ask"`, `continue`, `stopReason` для PreToolUse **не поддерживаются**: hook run = failed, tool call продолжается | мануал, дословно ⚠ (следствие для гейта — §4.1) |
| 7 | `codex exec` не принимает `-a`; политика — `-c approval_policy=never` или профиль `-p <name>` (`$CODEX_HOME/<name>.config.toml`); stdin не-TTY → «Reading additional input from stdin» и ожидание EOF — в скриптах всегда `</dev/null` | ✅ (два зависших прогона) |
| 8 | `codex exec review --base <branch>` несовместим с позиционным промптом; кастомные инструкции — либо без `--base` (сам берёт `git diff`), либо через `## Code Review Rules` в AGENTS.md | ✅ |
| 9 | Песочница Codex (bwrap) на этом хосте падает: `kernel.apparmor_restrict_unprivileged_userns = 1`, профиль есть только у `/usr/lib/chatgpt/ChatGPT` (`flags=(unconfined) { userns, }`), у бинаря `codex` — нет | `codex sandbox linux -- echo` ✅; `use_legacy_landlock` — deprecated и сломан (panic) ✅ |
| 10 | `codex mcp-server` работает, но помечен deprecated («use the app server»); инструменты `codex` / `codex-reply` | probe по stdio ✅ — в стек **не** берём |
| 11 | `/import` в Codex CLI и Settings → Import в десктопе импортируют из Claude Code: `CLAUDE.md`→`AGENTS.md`, `settings.json`→`config.toml`, скиллы, плагины, хуки, MCP, subagents | мануал (Import from another agent) ⚠ |
| 12 | Codex Security CLI: `npx @openai/codex-security@0.1.31`, команды `scan --diff BASE --head HEAD`, `--working-tree`, `--fail-on-severity`, `--auth chatgpt\|api-key`, `export --export-format sarif`, exit 0/1/2; `--dry-run` требует чистого дерева | ✅ dry-run; сам скан — ⚠ (нужен доступ Codex Security / Trusted Access for Cyber на аккаунте) |
| 13 | В auto-режиме Claude Code классификатор отказывает в `codex exec -s workspace-write` и в `--dangerously-bypass-hook-trust` («Create Unsafe Agents»); read-only `codex exec` разрешён | ✅ |
| 14 | Codex 0.162.1, stdin хука: общие `session_id/transcript_path/cwd/hook_event_name/model/permission_mode`; PreToolUse добавляет `turn_id` (расширение Codex — у Claude Code его нет), `tool_name/tool_use_id/tool_input`; `agent_id/agent_type` — для spawn-субагентов. `permission_mode` выводится из approval policy: `never` → `bypassPermissions`, всё остальное → `default`. **`codex exec` всегда `approval: never`** (`-c approval_policy=on-request` игнорируется) — каждая exec-сессия для гейта делегированная; `default` только в TUI/приложении | живой прогон в изолированном `CODEX_HOME` с логирующим хуком ✅ 2026-10-15 |
| 15 | `apply_patch` приходит хуку как `tool_name: "apply_patch"`, `tool_input.command` = текст патча (`*** Add File:` …), матчится по `apply_patch`, `Edit` или `Write`; shell-инструмент — `Bash` | ✅ 2026-10-15 (исходники `codex-rs/core/src/tools/hook_names.rs`, `handlers/apply_patch.rs` + живой прогон) |
| 16 | Env хука плагина: `PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`; у пользовательского хука ничего из этого. Шелл модели: `CODEX_SESSION_ID` (= `session_id` хука), `CODEX_THREAD_ID`, `CODEX_SANDBOX_NETWORK_DISABLED=1`; `bin/` плагина в PATH не добавляется. **Утечка:** Codex, запущенный из шелла Claude Code, наследует `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_SESSION_ID`, `CLAUDECODE` и пр. в свои хуки и в шелл модели — харнесс нельзя определять по `CLAUDE_*` | ✅ 2026-10-15 |
| 17 | Trust хуков: `~/.codex/config.toml` → `[hooks.state."<plugin>@<marketplace>:hooks/hooks.json:<event>:<group>:<handler>"] trusted_hash = "sha256:…"`; хэш — не файла, а нормализованной идентичности `{event_name, matcher, hooks:[{type, command (плейсхолдеры не раскрыты), timeout (default 600), async, statusMessage}]}` → TOML → JSON с сортировкой ключей → SHA-256 (`codex-rs/hooks/src/engine/discovery.rs::hook_hash`, `config/src/fingerprint.rs`) | воспроизведён в python, совпал со всеми 6 живыми записями claude-mem ✅ 2026-10-15 |
| 18 | Платформенная таблица Codex через `platform-probe.sh --codex`: deny-JSON и exit 2 блокируют; `ask`, exit 1, битый JSON и превышение таймаута → hook Failed, **команда выполняется**. SessionStart `additionalContext` принимается (модель отказывается цитировать «скрытый контекст», но хук Completed). Песочница — свой pid-namespace (PID 1 = `codex`), предка по `/proc` не найти | ✅ 2026-10-15 |
| 19 | Ревьюер `claude -p` получает больше, чем `--tools`: по умолчанию 9 SessionStart-хуков пользовательских плагинов (claude-mem пересказывает историю проекта — рассказ автора), без пользовательских настроек — 0; **`.claude/settings.json` и `settings.local.json`, закоммиченные в проверяемом диффе, исполняют свои хуки и `apiKeyHelper` при старте `-p`-сессии** (даже в недоверенном workspace — там игнорируется только `permissions.allow`); `--tools` ограничивает лишь встроенные инструменты — MCP проекта/аккаунта остаются. Безопасно: `--setting-sources "" --settings '{"disableAllHooks":true}' --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands` — OAuth при этом работает; разрешённый `Bash(git diff *)` не read-only (`git diff --output=<file>`, сокращения длинных опций) | lab-репозиторий с маркерами ✅ 2026-10-16 |
| 20 | `codex exec` по умолчанию — 4 SessionStart-хука (claude-mem, prediction-protocol), с `--ignore-user-config` — 0, проектный `.codex/hooks.json` не исполняется; **но пользовательские `.rules` грузятся и под `--ignore-user-config`: `allow`-правило выполняет команду вне read-only песочницы** (маркер записан) — ревьюеру нужен `--ignore-rules` | изолированный `CODEX_HOME` ✅ 2026-10-16 |
| 21 | `codex exec -p <name>` в 0.162 = слой `$CODEX_HOME/<name>.config.toml` (help: `CONFIG_PROFILE_V2`), факт 7 подтверждён; роли агентов — `<config folder>/agents/*.toml` (`agent-roles/src/loader.rs`), без `developer_instructions` роль отбрасывается («Ignoring malformed agent role definition») | исходники `rust-v0.162.1` + негативный контроль ✅ |
| 22 | execpolicy `prefix_rule` сравнивает точные токены на точных позициях: `git push --force-with-lease=<ref>`, `git push -fu`, `git push origin main --force` не видит правило `forbidden` для `["git","push",["--force",…]]` → push нельзя разрешать `allow` вообще (только `prompt`); решения сравнимы `allow < prompt < forbidden`; примеры `match`/`not_match` валидируются при загрузке | `codex execpolicy check` ✅ 2026-10-16 |
| 23 | Официальный минимальный GitLab-пример Codex Security: в `node:26-bookworm-slim` нет `git` и `python3` (его `git merge-base` и экспорт не запускаются); без `--fail-on-severity` сканер не выходит с 1 (гейт зелёный при любых находках); committed-diff скан отказывается от грязного дерева (ничего нельзя писать в checkout до скана); родитель `--output-dir` не может быть group/world-writable без sticky; `--mock` даёт синтетические находки без ключа и LLM; ключ в CI — `OPENAI_API_KEY`/`CODEX_API_KEY` (`CODEX_SECURITY_API_KEY` — защищённая переменная шаблона) | docker + `--mock`, `scripts/codex-security-mock.sh` 20/20 ✅ 2026-10-16 |
| 24 | `codex exec` у раннера: экспортированный `PP_SESSION` доходит и до хука, и до шелла модели (`printenv` в шелле модели вернул `PP_SESSION`/`PREDICT`/`PP_ENTRYPOINT`), гейт отказал по состоянию **этой** сессии, `predict report` → `gate_seen` выставлен — `--session-id` Codex'у не нужен | изолированный `CODEX_HOME`, хуки prediction-protocol 1.1.0 из кэша Codex, доверенные по хэшу ✅ 2026-10-16 |
| 25 | **Отказ хука не попадает в поток `codex exec --json`**: запрещённого вызова там нет ни как `command_execution`, ни иначе. Он есть в stderr Codex — `<ts> ERROR codex_core::tools::router: error=Command blocked by PreToolUse hook: <причина, обрезанная>… Command: <команда>` — и в rollout (`custom_tool_call_output`). Модель — только в rollout (`turn_context.model`); под `--json` баннера `model:` в stderr нет | там же ✅ 2026-10-16 |
| 26 | В песочнице `workspace-write` `~/.local/state` только на чтение (`Read-only file system`), `/tmp` записываем → `predict open/close` из шелла Codex-модели падают. **Так и надо оставить:** prediction-protocol 1.1.0 ловит запись в состояние только по буквальному пути (`pp_classify` на `pathlib …/"state"` → не классифицировано), а `predict status` при `active=0` — rc 0: записываемое моделью состояние = гейт, который она выключает незаметно. `codex sandbox -C <dir>` требует `-P <profile>` (`:workspace`); без `-C` — нет | `codex sandbox -P :workspace`, `pp_classify` ✅ 2026-10-16; сам `codex exec -s workspace-write` — ⚠ (факт 13) |
| 27 | Проектный `.codex/hooks.json` с **доверенным** хэшем не исполнился, пока проект не trusted; после `trust_level = "trusted"` — исполнился. Попутно: проектный хук с JSON-deny и `exit 2` при **пустом** stderr команду не остановил (одно наблюдение) | изолированный `CODEX_HOME` с маркером ✅ 2026-10-16 |
| 29 | Отказ **state-guard** prediction-protocol 1.1.0 (правка самого состояния протокола) — вторая форма отказа в записи сессии: Claude — `tool_result` `is_error` `PreToolUse:Edit hook error: prediction-protocol: …` (без версии); Codex (`apply_patch`) — строка роутера `error=Command blocked by PreToolUse hook: prediction-protocol: editing the protocol state is a bypass. Command: *** Begin Patch` + `*** Update File: <путь>`. Упавшая команда, печатающая маркер гейта, в `stream-json` — `Exit code 1\n…`, `is_error: true`; успешная — `is_error: false`; событий PreToolUse-хука в `stream-json` нет | живые прогоны (haiku, `codex exec -s read-only`) ✅ 2026-10-16; состояние не изменилось |
| 28 | Claude Code 2.1.301: `claude -p --output-format stream-json` без `--verbose` → `Error: When using --print, --output-format=stream-json requires --verbose`. Отказ гейта в `stream-json` — `tool_result` `PreToolUse:Bash hook error: prediction-protocol v…` (отказ `dontAsk` — другой текст); гейт ключует по `PP_SESSION` из env и при другом `--session-id`. `env -i` без `HTTPS_PROXY` на хосте с прокси — `claude -p` висит после `init` | ✅ 2026-10-16 (`--plugin-dir`, haiku, $0.003) |
| 30 | Поле `skills` в `.claude-plugin/plugin.json` (Claude 2.1.301 / Codex 0.162.1): `["./"]` — Claude ✅ / Codex ❌; `"./premortem/"` — ✅/✅; `["./premortem/"]` — ✅/✅; `["./"]` + оверлей `.codex-plugin/plugin.json` — ✅/✅. Путь в `skills` может указывать прямо на каталог с `SKILL.md` в обоих харнессах — второй манифест (и вторая копия версии) не нужен | lab-маркетплейс с четырьмя вариантами в изолированных `CLAUDE_CONFIG_DIR`/`CODEX_HOME`; Claude — `claude plugin details` и init-событие `claude -p --plugin-dir` (`skills: ['pm-v2:premortem']`) ✅ 2026-10-16 |
| 31 | Видимость скиллов проверяется **без вызова модели**: `codex debug prompt-input x </dev/null` печатает промпт модели JSON-ом, со списком скиллов и путями к `SKILL.md` (auth не нужен, работает в пустом `CODEX_HOME`); `claude plugin details <plugin>@<marketplace>` — инвентарь компонентов, включая скиллы. На этом построен `scripts/check-skills.sh` каталога: одноразовые `CLAUDE_CONFIG_DIR`/`CODEX_HOME`, точное сравнение с `scripts/expected-skills.txt` | ✅ 2026-10-16 |
| 32 | Codex 0.162.1 в системном промпте: «Resolve relative paths against the directory containing a filesystem-backed `SKILL.md`»; Claude Code печатает модели «Base directory for this skill: <dir>». Относительный `scripts/…` в SKILL.md работает в обоих, абсолютный `~/.claude/skills/<skill>/…` — ни в одном для установленного плагина (тот лежит в версионном кэше харнесса) | строки бинаря Codex; md2pdf 1.3.0 ✅ 2026-10-16 |
| 33 | **В песочнице Codex (`workspace-write`, сеть выключена — по умолчанию) не стартовали ни проверенные сборки Chromium, ни snap-приложения.** `codex sandbox -P :workspace`: AF_UNIX `socketpair` создаётся, но `setsockopt`/`shutdown`/`send` на нём возвращают EPERM; `/proc/self/status` в песочнице — `Seccomp: 2`, `Seccomp_filters: 1`, `NoNewPrivs: 1` (на хосте 0; в бинаре Codex режим зовётся `LinuxSeccomp`) — механизм отказа этим не доказан, только соседство. Chromium Playwright падает на crashpad (`setsockopt: Operation not permitted`), его headless-shell — на `shutdown`; `--no-sandbox` и отключение crashpad не помогают. snap: chromium — `snap-confine is packaged without necessary permissions … cap_dac_override`; `cups.*` — раньше, `snap run` не может создать `~/snap/<name>` и `/run/user/<uid>/snap.<name>` (read-only). Вне песочницы snap-chromium не читает `/tmp` (`ERR_FILE_NOT_FOUND`) и скрытые каталоги `~/.x/` (`ERR_ACCESS_DENIED`). `-c sandbox_workspace_write.network_access=true` при `-P :workspace` не действует (сеть так и осталась выключена) — песочница с сетью не измерена | md2pdf, Python-проба в песочнице ✅ 2026-10-16 |
| 34 | `uv run` в песочнице `workspace-write`: `~/.cache/uv` только на чтение → `Could not acquire lock … Read-only file system`; с `UV_CACHE_DIR` в cwd — нет сети на загрузку зависимостей. Скрипты premortem (`uv run scripts/cli.py …`) на Codex идут только с эскалацией; голый `python3` проходит, если зависимости уже стоят в системном Python | ✅ 2026-10-16 |
| 35 | Codex 0.162.1 читает у записи legacy-маркетплейса `.claude-plugin/marketplace.json` поле `"policy": {"installation": "NOT_AVAILABLE"}`: `codex plugin add statusline@devpowers` → ``Error: plugin `statusline` is not available for install in marketplace `devpowers` ``, rc 1; в `codex plugin list` запись остаётся (`not installed`). Уже установленный плагин после появления политики остаётся `installed, enabled`. Claude Code 2.1.301: `claude plugin validate` → `Unknown field 'policy'. Claude Code ignores it at load time`, «passed with warnings», rc 0; `claude plugin install` ставит | лаборатории с маркетплейсом по локальному пути в изолированных `CLAUDE_CONFIG_DIR`/`CODEX_HOME` ✅ 2026-10-16 |
| 36 | Инвентари расходятся на командах. Claude `plugin details` относит к Skills команду из автообнаруженного `commands/` (research-pipeline: `Skills (13)`, среди них `research-pipeline`), а команду из поля манифеста `"commands": ["./commands/setup.md"]` — нет (statusline: `Skills (0)`); причина не установлена. В выводе `codex debug prompt-input` нет ни команды research-pipeline, ни имён его `agents/*.md` — только 12 скиллов. В пустом `CODEX_HOME` тот же вывод перечисляет и личные скиллы из `~/.agents/skills` (без префикса плагина) — `check-skills.sh` фильтрует по `<plugin>:` | `check-skills.sh`, `claude plugin details`, `codex debug prompt-input` ✅ 2026-10-16 |

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
| `docs/reviews/<TASK>-<sha7>-<by>[-security].md` | `xreview.sh` (ревьюер другой модели) | builder (fix(review): …) | task-flow 1.12.0 |
| `docs/evidence/<TASK>.md`, `REFUTED.md` | `predict` (CLI) | оба | prediction-protocol |
| `loops/journal/<loop>.jsonl` | раннер | оператор | loop-foundry |

Никакого MCP «модель → модель»: `codex mcp-server` deprecated, а связь через
файлы переживает смену любой из моделей и читается человеком.

### 2.3 Оркестратор — раннер

Интерактивно вы работаете в **одной** из двух TUI и зовёте скилл
(`/task-flow:task` в Claude, `$task-flow:task` в Codex); вторая модель
приходит как ревьюер через `xreview.sh` (task-flow 1.12.0) — короткий
headless-вызов из скилла или из терминала. Пакетно — раннер loop-foundry, где исполнитель
тика — `codex exec` **или** `claude -p`, верификатор — другая модель
через тот же `xreview.sh`, вне протокола по построению (loop-foundry 1.2.0,
`references/harnesses.md`). Причины не «оркестрировать из сессии Claude»: классификатор
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
| **prediction-protocol** | hooks (PreToolUse×2, PostToolUse, SessionStart), CLI `bin/predict`, skill | хуки грузятся (после trust) ⚠, но `ask` → failed → **команда выполняется** — на Codex гейт сегодня fail-open в двух клетках таблицы; `PREDICT` не экспортируется (нет `CLAUDE_ENV_FILE`); стейт-гард не видит `apply_patch` | `ask`→`deny` на Codex; `apply_patch`-парсер; SessionStart `additionalContext`; glob по обоим кэшам в SKILL; таблица платформы Codex в `hook-engineering.md`; фикстуры Codex в `tests/run.sh`; `platform-probe.sh --codex` | **S1 → 1.1.0**; запись отказов (`predict status --json` → `denies`) — **S3 → 1.2.0** |
| **task-flow** | 3 skills, `templates/ci-gate`, scripts | скиллы видны ✅; `ROOT` резолвится по пути SKILL.md (fallback уже есть) ✅; «Agent tool / subagent» и `/task` — Claude-термины | раздел Harness в 3 SKILL.md; фазы 6/6b: перекрёстное ревью как предпочтительный dispatch; `references/cross-review.md`; `templates/xreview/xreview.sh`; `templates/ci-gate/gitlab/codex-security.gitlab-ci.yml`; `templates/agents/` (AGENTS.md-скелет, `.codex/agents/reviewer.toml`, `.codex/rules/git.rules`); bindings читаются из `AGENTS.md`/`CLAUDE.md` | **S2 → 1.12.0 ✅** |
| **loop-foundry** | skill + references | скилл виден ✅; контракт раннера завязан на `claude -p --session-id` | `references/harnesses.md`: исполнитель `claude -p` или `codex exec -p <profile> --ignore-rules --dangerously-bypass-hook-trust` (checkout никогда не trusted, состояние протокола модели недоступно на запись) под экспортированным `PP_SESSION` + `PP_ENTRYPOINT=headless`; `PREDICT` закреплён по записи установки харнесса исполнителя, без glob; `gate_denies` — из `predict status --json` (`denies`, prediction-protocol 1.2.0): в `--json` Codex отказа нет, а его stderr-записи подделываемы (факт 25); верификатор — другая модель через `xreview.sh`, вне протокола по построению; `executor_model`/`verifier_model`; чистый checkout на каждый тик | **S3 → 1.2.0 ✅** |
| **premortem** (форк) | skill в `./premortem/` | до 1.0.2 **не виден** ✅ | `"skills": ["./premortem/"]` в его же `.claude-plugin/plugin.json` — оба харнесса видят скилл, оверлей не нужен (факт 30); файлы апстрима не тронуты. Скрипты (`uv run scripts/cli.py`) в песочнице Codex не идут — эскалация (факт 34) | **S4 → упаковка 1.0.2 ✅** (1.0.1 был занят: тег 2026-08-22 при `plugin.json` 1.0.0) |
| **co-rar** | skill | виден ✅, чистая рамка | payload без харнесс-специфики → релиза нет; README «In Codex» (`co-rar@co-rar`, `co-rar@devpowers`, `$co-rar:co-rar`), в `CLAUDE.md` — проверка без модели | **S4 ✅ docs, без версии** |
| **md2pdf** | skill + scripts | виден ✅; в Quick start захардкожен `~/.claude/skills/md2pdf/scripts/md2pdf.py` — неверен в **обоих** харнессах для установленного плагина | `<SKILL_DIR>/scripts/md2pdf.py` (факт 32); на Codex — запуск вне песочницы с первой попытки (факт 33); предупреждение snap и о скрытых каталогах; первые тесты | **S4 → 1.3.1 ✅** |
| **devpowers** (каталог) | marketplace.json, README, docs, `scripts/check-skills.sh` | читается ✅ | README «Install → Codex» и матрица «Claude Code and Codex», этот документ, CHANGELOG; statusline — `policy.installation: NOT_AVAILABLE`; контракт видимости скиллов на все 9 плагинов; второй манифест `.agents/plugins/marketplace.json` **не нужен** | **S0 ✅, S5 ✅** |
| **research-pipeline** | skills, `agents/*.md` (Claude subagents), `commands/`, `workflows/` | 12 скиллов видны ✅; команды `/research-pipeline:research-pipeline` и агентов в промпте нет (факт 36); агенты — Claude-формат, у Codex агенты — `.codex/agents/*.toml` на уровне проекта, не плагина | отдельный этап: генерация `.codex/agents/*.toml` в проект пользователя + harness-раздел в manager-research | отложено (S6) |
| **voxscribe** | skills + python scripts | скилл виден ✅; не прогонялся (скрипты запускаются из shell) | «fan out to subagents» → harness-заметка | отложено (S6) |
| **statusline** | Claude `statusLine`: команда + SessionStart-хук | **N/A** — команда Claude Code и хук, читающий его `settings.json` и советующий `/statusline:setup` | запись каталога с `"policy": {"installation": "NOT_AVAILABLE"}` — Codex в установке отказывает (факт 35); README «Claude Code only»; в контракте `statusline not-in-codex` | **S5 ✅** |

---

## 4. Что меняется по этапам (спека)

Порядок — по CLAUDE.md каталога: плагин → каталог → потребители. Каждый этап
— свой релиз по ритуалу (supply-chain self-check, бамп, CHANGELOG через
`Edit`, аннотированный тег, `gh release create --verify-tag`); task-flow —
через PR + `gh pr merge --auto --squash` (защищённый main, локальный CLAUDE.md).

### 4.1 S1 — prediction-protocol 1.1.0: «второй харнесс» — ✅ выпущено 2026-10-15

Сделано как ниже, с поправками по живым фактам (§1, строки 14–18):
харнесс определяется по stdin (`turn_id`/`model`) и `PLUGIN_ROOT`, а не по
`CLAUDE_*`-переменным (они утекают во вложенный Codex); `codex exec` всегда
делегированная сессия (approval never), deny-вместо-ask действует только в
TUI/приложении; CLI резолвит сессию из `CODEX_SESSION_ID`, при двух id сразу
требует `PP_SESSION`; стейт-гард и классификатор читают заголовки
`apply_patch`-патча; `platform-probe.sh --codex` сам доверяет свои хуки по
воспроизведённому хэшу. 179 контролей, 329 корпусных кейсов.

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

### 4.2 S2 — task-flow 1.12.0: «dual-harness + cross-review» — ✅ выпущено 2026-10-16

Сделано по пунктам ниже, с поправками, которые дали живые факты (§1,
строки 19–23) и восемь раундов перекрёстного ревью самого релиза (Codex
ревьюил через `xreview.sh`, последний раунд — `Ready to merge`): Claude-ревьюер
**без shell** (материалы диапазона прикладываются к брифу), без MCP, без
skills и без файлов настроек; Codex-ревьюер с `--ignore-rules`; вердикт —
**отдельный канал** (две последние строки ответа `REVIEWED <sha>` /
`VERDICT …`, у 6b `SUMMARY …`), скрипт выносит его в шапку отчёта, а текст
ревьюера кладёт одним буквальным блоком — разбор вердикта из Markdown дважды
подряд дал расхождение «человек видит одно, парсер читает другое»; в
`git.rules` push = `prompt`; Codex Security-шаблоны исправляют официальный
пример (образ по digest, `git`/`python3`, `--fail-on-severity`, `.post`,
ничего в checkout до скана, ключ снят до первого дочернего процесса,
`mktemp`). Дизайн и запись ревью — `task-flow/docs/superpowers/specs/2026-10-16-task-flow-1-12-0-design.md`.


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

### 4.3 S3 — loop-foundry 1.2.0: «executor per harness» — ✅ выпущено 2026-10-16

Дизайн — `loop-foundry/docs/superpowers/specs/2026-10-16-loop-foundry-1-2-0-design.md`
(его факты E1–E12 сведены здесь в 24–29). Что выпущено, и где план этого раздела оказался
неверен:

- Новый `references/harnesses.md`. Исполнитель:
  `codex exec -p <profile> -m <model> -C "$CHECKOUT" --ignore-rules --dangerously-bypass-hook-trust --json -o "$TICK/last.md" - < prompt > executor.jsonl 2> executor.stderr`
  или `claude -p --session-id "$PP_SESSION" --output-format stream-json --verbose …`
  (без `--verbose` строка 1.1.0 не запускалась — факт 28). Ключ сессии у
  обоих — экспортированный `PP_SESSION` (факт 24). **Состояние протокола
  модели на запись недоступно** — план этого не учитывал: в `workspace-write`
  оно read-only, и так и оставлено (факт 26: записываемое — выключаемо);
  цена — у исполнителя Codex нет квитанций в сессии, его one-way — deny,
  one-way класса — в `deliver.sh`. Первая версия давала `--add-dir` — снято
  ревью Codex. `--ignore-rules` (факт 20). Bypass trust — только с
  checkout'ом, который никогда не trusted (факт 27). Коммитит раннер (`.git`
  read-only в песочнице) — результат тика всегда диапазон.
- **`PREDICT` — не «glob по обоим кэшам» и вообще не glob**: тик гейтит хук
  харнесса исполнителя, а `sort -V | tail -1` по путям сравнивает каталоги
  (кэши, маркетплейсы) раньше версий, кэш Claude ещё и хранит старые версии.
  `PREDICT`/`XREVIEW` закрепляются по записи установки: `installed_plugins.json`
  у Claude, `codex plugin list --json` у Codex. Та же ошибка была в §7.2' —
  исправлена.
- **`gate_denies` на Codex — не из событий**: отказа в `--json` нет вовсе,
  источник — stderr Codex (факт 25); канарейка GAPS проверяет и разбор.
  Модель Codex — из rollout.
- Верификатор — другая модель через `xreview.sh` task-flow ≥ 1.12.0 по
  спеке тика, которую `run.sh` собирает из файлов (§3.1, Intent, proxy risk,
  правило `gate_denies`); exit 0/1/2 → pass/fail/escalated. **Своя сессия
  `<loop>-verify` снята**: изолированный ревьюер не получает `PP_*`, хуков и
  пути записи — выстрелить квитанцию исполнителя не может; команд у него нет
  (то, что надо запустить, — гейт `gates.sh`).
- **Отказы тика — у инструмента, не в выводе харнессов.** Пять раундов
  ревью разбора записей кончились выводом: stderr Codex безопасно не
  разобрать (многострочные записи, рамку которых команда может подделать).
  Корень закрыт в **prediction-protocol 1.2.0** (выпущен в рамках S3): хуки
  пишут каждый отказ сессии в её состояние (класс, base64 точной команды;
  `state-guard` с путём; `gate-error`), `predict status --json` отдаёт их как
  `denies`. loop-foundry берёт оттуда `gate_denies` и `guard_denies`
  (`state-guard` → `escalated`, `state-tamper`; факт 29).
- Модель и стоимость читает `scripts/tick_record.py` в payload'е (раннеры
  зовут его на месте, не переписывают) — **белый список** наблюдённых форм:
  отсутствующий счётчик, нечисловая сумма, непредусмотренная форма → exit 2
  → тик `escalated`.
  `tests/contract.sh` гоняет его по урезанным реальным записям (stderr и
  события Codex, rollout, `stream-json` Claude) и синтетическим краям.
  Захват потоков исполнителя (`$TICK`) — у раннера, вне checkout'а и `/tmp`:
  иначе исполнитель Codex обнулил бы свой stderr и спрятал отказ.
- `ladder.md`: `executor_model`/`verifier_model`, `gates.reviewed`, демоушен
  по каждой роли; `loop-spec.md` §3.2/§4/§5/§7 — поля харнесса и модели;
  `gaps.md` — оба CLI и авторизация, AppArmor, `XREVIEW`, канарейка в
  харнессе исполнителя; `security.md` — чистый checkout на каждый тик,
  checkout не trusted, `--setting-sources user` для чужих веток, источники
  хуков вне записи исполнителя; `SKILL.md` — раздел Harness и компаньон
  task-flow.

### 4.4 S4 — md2pdf 1.3.1, premortem (упаковка) 1.0.2, co-rar — docs — ✅ выпущено 2026-10-16

План был «premortem 1.0.1 оверлеем, co-rar 1.0.2, md2pdf 1.3.1». Что вышло и чем
отличается:

- **premortem → `plugin-v1.0.2`.** Оверлей `.codex-plugin/plugin.json` не понадобился:
  в лаборатории из четырёх вариантов манифеста `"skills": ["./premortem/"]` в
  существующем `.claude-plugin/plugin.json` видят оба харнесса (факт 30), так что
  второго манифеста и второй копии версии нет. Номер 1.0.2, потому что `plugin-v1.0.1`
  уже был: тег 2026-08-22 поставлен при `plugin.json` 1.0.0, и оба харнесса ставили
  его как 1.0.0. Упаковка трогает только манифест. Скрипты скилла (`uv run
  scripts/cli.py …`) в песочнице Codex не идут: кэш uv read-only, сети нет (факт 34).
  В интерактивном Codex — эскалация на каждый вызов (правило префикса `uv run`), в
  `codex exec` — никак. SKILL.md апстрима об этом не говорит, и мы его не правим.
- **co-rar — без релиза.** В payload (`plugins/co-rar/**`) нет ни слова, специфичного
  для харнесса, и бамп без изменения payload был бы пустой версией. README получил
  раздел «In Codex»: собственный маркетплейс `co-rar@co-rar`, общий каталог
  `co-rar@devpowers`, вызов `$co-rar:co-rar`. В `CLAUDE.md` — проверка через `codex
  debug prompt-input` в собственном `CODEX_HOME`.
- **md2pdf 1.3.1.** Quick start ссылался на `~/.claude/skills/md2pdf/scripts/md2pdf.py`.
  Этот путь неверен в **обоих** харнессах: плагин лежит в версионном кэше. Теперь там
  `<SKILL_DIR>/scripts/md2pdf.py` (факт 32). «Зависимости хостовые» оказалось
  неполной правдой: в песочнице Codex не стартовала ни одна проверенная сборка
  Chromium (факт 33). Поэтому SKILL.md велит Codex-агенту просить
  `require_escalated` с первого вызова, а скрипт дописывает эту подсказку к ошибке
  песочницы. Предупреждение snap теперь ловит и скрытые каталоги. Добавлены первые
  тесты (stdlib `unittest`).
- **Каталог: `scripts/check-skills.sh`** — какие скиллы видит модель в обоих
  харнессах, без вызова модели, против контракта `scripts/expected-skills.txt`
  (факт 31). Его попросило ревью упаковки premortem. Проверка живёт в каталоге, а
  не в форке, и покрывает всю линейку.
- Ревью: Codex через `xreview.sh` по каждому репозиторию; до «ready to merge»
  premortem прошёл 2 раунда, co-rar — 3, md2pdf — 4. md2pdf: нет тестов, затем
  трижды заявления шире измеренного («ни один Chromium», «seccomp режет»,
  значения хоста по полям, измеренным только в песочнице). co-rar: изоляция
  проверки только в прозе, затем `export X=$(mktemp)` маскировал сбой. premortem:
  нет проверки на уровне загрузчиков. Сама проверка в каталоге прошла 7 раундов,
  и в ней было четыре неверных выхода: пустой контракт → 0; сбой подготовки → произвольный код;
  нечитаемый инвентарь → пустой список; регулярка по сырому выводу Codex вместо
  разбора JSON, а после неё — блок скиллов, который обрывался на любой лишней
  строке или не привязывался к началу строки. Теперь все четыре дают rc 2. Ещё
  нашлась critical-находка: имя из `--local` попадало в путь распаковки до
  проверки, и `../../../x` распаковывал клон вне рабочего каталога. Всё это
  держат 37 офлайн-контролей. Опубликованный
  контракт (task-flow, prediction-protocol, loop-foundry, co-rar, md2pdf,
  premortem) — ok в обоих харнессах.

### 4.5 S0/S5 — devpowers — ✅ S5 выпущено 2026-10-16

- S0 (2026-09-27): документ, CHANGELOG-запись, README «Install → in Codex».
- S5. План был: README-матрица «Claude Code / Codex», пометка statusline «Claude Code
  only», описания записей с именами `$plugin:skill`. Что вышло и чем отличается:
  - **statusline закрыт для Codex политикой записи, а не только пометкой.** Codex
    читает у записи legacy-маркетплейса `"policy": {"installation": "NOT_AVAILABLE"}`
    и отказывает в `codex plugin add` (факт 35). Для Codex в плагине ничего нет:
    команда Claude Code и SessionStart-хук, который читает `settings.json` Claude Code и
    советует `/statusline:setup`. Цена — одно постоянное предупреждение `claude plugin
    validate` (`Unknown field 'policy'`), в CLAUDE.md каталога оно названо ожидаемым.
    Уже стоящие установки политика не снимает: `codex plugin remove
    statusline@devpowers` — руками.
  - **Имена `$plugin:skill` — в README-матрице, а не в `description` записей.**
    Описание показывают оба харнесса, а `$` — синтаксис Codex; матрица даёт обе формы
    (`$…` в Codex, `/…` в Claude Code). В описания записей вошли только факты о
    доступности: statusline — «Claude Code only — Codex refuses to install it»,
    research-pipeline — в Codex грузятся только скиллы, пайплайн идёт в Claude Code.
    `metadata.description` — «plugins for Claude Code and Codex CLI».
  - **Контракт `scripts/expected-skills.txt` покрывает все девять плагинов** — строки
    unchecked больше нет. research-pipeline: 12 скиллов `both` и
    `research-pipeline:research-pipeline claude` — команда, которую Claude показывает как
    скилл (факт 36); voxscribe — `both`; statusline — новая форма строки
    `<plugin> not-in-codex`: проверка ждёт отказа `codex plugin add` с текстом политики,
    успешная установка — MISMATCH (rc 1), любая другая ошибка — rc 2. Контракт — о
    видимости, не о работоспособности: пайплайн research-pipeline и прогон voxscribe в
    Codex остаются в S6.

---

## 5. Пошагово: хост (один раз)

### 5.1 Codex CLI из терминала

```bash
# 1. пакетный CLI (бинарь из бандла ChatGPT умеет только `exec`; интерактивный TUI отвечает
#    "this CLI has no complete local package" — проверено 2026-10-14)
npm install -g @openai/codex@latest        # или standalone: chatgpt.com/codex/install.sh → ~/.local/bin/codex
codex --version                            # codex-cli 0.162.1; тот же ~/.codex, что у десктоп-приложения
sudo apt install ripgrep                   # codex doctor: "search command could not be verified"

# 2. песочница: Ubuntu 24.04 запрещает userns непрофилированным бинарям — дать нативному бинарю codex
#    тот же профиль, что у ChatGPT. У npm-установки бинарь лежит внутри nvm-версии Node → путь с глобами.
sudo tee /etc/apparmor.d/codex-cli >/dev/null <<'APP'
abi <abi/4.0>,
include <tunables/global>

profile codex-cli "/home/<user>/.nvm/versions/node/*/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/*/bin/codex" flags=(unconfined) {
  userns,
  include if exists <local/codex-cli>
}
APP
sudo apparmor_parser -r /etc/apparmor.d/codex-cli
codex sandbox -- echo SANDBOX_OK           # ✅ 2026-10-15: SANDBOX_OK (до профиля: bwrap: loopback: Failed RTM_NEWADDR)
codex doctor
```

Проверено 2026-10-15: после профиля и `codex sandbox -- …`, и команда модели в
`codex exec -s read-only` выполняются внутри bwrap. Форма `codex sandbox linux -- …`
из мануала в 0.162 неверна — слово `linux` уходит в `execvp` и даёт panic
`Failed to execvp linux`. Многострочный heredoc с `sudo` набирать в настоящем
терминале, не через `!` в промпте Claude (нет TTY для пароля, кавычки ломаются);
альтернатива — записать профиль в файл и `sudo install -m 644 <файл> /etc/apparmor.d/codex-cli`.

Без профиля Codex CLI **не выполнит ни одну команду** ни в `read-only`, ни в
`workspace-write` (обе идут через bwrap); работал бы только
`--dangerously-bypass-approvals-and-sandbox`, что для билдера неприемлемо.
Альтернатива системная (`sysctl kernel.apparmor_restrict_unprivileged_userns=0`)
ослабляет весь хост — не рекомендую. Standalone-установка кладёт бинарь под
`~/.codex/packages/standalone/<ver>/…` — профиль тогда на этот путь.

### 5.2 Маркетплейс и плагины в Codex

```bash
codex plugin marketplace add umar-s/devpowers            # ✅ читает .claude-plugin/marketplace.json
codex plugin add task-flow@devpowers
codex plugin add prediction-protocol@devpowers
codex plugin add loop-foundry@devpowers
codex plugin add co-rar@devpowers
codex plugin add md2pdf@devpowers
codex plugin add premortem@devpowers                     # скилл виден с упаковки 1.0.2 (S4)
codex plugin add research-pipeline@devpowers             # только скиллы: пайплайн — команда и агенты Claude (S6)
codex plugin add voxscribe@devpowers                     # скилл виден; в Codex не прогонялся (S6)
# statusline@devpowers — отказ политикой каталога (S5); стоявший раньше: codex plugin remove statusline@devpowers
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

Правила эскалации (`.codex/rules/git.rules` — шаблон `task-flow/templates/agents/`,
Starlark): в `workspace-write` `.git/` защищён как read-only, т.е. `git commit`
требует эскалации; под `approval_policy = "never"` без правила он просто
падает. **`git commit` — `allow`; `git push` — `prompt`** (в TUI одобряет
человек, под `codex exec` пушит раннер, не модель); force-формы сразу после
`push` — `forbidden`. Разрешать push целиком нельзя: prefix-правило не видит
`--force-with-lease=<ref>`, `-fu` и флаг после refspec (факт 22) — исходная
версия этого раздела с `allow` для push была обходима.

```python
prefix_rule(pattern = ["git", "commit"], decision = "allow",  justification = "the builder commits; .git is read-only inside the sandbox")
prefix_rule(pattern = ["git", "push"],   decision = "prompt", justification = "a push leaves the machine: a person approves it, or the runner pushes")
prefix_rule(pattern = ["git", "push", ["--force", "-f", "--force-with-lease", "--force-if-includes", "--mirror", "--delete", "-d", "--prune"]],
            decision = "forbidden", justification = "a history-rewriting or ref-deleting push never comes from the builder")
```

```bash
codex execpolicy check --pretty --rules .codex/rules/git.rules -- git push origin feature/x          # prompt
codex execpolicy check --pretty --rules .codex/rules/git.rules -- git push --force origin main       # forbidden
codex execpolicy check --pretty --rules .codex/rules/git.rules -- git push origin main --force       # prompt (не allow)
```

Ревьюер (`xreview.sh`) запускает Codex с `--ignore-rules`: `allow` любого
правила вывел бы его команды из read-only песочницы (факт 20).

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
32 KiB `project_doc_max_bytes`) и **только** его, когда рядом лежит `CLAUDE.md`;
Claude Code читает `CLAUDE.md` и разворачивает `@AGENTS.md` при загрузке —
проверено 2026-10-14 на 2.1.283 / Codex 0.162: в каталоге с обоими файлами
Claude процитировал маркеры из обоих, Codex — только из `AGENTS.md` ✅.

**Два файла, не один — осознанно.** Claude Code 2.1.283 умеет читать `AGENTS.md`
напрямую, когда `CLAUDE.md` отсутствует (проверено), но на этом строить нельзя:
над одним каталогом параллельно работают сессии обоих харнессов, и каждый пишет
в *свой* файл (`#`-заметки Claude дописывают `CLAUDE.md`, `/init` Codex создаёт
`AGENTS.md`). Первый же `CLAUDE.md`, появившийся рядом, молча **прячет**
`AGENTS.md` от Claude — ровно по этой причине superpowers 6.4.2 убрал свой
`CLAUDE.md`-указатель. Поэтому `CLAUDE.md` существует всегда и первой строкой
импортирует `@AGENTS.md`; harness-специфика живёт ниже импорта (Claude) и в
`AGENTS.md` (Codex: sandbox, rules, `$plugin:skill`). Обратный импорт
невозможен — у Codex нет механизма включения файлов, `AGENTS.md` обязан быть
самодостаточным.

Параллельные сессии в одном каталоге упираются не в инструкции, а в рабочее
дерево и индекс git — ответ линейки прежний: один worktree на сессию/тикет
(§7.2'), а `docs/specs/<TASK>.spec.md` и evidence-файлы — по одному на тикет.

Сегодняшняя схема ваших репо (AGENTS.md-указатель «прочитай CLAUDE.md», либо
симлинк `AGENTS.md → CLAUDE.md`) работает, но стоит вызова инструмента на каждую
сессию Codex и не даёт `Code Review Rules`. Переворот — одноразовый
`git mv CLAUDE.md AGENTS.md` + новый `CLAUDE.md`: `@AGENTS.md` и Claude-специфика.

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

Роль ревьюера для собственных субагентов Codex — шаблон
`task-flow/templates/agents/.codex/agents/reviewer.toml`: `sandbox_mode =
"read-only"`, обязательные `developer_instructions` (без них Codex роль
отбрасывает, факт 21), ответ заканчивается двумя машинными строками брифа
(`REVIEWED <sha>`, затем `VERDICT` или `SUMMARY`). Это запасной путь «та же
модель»; первый выбор — другая модель через `xreview.sh` (§7.4).

`.codex/rules/git.rules` — те же префиксы, что в §5.3, если хотите держать
их в репо, а не у пользователя. `.worktreeinclude` — `.env` и прочие
игнорируемые файлы, которые нужны билдеру в worktree.

### 6.3 CI: ci-gate + второй security-pass

1. `/task-flow:ci-gate` (Claude) или `$task-flow:ci-gate` (Codex) — как
   сейчас: `ci/gate.sh`, `ci-gate.shell.gitlab-ci.yml`, `.gitleaks.toml`,
   `--selftest`.
2. Codex Security — шаблоны task-flow 1.12.0 (`ci-gate` шаг 7,
   `templates/ci-gate/gitlab/codex-security{,.shell}.gitlab-ci.yml`), собранные
   из официального scan-only примера с исправлениями (факт 23); исходное описание:
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
Фаза 6: `xreview.sh --by claude` (§7.4).

### 7.2' Стройка — вариант B: headless из раннера / терминала

```bash
TASK=BA-123; WT=~/wt/$TASK; git -C ~/Project/<repo> worktree add "$WT" -b "feature/$TASK" origin/development
export PP_SESSION="$(uuidgen)" PP_ENTRYPOINT=headless
V="$(codex plugin list --json | python3 -c 'import json,sys; print([p["version"] for p in json.load(sys.stdin)["installed"] if p["pluginId"]=="prediction-protocol@devpowers"][0])')"
PREDICT="${CODEX_HOME:-$HOME/.codex}/plugins/cache/devpowers/prediction-protocol/$V/bin/predict"   # установленная копия харнесса, чей хук гейтит сессию (§4.3)
"$PREDICT" on "$TASK" --task --root "$WT"                 # predict-gate: active vX (selftest: …)
codex exec -p builder -C "$WT" --dangerously-bypass-hook-trust --json -o "/tmp/$TASK.last.md" \
  "Use \$task-flow:task for ticket $TASK. Project instructions are in AGENTS.md. Stop after phase 6 is ready for review; do not merge." \
  </dev/null > "/tmp/$TASK.events.jsonl" 2> "/tmp/$TASK.stderr"
"$PREDICT" report                                          # строка для evidence block
```

В `workspace-write` состояние `predict` модели недоступно на запись (факт 26)
— и это защита, а не помеха: квитанции из сессии не открываются, one-way
команды тикета отклоняются, и их делаете вы после прогона (или тикет идёт в
TUI/Claude). `--add-dir` на корень состояния не давать: записываемое моделью
состояние — выключаемый гейт. Отказы гейта ищите в `$TASK.stderr`, не в
событиях (факт 25). `.git` worktree'а лежит вне песочницы — коммит модели
требует правила `git commit` (§5.3) у **пользовательских** `.rules` либо
делается после прогона руками; worktree не помечайте trusted (факт 27).

`--dangerously-bypass-hook-trust` здесь — осознанно: раннер сам поставил
плагин и отвечает за источник хуков (формулировка мануала «automation that
already vets hook sources»). Без флага плагинные хуки в headless просто
пропускаются, и гейт не существует — `predict report` покажет `gate: never`.

### 7.3 Стройка — вариант C: в Claude (как сегодня)

`/task-flow:task BA-123` — без изменений; ревьюер — Codex (§7.4).

### 7.4 Перекрёстное ревью — `xreview.sh` (task-flow 1.12.0)

```bash
git fetch --no-tags origin development
ROOT=<каталог установленного task-flow>          # ~/.claude/plugins/cache/devpowers/task-flow/<ver> или ~/.codex/plugins/cache/…
bash "$ROOT/templates/xreview/xreview.sh" --by codex  --task "$TASK" --base origin/development                   # Codex ревьюит работу Claude
bash "$ROOT/templates/xreview/xreview.sh" --by claude --task "$TASK" --base origin/development --model opus      # Claude ревьюит работу Codex
bash "$ROOT/templates/xreview/xreview.sh" --by codex  --task "$TASK" --base origin/development --kind security   # 6b
```

Скрипт заполняет бриф `code-review-prompt.md` / `security-review-prompt.md`
из `docs/specs/$TASK.spec.md` и git, запускает ревьюера read-only и в
изоляции (§1, факты 19–20), читает вердикт из двух последних строк ответа и
пишет `docs/reviews/<TASK>-<sha7>-<by>[-security].md`; exit 0 — чисто, 1 —
блокирует, 2 — ревью не состоялось (никогда не «чисто»). Подробно, включая
ручные эквиваленты и что делать с расхождением двух ревью, —
`task-flow/skills/task/references/cross-review.md`.

Прежние ручные команды этого раздела **не использовать**: `claude -p` с
`--allowedTools 'Bash(git diff:*)…'` не read-only (`git diff --output=<file>`)
и в каталоге с проверяемым диффом исполняет его `.claude/settings*.json`
(хуки, `apiKeyHelper`); `codex exec -p reviewer` без `--ignore-rules`
выпускает `allow`-команды из песочницы. Штатный `codex exec review --base
<ветка>` по-прежнему полезен как дополнительное мнение (применяет `## Code
Review Rules` из `AGENTS.md`), но DoD не грейдит и бриф не принимает.

Дальше — контракт «After the review comes back» из шаблона: Critical/Required
блокируют, поведенческая находка → fix → **ре-ревью дельты той же чужой
моделью** (`--base <reviewed sha>`), `fix(review): <id>` по коммиту на
находку, `reviewed` из шапки отчёта — в evidence block. Два ревью нашли одно
и то же независимо — приоритет; разошлись во вердикте — не усреднять, а
решать человеку (или третьим прогоном с явным вопросом).

### 7.5 Security

- Фаза 6b task (LLM, другой моделью): `xreview.sh … --kind security` (§7.4).
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
   (`harnesses.md`) → `predict status/report` снапшоты → `run.sh` коммитит
   тик → `gates.sh` (диффы `predict report --json`, `gate_denies`, evidence
   vs DoD) → верификатор другой моделью через `xreview.sh`, вне протокола →
   `journal.py` → `deliver.sh` (только на gated/autonomous, только
   разрешённый класс действия) → checkout обратно к базе, чистый.
3. Лестница shadow → gated → autonomous и её пороги — без изменений; поля
   `executor_model`/`verifier_model`, демоушен по смене любой из двух.
4. Раннер-хост: AppArmor-профиль, `codex login` раннер-пользователя, trust
   хуков не нужен (флаг; checkout не trusted), `PREDICT` (кэш харнесса
   исполнителя) и `XREVIEW` в env-файле раннера, без плагинов памяти (GAPS).

Это loop-foundry 1.2.0 (S3 ✅): контракт — `references/harnesses.md`,
`predictions.md`, `ladder.md`; §7.2' остаётся ручным вариантом для одного тикета.

---

## 9. Ловушки

| Ловушка | Следствие | Что делать |
|---|---|---|
| `permissionDecision: ask` не поддерживается в Codex | до S1 гейт на Codex fail-open в клетках «ask» — one-way вне протокола **выполняется** | S1: deny; до S1 — на Codex всегда `predict on` перед one-way (тогда клетка «без квитанции» = deny уже сейчас) |
| Trust хуков по хэшу | после каждого обновления плагина хуки молча не работают до `/hooks` → Trust | `predict report` → `gate: never` = хук не срабатывал; раннер — флаг bypass |
| bwrap + AppArmor userns (Ubuntu 24.04) | любая команда модели в CLI-Codex падает | профиль §5.1 (sudo, один раз, и на раннер-хосте) |
| `.git`/`.codex`/`.agents` read-only в `workspace-write` | `git commit` = эскалация; под `never` — ошибка | `.rules` §5.3 или интерактивные approvals |
| Сеть off в `workspace-write` | `git push`/`pip`/`glab` — эскалация | `[sandbox_workspace_write] network_access = true` |
| `~/.local/state` read-only в `workspace-write` | `predict open`/`close` из шелла Codex-модели падают — квитанцию не открыть, каждый one-way = deny | так и оставить: `--add-dir` на корень состояния даёт модели выключить гейт вычисленным путём, незаметно (факт 26). One-way — после прогона руками или в `deliver.sh` лупа; квитанции в сессии — только у Claude (там гейт — свидетель, не граница) |
| Отказ хука в `codex exec --json` | в потоке событий его **нет** — grep по `command_execution` даёт пустой `gate_denies` при реальных отказах | читать отказы у инструмента: `predict status --json` → `denies` (prediction-protocol ≥ 1.2.0 пишет каждый отказ из хуков); stderr не разбирать — многострочную запись команда может подделать (5 раундов ревью loop-foundry 1.2.0) |
| `PREDICT` = новейший из двух кэшей (`sort -V` по полным путям) | сравниваются каталоги, не версии: при 1.2 у Claude и 1.1 у Codex берётся 1.1 из `.codex`; `selftest` доказывает не тот хук | `PREDICT` из кэша харнесса, чья сессия гейтится |
| `claude -p --output-format stream-json` без `--verbose` | `Error: … requires --verbose` — раннер не стартует | `--verbose` (факт 28; строка loop-foundry 1.1.0 его не несла) |
| `--dangerously-bypass-hook-trust` в trusted-checkout'е | исполнитель пишет `.codex/hooks.json`, следующая сессия исполняет его вне песочницы | checkout лупа никогда не trusted (факт 27) + чистый checkout на тик |
| Хук: JSON-deny + `exit 2` при пустом stderr | команда выполнилась (одно наблюдение, Codex 0.162.1) | писать причину и в stdout-JSON, и в stderr — как гейт prediction-protocol |
| `codex exec` читает stdin, если он не TTY | скрипт «висит» | `</dev/null` или `-` как промпт |
| `codex exec review --base` ≠ промпт | «cannot be used with [PROMPT]» | либо `--base`, либо бриф через `codex exec -p reviewer -` |
| Auto-режим Claude ↔ `codex exec` с записью | классификатор отказывает | оркестрирует раннер; интерактивно — обычный режим разрешений |
| Codex из шелла Claude (или наоборот) | `CLAUDE_*`/`CODEX_*` переменные наследуются вложенным харнессом: его хуки и шелл модели видят чужие `CLAUDE_CODE_SESSION_ID`/`CODEX_SESSION_ID` | хуки решают харнесс по stdin; `predict` при двух id требует `PP_SESSION`; раннер всегда экспортирует `PP_SESSION` |
| `codex exec -c approval_policy=on-request` | игнорируется: exec всегда `approval: never`, хуки видят `bypassPermissions` | интерактивную клетку (deny вместо ask) проверять в TUI; exec = делегированная сессия, как `claude -p` |
| Хэш trust после обновления плагина | хэш покрывает **определение** хука в `hooks.json` (команда, matcher, timeout, statusMessage), а не скрипт, который она запускает: 1.0.3 → 1.1.0 сменил четыре скрипта, trust сохранился ✅ 2026-10-15. Обратная сторона: обновлённый скрипт под прежней строкой команды доверен автоматически — доверие относится к источнику плагина, не к коду | меняется `hooks.json` → `/hooks` → Trust; раннер — `--dangerously-bypass-hook-trust`; алгоритм хэша воспроизводим (факт 17), но запись в чужой `config.toml` — решение владельца |
| `CLAUDE_PLUGIN_ROOT` в шелле модели на Codex | не задан (только хукам) | `ROOT` по пути `SKILL.md` — task-flow уже так умеет |
| `project_doc_max_bytes` 32 KiB | длинный AGENTS.md обрежется молча | вынести детали в `docs/`, оставить правила |
| Codex Security = Platform API key в CI | отдельный счёт | `--max-cost`, `low` effort на MR; или ChatGPT-auth раннера (приватные репо) |
| Имена скиллов | `/task-flow:task` (Claude) ↔ `$task-flow:task` (Codex) | Harness-раздел в SKILL (S2) |
| Git-маркетплейс с большим репо (claude-mem ≈ 560 МБ) | Codex клонирует с жёстким лимитом 30 с, по таймауту бросает `git clone` и оставляет `~/.codex/.tmp/marketplaces/.staging/marketplace-upgrade-*` (~720 МБ каждый); фоновый refresh повторяет это на каждом старте — за 2,5 дня 88 каталогов, 61 ГБ ✅ 2026-10-15 | источник плагина — локальный клон маркетплейса Claude (`codex plugin marketplace add ~/.claude/plugins/marketplaces/<name>`): без второго клона, версии в lockstep; обновление — `claude plugin marketplace update <name> && codex plugin add <plugin>@<marketplace>`; staging-каталоги удалить |
| `hook: <Event> Failed` в выводе `codex exec` | хук пропущен как недоверенный/изменившийся **или** его stdout не по контракту Codex. Проверено 2026-10-15: все скрипты rc=0, виновник — `security-guidance` (Anthropic, Claude-only): печатает `{"async":true,…}` + второй JSON — протокол асинхронных хуков Claude Code, для Codex «не один JSON-документ» → Failed на каждом событии | Claude-only плагины с хуками в Codex не ставить (security-guidance, statusline); `codex` → `/hooks` → Trust для остальных; superpowers хуков на Codex не имеет по замыслу автора (`.codex-plugin/plugin.json`: `"hooks": {}`) — бутстрап через описание скилла |
| `claude -p` в каталоге с проверяемым диффом | дифф, коммитящий `.claude/settings.json` / `settings.local.json`, исполняет хуки и `apiKeyHelper` в ревьюере; `.mcp.json` + `enableAllProjectMcpServers` даёт ему MCP-инструменты; `--tools` их не ограничивает | `xreview.sh` (без файлов настроек, `disableAllHooks`, `--strict-mcp-config`, без shell); вручную — те же флаги (факт 19) |
| `codex exec --ignore-user-config` как «изоляция» | пользовательские `.rules` всё равно грузятся; `allow` выводит команду из read-only песочницы | `--ignore-rules` у каждого ревьюера (факт 20) |
| Плагины памяти у ревьюера | claude-mem и др. пересказывают ревьюеру историю реализации — тот самый брифинг автором, который запрещает clean-context | изоляция по умолчанию в `xreview.sh`; опт-аут `XREVIEW_ISOLATE=0` только с причиной |
| Вердикт LLM-ревью в свободном Markdown | цитата, комментарий, отступ, вложенный fence читаются человеком и парсером по-разному → ложное «чисто» (три раунда ревью подряд) | вердикт отдельным каналом — две последние строки простым текстом; текст ревьюера в отчёте — одним буквальным блоком |
| Официальный GitLab-пример Codex Security как есть | не стартует на своём образе (нет `git`/`python3`), без порога никогда не падает, грязное дерево = exit 2 | шаблоны task-flow 1.12.0 (факт 23) |
| Абсолютный `~/.claude/skills/<skill>/…` в SKILL.md | у установленного плагина неверен в **обоих** харнессах (версионный кэш) — агент ищет скрипт сам или падает | путь от каталога SKILL.md: `scripts/…` или `<SKILL_DIR>/scripts/…` с объяснением (факт 32) |
| `"skills": ["./"]` в манифесте, скилл в подкаталоге | Claude скилл видит, Codex — нет, молча | `"skills": ["./<skill>/"]` (факт 30); после правки манифеста — `scripts/check-skills.sh --local <plugin>=<clone>` |
| Chromium, snap-приложения в песочнице Codex | не стартуют: `setsockopt`/`shutdown`/`send` → EPERM (в песочнице `Seccomp: 2`, `NoNewPrivs: 1`), snap-confine без capabilities, `snap run` без записи в `~/snap` (факт 33) | эскалация с первого вызова (`require_escalated`, md2pdf 1.3.1 так и делает); в `codex exec` — никак |
| `uv run` в песочнице Codex | `~/.cache/uv` read-only, сети нет → скрипт не стартует (premortem) | эскалация (правило префикса `uv run`); **не** давать песочнице писать в кэш uv через `writable_roots`: модель подложит пакет, который потом исполнится вне песочницы |
| Политика `NOT_AVAILABLE` в записи каталога | Codex отказывает только новым установкам: стоявший плагин остаётся `installed, enabled` (факт 35); Claude Code поле игнорирует с предупреждением `validate` | после введения политики — `codex plugin remove <plugin>@<marketplace>` руками; `Unknown field 'policy'` — единственное ожидаемое предупреждение (CLAUDE.md каталога) |
| Тег релиза без бампа `plugin.json` | оба харнесса ставят старую версию (premortem `plugin-v1.0.1` стоял как 1.0.0), кэш `…/<plugin>/<старая версия>/` | перед тегом сверить версию в `plugin.json` с тегом (у task-flow это делает `scripts/release-check.sh`, у форков — руками) |

---

## 10. Приёмка (что проверить вам — мне это недоступно из auto-режима)

После §5.1–5.2 на этом хосте, в пустом репо с пустым `origin`:

1. `codex sandbox -- echo SANDBOX_OK` → `SANDBOX_OK` — ✅ сделано 2026-10-15.
2. ✅ 2026-10-15 для `codex exec` (делегированная клетка) и для реплея stdin
   TUI через гейт — `tests/platform-probe.sh --codex` в prediction-protocol
   1.1.0 (deny JSON/exit 2 блокируют; ask/exit 1/битый JSON/таймаут —
   команда выполняется; под протоколом без квитанции — deny с рецептом дошёл
   до модели; с квитанцией — silent, квитанция consumed; `apply_patch` в
   стейт — deny стейт-гарда). **Остаётся вам**: интерактивный TUI после
   обновления до 1.1.0 и `/hooks` → Trust: вне протокола
   `git push --force origin main` → **deny**, текст упоминает «cannot ask».
3. `"$PREDICT" report` → `gate: seen <utc>` (хук реально срабатывал) — в TUI.
4. ✅ 2026-10-16, иначе, чем планировалось: перекрёстное ревью через
   `xreview.sh` в lab-репо с внесённым дефектом — Codex и Claude независимо
   нашли подавленную ошибку, off-by-one на обеих границах и отсутствующие
   тесты (вердикты разобраны, checkout не тронут). Штатный `codex exec review
   --base master` (с `## Code Review Rules`) по-прежнему не прогнан — **вам**.
5. ✅ 2026-10-15: `codex plugin marketplace upgrade devpowers && codex plugin add
   prediction-protocol@devpowers` → `…/cache/devpowers/prediction-protocol/1.1.0`;
   trust **не** запросил — `hooks.json` не менял определения хуков (см. §9).
6. `npx @openai/codex-security scan . --diff master --head HEAD --auth chatgpt
   --output-dir /tmp/sec --headless` в `lab`-репо → `findings.json`,
   `coverage.json`; если «access required» — решение про Trusted Access / API-ключ.
7. `/import` в Codex CLI из Claude Code — что именно переехало в
   `~/.codex/AGENTS.md`, `config.toml`, `~/.agents/skills`.
8. loop-foundry 1.2.0 (S3) — ✅ 2026-10-16 в лаборатории (`codex exec -s
   read-only`): `PP_SESSION` до хука и шелла модели, отказ только в stderr,
   модель только в rollout, проектный `.codex/` только у trusted. **Вам**
   (классификатор, факт 13): тик исполнителя Codex в `workspace-write` по
   строке `harnesses.md` — one-way без квитанции отклонён, `predict open` из
   шелла модели упал на read-only, `active = 1` после тика, отказ в
   `gate_denies`; `--dangerously-bypass-hook-trust` в недоверенном
   checkout'е с подложенным `.codex/hooks.json` — хук **не** исполнился;
   полный shadow-тик с обоими харнессами и записью журнала.
9. S4 — ✅ 2026-10-16 без модели: `scripts/check-skills.sh` — premortem, md2pdf,
   co-rar видны в обоих харнессах; md2pdf в `codex sandbox -P :workspace` падает с
   подсказкой об эскалации, вне песочницы под `~/<каталог>` даёт PDF. **Вам**, в
   интерактивном Codex: «сделай pdf из <md>» — агент сам просит эскалацию на первом
   вызове md2pdf (не после отказа), PDF появляется; `$premortem:premortem` на
   небольшом плане — `uv run` идёт через эскалацию (одобрить с префиксом), отчёт
   ложится в `docs/premortem/` проекта, а не в кэш плагина.
10. S5 — ✅ 2026-10-16 без модели: `scripts/check-skills.sh` — все 9 плагинов по
    контракту в обоих харнессах, statusline в Codex — `not installable`; каталог без
    политики даёт MISMATCH. **Вам**: `codex plugin remove statusline@devpowers` в своём
    `~/.codex` — там стоит 1.0.2, поставленный до S5.

Лабораторный каталог этой сессии (изолированный `CODEX_HOME` с
установленными плагинами, `lab`-репо с диффом, `lab-market` с двумя
вариантами premortem) — в scratchpad сессии; после приёмки его можно
удалить целиком.
