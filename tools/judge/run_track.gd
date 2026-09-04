@tool
extends SceneTree

## Главная приёмка: целый трек из Strudel играет в Godot от начала до конца.
##
##   godot --headless --path <проект> --script res://tools/judge/run_track.gd
##
## Файл трека берётся КАК ЕСТЬ — тот же самый, что скормлен Булке.
## Выгружает события всех 64 циклов для посекундной сверки.

const TRACK := "res://examples/04_full_track/track/kuvshinka.js"
const OUT := "res://tools/judge/golden/godot_track.json"
const CYCLES := 64


func _init() -> void:
	var f := FileAccess.open(TRACK, FileAccess.READ)
	if f == null:
		printerr("[трек] не прочитал ", TRACK)
		quit(1)
		return
	var code := f.get_as_text()
	f.close()

	var t_parse := Time.get_ticks_usec()
	var run: Dictionary = StrudelRuntime.run(code)
	var parse_ms := (Time.get_ticks_usec() - t_parse) / 1000.0
	if not run.get("ok", false):
		printerr("[трек] не собрался: ", run.get("error", "?"))
		quit(1)
		return

	var pat: StrudelPattern = run["pattern"]
	var cps: float = run.get("cps", 0.5)

	var t_query := Time.get_ticks_usec()
	var rows: Array = []
	# 🔴 ОДИН запрос на все круги, а не по кругу за раз: покруговая выборка
	# режет события, чьё «целое» переходит через границу круга. Эталон снят
	# ровно так же — `queryArc(0, CYCLES)` одним вызовом.
	for hap in pat.query_arc(0, CYCLES):
		rows.append([
			"" if hap.whole == null else hap.whole.begin.show(),
			"" if hap.whole == null else hap.whole.end.show(),
			hap.part.begin.show(),
			hap.part.end.show(),
			_canon(hap.value),
		])
	var query_ms := (Time.get_ticks_usec() - t_query) / 1000.0

	var out := FileAccess.open(OUT, FileAccess.WRITE)
	out.store_string(JSON.stringify({"track/kuvshinka": {"n": rows.size(), "haps": rows}}, "", false))
	out.close()

	print("[трек] событий %d за %d циклов" % [rows.size(), CYCLES])
	print("[трек] сборка паттерна %.1f мс, выборка событий %.1f мс (%.2f мс на цикл)"
		% [parse_ms, query_ms, query_ms / CYCLES])
	print("[трек] темп %.4f цикла в секунду, длительность %.1f с" % [cps, CYCLES / cps])
	quit(0)


func _canon(v: Variant) -> String:
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is int or v is float:
		return "#" + PackedFloat64Array([float(v)]).to_byte_array().hex_encode()
	if v is String or v is StringName:
		return JSON.stringify(String(v))
	if v is Array:
		var items: Array[String] = []
		for x in v:
			items.append(_canon(x))
		return "[" + ",".join(items) + "]"
	if v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		keys.sort()
		var pairs: Array[String] = []
		for k in keys:
			pairs.append(JSON.stringify(String(k)) + ":" + _canon((v as Dictionary)[k]))
		return "{" + ",".join(pairs) + "}"
	return JSON.stringify(str(v))
