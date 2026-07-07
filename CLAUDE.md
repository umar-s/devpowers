# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это за репозиторий

Зонтичный marketplace-каталог **devpowers** — продуктовая линейка Claude Code-плагинов владельца (umar-s). Здесь нет кода и самих плагинов: только `.claude-plugin/marketplace.json`, записи которого ссылаются на отдельные репозитории плагинов через `git-subdir`-источники с `ref: main` (без фиксации sha — плагины обновляются своими push'ами, релизного шага здесь нет).

Версии плагинов здесь не хранятся — единственный источник версии каждого плагина — его собственный `plugin.json`. Конвенции каталога взяты из anthropics/knowledge-work-plugins: лаконичные записи (`name`, `displayName`, `description`, `category`, `homepage`, `source`), без дублирования версий.

## Команды

Проверка каталога после правок:

```bash
claude plugin validate .
```

Локальная проверка установки (в Claude Code, после — полный перезапуск сессии):

```
/plugin marketplace add /home/serpens/Project/devpowers
/plugin install <name>
```

## Добавление плагина в линейку

1. Плагин создаётся в собственном репозитории по макету: `plugins/<name>/` с `.claude-plugin/plugin.json`, скиллы в `plugins/<name>/skills/<skill>/SKILL.md` (см. umar-s/loop-foundry как образец).
2. Сюда добавляется одна запись в `marketplace.json` с `git-subdir`-источником: `url` репозитория, `path: plugins/<name>`, `ref: main`.
3. `claude plugin validate .`, коммит, push.

Таблицу плагинов в README держать синхронной с `marketplace.json`.
