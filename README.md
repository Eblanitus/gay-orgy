# Алхимический Tower Defense (Roblox)

- `src/` — все скрипты и RemoteEvent'ы текстом, по папкам как в Explorer.
- `place/game.rbxl` — снимок всего места (карта, модели, шаблоны). Открывается в Studio через **File → Open from File**.
- `default.project.json` — проект Rojo: переносит `src/` в Studio.
- `RULES.md`, `CLAUDE.md` — правила для агентов, `CHANGELOG.md` — история задач.

Суффикс файла задаёт тип скрипта: `.server.luau` — Script, `.client.luau` — LocalScript, `.luau` — ModuleScript.

## Rojo: код из src/ в Studio

1. Установить Rojo 7.6: https://github.com/rojo-rbx/rojo/releases (или `aftman`/`rokit`), плагин — **Plugins → Manage Plugins** / Toolbox «Rojo».
2. В папке репозитория: `rojo serve`.
3. В Studio: плагин Rojo → **Connect**.

Rojo меняет только скрипты и `ReplicatedStorage.Remotes`. Карта и модели остаются как есть.

## Без Studio (облачная сессия)

```sh
tools/get-lune.sh                       # один раз: скачать Lune
tools/bin/lune run tools/sync extract   # place/game.rbxl -> src/
tools/bin/lune run tools/sync build     # src/ -> place/game.rbxl
```
