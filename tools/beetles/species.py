"""Шесть жуков игры. Каждая функция возвращает Model. Оси: голова +Z, левая сторона +X, пол y = 0."""
import math

import numpy as np

from beetlegen import (Mesh, Model, add_abdomen, add_antennae, add_elytra, add_head, add_legs, add_mandibles,
                       add_sternites, blob, elytron, loft, rotate_about, section_rings, shield, tube)


def dome(z_front, z_rear, w_max, h_max, z_straight=None, power=2.2):
    """Ширина/высота надкрылий: ровные бока до z_straight, к заду — скругление."""
    zs_ = z_straight if z_straight is not None else (z_front + z_rear) / 2

    def width(z):
        if z > zs_:
            t = (z - zs_) / max(1e-6, z_front - zs_)
            return w_max * (1 - 0.06 * t * t)
        t = (z - zs_) / (z_rear - zs_)
        return w_max * math.sqrt(max(0.02, 1 - t ** power))

    def height(z):
        if z > zs_:
            t = (z - zs_) / max(1e-6, z_front - zs_)
            return h_max * (1 - 0.2 * t * t)
        t = (z - zs_) / (z_rear - zs_)
        return h_max * math.sqrt(max(0.05, 1 - t ** 2.0))

    return width, height


def thorax_groove(m_mesh, z0, z1, top0, top1):
    m_mesh.extend(tube([[0, top0 + 0.005, z0], [0, (top0 + top1) / 2, (z0 + z1) / 2], [0, top1 - 0.08, z1]],
                       [0.018] * 3, n=3))


# ---------------------------------------------------------------- Работяга

def worker():
    """Каста 1 — работяга: грызёт стены, таскает материал. Коренастый: высокий короткий
    купол, широкая переднеспинка без талии, тяжёлая голова с широкими жвалами-кусачками,
    короткие булавовидные усы, толстые короткие лапы."""
    m = Model()
    m.material("worker_elytra", (0.20, 0.10, 0.03), rough=0.55)
    m.material("worker_chitin", (0.11, 0.05, 0.015), rough=0.6)
    m.material("worker_leg", (0.040, 0.020, 0.008), rough=0.6)
    m.material("worker_eye", (0.010, 0.010, 0.012), rough=0.15)
    m.material("worker_mandible", (0.020, 0.010, 0.004), rough=0.35)
    y0 = 0.6

    add_abdomen(m, [(0.15, 0.7, 1.0, 0.36), (-0.3, 0.85, 1.05, 0.3), (-0.9, 0.85, 1.05, 0.3),
                    (-1.35, 0.65, 1.0, 0.36), (-1.58, 0.3, 0.92, 0.5)], "worker_chitin")
    add_sternites(m, [(-0.35, 0.5, 0.27), (-0.8, 0.5, 0.27), (-1.2, 0.4, 0.3)], "worker_chitin")

    zs = [0.16, 0.0, -0.35, -0.75, -1.1, -1.38, -1.55, -1.62]
    width, height = dome(0.16, -1.62, 0.94, 0.82, z_straight=-0.55, power=1.8)
    add_elytra(m, elytron(zs, width, height, y0, segs=5, ribs=(0.3, 0.6), rib_r=0.026), "worker_elytra")

    thorax = loft(section_rings([(0.12, 0.96, 1.4, 0.34), (0.42, 0.95, 1.38, 0.34), (0.68, 0.84, 1.28, 0.38),
                                 (0.8, 0.7, 1.16, 0.42)], shield)[::-1])
    # Два бугра у переднего края щита.
    for x in (-0.28, 0.28):
        thorax.extend(blob((x, 1.33, 0.62), (0.12, 0.08, 0.12), n=6, rows=3))
    m.part("ThoraxCore", thorax, "worker_chitin")

    add_legs(m, {
        "front": dict(hip=(0.45, 0.42, 0.6), knee=(0.98, 0.86, 0.86), ankle=(1.3, 0.12, 1.12),
                      foot=(1.42, 0.03, 1.36), claw=(0.4, 0, 1)),
        "mid": dict(hip=(0.55, 0.4, 0.05), knee=(1.15, 0.9, 0.05), ankle=(1.5, 0.12, 0.08),
                    foot=(1.68, 0.03, 0.1), claw=(1, 0, 0.1)),
        "rear": dict(hip=(0.58, 0.38, -0.5), knee=(1.1, 0.88, -0.86), ankle=(1.4, 0.12, -1.2),
                     foot=(1.5, 0.03, -1.45), claw=(0.4, 0, -1)),
    }, 0.17, 0.1, "worker_leg", "worker_chitin", coxa_r=(0.17, 0.14, 0.17))

    add_head(m, [(0.7, 0.6, 1.0, 0.38), (0.9, 0.62, 0.98, 0.36), (1.06, 0.54, 0.88, 0.38), (1.16, 0.42, 0.74, 0.42)],
             "worker_chitin", eyes=((0.56, 0.78, 0.86), (0.08, 0.09, 0.1)), eye_mat="worker_eye")
    # Жвалы-кусачки: широкие, короткие, с зубцами — грызть стены.
    add_mandibles(m, (0.26, 0.5, 1.12), (0.38, 0.48, 1.34), (0.27, 0.47, 1.5), (0.08, 0.46, 1.56), 0.13,
                  "worker_mandible", tooth=True)
    add_antennae(m, [(0.44, 0.8, 1.06), (0.62, 0.9, 1.18), (0.72, 0.92, 1.3), (0.78, 0.88, 1.4)], 0.045,
                 "worker_chitin", clubbed=0.09)
    # По замечанию автора: худее (уже на 26%) и длиннее (брюшко и надкрылья +18% назад).
    for n in m.nodes:
        if n["mesh"] is not None:
            n["mesh"] = n["mesh"].transformed(
                lambda p: np.array([p[0] * 0.74, p[1], p[2] * 1.18 if p[2] < 0 else p[2]]))
    return m


