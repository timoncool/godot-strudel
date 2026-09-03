"""Сверка плагина с эталоном из живой Булки.

Эталон снят через queryArc на странице Булки (golden/haps.json), плагин
выгружает то же самое через run_corpus.gd (golden/godot.json). Здесь они
сравниваются по времени и по значению.

    python tools/judge/compare.py [--only=подстрока] [-v]

Числа сравниваются БИТАМИ: десятичная запись у Godot на восемнадцати знаках
врёт, и сверка краснела бы на верных значениях.
"""

import json
import struct
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

HERE = Path(__file__).resolve().parent
GOLDEN = HERE / "golden" / "haps.json"
MINE = HERE / "golden" / "godot.json"


def canon(v) -> str:
    """Та же каноническая запись, что в run_corpus.gd."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return "#" + struct.pack("<d", float(v)).hex()
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return "[" + ",".join(canon(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ",".join(
            json.dumps(str(k), ensure_ascii=False) + ":" + canon(v[k])
            for k in sorted(v.keys())
        ) + "}"
    return json.dumps(str(v), ensure_ascii=False)


def golden_rows(entry: dict) -> list[tuple]:
    rows = []
    for h in entry.get("haps") or []:
        rows.append((h[0] or "", h[1] or "", h[2], h[3], canon(h[4])))
    return sorted(rows, key=lambda r: (frac(r[0]), frac(r[1]), frac(r[2]), frac(r[3]), r[4]))


def mine_rows(entry: dict) -> list[tuple]:
    rows = [tuple(h) for h in entry.get("haps") or []]
    return sorted(rows, key=lambda r: (frac(r[0]), frac(r[1]), frac(r[2]), frac(r[3]), r[4]))


def frac(text: str) -> float:
    if not text:
        return -1e18
    a, _, b = text.partition("/")
    try:
        return int(a) / int(b)
    except (ValueError, ZeroDivisionError):
        return 0.0


def main() -> int:
    global GOLDEN, MINE
    only = ""
    verbose = False
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = arg[7:]
        elif arg == "--track":
            # Главная приёмка: целый трек вместо корпуса выражений.
            GOLDEN = HERE / "golden" / "track_haps.json"
            MINE = HERE / "golden" / "godot_track.json"
        elif arg == "--tunes":
            # Настоящие треки сообщества из коллекции Strudel.
            GOLDEN = HERE / "golden" / "tunes_haps.json"
            MINE = HERE / "golden" / "godot_tunes.json"
        elif arg in ("-v", "--verbose"):
            verbose = True

    if not GOLDEN.is_file():
        print(f"нет эталона: {GOLDEN}", file=sys.stderr)
        return 2
    if not MINE.is_file():
        print(f"нет выгрузки плагина: {MINE}\nсперва прогони run_corpus.gd", file=sys.stderr)
        return 2

    golden = json.loads(GOLDEN.read_text(encoding="utf-8"))
    mine = json.loads(MINE.read_text(encoding="utf-8"))

    same, differ, missing, both_error = [], [], [], []
    for cid, g in golden.items():
        if only and only not in cid:
            continue
        m = mine.get(cid)
        if m is None:
            missing.append((cid, "плагин не выдал результата"))
            continue
        g_err = "error" in g
        m_err = "error" in m
        if g_err and m_err:
            both_error.append(cid)
            continue
        if g_err != m_err:
            side = "плагин упал" if m_err else "плагин сыграл там, где Булка отказалась"
            reason = m.get("error", g.get("error", ""))
            missing.append((cid, f"{side}: {reason}"))
            continue

        gr = golden_rows(g)
        mr = mine_rows(m)
        if gr == mr:
            same.append(cid)
            continue

        detail = []
        if len(gr) != len(mr):
            detail.append(f"событий: Булка {len(gr)}, плагин {len(mr)}")
        for i in range(min(len(gr), len(mr))):
            if gr[i] != mr[i]:
                detail.append(f"  #{i} Булка  {gr[i][0]}..{gr[i][1]} {gr[i][4][:70]}")
                detail.append(f"      плагин {mr[i][0]}..{mr[i][1]} {mr[i][4][:70]}")
                if len(detail) > 7:
                    break
        differ.append((cid, detail))

    total = len(same) + len(differ) + len(missing) + len(both_error)
    print(f"[сверка] проверок {total}: совпало {len(same)}, "
          f"расходится {len(differ)}, не сыграно {len(missing)}, "
          f"обе стороны отказались {len(both_error)}")

    if differ:
        print("\nРАСХОЖДЕНИЯ:")
        for cid, detail in differ:
            print(f"  ✗ {cid}")
            for line in detail[:8]:
                print(f"      {line}")
    if missing:
        print("\nНЕ СЫГРАНО:")
        for cid, why in missing:
            print(f"  ✗ {cid}: {why}")
    if verbose and same:
        print("\nСОВПАЛО:")
        for cid in same:
            print(f"  ✓ {cid}")

    return 0 if not differ and not missing else 1


if __name__ == "__main__":
    raise SystemExit(main())
