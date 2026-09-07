@tool
@icon("res://addons/strudel/icons/strudel_player.svg")
class_name StrudelPlayer
extends Node

## Проигрыватель живого кода Strudel.
##
## Минимальный сценарий — три строки:
## [codeblock]
## var music := StrudelPlayer.new()
## add_child(music)
## music.play('s("bd sd*2, ~ hh")')
## [/codeblock]
##
## Код пишется так же, как в Strudel или на bulka.app, и вставляется сюда без
## правок. Всё, что происходит дальше — разбор, планирование и сведение —
## внутри плагина.
##
## Сеть не используется: сэмплы берутся только из папки, которую указали в
## [member samples_path]. Пустая папка — не ошибка: тогда всё играет синтезом.

## Событие паттерна прозвучало. `value` — словарь параметров ({s, note, gain…}).
## По нему игра может дышать в такт музыке.
signal event_played(value: Dictionary)
## Разбор или исполнение кода не удались. Текст уже понятный, с местом ошибки.
signal error_raised(message: String)
## Голосов не хватило и пришлось вытеснять. Слышно как пропавшие ноты.
signal voices_exhausted(total_stolen: int, limit: int)

## Код Strudel. Меняется на ходу: такт при этом не сбрасывается.
@export_multiline var code: String = "":
	set(value):
		code = value
		if is_inside_tree() and _engine != null and _playing:
			_apply_code(code)

## Начинать игру сразу после добавления в сцену.
@export var autoplay := false

## Папка с сэмплами и картами формата Strudel. Пустая строка — только синтез.
@export_dir var samples_path := ""

## Файл саундфонта (.sf2). Звуки из него адресуются как `sf:<банк>:<программа>`.
@export_file("*.sf2") var soundfont_path := ""

## Папка с пресетами webaudiofont (`0320_JCLive_sf2_file.js` и т. п.) — те
## самые, что Strudel тянет для имён `gm_*` (`@strudel/soundfonts`). Пусто —
## имена `gm_*` играют синтезом.
@export_dir var gm_fonts_path := ""

## Темп в циклах в минуту. `setcpm(...)` в самом коде перебивает это значение.
@export_range(1.0, 600.0, 0.1) var cycles_per_minute := 30.0:
	set(value):
		cycles_per_minute = value
		if _engine != null and not _cps_from_code:
			_engine.set_cps(value / 60.0)

## Зал и эхо орбит — на ШТАТНЫХ узлах Godot: под каждую орбиту заводятся
## две шины с `AudioEffectReverb` и `AudioEffectDelay`, посылы идут туда, а
## сведённое возвращается в [member bus]. Это тот же принцип, что у Strudel:
## там зал — нативный узел браузера, а не скрипт.
##
## 🔴 ПОЧЕМУ НЕ СВОЙ ЗАЛ. Свой (`StrudelReverb`) рекурсивный, и хвост у него
## на 8.7 дБ тише и иной формы, чем у оригинала; а честная свёртка с импульсом,
## как в `reverbGen.mjs`, замерена настоящим кодом на GDScript — 105% реального
## времени на ОДИН зал. Штатный узел даёт хвост в −1.2 дБ от оригинала и стоит
## почти ничего. Свой остаётся для оффлайн-рендера: там звукового сервера нет.
@export var native_effects := true
## Во сколько раз ослаблен посыл в штатный зал — см. `_apply_wet_settings`.
const SEND_TRIM := 0.5

## Шина вывода. Своей шины плагин не заводит и чужих не трогает.
@export var bus: StringName = &"Master":
	set(value):
		bus = value
		if _player != null:
			_player.bus = value

## Громкость вывода.
@export_range(-60.0, 12.0, 0.1) var volume_db := 0.0:
	set(value):
		volume_db = value
		if _player != null:
			_player.volume_db = value

## На сколько секунд вперёд считаются события. Больше — устойчивее к
## просадкам кадров, меньше — быстрее отзывается на замену кода.
@export_range(0.02, 2.0, 0.01) var lookahead := 0.2:
	set(value):
		lookahead = value
		if _engine != null:
			_engine.lookahead = value

## Предел одновременно звучащих голосов. Сверх него голоса вытесняются, и об
## этом сообщает сигнал — молчаливой кражи нот здесь нет.
@export_range(1, 256, 1) var max_voices := 64