# ---------------------------------------------------------------- Мини

def mini():
    """Мелкий, круглый, яркий — божья коровка-переросток. Короткие лапы, большая голова."""
    m = Model()
    m.material("mini_elytra", (0.34, 0.085, 0.016), rough=0.5)
    m.material("mini_spot", (0.025, 0.010, 0.006), rough=0.5)
    m.material("mini_chitin", (0.055, 0.020, 0.008), rough=0.6)
    m.material("mini_leg", (0.035, 0.014, 0.006), rough=0.6)
    m.material("mini_eye", (0.010, 0.010, 0.012), rough=0.15)
    y0 = 0.5

    add_abdomen(m, [(0.08, 0.48, 0.72, 0.3), (-0.3, 0.64, 0.78, 0.24), (-0.8, 0.66, 0.78, 0.24),
                    (-1.25, 0.5, 0.74, 0.3), (-1.5, 0.22, 0.66, 0.42)], "mini_chitin")
    add_sternites(m, [(-0.45, 0.36, 0.23), (-0.9, 0.36, 0.23), (-1.25, 0.24, 0.29)], "mini_chitin")

    zs = [0.1, -0.1, -0.45, -0.8, -1.15, -1.4, -1.56, -1.64]
    width, height = dome(0.1, -1.64, 0.8, 0.66, z_straight=-0.55, power=2.0)
    add_elytra(m, elytron(zs, width, height, y0, segs=5, ribs=()), "mini_elytra")
    # Пятна на надкрыльях — сидят на куполе.
    spots = Mesh()
    for z, u, r in ((-0.35, 0.45, 0.17), (-0.95, 0.62, 0.15), (-1.3, 0.3, 0.11)):
        a = (math.pi / 2) * u
        w, h = width(z), height(z)
        c = np.array([0.012 + (w - 0.012) * math.sin(a), y0 + h * math.cos(a), z])
        normal = np.array([math.sin(a) * h, math.cos(a) * w, 0.0])
        normal /= np.linalg.norm(normal)
        disc = blob((0, 0, 0), (r, 0.04, r), n=6, rows=3)
        up = np.array([0, 1.0, 0])
        ax = np.cross(up, normal)
        ang = math.acos(np.clip(np.dot(up, normal), -1, 1))
        if np.linalg.norm(ax) > 1e-6:
            disc = rotate_about(disc, (0, 0, 0), ax, ang)
        spots.extend(disc.transformed(lambda p, c=c, n_=normal: p + c + n_ * 0.015))
    m.part("elytra_spot_00", spots, "mini_spot")
    m.part("elytra_spot_01", spots.mirrored_x(), "mini_spot")

    thorax = loft(section_rings([(0.05, 0.6, 1.02, 0.3), (0.25, 0.57, 1.0, 0.3), (0.42, 0.47, 0.9, 0.34)],
                                shield)[::-1])
    m.part("ThoraxCore", thorax, "mini_chitin")

    add_legs(m, {
        "front": dict(hip=(0.3, 0.34, 0.34), knee=(0.74, 0.6, 0.58), ankle=(0.98, 0.1, 0.84),
                      foot=(1.1, 0.03, 1.04), claw=(0.4, 0, 1)),
        "mid": dict(hip=(0.38, 0.32, -0.08), knee=(0.86, 0.64, -0.04), ankle=(1.14, 0.1, 0.0),
                    foot=(1.34, 0.03, 0.04), claw=(1, 0, 0.1)),
        "rear": dict(hip=(0.42, 0.3, -0.48), knee=(0.82, 0.6, -0.74), ankle=(1.04, 0.1, -1.0),
                     foot=(1.14, 0.03, -1.22), claw=(0.4, 0, -1)),
    }, 0.1, 0.06, "mini_leg", "mini_chitin", coxa_r=(0.11, 0.1, 0.11), tibia_spikes=False)

    add_head(m, [(0.36, 0.4, 0.84, 0.36), (0.58, 0.42, 0.82, 0.34), (0.76, 0.34, 0.72, 0.36),
                 (0.86, 0.22, 0.6, 0.4)], "mini_chitin",
             eyes=((0.37, 0.68, 0.6), (0.11, 0.13, 0.13)), eye_mat="mini_eye")
    add_mandibles(m, (0.14, 0.45, 0.82), (0.18, 0.44, 0.94), (0.12, 0.43, 1.03), (0.03, 0.43, 1.06), 0.055,
                  "mini_chitin", tooth=False)
    add_antennae(m, [(0.24, 0.74, 0.76), (0.38, 0.86, 0.92), (0.48, 0.9, 1.04), (0.56, 0.88, 1.14)], 0.032,
                 "mini_chitin", clubbed=0.06)
    return m


# ---------------------------------------------------------------- Строитель

