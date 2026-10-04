# CLAUDE.md

Сначала прочитать `RULES.md`: правила проекта, документы, чего не делать.

## Папки документов

- `ВИКИПЕДИЯ/` — действующие дизайн-документы (список и правила — в `RULES.md`).
- `Устаревшие документы/` — отработавшие ТЗ, старые версии вики, `STATE.md`, архивный `CHANGELOG.md` (#1–#232). Не читать без нужды.
- `Отчёты/` — сводки по неделям для автора. Агенту не нужны.
- `Паттерны/` — картинки узоров элементов: `Исходники/` — исходники, `out/` — готовые маски `p_<Элемент>.png`
  (`неиспользуемое/`, `Переделать/` — отложенные), `build_patterns.py` — переводит исходники в маски.
  Картинки не открывать без задачи по паттернам — каждая стоит много контекста.
- `Модели/` — авторские .glb. `Модели/Жуки/` — жуки: сами .glb генерирует `tools/beetles/build_all.py`
  (форма каждого вида — `tools/beetles/species.py`), шаблоны из них собирает `tools/prepare_beetles.luau`
  (Command Bar в Studio после Import 3D). Поменял цвета в `species.py` — таблицу COLORS для
  `prepare_beetles` печатает `tools/beetles/colors_lua.py`.
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
- Крупные файлы (>60 КБ) — не открывать целиком:
  `Elements.luau`, `EnemySpawner.luau`, `TowerInteraction.client.luau`, `EnemyGait.luau`, `Effects.luau`,
  `ProfileStore.luau`.
- Большие файлы разрезаны на модули (задача #240): `CraftingUI` → `CraftingBuyTab`, `CraftingProducer`,
  `CraftingCraftTab`, `CraftingReference`; `UITheme` → `UIThemePanel`, `UIThemeButtons`;
  `TowerBuilder` → `TowerModels`, `TowerFiring`; `Effects` → `EffectsDebuffs`; `CraftingReference` →
  `ReferenceWire`, `ReferenceDraw`, `ReferenceList`, `ReferenceInput`, `ReferenceSections`. Модуль —
  `return function(deps) ... end`: в начале `local x = deps.x` — локальные основного файла,
  в конце — что основной файл использует дальше. У модулей `CraftingReference` изменяемое общее
  (раскладка `graph`, масштаб `zoom`, выбор `selected`, функции `repaint`, `selectNode`…) лежит
  в таблице `ref`: местная копия в модуле не увидела бы новое значение.

## Справочник лаборатории

- `CraftingReference` — вкладка справочника: разделы «Жуки», «Карта» (граф рецептов), «Элементы»,
  поиск, карточка выбранного узла, метка «● можно скрафтить». Кривые карты — `ReferenceWire`,
  узлы, подсветка и поворот — `ReferenceDraw`, список под картой и выбор — `ReferenceList`,
  протяжка и масштаб — `ReferenceInput`, разделы, поиск, «+N» и события сервера — `ReferenceSections`.
- `ReferencePages` — разделы «Элементы» и «Жуки» (сетка + карточка), `ReferenceDetail` — сама
  карточка элемента/жука (общая для карты и разделов).
- Тексты описаний — `ReplicatedStorage/ReferenceTexts.luau`: для игрока, по смыслу вики, но без
  заметок разработки, цифр и жаргона. Правится руками; поменялась механика в вики — поправить и тут.
- Характеристики словами («быстрая», «огромный») — `EntityInfo.ElementStats`, пороги слов — таблицы
  `EntityInfo.*_WORDS`. Строки «особенности» (как стреляет турель) и «эффект» (что остаётся на жуке
  и на карте) — таблицы `EntityInfo.ELEMENT_FEATURES` / `ELEMENT_EFFECTS`, имена зон — `ZONE_NAMES`.
- Журнал главного меню (`JournalUI`) — только статистика.

## Физика

Всё незакреплённое (трупы, лапы, осколки, дальше обломки турелей) идёт через общий слой
`ReplicatedStorage/Loose.luau`: группы столкновений, метка `Loose`, толчок, взрыв и отдача, папки,
растворение, потолок числа деталей (`Track`), опора лучом (`FloorAt`). Числа — `PhysicsFX`. Новую физику своим кодом не писать.

## Облачная сессия (без Studio)

Правит `src/`, затем `tools/bin/lune run tools/sync build` пересобирает `place/game.rbxl`
(`tools/get-lune.sh` — скачать Lune). Тест в Studio делает автор или локальная сессия.
