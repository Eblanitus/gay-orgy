"""Остальные жуки игры (те, что до #402 были примитивами). Оси как в species.py: голова +Z,
левая сторона +X, пол y = 0. Каждый вид — Model; общий каркас собирает kit().

Цвет панциря, головы и лап в игре даёт BugPalette по касте (EnemyModel перекрашивает детали
по имени). Свой цвет сохраняют только «приметы» вида — детали с особыми именами (кислотный
мешок, щит, рог, бомба…): по ним вид читается издалека."""
import math

import numpy as np

from beetlegen import (Mesh, Model, add_abdomen, add_antennae, add_elytra, add_head, add_legs, add_mandibles,
                       add_sternites, blob, elytron, headshape, loft, rotate_about, section_rings, shield, tube)
from species import dome

# Доли длины надкрылий для колец (как у Стандарта).
EL_F = [0.0, 0.075, 0.27, 0.5, 0.72, 0.86, 0.96, 1.0]


def mats(m, p, shell_rgb, leg=(0.035, 0.016, 0.008)):
    m.material(p + "_elytra", shell_rgb, rough=0.55)
    m.material(p + "_chitin", tuple(c * 0.5 for c in shell_rgb), rough=0.6)
    m.material(p + "_leg", leg, rough=0.6)
    m.material(p + "_eye", (0.010, 0.010, 0.012), rough=0.15)
    m.material(p + "_mand", (0.022, 0.010, 0.005), rough=0.35)


def kit(m, p, *, abd, thorax, legs, head, eyes=None, elytra=None, mand=None, ant=None, leg_r=(0.1, 0.06),
        coxa=0.11, spikes=False, ant_r=0.032, club=0.0, head_extra=(), sternites=None, thorax_extra=None):
    """Каркас жука. elytra: dict(zf, zr, w, h, y0, zst, power, ribs, open) — open (рад) разводит
    надкрылья в стороны. Возвращает (width, height, y0) купола или None."""
    add_abdomen(m, abd, p + "_chitin")
    if sternites:
        add_sternites(m, sternites, p + "_chitin")
    dome_fn = None
    if elytra:
        e = elytra
        zf, zr = e["zf"], e["zr"]
        zs = [zf + (zr - zf) * f for f in EL_F]
        width, height = dome(zf, zr, e["w"], e["h"], z_straight=e.get("zst", (zf + zr) / 2), power=e.get("power", 2.0))
        mesh = elytron(zs, width, height, e["y0"], segs=5, ribs=e.get("ribs", (0.5,)), rib_r=e.get("rib_r", 0.022))
        if e.get("open"):
            piv = (0.02, e["y0"] + e["h"] * 0.6, zf)
            mesh = rotate_about(mesh, piv, (0, 0, 1), -e["open"])
            mesh = rotate_about(mesh, piv, (0, 1, 0), e["open"] * 0.6)
        add_elytra(m, mesh, p + "_elytra")
        dome_fn = (width, height, e["y0"])
    th = loft(section_rings(thorax, shield)[::-1])
    if thorax_extra is not None:
        th.extend(thorax_extra)
    m.part("ThoraxCore", th, p + "_chitin")
    lr = leg_r
    add_legs(m, legs, lr[0], lr[1], p + "_leg", p + "_chitin", coxa_r=(coxa, coxa * 0.9, coxa), tibia_spikes=spikes)
    add_head(m, head, p + "_chitin", eyes=eyes, eye_mat=p + "_eye", extra=head_extra)
    if mand:
        base, mid, bend, tip, r, tooth = mand
        add_mandibles(m, base, mid, bend, tip, r, p + "_mand", tooth=tooth)
    if ant:
        add_antennae(m, ant, ant_r, p + "_chitin", clubbed=club)
    return dome_fn


def on_dome(dome_fn, z, u, lift=0.0):
    """Точка на куполе надкрылья (левом) и нормаль: u = 0 — шов, 1 — край."""
    width, height, y0 = dome_fn
    a = (math.pi / 2) * u
    w, h = width(z), height(z)
    c = np.array([0.012 + (w - 0.012) * math.sin(a), y0 + h * math.cos(a), z])
    n = np.array([math.sin(a) * h, math.cos(a) * w, 0.0])
    n /= np.linalg.norm(n)
    return c + n * lift, n


def stuck_disc(center, normal, r, thick=0.035, stretch=1.0):
    disc = blob((0, 0, 0), (r, thick, r * stretch), n=6, rows=3)
    ax = np.cross([0, 1.0, 0], normal)
    if np.linalg.norm(ax) > 1e-6:
        disc = rotate_about(disc, (0, 0, 0), ax, math.acos(np.clip(normal[1], -1, 1)))
    return disc.transformed(lambda q: q + center)


def membrane(outline, s, thick=0.012):
    c = np.mean(outline, axis=0)
    mem = Mesh()
    th = np.array([0, thick, 0])
    for i in range(len(outline)):
        a, b = outline[i], outline[(i + 1) % len(outline)]
        if s == 1:
            mem.tri(c + th, a + th, b + th)
            mem.tri(c - th, b - th, a - th)
        else:
            mem.tri(c + th, b + th, a + th)
            mem.tri(c - th, a - th, b - th)
    return mem


def add_wings(m, outline_left, mat, vein_mat, lift=0.35, veins=(1, 2, 3)):
    """Перепончатые крылья (имена wing_membrane / wing_vein — prepare_beetles кладёт их в wing_L/R)."""
    for s, suf in ((1, "001"), (-1, "002")):
        pts = [np.asarray(q, float) for q in outline_left]
        x0 = pts[0][0]
        pts = [q + np.array([0, (q[0] - x0) * lift, 0]) for q in pts]
        pts = [q * np.array([s, 1, 1]) for q in pts]
        m.part("wing_membrane" + suf, membrane(pts, s), mat)
        th = np.array([0, 0.014, 0])
        vein = Mesh()
        for k in veins:
            vein.extend(tube([pts[0] + th, pts[k] + th], [0.025, 0.01], n=3))
        m.part("wing_vein" + suf, vein, vein_mat)


def both(mesh):
    out = Mesh()
    out.extend(mesh)
    out.extend(mesh.mirrored_x())
    return out


def sac(profile, n=10):
    """Мешок вдоль Z: profile — [(z, y, rx, ry)] от переда к заду. Возвращает (Mesh, at(z) -> (y, rx, ry))."""
    zs = [p[0] for p in profile]

    def at(z):
        for a, b in zip(profile, profile[1:]):
            if b[0] <= z <= a[0]:
                t = (a[0] - z) / (a[0] - b[0])
                return tuple(a[k] + (b[k] - a[k]) * t for k in (1, 2, 3))
        p = profile[0] if z > zs[0] else profile[-1]
        return p[1], p[2], p[3]

    # Кольца в плоскостях z = const (не поперёк оси, как у tube): тогда пластины band_plate,
    # построенные по тому же at(z), ровно ложатся поверх и не протыкаются.
    rings = []
    for z, y, rx, ry in profile:
        rings.append([np.array([-math.cos(a) * rx, y + math.sin(a) * ry, z])
                      for a in (math.pi / n + 2 * math.pi * i / n for i in range(n))])
    mesh = loft(rings)
    return mesh, at


def band_plate(at, z0, z1, grow=1.1, a0=-0.6, a1=math.pi + 0.6, thick=0.05, steps=11):
    """Поперечная пластина (тергит) поверх мешка: дуга от a0 до a1 по сечению, z0 > z1."""
    def arch(z, k):
        y, rx, ry = at(z)
        out = [(math.cos(a) * rx * grow * k, y + math.sin(a) * ry * grow * k) for a in np.linspace(a0, a1, steps)]
        inn = [(math.cos(a) * (rx * grow * k - thick), y + math.sin(a) * (ry * grow * k - thick))
               for a in np.linspace(a1, a0, steps)]
        return [np.array([x, yy, z]) for x, yy in out + inn]
    zm = (z0 + z1) / 2
    return loft([arch(z1, 0.98), arch(zm, 1.0), arch(z0, 1.03)])


def _rock_noise(p, seed):
    """Детерминированный шум точки: одинаковые вершины смещаются одинаково."""
    v = math.sin(p[0] * 12.9898 + p[1] * 78.233 + p[2] * 37.719 + seed * 4.1414) * 43758.5453
    return (v - math.floor(v)) * 2 - 1


def rock_half(profile, seed, amp=0.16, steps=7, gap=0.025):
    """Левая половина «камня» вдоль Z: profile — [(z, y, rx, ry_top, ry_bot)]. Внутренняя
    стенка плоская (x = gap), снаружи — неровные грани."""
    rings = []
    for z, y, rx, rt, rb in profile:
        ring = []
        for b in np.linspace(math.pi / 2, 3 * math.pi / 2, steps):
            ry = rt if math.sin(b) > 0 else rb
            d = np.array([-math.cos(b) * rx, math.sin(b) * ry])
            n = _rock_noise((round(d[0], 3), round(d[1], 3), round(z, 3)), seed)
            d = d * (1 + amp * n)
            ring.append(np.array([gap + d[0], y + d[1], z + amp * 0.6 * _rock_noise((z, d[1], d[0]), seed + 1)]))
        rings.append(ring)
    return loft(rings)


# ================================================================ Каста 1 — работяги