def builder():
    """Толстяк-копатель: широкий высокий купол, светлое раздутое брюхо, голова-лопата,
    передние лапы-лопатки."""
    m = Model()
    m.material("builder_chitin", (0.195, 0.068, 0.019), rough=0.6)
    m.material("builder_dark", (0.068, 0.023, 0.007), rough=0.5)
    m.material("builder_leg", (0.045, 0.018, 0.007), rough=0.6)
    m.material("belly_fill", (0.687, 0.546, 0.332), rough=0.45)
    m.material("belly_seam", (0.254, 0.144, 0.065), rough=0.6)
    m.material("builder_eye", (0.010, 0.010, 0.012), rough=0.15)
    y0 = 0.82

    add_abdomen(m, [(0.25, 0.7, 1.0, 0.42), (-0.2, 0.85, 1.0, 0.35), (-1.0, 0.9, 1.0, 0.33),
                    (-1.7, 0.8, 1.0, 0.38), (-2.15, 0.5, 0.95, 0.5), (-2.4, 0.2, 0.85, 0.65)], "builder_chitin")
    # Раздутое светлое брюхо: торчит из-под надкрылий по бокам и снизу.
    belly = loft(section_rings([(0.05, 0.86, 0.95, 0.34), (-0.4, 1.06, 0.98, 0.26), (-1.1, 1.12, 0.98, 0.24),
                                (-1.7, 1.0, 0.98, 0.28), (-2.1, 0.7, 0.95, 0.38)],
                               lambda w, t, b: [(math.cos(a) * w, (t + b) / 2 + math.sin(a) * (t - b) / 2)
                                                for a in (2 * math.pi * i / 10 + math.pi / 10 for i in range(10))])[::-1])
    m.part("belly_fill", belly, "belly_fill")
    seams = Mesh()
    for z, w in ((-0.45, 1.04), (-0.85, 1.1), (-1.25, 1.1), (-1.65, 1.0)):
        pts = [[math.cos(a) * w * 1.01, 0.61 + math.sin(a) * 0.37 * 1.01, z]
               for a in np.linspace(-math.pi * 0.95, -math.pi * 0.05, 7)]
        seams.extend(tube(pts, [0.03] * len(pts), n=3, up_hint=(0, 0, 1)))
    m.part("belly_seam", seams, "belly_seam")

    zs = [0.22, 0.05, -0.5, -1.1, -1.65, -2.05, -2.32, -2.45]
    width, height = dome(0.22, -2.45, 1.06, 0.78, z_straight=-1.2)
    add_elytra(m, elytron(zs, width, height, y0, segs=5, ribs=(0.25, 0.5, 0.75), rib_r=0.026), "builder_chitin")

    thorax = loft(section_rings([(0.18, 0.92, 1.58, 0.42), (0.52, 0.88, 1.52, 0.42), (0.86, 0.72, 1.36, 0.46),
                                 (1.02, 0.58, 1.2, 0.5)], shield)[::-1])
    thorax.extend(tube([[0, 1.585, 0.22], [0, 1.55, 0.6], [0, 1.4, 0.88]], [0.022] * 3, n=3))
    # Рог-бугор на переднеспинке.
    thorax.extend(tube([[0, 1.5, 0.55], [0, 1.72, 0.78], [0, 1.74, 0.92]], [(0.16, 0.1), (0.1, 0.07), (0.03, 0.03)],
                       n=5))
    m.part("ThoraxCore", thorax, "builder_chitin")

    add_legs(m, {
        "front": dict(hip=(0.45, 0.48, 0.8), knee=(1.12, 1.0, 1.15), ankle=(1.5, 0.14, 1.55),
                      foot=(1.64, 0.03, 1.85), claw=(0.4, 0, 1), paddle=0.2),
        "mid": dict(hip=(0.62, 0.44, 0.1), knee=(1.42, 1.08, 0.12), ankle=(1.9, 0.14, 0.15),
                    foot=(2.12, 0.03, 0.2), claw=(1, 0, 0.1)),
        "rear": dict(hip=(0.66, 0.42, -0.55), knee=(1.38, 1.04, -1.05), ankle=(1.76, 0.14, -1.62),
                     foot=(1.92, 0.03, -2.0), claw=(0.4, 0, -1)),
    }, 0.17, 0.1, "builder_leg", "builder_chitin", coxa_r=(0.18, 0.15, 0.18))

    shovel = loft(section_rings([(1.18, 0.62, 0.62, 0.46), (1.5, 0.74, 0.54, 0.44), (1.72, 0.66, 0.48, 0.42),
                                 (1.8, 0.5, 0.46, 0.43)],
                                lambda w, t, b: [(0, t), (w * 0.8, t - 0.02), (w, (t + b) / 2), (w * 0.8, b),
                                                 (0, b), (-w * 0.8, b), (-w, (t + b) / 2), (-w * 0.8, t - 0.02)])[::-1])
    for x in (-0.36, 0.0, 0.36):  # зубцы лопаты
        shovel.extend(tube([[x, 0.45, 1.76], [x * 1.08, 0.43, 1.92]], [(0.07, 0.03), (0.01, 0.01)], n=4))
    cheeks = []
    for s, name in ((1, "cheek_L"), (-1, "cheek_R")):
        cheeks.append((name, blob((0.5 * s, 0.82, 1.1), (0.2, 0.2, 0.24), n=6, rows=4), "builder_chitin"))
    add_head(m, [(0.92, 0.55, 1.2, 0.5), (1.15, 0.56, 1.12, 0.46), (1.32, 0.46, 0.92, 0.46), (1.42, 0.36, 0.72, 0.46)],
             "builder_chitin", eyes=((0.5, 0.9, 1.3), (0.08, 0.09, 0.1)), eye_mat="builder_eye",
             extra=[("shovel_plate", shovel, "builder_dark")] + cheeks)
    add_mandibles(m, (0.22, 0.5, 1.4), (0.3, 0.46, 1.58), (0.22, 0.45, 1.7), (0.08, 0.44, 1.74), 0.08,
                  "builder_dark", tooth=False)
    add_antennae(m, [(0.42, 0.95, 1.32), (0.62, 1.08, 1.5), (0.76, 1.1, 1.66), (0.86, 1.06, 1.8)], 0.045,
                 "builder_dark", clubbed=0.11)
    return m


