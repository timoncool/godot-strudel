@tool
extends SceneTree

## Чего из ПУБЛИЧНОГО API Strudel плагин не знает.
##
##   python tools/judge/api_list.py --json
##   godot --headless --path <проект> --script res://tools/judge/check_coverage.gd
##
## Список снят с исходников Булки (`register`, `registerControl`,
## `Pattern.prototype`) — без редактора, DOM и датчиков телефона, которых в
## движке нет и быть не должно. Каждое имя пробуется методом на паттерне и
## глобальной функцией; печатается то, на что плагин отвечает «не знаю».

const API := "res://tools/judge/golden/api.json"
const OUT := "res://tools/judge/golden/coverage.json"


func _init() -> void:
	var f := FileAccess.open(API, FileAccess.READ)
	if f == null:
		printerr("[охват] нет ", API, " — сперва python tools/judge/api_list.py --json")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var pat := StrudelPattern.pure(1)
	var arg := StrudelPattern.pure(1)
	var missing_fn: Array[String] = []
	var missing_ctrl: Array[String] = []

	for name in data.get("functions", []):
		var n := String(name)
		if not _known_method(pat, n, arg):
			missing_fn.append(n)
	for name in data.get("controls", []):
		var n := String(name)
		if not StrudelControls.is_control(n):
			missing_ctrl.append(n)

	missing_fn.sort()
	missing_ctrl.sort()
	var out := FileAccess.open(OUT, FileAccess.WRITE)
	out.store_string(JSON.stringify({"functions": missing_fn, "controls": missing_ctrl}, " "))
	out.close()
	print("[охват] функций знаю %d из %d, параметров %d из %d"
		% [data.get("functions", []).size() - missing_fn.size(), data.get("functions", []).size(),
			data.get("controls", []).size() - missing_ctrl.size(), data.get("controls", []).size()])
	print("[охват] НЕТ функций (%d): %s" % [missing_fn.size(), ", ".join(missing_fn)])
	print("[охват] НЕТ параметров (%d): %s" % [missing_ctrl.size(), ", ".join(missing_ctrl)])
	quit(0)


func _known_method(pat: StrudelPattern, name: String, arg: StrudelPattern) -> bool:
	# Пробуем и без довода, и с ним: часть имён без довода законно молчит.
	for args in [[], [arg], [arg, arg]]:
		var r: Variant = StrudelStdlib.method_call(null, pat, name, args)
		if not (r is Dictionary and (r as Dictionary).get("__unknown", false)):
			return true
	return false
