extends Control

## Пример 7 — ЖИВОЙ КОД. Вставил трек, нажал играть, слышишь и видишь.
##
## Зачем он есть: проверить, как трек звучит ИМЕННО В ГОДОТОВСКОМ ТРАКТЕ, не
## поднимая игру и не сравнивая файлы. Пишешь тот же код, что в браузере, —
## получаешь тот же звук, и рядом видно, что играет.
##
## Собран из того, что уже есть в примерах: лента событий (высота это нота,
## цвет партия, размер громкость) и те же тридцать два чужих трека, что
## листает `05_community_tunes`. Своего здесь только поле кода и осциллограф:
## волна и спектр снимаются с шины движковыми `AudioEffectCapture` и
## `AudioEffectSpectrumAnalyzer`, то есть это настоящий выход, а не рисунок
## по событиям.
##
## Ключи запуска: `--tune=<имя>` — сразу взять трек из списка,
## `--shot=<файл> --warm=<секунд>` — снимок и выход.

const BUS := &"StrudelRepl"
const TUNES_DIR := "res://examples/05_community_tunes/tunes"

## Инструменты берутся из папки примера 02 — её собирает `make_pack.py`.
## Свой набор подключается так же: допиши сюда путь, банк копит паки по разу
## на папку, ровно как `samples()` в браузере.
const PACKS := ["res://examples/02_own_samples"]

## Папки, которых в поставке нет, но если они у тебя лежат — подхватим.
## Так плеер играет чужие треки настоящими инструментами: имена вроде
## `piano1`, `harp`, `vibraphone` живут в банке VCSL, а не в примере.
const EXTRA_PACKS := ["res://tools/judge/vcslbank"]

## Сколько отсчётов волны держим для рисования.
const SCOPE_FRAMES := 2048
## Сколько живёт метка на ленте.
const KEEP := 240.0

const START_CODE := """// Вставь сюда любой код Strudel и нажми «играть» (Ctrl+Enter).
// Это тот же язык, что в браузере: strudel.cc или bulka.app.
// Список сверху — чужие треки, они играют без единой правки.

setcpm(90/4)

$: s("bd ~ [bd bd] sd").gain(0.9)
$: s("hh*8").gain(0.3).pan(sine.slow(4))
$: note("<c3 eb3 g3 bb3>").s("sawtooth")
  .lpf(sine.range(300, 2000).slow(8))
  .gain(0.35).room(0.4)
"""


class Mark:
	var age := 0.0
	var height := 0.5
	var size := 6.0
	var color := Color.WHITE


var music: StrudelPlayer
var _marks: Array[Mark] = []
var _flash := 0.0
var _error := ""
var _names: PackedStringArray = PackedStringArray()

var _capture: AudioEffectCapture = null
var _spectrum: AudioEffectSpectrumAnalyzerInstance = null
var _scope := PackedFloat32Array()
var _bars := PackedFloat32Array()

var _code: CodeEdit
var _view: Control
var _status: Label
var _play: Button
var _cpm: SpinBox
var _pick: OptionButton
var _font: Font

# Снимок для документации: --shot=<файл> --warm=<секунд>
var _shot_path := ""
var _shot_at := 4.0
var _want_tune := ""
var _clock := 0.0

const BACK := Color(0.055, 0.065, 0.09)
const PANEL := Color(0.085, 0.10, 0.135)
const INK := Color(0.90, 0.93, 0.96)
const DIM := Color(0.52, 0.58, 0.67)


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_scope.resize(SCOPE_FRAMES)
	_bars.resize(28)
	_setup_bus()
	_build_ui()

	music = StrudelPlayer.new()
	music.max_voices = 96
	music.bus = BUS
	add_child(music)
	music.event_played.connect(_on_event)
	music.error_raised.connect(func(m: String) -> void: _error = m)
	music.set_bank(_load_packs())

	for arg in OS.get_cmdline_user_args():
		var s := String(arg)
		if s.begins_with("--shot="):
			_shot_path = s.substr(7)
		elif s.begins_with("--warm="):
			_shot_at = s.substr(7).to_float()
		elif s.begins_with("--tune="):
			_want_tune = s.substr(7)

	_names = _list_tunes()
	_pick.add_item("— свой код —")
	for name in _names:
		_pick.add_item(name.get_basename())
	print("Треков в списке: %d, сэмплов в банке: %d. Ctrl+Enter — играть, Esc — выход."
		% [_names.size(), int(music.stats().get("сэмплов_в_банке", 0))])

	if _want_tune != "":
		for i in _names.size():
			if _names[i].get_basename() == _want_tune:
				_pick.select(i + 1)
				_take_tune(i + 1)
				break
	if _shot_path != "":
		_start()


