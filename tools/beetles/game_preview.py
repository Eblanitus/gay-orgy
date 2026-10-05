"""Превью жуков в игровых цветах: перекраска как в EnemyModel.FromTemplate (роль детали по имени)
с цветами BugPalette.Paint по касте и тону из Enemies.luau. python3 game_preview.py <папка>"""
import os
import re
import sys

from species import SPECIES
from species2 import SPECIES2

SPECIES = {**SPECIES, **SPECIES2}

HEX = {"olive": "#66703F", "ochre": "#9A7238", "brick": "#8C3B2A", "plum": "#5B3F63", "bone": "#D3C7A6",
       "tar": "#2A2522"}
BY_CASTE = {0: "olive", 1: "ochre", 2: "brick", 3: "plum"}
# Каста / семейство и тон — из src/ReplicatedStorage/Enemies.luau.
ENEMY = {"standard_beetle": (0, None, 0), "worker_beetle": (1, None, 0), "mini_beetle": (0, None, 0.45),
         "hmuryi_bron": (0, None, -0.6), "moth": (0, "bone", 0), "builder_beetle": (1, None, -0.4),
         "pelican_beetle": (1, None, 0.15),
         "acid_spitter": (1, None, 0), "medic": (1, None, 0.25), "queen": (1, None, -0.2), "larva": (1, "bone", 0),
         "bomber": (2, None, 0), "shield_bearer": (2, None, -0.3), "coordinator": (2, None, 0.15),
         "ram": (2, None, -0.5), "sprinter": (2, None, 0.4), "giant": (2, None, -0.7), "knitter": (2, None, 0.1),
         "facehugger": (3, None, 0.3), "absorber": (3, None, 0), "evolver": (3, None, 0), "carrier": (3, None, -0.4),
         "puppeteer": (3, None, 0.2), "hive_architect": (3, None, -0.3), "mimic": (3, "bone", -0.3),
         "shadow": (3, "tar", 0)}
ROLE = [("^BeetlePlate", "elytra"), ("^BeetleSternite", "chitin"), ("^BeetleBodyInner", "chitin"),
        ("^AbdomenCore", "chitin"), ("^ThoraxCore", "chitin"), ("^BeetleNeck", "chitin"), ("^ROOT", "joints"),
        ("^thorax", "chitin"), ("^neck$", "chitin"), ("^HeadBase", "head"), ("^AntNode", "head"),
        ("^AntSeg", "head"), ("^Mandible", "head"), ("^Tooth", "head"), ("^cheek", "head"), ("^shovel", "head"),
        ("^labial_palp", "head"), ("^Femur", "head"), ("^KneeJoint", "head"), ("^AnkleJoint", "head"),
        ("^Tibia", "joints"), ("^Tarsus", "joints")]


def rgb(h):
    return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def lerp(a, b, t):
    return [x + (y - x) * t for x, y in zip(a, b)]


def lin(c):
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def palette(src):
    caste, family, tone = ENEMY[src]
    base = rgb(HEX[family or BY_CASTE[caste]])
    shell = lerp(base, rgb(HEX["bone"]), tone * 0.4) if tone >= 0 else lerp(base, rgb(HEX["tar"]), -tone * 0.5)
    tar = rgb(HEX["tar"])
    return {"chitin": shell, "elytra": lerp(shell, tar, 0.12), "head": lerp(shell, tar, 0.32),
            "joints": lerp(tar, shell, 0.18)}


def painted(src):
    m = SPECIES[src]()
    pal = palette(src)
    made = {}
    for n in m.nodes:
        if n["mesh"] is None:
            continue
        name = re.sub(r"\d{3}$", "", n["name"])
        if name == "BeetleBodyInner" or name == "abdomen":
            name = "AbdomenCore"
        role = next((r for pat, r in ROLE if re.match(pat, name)), None)
        if role:
            if role not in made:
                m.material("game_" + role, tuple(lin(pal[role])), rough=0.75)
                made[role] = m.mat_index["game_" + role]
            n["mat"] = made[role]
    return m


if __name__ == "__main__":
    out = sys.argv[1]
    for src in SPECIES:
        painted(src).save(os.path.join(out, src + ".glb"))
        print(src)