## Мягкое ограничение на выходе.
##
## Выключено по умолчанию, потому что в самом Strudel лимитера нет и звук с ним
## перестаёт быть побитово тем же. Если в логе появилось предупреждение о
## перегрузе — включите его либо убавьте [member volume_db].
@export var master_limiter := false:
	set(value):
		master_limiter = value
		if _engine != null:
			_engine.master_limiter = value

var _player: AudioStreamPlayer = null
## Орбита → её шины, узлы и проигрыватели посылов.
var _wet: Dictionary = {}
## Партии последнего разобранного кода: имя метки → паттерн.
var _layers: Dictionary = {}
var _engine: StrudelEngine = null
var _bank: StrudelSampleBank = null
var _playing := false
var _cps_from_code := false
var _last_error := ""
var _warned_clip := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build()
	if autoplay and code.strip_edges() != "":
		play()


func _build() -> void:
	_engine = StrudelEngine.new()
	_engine.wet_external = native_effects
	_engine.max_voices = max_voices
	_engine.lookahead = lookahead
	_engine.master_limiter = master_limiter
	_engine.event_started.connect(func(value, _delay): event_played.emit(value))
	_engine.voices_exhausted.connect(func(total, limit): voices_exhausted.emit(total, limit))

	_bank = StrudelSampleBank.new()
	if samples_path != "":
		var n := _bank.load_folder(ProjectSettings.globalize_path(samples_path))
		if n == 0:
			push_warning("Strudel: в папке \"%s\" не нашлось сэмплов — играю синтезом." % samples_path)
	_engine.bank = _bank

	if gm_fonts_path != "":
		var gmf := StrudelGMFonts.new()
		var found := gmf.load_folder(gm_fonts_path)
		if found > 0:
			_engine.gm_fonts = gmf
			print("Strudel: пресеты gm_* — %d на диске" % found)
		else:
			push_warning("Strudel: в «%s» нет пресетов gm_*" % gm_fonts_path)

	if soundfont_path != "":
		var sf := StrudelSoundFont.new()
		if sf.load_file(soundfont_path):
			_engine.soundfont = sf
			print("Strudel: саундфонт «%s» — пресетов %d, звуков %d"
				% [soundfont_path.get_file(), sf.preset_count(), sf.sample_count()])
		else:
			push_warning("Strudel: саундфонт \"%s\" не прочитался" % soundfont_path)

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = AudioServer.get_mix_rate()
	stream.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.name = "StrudelOutput"
	_player.stream = stream
	_player.bus = bus
	_player.volume_db = volume_db
	add_child(_player)
	_engine.setup(stream.mix_rate)
	_engine.set_cps(cycles_per_minute / 60.0)


# ═══════════════════════════════════════════════════════════════════════════
# Управление
# ═══════════════════════════════════════════════════════════════════════════

func play(new_code: String = "") -> bool:
	## Запускает музыку. Пустой аргумент — играет то, что лежит в [member code].
	## Возвращает false, если код не разобрался; текст ошибки — в сигнале.
	if _engine == null:
		_build()
	if new_code != "":
		code = new_code
	if not _apply_code(code):
		return false
	if not _player.playing:
		_player.play()
	_playing = true
	# Сэмплы разбираются наперёд, чтобы первая нота каждой высоты не вставала
	# посреди фразы.
	if _engine.bank != null and _engine.bank.has_method("prime_async"):
		# Прогреваем ровно те наборы, которые называет сам код: у большого
		# банка прогрев целиком читает гигабайты впустую.
		_engine.bank.prime_async(_voices_in_code())
	return true


func _voices_in_code() -> PackedStringArray:
	## Какие наборы банка упоминает код. Без разбора синтаксиса: просто ищем
	## имена самого банка в тексте — надёжнее любого шаблона и не ломается на
	## незнакомой записи. Лишнее имя в списке стоит одного разбора файла,
	## пропущенное — рывка посреди фразы, поэтому ошибаться лучше в плюс.
	var out: PackedStringArray = []
	if _engine.bank == null:
		return out
	for key in _engine.bank.entries.keys():
		var name := String(key)
		if name.length() >= 2 and code.contains(name):
			out.append(name)
	return out


func _capacity() -> int:
	var stream := _player.stream as AudioStreamGenerator
	return int(stream.buffer_length * stream.mix_rate) if stream != null else 0


