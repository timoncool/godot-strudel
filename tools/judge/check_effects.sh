#!/usr/bin/env bash
# Сверка КАЖДОГО узла цепи эффектов с эталоном из Булки.
#
# Эталон снимается офлайн-рендером самой Булки и лежит в golden/fx_<id>.wav
# (см. tools/judge/README.md). Здесь то же самое рендерится плагином и
# сравнивается по уровню и спектру.
#
#   bash tools/judge/check_effects.sh
#
# 🔴 ГЕЙТ ОБЯЗАН КРАСНЕТЬ. Раньше он числа только ПЕЧАТАЛ: `fail` рос ровно в
# одном месте — когда плагин не создал файл, — а отсутствие эталона считалось
# «пропущен» и провалом не было. На свежем клоне, где звуковых эталонов нет по
# построению (README.md), выходило сорок одно «пропущено» и код возврата ноль:
# сорок один замер, ноль сравнений, зелено. И при живом расхождении в шесть
# децибел он тоже выходил нулём. Теперь каждое число сверяется с порогом
# (`fx_verdict.py`), а отсутствие эталона — провал, а не пропуск.
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
checked=0
ungated=0
printf '%-20s %10s %10s %10s  %s\n' "узел" "СКЗ, дБ" "пик, дБ" "полоса" "приговор"
printf '%s\n' "------------------------------------------------------------------------------------"

while IFS=$'\t' read -r id expr; do
  ref="$GOLD/fx_$id.raw"
  [ -f "$ref" ] || ref="$GOLD/fx_$id.wav"
  if [ ! -f "$ref" ]; then
    # Эталона нет — сравнивать НЕЧЕМ, и это провал. Раньше тут стоял `continue`
    # без счётчика, и пустой прогон выглядел успешным.
    printf '%-20s %10s %10s %10s  %s\n' "$id" "-" "-" "-" "НЕТ ЭТАЛОНА"
    fail=$((fail+1))
    continue
  fi
  wav="$GOLD/fx_${id}_ref.wav"
  cp "$ref" "$wav"
  mine="$GOLD/fx_${id}_godot.wav"
  "$GODOT" --headless --path "$PROJ" --script res://tools/render_wav.gd -- \
     --code="\$: $expr" --out="$(echo "$mine" | sed 's|/d/|D:/|')" --seconds=4 --cpm=30 \
     > /tmp/fx_render.log 2>&1
  if [ ! -f "$mine" ]; then
    printf '%-20s %10s %10s %10s  %s\n' "$id" "-" "-" "-" "ПЛАГИН НЕ СЫГРАЛ"
    fail=$((fail+1))
    continue
  fi
  out=$(PYTHONIOENCODING=utf-8 python "$HERE/compare_audio.py" "$wav" "$mine" 2>&1)
  rms=$(echo "$out" | sed -n 's/.*СКЗ:.*разница \([+-][0-9.]*\) дБ.*/\1/p')
  peak=$(echo "$out" | sed -n 's/.*пик:.*разница \([+-][0-9.]*\) дБ.*/\1/p')
  worst=$(echo "$out" | sed -n 's/.*разница *\([+-][0-9.]*\)$/\1/p' | sort -g | awk 'NR==1{lo=$1} {hi=$1} END{if (-lo>hi) print lo; else print hi}')
  verdict=$(PYTHONIOENCODING=utf-8 python "$HERE/fx_verdict.py" "$id" "$rms" "$peak" "$worst")
  code=$?
  # 0 — сошлось, 1 — вышло за порог, 2 — числом не сверяется (случайность
  # в самом узле). Третий случай в число сверенных НЕ идёт: иначе итог врёт.
  if [ "$code" -eq 1 ]; then
    fail=$((fail+1))
    checked=$((checked+1))
  elif [ "$code" -eq 2 ]; then
    ungated=$((ungated+1))
  else
    checked=$((checked+1))
  fi
  printf '%-20s %10s %10s %10s  %s\n' "$id" "$rms" "$peak" "$worst" "$verdict"
done < /tmp/fx_list.txt

printf '%s\n' "------------------------------------------------------------------------------------"
printf '[эффекты] ИТОГ: сверено %d, вышли за порог %d, числом не сверяются %d
' "$checked" "$fail" "$ungated"
exit $fail
