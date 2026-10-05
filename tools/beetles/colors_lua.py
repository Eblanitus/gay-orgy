"""Печатает таблицу COLORS для tools/prepare_beetles.luau из моделей species.py
(Import 3D теряет цвета материалов — prepare_beetles красит детали по имени)."""
import re

from species import SPECIES as SPECIES1
from species2 import SPECIES2

SPECIES = {**SPECIES1, **SPECIES2}

TEMPLATES = {"standard_beetle": "NormalBeetleTemplate", "mini_beetle": "MiniBeetleTemplate", "hmuryi_bron": "ArmoredBeetleTemplate",
             "moth": "MothTemplate", "worker_beetle": "WorkerBeetleTemplate",
             "builder_beetle": "BuilderBeetleTemplate", "pelican_beetle": "PelicanBeetleTemplate",
             "acid_spitter": "AcidSpitterTemplate",
             "medic": "MedicTemplate",
             "queen": "QueenTemplate",
             "larva": "LarvaTemplate",
             "bomber": "BomberTemplate",
             "shield_bearer": "ShieldBearerTemplate",
             "coordinator": "CoordinatorTemplate",
             "ram": "RamTemplate",
             "sprinter": "SprinterTemplate",
             "giant": "GiantTemplate",
             "knitter": "KnitterTemplate",
             "facehugger": "FacehuggerTemplate",
             "absorber": "AbsorberTemplate",
             "evolver": "EvolverTemplate",
             "carrier": "CarrierTemplate",
             "puppeteer": "PuppeteerTemplate",
             "hive_architect": "HiveArchitectTemplate",
             "mimic": "MimicTemplate",
             "shadow": "ShadowTemplate",}


def key(name):
    k = re.sub(r"\d{3}$", "", name)  # как baseName в prepare_beetles
    k = re.sub(r"_?[-\d]+$", "", k)
    return re.sub(r"_[LR]$", "", k)


def lua():
    out = ["local COLORS = {"]
    for src, fn in SPECIES.items():
        m = fn()
        groups = {}
        seen = {}
        for n in m.nodes:
            if n["mesh"] is None:
                continue
            k = key(n["name"])
            mat = m.materials[n["mat"]]
            if k in seen and seen[k] != mat[0]:
                raise SystemExit(f"{src}: {k} — два материала: {seen[k]} и {mat[0]}")
            seen[k] = mat[0]
            groups.setdefault(mat[0], (mat, []))
            if k not in groups[mat[0]][1]:
                groups[mat[0]][1].append(k)
        out.append(f"\t{TEMPLATES[src]} = {{")
        for (name, rgb, rough, metal, alpha), keys in groups.values():
            vals = ", ".join(f"{c:.3f}".rstrip("0").rstrip(".") for c in rgb)
            names = ", ".join(f'"{k}"' for k in keys)
            tail = f", alpha = {alpha}" if alpha < 1 else ""
            out.append(f"\t\t{{ {vals}, {names}{tail} }},")
        out.append("\t},")
    out.append("}")
    return "\n".join(out)




def lengths():
    """Длина для SPECS в prepare_beetles: перед HeadBase − зад брюшка (как меряет prepare_beetles)."""
    out = []
    for src, fn in SPECIES.items():
        m = fn()
        z = {}
        for n in m.nodes:
            if n["mesh"] is not None:
                zs = [p[2] for t in n["mesh"].v for p in t]
                z[re.sub(r"\d{3}$", "", n["name"])] = (min(zs), max(zs))
        rear = (z.get("BeetleBodyInner") or z["abdomen"])[0]
        if "BeetlePlate_05" in z:
            rear = min(rear, z["BeetlePlate_05"][0])
        out.append(f'{TEMPLATES[src]}: length = {z["HeadBase"][1] - rear:.2f}')
    return "\n".join(out)


if __name__ == "__main__":
    import sys
    print(lengths() if "--lengths" in sys.argv else lua())
