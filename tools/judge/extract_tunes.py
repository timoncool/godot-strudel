"""Вытаскивает настоящие треки сообщества из коллекции Strudel.

Приёмка плагина — не один подогнанный трек, а ЛЮБОЙ мощный. В репозитории
Strudel лежит `website/src/repl/tunes.mjs` — 32 трека, написанных людьми:
giantSteps, caverave, bassFuge, amensister, flatrave и прочие. Они и
становятся корпусом.

    python tools/judge/extract_tunes.py

Кладёт каждый трек отдельным файлом в examples/tunes/ и список — в
tools/judge/tunes.json.
"""

import json
import re
import sys
from pathlib import Path

SRC = Path(r"D:/Projects/TEMP/bulka/website/src/repl/tunes.mjs")
ROOT = Path(__file__).resolve().parent.parent.parent
OUT_DIR = ROOT / "examples" / "tunes"
LIST = ROOT / "tools" / "judge" / "tunes.json"

# export const имя = `…`;  либо  export const имя = "…";
DECL = re.compile(r"export const ([A-Za-z0-9_]+)\s*=\s*([`'\"])", re.M)


def unescape(text: str, quote: str) -> str:
    if quote != "`":
        return text
    # В шаблонных строках экранированы обратные кавычки и ${
    return text.replace("\\`", "`").replace("\\${", "${").replace("\\\\", "\\")


def main() -> int:
    if not SRC.is_file():
        print(f"нет коллекции: {SRC}", file=sys.stderr)
        return 1
    text = SRC.read_text(encoding="utf-8")

    tunes = []
    for m in DECL.finditer(text):
        name = m.group(1)
        quote = m.group(2)
        start = m.end()
        # ищем закрывающую кавычку, пропуская экранированные
        i = start
        while i < len(text):
            if text[i] == "\\":
                i += 2
                continue
            if text[i] == quote:
                break
            i += 1
        body = unescape(text[start:i], quote)
        tunes.append((name, body))

    if not tunes:
        print("не нашёл ни одного трека", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.js"):
        old.unlink()

    index = []
    for name, body in tunes:
        path = OUT_DIR / f"{name}.js"
        header = (
            f"// {name} — трек из коллекции Strudel (website/src/repl/tunes.mjs).\n"
            "// Взят КАК ЕСТЬ, без единой правки: на таких треках и проверяется плагин.\n\n"
        )
        path.write_text(header + body.strip() + "\n", encoding="utf-8")
        index.append({
            "id": name,
            "file": f"examples/tunes/{name}.js",
            "lines": len(body.strip().splitlines()),
            "chars": len(body.strip()),
        })

    LIST.write_text(json.dumps(index, indent=1, ensure_ascii=False), encoding="utf-8")
    total = sum(t["lines"] for t in index)
    print(f"треков {len(index)}, строк всего {total}")
    for t in sorted(index, key=lambda x: -x["lines"])[:10]:
        print(f"   {t['id']:24} {t['lines']:3} строк")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