def acid_spitter():
    """Кислотник: жук-бомбардир. Короткие разведённые надкрылья открывают раздутые парные
    железы с кислотой — гладкие, блестящие, в тёмных прожилках. Голова вытянута в короткий
    хоботок, на его конце висит светящаяся капля: этим он и плюёт."""
    m = Model()
    mats(m, "acid", (0.16, 0.09, 0.03))
    m.material("acid_sac", (0.26, 0.42, 0.02), rough=0.18)
    m.material("acid_vein", (0.07, 0.11, 0.008), rough=0.5)
    m.material("acid_glow", (0.35, 0.85, 0.04), rough=0.2)
    dfn = kit(m, "acid",
              abd=[(0.0, 0.45, 0.95, 0.45), (-0.4, 0.62, 1.0, 0.36), (-0.9, 0.62, 0.98, 0.36),
                   (-1.3, 0.48, 0.92, 0.42), (-1.5, 0.22, 0.85, 0.55)],
              elytra=dict(zf=0.06, zr=-0.85, w=0.6, h=0.4, y0=0.72, zst=-0.3, ribs=(0.5,), open=0.28),
              thorax=[(0.05, 0.5, 1.0, 0.45), (0.3, 0.52, 1.02, 0.44), (0.52, 0.44, 0.98, 0.48),
                      (0.64, 0.34, 0.92, 0.52)],
              legs={
                  "front": dict(hip=(0.28, 0.5, 0.45), knee=(0.8, 0.9, 0.72), ankle=(1.08, 0.12, 1.0),
                                foot=(1.2, 0.03, 1.24), claw=(0.4, 0, 1)),
                  "mid": dict(hip=(0.34, 0.48, 0.12), knee=(0.95, 0.94, 0.14), ankle=(1.3, 0.12, 0.18),
                              foot=(1.48, 0.03, 0.22), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.38, 0.46, -0.2), knee=(0.92, 0.92, -0.56), ankle=(1.2, 0.12, -0.98),
                               foot=(1.3, 0.03, -1.26), claw=(0.4, 0, -1)),
              }, leg_r=(0.11, 0.065),
              head=[(0.6, 0.42, 0.98, 0.5), (0.8, 0.44, 0.98, 0.48), (0.96, 0.38, 0.9, 0.5), (1.04, 0.28, 0.8, 0.54)],
              eyes=((0.4, 0.86, 0.8), (0.1, 0.11, 0.11)),
              head_extra=[("cheek_rostrum", tube([[0, 0.66, 0.98], [0, 0.6, 1.16], [0, 0.52, 1.28]],
                                                 [(0.13, 0.1), (0.08, 0.065), (0.035, 0.03)], n=6), "acid_chitin"),
                          ("acid_drip", blob((0, 0.47, 1.3), (0.045, 0.06, 0.045), n=6, rows=3), "acid_glow")],
              ant=[(0.24, 0.92, 0.94), (0.4, 1.06, 1.08), (0.5, 1.1, 1.22), (0.56, 1.08, 1.34)], club=0.07)
    # Парные железы: две гладкие доли бок о бок, спереди уходят под надкрылья.
    glands = Mesh()
    veins = Mesh()
    for s in (1, -1):
        prof = [(-0.25, 0.86, 0.22, 0.2), (-0.5, 0.96, 0.38, 0.38), (-0.9, 1.0, 0.44, 0.44),
                (-1.3, 0.94, 0.38, 0.38), (-1.56, 0.84, 0.18, 0.18)]
        lobe, at = sac(prof, n=10)
        glands.extend(lobe.transformed(lambda q, s=s: q + np.array([s * 0.24, 0, 0])))
        # Прожилки по внешнему боку доли.
        for a0 in (0.35, 0.95):
            pts = []
            for z in np.linspace(-0.45, -1.42, 6):
                y, rx, ry = at(z)
                pts.append([s * (0.24 + math.cos(a0) * rx * 1.01), y + math.sin(a0) * ry * 1.01, z])
            veins.extend(tube(pts, [0.014] * 6, n=3))
    m.part("acid_sac", glands, "acid_sac")
    m.part("acid_vein", veins, "acid_vein")
    return m


def medic():
    """Медик: носит личинок и раненых. Края надкрылий загнуты вверх бортиками — на спине
    получилось корыто, в нём лежит кокон из шёлка, перемотанный нитями. Тонкий,
    высокий на длинных лапах; короткие щупики у рта."""
    m = Model()
    mats(m, "med", (0.18, 0.10, 0.04))
    m.material("med_silk", (0.44, 0.40, 0.31), rough=0.85)
    m.material("med_thread", (0.30, 0.27, 0.2), rough=0.8)
    zf, zr = 0.06, -1.9
    dfn = kit(m, "med",
              abd=[(0.0, 0.4, 1.05, 0.55), (-0.4, 0.52, 1.12, 0.5), (-1.0, 0.54, 1.1, 0.5),
                   (-1.5, 0.42, 1.04, 0.56), (-1.8, 0.18, 0.95, 0.7)],
              elytra=dict(zf=zf, zr=zr, w=0.64, h=0.36, y0=0.84, zst=-0.8, ribs=(0.35,)),
              thorax=[(0.05, 0.36, 1.1, 0.62), (0.3, 0.38, 1.12, 0.6), (0.55, 0.34, 1.08, 0.64),
                      (0.7, 0.26, 1.02, 0.68)],
              legs={
                  "front": dict(hip=(0.22, 0.66, 0.5), knee=(0.8, 1.3, 0.82), ankle=(1.12, 0.12, 1.18),
                                foot=(1.24, 0.03, 1.44), claw=(0.4, 0, 1)),
                  "mid": dict(hip=(0.28, 0.64, 0.2), knee=(1.0, 1.36, 0.22), ankle=(1.42, 0.12, 0.26),
                              foot=(1.62, 0.03, 0.3), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.3, 0.62, -0.08), knee=(0.98, 1.34, -0.55), ankle=(1.3, 0.12, -1.1),
                               foot=(1.42, 0.03, -1.42), claw=(0.4, 0, -1)),
              }, leg_r=(0.085, 0.05),
              head=[(0.66, 0.3, 1.16, 0.74), (0.84, 0.32, 1.14, 0.72), (0.98, 0.26, 1.06, 0.74), (1.06, 0.18, 0.96, 0.78)],
              eyes=((0.28, 1.04, 0.88), (0.08, 0.09, 0.09)),
              head_extra=[("labial_palp", both(tube([[0.1, 0.82, 1.02], [0.15, 0.72, 1.12], [0.13, 0.66, 1.18]],
                                                    [0.03, 0.026, 0.016], n=4)), "med_chitin")],
              ant=[(0.18, 1.18, 1.0), (0.34, 1.42, 1.12), (0.48, 1.58, 1.26), (0.58, 1.66, 1.42), (0.64, 1.68, 1.6)])
    # Бортики: внешний край надкрылья загнут вверх и чуть наружу.
    rings = []
    zs = list(np.linspace(zf - 0.08, zr + 0.12, 9))
    for z in zs:
        c, n = on_dome(dfn, z, 0.86)
        t = 1 - abs((z - (zf + zr) / 2) / ((zf - zr) / 2)) ** 2.5
        up = np.array([0.04, 1.0, 0]) * (0.08 + 0.34 * t)
        rings.append([c - n * 0.03, c + n * 0.03, c + n * 0.02 + up, c - n * 0.02 + up])
    fl = loft(rings)
    m.part("BeetlePlate_flange", both(fl), "med_elytra")
    # Кокон в корыте и нити, которыми он примотан к бортикам.
    pod_c = np.array([0, 1.3, -0.86])
    pod = blob(pod_c, (0.32, 0.22, 0.64), n=9, rows=5)
    m.part("med_pod", pod, "med_silk")
    thr = Mesh()
    for z in (-0.5, -0.78, -1.06, -1.32):
        t = (z - pod_c[2]) / 0.64
        k = math.sqrt(max(0.05, 1 - t * t))
        pts = [[math.cos(a) * 0.33 * k, pod_c[1] + math.sin(a) * 0.23 * k, z + 0.04 * math.cos(a)]
               for a in np.linspace(0, 2 * math.pi, 9)]
        thr.extend(tube(pts, [0.018] * 9, n=3, up_hint=(0, 0, 1)))
    m.part("med_thread", thr, "med_thread")
    return m


def queen():
    """Матка: летает, откладывает личинку. Маленькие грудь и голова, огромное светлое брюшко
    в поперечных кольцах (как у королевы термитов), прозрачные крылья, корона шипов."""
    m = Model()
    mats(m, "queen", (0.14, 0.06, 0.03))
    m.material("queen_belly", (0.70, 0.58, 0.42), rough=0.45)
    m.material("queen_ring", (0.10, 0.05, 0.03), rough=0.55)
    m.material("queen_wing", (0.75, 0.68, 0.55), rough=0.4, alpha=0.5)
    m.material("queen_vein", (0.06, 0.03, 0.015), rough=0.5)
    m.material("queen_crown", (0.04, 0.02, 0.01), rough=0.4)
    kit(m, "queen",
        abd=[(0.0, 0.35, 1.0, 0.6), (-0.3, 0.42, 1.05, 0.56), (-0.6, 0.4, 1.02, 0.6)],
        thorax=[(0.0, 0.42, 1.12, 0.6), (0.28, 0.44, 1.16, 0.58), (0.5, 0.38, 1.1, 0.62), (0.62, 0.3, 1.04, 0.66)],
        legs={
            "front": dict(hip=(0.26, 0.64, 0.46), knee=(0.78, 1.1, 0.74), ankle=(1.06, 0.12, 1.04),
                          foot=(1.18, 0.03, 1.28), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.32, 0.62, 0.16), knee=(0.98, 1.14, 0.18), ankle=(1.36, 0.12, 0.22),
                        foot=(1.56, 0.03, 0.26), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.36, 0.6, -0.08), knee=(1.1, 1.14, -0.4), ankle=(1.5, 0.12, -0.8),
                         foot=(1.66, 0.03, -1.06), claw=(0.6, 0, -1)),
        }, leg_r=(0.09, 0.055),
        head=[(0.6, 0.32, 1.14, 0.74), (0.78, 0.34, 1.14, 0.72), (0.92, 0.28, 1.06, 0.74), (1.0, 0.2, 0.96, 0.78)],
        eyes=((0.3, 1.02, 0.82), (0.1, 0.11, 0.11)),
        head_extra=[("queen_crown", both(Mesh().extend(tube([[0.16, 1.12, 0.74], [0.24, 1.36, 0.7]], [0.05, 0.008], n=4))
                                           .extend(tube([[0.06, 1.14, 0.8], [0.08, 1.42, 0.82]], [0.05, 0.008], n=4))),
                     "queen_crown")],
        mand=((0.12, 0.8, 0.96), (0.2, 0.78, 1.1), (0.14, 0.77, 1.2), (0.03, 0.76, 1.24), 0.06, False),
        ant=[(0.2, 1.1, 0.94), (0.38, 1.3, 1.08), (0.52, 1.4, 1.22), (0.62, 1.42, 1.38), (0.68, 1.38, 1.54)])
    # Брюшко-«мешок»: длинное, светлое, в кольцах, чуть свисает к хвосту.
    pts = [[0, 0.82, -0.55], [0, 0.88, -1.0], [0, 0.86, -1.6], [0, 0.78, -2.2], [0, 0.66, -2.65], [0, 0.56, -2.9]]
    rad = [(0.5, 0.42), (0.72, 0.58), (0.8, 0.64), (0.76, 0.6), (0.56, 0.46), (0.22, 0.2)]
    m.part("queen_belly", tube(pts, rad, n=10), "queen_belly")
    rings = Mesh()
    for k in range(1, 5):
        t = k / 5
        i = int(t * (len(pts) - 1))
        f = t * (len(pts) - 1) - i
        p = np.array(pts[i]) * (1 - f) + np.array(pts[i + 1]) * f
        rx = rad[i][0] * (1 - f) + rad[i + 1][0] * f
        ry = rad[i][1] * (1 - f) + rad[i + 1][1] * f
        loop = [[math.cos(a) * rx * 1.03, p[1] + math.sin(a) * ry * 1.03, p[2]] for a in np.linspace(0, 2 * math.pi, 11)]
        rings.extend(tube(loop, [0.035] * 11, n=3, up_hint=(0, 0, 1)))
    m.part("queen_ring", rings, "queen_ring")
    add_wings(m, [(0.2, 1.18, 0.35), (0.9, 1.26, 0.2), (1.5, 1.24, -0.4), (1.7, 1.2, -1.3), (1.3, 1.18, -1.9),
                  (0.6, 1.18, -1.4), (0.25, 1.18, -0.3)], "queen_wing", "queen_vein", lift=0.2)
    return m


