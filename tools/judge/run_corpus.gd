@tool
extends SceneTree

## Прогон корпуса через плагин и выгрузка событий для сверки с эталоном.
##
##   godot --headless --path <проект> --script res://tools/judge/run_corpus.gd
##
## Каждое выражение корпуса — это код Strudel КАК ЕСТЬ, без правок: тем самым
## проверяется не только ядро, но и то, ради чего плагин делается.
##
## Числа выгружаются БИТАМИ (IEEE754). Десятичная запись здесь не годится:
## String.num на восемнадцати знаках ошибается сам, и сверка краснела бы на
## верных значениях.

const CORPUS := "res://tools/judge/corpus.json"
const OUT := "res://tools/judge/golden/godot.json"


func _init() -> void:
	var corpus: Variant = _read_json(CORPUS)
	if corpus == null:
		printerr("[корпус] не прочитал ", CORPUS)
		quit(1)
		return

	var results: Dictionary = {}
	var ok := 0
	var failed := 0
	var started := Time.get_ticks_usec()

	for entry in corpus:
		var id := String(entry["id"])
		var expr := String(entry["expr"])
		var from_time: float = float(entry.get("from", 0))
		var to_time: float = float(entry.get("to", 1))

		var run: Dictionary = StrudelRuntime.run(expr)
		if not run.get("ok", false):
			results[id] = {"error": String(run.get("error", "?"))}
			failed += 1
			continue
		var pat: StrudelPattern = run["pattern"]
		var rows: Array = []
		for hap in pat.query_arc(from_time, to_time):
			rows.append([
				"" if hap.whole == null else hap.whole.begin.show(),
				"" if hap.whole == null else hap.whole.end.show(),
				hap.part.begin.show(),
				hap.part.end.show(),
				_canon(hap.value),
			])
		rows.sort_custom(_by_time)
		results[id] = {"n": rows.size(), "haps": rows}
		ok += 1

	var spent := (Time.get_ticks_usec() - started) / 1000.0
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		printerr("[корпус] не смог записать ", OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(results, "", false))
	f.close()

	print("[корпус] выражений %d, сыграно %d, не удалось %d, время %.0f мс"
		% [corpus.size(), ok, failed, spent])
	quit(0)


func _by_time(a: Array, b: Array) -> bool:
	for i in 4:
		if a[i] != b[i]:
			return _frac(a[i]) < _frac(b[i])
	return String(a[4]) < String(b[4])


func _frac(text: String) -> float:
	if text == "":
		return -1e18
	var bits := text.split("/")
	if bits.size() != 2:
		return 0.0
	return float(bits[0].to_int()) / float(bits[1].to_int())


func _canon(v: Variant) -> String:
	## Каноническая запись значения. Ключи словаря сортируются: их порядок
	## музыкального смысла не несёт, а различался бы на ровном месте.
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


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)
