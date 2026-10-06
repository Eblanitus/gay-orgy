# CLAUDE.md

Сначала прочитать `RULES.md`: правила проекта, документы, чего не делать.

## Папки документов

- `ВИКИПЕДИЯ/` — действующие дизайн-документы (список и правила — в `RULES.md`).
- `Устаревшие документы/` — отработавшие ТЗ, старые версии вики, `STATE.md`, архивный `CHANGELOG.md` (#1–#232). Не читать без нужды.
- `Отчёты/` — сводки по неделям для автора. Агенту не нужны.
- `Паттерны/` — картинки узоров элементов: `Исходники/` — исходники, `out/` — готовые маски `p_<Элемент>.png`
  (`неиспользуемое/`, `Переделать/` — отложенные), `build_patterns.py` — переводит исходники в маски.
  Картинки не открывать без задачи по паттернам — каждая стоит много контекста.
- `Модели/` — авторские .glb. `Модели/Жуки/` — жуки (все 26 видов): сами .glb генерирует `tools/beetles/build_all.py`
  (форма каждого вида — `tools/beetles/species.py` и `species2.py`, все виды разом — `all_beetles.glb`),
  шаблоны из них собирает `tools/prepare_beetles.luau` (Command Bar в Studio после Import 3D). Поменял цвета в `species.py` — таблицу COLORS для
  `prepare_beetles` печатает `tools/beetles/colors_lua.py` (`--lengths` — длины для его SPECS).
  Без Import 3D: `tools/upload_models.py` грузит .glb в Roblox (Open Cloud, ключ в `ROBLOX_API_KEY`),
  id — в `Модели/asset_ids.json`; агент вставляет их через MCP `insert_asset` и запускает `prepare_beetles`.
- `Звуки/` — звуки игры (.ogg). Черновой набор собирает `tools/synth_sounds.py`, в Roblox их грузит
  `tools/upload_sounds.py` (нужен `ROBLOX_API_KEY`) и сам пишет id в `src/ReplicatedStorage/SoundIds.luau`.
- `inbox/` — сюда автор заливает файлы через GitHub; агент раскладывает их по папкам.

## Где что живёт

| Что | Где правда | Как править |
|---|---|---|
| Скрипты (~100 шт.) | `src/` | файлами; в Studio их переносит Rojo |
| RemoteEvent'ы | `src/ReplicatedStorage/Remotes/*.model.json` | файлами: новый remote — новый файл `Имя.model.json` с `{"className": "RemoteEvent"}` |
| Группы звука `SoundService.Master.Music`, `.Combat`, `.Ambient` | `src/SoundService/Master/*.model.json` | файлом, как remote |
| Звуки игры (бой, жуки, фон, музыка) | файлы — `Звуки/`, что и как звучит — `ReplicatedStorage/SoundBank.luau`, id — `SoundIds.luau` | см. «Звук» ниже |
| Карта, модели, шаблоны, GUI, звук, свет | только в месте Studio (`Workspace`, `ServerStorage`, `ReplicatedStorage.NormalBeetleTemplate`, `StarterGui`, `Lighting`, `SoundService`) | через MCP в Edit-режиме |
| Снимок всего места | `place/game.rbxl` | не править; обновляется экспортом из Studio |

Rojo-проект — `default.project.json`. Он управляет только скриптами, `Remotes` и группами `SoundService.Master` (Music, Combat, Ambient), всё остальное
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

## Размер текста — мелкий запрещён

**Мельче 14 px текста в интерфейсе нет. Нигде.** Ни подписей, ни «второстепенных» строк,
ни статусов, ни подсказок, ни на телефоне, ни на ПК. Мелкий текст — мусор (запрет автора).

- Число одно — `Theme.MIN_TEXT` (`UITheme`). Новый код пишет `TextSize = Theme.MIN_TEXT` или больше,
  а не своё число. Экран загрузки (`ReplicatedFirst`) UITheme не видит — там своя копия числа.
- То же для `<font size>` в RichText (`Theme.Readout` сам не даёт меньше), для `MinTextSize`
  у `UITextSizeConstraint` и для подбора кегля «пока не влезет» — пол у такого подбора `Theme.MIN_TEXT`.
- Не влезает — растёт рамка, строка или ячейка (перенос, `AutomaticSize`, ширина по замеру),
  а не уменьшается шрифт.
- `TextScale.client` дотягивает до минимума любую надпись в `PlayerGui` — это страховка, а не повод
  ставить меньше: раскладку под 14 px окно обязано считать само, иначе текст обрежется.

## Без «>» и «//» в текстах интерфейса

Декоративных `>` в начале строк и `//` между частями строки нет ни в одном интерфейсе
(решение автора). Раздел и текст — через двоеточие («ОБУЧЕНИЕ: шаг»: `Theme.StatusText`,
`Theme.ArenaText`, `Theme.Status`), подпись и пометка — через «·» (`Theme.Section`),
заголовки — просто заглавными (`Theme.Title`). Выбранный пункт меню — выворотка плашки,
не скобка. `>` по смыслу (сравнения, разметка RichText) это правило не трогает.

## Физика

Всё незакреплённое (трупы, лапы, осколки, дальше обломки турелей) идёт через общий слой
`ReplicatedStorage/Loose.luau`: группы столкновений, метка `Loose`, толчок, взрыв и отдача, папки,
растворение, потолок числа деталей (`Track`), опора лучом (`FloorAt`). Числа — `PhysicsFX`. Новую физику своим кодом не писать.

## Облачная сессия (без Studio)

Правит `src/`, затем `tools/bin/lune run tools/sync build` пересобирает `place/game.rbxl`
(`tools/get-lune.sh` — скачать Lune). Тест в Studio делает автор или локальная сессия.

## Звук

- Интерфейс — `UISound` + `SoundService.UISounds` (Sound'ы живут в месте, правятся в Studio).
- Игра — `GameAudio.client` по событиям, которые сервер уже шлёт для эффектов (`ShotFired`, `Explosion`,
  `EnemyFX`, `WaveChanged`, `RunEnded`). Какой звук на что, громкость, разброс высоты, дальность, лимит
  копий — таблицы `SoundBank`. Новый звук: файл в `Звуки/`, строка в `SoundBank`, `upload_sounds.py`.
- Звук без id в `SoundIds` молча не играет — игра не ломается, пока звуки не загружены.
