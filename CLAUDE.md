# CLAUDE.md

Сначала прочитать `RULES.md`: правила проекта, документы, чего не делать.

## Где что живёт

| Что | Где правда | Как править |
|---|---|---|
| Скрипты (88 шт.) | `src/` | файлами; в Studio их переносит Rojo |
| RemoteEvent'ы | `src/ReplicatedStorage/Remotes/*.model.json` | файлами: новый remote — новый файл `Имя.model.json` с `{"className": "RemoteEvent"}` |
| Карта, модели, шаблоны, GUI, звук, свет | только в месте Studio (`Workspace`, `ServerStorage`, `ReplicatedStorage.NormalBeetleTemplate`, `StarterGui`, `Lighting`, `SoundService`) | через MCP в Edit-режиме |
| Снимок всего места | `place/game.rbxl` | не править; обновляется экспортом из Studio |

Rojo-проект — `default.project.json`. Он управляет только скриптами и `Remotes`, всё остальное
в сервисах не трогает (`$ignoreUnknownInstances`).

## Главное правило после переезда на Rojo

**Не менять `.Source` скриптов через MCP** (`execute_luau` с `gsub`, запись `Source`, правка в
редакторе Studio). Rojo перезапишет это содержимым `src/` при следующей синхронизации — правка
тихо пропадёт. Код правится только файлами в `src/`.

То же с RemoteEvent'ами: не создавать и не удалять их через MCP — только файлом в `Remotes/`.

## Для чего MCP Studio

- Play-тесты, чтение Output, проверки через `execute_luau` (только чтение или временные данные).
- Правка карты, моделей и шаблонов в Edit-режиме. После неё автору нужно сохранить место
  (Ctrl+S / Save to Roblox) — написать это в отчёте.
- Код через MCP не читать: он дублирует `src/` и стоит дороже.

## Как читать код дёшево

- Искать `grep -rn` по `src/`, читать только найденный кусок (`Read` с `offset`/`limit`).
- Крупные файлы — не открывать целиком: `CraftingUI.client.luau` (~190 КБ), `TowerBuilder.luau`,
  `UITheme.luau`, `Effects.luau` (>100 КБ), `Elements.luau`, `EnemySpawner.luau`, `TowerInteraction.client.luau`.

## Облачная сессия (без Studio)

Правит `src/`, затем `tools/bin/lune run tools/sync build` пересобирает `place/game.rbxl`
(`tools/get-lune.sh` — скачать Lune). Тест в Studio делает автор или локальная сессия.
