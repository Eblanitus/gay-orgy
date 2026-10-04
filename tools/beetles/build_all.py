"""Пересобирает все .glb жуков: python3 tools/beetles/build_all.py [папка]  (по умолчанию «Модели/Жуки»)."""
import os
import sys

from species import SPECIES

out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "Модели", "Жуки")
for name, fn in SPECIES.items():
    model = fn()
    # Корень назван видом: Import 3D отдаёт его имя модели, prepare_beetles находит импорт сам.
    model.nodes[model.root]["name"] = name
    path = os.path.join(out_dir, name + ".glb")
    model.save(path)
    parts = sum(1 for n in model.nodes if n["mesh"] is not None)
    print(f"{name}: {model.tris()} треугольников, {parts} деталей")