def larva():
    """Личинка: мягкая С-образная личинка жука. Светлое кольчатое тело, тёмная головная
    капсула, три пары крошечных лапок под грудью — стоит на месте, пока не вылупится выводок."""
    m = Model()
    mats(m, "larva", (0.70, 0.62, 0.48), leg=(0.30, 0.20, 0.10))
    m.material("larva_fold", (0.45, 0.36, 0.25), rough=0.7)
    m.material("larva_spot", (0.20, 0.14, 0.08), rough=0.6)
    # Тело по дуге: от хвоста (подогнут вниз-вперёд) к груди.
    path = [[0, 0.32, -1.55], [0, 0.55, -1.4], [0, 0.7, -1.05], [0, 0.72, -0.6], [0, 0.66, -0.15]]
    rad = [(0.32, 0.26), (0.48, 0.38), (0.6, 0.5), (0.62, 0.52), (0.56, 0.48)]
    m.part("BeetleBodyInner", tube(path, rad, n=10), "larva_chitin")
    folds = Mesh()
    for k in range(len(path) - 1):
        for f in (0.33, 0.66):
            p = np.array(path[k]) * (1 - f) + np.array(path[k + 1]) * f
            rx = rad[k][0] * (1 - f) + rad[k + 1][0] * f
            ry = rad[k][1] * (1 - f) + rad[k + 1][1] * f
            d = np.array(path[k + 1]) - np.array(path[k])
            d /= np.linalg.norm(d)
            side = np.array([1.0, 0, 0])
            up = np.cross(d, side)
            loop = [p + side * math.cos(a) * rx * 1.0 + up * math.sin(a) * ry * 1.0
                    for a in np.linspace(-0.2, math.pi + 0.2, 7)]
            folds.extend(tube(loop, [0.026] * 7, n=3))
    m.part("larva_fold", folds, "larva_fold")
    m.part("larva_spot", Mesh().extend(blob((0.4, 0.62, -0.6), (0.06, 0.06, 0.06), n=5, rows=3))
           .extend(blob((-0.4, 0.62, -0.6), (0.06, 0.06, 0.06), n=5, rows=3))
           .extend(blob((0.45, 0.66, -1.05), (0.06, 0.06, 0.06), n=5, rows=3))
           .extend(blob((-0.45, 0.66, -1.05), (0.06, 0.06, 0.06), n=5, rows=3)), "larva_spot")
    m.part("ThoraxCore", tube([[0, 0.62, -0.1], [0, 0.58, 0.2], [0, 0.52, 0.42]], [(0.54, 0.46), (0.48, 0.42),
                                                                                   (0.4, 0.36)], n=10),
           "larva_chitin")
    add_legs(m, {
        "front": dict(hip=(0.26, 0.3, 0.36), knee=(0.42, 0.26, 0.42), ankle=(0.48, 0.08, 0.46),
                      foot=(0.5, 0.03, 0.52), claw=(0.4, 0, 1)),
        "mid": dict(hip=(0.3, 0.28, 0.14), knee=(0.48, 0.24, 0.16), ankle=(0.54, 0.08, 0.18),
                    foot=(0.56, 0.03, 0.22), claw=(1, 0, 0.3)),
        "rear": dict(hip=(0.32, 0.28, -0.08), knee=(0.5, 0.24, -0.1), ankle=(0.56, 0.08, -0.1),
                     foot=(0.58, 0.03, -0.12), claw=(1, 0, -0.3)),
    }, 0.05, 0.035, "larva_leg", "larva_chitin", coxa_r=(0.06, 0.05, 0.06), tibia_spikes=False)
    m.material("larva_head", (0.22, 0.12, 0.05), rough=0.45)
    hs = [(0.36, 0.38, 0.84, 0.2), (0.52, 0.4, 0.84, 0.18), (0.68, 0.33, 0.77, 0.2), (0.76, 0.24, 0.68, 0.24)]
    # Твёрдая тёмная головная капсула поверх головы (в игре голова красится палитрой, капсула — нет).
    cs = [(z, w * 1.04, t + 0.02, b - 0.01) for z, w, t, b in hs]
    cs[0], cs[-1] = (cs[0][0] - 0.02,) + cs[0][1:], (cs[-1][0] + 0.02,) + cs[-1][1:]
    cap = loft(section_rings(cs, headshape)[::-1])
    add_head(m, hs, "larva_head", extra=[("larva_capsule", cap, "larva_head")])
    m.material("larva_jaw", (0.05, 0.03, 0.015), rough=0.35)
    add_mandibles(m, (0.12, 0.3, 0.74), (0.17, 0.28, 0.84), (0.12, 0.26, 0.9), (0.03, 0.26, 0.92), 0.05, "larva_jaw",
                  tooth=False)
    add_antennae(m, [(0.22, 0.7, 0.7), (0.3, 0.78, 0.76), (0.34, 0.8, 0.82)], 0.025, "larva_chitin")
    return m


# ================================================================ Каста 2 — солдаты

def bomber():
    """Подрывник: живой заряд. Брюшко раздуто взрывчатой железой, как у муравья-камикадзе:
    тёмные тергиты разошлись, между ними светится натянутая перепонка; короткие надкрылья
    прикрывают только основание, на конце — тлеющие протоки. Попадание в брюшко — подрыв."""
    m = Model()
    mats(m, "bomb", (0.22, 0.08, 0.04))
    m.material("bomb_glow", (0.85, 0.2, 0.015), rough=0.35)
    m.material("bomb_duct_glow", (1.0, 0.42, 0.06), rough=0.3)
    m.material("bomb_seam", (0.30, 0.06, 0.02), rough=0.5)
    kit(m, "bomb",
        abd=[(0.0, 0.42, 0.82, 0.4), (-0.4, 0.5, 0.86, 0.36), (-0.9, 0.46, 0.84, 0.38), (-1.2, 0.3, 0.8, 0.44)],
        elytra=dict(zf=0.06, zr=-0.7, w=0.74, h=0.46, y0=0.66, zst=-0.25, ribs=(0.45,)),
        thorax=[(0.04, 0.6, 0.98, 0.38), (0.3, 0.62, 1.0, 0.38), (0.52, 0.52, 0.96, 0.42), (0.64, 0.4, 0.9, 0.46)],
        legs={
            "front": dict(hip=(0.36, 0.42, 0.5), knee=(0.86, 0.84, 0.74), ankle=(1.12, 0.12, 1.0),
                          foot=(1.22, 0.03, 1.22), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.44, 0.4, 0.06), knee=(1.04, 0.88, 0.04), ankle=(1.36, 0.12, 0.06),
                        foot=(1.52, 0.03, 0.08), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.46, 0.38, -0.34), knee=(1.06, 0.9, -0.74), ankle=(1.34, 0.12, -1.12),
                         foot=(1.44, 0.03, -1.36), claw=(0.4, 0, -1)),
        }, leg_r=(0.12, 0.075), coxa=0.13, spikes=True,
        head=[(0.6, 0.44, 0.86, 0.4), (0.78, 0.46, 0.86, 0.38), (0.92, 0.38, 0.78, 0.4), (1.0, 0.28, 0.68, 0.44)],
        eyes=((0.42, 0.74, 0.76), (0.08, 0.09, 0.09)),
        mand=((0.18, 0.5, 0.94), (0.28, 0.48, 1.1), (0.2, 0.47, 1.22), (0.05, 0.47, 1.27), 0.075, True),
        ant=[(0.26, 0.8, 0.92), (0.42, 0.94, 1.0), (0.56, 1.0, 1.08), (0.66, 1.0, 1.16), (0.72, 0.96, 1.24)])
    # Раздутая железа: поднимается из-под надкрылий и нависает над задними лапами.
    gland, at = sac([(-0.1, 0.62, 0.4, 0.26), (-0.45, 0.82, 0.68, 0.5), (-0.95, 0.98, 0.84, 0.64),
                     (-1.5, 0.94, 0.82, 0.62), (-1.95, 0.82, 0.62, 0.48), (-2.2, 0.72, 0.28, 0.24)], n=12)
    m.part("bomb_gland", gland, "bomb_glow")
    # Тёмные тергиты поверх: между ними светится перепонка — видно, что брюшко вот-вот лопнет.
    for k, (z0, z1) in enumerate(((-0.06, -0.37), (-0.47, -0.77), (-0.87, -1.15), (-1.25, -1.51), (-1.61, -1.85), (-1.95, -2.12))):
        m.part(f"BeetleSternite_{k + 3:02d}", band_plate(at, z0, z1), "bomb_chitin")
    # Тёмные швы-рубцы вдоль боков и протоки на конце, тлеющие тем же цветом.
    seam = Mesh()
    for s in (1, -1):
        pts = []
        for z in np.linspace(-0.3, -2.0, 7):
            y, rx, ry = at(z)
            pts.append([s * rx * 1.01 * math.cos(0.5), y - ry * 1.01 * math.sin(0.5), z])
        seam.extend(tube(pts, [0.03] * 7, n=3))
    m.part("bomb_seam", seam, "bomb_seam")
    ducts = Mesh()
    for a in (0.6, 1.57, 2.5):
        base = np.array([math.cos(a) * 0.18, 0.72 + math.sin(a) * 0.15, -2.18])
        ducts.extend(tube([base, base + np.array([math.cos(a) * 0.08, math.sin(a) * 0.06, -0.12])], [0.05, 0.035], n=5))
    m.part("bomb_duct", ducts, "bomb_duct_glow")
    return m