func _feed_wet(count: int, buffered_before: int) -> void:
	## Отдать посылы орбит их шинам — ровно те отсчёты, что легли в сухой выход.
	for id in _engine.orbit_ids():
		var w: Dictionary = _wet.get(id, {})
		if w.is_empty():
			w = _make_wet(int(id), buffered_before)
			_wet[id] = w
		_apply_wet_settings(w, _engine.orbit_settings(int(id)))
		var room: PackedFloat32Array = _engine.orbit_send(int(id), "room")
		var echo: PackedFloat32Array = _engine.orbit_send(int(id), "delay")
		var rp := (w["room_player"] as AudioStreamPlayer).get_stream_playback() as AudioStreamGeneratorPlayback
		var dp := (w["delay_player"] as AudioStreamPlayer).get_stream_playback() as AudioStreamGeneratorPlayback
		var n := mini(count, room.size())
		for i in n:
			if rp != null:
				rp.push_frame(Vector2(room[i] * SEND_TRIM, room[i] * SEND_TRIM))
			if dp != null:
				dp.push_frame(Vector2(echo[i], echo[i]))


func _make_wet(id: int, buffered_before: int) -> Dictionary:
	## Две шины на орбиту: зал и эхо. Обе сводятся в [member bus].
	var stem := "%s·%d·orbit%d" % [name, get_instance_id() % 10000, id]
	var made := {}
	for kind in ["room", "delay"]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, stem + "·" + kind)
		AudioServer.set_bus_send(idx, bus)
		var fx: AudioEffect
		if kind == "room":
			var rev := AudioEffectReverb.new()
			rev.dry = 0.0
			rev.wet = 1.0
			rev.spread = 1.0
			rev.hipass = 0.0
			fx = rev
		else:
			var dl := AudioEffectDelay.new()
			dl.dry = 0.0
			# Как `FeedbackDelayNode` в Strudel: первое эхо — в полный голос
			# (отвод 1 на времени задержки, 0 дБ), дальше — петля с весом
			# `delayfeedback`. Замерено: удар 0.80 даёт 0.80 → 0.40 → 0.20 при
			# обратной связи 0.5, ровно как в оригинале. Без отвода петля
			# штатного узла не отдаёт наружу ничего.
			dl.tap1_active = true
			dl.tap1_level_db = 0.0
			dl.tap1_pan = 0.0
			dl.tap2_active = false
			dl.feedback_active = true
			dl.feedback_lowpass = 20000.0
			fx = dl
		AudioServer.add_bus_effect(idx, fx)
		var stream := AudioStreamGenerator.new()
		var main := _player.stream as AudioStreamGenerator
		stream.mix_rate = main.mix_rate
		stream.buffer_length = main.buffer_length
		var p := AudioStreamPlayer.new()
		p.name = "Strudel%s%d" % [kind.capitalize(), id]
		p.stream = stream
		p.bus = StringName(stem + "·" + kind)
		p.volume_db = volume_db
		add_child(p)
		p.play()
		# 🔴 ВЫРАВНИВАНИЕ ПО ВРЕМЕНИ. Сухой выход к этому моменту уже держит в
		# буфере до ста миллисекунд, а новый проигрыватель — ничего: без
		# подкладки тишины зал шёл бы ВПЕРЕДИ прямого звука.
		var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
		if pb != null:
			for i in buffered_before:
				pb.push_frame(Vector2.ZERO)
		made[kind + "_bus"] = idx
		made[kind + "_fx"] = fx
		made[kind + "_player"] = p
	return made


