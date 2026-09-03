@tool
extends StrudelTestBase

## Сэмплер: чужая папка, карты формата Strudel, многосэмплированный инструмент.
##
## Пак не лежит в репозитории готовым — он синтезируется скриптом
## examples/04_own_samples/make_pack.py, чтобы ни одного чужого звука в
## поставке не было и чтобы проверка не зависела от сети.

const PACK_DIR := "res://examples/04_own_samples"


func _bank() -> StrudelSampleBank:
	var bank := StrudelSampleBank.new()
	bank.load_folder(ProjectSettings.globalize_path(PACK_DIR))
	return bank


func test_карта_формата_strudel_читается() -> void:
	var bank := _bank()
	check(not bank.is_empty(), "банк не пуст: %d имён" % bank.count())
	for name in ["bd", "sd", "hh", "bell"]:
		check(bank.entries.has(name), "имя \"%s\" на месте" % name)


func test_индекс_выбирает_нужный_файл() -> void:
	# "bd:0" и "bd:1" — РАЗНЫЕ файлы, а "bd:2" заворачивается обратно на первый.
	var bank := _bank()
	var a := bank.resolve("bd", 0, "", 60.0)
	var b := bank.resolve("bd", 1, "", 60.0)
	var c := bank.resolve("bd", 2, "", 60.0)
	check(not a.is_empty() and not b.is_empty(), "оба файла нашлись")
	check(a["data"].size() != b["data"].size(), "и это разные звуки")
	eq(c["data"].size(), a["data"].size(), "индекс за пределами заворачивается")


func test_многосэмплированный_берёт_ближайшую_высоту() -> void:
	# Записаны C3 (48), G3 (55) и C4 (60). Нота D3 (50) обязана взять C3
	# и растянуться вверх, а A3 (57) — взять G3.
	var bank := _bank()
	var c3 := bank.resolve("bell", 0, "", 48.0)
	var d3 := bank.resolve("bell", 0, "", 50.0)
	var a3 := bank.resolve("bell", 0, "", 57.0)

	check(not c3.is_empty(), "C3 нашлась")
	eq_num(float(c3["speed"]), 1.0, 0.0001, "на записанной высоте растяжки нет")
	eq_num(float(d3["speed"]), pow(2.0, 2.0 / 12.0), 0.0001, "D3 = C3, растянутая на два полутона")
	eq_num(float(a3["speed"]), pow(2.0, 2.0 / 12.0), 0.0001, "A3 = G3, тоже на два полутона")
	eq(d3["data"].size(), c3["data"].size(), "D3 взяла файл C3")


func test_звучит_из_чужого_банка() -> void:
	var run: Dictionary = StrudelRuntime.run('setcpm(120/4)\n$: s("bd sd bd hh")')
	check(run.get("ok", false), "код собрался")
	var e := StrudelEngine.new()
	e.setup(48000.0)
	e.bank = _bank()
	e.set_pattern(run["pattern"])
	e.set_cps(0.5)
	var peak := 0.0
	for b in 16:
		var chunk: Array = e.render_block(4096)
		var l: PackedFloat32Array = chunk[0]
		for i in l.size():
			peak = maxf(peak, absf(l[i]))
	check(peak > 0.01, "чужой банк звучит, пик %f" % peak)


func test_wav_разбирается_в_отсчёты() -> void:
	var bank := _bank()
	var picked := bank.resolve("sd", 0, "", 60.0)
	check(not picked.is_empty(), "снейр нашёлся")
	var data: PackedFloat32Array = picked["data"]
	check(data.size() > 1000, "отсчётов много: %d" % data.size())
	eq_num(float(picked["rate"]), 44100.0, 1.0, "частота файла прочитана")
	var peak := 0.0
	for v in data:
		peak = maxf(peak, absf(v))
	check(peak > 0.2 and peak <= 1.0, "значения в разумных пределах, пик %f" % peak)