def shield_bearer():
    """Щитоносец: переднеспинка разрослась в широкий выпуклый щит (как у жука-черепашки):
    он закрывает голову и передние лапы, выше и шире самого жука, с рёбрами-лучами и
    зубчатой кромкой. Под щитом видны только жвалы и концы лап."""
    m = Model()
    mats(m, "shld", (0.20, 0.08, 0.04))
    m.material("shield_plate", (0.05, 0.022, 0.012), rough=0.35)
    m.material("shield_rib", (0.07, 0.03, 0.016), rough=0.45)
    m.material("shield_rim", (0.09, 0.04, 0.02), rough=0.45)
    kit(m, "shld",
        abd=[(0.0, 0.58, 0.9, 0.36), (-0.4, 0.74, 0.95, 0.3), (-1.0, 0.74, 0.94, 0.3),
             (-1.45, 0.56, 0.88, 0.36), (-1.65, 0.24, 0.82, 0.5)],
        elytra=dict(zf=0.06, zr=-1.75, w=0.84, h=0.5, y0=0.56, zst=-0.7, ribs=(0.35, 0.7)),
        # Переднеспинка горбом поднимается к щиту.
        thorax=[(0.04, 0.78, 1.02, 0.34), (0.3, 0.84, 1.2, 0.34), (0.5, 0.8, 1.42, 0.38), (0.64, 0.66, 1.56, 0.42)],
        legs={
            "front": dict(hip=(0.42, 0.38, 0.52), knee=(0.92, 0.74, 0.62), ankle=(1.14, 0.12, 0.84),
                          foot=(1.22, 0.03, 1.04), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.5, 0.36, 0.08), knee=(1.12, 0.8, 0.04), ankle=(1.46, 0.12, 0.02),
                        foot=(1.64, 0.03, 0.02), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.52, 0.34, -0.4), knee=(1.08, 0.78, -0.78), ankle=(1.36, 0.12, -1.16),
                         foot=(1.46, 0.03, -1.42), claw=(0.4, 0, -1)),
        }, leg_r=(0.13, 0.08), coxa=0.14, spikes=True,
        head=[(0.6, 0.4, 0.8, 0.36), (0.78, 0.42, 0.8, 0.34), (0.92, 0.34, 0.72, 0.36), (1.0, 0.26, 0.62, 0.4)],
        eyes=((0.4, 0.68, 0.78), (0.07, 0.08, 0.08)),
        mand=((0.18, 0.44, 0.96), (0.28, 0.42, 1.12), (0.2, 0.41, 1.26), (0.05, 0.41, 1.32), 0.075, True),
        ant=[(0.3, 0.72, 0.9), (0.52, 0.8, 0.94), (0.72, 0.84, 0.98), (0.9, 0.82, 1.02)])
    # Щит — кусок купола вокруг центра c: азимут ±PHI, высота от низа (по бокам выше — под ним
    # проходят лапы) до макушки, которая врастает в горб переднеспинки.
    c = np.array([0.0, 0.1, 0.25])
    R, T = 1.5, 0.07
    PHI = math.radians(78)
    nu, nv = 12, 7

    def pt(u, v, r):
        phi = PHI * u
        th_lo = math.radians(-2 + 42 * u * u)
        th_hi = math.radians(76)
        th = th_lo + (th_hi - th_lo) * v
        sx = 1.08  # чуть шире, чем выше
        return c + np.array([r * math.cos(th) * math.sin(phi) * sx, r * math.sin(th), r * math.cos(th) * math.cos(phi)])

    us = np.linspace(-1, 1, nu + 1)
    vs = np.linspace(0, 1, nv + 1)
    outer = [[pt(u, v, R) for v in vs] for u in us]
    inner = [[pt(u, v, R - T) for v in vs] for u in us]
    plate = Mesh()
    for i in range(nu):
        for j in range(nv):
            plate.quad(outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1])
            plate.quad(inner[i][j], inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j])
    for i in range(nu):  # нижняя и верхняя кромки
        plate.quad(outer[i][0], inner[i][0], inner[i + 1][0], outer[i + 1][0])
        plate.quad(outer[i][nv], outer[i + 1][nv], inner[i + 1][nv], inner[i][nv])
    for i, flip in ((0, False), (nu, True)):  # боковые кромки
        for j in range(nv):
            a, b, cc, d = outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]
            if flip:
                plate.quad(a, b, cc, d)
            else:
                plate.quad(d, cc, b, a)
    m.part("BeetlePlate_shield", plate, "shield_plate")
    # Пологие рёбра-лучи от макушки к кромке.
    ribs = Mesh()
    for u in np.linspace(-0.75, 0.75, 5):
        pts = [pt(u, v, R + 0.012) for v in np.linspace(0.9, 0.08, 6)]
        ribs.extend(tube(pts, [0.02, 0.026, 0.03, 0.034, 0.034, 0.03], n=4))
    m.part("shield_rib", ribs, "shield_rib")
    # Утолщённая кромка по низу и бокам.
    rim = Mesh()
    edge = [pt(u, 0.0, R - T / 2) for u in np.linspace(-1, 1, 17)]
    rim.extend(tube(edge, [0.06] * 17, n=5))
    m.part("shield_rim", rim, "shield_rim")
    return m


def coordinator():
    """Координатор: щелкун-светлячок (как Pyrophorus). Длинное узкое тело, колоколом
    переднеспинка с острыми задними углами, на ней два светящихся пятна-«фары»: ими он и
    наводит солдат. Гребенчатые усы подняты вперёд — он всё время «показывает»."""
    m = Model()
    mats(m, "coord", (0.20, 0.08, 0.04))
    m.material("coord_glow", (0.25, 0.8, 0.04), rough=0.3)
    # Острые задние углы переднеспинки — продолжение груди назад по бокам надкрылий.
    horns = Mesh()
    for s in (1, -1):
        horns.extend(tube([[s * 0.56, 0.92, 0.04], [s * 0.64, 0.86, -0.12], [s * 0.66, 0.8, -0.24]],
                          [(0.09, 0.06), (0.06, 0.04), (0.012, 0.01)], n=4))
    kit(m, "coord",
        abd=[(-0.05, 0.46, 0.8, 0.4), (-0.5, 0.52, 0.86, 0.36), (-1.1, 0.5, 0.84, 0.36),
             (-1.6, 0.38, 0.74, 0.42), (-1.92, 0.18, 0.6, 0.5)],
        elytra=dict(zf=0.0, zr=-2.0, w=0.6, h=0.4, y0=0.62, zst=-0.9, power=2.4, ribs=(0.25, 0.5, 0.75),
                    rib_r=0.014),
        thorax=[(-0.02, 0.6, 1.04, 0.42), (0.22, 0.6, 1.1, 0.4), (0.46, 0.52, 1.06, 0.42), (0.64, 0.4, 0.96, 0.48)],
        thorax_extra=horns,
        legs={
            "front": dict(hip=(0.36, 0.5, 0.48), knee=(0.86, 0.9, 0.7), ankle=(1.1, 0.12, 1.04),
                          foot=(1.2, 0.03, 1.28), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.4, 0.46, 0.1), knee=(1.0, 0.92, 0.08), ankle=(1.36, 0.12, 0.08),
                        foot=(1.54, 0.03, 0.1), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.42, 0.44, -0.24), knee=(1.0, 0.9, -0.64), ankle=(1.28, 0.12, -1.06),
                         foot=(1.4, 0.03, -1.34), claw=(0.4, 0, -1)),
        }, leg_r=(0.09, 0.055), spikes=True,
        head=[(0.6, 0.36, 0.88, 0.48), (0.76, 0.38, 0.88, 0.46), (0.9, 0.32, 0.8, 0.48), (0.98, 0.24, 0.72, 0.5)],
        eyes=((0.3, 0.76, 0.82), (0.09, 0.1, 0.1)),
        mand=((0.13, 0.54, 0.96), (0.2, 0.52, 1.06), (0.13, 0.51, 1.14), (0.04, 0.51, 1.17), 0.05, False),
        ant=[(0.2, 0.84, 0.96), (0.34, 0.98, 1.16), (0.48, 1.12, 1.36), (0.6, 1.24, 1.54), (0.7, 1.32, 1.7)],
        ant_r=0.03)
    # Гребень на усиках: от каждого членика наружу и вниз — плоские зубцы.
    pts = [np.array(p) for p in [(0.2, 0.84, 0.96), (0.34, 0.98, 1.16), (0.48, 1.12, 1.36), (0.6, 1.24, 1.54),
                                 (0.7, 1.32, 1.7)]]
    comb = Mesh()
    for i in range(len(pts) - 1):
        for t in (0.35, 0.8):
            p0 = pts[i] + (pts[i + 1] - pts[i]) * t
            ln = 0.2 - 0.025 * i
            comb.extend(tube([p0, p0 + np.array([ln * 0.8, -ln * 0.5, ln * 0.25])], [(0.022, 0.012), (0.006, 0.004)],
                             n=4))
    for s, suf in ((1, "002"), (-1, "003")):
        m.part("AntSeg5Comb" + suf, comb if s == 1 else comb.mirrored_x(), "coord_chitin")
    # «Фары» на переднеспинке: два выпуклых овала у задних углов.
    lamp = Mesh()
    for s in (1, -1):
        c = np.array([s * 0.34, 1.07, 0.12])
        n = np.array([s * 0.35, 1.0, 0.0])
        lamp.extend(stuck_disc(c, n / np.linalg.norm(n), 0.13, thick=0.045, stretch=1.25))
    m.part("coord_lamp", lamp, "coord_glow")
    return m


