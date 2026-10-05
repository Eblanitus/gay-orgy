"""Генератор лоу-поли жуков в .glb (по стилю из вики: гранёный матовый хитин,
мало граней на деталь, три масштаба деталей, тело несут согнутые лапы).

Оси как у старых .glb: голова по +Z, левая сторона по +X, Y вверх, пол — y = 0.
Имена узлов — те, что ждут tools/prepare_beetles.luau и EnemyGait:
leg_* (Femur, KneeJoint, Tibia, AnkleJoint, Tarsus1, Tarsus2), ROOT_0x у бедра,
ThoraxCore, BeetleBodyInner, BeetlePlate_*, head (HeadBase, Eye*), mandible_* (MandibleBase,
MandibleJoint, MandibleTip, Tooth1), AntSeg1..4 / AntNode1..3.
Вся геометрия запечена в мировых координатах, у узлов нет своих трансформов.
"""
import json
import math
import struct

import numpy as np


# ---------------------------------------------------------------- геометрия

class Mesh:
    def __init__(self):
        self.v = []  # треугольники: список (a, b, c), каждая — np.array(3)

    def tri(self, a, b, c):
        self.v.append((np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)))

    def quad(self, a, b, c, d):
        self.tri(a, b, c)
        self.tri(a, c, d)

    def extend(self, other):
        self.v.extend(other.v)
        return self

    def ntris(self):
        return len(self.v)

    def transformed(self, fn):
        m = Mesh()
        m.v = [(fn(a), fn(b), fn(c)) for a, b, c in self.v]
        return m

    def mirrored_x(self):
        m = Mesh()
        f = np.array([-1.0, 1, 1])
        m.v = [(a * f, c * f, b * f) for a, b, c in self.v]
        return m


def loft(rings, cap_start=True, cap_end=True):
    """Тело из колец одинаковой длины (каждое — список точек по кругу, против часовой,
    если смотреть с конца). Грани плоские."""
    m = Mesh()
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            m.quad(r0[i], r0[j], r1[j], r1[i])
    if cap_start:
        c = np.mean(rings[0], axis=0)
        for i in range(n):
            m.tri(c, rings[0][(i + 1) % n], rings[0][i])
    if cap_end:
        c = np.mean(rings[-1], axis=0)
        for i in range(n):
            m.tri(c, rings[-1][i], rings[-1][(i + 1) % n])
    return m


def frame(direction, up_hint=(0, 1, 0)):
    d = np.asarray(direction, float)
    d = d / np.linalg.norm(d)
    up = np.asarray(up_hint, float)
    if abs(np.dot(up, d)) > 0.95:
        up = np.array([1.0, 0, 0]) if abs(d[0]) < 0.9 else np.array([0, 0, 1.0])
    side = np.cross(up, d)
    side /= np.linalg.norm(side)
    up = np.cross(d, side)
    return d, side, up


def ring(center, direction, rx, ry, n, rot=0.0, up_hint=(0, 1, 0)):
    """Кольцо-многоугольник поперёк direction: rx — по боковой оси, ry — по «верху»."""
    d, side, up = frame(direction, up_hint)
    pts = []
    for i in range(n):
        a = rot + 2 * math.pi * i / n
        pts.append(np.asarray(center, float) + side * math.cos(a) * rx + up * math.sin(a) * ry)
    return pts


def tube(points, radii, n=6, up_hint=(0, 1, 0), rot=None, caps=(True, True)):
    """Гранёная трубка по ломаной. radii — по точке (r) или (rx, ry)."""
    points = [np.asarray(p, float) for p in points]
    rings = []
    rot = math.pi / n if rot is None else rot
    for i, p in enumerate(points):
        if i == 0:
            d = points[1] - points[0]
        elif i == len(points) - 1:
            d = points[-1] - points[-2]
        else:
            d = (points[i + 1] - points[i - 1])
        r = radii[i]
        rx, ry = (r, r) if np.isscalar(r) else r
        rings.append(ring(p, d, rx, ry, n, rot, up_hint))
    return loft(rings, *caps)


