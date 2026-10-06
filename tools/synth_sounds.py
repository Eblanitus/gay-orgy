"""Синтез звуков игры в «Звуки/*.wav» — черновой набор, собранный кодом, а не записанный.

    python3 tools/synth_sounds.py            # все звуки
    python3 tools/synth_sounds.py Boom Splat # только эти

Нужны numpy и scipy. Каждый звук — функция ниже, имя функции = имя файла = ключ в
ReplicatedStorage.SoundBank. Случайность с фиксированным зерном: повторный запуск даёт
те же файлы, и upload_sounds.py не грузит их второй раз.

Захочется заменить звук настоящим — положить свой файл с тем же именем в «Звуки/»
(.wav/.ogg/.mp3) и запустить upload_sounds.py; этот скрипт тогда этот звук не трогать
(передавать имена явно).
"""

import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Звуки"
SR = 44100


# ---------- примитивы ----------

def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def noise(seconds, rng):
    return rng.uniform(-1, 1, int(seconds * SR))


def lp(x, hz, order=2):
    return sosfilt(butter(order, min(hz, SR * 0.45), "low", fs=SR, output="sos"), x)


def hp(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos"), x)


def env_exp(seconds, decay, attack=0.002):
    t = t_axis(seconds)
    e = np.exp(-t / decay)
    a = np.minimum(t / attack, 1.0) if attack > 0 else 1.0
    return e * a


def sweep(seconds, f0, f1, shape="exp"):
    """Синус со скольжением частоты f0 -> f1."""
    t = t_axis(seconds)
    if shape == "exp":
        f = f0 * (f1 / f0) ** (t / seconds)
    else:
        f = f0 + (f1 - f0) * t / seconds
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def saw(freq, seconds):
    t = t_axis(seconds)
    return 2 * ((t * freq) % 1.0) - 1


def pad(x, seconds):
    n = int(seconds * SR)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    dst[i:j] += src[: j - i]


def fade(x, fin=0.002, fout=0.02):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def loopable(x, overlap):
    """Склеить конец с началом: хвост длиной overlap подмешивается к началу с кроссфейдом."""
    n = int(overlap * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0, 1, n)
    joined = tail * (1 - ramp) + head * ramp
    return np.concatenate([joined, body])


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def softclip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def crunch(rng, seconds=0.12, bright=3500):
    """Хруст хитина: пачка коротких щелчков с убывающей плотностью."""
    x = np.zeros(int(seconds * SR))
    clicks = rng.integers(14, 26)
    for _ in range(clicks):
        at = rng.random() ** 1.8 * seconds * 0.8
        c = noise(0.004, rng) * env_exp(0.004, 0.0012) * rng.uniform(0.3, 1.0)
        place(x, c, at)
    return bp(x, 600, bright)


# ---------- бой ----------

def ShotFlask(rng):
    # Колба: пневмохлопок и звон стекла.
    d = 0.4
    pop = lp(noise(d, rng), 1800) * env_exp(d, 0.025) * 1.2
    thump = sweep(d, 220, 70) * env_exp(d, 0.05)
    glass = sum(np.sin(2 * np.pi * f * t_axis(d)) * rng.uniform(0.2, 0.4) for f in (2350, 3110, 4720))
    glass = glass * env_exp(d, 0.08) * 0.35
    return fade(pop + thump + glass)


def ShotInjector(rng):
    # Инжектор: резкий выдох сжатого воздуха и щелчок поршня.
    d = 0.32
    hiss = bp(noise(d, rng), 2500, 9000) * env_exp(d, 0.06, 0.004)
    click = hp(noise(0.006, rng), 3000) * 1.5
    x = hiss + 0.4 * sweep(d, 900, 300) * env_exp(d, 0.03)
    place(x, click, 0)
    return fade(x)


def DroneLaunch(rng):
    # Станция дронов: лязг люка и уходящий вверх жужжащий моторчик.
    d = 0.9
    clank = sum(np.sin(2 * np.pi * f * t_axis(0.3)) for f in (410, 655, 1180)) * env_exp(0.3, 0.06)
    x = np.zeros(int(d * SR))
    place(x, clank * 0.5 + hp(noise(0.3, rng), 1500) * env_exp(0.3, 0.01), 0)
    t = t_axis(0.75)
    f = 140 + 260 * t / 0.75
    motor = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.25
    motor = lp(motor, 2500) * np.minimum(t / 0.1, 1) * np.exp(-t / 0.4)
    place(x, motor, 0.12)
    return fade(x)


def Boom(rng):
    # Огненный взрыв: удар, рёв и осыпающийся хвост.
    d = 1.8
    body = lp(noise(d, rng), 900, 4) * env_exp(d, 0.35, 0.004) * 1.6
    thump = sweep(d, 110, 35) * env_exp(d, 0.22) * 1.4
    crack = hp(noise(0.05, rng), 2000) * env_exp(0.05, 0.012)
    debris = np.zeros(int(d * SR))
    for _ in range(18):
        place(debris, hp(noise(0.01, rng), 2500) * env_exp(0.01, 0.003) * rng.uniform(0.05, 0.25),
              0.15 + rng.random() * 1.2)
    x = softclip(body + thump + debris, 1.8)
    place(x, crack, 0)
    return fade(x, 0.001, 0.2)


def DroneBoom(rng):
    # Подрыв дрона: короткий сухой хлопок с металлом.
    d = 0.9
    body = lp(noise(d, rng), 2200) * env_exp(d, 0.12, 0.002) * 1.3
    thump = sweep(d, 160, 50) * env_exp(d, 0.1)
    ring = np.sin(2 * np.pi * 1730 * t_axis(d)) * env_exp(d, 0.15) * 0.12
    return fade(softclip(body + thump + ring, 2.0), 0.001, 0.1)


def Quake(rng):
    # Земля, разлом: низкий гул и треск породы.
    d = 2.2
    rumble = lp(noise(d, rng), 140, 4) * 4.0
    t = t_axis(d)
    shape = np.minimum(t / 0.08, 1) * np.exp(-t / 0.8)
    x = rumble * shape + sweep(d, 55, 30) * shape * 0.8
    for _ in range(10):
        place(x, crunch(rng, 0.15, 2500) * 2.0, rng.random() * 1.3)
    return fade(softclip(x, 1.4), 0.002, 0.3)


def Splash(rng):
    # Вода, облако, снег: всплеск и шипение.
    d = 1.3
    x = bp(noise(d, rng), 400, 6000) * env_exp(d, 0.25, 0.01)
    for _ in range(25):
        drop = np.sin(2 * np.pi * rng.uniform(900, 2400) * t_axis(0.03)) * env_exp(0.03, 0.008)
        place(x, drop * rng.uniform(0.1, 0.35), 0.05 + rng.random() * 0.8)
    x += lp(noise(d, rng), 300) * env_exp(d, 0.08) * 1.2
    return fade(x, 0.003, 0.2)


def Sizzle(rng):
    # Обугленный жук: потрескивание и шипение жара.
    d = 0.9
    x = hp(noise(d, rng), 3000) * env_exp(d, 0.4, 0.02) * 0.4
    for _ in range(40):
        c = noise(0.003, rng) * env_exp(0.003, 0.0008)
        place(x, c * rng.uniform(0.3, 1.0), rng.random() * 0.8)
    return fade(x)


# ---------- жуки ----------

def DeathSmall(rng):
    d = 0.35
    x = pad(crunch(rng, 0.1, 6000) * 2.5, d)
    x += lp(noise(d, rng), 900) * env_exp(d, 0.04) * 0.6
    return fade(x)


def DeathMedium(rng):
    d = 0.6
    x = pad(crunch(rng, 0.18, 4500) * 2.5, d)
    squelch = bp(noise(d, rng), 200, 1200) * env_exp(d, 0.12, 0.02)
    gurgle = sweep(d, 260, 90) * env_exp(d, 0.1) * 0.6
    return fade(x + squelch + gurgle)


def DeathBig(rng):
    d = 1.0
    x = pad(crunch(rng, 0.3, 3500) * 2.5, d)
    thud = sweep(d, 90, 38) * env_exp(d, 0.18) * 1.4
    squelch = bp(noise(d, rng), 150, 900) * env_exp(d, 0.25, 0.03) * 1.2
    return fade(softclip(x + thud + squelch, 1.5), 0.002, 0.1)


def Splat(rng):
    # Влажный шлепок останков.
    d = 0.4
    x = bp(noise(d, rng), 250, 1800) * env_exp(d, 0.06, 0.004) * 1.5
    x += sweep(d, 340, 120) * env_exp(d, 0.05) * 0.5
    return fade(x)


def Shatter(rng):
    # Керамическая статуя разбита.
    d = 0.9
    x = hp(noise(d, rng), 1500) * env_exp(d, 0.05) * 0.8
    for _ in range(30):
        f = rng.uniform(2000, 6500)
        dd = rng.uniform(0.05, 0.25)
        ping = np.sin(2 * np.pi * f * t_axis(dd)) * env_exp(dd, dd / 4)
        place(x, ping * rng.uniform(0.05, 0.25), rng.random() ** 1.5 * 0.6)
    return fade(x)


def WingBuzz(rng):
    # Петля: крылья летающего жука.
    d = 1.0
    t = t_axis(d + 0.2)
    f = 180 + 6 * np.sin(2 * np.pi * 3 * t)
    ph = np.cumsum(f) / SR
    x = (2 * (ph % 1.0) - 1) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    x = bp(x, 150, 2200)
    return loopable(x, 0.2)


def HumArea(rng):
    # Петля: гул работающей площадной турели (Испаритель, Бур, Центрифуга — высотой).
    d = 2.0
    t = t_axis(d + 0.3)
    x = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((60, 0.6), (120, 0.4), (180, 0.15), (240, 0.1)))
    x += bp(noise(d + 0.3, rng), 800, 2400) * 0.08
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 2 * t)
    return loopable(x, 0.3)


