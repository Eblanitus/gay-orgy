# Алхимический Tower Defense (Roblox)

- `src/` — все скрипты и RemoteEvent'ы текстом, по папкам как в Explorer.
- `place/game.rbxl` — снимок всего места (карта, модели, шаблоны). Открывается в Studio через **File → Open from File**.
- `default.project.json` — проект Rojo: переносит `src/` в Studio.
- `ВИКИПЕДИЯ/` — дизайн-документы, `Устаревшие документы/` — архив, `Отчёты/` — сводки по неделям.
- `Паттерны/` — узоры элементов: исходники, готовые маски (`out/`) и скрипт `build_patterns.py`.
- `inbox/` — сюда заливать файлы через GitHub (Add file → Upload files).
- `RULES.md`, `CLAUDE.md` — правила для агентов, история задач — в коммитах (`git log`), старый CHANGELOG — в `Устаревшие документы/`.

Суффикс файла задаёт тип скрипта: `.server.luau` — Script, `.client.luau` — LocalScript, `.luau` — ModuleScript.

## Rojo: код из src/ в Studio

**Обычный запуск:** двойной клик по `start.bat`. Он запускает Rojo и раз в 30 секунд забирает изменения с GitHub — в Studio остаётся только один раз нажать **Connect**.

Первая настройка:

1. Скачать Rojo 7.7 (`rojo-…-windows-x86_64.zip`): https://github.com/rojo-rbx/rojo/releases и положить `rojo.exe` в папку репозитория (в Git он не попадает).
2. Один раз дважды кликнуть `rojo.exe` — он ставит плагин в Studio.

Rojo меняет только скрипты и `ReplicatedStorage.Remotes`. Карта и модели остаются как есть.

## Без Studio (облачная сессия)

```sh
tools/get-lune.sh                       # один раз: скачать Lune
tools/bin/lune run tools/sync extract   # place/game.rbxl -> src/
tools/bin/lune run tools/sync build     # src/ -> place/game.rbxl
```
