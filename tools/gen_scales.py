"""Генератор таблицы ладов из @tonaljs/scale-type.

`scale("C:major")` обязан дать те же ноты, что в Булке, а список ладов там
берётся из @tonaljs. Переписывать сотню строк интервалов руками — значит
рано или поздно разъехаться на одном полутоне.

    python tools/gen_scales.py

Пишет addons/strudel/tonal/scale_table.gd.
"""

import re
import sys
from pathlib import Path

CANDIDATES = [
    Path(r"D:/Projects/TEMP/bulka/desktop/dist-portable/Bulka/app/node_modules/@tonaljs/scale-type/dist/index.mjs"),
    Path(r"D:/Projects/TEMP/bulka/node_modules/@tonaljs/scale-type/dist/index.mjs"),
]
OUT = Path(__file__).resolve().parent.parent / "addons" / "strudel" / "tonal" / "scale_table.gd"

ROW = re.compile(r'\[\s*"([0-9PMmAd#b ]+)"\s*((?:,\s*"[^"]+"\s*)+)\]')
NAME = re.compile(r'"([^"]+)"')


def main() -> int:
    src = next((p for p in CANDIDATES if p.is_file()), None)
    if src is None:
        print("не нашёл @tonaljs/scale-type", file=sys.stderr)
        return 1
    text = src.read_text(encoding="utf-8")
    start = text.index("var SCALES = [")
    end = text.index("\n];", start)
    body = text[start:end]

    entries: list[tuple[str, list[str]]] = []
    for m in ROW.finditer(body):
        intervals = m.group(1).strip()
        names = NAME.findall(m.group(2))
        entries.append((intervals, names))

    if not entries:
        print("не разобрал таблицу ладов", file=sys.stderr)
        return 1

    lines = [
        "@tool",
        "class_name StrudelScaleTable",
        "extends RefCounted",
        "",
        "## Лады — ПОРОЖДЕНЫ из @tonaljs/scale-type, тем же списком, что у Булки.",
        "## Генератор: tools/gen_scales.py. Править надо его.",
        "##",
        '## Запись: имя лада → интервалы от тоники ("1P 2M 3M 4P 5P 6M 7M").',
        f"## Ладов: {len(entries)}, имён с псевдонимами: {sum(len(n) for _, n in entries)}.",
        "",
        "const SCALES := {",
    ]
    seen: set[str] = set()
    for intervals, names in entries:
        for n in names:
            key = n.lower()
            if key in seen:
                continue
            seen.add(key)
            lines.append(f'\t"{key}": "{intervals}",')
    lines.append("}")
    lines += [
        "",
        "",
        "static func intervals(name: String) -> String:",
        '\t## Интервалы лада; "" — если такого лада нет.',
        '\treturn String(SCALES.get(name.strip_edges().to_lower(), ""))',
        "",
    ]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{OUT.name}: {len(entries)} ладов, {len(seen)} имён")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