# ---------- забег ----------

def WaveStart(rng):
    # Тревога бункера: два гудка сирены.
    d = 1.9
    x = np.zeros(int(d * SR))
    for at in (0.0, 0.85):
        tone = saw(311, 0.7) * 0.5 + saw(466, 0.7) * 0.35
        tone = lp(tone, 2200) * np.minimum(t_axis(0.7) / 0.03, 1) * np.minimum((0.7 - t_axis(0.7)) / 0.08, 1)
        place(x, tone, at)
    return fade(softclip(x, 1.3), 0.002, 0.05)


def _arp(notes, step, d, decay=0.35, bright=3000):
    x = np.zeros(int(d * SR))
    for i, f in enumerate(notes):
        n = saw(f, 0.9) * 0.5 + np.sin(2 * np.pi * f * 2 * t_axis(0.9)) * 0.2
        place(x, lp(n, bright) * env_exp(0.9, decay, 0.005), i * step)
    return x


def RunWin(rng):
    d = 2.2
    return fade(_arp([261.6, 329.6, 392.0, 523.3, 659.3], 0.12, d, 0.6), 0.002, 0.3)


def RunLose(rng):
    d = 2.4
    x = _arp([392.0, 311.1, 261.6, 196.0], 0.22, d, 0.5, 1800)
    x += sweep(d, 160, 45) * env_exp(d, 0.9) * 0.4
    return fade(x, 0.002, 0.3)


