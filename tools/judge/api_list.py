"""Список ПУБЛИЧНОГО API Strudel прямо из исходников Булки.

Браузерный `Object.keys(strudelScope)` не годится: в нём редактор, DOM,
датчики телефона и сотни служебных имён. Здесь берутся только те, что
объявлены как функции паттерна (`register`) и параметры звука
(`registerControl`, `registerMultiControl`) в ядре, mini, tonal и superdough.

    python tools/judge/api_list.py            печатает список
    python tools/judge/api_list.py --json     кладёт golden/api.json
"""

import json
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SRC = Path(r"D:/Projects/TEMP/bulka/packages")
PKGS = ["core", "mini", "tonal"]
OUT = Path(__file__).resolve().parent / "golden" / "api.json"

REGISTER = re.compile(r"\bregister\(\s*(\[[^\]]*\]|'[^']*'|\"[^\"]*\")")
CONTROL = re.compile(r"\bregisterControl\(\s*(\[[^\]]*\]|'[^']*')((?:\s*,\s*'[^']*')*)")
MULTI = re.compile(r"\bregisterMultiControl\(\s*(\[[^\]]*\]|'[^']*')\s*,\s*(\d+)((?:\s*,\s*'[^']*')*)")
PROTO = re.compile(r"Pattern\.prototype\.([A-Za-z_][A-Za-z0-9_]*)\s*=")


def names_of(blob: str) -> list[str]:
    return re.findall(r"'([^']*)'|\"([^\"]*)\"", blob) and [
        a or b for a, b in re.findall(r"'([^']*)'|\"([^\"]*)\"", blob)
    ]


def main() -> int:
    functions: set[str] = set()
    controls: set[str] = set()
    for pkg in PKGS:
        for path in sorted((SRC / pkg).glob("*.mjs")):
            text = path.read_text(encoding="utf-8")
            # Закомментированные объявления — не API (в pattern.mjs так лежат
            #  и пример с ).
            text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
            text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
            functions.update(PROTO.findall(text))
            for m in REGISTER.finditer(text):
                functions.update(names_of(m.group(1)))
            for m in CONTROL.finditer(text):
                # 🔴 Только ПЕРВОЕ имя вызывается: остальные в массиве —
                # слоты значений (`s("bd:3:0.7")` → s, n, gain), их своей
                # функции у Strudel нет.
                controls.update(names_of(m.group(1))[:1])
                controls.update(names_of(m.group(2)))
            for m in MULTI.finditer(text):
                base = names_of(m.group(1))
                aliases = names_of(m.group(3))
                count = int(m.group(2))
                base = base[:1]
                for i in range(1, count + 1):
                    for n in base + aliases:
                        controls.add(n if i == 1 else f"{n}{i}")
                        if i == 1:
                            controls.add(f"{n}1")
    data = {"functions": sorted(functions), "controls": sorted(controls)}
    if "--json" in sys.argv:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"функций {len(functions)}, параметров {len(controls)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