def blob(center, radii, n=8, rows=5, squash_bottom=1.0):
    """Гранёный эллипсоид (низкий «глобус»)."""
    c = np.asarray(center, float)
    rx, ry, rz = radii
    rings = []
    for k in range(1, rows):
        t = -math.pi / 2 + math.pi * k / rows
        y = math.sin(t)
        w = math.cos(t)
        if y < 0:
            y *= squash_bottom
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n + math.pi / n
            pts.append(c + np.array([math.cos(a) * w * rx, y * ry, math.sin(a) * w * rz]))
        rings.append(pts)
    m = loft(rings, cap_start=False, cap_end=False)
    bottom = c + np.array([0, -ry * squash_bottom, 0])
    top = c + np.array([0, ry, 0])
    n_ = len(rings[0])
    for i in range(n_):
        j = (i + 1) % n_
        m.tri(bottom, rings[0][i], rings[0][j])
        m.tri(top, rings[-1][j], rings[-1][i])
    return m


def shell(z_list, profile, segs, closed_bottom=True):
    """Пластина-купол вдоль Z. profile(z, u) -> (x, y) для u в [0, 1] по сечению.
    Сечения соединяются гранями; низ закрывается плоско."""
    rings = []
    for z in z_list:
        pts = [np.array([*profile(z, i / segs)[:1], profile(z, i / segs)[1], z]) for i in range(segs + 1)]
        rings.append(pts)
    m = Mesh()
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(segs):
            m.quad(r0[i], r1[i], r1[i + 1], r0[i + 1])
        if closed_bottom:
            m.quad(r0[segs], r1[segs], r1[0], r0[0])
    for r, flip in ((rings[0], False), (rings[-1], True)):
        c = np.mean(r, axis=0)
        for i in range(segs):
            if flip:
                m.tri(c, r[i + 1], r[i])
            else:
                m.tri(c, r[i], r[i + 1])
    return m


# ---------------------------------------------------------------- сборка .glb

class Model:
    def __init__(self):
        self.materials = []
        self.mat_index = {}
        self.nodes = []  # {name, mesh?, mat?, children}
        self.root = self._node("Beetle")

    def material(self, name, rgb, rough=0.65, metal=0.0, alpha=1.0):
        self.mat_index[name] = len(self.materials)
        self.materials.append((name, rgb, rough, metal, alpha))

    def _node(self, name, mesh=None, mat=None):
        self.nodes.append({"name": name, "mesh": mesh, "mat": mat, "children": []})
        return len(self.nodes) - 1

    def group(self, name, parent=None):
        i = self._node(name)
        self.nodes[self.root if parent is None else parent]["children"].append(i)
        return i

    def part(self, name, mesh, mat, parent=None):
        i = self._node(name, mesh, self.mat_index[mat])
        self.nodes[self.root if parent is None else parent]["children"].append(i)
        return i

    def tris(self):
        return sum(n["mesh"].ntris() for n in self.nodes if n["mesh"] is not None)

    def save(self, path):
        buf = bytearray()
        views, accessors, meshes = [], [], []

        def add_view(data, target):
            while len(buf) % 4:
                buf.append(0)
            views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data), "target": target})
            buf.extend(data)
            return len(views) - 1

        node_mesh = {}
        for idx, n in enumerate(self.nodes):
            if n["mesh"] is None:
                continue
            tri = n["mesh"].v
            pos = np.array([p for t in tri for p in t], dtype=np.float32)
            nrm = []
            for a, b, c in tri:
                fn = np.cross(b - a, c - a)
                ln = np.linalg.norm(fn)
                fn = fn / ln if ln > 1e-12 else np.array([0, 1.0, 0])
                nrm += [fn, fn, fn]
            nrm = np.array(nrm, dtype=np.float32)
            ind = np.arange(len(pos), dtype=np.uint32)
            pv = add_view(pos.tobytes(), 34962)
            nv = add_view(nrm.tobytes(), 34962)
            iv = add_view(ind.tobytes(), 34963)
            accessors.append({"bufferView": pv, "componentType": 5126, "count": len(pos), "type": "VEC3",
                              "min": pos.min(0).tolist(), "max": pos.max(0).tolist()})
            accessors.append({"bufferView": nv, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
            accessors.append({"bufferView": iv, "componentType": 5125, "count": len(ind), "type": "SCALAR"})
            a0 = len(accessors) - 3
            meshes.append({"name": n["name"], "primitives": [{
                "attributes": {"POSITION": a0, "NORMAL": a0 + 1}, "indices": a0 + 2, "material": n["mat"]}]})
            node_mesh[idx] = len(meshes) - 1

        nodes = []
        for idx, n in enumerate(self.nodes):
            d = {"name": n["name"]}
            if idx in node_mesh:
                d["mesh"] = node_mesh[idx]
            if n["children"]:
                d["children"] = n["children"]
            nodes.append(d)

        mats = []
        for name, rgb, rough, metal, alpha in self.materials:
            m = {"name": name, "pbrMetallicRoughness": {
                "baseColorFactor": [*rgb, alpha], "metallicFactor": metal, "roughnessFactor": rough}}
            if alpha < 1:
                m["alphaMode"] = "BLEND"
                m["doubleSided"] = True
            mats.append(m)

        gltf = {
            "asset": {"version": "2.0", "generator": "beetlegen.py"},
            "scene": 0,
            "scenes": [{"name": "Scene", "nodes": getattr(self, "roots", [self.root])}],
            "nodes": nodes, "meshes": meshes, "materials": mats,
            "accessors": accessors, "bufferViews": views,
            "buffers": [{"byteLength": len(buf)}],
        }
        js = json.dumps(gltf, ensure_ascii=False).encode("utf-8")
        while len(js) % 4:
            js += b" "
        while len(buf) % 4:
            buf.append(0)
        total = 12 + 8 + len(js) + 8 + len(buf)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(buf), 0x004E4942))
            f.write(buf)