# ---------------------------------------------------------------- Хмурый брон

def armored():
    """Слепой танк: поперечные стальные пластины внахлёст, шлем на голове вместо глаз,
    тяжёлые тупые жвалы, длинные усы-щупы у пола."""
    m = Model()
    m.material("bron_chitin", (0.030, 0.018, 0.010), rough=0.6)
    m.material("bron_armor", (0.107, 0.133, 0.162), rough=0.4, metal=0.3)
    m.material("bron_edge", (0.200, 0.230, 0.260), rough=0.35, metal=0.3)
    m.material("bron_leg", (0.028, 0.020, 0.014), rough=0.6)
    m.material("bron_jaw", (0.042, 0.051, 0.065), rough=0.4, metal=0.2)

    add_abdomen(m, [(0.1, 0.6, 0.85, 0.32), (-0.3, 0.75, 0.88, 0.26), (-1.0, 0.78, 0.88, 0.26),
                    (-1.6, 0.6, 0.85, 0.32), (-1.95, 0.3, 0.78, 0.45)], "bron_chitin")
    add_sternites(m, [(-0.4, 0.42, 0.24), (-0.9, 0.42, 0.24), (-1.4, 0.36, 0.26)], "bron_chitin")

    # Поперечные пластины внахлёст: каждая следующая ниже и уже, передний край приподнят.
    bands = [(0.2, -0.32, 1.0, 0.68), (-0.22, -0.72, 0.98, 0.64), (-0.62, -1.1, 0.95, 0.6),
             (-1.0, -1.45, 0.86, 0.54), (-1.36, -1.78, 0.7, 0.45), (-1.7, -2.02, 0.45, 0.33)]
    y0 = 0.5
    for k, (z0, z1, w, h) in enumerate(bands):
        def arch(z, rise, w=w, h=h):
            outer = [(math.cos(a) * w, y0 + math.sin(a) * h + rise) for a in np.linspace(0, math.pi, 7)]
            inner = [(math.cos(a) * (w - 0.08), y0 + math.sin(a) * (h - 0.08) + rise)
                     for a in np.linspace(math.pi, 0, 7)]
            return [np.array([x, y, z]) for x, y in outer + inner]
        plate = loft([arch(z1, 0.0), arch((z0 + z1) / 2, 0.02), arch(z0, 0.06)])
        # Кромка-валик по переднему краю.
        edge = [[math.cos(a) * w, y0 + math.sin(a) * h + 0.07, z0] for a in np.linspace(0.05, math.pi - 0.05, 7)]
        m.part(f"Armor_BeetlePlate_{k:02d}", plate, "bron_armor")
        m.part(f"Armor_edge_{k:02d}", tube(edge, [0.035] * 7, n=4, up_hint=(0, 0, 1)), "bron_edge")

    # Грудь — хитин (prepare_beetles красит брюшко и тазики цветом груди), сверху — стальной щит.
    m.part("ThoraxCore", loft(section_rings([(0.18, 0.84, 1.2, 0.32), (0.5, 0.82, 1.18, 0.32), (0.8, 0.7, 1.08, 0.36),
                                             (0.93, 0.56, 0.97, 0.4)], shield)[::-1]), "bron_chitin")
    m.part("Armor_pronotum", loft(section_rings([(0.16, 0.92, 1.3, 0.62), (0.5, 0.9, 1.28, 0.62),
                                                 (0.8, 0.78, 1.18, 0.62), (0.95, 0.62, 1.05, 0.62)],
                                                shield)[::-1]), "bron_armor")

    add_legs(m, {
        "front": dict(hip=(0.42, 0.4, 0.66), knee=(1.02, 0.78, 0.98), ankle=(1.36, 0.12, 1.3),
                      foot=(1.5, 0.03, 1.58), claw=(0.4, 0, 1)),
        "mid": dict(hip=(0.55, 0.36, 0.08), knee=(1.2, 0.82, 0.1), ankle=(1.6, 0.12, 0.14),
                    foot=(1.82, 0.03, 0.18), claw=(1, 0, 0.1)),
        "rear": dict(hip=(0.58, 0.34, -0.45), knee=(1.16, 0.8, -0.85), ankle=(1.48, 0.12, -1.3),
                     foot=(1.62, 0.03, -1.65), claw=(0.4, 0, -1)),
    }, 0.16, 0.095, "bron_leg", "bron_chitin", coxa_r=(0.17, 0.14, 0.17))

    # Голова без глаз: шлем-каска и надбровный валик.
    casque = loft(section_rings([(0.85, 0.62, 1.08, 0.62), (1.1, 0.6, 1.06, 0.6), (1.32, 0.5, 0.95, 0.58),
                                 (1.45, 0.36, 0.82, 0.58)], shield)[::-1])
    brow = tube([[-0.5, 0.86, 1.33], [-0.25, 0.94, 1.42], [0.25, 0.94, 1.42], [0.5, 0.86, 1.33]],
                [(0.08, 0.06)] * 4, n=5, up_hint=(0, 1, 0))
    muscles = Mesh()
    for s in (1, -1):
        muscles.extend(blob((0.42 * s, 0.52, 1.12), (0.18, 0.14, 0.2), n=6, rows=3))
    add_head(m, [(0.8, 0.5, 0.95, 0.38), (1.05, 0.5, 0.92, 0.36), (1.3, 0.42, 0.8, 0.38), (1.45, 0.3, 0.68, 0.42)],
             "bron_chitin",
             extra=[("head_casque", casque, "bron_armor"), ("brow_ridge", brow, "bron_jaw"),
                    ("bite_muscle", muscles, "bron_chitin")])
    # Тяжёлые тупые жвалы-кусачки.
    add_mandibles(m, (0.26, 0.48, 1.42), (0.34, 0.46, 1.62), (0.24, 0.45, 1.76), (0.1, 0.45, 1.8), 0.13,
                  "bron_jaw", tooth=True)
    # Длинные щупы вперёд и вниз — он слепой, ищет дорогу усами.
    add_antennae(m, [(0.34, 0.78, 1.36), (0.55, 0.82, 1.62), (0.72, 0.7, 1.95), (0.84, 0.5, 2.3), (0.9, 0.3, 2.62)],
                 0.045, "bron_chitin")
    return m


