"""Ключ Open Cloud и владелец ассетов для скриптов загрузки (upload_models, upload_sounds,
upload_patterns).

Откуда берутся, по порядку:
  1. переменные окружения ROBLOX_API_KEY и ROBLOX_USER_ID (или ROBLOX_GROUP_ID);
  2. файл tools/roblox_key.txt — строки ROBLOX_API_KEY=… и ROBLOX_USER_ID=… (или просто ключ
     одной строкой и id числом другой). В git он не попадает (.gitignore);
  3. вопрос в консоли: ответ сохраняется в tools/roblox_key.txt, второй раз не спросит.

Режим прокси (ROBLOX_AUTH_PROXY=1, облачная сессия): ключ подставляет прокси окружения сам,
скрипту он не нужен — load() отдаёт пустой ключ, и заголовок x-api-key не ставится.
Нужен только владелец (ROBLOX_USER_ID или ROBLOX_GROUP_ID).
"""

import os
import sys
from pathlib import Path

KEY_FILE = Path(__file__).resolve().parent / "roblox_key.txt"
NAMES = ("ROBLOX_API_KEY", "ROBLOX_USER_ID", "ROBLOX_GROUP_ID")


def _from_file():
    found = {}
    if not KEY_FILE.exists():
        return found
    for line in KEY_FILE.read_text("utf-8-sig").splitlines():
        line = line.strip().strip('"').strip("'")
        if not line or line.startswith("#"):
            continue
        name, sep, value = line.partition("=")
        if sep and name.strip().upper() in NAMES:
            found[name.strip().upper()] = value.strip().strip('"').strip("'")
        elif line.isdigit():
            found.setdefault("ROBLOX_USER_ID", line)
        else:
            found.setdefault("ROBLOX_API_KEY", line)
    return found


def load():
    """(ключ, creator) для Open Cloud Assets API."""
    values = _from_file()
    for name in NAMES:
        if os.environ.get(name):
            values[name] = os.environ[name]
    proxy = os.environ.get("ROBLOX_AUTH_PROXY") not in (None, "", "0")
    if proxy:
        values["ROBLOX_API_KEY"] = ""
    asked = False
    if not proxy and not values.get("ROBLOX_API_KEY"):
        values["ROBLOX_API_KEY"] = input("Ключ Open Cloud (ROBLOX_API_KEY): ").strip()
        asked = True
    if not values.get("ROBLOX_USER_ID") and not values.get("ROBLOX_GROUP_ID"):
        values["ROBLOX_USER_ID"] = input("id аккаунта Roblox (ROBLOX_USER_ID): ").strip()
        asked = True
    if not proxy and not values["ROBLOX_API_KEY"]:
        sys.exit("нет ключа ROBLOX_API_KEY")
    if asked:
        KEY_FILE.write_text("".join(f"{n}={values[n]}\n" for n in NAMES if values.get(n)), "utf-8")
        # в режиме прокси ключа в values нет — в файл уходит только владелец
        print(f"сохранено в {KEY_FILE}, второй раз не спрошу")
    if values.get("ROBLOX_GROUP_ID"):
        return values["ROBLOX_API_KEY"], {"groupId": values["ROBLOX_GROUP_ID"]}
    if values.get("ROBLOX_USER_ID"):
        return values["ROBLOX_API_KEY"], {"userId": values["ROBLOX_USER_ID"]}
    sys.exit("нет ROBLOX_USER_ID (или ROBLOX_GROUP_ID)")