# ---------------------------------------------------------------- детали жука

def lerp(a, b, t):
    return np.asarray(a, float) * (1 - t) + np.asarray(b, float) * t


def leg_parts(hip, knee, ankle, foot, femur_r, tibia_r, claw_dir, spikes=True, paddle=0.0):
    """Лапа на левой стороне (+X). Возвращает {имя: Mesh}."""
    hip, knee, ankle, foot = (np.asarray(p, float) for p in (hip, knee, ankle, foot))
    parts = {}
    # Бедро: толще к середине, сплющенное (рабочая лапа, а не спица).
    fm = [lerp(hip, knee, t) for t in (0.0, 0.35, 0.8, 1.0)]
    parts["Femur"] = tube(fm, [(femur_r * 0.7, femur_r * 0.55), (femur_r, femur_r * 0.75),
                               (femur_r * 0.85, femur_r * 0.6), (femur_r * 0.6, femur_r * 0.5)], n=6)
    parts["KneeJoint"] = blob(knee, (femur_r * 0.75,) * 3, n=6, rows=3)
    # Голень: к низу тоньше, вдоль — пара шипов (мелкая деталь).
    tb = [lerp(knee, ankle, t) for t in (0.0, 0.5, 1.0)]
    tib = tube(tb, [tibia_r, tibia_r * 0.85, tibia_r * 0.6], n=5)
    d, side, up = frame(ankle - knee)
    for t in ((0.45, 0.75) if spikes else ()):
        base = lerp(knee, ankle, t)
        out = np.cross(up, d)
        spike_base = base + out * tibia_r * 0.6
        spike_tip = spike_base + out * tibia_r * 1.3 + d * tibia_r * 1.2
        tib.extend(tube([spike_base, spike_tip], [tibia_r * 0.35, tibia_r * 0.05], n=3))
    if paddle:
        # Копательная голень: плоская лопатка с зубцами по внешнему краю.
        out = np.cross(up, d)
        for t in (0.55, 0.75, 0.95):
            base = lerp(knee, ankle, t)
            tib.extend(tube([base, base + out * paddle + up * paddle * 0.2],
                            [(tibia_r * 0.8, tibia_r * 0.35), (tibia_r * 0.15, tibia_r * 0.1)], n=4))
    parts["Tibia"] = tib
    parts["AnkleJoint"] = blob(ankle, (tibia_r * 0.8,) * 3, n=5, rows=3)
    # Лапка: три членика по полу к ступне.
    ts = [lerp(ankle, foot, t) for t in (0.0, 0.34, 0.36, 0.67, 0.69, 1.0)]
    rr = tibia_r * 0.55
    parts["Tarsus1"] = tube(ts, [rr, rr * 0.8, rr * 0.95, rr * 0.75, rr * 0.9, rr * 0.7], n=4)
    # Коготки на полу.
    cd = np.asarray(claw_dir, float)
    cd /= np.linalg.norm(cd)
    sd = np.cross([0, 1, 0], cd)
    claw = Mesh()
    for s in (-1, 1):
        tip = foot + cd * rr * 2.2 + sd * s * rr * 1.1 - np.array([0, foot[1] - 0.005, 0])
        claw.extend(tube([foot, tip], [rr * 0.6, rr * 0.12], n=3))
    parts["Tarsus2"] = claw
    return parts


