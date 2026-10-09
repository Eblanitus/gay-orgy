"""Строит графики (все времена — UTC) по истории репозитория (git log) и архивному CHANGELOG.
Запуск из корня репозитория: python analysis/build_charts.py
Нужны: matplotlib, pandas. Выход: analysis/*.png, analysis/metrics.json
"""
import json, os, re, subprocess, collections
from datetime import datetime, timezone
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "analysis")
os.chdir(ROOT)

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True).stdout

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                     "axes.spines.top": False, "axes.spines.right": False,
                     "axes.grid": True, "grid.alpha": 0.3})
C_CLAUDE, C_HUMAN, C_ACC = "#4C72B0", "#DD8452", "#55A868"

# ---------- 1. коммиты: метаданные, объём кода (src/), churn ----------
meta = []
for line in sh("git log --reverse --format='@@%H|%aI|%an|%s' --numstat -- src").splitlines():
    if line.startswith("@@"):
        h, dt, au, subj = line[2:].split("|", 3)
        meta.append(dict(hash=h, dt=datetime.fromisoformat(dt).astimezone(timezone.utc), author=au, subject=subj, ins=0, dele=0))
    elif line.strip() and meta:
        p = line.split("\t")
        if len(p) == 3 and p[0].isdigit():
            meta[-1]["ins"] += int(p[0]); meta[-1]["dele"] += int(p[1])
# все коммиты (включая те, что не трогали src)
all_commits = []
for line in sh("git log --reverse --format='%H|%aI|%an|%s'").splitlines():
    h, dt, au, subj = line.split("|", 3)
    all_commits.append(dict(hash=h, dt=datetime.fromisoformat(dt).astimezone(timezone.utc), author=au, subject=subj))
df = pd.DataFrame(all_commits)
df["day"] = df["dt"].dt.strftime("%Y-%m-%d")
df["hour"] = df["dt"].dt.hour
df["dow"] = df["dt"].dt.dayofweek  # 0=Пн

# размер кода (.luau в src) по коммитам
size = []
for c in all_commits:
    out = sh(f"git ls-tree -r -l {c['hash']} -- src")
    fl = [l for l in out.splitlines() if l.endswith(".luau")]
    size.append((c["dt"], len(fl), sum(int(l.split()[3]) for l in fl)))
size_df = pd.DataFrame(size, columns=["dt", "files", "bytes"])

# ---------- 2. задачи: архивный CHANGELOG (#1–#232) + Git (#233+) ----------
txt = open("Устаревшие документы/CHANGELOG.md", encoding="utf-8-sig").read()
heads = re.findall(r"^## #(\d+)\s*—\s*(.*?)\s*\((\d{4}-\d{2}-\d{2})\)\s*$", txt, re.M)
tasks = {int(n): (t, datetime.strptime(d, "%Y-%m-%d")) for n, t, d in heads}
for c in all_commits:
    m = re.match(r"#(\d+)\s*—\s*(.*)", c["subject"])
    if m:
        n = int(m.group(1))
        tasks.setdefault(n, (m.group(2), c["dt"].replace(tzinfo=None)))

TOPICS = [("Баги и фиксы", r"исправ|фикс|почин|не работ|не видн|баг|ошибк|сломан|падени|не реаг"),
          ("Вики / дизайн", r"вики|дизайн|стиль|документ"),
          ("Баланс", r"баланс|урон|хп|цен|стоим|скорост"),
          ("Визуал / модели", r"модел|визуал|паттерн|узор|цвет|свет|эффект|fx|анимац|дым|ракурс"),
          ("Меню / UI", r"меню|интерфейс|экран|кнопк|справочник|подсказ|hud|окно|ui\b"),
          ("Враги / волны", r"жук|волн|враг|моль|поток|паук|пчел"),
          ("Башни / элементы", r"башн|турел|пил|колб|лент|бур|стрел|элемент|крафт|стол|рецепт"),
          ("Инфраструктура", r"rojo|git|бэкап|звук|музык|переезд|пересборк|sync|загруз|tools|роблокс")]
def topic(t):
    tl = t.lower()
    for name, pat in TOPICS:
        if re.search(pat, tl):
            return name
    return "Прочее"
tdf = pd.DataFrame([(n, t, d, topic(t)) for n, (t, d) in tasks.items()],
                   columns=["n", "title", "dt", "topic"]).sort_values("dt")