def ram():
    """Таран: жук-носорог. Массивный, низкий, с толстым загнутым вверх раздвоенным рогом на голове и вторым
    коротким на переднеспинке; толстые лапы с шипами — упираться при разгоне."""
    m = Model()
    mats(m, "ram", (0.17, 0.07, 0.035))
    # Рог головы: толстый у основания, загнут вверх, на конце раздвоен.
    horn_head = tube([[0, 0.8, 1.04], [0, 0.92, 1.32], [0, 1.12, 1.54], [0, 1.38, 1.64]],
                     [(0.17, 0.2), (0.13, 0.15), (0.09, 0.1), (0.05, 0.05)], n=6)
    horn_head.extend(both(tube([[0, 1.34, 1.63], [0.11, 1.5, 1.6]], [(0.05, 0.05), (0.012, 0.012)], n=5)))
    kit(m, "ram",
        abd=[(0.0, 0.66, 1.0, 0.4), (-0.45, 0.82, 1.06, 0.34), (-1.1, 0.82, 1.04, 0.34),
             (-1.6, 0.62, 0.98, 0.4), (-1.82, 0.26, 0.9, 0.55)],
        elytra=dict(zf=0.08, zr=-1.92, w=0.92, h=0.6, y0=0.62, zst=-0.8, ribs=()),
        thorax=[(0.06, 0.86, 1.12, 0.38), (0.36, 0.88, 1.16, 0.38), (0.62, 0.78, 1.1, 0.42), (0.76, 0.62, 1.0, 0.46)],
        thorax_extra=tube([[0, 1.14, 0.42], [0, 1.36, 0.62], [0, 1.44, 0.82]], [(0.14, 0.16), (0.08, 0.09),
                                                                              (0.015, 0.015)], n=6),
        legs={
            "front": dict(hip=(0.46, 0.42, 0.62), knee=(1.04, 0.86, 0.8), ankle=(1.34, 0.12, 1.06),
                          foot=(1.46, 0.03, 1.28), claw=(0.4, 0, 1), paddle=0.12),
            "mid": dict(hip=(0.56, 0.4, 0.1), knee=(1.22, 0.88, 0.1), ankle=(1.58, 0.12, 0.12),
                        foot=(1.76, 0.03, 0.14), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.58, 0.38, -0.42), knee=(1.16, 0.86, -0.84), ankle=(1.46, 0.12, -1.26),
                         foot=(1.56, 0.03, -1.54), claw=(0.4, 0, -1)),
        }, leg_r=(0.15, 0.09), coxa=0.15, spikes=True,
        head=[(0.7, 0.5, 0.92, 0.4), (0.88, 0.5, 0.9, 0.38), (1.02, 0.42, 0.82, 0.4), (1.1, 0.32, 0.72, 0.44)],
        eyes=((0.48, 0.74, 0.84), (0.07, 0.08, 0.08)),
        head_extra=[("cheek_horn", horn_head, "ram_chitin")],
        ant=[(0.36, 0.7, 1.0), (0.48, 0.74, 1.1), (0.56, 0.74, 1.18)], club=0.06)
    return m


def sprinter():
    """Спринтер: мелкий бегун, как жук-скакун. Низкое узкое обтекаемое тело, очень длинные
    тонкие лапы (задние — длиннее всех), большие выпуклые глаза, усы откинуты назад; без
    жвал — он не грызёт."""
    m = Model()
    mats(m, "spr", (0.24, 0.09, 0.05))
    kit(m, "spr",
              abd=[(0.0, 0.34, 0.72, 0.42), (-0.4, 0.44, 0.74, 0.38), (-1.0, 0.42, 0.72, 0.38),
                   (-1.5, 0.3, 0.68, 0.44), (-1.85, 0.12, 0.62, 0.52)],
              elytra=dict(zf=0.06, zr=-1.95, w=0.5, h=0.3, y0=0.6, zst=-0.5, power=1.6, ribs=(0.3, 0.62), rib_r=0.014),
              thorax=[(0.04, 0.34, 0.8, 0.46), (0.28, 0.34, 0.82, 0.46), (0.5, 0.3, 0.8, 0.5), (0.62, 0.24, 0.76, 0.54)],
              legs={
                  "front": dict(hip=(0.2, 0.5, 0.48), knee=(0.82, 1.0, 0.86), ankle=(1.2, 0.12, 1.3),
                                foot=(1.32, 0.03, 1.6), claw=(0.4, 0, 1)),
                  "mid": dict(hip=(0.26, 0.48, 0.16), knee=(1.1, 1.08, 0.2), ankle=(1.66, 0.12, 0.26),
                              foot=(1.88, 0.03, 0.3), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.28, 0.46, -0.12), knee=(1.12, 1.12, -0.7), ankle=(1.56, 0.12, -1.5),
                               foot=(1.7, 0.03, -1.9), claw=(0.4, 0, -1)),
              }, leg_r=(0.075, 0.045), coxa=0.09,
              head=[(0.58, 0.3, 0.8, 0.5), (0.76, 0.32, 0.8, 0.48), (0.9, 0.26, 0.74, 0.5), (0.98, 0.18, 0.66, 0.54)],
              eyes=((0.33, 0.76, 0.8), (0.14, 0.13, 0.15)),
              ant=[(0.18, 0.78, 0.92), (0.36, 0.88, 0.8), (0.54, 0.92, 0.5), (0.66, 0.9, 0.12), (0.72, 0.86, -0.2)],
              ant_r=0.026)
    return m


def giant():
    """Гигант: жук-голиаф. Огромный высокий купол в буграх, толстые колонны-лапы, маленькая
    голова, тупой Y-образный рог; медленный и непробиваемый."""
    m = Model()
    mats(m, "giant", (0.15, 0.06, 0.03))
    dfn = kit(m, "giant",
              abd=[(0.0, 0.72, 1.1, 0.48), (-0.5, 0.9, 1.18, 0.42), (-1.2, 0.9, 1.16, 0.42),
                   (-1.8, 0.7, 1.08, 0.5), (-2.05, 0.3, 1.0, 0.66)],
              elytra=dict(zf=0.1, zr=-2.15, w=1.0, h=0.82, y0=0.72, zst=-0.9, power=2.2, ribs=(0.3, 0.6), rib_r=0.04),
              thorax=[(0.08, 0.94, 1.5, 0.48), (0.4, 0.96, 1.52, 0.48), (0.7, 0.84, 1.42, 0.52), (0.86, 0.66, 1.3, 0.56)],
              legs={
                  "front": dict(hip=(0.5, 0.54, 0.66), knee=(1.14, 1.06, 0.88), ankle=(1.46, 0.14, 1.16),
                                foot=(1.58, 0.03, 1.4), claw=(0.4, 0, 1)),
                  "mid": dict(hip=(0.62, 0.52, 0.08), knee=(1.34, 1.1, 0.08), ankle=(1.74, 0.14, 0.1),
                              foot=(1.92, 0.03, 0.12), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.64, 0.5, -0.5), knee=(1.3, 1.08, -0.96), ankle=(1.62, 0.14, -1.42),
                               foot=(1.74, 0.03, -1.7), claw=(0.4, 0, -1)),
              }, leg_r=(0.2, 0.13), coxa=0.19, spikes=True,
              head=[(0.8, 0.46, 0.98, 0.48), (0.96, 0.46, 0.96, 0.46), (1.08, 0.38, 0.88, 0.48), (1.14, 0.28, 0.78, 0.52)],
              eyes=((0.42, 0.82, 0.92), (0.07, 0.08, 0.08)),
              head_extra=[("cheek_horn", Mesh().extend(tube([[0, 0.9, 1.02], [0, 1.04, 1.24]], [(0.12, 0.1), (0.08, 0.07)], n=6))
                           .extend(both(tube([[0, 1.04, 1.24], [0.14, 1.14, 1.34]], [(0.07, 0.06), (0.03, 0.03)], n=5))),
                           "giant_chitin")],
              mand=((0.2, 0.56, 1.06), (0.28, 0.54, 1.18), (0.2, 0.53, 1.28), (0.06, 0.53, 1.32), 0.09, True),
              ant=[(0.36, 0.86, 1.04), (0.5, 0.92, 1.14), (0.6, 0.92, 1.24)], club=0.08)
    # Бугры на надкрыльях — того же панциря, низкие, рядами.
    knobs = Mesh()
    for z in (-0.2, -0.55, -0.9, -1.25, -1.6):
        for u in (0.22, 0.5, 0.78):
            c, n = on_dome(dfn, z + (0.17 if u == 0.5 else 0), u)
            knobs.extend(stuck_disc(c, n, 0.12, thick=0.05))
    m.part("BeetlePlate_knob", both(knobs), "giant_elytra")
    return m


def knitter():
    """Заживалка: панцирь треснул и не сходится — надкрылья раздвинуты, между ними набухла
    тёмная живая ткань. Через щель её стягивают свежие волокна, по краям — корки струпьев:
    видно, что жук зарастает прямо на ходу."""
    m = Model()
    mats(m, "knit", (0.20, 0.08, 0.05))
    m.material("knit_flesh", (0.36, 0.05, 0.06), rough=0.3)
    m.material("knit_strand", (0.62, 0.24, 0.22), rough=0.35)
    m.material("knit_scab", (0.07, 0.018, 0.012), rough=0.85)
    kit(m, "knit",
        abd=[(0.0, 0.52, 0.98, 0.45), (-0.4, 0.64, 1.04, 0.38), (-1.0, 0.64, 1.02, 0.38),
             (-1.4, 0.5, 0.96, 0.44), (-1.66, 0.22, 0.88, 0.56)],
        thorax=[(0.04, 0.58, 1.06, 0.44), (0.3, 0.6, 1.1, 0.44), (0.54, 0.52, 1.06, 0.48), (0.66, 0.4, 1.0, 0.52)],
        legs={
            "front": dict(hip=(0.32, 0.5, 0.48), knee=(0.84, 0.92, 0.76), ankle=(1.12, 0.12, 1.04),
                          foot=(1.24, 0.03, 1.28), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.4, 0.48, 0.1), knee=(1.02, 0.96, 0.1), ankle=(1.38, 0.12, 0.14),
                        foot=(1.56, 0.03, 0.18), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.42, 0.46, -0.26), knee=(0.98, 0.94, -0.62), ankle=(1.26, 0.12, -1.04),
                         foot=(1.36, 0.03, -1.3), claw=(0.4, 0, -1)),
        }, leg_r=(0.11, 0.065), spikes=True,
        head=[(0.62, 0.4, 0.98, 0.5), (0.8, 0.42, 0.98, 0.48), (0.94, 0.36, 0.9, 0.5), (1.02, 0.26, 0.8, 0.54)],
        eyes=((0.38, 0.86, 0.82), (0.09, 0.1, 0.1)),
        mand=((0.16, 0.56, 0.98), (0.24, 0.54, 1.12), (0.17, 0.53, 1.22), (0.04, 0.53, 1.26), 0.065, True),
        ant=[(0.24, 0.92, 0.94), (0.4, 1.06, 1.06), (0.52, 1.12, 1.2), (0.6, 1.12, 1.34)])
    # Надкрылья не сходятся: внутренний край отодвинут от шва на GAP.
    zf, zr, y0, GAP = 0.06, -1.72, 0.68, 0.22
    zs = [zf + (zr - zf) * f for f in EL_F]
    width, height = dome(zf, zr, 0.74, 0.5, z_straight=-0.7, power=2.0)
    add_elytra(m, elytron(zs, width, height, y0, seam=GAP, segs=5, ribs=(0.55,)), "knit_elytra")
    # Набухшая ткань в щели: чуть выше кромок надкрылий.
    flesh, at = sac([(0.04, 0.86, 0.34, 0.28), (-0.3, 0.88, 0.48, 0.36), (-0.8, 0.88, 0.5, 0.36),
                     (-1.3, 0.84, 0.44, 0.3), (-1.66, 0.74, 0.22, 0.16)], n=10)
    m.part("knit_flesh", flesh, "knit_flesh")
    # Волокна крест-накрест через щель, провисают в ткань.
    strands = Mesh()
    for k, z in enumerate(np.linspace(-0.12, -1.4, 7)):
        dz = 0.16 if k % 2 else -0.16
        za, zb = z + dz / 2, z - dz / 2
        a = np.array([GAP + 0.02, y0 + height(za) - 0.02, za])
        b = np.array([-GAP - 0.02, y0 + height(zb) - 0.02, zb])
        y, rx, ry = at(z)
        mid = np.array([0, y + ry + 0.01, z])
        strands.extend(tube([a, (a + mid) / 2 + np.array([0, 0.02, 0]), mid, (b + mid) / 2 + np.array([0, 0.02, 0]), b],
                            [0.024, 0.03, 0.026, 0.03, 0.024], n=4))
    m.part("knit_strand", strands, "knit_strand")
    # Корки по внутренним кромкам надкрылий.
    scabs = Mesh()
    for z, s, r in ((-0.05, 1, 0.1), (-0.42, -1, 0.13), (-0.66, 1, 0.09), (-1.0, 1, 0.12), (-1.18, -1, 0.1),
                    (-1.5, -1, 0.08)):
        c = np.array([s * (GAP + 0.04), y0 + height(z) - 0.01, z])
        scabs.extend(blob(c, (r * 0.8, r * 0.4, r * 1.3), n=5, rows=3))
    m.part("knit_scab", scabs, "knit_scab")
    return m


