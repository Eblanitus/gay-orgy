"""Узоры жуков для ячеек справочника: python3 tools/beetles/patterns.py [Ключ ...]

Пятна с панциря модели (Модели/Жуки/*.glb) вырезаются по одному и разбрасываются по всей
текстуре: повёрнуты, отражены, разного размера, друг на друга не налезают. У видов без пятен
вместо них берутся пластины панциря (надкрылья, щит).

Маска — в негативе к элементам (решение автора): у элемента фон тёмный и узор светлый, у жука
фон светлый, а пятна вырезаны тёмным, так «чужое» видно сразу. Пишется в
Паттерны/out/Жуки/p_<ключ из Enemies>.png (1024×1024, белый, рисунок в альфе).
В Roblox их грузит tools/upload_patterns.py.

Нужны numpy, scipy, trimesh, Pillow. Результат при том же .glb один и тот же (seed постоянный).
"""
import re
import sys
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image
from scipy import ndimage as nd

ROOT = Path(__file__).resolve().parent.parent.parent
GLB = ROOT / "Модели" / "Жуки"
OUT = ROOT / "Паттерны" / "out" / "Жуки"
R = 1024
# Детали, которых сверху на спине нет или которые не рисунок: лапы, усы, глаза, голова.
SKIP = ("Ankle", "Ant", "Femur", "Knee", "Mandible", "ROOT", "Eye", "Tibia", "Tarsus", "Coxa", "Claw", "Leg",
        "Head", "Palp", "ThoraxCore", "BodyInner", "Tooth")
# Шаблон в Enemies -> файл .glb, где имя не выводится из шаблона.
GLB_NAME = {"NormalBeetle": "standard_beetle", "ArmoredBeetle": "hmuryi_bron"}


def species():
    src = (ROOT / "src" / "ReplicatedStorage" / "Enemies.luau").read_text()
    out = {}
    for key, body in re.findall(r"\n\t(\w+) = \{(.*?)\n\t\},", src, re.S):
        m = re.search(r'model = "(\w+)Template"', body)
        if m:
            name = GLB_NAME.get(m.group(1)) or re.sub(r"(?<!^)([A-Z])", r"_\1", m.group(1)).lower()
            out[key] = name
    return out