def antenna(points, r0):
    """Усик по точкам: чередуются AntSeg и AntNode. Возвращает список (имя, Mesh)."""
    out = []
    pts = [np.asarray(p, float) for p in points]
    seg = 1
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        r = r0 * (1 - 0.15 * i)
        out.append((f"AntSeg{seg}", tube([a, b], [r, r * 0.8], n=5)))
        if i < len(pts) - 2 and seg <= 3:
            out.append((f"AntNode{seg}", blob(b, (r * 0.95,) * 3, n=5, rows=3)))
        seg += 1
    return out


def mirror_name_suffix(name, s):
    return name + ("002" if s == 1 else "003")


# ---------------------------------------------------------------- узлы жука целиком

def section_rings(sections, shape):
    """sections: (z, w, top, bot); shape(w, top, bot) -> [(x, y)] по кругу."""
    return [[np.array([x, y, z]) for x, y in shape(w, top, bot)] for z, w, top, bot in sections]


def oval(n=8):
    def shape(w, top, bot):
        yc, ry = (top + bot) / 2, (top - bot) / 2
        return [(math.cos(a) * w, yc + math.sin(a) * ry)
                for a in (2 * math.pi * i / n + math.pi / n for i in range(n))]
    return shape


def shield(w, top, bot):
    """Щит переднеспинки: плоский верх, отогнутые края."""
    pts = [(0.0, top), (w * 0.55, top - 0.03), (w * 0.95, top - 0.2), (w * 1.02, top - 0.32),
           (w * 0.85, bot + 0.08), (w * 0.4, bot), (0.0, bot - 0.01)]
    return pts + [(-x, y) for x, y in reversed(pts[1:-1])]


def headshape(w, top, bot):
    pts = [(0, top), (w * 0.7, top - 0.04), (w, (top + bot) / 2 + 0.05), (w * 0.8, bot + 0.04), (0, bot)]
    return pts + [(-x, y) for x, y in reversed(pts[1:-1])]


def add_abdomen(m, sections, mat, n=8, name="BeetleBodyInner"):
    m.part(name, loft(section_rings(sections, oval(n))[::-1]), mat)


def add_sternites(m, bands, mat):
    """bands: (z, полуширина, y)."""
    for k, (z, w, y) in enumerate(bands):
        mesh = tube([[-w, y + 0.03, z], [-w * 0.5, y, z], [w * 0.5, y, z], [w, y + 0.03, z]],
                    [(0.05, 0.025)] * 4, n=4, up_hint=(0, 0, 1))
        m.part(f"BeetleSternite_{k:02d}", mesh, mat)


def elytron(zs, width, height, y0, seam=0.012, segs=4, ribs=(0.33, 0.62), rib_r=0.022):
    rings = []
    for z in zs:
        w, h = width(z), height(z)
        pts = [np.array([seam + (w - seam) * math.sin(a), y0 + h * math.cos(a), z])
               for a in ((math.pi / 2) * i / segs for i in range(segs + 1))]
        pts.append(np.array([w - 0.06, y0 - 0.02, z]))
        pts.append(np.array([seam, y0 + 0.08, z]))
        rings.append(pts)
    mesh = loft(rings)
    for u in ribs:
        a = (math.pi / 2) * u
        pts = [[seam + (width(z) - seam) * math.sin(a) * 1.01, y0 + height(z) * math.cos(a) + rib_r * 0.6, z]
               for z in zs[1:-1]]
        mesh.extend(tube(pts, [rib_r] * len(pts), n=3))
    return mesh


def rotate_about(mesh, pivot, axis, angle):
    axis = np.asarray(axis, float) / np.linalg.norm(axis)
    pivot = np.asarray(pivot, float)
    c, s = math.cos(angle), math.sin(angle)
    x, y, z = axis
    R = np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                  [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                  [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])
    return mesh.transformed(lambda p: R @ (p - pivot) + pivot)


def add_elytra(m, mesh_left, mat, names=("BeetlePlate_00", "BeetlePlate_01")):
    m.part(names[0], mesh_left, mat)
    m.part(names[1], mesh_left.mirrored_x(), mat)


