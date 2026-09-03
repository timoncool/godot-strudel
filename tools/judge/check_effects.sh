#!/usr/bin/env bash
# Сверка КАЖДОГО узла цепи эффектов с эталоном из Булки.
#
# Эталон снимается офлайн-рендером самой Булки и лежит в golden/fx_<id>.wav
# (см. tools/judge/README.md). Здесь то же самое рендерится плагином и
# сравнивается по уровню и спектру.
#
#   bash tools/judge/check_effects.sh
set -u

GODOT="${GODOT:-/d/Programs/Godot/Godot_v4.7.1-stable_win64_console.exe}"
PROJ="D:/Projects/TEMP/godot-strudel"
HERE="$PROJ/tools/judge"
GOLD="$HERE/golden"

python - <<'PY' > /tmp/fx_list.txt
import json, pathlib
items = json.loads(pathlib.Path(r"D:/Projects/TEMP/godot-strudel/tools/judge/effects.json").read_text(encoding="utf-8"))
for it in items:
    print(it["id"] + "\t" + it["expr"])
PY

fail=0
printf '%-20s %10s %10s %s\n' "узел" "СКЗ, дБ" "пик, дБ" "спектр: худшая полоса"
printf '%s\n' "--------------------------------------------------------------------------"

while IFS=$'\t' read -r id expr; do
  ref="$GOLD/fx_$id.raw"
  [ -f "$ref" ] || ref="$GOLD/fx_$id.wav"
  if [ ! -f "$ref" ]; then
    printf '%-20s %s\n' "$id" "нет эталона — пропущен"
    continue
  fi
  wav="$GOLD/fx_${id}_ref.wav"
  cp "$ref" "$wav"
  mine="$GOLD/fx_${id}_godot.wav"
  "$GODOT" --headless --path "$PROJ" --script res://tools/render_wav.gd -- \
     --code="\$: $expr" --out="$(echo "$mine" | sed 's|/d/|D:/|')" --seconds=4 --cpm=30 \
     > /tmp/fx_render.log 2>&1
  if [ ! -f "$mine" ]; then
    printf '%-20s %s\n' "$id" "ПЛАГИН НЕ СЫГРАЛ"
    fail=$((fail+1))
    continue
  fi
  out=$(PYTHONIOENCODING=utf-8 python "$HERE/compare_audio.py" "$wav" "$mine" 2>&1)
  rms=$(echo "$out" | sed -n 's/.*СКЗ:.*разница \([+-][0-9.]*\) дБ.*/\1/p')
  peak=$(echo "$out" | sed -n 's/.*пик:.*разница \([+-][0-9.]*\) дБ.*/\1/p')
  worst=$(echo "$out" | sed -n 's/.*разница *\([+-][0-9.]*\)$/\1/p' | sort -g | awk 'NR==1{lo=$1} {hi=$1} END{if (-lo>hi) print lo; else print hi}')
  printf '%-20s %10s %10s %s\n' "$id" "$rms" "$peak" "$worst"
done < /tmp/fx_list.txt

exit $fail