func _apply_wet_settings(w: Dictionary, s: Dictionary) -> void:
	if s.is_empty() or w.get("settings", {}) == s:
		return
	w["settings"] = s.duplicate()
	var rev := w["room_fx"] as AudioEffectReverb
	# `roomsize` в Strudel — время затухания до −60 дБ. Штатный зал — по
	# Фридверу: отклик гребёнки g = 0.7 + 0.28·room_size, а время затухания
	# T = −0.0952 / log10(g) (длина гребёнок около 32 мс). Отсюда обратно:
	var decay := maxf(float(s["decay"]), 0.05)
	var g := pow(10.0, -0.0952 / decay)
	# 🔴 ЧИСЛА НИЖЕ — ИЗ СВЕРКИ С ЗАПИСЬЮ STRUDEL, А НЕ ИЗ ГОЛОВЫ. Эталон:
	# одна нота рояля, `room(0.36).roomsize(4).roomlp(4200)`, записана в Булке
	# и здесь (`tools/record_live.gd`). Ранние отражения у Freeverb плотнее, чем
	# у шумового импульса оригинала, поэтому посыл в зал ослаблен вдвое
	# (SEND_TRIM), а размер сдвинут на +0.06 — тогда хвост 1.5–4 с сходится в
	# 0.0 дБ, прямой звук в −0.5 дБ, тело 0.2–1 с остаётся на +4 дБ громче.
	# Без сдвига и трима было: хвост −1.9, тело +6.5. Свой зал давал −8.7.
	rev.room_size = clampf((g - 0.7) / 0.28 + 0.06, 0.0, 1.0)
	# `roomlp` — потолок хвоста; у штатного зала это глушение верхов 0…1.
	# Делитель подобран той же сверкой: при 12000 полоса 2–5 кГц выходила на
	# 8 дБ темнее оригинала, при 40000 — на 5.7; глубже Freeverb не пускает.
	var lp := float(s["lp_start"])
	rev.damping = clampf(1.0 - lp / 40000.0, 0.0, 1.0) if lp > 0.0 else 0.0
	# `roomfade` — наплыв импульса; ближайшее у штатного — предзадержка.
	rev.predelay_msec = clampf(float(s["fade"]) * 500.0, 0.0, 500.0)
	rev.predelay_feedback = 0.0

	var dl := w["delay_fx"] as AudioEffectDelay
	var fb := clampf(float(s["delay_feedback"]), 0.0, 0.98)
	dl.feedback_delay_ms = clampf(float(s["delay_time"]) * 1000.0, 1.0, 1500.0)
	dl.tap1_delay_ms = dl.feedback_delay_ms
	dl.feedback_level_db = linear_to_db(maxf(fb, 0.001))


func _drop_wet() -> void:
	## Снять свои шины: чужих не трогаем, свои за собой убираем.
	for id in _wet:
		var w: Dictionary = _wet[id]
		for kind in ["room", "delay"]:
			var p := w.get(kind + "_player") as AudioStreamPlayer
			if p != null:
				p.stop()
				p.queue_free()
	# Индексы шин плывут при удалении — снимаем по имени, с конца.
	var names: Array = []
	for id in _wet:
		var w: Dictionary = _wet[id]
		for kind in ["room", "delay"]:
			names.append(AudioServer.get_bus_name(int(w[kind + "_bus"])))
	for i in range(AudioServer.bus_count - 1, 0, -1):
		if names.has(AudioServer.get_bus_name(i)):
			AudioServer.remove_bus(i)
	_wet.clear()


func _exit_tree() -> void:
	_drop_wet()
	# 🔴 ПОТОК ПРОГРЕВА ГАСИТСЯ ПРИ ВЫХОДЕ. Он стартует вместе с музыкой, но
	# при закрытии игры `stop()` зовут не всегда — движок тогда ругается
	# `~Thread` и роняет утечку объектов на выходе.
	if _engine != null and _engine.bank != null and _engine.bank.has_method("prime_stop"):
		_engine.bank.prime_stop()
	if _engine != null:
		_engine.shutdown()


func restart_clock() -> void:
	## Начать с начала формы. Нужно, когда несколько плееров ведут один трек
	## разными партиями: собираются они по очереди, а идти обязаны вместе.
	_engine.reset_clock()


func stop() -> void:
	## Останавливает музыку и глушит голоса.
	_playing = false
	_drop_wet()
	if _engine.bank != null and _engine.bank.has_method("prime_stop"):
		_engine.bank.prime_stop()
	if _player != null:
		_player.stop()
	if _engine != null:
		_engine.shutdown()
		_engine.reset_clock()


func is_playing() -> bool:
	return _playing


func set_code(new_code: String) -> bool:
	## Живая замена кода. Такт НЕ сбрасывается и щелчка не будет: уже
	## звучащие голоса доигрывают, новые события идут по новому паттерну.
	code = new_code
	return _apply_code(new_code)


func set_soundfont(sf: StrudelSoundFont) -> void:
	## Поставить готовый саундфонт вместо загрузки по пути.
	if _engine == null:
		_build()
	_engine.soundfont = sf


func set_bank(new_bank: StrudelSampleBank) -> void:
	## Поставить готовый банк вместо загрузки из папки.
	##
	## Нужен проектам со своим форматом описи: они переводят её в банк плагина
	## сами, а плагин про их формат не знает.
	if _engine == null:
		_build()
	_bank = new_bank
	_engine.bank = new_bank


func get_bank() -> StrudelSampleBank:
	return _bank


