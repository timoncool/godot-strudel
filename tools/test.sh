#!/usr/bin/env bash
# Прогон тестов плагина. ВСЕГДА через переимпорт: Godot держит реестр
# глобальных классов в .godot и без пересканирования новый class_name
# «не объявлен», хотя файл на месте.
set -u
GODOT="${GODOT:-/d/Programs/Godot/Godot_v4.7.1-stable_win64_console.exe}"
PROJ="D:/Projects/TEMP/godot-strudel"
LOG="$PROJ/tools/judge/tests.log"

"$GODOT" --headless --path "$PROJ" --import > "$PROJ/tools/judge/import.log" 2>&1
"$GODOT" --headless --path "$PROJ" --script res://tests/run_tests.gd "$@" > "$LOG" 2>&1
code=$?

errs=$(grep -c "SCRIPT ERROR" "$LOG")
grep -E "^  [✓✗]" "$LOG"
sed -n '/\[тесты\]/,$p' "$LOG"
if [ "$errs" -gt 0 ]; then
  echo ""
  echo "!! ошибок движка: $errs — вывод целиком в $LOG"
  grep -B1 -A3 "SCRIPT ERROR" "$LOG" | head -40
  exit 1
fi
exit $code
