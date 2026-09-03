"""Подробная разница по ОДНОМУ треку: что есть только у Булки, что только у плагина.

    python tools/judge/tune_diff.py giantSteps [сколько_строк]

Сверка `compare.py` says только «расходится»; здесь видно, ЧЕМ именно.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare import canon  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

H = Path(__file__).resolve().parent / "golden"


def main() -> int:
    name = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    ref = json.loads((H / "tunes_haps.json").read_text(encoding="utf-8"))[name]
    mine = json.loads((H / "godot_tunes.json").read_text(encoding="utf-8"))[name]
    if "error" in ref:
        print("Булка отказалась:", ref["error"])
    R = sorted((h[0], h[1], h[2], h[3], canon(h[4])) for h in ref.get("haps") or [])
    M = sorted(tuple(h) for h in mine.get("haps") or [])
    print(f"{name}: Булка {len(R)}, плагин {len(M)}")
    only_r = [r for r in R if r not in M]
    only_m = [m for m in M if m not in R]
    for title, rows in (("только у Булки", only_r), ("только у плагина", only_m)):
        print(f"  {title}: {len(rows)}")
        for r in rows[:limit]:
            print(f"    {r[0]:>7}..{r[1]:<7} part {r[2]:>7}..{r[3]:<8} {r[4]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