tdf["week"] = tdf["dt"].dt.to_period("W-SUN").apply(lambda p: p.start_time)

# ---------- 3. структура кода ----------
loc_rows = []
for root, _, files in os.walk("src"):
    for f in files:
        if f.endswith(".luau"):
            p = os.path.join(root, f)
            with open(p, encoding="utf-8", errors="ignore") as fh:
                loc_rows.append((p.replace("src/", ""), sum(1 for _ in fh)))
loc = pd.DataFrame(loc_rows, columns=["file", "lines"])
loc["folder"] = loc["file"].apply(lambda s: s.split("/")[0] + ("/" + s.split("/")[1] if s.count("/") >= 2 else ""))
folder_loc = loc.groupby("folder")["lines"].agg(["sum", "count"]).sort_values("sum", ascending=False)
top_files = loc.sort_values("lines", ascending=False).head(15)

churn = collections.Counter()
for line in sh("git log --format= --name-only -- src").splitlines():
    if line.strip().endswith(".luau"):
        churn[line.strip().replace("src/", "")] += 1
top_churn = churn.most_common(15)

# ---------- ГРАФИКИ ----------
def save(fig, name):
    fig.tight_layout(); fig.savefig(os.path.join(OUT, name), dpi=130); plt.close(fig)

# 1) Задачи по неделям (CHANGELOG + Git)
wk = tdf.groupby("week").size()
fig, ax = plt.subplots(figsize=(10, 4.5))
ax.bar(wk.index, wk.values, width=5, color=C_ACC)
for x, y in zip(wk.index, wk.values):
    ax.text(x, y + 0.5, str(y), ha="center", fontsize=9)
ax.set_title("Закрытых задач в неделю (#13–#452, по заголовкам CHANGELOG и коммитов)")
ax.set_ylabel("задач"); ax.set_xlabel("неделя (с понедельника)")
save(fig, "01_tasks_per_week.png")

# 2) Активность по дням: коммиты по авторам
pv = df.assign(human=lambda d: d.author.eq("Eblanitus")).groupby(["day", "author"]).size().unstack(fill_value=0)
fig, ax = plt.subplots(figsize=(10, 4.5))
x = range(len(pv))
bottom = [0]*len(pv)
for col, color in [("Claude", C_CLAUDE), ("Eblanitus", C_HUMAN)]:
    if col in pv:
        ax.bar(x, pv[col].values, bottom=bottom, color=color, label=col)
        bottom = [b + v for b, v in zip(bottom, pv[col].values)]
ax.set_xticks(list(x)); ax.set_xticklabels([d[5:] for d in pv.index], rotation=45)
ax.set_title("Коммиты по дням и авторам (24.09 — 09.10.2026)")
ax.set_ylabel("коммитов"); ax.legend(frameon=False)
save(fig, "02_commits_per_day.png")

# 3) Рост кодовой базы: объём .luau и число файлов
fig, ax1 = plt.subplots(figsize=(10, 4.5))
ax1.plot(size_df["dt"], size_df["bytes"] / 1e6, color=C_CLAUDE, lw=2, label="объём .luau, МБ")
ax1.set_ylabel("МБ (.luau)", color=C_CLAUDE)
ax2 = ax1.twinx(); ax2.spines["right"].set_visible(True)
ax2.plot(size_df["dt"], size_df["files"], color=C_HUMAN, lw=2, ls="--", label="число скриптов")
ax2.set_ylabel("скриптов (.luau)", color=C_HUMAN)
ax1.set_title("Рост кодовой базы src/ по коммитам")
save(fig, "03_codebase_growth.png")

# 4) Churn по дням (без первичного импорта 24.09 — отдельный подзаголовок)
ch = pd.DataFrame(meta).assign(day=lambda d: d.dt.dt.strftime("%Y-%m-%d")).groupby("day")[["ins", "dele"]].sum()
fig, ax = plt.subplots(figsize=(10, 4.5))
x = range(len(ch))
ax.bar([i - 0.2 for i in x], ch["ins"], width=0.4, color=C_ACC, label="добавлено строк")
ax.bar([i + 0.2 for i in x], -ch["dele"], width=0.4, color="#C44E52", label="удалено строк")
ax.axhline(0, color="black", lw=0.8)
ax.set_xticks(list(x)); ax.set_xticklabels([d[5:] for d in ch.index], rotation=45)
ax.set_title("Изменения кода (churn) по дням, строк src/")
ax.legend(frameon=False); ax.set_ylabel("строк")
save(fig, "04_churn_per_day.png")

