@tool
extends StrudelTestBase

## Саундфонт. Файл в репозиторий не кладётся (десятки мегабайт), поэтому
## проверка идёт по любому .sf2, который найдётся: сперва рядом с проектом,
## потом по пути из переменной окружения STRUDEL_SF2.

func _find() -> String:
	var candidates := [
		"res://examples/soundfont/test.sf2",
		OS.get_environment("STRUDEL_SF2"),
		"D:/Projects/TEMP/aquarelle/audio/gu.sf2",
	]
	for path in candidates:
		if path != "" and FileAccess.file_exists(path):
			return path
	return ""


func test_саундфонт_читается_и_звучит() -> void:
	var path := _find()
	if path == "":
		# Файла нет — это не провал: проверка просто пропускается.
		check(true, "саундфонта не нашлось, проверка пропущена")
		return

	var sf := StrudelSoundFont.new()
	check(sf.load_file(path), "файл разобрался")
	check(sf.preset_count() > 0, "пресетов: %d" % sf.preset_count())
	check(sf.sample_count() > 0, "описаний звуков: %d" % sf.sample_count())

	var list := sf.programs()
	check(list.size() > 0, "список пресетов не пуст")
	var bank := int(list[0][0])
	var program := int(list[0][1])
	check(sf.has_preset(bank, program), "пресет %d:%d есть" % [bank, program])

	var low := sf.resolve(bank, program, 48.0)
	var high := sf.resolve(bank, program, 72.0)
	check(not low.is_empty(), "нота 48 нашлась")
	check(not high.is_empty(), "нота 72 нашлась")
	check(low["data"].size() > 0, "отсчёты есть")
	check(float(low["rate"]) > 1000.0, "частота осмысленная: %f" % low["rate"])

	# Несуществующий пресет не должен ронять.
	check(sf.resolve(99, 999, 60.0).is_empty(), "неизвестный пресет даёт пустоту")


func test_битый_файл_не_роняет() -> void:
	var sf := StrudelSoundFont.new()
	check(not sf.load_file("res://project.godot"), "не-саундфонт отвергнут")
	check(not sf.loaded, "и не считается загруженным")
	check(sf.resolve(0, 0, 60.0).is_empty(), "запрос к пустому даёт пустоту")
