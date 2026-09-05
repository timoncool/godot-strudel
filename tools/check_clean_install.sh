#!/usr/bin/env bash
# Проверка установки С НУЛЯ: пустой проект Godot → копируется addons/strudel →
# включается → сцена играет.
#
# Это отдельная проверка не для галочки: в своём проекте плагин работает уже
# потому, что всё под рукой. Чужой пользователь получает ТОЛЬКО папку addons,
# и любая забытая зависимость (пример, инструмент, картинка) вылезет здесь.
#
#   bash tools/check_clean_install.sh
set -u

GODOT="${GODOT:-/d/Programs/Godot/Godot_v4.7.1-stable_win64_console.exe}"
# 🔴 КОРЕНЬ СЧИТАЕТСЯ ОТ СКРИПТА, А НЕ ЗАШИТ. Здесь стоял путь моей машины
# (`D:/Projects/...`), и на линуксовом раннере CI шаг падал: `cp: cannot
# stat` — плагин не копировался, проверка «размер поставки» показывала
# ноль файлов. Локально это не всплывало никогда.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/strudel_clean_$$"
# 🔴 ЗАПАСНОЙ ВАРИАНТ ПОСЛЕ КОНВЕЙЕРА НЕ СРАБАТЫВАЕТ. Здесь стояло
# `cygpath … | sed … || echo "$TMP"`, но код возврата у конвейера — от
# ПОСЛЕДНЕЙ команды: на линуксовом раннере `cygpath` нет, `sed` спокойно
# отрабатывает на пустом входе и отдаёт ноль, `||` не срабатывает — и путь
# выходил ПУСТОЙ. Godot отвечал `Invalid project path specified: ""`, шаг CI
# падал, а в логе об этом не было ни слова. Проверяем наличие команды явно.
if command -v cygpath >/dev/null 2>&1; then
  WIN_TMP=$(cygpath -w "$TMP" | sed 's|\\|/|g')
else
  WIN_TMP="$TMP"
fi
if [ -z "$WIN_TMP" ]; then
  echo "[чисто] путь к проекту пуст — дальше идти некуда"
  exit 1
fi

echo "[чисто] пустой проект: $TMP"
rm -rf "$TMP"
mkdir -p "$TMP/addons"

# 1. Пользователь копирует ТОЛЬКО папку плагина
cp -r "$SRC/addons/strudel" "$TMP/addons/strudel"

# 2. И заводит проект
cat > "$TMP/project.godot" <<'EOF'
config_version=5

[application]
config/name="Чистая проверка"
config/features=PackedStringArray("4.7")

[editor_plugins]
enabled=PackedStringArray("res://addons/strudel/plugin.cfg")
EOF

# 3. Пишет три строки — как в README
mkdir -p "$TMP/scene"
cat > "$TMP/scene/main.gd" <<'EOF'
extends SceneTree

func _init() -> void:
	var run: Dictionary = StrudelRuntime.run('setcpm(120/4)\n$: s("bd sd*2, ~ hh").gain(0.8)')
	if not run.get("ok", false):
		printerr("[чисто] код не разобрался: ", run.get("error", "?"))
		quit(1)
		return
	var pattern: StrudelPattern = run["pattern"]
	var events := pattern.query_arc(0, 4).size()

	# И слышит звук: считаем его без звуковой карты.
	var engine := StrudelEngine.new()
	engine.setup(48000.0)
	engine.set_pattern(pattern)
	engine.set_cps(run.get("cps", 0.5))
	var peak := 0.0
	for block in 24:
		var chunk: Array = engine.render_block(4096)
		var l: PackedFloat32Array = chunk[0]
		for i in l.size():
			peak = maxf(peak, absf(l[i]))

	print("[чисто] событий за 4 цикла: %d, пик звука: %.4f" % [events, peak])
	if events < 8:
		printerr("[чисто] событий слишком мало")
		quit(1)
		return
	if peak < 1e-4:
		printerr("[чисто] ТИШИНА")
		quit(1)
		return
	print("[чисто] ОК — плагин работает в пустом проекте")
	quit(0)
EOF

"$GODOT" --headless --path "$WIN_TMP" --import > "$TMP/import.log" 2>&1
code_import=$?
errors=$(grep -cE "SCRIPT ERROR|Failed to load" "$TMP/import.log")
if [ "$errors" -gt 0 ]; then
  echo "[чисто] ПРИ ИМПОРТЕ ОШИБКИ ($errors):"
  grep -E "SCRIPT ERROR|Failed to load" "$TMP/import.log" | head -10
  exit 1
fi

"$GODOT" --headless --path "$WIN_TMP" --script res://scene/main.gd > "$TMP/run.log" 2>&1
code_run=$?
grep -E "^\[чисто\]" "$TMP/run.log" || true
if grep -q "SCRIPT ERROR" "$TMP/run.log"; then
  echo "[чисто] ОШИБКИ ДВИЖКА:"
  grep -A3 "SCRIPT ERROR" "$TMP/run.log" | head -20
  exit 1
fi
# 🔴 МОЛЧАНИЕ — ТОЖЕ ПРОВАЛ, И ОНО ДОЛЖНО БЫТЬ ГОВОРЯЩИМ. Раньше проверка
# держалась на кодах возврата grep: не нашлось ни одной строки — шаг падал, а
# в логе оставались только «размер поставки» и `exit code 1`, по которым
# причину не установить. Теперь печатается хвост запуска.
if ! grep -q "ОК — плагин работает" "$TMP/run.log"; then
  echo "[чисто] ПРОВАЛ: проверка не отчиталась (код запуска $code_run)."
  echo "[чисто] последние строки запуска:"
  tail -30 "$TMP/run.log"
  echo "[чисто] последние строки импорта:"
  tail -10 "$TMP/import.log"
  exit 1
fi

# 4. Снятие галочки не должно ничего ломать: выключаем и проверяем ещё раз
sed -i 's|^enabled=.*|enabled=PackedStringArray()|' "$TMP/project.godot"
"$GODOT" --headless --path "$WIN_TMP" --import > "$TMP/import2.log" 2>&1
if grep -qE "SCRIPT ERROR|Failed to load" "$TMP/import2.log"; then
  echo "[чисто] после ВЫКЛЮЧЕНИЯ плагина проект сломался:"
  grep -E "SCRIPT ERROR|Failed to load" "$TMP/import2.log" | head -5
  exit 1
fi
echo "[чисто] выключение плагина проект не ломает"

size=$(du -sh "$TMP/addons/strudel" | cut -f1)
files=$(find "$TMP/addons/strudel" -type f | wc -l)
echo "[чисто] размер поставки: $size, файлов: $files"

rm -rf "$TMP"
exit $code_run
