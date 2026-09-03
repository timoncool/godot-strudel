@tool
extends SceneTree

## Проверка саундфонта: заголовки читаются, ноты звучат, память не раздувается.
##
##   godot --headless --path <проект> --script res://tools/check_soundfont.gd -- --sf2=<файл>

var _path := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sf2="):
			_path = arg.substr(6)
	if _path == "":
		printerr("[саундфонт] нужен --sf2=<файл>")
		quit(1)
		return

	var before := OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	var sf := StrudelSoundFont.new()
	if not sf.load_file(_path):
		printerr("[саундфонт] не прочитался")
		quit(1)
		return
	var load_ms := (Time.get_ticks_usec() - started) / 1000.0
	var after_headers := OS.get_static_memory_usage()

	print("[саундфонт] %s" % _path.get_file())
	print("[саундфонт] пресетов %d, описаний звуков %d, заголовки за %.0f мс"
		% [sf.preset_count(), sf.sample_count(), load_ms])
	print("[саундфонт] память под заголовки: %.1f МБ"
		% ((after_headers - before) / 1048576.0))

	var list := sf.programs()
	var shown: Array[String] = []
	for i in mini(8, list.size()):
		shown.append("%d:%d" % [list[i][0], list[i][1]])
	print("[саундфонт] первые пресеты: %s" % ", ".join(shown))

	# Достаём несколько нот одного пресета — так проверяется ленивая загрузка.
	var bank := int(list[0][0])
	var program := int(list[0][1])
	var got := 0
	for note in [48.0, 55.0, 60.0, 67.0, 72.0]:
		var picked := sf.resolve(bank, program, note)
		if picked.is_empty():
			continue
		got += 1
		if got == 1:
			print("[саундфонт] нота %d: отсчётов %d, частота %d Гц, растяжка %.4f, петля %s"
				% [int(note), picked["data"].size(), int(picked["rate"]),
				   float(picked["speed"]), "да" if picked["loop"] else "нет"])
	print("[саундфонт] нот достали: %d из 5" % got)
	var after_notes := OS.get_static_memory_usage()
	print("[саундфонт] память после пяти нот: %.1f МБ (весь файл — %.1f МБ)"
		% [(after_notes - before) / 1048576.0, FileAccess.get_file_as_bytes(_path).size() / 1048576.0])

	# И звучит ли это в тракте
	var run: Dictionary = StrudelRuntime.run(
		'$: note("c3 e3 g3").s("sf:%d:%d").gain(0.7)' % [bank, program])
	if not run.get("ok", false):
		printerr("[саундфонт] код не собрался: ", run.get("error", "?"))
		quit(1)
		return
	var engine := StrudelEngine.new()
	engine.setup(48000.0)
	engine.soundfont = sf
	engine.set_pattern(run["pattern"])
	engine.set_cps(0.5)
	var peak := 0.0
	for b in 24:
		var chunk: Array = engine.render_block(4096)
		var l: PackedFloat32Array = chunk[0]
		for i in l.size():
			peak = maxf(peak, absf(l[i]))
	print("[саундфонт] событий %d, пик звука %.4f" % [engine.played_events, peak])
	if peak < 1e-4:
		printerr("[саундфонт] ТИШИНА")
		quit(1)
		return
	print("[саундфонт] ОК")
	quit(0)