# ================================================================ Каста 3 — особые

def facehugger():
    """Лицехват: плоское широкое тело, шесть длинных узловатых лап-«пальцев» дугой вниз —
    ими он обхватывает корпус турели; сегментированный хвост закручен над спиной, под
    головой — присоска. Маленькие перепончатые крылья: перелетает на турель."""
    m = Model()
    mats(m, "hug", (0.60, 0.52, 0.36), leg=(0.50, 0.42, 0.28))
    m.material("hug_wing", (0.32, 0.28, 0.26), rough=0.4, alpha=0.55)
    m.material("hug_vein", (0.12, 0.09, 0.07), rough=0.5)
    m.material("hug_sucker", (0.42, 0.12, 0.14), rough=0.35)
    kit(m, "hug",
        abd=[(0.1, 0.62, 0.84, 0.58), (-0.2, 0.74, 0.86, 0.56), (-0.5, 0.66, 0.84, 0.58), (-0.74, 0.34, 0.8, 0.62)],
        thorax=[(0.08, 0.62, 0.88, 0.6), (0.3, 0.66, 0.9, 0.6), (0.5, 0.58, 0.88, 0.62), (0.62, 0.42, 0.84, 0.64)],
        legs={
            "front": dict(hip=(0.42, 0.72, 0.5), knee=(0.96, 1.16, 0.98), ankle=(1.34, 0.42, 1.38),
                          foot=(1.28, 0.03, 1.56), claw=(-0.5, 0, -0.4), femur_r=0.1, tibia_r=0.075),
            "mid": dict(hip=(0.56, 0.72, 0.1), knee=(1.3, 1.2, 0.12), ankle=(1.86, 0.42, 0.14),
                        foot=(1.9, 0.03, 0.14), claw=(-1, 0, 0), femur_r=0.1, tibia_r=0.075),
            "rear": dict(hip=(0.5, 0.72, -0.3), knee=(1.14, 1.16, -0.74), ankle=(1.56, 0.42, -1.12),
                         foot=(1.52, 0.03, -1.3), claw=(-0.5, 0, 0.5), femur_r=0.1, tibia_r=0.075),
        }, leg_r=(0.1, 0.075), coxa=0.13,
        head=[(0.56, 0.3, 0.86, 0.64), (0.72, 0.3, 0.86, 0.62), (0.84, 0.24, 0.82, 0.64), (0.9, 0.16, 0.78, 0.66)],
        eyes=((0.22, 0.8, 0.74), (0.05, 0.05, 0.06)),
        head_extra=[("hug_sucker", Mesh().extend(blob((0, 0.6, 0.78), (0.16, 0.05, 0.16), n=8, rows=3)),
                     "hug_sucker")])
    # Хвост из члеников: назад, вверх и закручен над спиной.
    path = [np.array(p) for p in [(0, 0.7, -0.72), (0, 0.72, -1.04), (0, 0.8, -1.34), (0, 0.96, -1.6),
                                  (0, 1.18, -1.76), (0, 1.42, -1.8), (0, 1.62, -1.7), (0, 1.76, -1.5),
                                  (0, 1.8, -1.28), (0, 1.74, -1.1)]]
    tail = Mesh()
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        r = 0.15 - 0.011 * i
        d = b - a
        tail.extend(tube([a + d * 0.04, a + d * 0.5, b - d * 0.04], [r * 0.82, r, r * 0.86], n=6))
    tail.extend(tube([path[-1], path[-1] + np.array([0, -0.12, 0.1])], [0.04, 0.008], n=4))
    m.part("BeetleSternite_tail", tail, "hug_chitin")
    add_wings(m, [(0.2, 0.96, 0.25), (0.72, 1.0, 0.04), (0.98, 0.98, -0.4), (0.72, 0.96, -0.78), (0.24, 0.94, -0.36)],
              "hug_wing", "hug_vein", lift=0.3, veins=(1, 2))
    return m


def absorber():
    """Разносчик: впитывает элементы и копит их в брюшке, как медовый муравей-бочка мёд.
    Брюшко раздуто на тонком стебельке: тёмные тергиты разошлись островками по натянутой
    светлой перепонке, по бокам сквозь неё просвечивают три пузыря с впитанным."""
    m = Model()
    mats(m, "abs", (0.14, 0.07, 0.10))
    m.material("abs_membrane", (0.13, 0.085, 0.15), rough=0.18)
    m.material("abs_glow", (0.35, 0.06, 0.7), rough=0.3)
    prof = [(-0.3, 0.86, 0.3, 0.26), (-0.55, 0.94, 0.62, 0.52), (-0.95, 1.0, 0.8, 0.66),
            (-1.55, 0.98, 0.82, 0.66), (-2.05, 0.9, 0.66, 0.54), (-2.36, 0.82, 0.32, 0.3)]
    # Стебелёк между грудью и брюшком.
    petiole = Mesh().extend(blob((0, 0.84, -0.14), (0.16, 0.16, 0.16), n=6, rows=4))
    kit(m, "abs",
        abd=[(z, rx * 0.95, y + ry * 0.95, y - ry * 0.95) for z, y, rx, ry in prof],
        thorax=[(0.0, 0.42, 1.0, 0.56), (0.28, 0.46, 1.06, 0.54), (0.5, 0.4, 1.02, 0.56), (0.62, 0.32, 0.96, 0.6)],
        thorax_extra=petiole,
        legs={
            "front": dict(hip=(0.28, 0.6, 0.48), knee=(0.8, 1.02, 0.76), ankle=(1.1, 0.12, 1.06),
                          foot=(1.22, 0.03, 1.3), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.34, 0.58, 0.16), knee=(1.0, 1.04, 0.16), ankle=(1.4, 0.12, 0.14),
                        foot=(1.58, 0.03, 0.14), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.36, 0.58, -0.04), knee=(1.12, 1.04, -0.44), ankle=(1.5, 0.12, -0.86),
                         foot=(1.64, 0.03, -1.1), claw=(0.4, 0, -1)),
        }, leg_r=(0.09, 0.055),
        head=[(0.6, 0.36, 0.98, 0.56), (0.78, 0.38, 0.98, 0.54), (0.92, 0.32, 0.92, 0.56), (1.0, 0.22, 0.84, 0.6)],
        eyes=((0.34, 0.88, 0.8), (0.09, 0.1, 0.1)),
        mand=((0.13, 0.62, 0.96), (0.21, 0.6, 1.08), (0.14, 0.59, 1.18), (0.04, 0.59, 1.22), 0.055, False),
        ant=[(0.2, 0.94, 0.94), (0.34, 1.12, 1.02), (0.44, 1.2, 1.16), (0.5, 1.18, 1.32), (0.54, 1.12, 1.44)])
    skin, at = sac(prof, n=12)
    m.part("abs_membrane", skin, "abs_membrane")
    # Тергиты разошлись: узкие пластины только по верху, между ними — перепонка.
    for k, (z0, z1) in enumerate(((-0.4, -0.62), (-0.78, -1.0), (-1.18, -1.4), (-1.58, -1.8), (-1.96, -2.14),
                                  (-2.24, -2.34))):
        m.part(f"BeetleSternite_{k + 3:02d}", band_plate(at, z0, z1, grow=1.06, a0=0.55, a1=math.pi - 0.55, thick=0.04),
               "abs_chitin")
    # Пузыри с впитанным просвечивают сквозь перепонку по бокам, ниже тергитов.
    ves = Mesh()
    for z, a, r in ((-0.9, 0.2, 0.22), (-1.45, math.pi - 0.3, 0.26), (-1.95, 0.35, 0.19)):
        y, rx, ry = at(z)
        nrm = np.array([-math.cos(a) * ry, math.sin(a) * rx, 0.0])
        c = np.array([-math.cos(a) * rx * 1.0, y + math.sin(a) * ry * 1.0, z])
        ves.extend(stuck_disc(c, nrm / np.linalg.norm(nrm), r, thick=0.05, stretch=1.3))
    m.part("abs_vesicle", ves, "abs_glow")
    return m