# ---------- фон ----------

def AmbientBunker(rng):
    # Петля 24 с: гул сети, вытяжка, редкие капли и далёкий лязг.
    d = 24.0
    full = d + 2.0
    t = t_axis(full)
    hum = (np.sin(2 * np.pi * 50 * t) * 0.5 + np.sin(2 * np.pi * 100 * t) * 0.25
           + np.sin(2 * np.pi * 150 * t) * 0.08) * 0.35
    vent = lp(noise(full, rng), 500, 2) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.11 * t)) * 0.9
    x = hum + vent
    for _ in range(14):
        f = rng.uniform(1100, 2200)
        drop = sweep(0.08, f, f * 1.6) * env_exp(0.08, 0.02) * rng.uniform(0.05, 0.15)
        place(x, drop, rng.uniform(0.5, full - 1))
    for _ in range(3):
        clank = sum(np.sin(2 * np.pi * f * t_axis(1.2)) for f in (233, 377, 610)) * env_exp(1.2, 0.35) * 0.05
        place(x, lp(clank, 1500), rng.uniform(1, full - 2))
    return loopable(x, 2.0)


def MusicBunker(rng):
    # Петля 76,8 с (32 такта по 4/4, 100 BPM): бас-пульс, «булькающее» арпеджио, бочка.
    bpm = 100
    beat = 60 / bpm
    bars = 32
    d = bars * 4 * beat
    x = np.zeros(int(d * SR))
    # A минор: аккорды по 4 такта
    roots = [55.0, 43.65, 49.0, 41.2]  # A1 F1 G1 E1
    chords = [[220, 261.6, 329.6], [174.6, 220, 261.6], [196, 246.9, 293.7], [164.8, 207.7, 246.9]]
    for bar in range(bars):
        k = (bar // 4) % 4
        start = bar * 4 * beat
        # бас восьмыми, с ударением на долю
        for i in range(8):
            f = roots[k] * (2 if i % 4 == 3 else 1)
            n = lp(saw(f, beat / 2), 400 + 300 * (i % 2 == 0)) * env_exp(beat / 2, 0.12, 0.004)
            place(x, n * (0.55 if i % 2 == 0 else 0.35), start + i * beat / 2)
        # бочка на 1 и 3, с 5-го такта
        if bar >= 4:
            for b in (0, 2):
                kick = sweep(0.35, 120, 40) * env_exp(0.35, 0.09, 0.001)
                place(x, kick * 0.7, start + b * beat)
        # металлический хэт на слабые доли, с 9-го такта
        if bar >= 8:
            for i in range(4):
                hat = hp(noise(0.05, rng), 7000) * env_exp(0.05, 0.012)
                place(x, hat * 0.12, start + i * beat + beat / 2)
        # арпеджио шестнадцатыми: стекло и пузыри
        if bar >= 2:
            notes = chords[k]
            for i in range(16):
                f = notes[(i * 2 + bar) % 3] * (2 if i % 8 >= 4 else 1)
                tone = np.sin(2 * np.pi * f * t_axis(0.25)) + 0.3 * np.sin(2 * np.pi * f * 3.01 * t_axis(0.25))
                place(x, tone * env_exp(0.25, 0.06, 0.003) * 0.13, start + i * beat / 4)
        # пэд
        pad_t = 4 * beat
        p = sum(saw(f / 2 * (1 + det), pad_t) for f in chords[k] for det in (-0.003, 0.003))
        p = lp(p, 900) * 0.035 * np.minimum(t_axis(pad_t) / 0.4, 1) * np.minimum((pad_t - t_axis(pad_t)) / 0.4, 1)
        place(x, p, start)
    return softclip(x, 1.2)


ALL = [ShotFlask, ShotInjector, DroneLaunch, Boom, DroneBoom, Quake, Splash, Sizzle,
       DeathSmall, DeathMedium, DeathBig, Splat, Shatter, WingBuzz, HumArea,
       WaveStart, RunWin, RunLose, AmbientBunker, MusicBunker]

LOOPS = {"WingBuzz", "HumArea", "AmbientBunker", "MusicBunker"}


def write(name, x):
    x = normalize(x, 0.89)
    if name not in LOOPS:
        x = fade(x, 0.0005, 0.01)
    data = (x * 32767).astype("<i2").tobytes()
    OUT.mkdir(exist_ok=True)
    # В репозиторий идёт .ogg (в 8–10 раз меньше .wav), если есть ffmpeg; без него — .wav.
    ogg = shutil.which("ffmpeg") is not None
    path = Path(tempfile.mkdtemp()) / f"{name}.wav" if ogg else OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    if ogg:
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(path), "-c:a", "libvorbis", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        "-q:a", "5", str(OUT / f"{name}.ogg")], check=True)
        path.unlink()


def main(names):
    for fn in ALL:
        if names and fn.__name__ not in names:
            continue
        rng = np.random.default_rng(sum(map(ord, fn.__name__)))
        write(fn.__name__, fn(rng))
        print("ok", fn.__name__)


if __name__ == "__main__":
    main(set(sys.argv[1:]))