func _load_packs() -> StrudelSampleBank:
	var bank := StrudelSampleBank.new()
	for path in PACKS:
		bank.load_folder(ProjectSettings.globalize_path(path))
	for path in EXTRA_PACKS:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			bank.load_folder(ProjectSettings.globalize_path(path))
	return bank


func _missing_voices(code: String) -> PackedStringArray:
	## Каких инструментов трек просит, а в банке их нет.
	##
	## 🔴 БЕЗ ЭТОГО «НЕ ИГРАЕТ» ВЫГЛЯДИТ КАК ПОЛОМКА ПЛЕЕРА. Чужой трек зовёт
	## `piano1`, `harp`, `vibraphone`; если банка с ними нет, событий полно, а
	## звука ноль — и понять, что дело в сэмплах, снаружи нечем.
	var out: PackedStringArray = []
	var run: Dictionary = StrudelRuntime.run(code)
	if not run.get("ok", false):
		return out
	var bank := music.get_bank()
	var seen := {}
	for hap in (run["pattern"] as StrudelPattern).query_arc(0.0, 8.0):
		if not hap.value is Dictionary:
			continue
		var name := String((hap.value as Dictionary).get("s", ""))
		if name == "" or seen.has(name):
			continue
		seen[name] = true
		# Синтез сэмплов не просит: список берётся у самого плагина, чтобы он
		# не разъехался с ним при добавлении новой волны.
		if StrudelVoiceBuilder.SYNTHS.has(name):
			continue
		# `gm_*` живут не в банке, а в пресетах webaudiofont. Strudel тянет их
		# из сети, а плагину сеть запрещена: пресеты кладутся на диск заранее и
		# указываются `gm_fonts_path`. Пока путь пуст, эти голоса молчат — и об
		# этом надо сказать, иначе трек звучит наполовину без объяснений.
		if name.begins_with("gm_"):
			if music.gm_fonts_path == "":
				out.append(name)
			continue
		if bank == null or not bank.entries.has(name):
			out.append(name)
	out.sort()
	return out


func _list_tunes() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TUNES_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		# В собранной игре у файлов появляется хвост `.remap` — тот же случай,
		# что и в `05_community_tunes`.
		var clean := String(name).trim_suffix(".remap")
		if clean.ends_with(".js"):
			out.append(clean)
	out.sort()
	return out


func _setup_bus() -> void:
	## Своя шина: с неё снимаются волна и спектр, чужие не трогаются.
	var index := AudioServer.get_bus_index(BUS)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, String(BUS))
		AudioServer.set_bus_send(index, &"Master")
	if AudioServer.get_bus_effect_count(index) == 0:
		AudioServer.add_bus_effect(index, AudioEffectCapture.new())
		AudioServer.add_bus_effect(index, AudioEffectSpectrumAnalyzer.new())
	_capture = AudioServer.get_bus_effect(index, 0) as AudioEffectCapture
	_spectrum = AudioServer.get_bus_effect_instance(index, 1) as AudioEffectSpectrumAnalyzerInstance


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = BACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.offset_left = 18
	split.offset_top = 16
	split.offset_right = -18
	split.offset_bottom = -16
	split.split_offset = 460
	add_child(split)

	# слева: список треков, поле кода, кнопки
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)

	var title := Label.new()
	title.text = "Strudel for Godot — живой код"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", INK)
	left.add_child(title)

	_pick = OptionButton.new()
	_pick.item_selected.connect(_take_tune)
	left.add_child(_pick)

	_code = CodeEdit.new()
	_code.text = START_CODE
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.gutters_draw_line_numbers = true
	_code.add_theme_font_size_override("font_size", 14)
	_code.text_changed.connect(func() -> void: _error = "")
	left.add_child(_code)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	left.add_child(row)

	_play = Button.new()
	_play.text = "▶  играть"
	_play.custom_minimum_size = Vector2(130, 34)
	_play.pressed.connect(_toggle)
	row.add_child(_play)

	var label := Label.new()
	label.text = "кругов в минуту"
	label.add_theme_color_override("font_color", DIM)
	row.add_child(label)

	_cpm = SpinBox.new()
	_cpm.min_value = 10
	_cpm.max_value = 400
	_cpm.value = 30
	_cpm.value_changed.connect(func(v: float) -> void: music.cycles_per_minute = v)
	row.add_child(_cpm)

	# справа: лента событий и осциллограф
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)

	_view = Control.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	right.add_child(_view)

	_status = Label.new()
	_status.add_theme_color_override("font_color", DIM)
	right.add_child(_status)