# ---------------------------------------------------------------- Пеликан

def pelican():
    """Падальщик-летун: сгорбленный, длинная шея, клюв из длинных жвал, короткие
    раздвинутые надкрылья, из-под них — перепончатые крылья."""
    m = Model()
    m.material("pelican_chitin", (0.056, 0.021, 0.010), rough=0.6)
    m.material("pelican_fold", (0.13, 0.06, 0.03), rough=0.6)
    m.material("pelican_leg", (0.03, 0.014, 0.007), rough=0.6)
    m.material("milky_eye", (0.687, 0.651, 0.539), rough=0.3)
    m.material("beak", (0.023, 0.010, 0.005), rough=0.35)
    m.material("beak_tooth", (0.624, 0.552, 0.392), rough=0.4)
    m.material("neck_ruff", (0.013, 0.006, 0.003), rough=0.7)
    m.material("wing_membrane", (0.61, 0.479, 0.296), rough=0.4, alpha=0.55)
    m.material("wing_vein", (0.048, 0.019, 0.008), rough=0.5)

    # Пухлое брюшко со складками.
    add_abdomen(m, [(0.0, 0.5, 1.08, 0.5), (-0.35, 0.68, 1.15, 0.38), (-0.9, 0.72, 1.12, 0.36),
                    (-1.35, 0.58, 1.05, 0.44), (-1.6, 0.3, 0.95, 0.6)], "pelican_chitin", n=10)
    folds = Mesh()
    for z, w, y in ((-0.5, 0.7, 0.75), (-0.85, 0.72, 0.74), (-1.2, 0.62, 0.76)):
        pts = [[math.cos(a) * w * 1.02, y + math.sin(a) * 0.38 * 1.02, z] for a in np.linspace(-2.8, -0.34, 7)]
        folds.extend(tube(pts, [0.035] * 7, n=3, up_hint=(0, 0, 1)))
    m.part("abdomen_fold", folds, "pelican_fold")

    # Короткие надкрылья, раздвинуты в стороны.
    y0 = 0.92
    zs = [0.1, -0.05, -0.35, -0.65, -0.85, -0.95]
    width, height = dome(0.1, -0.95, 0.55, 0.3, z_straight=-0.4)
    left = elytron(zs, width, height, y0, ribs=(0.5,))
    left = rotate_about(left, (0.02, y0 + 0.3, 0.1), (0, 0, 1), -0.32)
    left = rotate_about(left, (0.02, y0 + 0.3, 0.1), (0, 1, 0), 0.22)
    add_elytra(m, left, "pelican_chitin")

    # Перепончатые крылья, сложены назад и чуть приподняты.
    # Имена крыльев без _L/_R: prepare_beetles узнаёт их по ^wing_membrane%d*$ и делит по стороне сам.
    for s, wsuf in ((1, "001"), (-1, "002")):
        f = np.array([s, 1, 1])
        hinge = np.array([0.18, 1.18, -0.05])
        outline = [hinge, [0.75, 1.22, -0.3], [1.15, 1.18, -0.95], [1.05, 1.12, -1.75], [0.6, 1.12, -2.05],
                   [0.25, 1.16, -1.3]]
        outline = [np.asarray(p, float) for p in outline]
        # Крыло приподнято наружу на ~25°.
        outline = [p + np.array([0, (p[0] - 0.18) * 0.45, 0]) for p in outline]
        outline = [p * f for p in outline]
        c = np.mean(outline, axis=0)
        mem = Mesh()
        th = np.array([0, 0.012, 0])
        for i in range(len(outline)):
            a, b = outline[i], outline[(i + 1) % len(outline)]
            if s == 1:
                mem.tri(c + th, a + th, b + th)
                mem.tri(c - th, b - th, a - th)
            else:
                mem.tri(c + th, b + th, a + th)
                mem.tri(c - th, a - th, b - th)
        m.part("wing_membrane" + wsuf, mem, "wing_membrane")
        vein = Mesh()
        for k in (1, 2, 3):
            vein.extend(tube([outline[0] + th, outline[k] + th], [0.025, 0.01], n=3))
        m.part("wing_vein" + wsuf, vein, "wing_vein")

    thorax = loft(section_rings([(-0.02, 0.6, 1.4, 0.52), (0.25, 0.58, 1.42, 0.54), (0.5, 0.45, 1.32, 0.6),
                                 (0.62, 0.32, 1.2, 0.68)], shield)[::-1])
    m.part("ThoraxCore", thorax, "pelican_chitin")
    # Шея вперёд-вверх и воротник шипов у основания.
    m.part("neck", tube([[0, 1.0, 0.5], [0, 1.18, 0.82], [0, 1.28, 1.08]], [(0.26, 0.24), (0.2, 0.19), (0.18, 0.17)],
                        n=7), "pelican_chitin")
    ruff = Mesh()
    for a in np.linspace(0.3, math.pi - 0.3, 6):
        base = np.array([math.cos(a) * 0.28, 1.0 + math.sin(a) * 0.3, 0.58])
        tip = base + np.array([math.cos(a) * 0.18, math.sin(a) * 0.18, -0.16])
        ruff.extend(tube([base, tip], [0.06, 0.008], n=4))
    m.part("neck_ruff", ruff, "neck_ruff")

    add_legs(m, {
        "front": dict(hip=(0.3, 0.6, 0.42), knee=(0.86, 1.02, 0.8), ankle=(1.18, 0.12, 1.15),
                      foot=(1.32, 0.03, 1.42), claw=(0.4, 0, 1)),
        "mid": dict(hip=(0.4, 0.55, 0.0), knee=(1.06, 1.06, 0.02), ankle=(1.42, 0.12, 0.05),
                    foot=(1.64, 0.03, 0.08), claw=(1, 0, 0.1)),
        "rear": dict(hip=(0.44, 0.52, -0.4), knee=(1.0, 1.0, -0.78), ankle=(1.3, 0.12, -1.2),
                     foot=(1.44, 0.03, -1.52), claw=(0.4, 0, -1)),
    }, 0.1, 0.06, "pelican_leg", "pelican_chitin", coxa_r=(0.12, 0.1, 0.12))

    add_head(m, [(1.02, 0.3, 1.5, 1.08), (1.2, 0.32, 1.5, 1.04), (1.36, 0.26, 1.4, 1.06), (1.44, 0.18, 1.3, 1.1)],
             "pelican_chitin", eyes=((0.3, 1.36, 1.24), (0.09, 0.1, 0.1)), eye_mat="milky_eye")
    # Клюв: две длинные жвалы, кончики вниз; зубцы — на жвалах.
    add_mandibles(m, (0.1, 1.16, 1.4), (0.12, 1.08, 1.85), (0.07, 0.95, 2.2), (0.02, 0.8, 2.36), 0.08, "beak",
                  tooth=True, tooth_name="beak_tooth")
    add_antennae(m, [(0.18, 1.45, 1.38), (0.34, 1.65, 1.52), (0.46, 1.74, 1.68), (0.56, 1.76, 1.84)], 0.03,
                 "pelican_chitin")
    return m