def evolver():
    """Эволюционер: подстраивается под оружие — и это видно: поверх старого панциря у него
    нарастает новая броня. Левое надкрылье и бок переднеспинки уже в черепице тёмных
    отливающих чешуй, на правом пошёл только первый ряд. Несимметричный, «на полпути»."""
    m = Model()
    mats(m, "evo", (0.12, 0.08, 0.10))
    m.material("evo_scale", (0.02, 0.1, 0.095), rough=0.15)
    dfn = kit(m, "evo",
              abd=[(0.0, 0.48, 0.96, 0.42), (-0.4, 0.62, 1.0, 0.36), (-1.0, 0.62, 0.98, 0.36),
                   (-1.4, 0.48, 0.92, 0.42), (-1.62, 0.2, 0.86, 0.54)],
              elytra=dict(zf=0.06, zr=-1.72, w=0.72, h=0.5, y0=0.64, zst=-0.7, ribs=(0.5,)),
              thorax=[(0.04, 0.56, 1.04, 0.42), (0.3, 0.58, 1.08, 0.42), (0.54, 0.5, 1.04, 0.46), (0.66, 0.38, 0.98, 0.5)],
              legs={
                  "front": dict(hip=(0.3, 0.48, 0.48), knee=(0.84, 0.92, 0.76), ankle=(1.12, 0.12, 1.04),
                                foot=(1.24, 0.03, 1.28), claw=(0.4, 0, 1)),
                  "mid": dict(hip=(0.38, 0.46, 0.1), knee=(1.02, 0.96, 0.1), ankle=(1.38, 0.12, 0.14),
                              foot=(1.56, 0.03, 0.18), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.4, 0.44, -0.26), knee=(0.98, 0.94, -0.64), ankle=(1.26, 0.12, -1.06),
                               foot=(1.36, 0.03, -1.32), claw=(0.4, 0, -1)),
              }, leg_r=(0.11, 0.065), spikes=True,
              head=[(0.62, 0.4, 0.96, 0.48), (0.8, 0.42, 0.96, 0.46), (0.94, 0.36, 0.88, 0.48), (1.02, 0.26, 0.78, 0.52)],
              eyes=((0.38, 0.84, 0.82), (0.09, 0.1, 0.1)),
              mand=((0.16, 0.54, 0.98), (0.26, 0.52, 1.12), (0.18, 0.51, 1.22), (0.04, 0.51, 1.26), 0.07, True),
              ant=[(0.24, 0.9, 0.94), (0.4, 1.04, 1.06), (0.5, 1.1, 1.2), (0.56, 1.08, 1.34)])
    # Новая броня черепицей: ряды чешуй, задний край каждой лежит на следующей.
    sc = Mesh()
    rows = {1: (0.2, 0.48, 0.76), -1: (0.76,)}
    for s, us in rows.items():
        for u in us:
            n_z = 6 if s == 1 else 3
            for k in range(n_z):
                z = -0.1 - k * 0.25 - (0.12 if u == 0.48 else 0)
                c, n = on_dome(dfn, z, u, lift=0.02)
                sc.extend(stuck_disc(c * np.array([s, 1, 1]), n * np.array([s, 1, 1]), 0.2 - 0.016 * k,
                                     thick=0.05, stretch=1.4))
    for z, x in ((0.18, 0.62), (0.4, 0.6), (0.28, 0.36)):
        sc.extend(stuck_disc(np.array([x, 1.04 if x < 0.5 else 0.9, z]), np.array([x * 0.6, 1, 0]) / np.linalg.norm([x * 0.6, 1, 0]),
                             0.17, thick=0.05, stretch=1.3))
    m.part("evo_scale", sc, "evo_scale")
    return m


def carrier():
    """Носитель: несёт в себе жуков, как пипа носит икру. Огромное брюшко-выводковая сумка,
    по спине — ячейки в кожистых валиках, из каждой выглядывает спинка молодого жука.
    Убит — они высыпаются. Сам тяжёлый и широкий."""
    m = Model()
    mats(m, "carr", (0.12, 0.07, 0.07))
    m.material("carr_rim", (0.045, 0.022, 0.024), rough=0.6)
    m.material("carr_brood", (0.13, 0.11, 0.04), rough=0.2)
    prof = [(0.0, 0.8, 0.5, 0.36), (-0.4, 0.92, 0.84, 0.56), (-1.0, 0.98, 0.94, 0.62), (-1.6, 0.92, 0.88, 0.56),
            (-2.0, 0.78, 0.6, 0.42), (-2.22, 0.66, 0.26, 0.2)]
    kit(m, "carr",
        abd=[(z, rx, y + ry, y - ry) for z, y, rx, ry in prof],
        thorax=[(0.04, 0.76, 1.0, 0.36), (0.34, 0.78, 1.04, 0.36), (0.6, 0.68, 1.0, 0.4), (0.74, 0.54, 0.94, 0.44)],
        legs={
            "front": dict(hip=(0.42, 0.4, 0.58), knee=(0.98, 0.84, 0.78), ankle=(1.28, 0.12, 1.04),
                          foot=(1.4, 0.03, 1.26), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.56, 0.38, -0.2), knee=(1.2, 0.86, -0.2), ankle=(1.56, 0.12, -0.18),
                        foot=(1.74, 0.03, -0.16), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.6, 0.36, -0.9), knee=(1.18, 0.84, -1.3), ankle=(1.46, 0.12, -1.7),
                         foot=(1.56, 0.03, -1.96), claw=(0.4, 0, -1)),
        }, leg_r=(0.13, 0.08), coxa=0.14,
        head=[(0.68, 0.42, 0.9, 0.4), (0.86, 0.44, 0.9, 0.38), (1.0, 0.36, 0.82, 0.4), (1.08, 0.26, 0.72, 0.44)],
        eyes=((0.42, 0.78, 0.86), (0.08, 0.09, 0.09)),
        mand=((0.18, 0.5, 1.02), (0.26, 0.48, 1.14), (0.18, 0.47, 1.24), (0.05, 0.47, 1.28), 0.07, False),
        ant=[(0.28, 0.84, 0.98), (0.42, 0.96, 1.1), (0.52, 1.0, 1.22), (0.58, 0.98, 1.34)], club=0.06)
    _, at = sac(prof)
    rims, brood = Mesh(), Mesh()
    for z, offs in ((-0.42, (-0.55, 0, 0.55)), (-0.92, (-0.9, -0.3, 0.3, 0.9)), (-1.42, (-0.55, 0, 0.55)),
                    (-1.84, (-0.3, 0.3))):
        y, rx, ry = at(z)
        for off in offs:
            a = math.pi / 2 + off
            n = np.array([-math.cos(a) * ry, math.sin(a) * rx, 0.0])
            n /= np.linalg.norm(n)
            p = np.array([-math.cos(a) * rx, y + math.sin(a) * ry, z])
            t1 = np.array([0, 0, 1.0])
            t2 = np.cross(n, t1)
            r = 0.17
            loop = [p + (t1 * math.cos(q) * 1.15 + t2 * math.sin(q)) * r for q in np.linspace(0, 2 * math.pi, 9)]
            rims.extend(tube(loop, [0.045] * 9, n=4, up_hint=tuple(n)))
            brood.extend(stuck_disc(p + n * 0.02, n, r * 0.78, thick=0.08, stretch=1.3))
    m.part("carr_rim", rims, "carr_rim")
    m.part("carr_brood", brood, "carr_brood")
    return m


def puppeteer():
    """Кукольник: оплетает раненых коконом. Длинное заострённое брюшко с прядильными
    бородавками, от них по полу тянутся нити шёлка; длинные хваткие передние лапы."""
    m = Model()
    mats(m, "pup", (0.16, 0.10, 0.14))
    m.material("pup_silk", (0.52, 0.5, 0.46), rough=0.7)
    m.material("pup_spinner", (0.09, 0.055, 0.08), rough=0.5)
    dfn = kit(m, "pup",
              abd=[(0.0, 0.42, 0.96, 0.5), (-0.4, 0.54, 1.02, 0.44), (-1.0, 0.54, 1.0, 0.44),
                   (-1.5, 0.4, 0.94, 0.5), (-1.85, 0.14, 0.86, 0.62)],
              elytra=dict(zf=0.04, zr=-1.3, w=0.62, h=0.44, y0=0.72, zst=-0.5, ribs=(0.5,)),
              thorax=[(0.02, 0.46, 1.06, 0.5), (0.3, 0.48, 1.1, 0.5), (0.56, 0.4, 1.06, 0.54), (0.7, 0.3, 1.0, 0.58)],
              legs={
                  "front": dict(hip=(0.24, 0.6, 0.56), knee=(0.74, 1.26, 1.0), ankle=(1.0, 0.3, 1.6),
                                foot=(1.06, 0.03, 1.86), claw=(0.2, 0, 1)),
                  "mid": dict(hip=(0.32, 0.56, 0.18), knee=(0.98, 1.06, 0.2), ankle=(1.34, 0.12, 0.24),
                              foot=(1.52, 0.03, 0.28), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.36, 0.54, -0.14), knee=(0.96, 1.04, -0.54), ankle=(1.26, 0.12, -1.0),
                               foot=(1.38, 0.03, -1.28), claw=(0.4, 0, -1)),
              }, leg_r=(0.09, 0.055),
              head=[(0.66, 0.34, 1.06, 0.62), (0.84, 0.36, 1.06, 0.6), (0.98, 0.3, 1.0, 0.62), (1.06, 0.22, 0.92, 0.66)],
              eyes=((0.32, 0.96, 0.9), (0.09, 0.1, 0.1)),
              mand=((0.12, 0.7, 1.02), (0.2, 0.68, 1.14), (0.14, 0.67, 1.24), (0.03, 0.67, 1.28), 0.055, False),
              ant=[(0.2, 1.06, 1.0), (0.34, 1.26, 1.14), (0.46, 1.36, 1.3), (0.54, 1.38, 1.46), (0.58, 1.34, 1.62)])
    # Хвост-веретено с прядильными бородавками.
    m.part("pup_spinner", Mesh().extend(tube([[0, 0.62, -1.75], [0, 0.66, -2.1], [0, 0.72, -2.35]],
                                             [(0.3, 0.26), (0.16, 0.14), (0.05, 0.05)], n=8))
           .extend(both(blob((0.08, 0.7, -2.36), (0.05, 0.05, 0.07), n=5, rows=3))), "pup_spinner")
    # Нити от бородавок: провисают к полу и тянутся следом.
    silk = Mesh()
    for x, sway in ((0.06, 0.16), (-0.06, -0.12)):
        pts = [[x, 0.7, -2.38], [x + sway * 0.3, 0.42, -2.5], [x + sway * 0.7, 0.14, -2.62], [x + sway, 0.03, -2.86],
               [x + sway * 1.2, 0.02, -3.1]]
        silk.extend(tube(pts, [0.016, 0.014, 0.013, 0.012, 0.008], n=3))
    m.part("pup_silk", silk, "pup_silk")
    return m


