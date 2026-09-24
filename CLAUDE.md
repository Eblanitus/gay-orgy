# CLAUDE.md

Сначала прочитать `RULES.md`: правила проекта, документы, чего не делать.

## Папки документов

- `ВИКИПЕДИЯ/` — действующие дизайн-документы (список и правила — в `RULES.md`).
- `Устаревшие документы/` — отработавшие ТЗ, старые версии вики, `STATE.md`, архивный `CHANGELOG.md` (#1–#232). Не читать без нужды.
- `Отчёты/` — сводки по неделям для автора. Агенту не нужны.
- `Паттерны/` — картинки узоров элементов: `Исходники/` — исходники, `out/` — готовые маски `p_<Элемент>.png`
  (`неиспользуемое/`, `Переделать/` — отложенные), `build_patterns.py` — переводит исходники в маски.
  Картинки не открывать без задачи по паттернам — каждая стоит много контекста.
- `inbox/` — сюда автор заливает файлы через GitHub; агент раскладывает их по папкам.

## Где что живёт

| Что | Где правда | Как править |
|---|---|---|
| Скрипты (~100 шт.) | `src/` | файлами; в Studio их переносит Rojo |
| RemoteEvent'ы | `src/ReplicatedStorage/Remotes/*.model.json` | файлами: новый remote — новый файл `Имя.model.json` с `{"className": "RemoteEvent"}` |
| Группа звука `SoundService.Master.Music` | `src/SoundService/Master/Music.model.json` | файлом, как remote |
| Карта, модели, шаблоны, GUI, звук, свет | только в месте Studio (`Workspace`, `ServerStorage`, `ReplicatedStorage.NormalBeetleTemplate`, `StarterGui`, `Lighting`, `SoundService`) | через MCP в Edit-режиме |
| Снимок всего места | `place/game.rbxl` | не править; обновляется экспортом из Studio |

Rojo-проект — `default.project.json`. Он управляет только скриптами, `Remotes` и `SoundService.Master.Music`, всё остальное
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
- Крупные файлы (>60 КБ) — не открывать целиком: `CraftingReference.luau` (справочник, ~75 КБ),
  `Elements.luau`, `EnemySpawner.luau`, `TowerInteraction.client.luau`, `EnemyGait.luau`, `Effects.luau`,
  `ProfileStore.luau`.
- Большие файлы разрезаны на модули (задача #240): `CraftingUI` → `CraftingBuyTab`, `CraftingProducer`,
  `CraftingCraftTab`, `CraftingReference`; `UITheme` → `UIThemePanel`, `UIThemeButtons`;
  `TowerBuilder` → `TowerModels`, `TowerFiring`; `Effects` → `EffectsDebuffs`. Модуль —
  `return function(deps) ... end`: в начале `local x = deps.x` — локальные основного файла,
  в конце — что основной файл использует дальше.

## Справочник лаборатории

- `CraftingReference` — вкладка справочника: разделы «Жуки», «Карта» (граф рецептов), «Элементы»,
  поиск, карточка выбранного узла, метка «● можно скрафтить».
- `ReferencePages` — разделы «Элементы» и «Жуки» (сетка + карточка), `ReferenceDetail` — сама
  карточка элемента/жука (общая для карты и разделов).
- Тексты описаний — `ReplicatedStorage/ReferenceTexts.luau`: для игрока, по смыслу вики, но без
  заметок разработки, цифр и жаргона. Правится руками; поменялась механика в вики — поправить и тут.
- Характеристики словами («быстрая», «огромный») — `EntityInfo.ElementStats`, пороги слов — таблицы
  `EntityInfo.*_WORDS`.
- Журнал главного меню (`JournalUI`) — только статистика.

## Облачная сессия (без Studio)

Правит `src/`, затем `tools/bin/lune run tools/sync build` пересобирает `place/game.rbxl`
(`tools/get-lune.sh` — скачать Lune). Тест в Studio делает автор или локальная сессия.
