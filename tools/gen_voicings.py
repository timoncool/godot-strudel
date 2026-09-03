"""Генератор словаря аккордовых раскладок из ireal.mjs Булки.

Раскладок сотни, и они задают КОНКРЕТНЫЕ ноты: переписывать руками —
гарантированно разъехаться с оригиналом. Поэтому файл порождается.

    python tools/gen_voicings.py

Пишет addons/strudel/tonal/voicing_table.gd.
"""

import json
import re
import sys
from pathlib import Path

SRC = Path(r"D:/Projects/TEMP/bulka/packages/tonal/ireal.mjs")
SRC_REG = Path(r"D:/Projects/TEMP/bulka/packages/tonal/voicings.mjs")
OUT = Path(__file__).resolve().parent.parent / "addons" / "strudel" / "tonal" / "voicing_table.gd"


def grab_object(text: str, name: str, prefix: str = "export const") -> dict:
    """Достаёт литерал объекта `<prefix> <name> = { … }` и читает его как JSON."""
    start = text.index(f"{prefix} {name} =")
    brace = text.index("{", start)
    depth = 0
    i = brace
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = text[brace : i + 1]
    # одинарные кавычки → двойные; голые числовые ключи → в кавычки
    body = re.sub("//.*", "", body)  # построчные пояснения JS — вон
    body = body.replace("'", '"')
    body = re.sub(r"(\{|,)\s*([A-Za-z0-9_+^\-]+)\s*:", lambda m: f'{m.group(1)}"{m.group(2)}":', body)
    body = re.sub(r",(\s*[}\]])", r"\1", body)  # висячие запятые
    return json.loads(body)


def add_aliases(table: dict) -> dict:
    """Псевдонимы символов, как их заводит voicings.mjs."""
    out = dict(table)
    if "^" in out:
        out[""] = out["^"]  # мажорное трезвучие без символа
    for symbol in list(table.keys()):
        if "-" in symbol:
            out.setdefault(symbol.replace("-", "m"), table[symbol])
        if "^" in symbol:
            out.setdefault(symbol.replace("^", "M"), table[symbol])
        if "+" in symbol:
            out.setdefault(symbol.replace("+", "aug"), table[symbol])
    return out


def emit(name: str, table: dict) -> list[str]:
    lines = [f"const {name} := {{"]
    for symbol, voicings in table.items():
        items = ", ".join('"%s"' % v for v in voicings)
        lines.append(f'\t"{symbol}": [{items}],')
    lines.append("}")
    return lines


def main() -> int:
    if not SRC.is_file():
        print(f"нет исходника: {SRC}", file=sys.stderr)
        return 1
    text = SRC.read_text(encoding="utf-8")

    simple = add_aliases(grab_object(text, "simple"))
    complex_ = add_aliases(grab_object(text, "complex"))

    # Четыре словаря из voicings.mjs. Псевдонимы к ним НЕ применяются:
    # `voicingAlias` в оригинале трогает только simple и complex.
    reg_text = SRC_REG.read_text(encoding="utf-8")
    extra = {
        "LEFTHAND": grab_object(reg_text, "lefthand", "const"),
        "GUIDETONES": grab_object(reg_text, "guidetones", "const"),
        "TRIADS": grab_object(reg_text, "triads", "const"),
        "LEGACY": grab_object(reg_text, "defaultDictionary", "const"),
    }

    lines = [
        "@tool",
        "class_name StrudelVoicingTable",
        "extends RefCounted",
        "",
        "## Словари аккордовых раскладок — ПОРОЖДЕНЫ, не написаны руками.",
        "##",
        "## Источник: packages/tonal/ireal.mjs Булки, генератор tools/gen_voicings.py.",
        "## Здесь задаются КОНКРЕТНЫЕ ноты аккордов; ручная копия разъехалась бы",
        "## с оригиналом молча, а слышно это только на аккорде.",
        "##",
        "## Запись: символ аккорда → список раскладок, каждая — интервалы от",
        '## основного тона ("3M 5P 7M 9M" — терция, квинта, большая септима, нона).',
        f"## Записей: simple {len(simple)}, complex {len(complex_)}.",
        "",
    ]
    lines += emit("IREAL", simple)
    lines.append("")
    lines += emit("IREAL_EXT", complex_)
    for const_name, table in extra.items():
        lines.append("")
        lines += emit(const_name, table)
    lines += [
        "",
        "",
        "static func dictionary(name: String) -> Dictionary:",
        '	## Словарь по имени. По умолчанию — "ireal", как в Strudel.',
        "	##",
        "	## 🔴 Своих `mode` и `anchor` у записей реестра НЕТ — точнее, они",
        "	## есть, но не работают: `voicing` подставляет в renderVoicing",
        "	## `anchor` и `mode` из значения события, а когда их не задали,",
        "	## в JS туда уезжает `undefined` и включается умолчание самой",
        '	## функции («below», «c5»). Реестровые «a4» и «above» мертвы,',
        "	## и повторять их здесь значило бы разойтись с Булкой.",
        "	match name:",
        '		"ireal-ext":',
        "			return IREAL_EXT",
        '		"lefthand":',
        "			return LEFTHAND",
        '		"guidetones":',
        "			return GUIDETONES",
        '		"triads":',
        "			return TRIADS",
        '		"legacy":',
        "			return LEGACY",
        "	return IREAL",
        "",
    ]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{OUT.name}: simple {len(simple)}, complex {len(complex_)}, "
          + ", ".join(f"{k.lower()} {len(v)}" for k, v in extra.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