# ---------------------------------------------------------------- Моль

def moth():
    """Светлая пушистая моль: толстое полосатое брюшко, мохнатая грудь, перистые усы,
    большие полупрозрачные крылья с тёмной кромкой и пятнами."""
    m = Model()
    m.material("moth_fur", (0.509, 0.456, 0.371), rough=0.9)
    m.material("moth_band", (0.20, 0.16, 0.11), rough=0.9)
    m.material("moth_dark", (0.03, 0.036, 0.028), rough=0.6)
    m.material("moth_leg", (0.06, 0.05, 0.04), rough=0.7)
    m.material("moth_eye", (0.010, 0.010, 0.012), rough=0.15)
    m.material("moth_wing", (0.62, 0.55, 0.42), rough=0.85, alpha=0.7)
    m.material("moth_spot", (0.16, 0.12, 0.08), rough=0.9)

    add_abdomen(m, [(-0.1, 0.32, 1.3, 0.72), (-0.5, 0.36, 1.32, 0.66), (-1.1, 0.33, 1.28, 0.66),
                    (-1.6, 0.24, 1.2, 0.74), (-1.95, 0.1, 1.1, 0.88)], "moth_fur", name="abdomen")
    bands = Mesh()
    for z, w, top, bot in ((-0.45, 0.37, 1.33, 0.65), (-0.85, 0.36, 1.32, 0.65), (-1.25, 0.32, 1.28, 0.67),
                           (-1.6, 0.25, 1.21, 0.73)):
        pts = [[math.cos(a) * w * 1.03, (top + bot) / 2 + math.sin(a) * (top - bot) / 2 * 1.03, z]
               for a in np.linspace(0, 2 * math.pi, 9)]
        bands.extend(tube(pts, [0.035] * 9, n=3, up_hint=(0, 0, 1)))
    m.part("abdomen_band", bands, "moth_band")

    thorax = blob((0, 1.08, 0.25), (0.42, 0.4, 0.5), n=8, rows=5)
    m.part("ThoraxCore", thorax, "moth_fur")
    fur = Mesh()
    for x, y, z, r in ((0.0, 1.45, 0.35, 0.22), (0.22, 1.38, 0.1, 0.18), (-0.22, 1.38, 0.1, 0.18),
                       (0.0, 1.4, -0.05, 0.2), (0.25, 1.3, 0.45, 0.16), (-0.25, 1.3, 0.45, 0.16)):
        fur.extend(blob((x, y, z), (r, r * 0.8, r), n=5, rows=3))
    m.part("thorax_plate", fur, "moth_fur")
    m.part("neck_collar", tube([[0, 1.0, 0.68], [0, 1.0, 0.8]], [(0.3, 0.3), (0.26, 0.26)], n=8), "moth_dark")

    add_legs(m, {
        "front": dict(hip=(0.2, 0.75, 0.45), knee=(0.6, 0.9, 0.75), ankle=(0.85, 0.12, 1.0),
                      foot=(0.95, 0.03, 1.2), claw=(0.4, 0, 1)),
        "mid": dict(hip=(0.26, 0.72, 0.2), knee=(0.75, 0.92, 0.25), ankle=(1.05, 0.12, 0.3),
                    foot=(1.22, 0.03, 0.34), claw=(1, 0, 0.1)),
        "rear": dict(hip=(0.28, 0.7, -0.05), knee=(0.72, 0.9, -0.35), ankle=(0.95, 0.12, -0.68),
                     foot=(1.05, 0.03, -0.92), claw=(0.4, 0, -1)),
    }, 0.075, 0.04, "moth_leg", "moth_fur", coxa_r=(0.08, 0.07, 0.08), tibia_spikes=False)

    palps = Mesh()
    for s in (1, -1):
        palps.extend(tube([[0.08 * s, 0.9, 1.1], [0.1 * s, 1.0, 1.28], [0.08 * s, 1.18, 1.36]], [0.045, 0.04, 0.02],
                          n=4))
    add_head(m, [(0.72, 0.3, 1.3, 0.82), (0.9, 0.32, 1.28, 0.8), (1.06, 0.26, 1.2, 0.84), (1.14, 0.16, 1.1, 0.9)],
             "moth_fur", eyes=((0.3, 1.08, 0.95), (0.14, 0.16, 0.16)), eye_mat="moth_eye",
             extra=[("labial_palp", palps, "moth_fur")])
    # Перистые усы: вверх-вперёд-в стороны, с зубцами-гребнем.
    for s, suf in ((1, "002"), (-1, "003")):
        f = np.array([s, 1, 1])
        pts = [np.array(p) * f for p in [(0.12, 1.3, 1.02), (0.3, 1.6, 1.2), (0.52, 1.82, 1.38), (0.74, 1.95, 1.5),
                                          (0.95, 1.98, 1.58)]]
        for i in range(4):
            a, b = pts[i], pts[i + 1]
            seg = tube([a, b], [0.03, 0.026], n=4)
            for t in (0.3, 0.7):
                p = a + (b - a) * t
                seg.extend(tube([p, p + np.array([0.0, -0.02, 0.16])], [0.012, 0.004], n=3))
                seg.extend(tube([p, p + np.array([0.13 * s, -0.06, 0.06])], [0.012, 0.004], n=3))
            m.part(f"AntSeg{i + 1}{suf}", seg, "moth_fur")
            if i < 3:
                m.part(f"AntNode{i + 1}{suf}", blob(b, (0.035,) * 3, n=5, rows=3), "moth_fur")

    # Крылья: передние и задние, раскрыты, слегка подняты.
    for s, wsuf in ((1, "001"), (-1, "002")):
        f = np.array([s, 1, 1])

        def plate(outline):
            outline = [np.asarray(p, float) for p in outline]
            outline = [p + np.array([0, (p[0] - 0.3) * 0.2, 0]) for p in outline]
            outline = [p * f for p in outline]
            c = np.mean(outline, axis=0)
            mem = Mesh()
            th = np.array([0, 0.01, 0])
            for i in range(len(outline)):
                a, b = outline[i], outline[(i + 1) % len(outline)]
                if s == 1:
                    mem.tri(c + th, a + th, b + th)
                    mem.tri(c - th, b - th, a - th)
                else:
                    mem.tri(c + th, b + th, a + th)
                    mem.tri(c - th, a - th, b - th)
            return mem, outline

        fore, fo = plate([(0.3, 1.32, 0.5), (1.2, 1.55, 0.9), (2.4, 1.75, 0.95), (3.2, 1.85, 0.6),
                          (3.3, 1.82, 0.15), (2.6, 1.68, -0.45), (1.4, 1.5, -0.35), (0.35, 1.3, 0.05)])
        hind, ho = plate([(0.32, 1.28, 0.05), (1.3, 1.42, -0.3), (2.2, 1.5, -0.7), (2.3, 1.48, -1.25),
                          (1.6, 1.38, -1.6), (0.7, 1.3, -1.25), (0.3, 1.26, -0.4)])
        m.part("forewing" + wsuf, fore, "moth_wing")
        m.part("hindwing" + wsuf, hind, "moth_wing")
        th = np.array([0, 0.02, 0])
        costa = tube([fo[0] + th, fo[1] + th, fo[2] + th, fo[3] + th, fo[4] + th], [0.04, 0.035, 0.03, 0.025, 0.02],
                     n=3)
        m.part("wing_costa" + wsuf, costa, "moth_dark")
        spots = Mesh()
        for p, r in (((2.4, 1.73, 0.5), 0.16), ((1.4, 1.55, 0.3), 0.1)):
            p = np.array(p) + np.array([0, (p[0] - 0.3) * 0.2, 0])
            spots.extend(blob(p * f + th, (r, 0.012, r * 0.7), n=6, rows=3))
        m.part("wing_vein_spot" + wsuf, spots, "moth_spot")
    return m