func _take_tune(index: int) -> void:
	if index <= 0:
		return
	var path := TUNES_DIR.path_join(_names[index - 1])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error = "не прочитал " + path
		return
	var text := file.get_as_text()
	file.close()
	# Возврат каретки CodeEdit переводом строки не считает: трек с виндовым
	# концом строки ложился в строку номер один целиком, а раз она начинается
	# с `//`, то и весь код оказывался закомментирован — снаружи это выглядело
	# как «плеер молчит».
	_code.text = text.replace("\r\n", "\n").replace("\r", "\n")
	# Показываем начало трека: после присвоения каретка уезжает в конец.
	_code.set_caret_line(0)
	_code.scroll_vertical = 0
	_error = ""
	if music.is_playing():
		_start()


func _toggle() -> void:
	if music.is_playing():
		music.stop()
		_play.text = "▶  играть"
		return
	_start()


func _start() -> void:
	_error = ""
	_marks.clear()
	var missing := _missing_voices(_code.text)
	if music.play(_code.text):
		_play.text = "■  стоп"
		if not missing.is_empty():
			_error = "нет в банке: " + ", ".join(missing)
	else:
		# Разбор не удался — ошибка приходит и сигналом, и через `last_error`.
		# Пустой текст ошибки тоже показываем: молчащая кнопка без объяснения
		# выглядит как «плеер сломан».
		_error = music.last_error()
		if _error == "":
			_error = "код не принят, а объяснения не дали"
		_play.text = "▶  играть"
		push_warning("Strudel: не запустилось — " + _error)


func _on_event(value: Dictionary) -> void:
	var mark := Mark.new()
	var sound := String(value.get("s", ""))
	var gain := clampf(float(value.get("gain", 0.5)), 0.02, 1.5)
	match sound:
		"bd":
			mark.height = 0.06
			mark.size = 15.0
			mark.color = Color(0.45, 0.66, 0.92)
			_flash = 1.0
		"sd", "sn":
			mark.height = 0.30
			mark.size = 11.0
			mark.color = Color(0.94, 0.65, 0.38)
		"hh", "oh":
			mark.height = 0.92
			mark.size = 5.0
			mark.color = Color(0.62, 0.68, 0.78)
		_:
			var note := float(value.get("note", 60.0))
			mark.height = clampf((note - 33.0) / 48.0, 0.0, 1.0)
			mark.size = 9.0
			mark.color = Color(0.52, 0.86, 0.68)
	mark.size *= 0.6 + gain
	_marks.append(mark)
	if _marks.size() > 400:
		_marks.remove_at(0)


func _process(delta: float) -> void:
	_clock += delta
	_flash = maxf(_flash - delta * 3.5, 0.0)
	for m in _marks:
		m.age += delta * 46.0
	_marks = _marks.filter(func(m: Mark) -> bool: return m.age < KEEP)
	_read_output()
	_view.queue_redraw()
	_update_status()

	if _shot_path != "" and _clock >= _shot_at:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("снимок: ", _shot_path)
		get_tree().quit()


func _read_output() -> void:
	if _capture != null:
		var have := _capture.get_frames_available()
		if have > 0:
			var got := _capture.get_buffer(mini(have, SCOPE_FRAMES))
			var n := got.size()
			if n > 0:
				# Окно едет: свежие отсчёты ложатся в хвост.
				for i in range(0, SCOPE_FRAMES - n):
					_scope[i] = _scope[i + n]
				for i in n:
					_scope[SCOPE_FRAMES - n + i] = (got[i].x + got[i].y) * 0.5
	if _spectrum != null:
		var lo := 40.0
		for i in _bars.size():
			var hi := lo * 1.28
			var m := _spectrum.get_magnitude_for_frequency_range(lo, hi).length()
			var db := linear_to_db(maxf(m, 1e-6) * 6.0)
			_bars[i] = clampf((db + 60.0) / 60.0, 0.0, 1.0)
			lo = hi


