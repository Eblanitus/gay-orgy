"""Загрузка .glb в Roblox через Open Cloud — чтобы агент вставлял модели в Studio сам, без Import 3D.

    python tools/upload_models.py                    # все .glb из «Модели/Жуки» (кроме all_beetles.glb)
    python tools/upload_models.py Модели/Жуки/moth.glb ...

Нужно в окружении:
    ROBLOX_API_KEY  — ключ Open Cloud (create.roblox.com → Open Cloud → API Keys, право Assets: read + write)
    ROBLOX_USER_ID  — id аккаунта-владельца (или ROBLOX_GROUP_ID для группы)

Каждый файл уходит ассетом Model; id пишется в «Модели/asset_ids.json» вместе с sha1 файла —
неизменённый файл второй раз не грузится. Дальше агент через MCP Studio: insert_asset по id
(в ServerStorage), затем tools/prepare_beetles.luau — он найдёт импорт по имени вида.
"""

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = ROOT / "Модели" / "Жуки"
IDS_FILE = ROOT / "Модели" / "asset_ids.json"
API = "https://apis.roblox.com/assets/v1/"


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
        "assetType": "Model",
        "displayName": path.stem,
        "description": "alchemy lab: " + path.name,
        "creationContext": {"creator": creator},
    }
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'.encode(),
        json.dumps(meta).encode(),
        (
            f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
            f'filename="{path.stem}.glb"\r\nContent-Type: model/gltf-binary\r\n\r\n'
        ).encode(),
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    op = request("POST", API + "assets", key, b"".join(parts), f"multipart/form-data; boundary={boundary}")
    # Загрузка асинхронная: опрашиваем операцию, пока не появится assetId.
    for _ in range(90):
        if op.get("done"):
            if "error" in op:
                raise RuntimeError(f"{path.name}: {op['error']}")
            return op["response"]["assetId"]
        time.sleep(2)
        op = request("GET", API + op["path"], key)
    raise RuntimeError(f"{path.name}: загрузка не завершилась за 3 минуты")


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

    files = [Path(a).resolve() for a in sys.argv[1:]] or sorted(
        p for p in DEFAULT_DIR.glob("*.glb") if p.name != "all_beetles.glb"
    )
    ids = json.loads(IDS_FILE.read_text("utf-8")) if IDS_FILE.exists() else {}
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


if __name__ == "__main__":
    main()