func set_pattern(pattern: StrudelPattern) -> void:
	## Программный вход: паттерн, собранный из GDScript, а не строкой.
	if _engine == null:
		_build()
	_engine.set_pattern(pattern)


func trigger(value: Dictionary, length: float = 0.25) -> void:
	## Сыграть событие СРАЗУ, без всякого паттерна: нота героя, звук капли,
	## отклик интерфейса. Голос — любой, какой понимает Strudel.
	##
	## Плеер для этого не обязан ничего играть: выход поднимается сам, и один
	## и тот же узел годится и на трек, и на россыпь отдельных звуков.
	##
	## [codeblock]
	## sfx.trigger({"s": "wt_epiano", "note": 67, "gain": 0.7}, 0.3)
	## [/codeblock]
	if _engine == null:
		_build()
	open()
	_engine.trigger(value, length)


func open() -> void:
	## Поднять выход, не заводя паттерна: плеер начинает считать звук и ждать
	## событий. Нужен, когда узел работает звуковой машиной, а не проигрывателем.
	if _engine == null:
		_build()
	if _player != null and not _player.playing:
		_player.play()
	_playing = true


func layers() -> Dictionary:
	## Партии последнего разобранного кода: имя метки → паттерн.
	##
	## 🔴 ЭТО И ЕСТЬ СПОСОБ ОТДАТЬ ПАРТИЮ ИГРОКУ. Пометь лид в треке
	## подчёркиванием (`_lead:`) — движок его не сыграет, но здесь он лежит
	## целым; спрашивай у него ноты (`query_arc`) и подавай их в [method
	## trigger] по действию человека. Трек идёт своим чередом, лид ведёт игрок,
	## и звучит он тем же голосом, что задуман в треке.
	return _layers


func layer(name: String) -> StrudelPattern:
	## Одна партия по имени метки. Ничего не нашлось — null.
	var got: Variant = _layers.get(name, null)
	return got if got is StrudelPattern else null


func set_cycles_per_second(value: float) -> void:
	## Смена темпа на ходу, без сброса такта.
	if _engine != null:
		_engine.set_cps(value)


func current_cycle() -> float:
	## Текущее место в паттерне, в циклах. Считается по звуковым часам.
	return _engine.current_cycle() if _engine != null else 0.0


func stats() -> Dictionary:
	## Что происходит внутри — для отладки и замеров.
	if _engine == null:
		return {}
	return {
		"голосов_звучит": _engine.active_voices(),
		"голосов_предел": _engine.max_voices,
		"вытеснено": _engine.stolen_voices,
		"событий_сыграно": _engine.played_events,
		"цикл": _engine.current_cycle(),
		"циклов_в_секунду": _engine.cps,
		"сэмплов_в_банке": _bank.count() if _bank != null else 0,
		"перегружено_отсчётов": _engine.clipped_frames,
	}


func last_error() -> String:
	return _last_error


# ═══════════════════════════════════════════════════════════════════════════
# Внутреннее
# ═══════════════════════════════════════════════════════════════════════════

func _apply_code(source: String) -> bool:
	if source.strip_edges() == "":
		_fail("код пуст")
		return false
	var run: Dictionary = StrudelRuntime.run(source)
	if not run.get("ok", false):
		_fail(String(run.get("error", "неизвестная ошибка")))
		return false
	_last_error = ""
	_layers = run.get("layers", {})
	_engine.set_pattern(run["pattern"])
	var cps: float = run.get("cps", 0.0)
	if cps > 0.0:
		# Темп из кода сильнее значения в инспекторе — так ведёт себя Strudel.
		_cps_from_code = true
		_engine.set_cps(cps)
	return true


func _fail(message: String) -> void:
	_last_error = message
	push_error("Strudel: " + message)
	error_raised.emit(message)


func _process(_delta: float) -> void:
	if not _playing or _player == null:
		return
	var playback := _player.get_stream_playback()
	if playback is AudioStreamGeneratorPlayback:
		var gen := playback as AudioStreamGeneratorPlayback
		var buffered_before: int = _capacity() - gen.get_frames_available()
		var n: int = _engine.fill(gen)
		if native_effects and n > 0:
			_feed_wet(n, buffered_before)
	# О перегрузе говорим ОДИН раз: иначе лог зальёт.
	if not _warned_clip and _engine.clipped_frames > int(_engine.mix_rate * 0.05):
		_warned_clip = true
		push_warning("Strudel: выход перегружен (%d отсчётов). Убавь volume_db или включи master_limiter."
			% _engine.clipped_frames)
