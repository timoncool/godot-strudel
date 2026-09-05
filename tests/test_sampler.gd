@tool
extends StrudelTestBase

## Сэмплер: чужая папка, карты формата Strudel, многосэмплированный инструмент.
##
## Пак не лежит в репозитории готовым — он синтезируется скриптом
## examples/02_own_samples/make_pack.py, чтобы ни одного чужого звука в
## поставке не было и чтобы проверка не зависела от сети.

const PACK_DIR := "res://examples/02_own_samples"
## Второй пак — рояль примера «Пока горит окно»: карта нот в отдельной папке.
const PIANO_DIR := "res://examples/06_okno"


func _bank() -> StrudelSampleBank:
	var bank := StrudelSampleBank.new()
	bank.load_folder(ProjectSettings.globalize_path(PACK_DIR))
	return bank


func test_карта_формата_strudel_читается() -> void:
	var bank := _bank()
	check(not bank.is_empty(), "банк не пуст: %d имён" % bank.count())
	for name in ["bd", "sd", "hh", "bell"]:
		check(bank.entries.has(name), "имя \"%s\" на месте" % name)


func test_банк_копит_паки_а_не_подменяет() -> void:
	# 🔴 ДВА ПАКА ЖИВУТ В ОДНОМ БАНКЕ. В Strudel реестр звуков накопительный
	# (`soundMap.setKey`, `superdough/superdough.mjs:61`), и `samples()` зовут
	# по разу на пак. Здесь `load_folder` чистил банк, и второй вызов
	# ВЫБРАСЫВАЛ первый: рояль (2 имени) плюс барабаны (4) давали 4 вместо 6,
	# и трек с бочкой и роялем звучал наполовину.
	var bank := StrudelSampleBank.new()
	bank.load_folder(ProjectSettings.globalize_path(PIANO_DIR))
	var after_piano := bank.count()
	check(bank.entries.has("piano"), "рояль загрузился: %d имён" % after_piano)
	bank.load_folder(ProjectSettings.globalize_path(PACK_DIR))
	check(bank.entries.has("piano") and bank.entries.has("bd"),
		"после второго пака на месте оба: имён %d (было %d)"
		% [bank.count(), after_piano])
	check(bank.count() > after_piano,
		"банк вырос, а не подменился: %d > %d" % [bank.count(), after_piano])


func test_забыть_паки_можно_явно() -> void:
	# Чистка осталась, но отдельным действием — иначе её не отличить от долива.
	var bank := _bank()
	check(not bank.is_empty(), "банк набран: %d имён" % bank.count())
	bank.clear()
	check(bank.is_empty(), "после clear() банк пуст")


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
	# 🔴 ЧАСТОТА ТУТ СЕРВЕРНАЯ, А НЕ ФАЙЛОВАЯ. Сэмплы читаются штатным
	# трактом движка (импортированный ресурс, затем `AudioStreamWAV`), и он
	# сам пересчитывает на частоту звукового сервера. Раньше тут стояло 44100
	# — это была частота файла, которую отдавал наш собственный разборщик; он
	# теперь только последний запасной путь, и ждать от него первенства
	# нельзя: в СОБРАННОЙ игре исходных `.wav` нет вовсе, едут только
	# импортированные ресурсы.
	eq_num(float(picked["rate"]), AudioServer.get_mix_rate(), 1.0,
		"частота серверная, движок пересчитал")
	var peak := 0.0
	for v in data:
		peak = maxf(peak, absf(v))
	check(peak > 0.2 and peak <= 1.0, "значения в разумных пределах, пик %f" % peak)


## Тон для проверки сжатых форматов: свой, синтезированный, чтобы в поставке
## не было ни одного чужого звука.
const TONE_DIR := "res://tests/fixtures"
const TONE_HZ := 440.0


func test_ogg_и_mp3_разбираются() -> void:
	# 🔴 У сжатых форматов отсчётов напрямую не достать — разбор живёт внутри
	# движка. Банк берёт их через проигрыватель, и частота при этом всегда
	# СЕРВЕРНАЯ: пересчёт делает сам движок.
	var bank := StrudelSampleBank.new()
	bank.load_folder(ProjectSettings.globalize_path(TONE_DIR))
	check(not bank.is_empty(), "банк с тонами не пуст: %d имён" % bank.count())
	for ext in ["wav", "ogg", "mp3"]:
		var path := ProjectSettings.globalize_path(TONE_DIR).path_join("tone." + ext)
		var data := bank.pcm_of(path)
		check(data.size() > 1000, "%s разобрался: %d отсчётов" % [ext, data.size()])
		var rate := bank.rate_of(path)
		check(rate > 8000.0, "%s: частота %f" % [ext, rate])
		# Частота тона проверяется счётом переходов через ноль: у синуса их
		# ровно два на период.
		var crossings := 0
		var prev := 0.0
		var peak := 0.0
		for v in data:
			if (prev <= 0.0 and v > 0.0):
				crossings += 1
			prev = v
			peak = maxf(peak, absf(v))
		var seconds := float(data.size()) / rate
		var hz := float(crossings) / maxf(seconds, 0.001)
		eq_num(hz, TONE_HZ, 20.0, "%s: тон около 440 Гц (вышло %.0f)" % [ext, hz])
		check(peak > 0.2, "%s: пик %f" % [ext, peak])


