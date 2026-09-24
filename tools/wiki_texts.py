#!/usr/bin/env python3
"""Собирает src/ReplicatedStorage/WikiTexts.luau — описания элементов и жуков для справочника.

Источник — вики автора (ВИКИПЕДИЯ/), а не текст от агента: справочник в игре должен
говорить то же, что и дизайн-документы. Цифр в вики нет, поэтому и в описаниях их нет —
числа справочник берёт из таблиц Elements/Enemies.

Запуск после правки вики: python3 tools/wiki_texts.py
"""
import glob, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIKI = os.path.join(ROOT, "ВИКИПЕДИЯ")
OUT = os.path.join(ROOT, "src", "ReplicatedStorage", "WikiTexts.luau")


def one(pattern):
    found = sorted(glob.glob(os.path.join(WIKI, pattern)))
    if len(found) != 1:
        raise SystemExit(f"ожидался один файл {pattern}, найдено: {found}")
    return open(found[0], encoding="utf-8").read(), os.path.basename(found[0])


def clean(text):
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"\s*\n\s*", " ", text.strip())
    return re.sub(r"\s{2,}", " ", text)


def enemies():
    text, name = one("alchemy_td_enemies_v*.md")
    result = {}
    # Разделы «### Имя» внутри каст: описание — до следующего заголовка, «Урок:» — отдельно.
    for m in re.finditer(r"^### (.+?)\n(.*?)(?=^#{2,3} |\Z)", text, re.S | re.M):
        title, body = m.group(1).strip(), m.group(2)
        body = re.split(r"^---\s*$", body, flags=re.M)[0]
        lesson = None
        lm = re.search(r"\*\*Урок:\*\*(.*)", body, re.S)
        if lm:
            lesson = clean(lm.group(1))
            body = body[: lm.start()]
        result[title] = {"text": clean(body), "lesson": lesson}
    return result, name


def elements():
    text, name = one("alchemy_td_effects_v*.md")
    result = {}
    # Строка элемента: «**Имя** (А + Б) — описание» или у базовых «**Имя** — описание»;
    # описание может идти несколькими строками до пустой строки.
    for m in re.finditer(r"^\*\*([^*]+)\*\*(?: \(([^)]*)\))? — (.*?)(?=\n\s*\n|\Z)", text, re.S | re.M):
        result[m.group(1).strip()] = clean(m.group(3))
    return result, name


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    en, en_file = enemies()
    el, el_file = elements()
    lines = [
        "-- Описания элементов и жуков для справочника. СГЕНЕРИРОВАНО tools/wiki_texts.py",
        f"-- из вики ({el_file}, {en_file}) — руками не править, править вики и перезапустить.",
        "-- Ключ — имя, как в вики и в поле name таблиц Elements/Enemies.",
        "local WikiTexts = {}",
        "",
        "WikiTexts.elements = {",
    ]
    for k in sorted(el):
        lines.append(f"\t[{lua_string(k)}] = {lua_string(el[k])},")
    lines += ["}", "", "WikiTexts.enemies = {"]
    for k in sorted(en):
        v = en[k]
        lesson = lua_string(v["lesson"]) if v["lesson"] else "nil"
        lines.append(f"\t[{lua_string(k)}] = {{ text = {lua_string(v['text'])}, lesson = {lesson} }},")
    lines += ["}", "", "return WikiTexts", ""]
    open(OUT, "w", encoding="utf-8").write("\n".join(lines))
    print(f"элементов {len(el)}, жуков {len(en)} -> {os.path.relpath(OUT, ROOT)}")


main()
