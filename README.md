# Алхимический Tower Defense (Roblox)

- `place/game.rbxl` — вся игра целиком (карта, модели, интерфейс, скрипты). Открывается в Roblox Studio через **File → Open from File**.
- `src/` — те же скрипты текстом, по папкам как в Explorer. Здесь удобно читать код и смотреть историю изменений.

Суффикс файла задаёт тип скрипта: `.server.luau` — Script, `.client.luau` — LocalScript, `.luau` — ModuleScript.

## Синхронизация

```sh
tools/get-lune.sh                       # один раз: скачать Lune
tools/bin/lune run tools/sync extract   # place/game.rbxl -> src/  (после правок в Studio)
tools/bin/lune run tools/sync build     # src/ -> place/game.rbxl  (после правок кода)
```
