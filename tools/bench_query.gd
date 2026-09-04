@tool
extends SceneTree

## Замер цены запроса паттерна: где именно уходит время.
##
##   godot --headless --path <проект> --script res://tools/bench_query.gd

const TRACK := "res://examples/04_full_track/track/kuvshinka.js"


func _init() -> void:
	_bench_fractions()
	_bench_simple()
	_bench_track()
	quit(0)


func _bench_fractions() -> void:
	var n := 200000
	var a := StrudelFraction.new("23/800")
	var b := StrudelFraction.new("1/3")

	var t := Time.get_ticks_usec()
	for i in n:
		var _x := a.add(b)
	var add_us := float(Time.get_ticks_usec() - t) / float(n)

	t = Time.get_ticks_usec()
	for i in n:
		var _x := a.mul(b)
	var mul_us := float(Time.get_ticks_usec() - t) / float(n)

	t = Time.get_ticks_usec()
	for i in n:
		var _x := a.compare(b)
	var cmp_us := float(Time.get_ticks_usec() - t) / float(n)

	t = Time.get_ticks_usec()
	for i in n:
		var _x := StrudelFraction.new(0)
	var new_us := float(Time.get_ticks_usec() - t) / float(n)

	print("[дроби] сложение %.3f мкс, умножение %.3f мкс, сравнение %.3f мкс, создание %.3f мкс"
		% [add_us, mul_us, cmp_us, new_us])


func _bench_simple() -> void:
	var run: Dictionary = StrudelRuntime.run('s("bd sd*2 ~ hh")')
	var pat: StrudelPattern = run["pattern"]
	var t := Time.get_ticks_usec()
	var cycles := 200
	var events := 0
	for c in cycles:
		events += pat.query_arc(c, c + 1).size()
	var per := float(Time.get_ticks_usec() - t) / float(cycles) / 1000.0
	print("[простой] s(\"bd sd*2 ~ hh\"): %.3f мс на цикл, событий %d" % [per, events / cycles])


func _bench_track() -> void:
	var f := FileAccess.open(TRACK, FileAccess.READ)
	if f == null:
		return
	var code := f.get_as_text()
	f.close()

	var t0 := Time.get_ticks_usec()
	var run: Dictionary = StrudelRuntime.run(code)
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if not run.get("ok", false):
		printerr("[трек] не собрался")
		return
	var pat: StrudelPattern = run["pattern"]

	# прогрев: первый запрос всегда дороже
	pat.query_arc(0, 1)

	var t := Time.get_ticks_usec()
	var cycles := 16
	var events := 0
	for c in cycles:
		events += pat.query_arc(c, c + 1).size()
	var per := float(Time.get_ticks_usec() - t) / float(cycles) / 1000.0
	print("[трек] сборка %.1f мс; запрос %.2f мс на цикл, событий на цикл %d"
		% [build_ms, per, events / cycles])

	# сколько стоит запрос ПОЛОВИНЫ цикла — так спрашивает планировщик
	t = Time.get_ticks_usec()
	for c in cycles * 2:
		pat.query_arc(c * 0.5, c * 0.5 + 0.5)
	var per_half := float(Time.get_ticks_usec() - t) / float(cycles * 2) / 1000.0
	print("[трек] запрос половины цикла: %.2f мс (планировщик спрашивает так)" % per_half)