def add_legs(m, legs, femur_r, tibia_r, leg_mat, coxa_mat, coxa_r=(0.14, 0.12, 0.14), tibia_spikes=True):
    """legs: {'front'|'mid'|'rear': dict(hip, knee, ankle, foot, claw)} — левая сторона."""
    root_i = 0
    for key in ("front", "mid", "rear"):
        L = legs[key]
        fr = L.get("femur_r", femur_r)
        tr = L.get("tibia_r", tibia_r)
        parts = leg_parts(L["hip"], L["knee"], L["ankle"], L["foot"], fr, tr, L["claw"], spikes=tibia_spikes,
                          paddle=L.get("paddle", 0))
        for s, side in ((1, "left"), (-1, "right")):
            g = m.group(f"leg_{key}_{side}001")
            for name, mesh in parts.items():
                m.part(f"{name}{root_i:03d}", mesh if s == 1 else mesh.mirrored_x(), leg_mat, parent=g)
            hip = np.array(L["hip"]) * np.array([s, 1, 1])
            m.part(f"ROOT_{root_i:02d}", blob(hip, coxa_r, n=6, rows=3), coxa_mat)
            root_i += 1


def add_head(m, sections, mat, eyes=None, eye_mat=None, extra=()):
    """eyes: (центр левого глаза, радиусы). extra: [(имя, Mesh, мат)] — тоже в группу головы."""
    g = m.group("head001")
    m.part("HeadBase001", loft(section_rings(sections, headshape)[::-1]), mat, parent=g)
    if eyes:
        c, r = eyes
        for s, name in ((1, "EyeLeft001"), (-1, "EyeRight001")):
            m.part(name, blob((c[0] * s, c[1], c[2]), r, n=6, rows=4), eye_mat, parent=g)
    for name, mesh, mt in extra:
        m.part(name, mesh, mt, parent=g)
    return g


def add_mandibles(m, base, mid, bend, tip, r, mat, tooth=True, tooth_name="Tooth1"):
    for s, gname, suf in ((1, "mandible_left001", "002"), (-1, "mandible_right001", "003")):
        g = m.group(gname)
        f = np.array([s, 1, 1])
        b, md, bd, tp = (np.asarray(p, float) * f for p in (base, mid, bend, tip))
        m.part("MandibleJoint" + suf, blob(b, (r * 1.1, r, r * 1.1), n=6, rows=3), mat, parent=g)
        m.part("MandibleBase" + suf, tube([b, md], [(r * 1.1, r * 0.75), (r * 0.9, r * 0.6)], n=5), mat, parent=g)
        m.part("MandibleTip" + suf, tube([md, bd, tp], [(r * 0.9, r * 0.6), (r * 0.6, r * 0.42), (r * 0.15, r * 0.12)],
                                          n=5), mat, parent=g)
        if tooth:
            tb = (md + bd) / 2
            m.part(tooth_name + suf, tube([tb, tb + np.array([-r * 1.2 * s, 0, r * 0.4])], [r * 0.38, r * 0.07], n=3),
                   mat, parent=g)


def add_antennae(m, pts_left, r, mat, clubbed=0.0):
    for s, suf in ((1, "002"), (-1, "003")):
        pts = [np.asarray(p, float) * np.array([s, 1, 1]) for p in pts_left]
        items = antenna(pts, r)
        if clubbed:
            last = pts[-1]
            items.append(("AntSeg4", blob(last, (clubbed, clubbed * 0.8, clubbed * 1.3), n=6, rows=3)))
        for name, mesh in items:
            m.part(name + suf, mesh, mat)


def merge(models, spacing=7.0):
    """Все жуки в одной сцене (для одного Import 3D): корни — отдельные узлы сцены,
    каждый вид сдвинут по X, чтобы не накладывались."""
    out = Model()
    out.nodes = []
    roots = []
    for k, m in enumerate(models):
        mat_off = len(out.materials)
        out.materials.extend(m.materials)
        node_off = len(out.nodes)
        shift = np.array([k * spacing, 0, 0])
        for n in m.nodes:
            mesh = n["mesh"].transformed(lambda p, s=shift: p + s) if n["mesh"] is not None else None
            out.nodes.append({"name": n["name"], "mesh": mesh,
                              "mat": None if n["mat"] is None else n["mat"] + mat_off,
                              "children": [c + node_off for c in n["children"]]})
        roots.append(m.root + node_off)
    out.roots = roots
    return out