# 5) Темы задач
tc = tdf["topic"].value_counts()
fig, ax = plt.subplots(figsize=(9, 4.8))
ax.barh(tc.index[::-1], tc.values[::-1], color=C_CLAUDE)
for i, v in enumerate(tc.values[::-1]):
    ax.text(v + 0.5, i, str(v), va="center")
ax.set_title(f"Темы задач (всего {len(tdf)})"); ax.set_xlabel("задач")
save(fig, "05_task_topics.png")

# 6) Размер модулей (топ-15 файлов по строкам)
fig, ax = plt.subplots(figsize=(10, 6))
tf = top_files.iloc[::-1]
ax.barh([f.split("/")[-1] for f in tf["file"]], tf["lines"], color=C_CLAUDE)
for i, v in enumerate(tf["lines"]):
    ax.text(v + 15, i, str(v), va="center", fontsize=8)
ax.set_title("15 самых больших модулей (строк Luau)"); ax.set_xlabel("строк")
save(fig, "06_largest_modules.png")

# 7) Строки кода по папкам
fl = folder_loc.reset_index()
fig, ax = plt.subplots(figsize=(10, 4.8))
ax.barh(fl["folder"][::-1], fl["sum"][::-1], color=C_HUMAN)
for i, (v, c) in enumerate(zip(fl["sum"][::-1], fl["count"][::-1])):
    ax.text(v + 60, i, f"{v} строк, {c} файлов", va="center", fontsize=9)
ax.set_xlim(0, fl["sum"].max() * 1.35)
ax.set_title("Строки Luau по папкам Rojo (src/)"); ax.set_xlabel("строк")
save(fig, "07_loc_by_folder.png")

# 8) Самые часто меняемые файлы (churn по коммитам)
fig, ax = plt.subplots(figsize=(10, 5.5))
names = [f.split("/")[-1] for f, _ in top_churn][::-1]
vals = [c for _, c in top_churn][::-1]
ax.barh(names, vals, color=C_ACC)
for i, v in enumerate(vals):
    ax.text(v + 0.3, i, str(v), va="center", fontsize=9)
ax.set_title("Самые часто меняемые файлы (число коммитов)"); ax.set_xlabel("коммитов")
save(fig, "08_most_changed_files.png")

# 9) Когда работают: день недели × час (Europe/Moscow не пересчитываем: время из коммитов)
names_dow = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
hm = df.groupby(["dow", "hour"]).size().unstack(fill_value=0).reindex(index=range(7), columns=range(24), fill_value=0)
fig, ax = plt.subplots(figsize=(11, 3.8))
im = ax.imshow(hm.values, aspect="auto", cmap="Blues")
ax.set_yticks(range(7)); ax.set_yticklabels(names_dow)
ax.set_xticks(range(24)); ax.set_xticklabels(range(24), fontsize=8)
ax.set_xlabel("час (по времени коммита)")
ax.grid(False)
ax.set_title("Когда делаются коммиты: день недели × час")
fig.colorbar(im, ax=ax, label="коммитов")
save(fig, "09_commit_heatmap.png")

# ---------- метрики в JSON ----------
metrics = dict(
    commits_total=len(df),
    commits_by_author=df["author"].value_counts().to_dict(),
    commits_with_task_number=int(df["subject"].str.match(r"#\d+").sum()),
    tasks_total=len(tdf),
    tasks_range=[int(tdf.n.min()), int(tdf.n.max())],
    first_day=str(df.day.min()), last_day=str(df.day.max()),
    luau_files_now=int(size_df.files.iloc[-1]), luau_bytes_now=int(size_df.bytes.iloc[-1]),
    loc_luau_total=int(loc.lines.sum()),
    loc_by_folder=folder_loc["sum"].to_dict(),
    top_files=top_files[["file", "lines"]].values.tolist(),
    topics=tc.to_dict(),
    ins_total=int(sum(m["ins"] for m in meta)), del_total=int(sum(m["dele"] for m in meta)),
)
json.dump(metrics, open(os.path.join(OUT, "metrics.json"), "w"), ensure_ascii=False, indent=2, default=str)
print(json.dumps(metrics, ensure_ascii=False, indent=2, default=str)[:3000])
