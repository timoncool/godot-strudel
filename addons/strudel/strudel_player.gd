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

## Темп в циклах в минуту. `setcpm(...)` в самом коде перебивает это значение.
@export_range(1.0, 600.0, 0.1) var cycles_per_minute := 30.0:
	set(value):
		cycles_per_minute = value
		if _engine != null and not _cps_from_code:
			_engine.set_cps(value / 60.0)

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

var _player: AudioStreamPlayer = null
var _engine: StrudelEngine = null
var _bank: StrudelSampleBank = null
var _playing := false
var _cps_from_code := false
var _last_error := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_build()
	if autoplay and code.strip_edges() != "":
		play()


func _build() -> void:
	_engine = StrudelEngine.new()
	_engine.max_voices = max_voices
	_engine.lookahead = lookahead
	_engine.event_started.connect(func(value, _delay): event_played.emit(value))
	_engine.voices_exhausted.connect(func(total, limit): voices_exhausted.emit(total, limit))

	_bank = StrudelSampleBank.new()
	if samples_path != "":
		var n := _bank.load_folder(ProjectSettings.globalize_path(samples_path))
		if n == 0:
			push_warning("Strudel: в папке \"%s\" не нашлось сэмплов — играю синтезом." % samples_path)
	_engine.bank = _bank

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
	return true


func stop() -> void:
	## Останавливает музыку и глушит голоса.
	_playing = false
	if _player != null:
		_player.stop()
	if _engine != null:
		_engine.reset_clock()


func is_playing() -> bool:
	return _playing


func set_code(new_code: String) -> bool:
	## Живая замена кода. Такт НЕ сбрасывается и щелчка не будет: уже
	## звучащие голоса доигрывают, новые события идут по новому паттерну.
	code = new_code
	return _apply_code(new_code)


func set_pattern(pattern: StrudelPattern) -> void:
	## Программный вход: паттерн, собранный из GDScript, а не строкой.
	if _engine == null:
		_build()
	_engine.set_pattern(pattern)


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
		_engine.fill(playback)
