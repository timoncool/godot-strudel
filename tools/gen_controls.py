"""Генератор таблицы управляющих функций из controls.mjs Булки.

Таблица большая (264 записи) и меняется вместе с апстримом, поэтому она
ПОРОЖДАЕТСЯ, а не ведётся руками: иначе список молча разъедется.

    python tools/gen_controls.py

Пишет addons/strudel/runtime/controls_table.gd.
"""

import re
import sys
from pathlib import Path

SRC = Path(r"D:/Projects/TEMP/bulka/packages/core/controls.mjs")
OUT = Path(__file__).resolve().parent.parent / "addons" / "strudel" / "runtime" / "controls_table.gd"

CALL = re.compile(
    r"registerControl\(\s*(\[[^\]]*\]|'[^']*'|\"[^\"]*\")\s*((?:,\s*(?:'[^']*'|\"[^\"]*\")\s*)*)\)",
    re.S,
)
MULTI = re.compile(
    r"registerMultiControl\(\s*(\[[^\]]*\]|'[^']*'|\"[^\"]*\")\s*,\s*(\d+)\s*((?:,\s*(?:'[^']*'|\"[^\"]*\")\s*)*)\)",
    re.S,
)
STR = re.compile(r"['\"]([^'\"]*)['\"]")


def names_of(token: str) -> list[str]:
    return STR.findall(token)


def aliases_of(token: str) -> list[str]:
    return STR.findall(token or "")


def main() -> int:
    if not SRC.is_file():
        print(f"нет исходника: {SRC}", file=sys.stderr)
        return 1
    text = SRC.read_text(encoding="utf-8")

    entries: list[tuple[list[str], list[str]]] = []

    for m in CALL.finditer(text):
        names = names_of(m.group(1))
        aliases = aliases_of(m.group(2))
        if names and names[0] != "names":
            entries.append((names, aliases))

    for m in MULTI.finditer(text):
        base = names_of(m.group(1))
        if not base or base[0] == "names":
            continue
        count = int(m.group(2))
        base_aliases = aliases_of(m.group(3))
        for i in range(1, count + 1):
            if i == 1:
                these_aliases = list(base_aliases)
                these_aliases += [f"{a}1" for a in base_aliases]
                these_aliases += [f"{n}1" for n in base]
                these_names = list(base)
            else:
                these_aliases = [f"{a}{i}" for a in base_aliases]
                these_names = [f"{n}{i}" for n in base]
            entries.append((these_names, these_aliases))

    # порядок как в исходнике; при столкновении имён побеждает первое
    seen: set[str] = set()
    rows: list[tuple[list[str], list[str]]] = []
    for names, aliases in entries:
        if names[0] in seen:
            continue
        seen.add(names[0])
        rows.append((names, aliases))

    lines = [
        "@tool",
        "class_name StrudelControlsTable",
        "extends RefCounted",
        "",
        "## Таблица управляющих функций Strudel — ПОРОЖДЕНА, не написана руками.",
        "##",
        "## Источник: packages/core/controls.mjs Булки, генератор tools/gen_controls.py.",
        "## Править надо генератор, а не этот файл: список меняется вместе с",
        f"## апстримом, и ручная копия разъезжается молча. Записей: {len(rows)}.",
        "##",
        "## Значение записи — список имён. У составных функций их несколько:",
        '## s("bd:3:0.7") раскладывается по ["s", "n", "gain"] — имя, индекс',
        "## сэмпла и громкость через двоеточие.",
        "",
        "const CONTROLS := {",
    ]
    for names, aliases in rows:
        arr = ", ".join(f'"{n}"' for n in names)
        al = ", ".join(f'"{a}"' for a in aliases)
        lines.append(f'\t"{names[0]}": {{"names": [{arr}], "aliases": [{al}]}},')
    lines.append("}")
    lines.append("")
    lines.append("")
    lines.append("static func main_name(name: String) -> String:")
    lines.append("\t## Настоящее имя параметра по имени или псевдониму; \"\" — не параметр.")
    lines.append("\tif CONTROLS.has(name):")
    lines.append("\t\treturn name")
    lines.append("\treturn String(ALIASES.get(name, \"\"))")
    lines.append("")
    lines.append("")
    lines.append("static func is_control(name: String) -> bool:")
    lines.append("\treturn CONTROLS.has(name) or ALIASES.has(name)")
    lines.append("")
    lines.append("")
    # Псевдонимы составных параметров пересекаются: "fmh1" приходит и от
    # ['fmh','fmi'], и от ['fmi','fmh']. Дубли и совпадения с основными
    # именами выбрасываются — в словаре GDScript ключ обязан быть один.
    lines.append("const ALIASES := {")
    used: set[str] = set()
    for names, aliases in rows:
        for a in aliases:
            if a in used or a in seen:
                continue
            used.add(a)
            lines.append(f'\t"{a}": "{names[0]}",')
    lines.append("}")
    lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{OUT.name}: {len(rows)} параметров, {len(used)} псевдонимов")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
