"""Загрузка узоров жуков (Паттерны/out/Жуки/p_<ключ>.png) в Roblox и запись их id в игру.

    python tools/upload_patterns.py                   # все узоры жуков
    python tools/upload_patterns.py Паттерны/out/Жуки/p_Mini.png ...

Нужно в окружении (как у upload_sounds.py):
    ROBLOX_API_KEY  — ключ Open Cloud (create.roblox.com → Open Cloud → API Keys, права
                      Assets: read + write и Legacy Assets: manage — без последнего не узнать id картинки)
    ROBLOX_USER_ID  — id аккаунта-владельца (или ROBLOX_GROUP_ID для группы)

Картинка уходит ассетом Decal. ImageLabel показывает не декаль, а картинку внутри неё, у которой
свой id: скрипт берёт его из самой декали (Asset Delivery). id и sha1 файла пишутся в
«Паттерны/out/Жуки/asset_ids.json» — неизменённый файл второй раз не грузится. После загрузки
скрипт переписывает src/ReplicatedStorage/BeetlePatternIds.luau: ключ жука -> "rbxassetid://…".
Узоры строит tools/beetles/patterns.py.
"""

import gzip
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAT_DIR = ROOT / "Паттерны" / "out" / "Жуки"
IDS_FILE = PAT_DIR / "asset_ids.json"
LUAU_FILE = ROOT / "src" / "ReplicatedStorage" / "BeetlePatternIds.luau"
API = "https://apis.roblox.com/assets/v1/"
TYPES = {".png": "image/png"}


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
        "assetType": "Decal",
        "displayName": "beetle_" + key_of(path),
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
    # Загрузка асинхронная (картинка ещё проходит модерацию): опрашиваем операцию до assetId.
    for _ in range(90):
        if op.get("done"):
            if "error" in op:
                raise RuntimeError(f"{path.name}: {op['error']}")
            return image_id(op["response"]["assetId"], key)
        time.sleep(2)
        op = request("GET", API + op["path"], key)
    raise RuntimeError(f"{path.name}: загрузка не завершилась за 3 минуты")


def image_id(decal_id, key):
    """id картинки внутри декали: декаль хранит ссылку на неё в свойстве Texture."""
    loc = request("GET", f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{decal_id}", key)["location"]
    with urllib.request.urlopen(loc, timeout=120) as r:
        body = r.read()
    if body[:2] == b"\x1f\x8b":
        body = gzip.decompress(body)
    m = re.search(rb"(?:asset/\?id=|rbxassetid://)(\d+)", body)
    if not m:
        raise RuntimeError(f"декаль {decal_id}: не нашёл в ней id картинки")
    return m.group(1).decode()


def write_luau(ids):
    lines = [
        "-- Создаётся tools/upload_patterns.py — руками не править: следующая загрузка перепишет.",
        "-- Ключ жука из ReplicatedStorage.Enemies -> id картинки его узора. Нет строки — узор",
        "-- ещё не загружен в Roblox, ячейка жука показывается без узора.",
        "return {",
    ]
    for name in sorted(ids):
        lines.append(f'\t{name} = "rbxassetid://{ids[name]["assetId"]}",')
    lines.append("}")
    LUAU_FILE.write_text("\n".join(lines) + "\n", "utf-8")


def key_of(path):
    return path.stem.removeprefix("p_")


def main():
    key = os.environ.get("ROBLOX_API_KEY")
    if not key:
        sys.exit("нет ROBLOX_API_KEY")
    if os.environ.get("ROBLOX_GROUP_ID"):
        creator = {"groupId": os.environ["ROBLOX_GROUP_ID"]}
    elif os.environ.get("ROBLOX_USER_ID"):
        creator = {"userId": os.environ["ROBLOX_USER_ID"]}
    else:
        sys.exit("нет ROBLOX_USER_ID (или ROBLOX_GROUP_ID)")

    files = [Path(a).resolve() for a in sys.argv[1:]] or sorted(PAT_DIR.glob("p_*.png"))
    ids = json.loads(IDS_FILE.read_text("utf-8")) if IDS_FILE.exists() else {}
    try:
        for path in files:
            sha = hashlib.sha1(path.read_bytes()).hexdigest()
            known = ids.get(key_of(path))
            if known and known["sha1"] == sha:
                print(f"{key_of(path)}: {known['assetId']} (без изменений)")
                continue
            asset_id = upload(path, key, creator)
            ids[key_of(path)] = {"assetId": asset_id, "sha1": sha}
            IDS_FILE.write_text(json.dumps(ids, ensure_ascii=False, indent=1, sort_keys=True), "utf-8")
            print(f"{key_of(path)}: {asset_id}")
    finally:
        # Даже если загрузка оборвалась на середине — то, что уже ушло, попадает в игру.
        write_luau(ids)


if __name__ == "__main__":
    main()