func test_wav_24_бита_читается_без_потери() -> void:
	# 🔴 РЕГРЕССИЯ. `AudioStreamWAV` знает ровно четыре вида — 8 бит, 16 бит,
	# IMA-ADPCM и QOA (справка движка, class_audiostreamwav). Двадцати четырёх
	# бит там НЕТ, и загрузчик молча ужимает файл до шестнадцати. Библиотеки
	# живых инструментов пишутся в 24 бита и с запасом по уровню: у сэмпла с
	# пиком 0.08 от шестнадцати бит работают одиннадцать. Замерено на VCSL:
	# через движок выходило 3929 разных значений отсчёта, своим разбором —
	# 97522, то есть в двадцать пять раз подробнее.
	var path := "user://_probe24.wav"
	var f := FileAccess.open(path, FileAccess.WRITE)
	check(f != null, "временный файл создался")
	if f == null:
		return
	# Тихая синусоида: её ступеньки видно только при полной разрядности.
	var frames := 512
	var body := PackedByteArray()
	for i in frames:
		var v := int(round(sin(TAU * 7.3 * float(i) / float(frames)) * 0.02 * 8388607.0))
		if v < 0:
			v += 0x1000000
		body.append(v & 0xFF)
		body.append((v >> 8) & 0xFF)
		body.append((v >> 16) & 0xFF)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + body.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)          # целые со знаком
	f.store_16(1)          # моно
	f.store_32(44100)
	f.store_32(44100 * 3)
	f.store_16(3)
	f.store_16(24)         # ДВАДЦАТЬ ЧЕТЫРЕ БИТА
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(body.size())
	f.store_buffer(body)
	f.close()

	# 🔴 ЗДЕСЬ ПРОВЕРЯЕТСЯ ЗАПАСНОЙ ПУТЬ, А НЕ ОСНОВНОЙ.
	#
	# Основным тракт стал движковый: импортированный ресурс, затем
	# `AudioStreamWAV`. Причины в `sample_bank.gd`: он вдвое дешевле на банке
	# игры (28 мс против 64) и, главное, в СОБРАННОЙ игре исходных `.wav` нет
	# — читать файл там нечем. Своё чтение осталось последним запасным для
	# видов, которых движок не знает: 24 и 32 бита, с плавающей точкой.
	#
	# Поэтому тест зовёт разборщик НАПРЯМУЮ. Через `pcm_of` он проверял бы
	# движок, а движок 24 бита ужимает до 16 — и проверка краснела бы на
	# верном поведении.
	var real := ProjectSettings.globalize_path(path)
	var mine: Dictionary = StrudelSampleBank._read_wav(real)
	check(not mine.is_empty(), "запасной разборщик осилил 24 бита")
	if mine.is_empty():
		return
	var data: PackedFloat32Array = mine["data"]
	eq_num(float(mine["rate"]), 44100.0, 1.0, "частота из заголовка файла")
	eq(data.size(), frames, "число отсчётов")

	# Сверка с движковым путём: на 24 битах он обязан оказаться ГРУБЕЕ —
	# у `AudioStreamWAV` всего четыре вида (8 бит, 16 бит, IMA-ADPCM, QOA),
	# двадцати четырёх среди них нет, и файл ужимается при загрузке.
	var wav := AudioStreamWAV.load_from_file(real)
	var engine_levels := {}
	if wav != null:
		for v in StrudelSampleBank._decode_wav(wav):
			engine_levels[snappedf(v, 1e-9)] = true
	var levels := {}
	for v in data:
		levels[snappedf(v, 1e-9)] = true
	check(levels.size() > engine_levels.size(),
		"запасной разбор подробнее движкового: %d разных значений против %d"
		% [levels.size(), engine_levels.size()])

	var worst := 0.0
	for i in frames:
		var want := sin(TAU * 7.3 * float(i) / float(frames)) * 0.02
		worst = maxf(worst, absf(float(data[i]) - want))
	# 16 бит на амплитуде 0.02 дают ступеньку 3.05e-05 — этот допуск её не пропустит.
	check(worst < 2e-6,
		"отсчёты совпали с исходными: худшее отклонение %s" % String.num_scientific(worst))

	DirAccess.remove_absolute(real)
