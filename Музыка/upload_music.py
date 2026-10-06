"""Загрузка музыки в Roblox через Open Cloud.

    python upload_music.py                  # mpledni_box.ogg из этой же папки
    python upload_music.py a.ogg b.mp3 ...  # свои файлы

Ключ берётся из ROBLOX_API_KEY, автор — из ROBLOX_USER_ID (или ROBLOX_GROUP_ID).
Если их нет, скрипт спросит сам; ключ при вводе не виден и никуда не сохраняется.
Печатает ID ассета и статус модерации. Подходят .ogg, .mp3, .wav, .flac.
"""

import getpass
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_FILES = ["mpledni_box.ogg"]
DEFAULT_USER_ID = "1116585926"
API = "https://apis.roblox.com/assets/v1/"
TYPES = {".ogg": "audio/ogg", ".mp3": "audio/mpeg", ".wav": "audio/wav", ".flac": "audio/flac"}


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code} {e.read().decode(errors='replace')}") from None


def upload(path, key, creator):
    mime = TYPES.get(path.suffix.lower())
    if not mime:
        raise RuntimeError(f"формат {path.suffix} не подходит, нужен один из {', '.join(TYPES)}")
    meta = {
        "assetType": "Audio",
        "displayName": path.stem,
        "description": path.stem,
        "creationContext": {"creator": creator},
    }
    boundary = uuid.uuid4().hex
    body = b"".join([
        f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'.encode(),
        json.dumps(meta).encode(),
        (
            f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
            f'filename="{path.name}"\r\nContent-Type: {mime}\r\n\r\n'
        ).encode(),
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    op = request("POST", API + "assets", key, body, f"multipart/form-data; boundary={boundary}")
    # Загрузка идёт в фоне: ждём, пока Roblox выдаст ID.
    for _ in range(150):
        if op.get("done"):
            if "error" in op:
                raise RuntimeError(str(op["error"]))
            return op["response"]["assetId"]
        time.sleep(2)
        op = request("GET", API + op["path"], key)
    raise RuntimeError("Roblox не закончил загрузку за 5 минут")


def moderation(asset_id, key):
    info = request("GET", API + f"assets/{asset_id}?readMask=moderationResult", key)
    return info.get("moderationResult", {}).get("moderationState", "неизвестно")


def main():
    key = os.environ.get("ROBLOX_API_KEY") or getpass.getpass("Ключ Open Cloud (не виден при вводе): ").strip()
    if os.environ.get("ROBLOX_GROUP_ID"):
        creator = {"groupId": os.environ["ROBLOX_GROUP_ID"]}
    else:
        user_id = os.environ.get("ROBLOX_USER_ID") or DEFAULT_USER_ID
        creator = {"userId": user_id}

    names = sys.argv[1:] or DEFAULT_FILES
    for name in names:
        path = Path(name)
        if not path.is_absolute() and not path.exists():
            path = HERE / name
        print(f"{path.name}: гружу...")
        try:
            asset_id = upload(path, key, creator)
        except Exception as e:  # noqa: BLE001
            print(f"{path.name}: ОШИБКА {e}")
            continue
        print(f"{path.name}: ID {asset_id}, rbxassetid://{asset_id}, модерация: {moderation(asset_id, key)}")
    input("\nГотово. Enter — закрыть окно.")


if __name__ == "__main__":
    main()