def hive_architect():
    """Архитектор улья: покрывает пол хитином. Широкий, плоский; надкрылья в рельефной сетке
    сот (из такого же хитина он и строит), в части ячеек — застывшая янтарная смола.
    Передние лапы-мастерки."""
    m = Model()
    mats(m, "hive", (0.10, 0.08, 0.10))
    m.material("hive_ridge", (0.035, 0.022, 0.035), rough=0.5)
    m.material("hive_resin", (0.42, 0.2, 0.02), rough=0.15)
    dfn = kit(m, "hive",
              abd=[(0.0, 0.62, 0.86, 0.36), (-0.45, 0.82, 0.9, 0.3), (-1.1, 0.82, 0.88, 0.3),
                   (-1.6, 0.62, 0.84, 0.36), (-1.82, 0.26, 0.78, 0.48)],
              elytra=dict(zf=0.08, zr=-1.9, w=0.96, h=0.4, y0=0.56, zst=-0.8, power=2.4, ribs=()),
              thorax=[(0.06, 0.84, 0.92, 0.34), (0.36, 0.88, 0.96, 0.34), (0.62, 0.78, 0.92, 0.38), (0.76, 0.62, 0.86, 0.42)],
              legs={
                  "front": dict(hip=(0.46, 0.38, 0.6), knee=(1.02, 0.78, 0.8), ankle=(1.3, 0.12, 1.06),
                                foot=(1.42, 0.03, 1.3), claw=(0.4, 0, 1), paddle=0.18),
                  "mid": dict(hip=(0.56, 0.36, 0.1), knee=(1.2, 0.8, 0.1), ankle=(1.56, 0.12, 0.12),
                              foot=(1.74, 0.03, 0.14), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.58, 0.34, -0.42), knee=(1.16, 0.78, -0.82), ankle=(1.44, 0.12, -1.2),
                               foot=(1.54, 0.03, -1.46), claw=(0.4, 0, -1)),
              }, leg_r=(0.12, 0.075), coxa=0.13,
              head=[(0.7, 0.5, 0.84, 0.36), (0.88, 0.52, 0.84, 0.34), (1.02, 0.44, 0.76, 0.36), (1.1, 0.34, 0.66, 0.4)],
              eyes=((0.5, 0.68, 0.88), (0.08, 0.09, 0.09)),
              mand=((0.2, 0.46, 1.06), (0.3, 0.44, 1.2), (0.2, 0.43, 1.3), (0.06, 0.43, 1.34), 0.075, False),
              ant=[(0.36, 0.78, 1.0), (0.56, 0.84, 1.08), (0.72, 0.84, 1.16), (0.84, 0.8, 1.24)], club=0.05)
    # Сетка сот по надкрылью: шестиугольники в координатах (u поперёк, z вдоль купола).
    R, du = 0.17, 0.2
    edges, centers = {}, []
    for row in range(8):
        z = -0.06 - row * R * 1.5
        for col in range(6):
            u = (col + (0.5 if row % 2 else 0)) * du + 0.04
            if u > 0.96 or z < -1.72:
                continue
            centers.append((u, z))
            vs = [(round(u + math.sin(k * math.pi / 3) * du / math.sqrt(3), 4), round(z + math.cos(k * math.pi / 3) * R, 4))
                  for k in range(6)]
            for i in range(6):
                e = tuple(sorted((vs[i], vs[(i + 1) % 6])))
                edges[e] = True
    ridges = Mesh()
    for (u0, z0), (u1, z1) in edges:
        if not (0 <= u0 <= 1 and 0 <= u1 <= 1 and z0 > -1.86 and z1 > -1.86 and z0 < 0.08 and z1 < 0.08):
            continue
        a, _ = on_dome(dfn, z0, u0, 0.012)
        b, _ = on_dome(dfn, z1, u1, 0.012)
        ridges.extend(tube([a, b], [0.022, 0.022], n=3))
    m.part("hive_ridge", both(ridges), "hive_ridge")
    resin = Mesh()
    for i in (3, 9, 14, 20, 26):
        if i < len(centers):
            u, z = centers[i]
            c, n = on_dome(dfn, z, u, 0.01)
            resin.extend(stuck_disc(c, n, 0.11, thick=0.03, stretch=1.1))
    m.part("hive_resin", resin, "hive_resin")
    return m


def mimic():
    """Мимик: прикидывается обломком бетона. Над телом — низкая гранёная «глыба» из двух
    половин (это надкрылья, сросшиеся с наростами); тонкий шов посередине — там, где она
    раскроется. Лапы и голова поджаты под камень, торчат только концы лапок и жвалы."""
    m = Model()
    mats(m, "mim", (0.18, 0.16, 0.13))
    kit(m, "mim",
        abd=[(0.0, 0.5, 0.74, 0.36), (-0.4, 0.62, 0.78, 0.3), (-1.0, 0.62, 0.78, 0.3),
             (-1.4, 0.48, 0.74, 0.36), (-1.6, 0.22, 0.68, 0.44)],
        thorax=[(0.04, 0.56, 0.78, 0.36), (0.3, 0.58, 0.8, 0.36), (0.52, 0.48, 0.76, 0.4), (0.64, 0.38, 0.72, 0.44)],
        legs={
            "front": dict(hip=(0.36, 0.36, 0.46), knee=(0.8, 0.58, 0.66), ankle=(1.02, 0.1, 0.88),
                          foot=(1.12, 0.03, 1.04), claw=(0.4, 0, 1)),
            "mid": dict(hip=(0.44, 0.34, 0.04), knee=(0.96, 0.58, 0.04), ankle=(1.2, 0.1, 0.06),
                        foot=(1.34, 0.03, 0.08), claw=(1, 0, 0.1)),
            "rear": dict(hip=(0.46, 0.32, -0.34), knee=(0.92, 0.58, -0.64), ankle=(1.12, 0.1, -0.94),
                         foot=(1.2, 0.03, -1.14), claw=(0.4, 0, -1)),
        }, leg_r=(0.11, 0.065),
        head=[(0.6, 0.36, 0.66, 0.3), (0.76, 0.38, 0.66, 0.28), (0.9, 0.32, 0.6, 0.3), (0.98, 0.24, 0.54, 0.34)],
        eyes=((0.3, 0.6, 0.8), (0.06, 0.06, 0.07)),
        mand=((0.15, 0.4, 0.92), (0.23, 0.38, 1.04), (0.15, 0.37, 1.12), (0.04, 0.37, 1.16), 0.06, True))
    prof = [(0.66, 0.6, 0.3, 0.12, 0.1), (0.46, 0.64, 0.8, 0.32, 0.26), (0.05, 0.68, 1.04, 0.46, 0.32),
            (-0.55, 0.7, 1.12, 0.52, 0.34), (-1.15, 0.68, 1.02, 0.46, 0.32), (-1.58, 0.62, 0.76, 0.34, 0.28),
            (-1.84, 0.58, 0.3, 0.14, 0.12)]
    m.part("BeetlePlate_00", rock_half(prof, 1), "mim_elytra")
    m.part("BeetlePlate_01", rock_half(prof, 7).mirrored_x(), "mim_elytra")
    # Пара мелких обломков, приросших сверху, — ломают ровный силуэт.
    chips = Mesh()
    for c, r, sd in (((0.42, 1.12, -0.42), (0.26, 0.14, 0.3), 3), ((-0.5, 1.08, -1.05), (0.22, 0.12, 0.2), 5)):
        b = blob(c, r, n=5, rows=3)
        chips.extend(b.transformed(lambda q, c=np.array(c), sd=sd: c + (q - c) * (1 + 0.3 * _rock_noise(q, sd))))
    m.part("BeetlePlate_chip", chips, "mim_elytra")
    return m


def shadow():
    """Тень: мелкий тёмный бегун. Узкий, низкий, матово-чёрный, без единой яркой детали;
    очень длинные тонкие усы и лапы — силуэт, который легко потерять из виду."""
    m = Model()
    mats(m, "shd", (0.04, 0.035, 0.04))
    kit(m, "shd",
              abd=[(0.0, 0.34, 0.74, 0.42), (-0.4, 0.44, 0.76, 0.38), (-1.0, 0.42, 0.74, 0.38),
                   (-1.45, 0.3, 0.7, 0.44), (-1.7, 0.12, 0.64, 0.52)],
              elytra=dict(zf=0.06, zr=-1.8, w=0.52, h=0.32, y0=0.6, zst=-0.5, power=1.7, ribs=(0.35, 0.7), rib_r=0.012),
              thorax=[(0.04, 0.36, 0.82, 0.46), (0.28, 0.38, 0.84, 0.46), (0.5, 0.32, 0.82, 0.5), (0.62, 0.26, 0.78, 0.54)],
              legs={
                  "front": dict(hip=(0.2, 0.5, 0.46), knee=(0.74, 0.92, 0.78), ankle=(1.04, 0.12, 1.12),
                                foot=(1.14, 0.03, 1.36), claw=(0.4, 0, 1)),
                  "mid": dict(hip=(0.26, 0.48, 0.14), knee=(0.94, 0.96, 0.16), ankle=(1.36, 0.12, 0.2),
                              foot=(1.54, 0.03, 0.24), claw=(1, 0, 0.1)),
                  "rear": dict(hip=(0.28, 0.46, -0.14), knee=(0.94, 0.98, -0.6), ankle=(1.28, 0.12, -1.2),
                               foot=(1.4, 0.03, -1.5), claw=(0.4, 0, -1)),
              }, leg_r=(0.07, 0.04), coxa=0.08,
              head=[(0.58, 0.3, 0.82, 0.5), (0.76, 0.32, 0.82, 0.48), (0.9, 0.26, 0.76, 0.5), (0.98, 0.18, 0.68, 0.54)],
              eyes=((0.3, 0.76, 0.8), (0.06, 0.07, 0.07)),
              ant=[(0.18, 0.8, 0.92), (0.4, 0.96, 1.2), (0.66, 1.04, 1.5), (0.92, 1.04, 1.84), (1.16, 0.96, 2.2)],
              ant_r=0.022)
    return m


SPECIES2 = {
    "acid_spitter": acid_spitter,
    "medic": medic,
    "queen": queen,
    "larva": larva,
    "bomber": bomber,
    "shield_bearer": shield_bearer,
    "coordinator": coordinator,
    "ram": ram,
    "sprinter": sprinter,
    "giant": giant,
    "knitter": knitter,
    "facehugger": facehugger,
    "absorber": absorber,
    "evolver": evolver,
    "carrier": carrier,
    "puppeteer": puppeteer,
    "hive_architect": hive_architect,
    "mimic": mimic,
    "shadow": shadow,
}
