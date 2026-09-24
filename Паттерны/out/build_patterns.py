# Adapts source patterns to the in-game style (white mask, alpha levels):
#   line = 1.0, lit field = FILL, dark objects = 0.
# Modes:
#   line  - drawn lines (dark or light) on a flat field: lines -> 1, field -> FILL
#   shape - two-tone shapes: shape interior -> 0, field -> FILL, contour -> 1
#   photo - luminance posterized: bright -> 1, mid -> FILL, dark -> 0
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as nd

Image.MAX_IMAGE_PIXELS = None
SRC = r"C:\Users\user\Contacts\Паттерны"
OUT = os.path.join(SRC, "out")
SCR = r"C:\Users\user\AppData\Local\Temp\claude\C--Users-user-Contacts\9acaadbd-6b0d-44c0-b826-383390d4baa1\scratchpad"
FILL = 0.55
DARK = 0  # line mode: field farther than this (px on the 1024 canvas) from a line goes dark; 0 = off

# key: (file, mode, options)
CFG = {
    "Ocean": ("ocean pattern.jpg", "line", dict(light=True, pct=82, blur=1.2, scale=0.7)),
    "Rain": ("patter дождь.png", "line", dict(light=True, pct=88, blur=0.8, scale=1.3)),
    "Flare": ("pattern flare.png", "bokeh", dict(pct=97, ring=3, blur=1, sigmas=(28, 18, 11, 7), scale=0.8)),
    "Water": ("water pattern rework.png", "photo", dict(hi=94, lo=22, blur=0.5)),
    "Wind": ("Ветер паттерн.png", "line", dict(light=True, pct=70, blur=1.0)),
    "Earth": ("Земля паттерн.jpg", "line", dict(light=False, pct=18, blur=1.5)),
    "Puddle": ("Лужа паттерн 2.png", "shape", dict(light=False, pct=70, ring=3.5, blur=2, crop=(0.02, 0.02, 0.98, 0.98), scale=1.95)),
    "Pond": ("пруд паттерн.jpg", "line", dict(light=False, pct=34, blur=1.5)),
    "Lightning": ("паттерн молния новый.png", "line", dict(light=True, pct=90, blur=1.0, trunk=True)),
    "Cloud": ("Облако паттерн.png", "line", dict(light=False, pct=14, blur=1.0, crop=(0.01, 0.01, 0.99, 0.99))),
    "Steam": ("Пар паттерн.png", "line", dict(light=False, pct=16, blur=1.5, scale=0.55)),
    "Air": ("Паттерн воздух.png", "shape", dict(light=True, pct=60, ring=3.5, blur=2, scale=0.8)),
    "Soil": ("Паттерн грунт.webp", "line", dict(light=False, pct=14, blur=0.8)),
    "Pressure": ("Давление реворк.png", "line", dict(light=True, pct=72, blur=1.0, scale=1.5, sea=5, sea_area=300, ring=2.5)),
    "Continent": ("Континент реворк.png", "line", dict(light=True, pct=80, blur=1.2, sea=6, ring=3, scale=1.5, shadow=70)),
    "Land": ("Суша реворк.png", "line", dict(light=True, pct=75, blur=1.2, scale=2, sea=4, sea_area=200, ring=2.5)),
    "Hurricane": ("Ураган паттерн.jpg", "shape", dict(light=True, pct=50, ring=3.5, blur=1.5)),
    "Energy": ("Энергия паттерн.png", "shape", dict(light=True, pct=50, ring=3.5, blur=1, scale=1.08, crop=(0.01, 0.01, 0.99, 0.99))),
    "Electricity": ("ПАттерн электричество новый.png", "line", dict(light=True, pct=85, blur=0.8, scale=1.5)),
    "Mist": ("Туман реворк.png", "shape", dict(light=False, pct=62, ring=2.5, blur=1.2)),
    "Smoke": ("Паттерн дым.png", "line", dict(light=True, pct=80, blur=1.5, hp=8)),
    "Sand": ("Паттерн песок.png", "line", dict(light=True, pct=80, blur=1.2)),
    "Dust": ("Паттерн пыль.png", "shape", dict(light=False, pct=35, ring=3, blur=4)),
    "Lava": ("ПАттерн лава.png", "line", dict(light=True, pct=72, blur=1.2)),
    "Volcano": ("Паттерн вулкан.png", "line", dict(light=True, pct=90, blur=1.5, scale=1.3)),
    "Eruption": ("паттерн извержение.png", "shape", dict(light=True, pct=72, ring=2.5, blur=2.5, no_open=True)),
    "Gunpowder": ("паттерн порох.png", "line", dict(light=True, pct=88, blur=1.0, scale=1.6)),
    "Stone": ("stone pattern.png", "line", dict(light=False, pct=22, blur=1.2)),
    "Obsidian": ("Обсидиан реворк.png", "shape", dict(light=False, pct=30, ring=2.5, blur=1.2)),
    "Clay": ("clay pattern.png", "line", dict(light=False, pct=28, blur=1.2)),
    "Mud": ("mud pattern.png", "shape", dict(light=False, pct=55, ring=3, blur=2)),
    "Oxygen": ("oxygen pattern.png", "shape", dict(light=True, pct=85, ring=2.5, blur=1.2, invert=True)),
    "Swamp": ("swamp pattern.png", "line", dict(light=True, pct=68, blur=1.5)),
    "Life": ("life pattern.png", "shape", dict(light=True, pct=55, ring=3, blur=1.5)),
    "Plant": ("plant pattern.png", "line", dict(light=True, pct=72, blur=1.2)),
    "Tree": ("wood pattern.png", "line", dict(light=False, pct=28, blur=1.2)),
    "Island": ("Остров паттерн.png", "shape", dict(light=True, pct=72, ring=3, blur=1.5)),
    "Metal": ("Метаалл паттерн.png", "line", dict(light=True, pct=88, blur=1.0)),
    "Coal": ("Уголь паттерн реворк.jpg", "photo", dict(hi=90, lo=40, blur=0.6)),
    "Diamond": ("Алмаз паттерн реворк.png", "line", dict(light=True, pct=85, blur=1.0)),
    "Smog": ("Смог паттерн реворк.png", "shape", dict(light=False, pct=55, ring=2.5, blur=1.2)),
    "Explosion": ("взрыв паттерн.png", "shape", dict(light=False, pct=62, ring=2.5, blur=1.5)),
    "Earthquake": ("Землетрясение паттерн Реворк.png", "photo", dict(hi=92, lo=12, blur=1.0, shadow=70)),
    "Sound": ("Звук реворк.png", "line", dict(light=True, pct=80, blur=1.0)),
    "Ash": ("Пепел паттерн.png", "shape", dict(light=False, pct=60, ring=2.5, blur=1.5, crop=(0.0, 0.25, 1.0, 0.7), scale=1.8)),
    "Rust": ("Ржавчина паттерн реворк.png", "shape", dict(light=False, pct=65, ring=2.5, blur=1.2)),
    "Antimatter": ("АнтиМатерия Паттерн реворк.png", "line", dict(light=True, pct=86, blur=1.0, scale=2.13)),
    "Poison": ("Яд паттерн.png", "shape", dict(light=False, pct=50, ring=3, blur=1.5)),
    "Frost": ("Иней паттерн.png", "line", dict(light=True, pct=78, blur=2.0, scale=3)),
    "BrickWall": ("Кирпичная стена паттерн.png", "line", dict(light=False, pct=30, blur=1.5, scale=1.9)),
    "Brick": ("Кирпичная стена паттерн.png", "line", dict(light=False, pct=30, blur=3.0, crop=(0.05, 0.05, 0.33, 0.33), scale=6.6)),
    "Blizzard": ("Метель паттерн.png", "line", dict(light=True, pct=82, blur=1.0)),
    "AcidRain": ("Кислотный дождь реворк.png", "line", dict(light=True, pct=84, blur=1.0)),
    "Cold": ("Холод паттерн.png", "line", dict(light=True, pct=84, blur=1.0)),
    "Acid": ("Кислота паттерн.png", "line", dict(light=True, pct=80, blur=1.0)),
    "Soap": ("Мыло паттерн.png", "line", dict(light=True, pct=84, blur=1.0)),
    "Plasma": ("Плазма паттерн.png", "shape", dict(light=False, pct=68, ring=2.5, blur=1.0)),
    "Drought": ("Засуха паттерн.png", "shape", dict(light=False, pct=75, ring=2.5, blur=1.0, crop=(0.0, 0.07, 1.0, 0.45), scale=2.0)),
    "Tornado": ("Паттерн торнадо.png", "shape", dict(light=False, pct=50, ring=2.5, blur=1.0, scale=1.6)),
    "Ice": ("Лед реворк паттерн.png", "line", dict(light=False, pct=12, blur=1.0, scale=1.4)),
    "Glass": ("Стекло паттерн реворк.png", "line", dict(light=False, pct=14, blur=1.0, scale=1.3)),
    "Mountain": ("Гора паттерн.png", "line", dict(light=True, pct=82, blur=1.0)),
    "Snow": ("Снег паттерн.png", "line", dict(light=True, pct=93, blur=1.2, scale=1.3)),
    "Steel": ("сталь паттрен.png", "line", dict(light=True, pct=80, blur=1.0, hp=10, crop=(0.12, 0.1, 0.88, 0.8), scale=2.82)),
    "Geyser": ("Гейзер паттерн.jpg", "photo", dict(hi=93, lo=45, blur=0.8)),
}

