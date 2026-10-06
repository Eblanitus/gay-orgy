"""Загрузка звуков из «Звуки/» в Roblox через Open Cloud и запись их id в игру.

    python tools/upload_sounds.py               # все файлы из «Звуки/»
    python tools/upload_sounds.py Звуки/Boom.ogg ...

Ключ и владелец (tools/roblox_auth.py: окружение, tools/roblox_key.txt или вопрос в консоли):
    ROBLOX_API_KEY  — ключ Open Cloud (create.roblox.com → Open Cloud → API Keys, право Assets: read + write)
    ROBLOX_USER_ID  — id аккаунта-владельца (или ROBLOX_GROUP_ID для группы — тогда звук
                      сразу доступен месту группы)

Каждый файл уходит ассетом Audio; id и sha1 файла пишутся в «Звуки/asset_ids.json» —
неизменённый файл второй раз не грузится. После загрузки скрипт переписывает
src/ReplicatedStorage/SoundIds.luau: имя звука -> "rbxassetid://…". Дальше Rojo
переносит это в Studio, звук начинает играть без правки кода.
"""

import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

import roblox_auth

ROOT = Path(__file__).resolve().parent.parent
SOUND_DIR = ROOT / "Звуки"
IDS_FILE = SOUND_DIR / "asset_ids.json"
LUAU_FILE = ROOT / "src" / "ReplicatedStorage" / "SoundIds.luau"
API = "https://apis.roblox.com/assets/v1/"
TYPES = {".ogg": "audio/ogg", ".mp3": "audio/mpeg", ".wav": "audio/wav", ".flac": "audio/flac"}


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {url}: {e.code} {e.read().decode(errors='replace')}") from None


def upload(path, key, creator):
    meta = {
        "assetType": "Audio",
        "displayName": path.stem,
        "description": "alchemy td: " + path.name,
        "creationContext": {"creator": creator},
    }
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'.encode(),
        json.dumps(meta).encode(),
        (
            f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
            f'filename="{path.name}"\r\nContent-Type: {TYPES[path.suffix.lower()]}\r\n\r\n'
        ).encode(),
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    op = request("POST", API + "assets", key, b"".join(parts), f"multipart/form-data; boundary={boundary}")
    # Загрузка асинхронная (звук ещё проходит модерацию): опрашиваем операцию до assetId.
    for _ in range(90):
        if op.get("done"):
            if "error" in op:
                raise RuntimeError(f"{path.name}: {op['error']}")
            return op["response"]["assetId"]
        time.sleep(2)
        op = request("GET", API + op["path"], key)
    raise RuntimeError(f"{path.name}: загрузка не завершилась за 3 минуты")


def write_luau(ids):
    lines = [
        "-- Создаётся tools/upload_sounds.py — руками не править: следующая загрузка перепишет.",
        "-- Имя звука из ReplicatedStorage.SoundBank -> id ассета Audio. Нет строки — звук",
        "-- ещё не загружен в Roblox и в игре молча не играет.",
        "return {",
    ]
    for name in sorted(ids):
        lines.append(f'\t{name} = "rbxassetid://{ids[name]["assetId"]}",')
    lines.append("}")
    LUAU_FILE.write_text("\n".join(lines) + "\n", "utf-8")


def main():
    key, creator = roblox_auth.load()  # окружение, tools/roblox_key.txt или вопрос в консоли

    files = [Path(a).resolve() for a in sys.argv[1:]] or sorted(
        p for p in SOUND_DIR.iterdir() if p.suffix.lower() in TYPES
    )
    ids = json.loads(IDS_FILE.read_text("utf-8")) if IDS_FILE.exists() else {}
    try:
        for path in files:
            sha = hashlib.sha1(path.read_bytes()).hexdigest()
            known = ids.get(path.stem)
            if known and known["sha1"] == sha:
                print(f"{path.stem}: {known['assetId']} (без изменений)")
                continue
            asset_id = upload(path, key, creator)
            ids[path.stem] = {"assetId": asset_id, "sha1": sha}
            IDS_FILE.write_text(json.dumps(ids, ensure_ascii=False, indent=1, sort_keys=True), "utf-8")
            print(f"{path.stem}: {asset_id}")
    finally:
        # Даже если загрузка оборвалась на середине — то, что уже ушло, попадает в игру.
        write_luau(ids)


if __name__ == "__main__":
    main()