# ---------------------------------------------------------------- Стандарт

def standard():
    """Каста 0 — разведчик: ищет лабораторию. Жук-скакун: голова шире груди, огромные
    выпуклые глаза, узкая «талия» между грудью и надкрыльями, выпуклые надкрылья со светлыми
    пятнами, длинные гладкие лапы бегуна, серпы-жвалы. Цвет в игре даёт BugPalette по касте,
    пятна остаются светлыми."""
    m = Model()
    m.material("std_elytra", (0.16, 0.07, 0.025), rough=0.55)
    m.material("std_chitin", (0.075, 0.032, 0.012), rough=0.6)
    m.material("std_spot", (0.66, 0.57, 0.39), rough=0.6)
    m.material("std_leg", (0.035, 0.016, 0.008), rough=0.6)
    m.material("std_eye", (0.010, 0.010, 0.012), rough=0.15)
    m.material("std_mandible", (0.022, 0.010, 0.005), rough=0.35)
    y0 = 0.62

    add_abdomen(m, [(0.0, 0.42, 0.95, 0.5), (-0.4, 0.58, 1.0, 0.42), (-1.0, 0.6, 0.98, 0.42),
                    (-1.45, 0.45, 0.92, 0.48), (-1.7, 0.2, 0.85, 0.6)], "std_chitin")

    zs = [0.06, -0.08, -0.45, -0.9, -1.3, -1.58, -1.75, -1.82]
    width, height = dome(0.06, -1.82, 0.7, 0.56, z_straight=-0.7, power=2.0)
    add_elytra(m, elytron(zs, width, height, y0, segs=5, ribs=(0.5,)), "std_elytra")
    spots = Mesh()
    for z, u, r in ((-0.3, 0.7, 0.1), (-0.95, 0.45, 0.13), (-1.4, 0.75, 0.09)):
        a = (math.pi / 2) * u
        w, h = width(z), height(z)
        c = np.array([0.012 + (w - 0.012) * math.sin(a), y0 + h * math.cos(a), z])
        normal = np.array([math.sin(a) * h, math.cos(a) * w, 0.0])
        normal /= np.linalg.norm(normal)
        disc = blob((0, 0, 0), (r, 0.035, r * 1.4), n=6, rows=3)
        ax = np.cross([0, 1.0, 0], normal)
        if np.linalg.norm(ax) > 1e-6:
            disc = rotate_about(disc, (0, 0, 0), ax, math.acos(np.clip(normal[1], -1, 1)))
        spots.extend(disc.transformed(lambda p, c=c, n_=normal: p + c + n_ * 0.012))
    m.part("elytra_spot_00", spots, "std_spot")
    m.part("elytra_spot_01", spots.mirrored_x(), "std_spot")

    # Узкая цилиндрическая грудь — «талия» уже головы и надкрылий.
    thorax = loft(section_rings([(0.08, 0.36, 0.98, 0.52), (0.28, 0.42, 1.04, 0.5), (0.5, 0.4, 1.02, 0.52),
                                 (0.66, 0.32, 0.96, 0.56)], shield)[::-1])
    m.part("ThoraxCore", thorax, "std_chitin")

    add_legs(m, {
        "front": dict(hip=(0.24, 0.56, 0.48), knee=(0.78, 0.98, 0.76), ankle=(1.1, 0.12, 1.06),
                      foot=(1.22, 0.03, 1.32), claw=(0.4, 0, 1)),
        "mid": dict(hip=(0.3, 0.52, 0.18), knee=(0.95, 1.02, 0.2), ankle=(1.36, 0.12, 0.24),
                    foot=(1.56, 0.03, 0.28), claw=(1, 0, 0.1)),
        "rear": dict(hip=(0.34, 0.5, -0.1), knee=(0.95, 1.0, -0.5), ankle=(1.26, 0.12, -1.02),
                     foot=(1.38, 0.03, -1.36), claw=(0.4, 0, -1)),
    }, 0.1, 0.06, "std_leg", "std_chitin", coxa_r=(0.11, 0.1, 0.11), tibia_spikes=False)

    add_head(m, [(0.62, 0.42, 1.05, 0.55), (0.82, 0.5, 1.06, 0.52), (1.0, 0.44, 0.98, 0.54), (1.1, 0.3, 0.86, 0.58)],
             "std_chitin", eyes=((0.46, 0.92, 0.84), (0.17, 0.18, 0.19)), eye_mat="std_eye")
    add_mandibles(m, (0.16, 0.62, 1.08), (0.27, 0.6, 1.26), (0.18, 0.59, 1.42), (0.03, 0.58, 1.48), 0.07,
                  "std_mandible")
    add_antennae(m, [(0.28, 1.0, 1.0), (0.44, 1.18, 1.18), (0.58, 1.26, 1.38), (0.68, 1.26, 1.58), (0.74, 1.2, 1.76)],
                 0.032, "std_chitin")
    return m

SPECIES = {
    "standard_beetle": standard,
    "worker_beetle": worker,
    "mini_beetle": mini,
    "builder_beetle": builder,
    "hmuryi_bron": armored,
    "pelican_beetle": pelican,
    "moth": moth,
}