def render(name, size, inset):
    """Вид сверху: цвет и номер детали в каждом пикселе (z-буфер по высоте)."""
    sc = trimesh.load(GLB / f"{name}.glb", force="scene")
    tris, plate, area = [], [], {}
    for node in sc.graph.nodes_geometry:
        if any(k in node for k in SKIP):
            continue
        T, g = sc.graph[node]
        m = sc.geometry[g].copy()
        m.apply_transform(T)
        mat = getattr(m.visual, "material", None)
        c = getattr(mat, "baseColorFactor", None)
        c = tuple(int(x) for x in (c[:3] if c is not None else (128, 128, 128)))
        for tri in m.faces[m.face_normals[:, 1] > 0.02]:
            p = m.vertices[tri]
            tris.append((p[:, [0, 2]], node, c, p[:, 1]))
            (ux, uz), (vx, vz) = p[1, [0, 2]] - p[0, [0, 2]], p[2, [0, 2]] - p[0, [0, 2]]
            area[node] = area.get(node, 0) + abs(ux * vz - uz * vx)
        plate.append(m.vertices[:, [0, 2]])
    P = np.concatenate(plate)
    lo, hi = P.min(0), P.max(0)
    w = hi - lo
    lo, hi = lo + w * inset, hi - w * inset
    sx, sy = size / (hi - lo)
    col = np.zeros((size, size, 3), np.uint8)
    part = np.zeros((size, size), np.int32)
    zb = np.full((size, size), -1e9)
    ids = {}
    # Крупные детали первыми: пятна (мелкие детали поверх панциря) ложатся сверху.
    tris.sort(key=lambda t: (-area[t[1]], t[3].mean()))
    for p, node, c, hz in tris:
        q = np.column_stack(((p[:, 0] - lo[0]) * sx, (p[:, 1] - lo[1]) * sy))
        x0, y0 = np.maximum(np.floor(q.min(0)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(q.max(0)).astype(int), size - 1)
        if x1 < x0 or y1 < y0:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
        (ax, ay), (bx, by), (cx, cy) = q
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        l1 = ((by - cy) * (xx - cx) + (cx - bx) * (yy - cy)) / den
        l2 = ((cy - ay) * (xx - cx) + (ax - cx) * (yy - cy)) / den
        ins = (l1 >= -1e-6) & (l2 >= -1e-6) & (1 - l1 - l2 >= -1e-6)
        zb[y0:y1 + 1, x0:x1 + 1][ins] = (l1 * hz[0] + l2 * hz[1] + (1 - l1 - l2) * hz[2])[ins]
        col[y0:y1 + 1, x0:x1 + 1][ins] = c
        part[y0:y1 + 1, x0:x1 + 1][ins] = ids.setdefault(node, len(ids) + 1)
    return col, part


def motifs(name):
    """Фигуры для узора: пятна панциря (с внутренними пятнами), а нет пятен — пластины."""
    S = 800
    col, part = render(name, S, 0.08)
    shell = part > 0
    cs, cnt = np.unique(col[shell].reshape(-1, 3), axis=0, return_counts=True)
    base = cs[cnt.argmax()]
    mark = shell & (np.abs(col.astype(int) - base).sum(-1) > 40)
    mark = nd.gaussian_filter(mark.astype(np.float32), 4) > 0.5
    lab, _ = nd.label(mark)
    out = []
    for i, sl in enumerate(nd.find_objects(lab), 1):
        m = lab[sl] == i
        if m.sum() < 150:
            continue
        c = col[sl]
        cc, cn = np.unique(c[m].reshape(-1, 3), axis=0, return_counts=True)
        inner = m & (np.abs(c.astype(int) - cc[cn.argmax()]).sum(-1) > 40)
        out.append((np.pad(m, 8), np.pad(inner, 8)))
    if sum(o[0].sum() for o in out) >= 0.01 * S * S:
        return out, 230
    col, part = render(name, S, -0.03)
    ids, ar = np.unique(part[part > 0], return_counts=True)
    out = []
    for i in ids[ar > 0.01 * S * S]:
        m = nd.gaussian_filter((part == i).astype(np.float32), 4) > 0.5
        sl = nd.find_objects(m.astype(int))[0]
        out.append((np.pad(m[sl], 8), np.zeros_like(np.pad(m[sl], 8))))
    return out, 170


def field(sig, rng, shape=(R, R)):
    f = nd.gaussian_filter(rng.standard_normal(shape), sig)
    return f / f.std()


def draw(fill, inn, rng):
    """Стиль масок узоров: тёмный фон, серые фигуры, тонкий неровный светлый контур, поры."""
    edge = np.zeros((R, R), bool)
    for L in (fill, inn):
        for s in ((0, 1), (1, 0)):
            edge |= L != np.roll(L, s, (0, 1))
    d = nd.distance_transform_edt(~edge)
    wid = 1.5 + 0.9 * np.clip(field(18, rng), -1.5, 1.5)
    line = np.clip(wid - d + 0.5, 0, 1) * (0.85 + 0.15 * np.clip(field(25, rng), -1, 1))
    out = np.where(fill, np.where(inn, 0.3, 0.5), 0.12)
    inner = d > 8
    for zone, count, val, mul in ((fill & inner, 1400, None, 0.6), (~fill & inner, 700, 0.3, None)):
        dots = np.zeros((R, R), np.float32)
        for _ in range(count):
            yi, xi = rng.integers(0, R, 2)
            r = rng.uniform(1.4, 2.8)
            y0, y1, x0, x1 = max(0, yi - 4), min(R, yi + 5), max(0, xi - 4), min(R, xi + 5)
            gy, gx = np.mgrid[y0:y1, x0:x1]
            dots[y0:y1, x0:x1] = np.maximum(dots[y0:y1, x0:x1], np.clip(r - np.hypot(gy - yi, gx - xi) + 0.5, 0, 1))
        out = np.where(zone, out * (1 - mul * dots) if mul else np.maximum(out, dots * val), out)
    return np.maximum(out, line)


def pattern(name, seed=1):
    rng = np.random.default_rng(seed)
    ms, target = motifs(name)
    big = max(max(m.shape) for m, _ in ms)
    occ = np.zeros((R, R), bool)
    inn = np.zeros((R, R), bool)
    w = np.sqrt([m.sum() for m, _ in ms])
    w /= w.sum()
    tries = 0
    while tries < 4000 and occ.mean() < 0.33:
        tries += 1
        m, ii = ms[rng.choice(len(ms), p=w)]
        s = max(target / big * rng.uniform(0.75, 1.15), 40 / max(m.shape))  # мелкое пятно остаётся видным
        a = rng.uniform(0, 360)
        flip = rng.random() < 0.5

        def tf(x):
            im = Image.fromarray((x * 255).astype(np.uint8))
            if flip:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            im = im.resize((max(3, int(x.shape[1] * s)), max(3, int(x.shape[0] * s))), Image.BILINEAR)
            return np.asarray(im.rotate(a, Image.BILINEAR, expand=True)) > 127

        M = tf(m)
        I = tf(ii) & M
        h, wd = M.shape
        if h >= R or wd >= R:
            continue
        y, x = rng.integers(0, R, 2)
        ys, xs = (np.arange(h) + y) % R, (np.arange(wd) + x) % R
        halo = nd.binary_dilation(np.pad(M, 14), iterations=14)
        if (occ[np.ix_((np.arange(h + 28) + y - 14) % R, (np.arange(wd + 28) + x - 14) % R)] & halo).any():
            continue
        occ[np.ix_(ys, xs)] |= M
        inn[np.ix_(ys, xs)] |= I
    return draw(occ, inn, rng)


# Негатив: фон (0.12) -> почти полная альфа, фигуры (0.5) -> слабая, контур (1) -> ноль.
NEG = 0.62


def main(keys):
    OUT.mkdir(parents=True, exist_ok=True)
    table = species()
    for key in keys or sorted(table):
        a = np.clip((NEG - pattern(table[key])) / NEG, 0, 1)
        img = np.zeros((R, R, 4), np.uint8)
        img[..., :3] = 255
        img[..., 3] = (a * 255).round().astype(np.uint8)
        Image.fromarray(img, "RGBA").save(OUT / f"p_{key}.png")
        print(key, table[key])


if __name__ == "__main__":
    main(sys.argv[1:])
