@tool
extends SceneTree

## ГЛАВНАЯ ПРИЁМКА: настоящие треки сообщества играют в Godot.
##
##   godot --headless --path <проект> --script res://tools/judge/run_tunes.gd
##
## Треки взяты из коллекции Strudel (`website/src/repl/tunes.mjs`) КАК ЕСТЬ,
## без единой правки: giantSteps, caverave, bassFuge, amensister, flatrave и
## далее. Каждый читается из examples/tunes/, исполняется и выгружается для
## сверки с эталоном, снятым с живой Булки.

const LIST := "res://tools/judge/tunes.json"
const OUT := "res://tools/judge/golden/godot_tunes.json"


func _init() -> void:
	var f := FileAccess.open(LIST, FileAccess.READ)
	if f == null:
		printerr("[треки] не прочитал ", LIST)
		quit(1)
		return
	var index: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not index is Array:
		printerr("[треки] список не разобрался")
		quit(1)
		return

	var results: Dictionary = {}
	var played := 0
	var broken: Array[String] = []
	var total_events := 0
	var total_build := 0.0
	var total_query := 0.0

	for item in index:
		var id := String(item["id"])
		var path := "res://" + String(item["file"])
		var src := FileAccess.open(path, FileAccess.READ)
		if src == null:
			results[id] = {"error": "файла нет"}
			broken.append(id + ": файла нет")
			continue
		var code := src.get_as_text()
		src.close()

		var t0 := Time.get_ticks_usec()
		var run: Dictionary = StrudelRuntime.run(code)
		total_build += (Time.get_ticks_usec() - t0) / 1000.0
		if not run.get("ok", false):
			var why := String(run.get("error", "?"))
			results[id] = {"error": why}
			broken.append(id + ": " + why)
			continue

		var pat: StrudelPattern = run["pattern"]
		var rows: Array = []
		var t1 := Time.get_ticks_usec()
		# 🔴 ОДИН запрос на восемь кругов, а не восемь по кругу. Покруговая
		# выборка режет события, чьё «целое» переходит через границу круга,
		# на две доли — и сверка краснела на верных значениях. Эталон снят
		# ровно так же: `queryArc(0, 8)` одним вызовом.
		for hap in pat.query_arc(0, 8):
			rows.append([
				"" if hap.whole == null else hap.whole.begin.show(),
				"" if hap.whole == null else hap.whole.end.show(),
				hap.part.begin.show(),
				hap.part.end.show(),
				_canon(hap.value),
			])
		total_query += (Time.get_ticks_usec() - t1) / 1000.0
		results[id] = {"n": rows.size(), "haps": rows}
		played += 1
		total_events += rows.size()
		print("[треки] %-20s событий %4d" % [id, rows.size()])

	var out := FileAccess.open(OUT, FileAccess.WRITE)
	out.store_string(JSON.stringify(results, "", false))
	out.close()

	print("")
	print("[треки] ИТОГ: сыграло %d из %d, событий всего %d"
		% [played, index.size(), total_events])
	print("[треки] сборка всех паттернов %.0f мс, выборка событий %.0f мс"
		% [total_build, total_query])
	if not broken.is_empty():
		print("")
		print("[треки] НЕ СЫГРАЛИ:")
		for line in broken:
			print("    " + line)
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
