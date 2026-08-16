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

## Релизы и версии в линейке

Каталог версий не хранит, но каждый плагинный репозиторий ведёт их традиционно —
чтобы версия и прогресс были видны с витрины GitHub, а не только в `plugin.json`:

1. бамп в `plugin.json` (единственный источник истины);
2. секция в `CHANGELOG.md` — Keep a Changelog (`Added/Changed/Fixed`) плюс
   compare-ссылка внизу;
3. аннотированный тег на коммите, который несёт оба пункта выше;
4. GitHub Release, тело которого — та самая секция changelog
   (`gh release create <tag> --notes-file … --verify-tag`).

Схема тегов зависит от формы репозитория, а не от каталога:

- один плагин в репозитории → `vX.Y.Z` (`task-flow`, `md2pdf`, `co-rar`,
  `loop-foundry`);
- несколько плагинов в одном репозитории → `<plugin>-vX.Y.Z`
  (`research-pipeline`, `voxscribe`) — тег обязан различать, что именно вышло;
- форк чужого скилла → префикс `plugin-vX.Y.Z` (`premortem`). У апстрима свои
  теги `vX.Y.Z` на других коммитах: одинаковое имя тега при синхронизации форка
  — конфликт. Номер здесь версионирует упаковку, а не сам скилл, и README форка
  не трогаем вообще, иначе мержи из апстрима перестают быть бесконфликтными.

Бейдж версии в README читает последний Release, поэтому пропущенный шаг 4
оставляет бейдж протухшим. Установка при этом всегда идёт с дефолтной ветки —
записи каталога не пинят `ref`, — так что теги размечают историю, а не раздачу.

Сам каталог версии не имеет: у него дата-ориентированный `CHANGELOG.md` и нет
тегов/релизов. Это осознанно — «версия каталога» не значила бы ничего.

## Добавление плагина в линейку

1. Плагин создаётся в собственном репозитории по макету: `plugins/<name>/` с `.claude-plugin/plugin.json`, скиллы в `plugins/<name>/skills/<skill>/SKILL.md` (см. umar-s/loop-foundry как образец).
2. Сюда добавляется одна запись в `marketplace.json` с `git-subdir`-источником: `url` репозитория, `path: plugins/<name>`, `ref: main`.
3. `claude plugin validate .`, коммит, push.

Таблицу плагинов в README держать синхронной с `marketplace.json`.