# Per-pattern dark distance for approved patterns (about a third dark like Fire); others keep a flat field.
DARK_BY = dict(Pond=5, Lightning=10, Diamond=5, Glass=5, Mountain=5, Cold=5, Plant=8, Cloud=8, Wind=5, Brick=16, Acid=5, Steam=13, Tree=5)

# Line patterns with a uniformly dark field, and ones whose dark areas follow the source tones (author picks).
FLAT_FILL = 0.2
FLAT = {"Ocean", "Rain", "Soil", "Electricity", "Gunpowder", "Stone", "Clay", "Metal", "Sound", "Frost", "Soap", "Ice"}
TONE = {"Earth", "Sand", "Lava", "Volcano", "Swamp", "Antimatter", "Blizzard", "AcidRain", "Snow", "Steel"}


def load(name, crop=None, scale=1):
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    bg.alpha_composite(im)
    im = bg.convert("L")
    if crop:
        w, h = im.size
        im = im.crop((int(crop[0] * w), int(crop[1] * h), int(crop[2] * w), int(crop[3] * h)))
    im.thumbnail((1024, 1024), Image.LANCZOS)
    if scale != 1:
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    # Tile to a full 1024 canvas so every pattern renders at the same texel density as Fire.
    a = np.array(im).astype(float) / 255
    return np.tile(a, (-(-1024 // a.shape[0]), -(-1024 // a.shape[1])))[:1024, :1024]


def build(key):
    name, mode, o = CFG[key]
    g = load(name, o.get("crop"), o.get("scale", 1))
    g = nd.gaussian_filter(g, o.get("blur", 1))
    if o.get("hp"):
        g = g - nd.gaussian_filter(g, o["hp"])
    if mode == "line":
        v = g if o["light"] else 1 - g
        t = np.percentile(v, o["pct"] if o["light"] else 100 - o["pct"])
        line = np.clip((v - t) / 0.04 + 0.5, 0, 1)
        out = np.maximum(line, FILL)
        if key in FLAT:
            out = np.maximum(line, FLAT_FILL)
        elif key in TONE:
            # Dark areas of the source picture become dark, lit ones keep the field.
            tone = nd.gaussian_filter(v, 6)
            lo, hi = np.percentile(tone, 30), np.percentile(tone, 65)
            out = np.maximum(line, FILL * np.clip((tone - lo) / (hi - lo), 0, 1))
        dark = o.get("dark", DARK_BY.get(key, DARK))
        if dark and not o.get("sea"):
            # Field far from lines fades to dark, leaving a lit halo around them (three tones like Fire).
            dist = nd.distance_transform_edt(line < 0.5)
            fade = np.clip((dist - dark) / 6, 0, 1)
            field = FILL * (1 - fade)
            if o.get("trunk"):
                # Thick strokes stay full, thin branches and the halo are quieter.
                thick = nd.grey_dilation(nd.distance_transform_edt(line >= 0.5), size=7)
                core = np.clip((thick - 1.5) / 2.5, 0, 1)
                out = np.where(line >= 0.5, line * (0.7 + 0.3 * core), np.maximum(line * 0.7, field * 0.3 / FILL))
            else:
                out = np.where(line >= 0.5, out, np.maximum(line, field))
        if o.get("sea"):
            # Areas with no lines (gaps between plates) become dark objects.
            far = nd.distance_transform_edt(line < 0.5) > o["sea"]
            lab, n = nd.label(far)
            areas = nd.sum(far, lab, range(1, n + 1))
            far = np.isin(lab, 1 + np.nonzero(areas > o.get("sea_area", 1500))[0])
            sea = nd.binary_dilation(far, iterations=o["sea"])
            d = np.where(sea, nd.distance_transform_edt(sea), nd.distance_transform_edt(~sea))
            out = np.where(sea, np.clip(o.get("ring", 3) - d, 0, 1), out)
    elif mode == "shape":
        v = g if o["light"] else 1 - g
        t = np.percentile(v, o["pct"])
        inside = v > t
        if not o.get("no_open"):
            inside = nd.binary_opening(inside, iterations=1)
        d = np.where(inside, nd.distance_transform_edt(inside), nd.distance_transform_edt(~inside))
        ring = np.clip(o["ring"] - d, 0, 1)
        # invert: shapes become the lit field on a dark background.
        out = np.maximum(ring, np.where(inside, FILL, 0) if o.get("invert") else np.where(inside, 0, FILL))
    elif mode == "bokeh":
        # Bokeh: bright blobs found at several scales become outlined dark discs.
        yy, xx = np.mgrid[:g.shape[0], :g.shape[1]]
        inside = np.zeros(g.shape, bool)
        for sig in [x * o.get("scale", 1) for x in o["sigmas"]]:
            dog = nd.gaussian_filter(g, sig) - nd.gaussian_filter(g, sig * 1.6)
            peak = (dog == nd.maximum_filter(dog, size=int(sig * 3))) & (dog > np.percentile(dog, o["pct"]))
            for y, x in zip(*np.nonzero(peak)):
                r = sig * 2.0
                if inside[y, x]:
                    continue
                inside |= (yy - y) ** 2 + (xx - x) ** 2 < r * r
        d = np.where(inside, nd.distance_transform_edt(inside), nd.distance_transform_edt(~inside))
        ring = np.clip(o["ring"] - d, 0, 1)
        out = np.maximum(ring, np.where(inside, 0, FILL))
    else:
        hi, lo = np.percentile(g, o["hi"]), np.percentile(g, o["lo"])
        a = np.clip((g - hi) / 0.03 + 0.5, 0, 1)
        b = np.clip((g - lo) / 0.03 + 0.5, 0, 1) * FILL
        out = np.maximum(a, b)
    if o.get("shadow"):
        # Dark areas creep into the field as a soft shadow; lines stay.
        f = np.clip(nd.distance_transform_edt(out >= 0.15) / o["shadow"], 0, 1) ** 0.6
        out = np.where(out > 0.7, out, np.minimum(out, FILL * f))
    img = np.zeros((*out.shape, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (np.clip(out, 0, 1) * 255).round()
    path = os.path.join(OUT, f"p_{key}.png")
    Image.fromarray(img).save(path)
    return Image.fromarray(img)


def card(mask, color, w=335, h=110):
    # Same fit as UITheme at a 670x220 card, rendered at half size.
    want = max(2.5, 230 / 220)
    rw, rh = 670 * want, 220 * want
    k = min(1, mask.width / rw, mask.height / rh)
    crop = mask.crop((0, 0, int(rw * k), int(rh * k))).resize((w, h), Image.LANCZOS)
    a = np.array(crop)[..., 3].astype(float) / 255 * 0.55
    base = np.array(color, float) * 0.1
    rgb = base * (1 - a[..., None]) + np.array(color, float) * a[..., None]
    return Image.fromarray(rgb.astype(np.uint8))


def preview(key, mask, color):
    # Craft slot 576x180 at density 2.5 and inventory row 340x34 with minRect 230 (Fire defaults).
    body = tuple(int(c * 0.1) for c in color)
    tiles = []
    for w, h, want in ((576, 180, 2.5), (340, 34, 230 / 34)):
        rw, rh = w * want, h * want
        k = min(1, mask.width / rw, mask.height / rh)
        rw, rh = rw * k, rh * k
        crop = mask.crop((0, 0, int(rw), int(rh))).resize((w, h), Image.LANCZOS)
        a = np.array(crop)[..., 3].astype(float) / 255 * 0.55
        base = np.array(body, float)
        rgb = base * (1 - a[..., None]) + np.array(color, float) * a[..., None]
        tiles.append(Image.fromarray(rgb.astype(np.uint8)))
    return tiles


# Current Elements colors with UITheme.PatternTint applied (V < 0.5 -> lerp 0.55 to white).
COLORS = dict(Fire=(255, 140, 0), Water=(40, 110, 255), Earth=(139, 90, 43), Air=(255, 255, 255),
              Energy=(255, 215, 40), Puddle=(110, 140, 155), Soil=(194, 188, 174), Pressure=(170, 160, 215),
              Steam=(215, 225, 235), Lava=(230, 85, 20), Smoke=(188, 188, 190), Mud=(183, 172, 160),
              Mist=(200, 215, 225), Dust=(180, 165, 140), Flare=(255, 228, 150), Land=(150, 130, 90),
              Cloud=(225, 232, 240), Smog=(140, 135, 70), Swamp=(174, 183, 165), Plant=(95, 175, 70),
              Stone=(130, 130, 130), Earthquake=(194, 191, 187), Volcano=(150, 55, 30), Geyser=(140, 190, 210),
              Wind=(215, 235, 240), Heat=(225, 62, 40), Obsidian=(156, 154, 158), Cold=(160, 210, 240),
              Acid=(150, 220, 60), Gunpowder=(172, 172, 174), Brick=(170, 80, 60), Pond=(60, 120, 160),
              Continent=(140, 125, 90), Lightning=(70, 55, 170), Ocean=(0, 165, 155), Hurricane=(100, 140, 165),
              Tree=(70, 130, 60), Oxygen=(180, 230, 255), Ash=(194, 192, 190), Coal=(165, 163, 163),
              Life=(255, 55, 115), Poison=(100, 255, 20), Rust=(160, 85, 45), Rain=(90, 140, 190),
              Snow=(235, 245, 255), Frost=(200, 230, 245), AcidRain=(160, 200, 90), Drought=(215, 170, 80),
              Blizzard=(215, 235, 250), Metal=(175, 180, 190), Sand=(225, 205, 150), Explosion=(255, 120, 40),
              Plasma=(140, 70, 200), Tornado=(150, 165, 180), Eruption=(200, 70, 25), Ice=(90, 200, 255),
              Clay=(160, 110, 85), Mountain=(190, 192, 194), BrickWall=(192, 167, 163), Star=(255, 250, 210),
              Lithosphere=(150, 75, 45), Hydrosphere=(30, 100, 190), Atmosphere=(110, 170, 240),
              Island=(90, 160, 120), Sound=(150, 120, 255), Soap=(240, 190, 230), Diamond=(190, 240, 250),
              Steel=(105, 125, 155), Antimatter=(156, 149, 167), Glass=(210, 240, 245), Electricity=(120, 200, 255))

if __name__ == "__main__":
    keys = sys.argv[1:] or list(CFG)
    cells = [("Fire", Image.open(os.path.join(OUT, "fire_inv_1024.png")), (255, 140, 0))]
    for key in keys:
        cells.append((key, build(key), COLORS[key]))
    cols = 3
    rows = -(-len(cells) // cols)
    sheet = Image.new("RGB", (cols * 345, rows * 130), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    for i, (key, m, c) in enumerate(cells):
        x, y = (i % cols) * 345, (i // cols) * 130
        sheet.paste(card(m, c), (x, y))
        d.text((x + 4, y + 112), key, fill=(255, 255, 0))
    sheet.save(os.path.join(SCR, "patterns_preview.png"))
    print("ok", keys)
