"""Пересобирает все .glb жуков: python3 tools/beetles/build_all.py [папка]  (по умолчанию «Модели/Жуки»)."""
import os
import sys

from beetlegen import merge
from species import SPECIES as SPECIES1
from species2 import SPECIES2

SPECIES = {**SPECIES1, **SPECIES2}

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "Модели", "Жуки")
for name, fn in SPECIES.items():
    model = fn()
    # Корень назван видом: Import 3D отдаёт его имя модели, prepare_beetles находит импорт сам.
    model.nodes[model.root]["name"] = name
    path = os.path.join(out_dir, name + ".glb")
    model.save(path)
    parts = sum(1 for n in model.nodes if n["mesh"] is not None)
    print(f"{name}: {model.tris()} треугольников, {parts} деталей")

# Все виды одним файлом: один Import 3D вместо двадцати шести (prepare_beetles находит виды по имени).
models = []
for name, fn in SPECIES.items():
    model = fn()
    model.nodes[model.root]["name"] = name
    models.append(model)
merge(models).save(os.path.join(out_dir, "all_beetles.glb"))
print("all_beetles.glb: все виды одним файлом")