func _update_status() -> void:
	var s := music.stats()
	# Темп в поле — тот, что стоит СЕЙЧАС: трек мог задать свой через `setcpm`,
	# и он сильнее значения в поле. Обновляется ДО ветки с предупреждением:
	# иначе при любой жалобе поле показывает старое число.
	var cpm := float(s.get("циклов_в_секунду", 0.0)) * 60.0
	if cpm > 0.0 and absf(cpm - _cpm.value) > 0.01:
		_cpm.set_value_no_signal(cpm)
	if _error != "":
		_status.text = "⚠  %s · цикл %.2f · голосов %d" % [
			_error, float(s.get("цикл", 0.0)), int(s.get("голосов_звучит", 0))]
		_status.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
		return
	_status.add_theme_color_override("font_color", DIM)
	_status.text = "цикл %.2f · голосов %d из %d · событий %d · сэмплов в банке %d" % [
		float(s.get("цикл", 0.0)),
		int(s.get("голосов_звучит", 0)),
		int(s.get("голосов_предел", 0)),
		int(s.get("событий_сыграно", 0)),
		int(s.get("сэмплов_в_банке", 0)),
	]


func _draw_view() -> void:
	var size := _view.size
	_view.draw_rect(Rect2(Vector2.ZERO, size), PANEL)
	if _flash > 0.0:
		_view.draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.52, 0.78, _flash * 0.07))

	var scope_h := minf(size.y * 0.28, 150.0)
	var lane_bottom := size.y - scope_h - 34.0
	_draw_ribbon(size, 18.0, maxf(lane_bottom, 40.0))
	_draw_scope(Rect2(0.0, size.y - scope_h, size.x, scope_h))


func _draw_ribbon(size: Vector2, top: float, bottom: float) -> void:
	var right := size.x - 16.0
	var left := 16.0
	for k in 5:
		var y := lerpf(top, bottom, float(k) / 4.0)
		_view.draw_line(Vector2(left, y), Vector2(right, y), Color(1, 1, 1, 0.035), 1.0)

	for m in _marks:
		var x := right - m.age * ((right - left) / KEEP)
		if x < left:
			continue
		var y := lerpf(bottom, top, m.height)
		var fade := clampf(1.0 - m.age / KEEP, 0.0, 1.0)
		var c := m.color
		c.a = 0.25 + fade * 0.7
		_view.draw_circle(Vector2(x, y), m.size * (0.55 + fade * 0.45), c)

	_view.draw_line(Vector2(right, top), Vector2(right, bottom), Color(1, 1, 1, 0.22), 2.0)
	if _marks.is_empty():
		_view.draw_string(_font, Vector2(left + 6, top + 26),
			"нажми «играть» — здесь пойдут события",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)

	var lx := left
	for item in [["бочка", Color(0.45, 0.66, 0.92)], ["снейр", Color(0.94, 0.65, 0.38)],
			["хэт", Color(0.62, 0.68, 0.78)], ["ноты", Color(0.52, 0.86, 0.68)]]:
		_view.draw_circle(Vector2(lx + 6, bottom + 14), 5.0, item[1])
		_view.draw_string(_font, Vector2(lx + 18, bottom + 19), String(item[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		lx += 96.0


func _draw_scope(rect: Rect2) -> void:
	_view.draw_rect(rect, Color(0.04, 0.05, 0.07))
	var bw := rect.size.x / float(_bars.size())
	for i in _bars.size():
		var h := _bars[i] * rect.size.y
		_view.draw_rect(Rect2(rect.position.x + bw * i + 1.0,
			rect.position.y + rect.size.y - h, bw - 2.0, h),
			Color(0.30, 0.55, 0.75, 0.30), true)
	var mid := rect.position.y + rect.size.y * 0.5
	var step := float(SCOPE_FRAMES) / maxf(rect.size.x, 1.0)
	var points := PackedVector2Array()
	points.resize(maxi(int(rect.size.x), 2))
	for x in points.size():
		var i := mini(int(float(x) * step), SCOPE_FRAMES - 1)
		points[x] = Vector2(rect.position.x + float(x), mid - _scope[i] * rect.size.y * 0.45)
	_view.draw_polyline(points, INK, 1.5, true)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# Ctrl+Enter — играть, как в браузере. Esc — выход.
	if key.keycode == KEY_ENTER and key.ctrl_pressed:
		_toggle()
		accept_event()
	elif key.keycode == KEY_ESCAPE:
		get_tree().quit()
