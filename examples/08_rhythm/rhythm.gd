extends Control

## Пример 8 — ЛИД ВЕДЁТ ИГРОК. Трек играет всё, кроме главной партии; её
## ноты выдаются по нажатию.
##
## Ради этого в плагине есть две вещи, и обе видны здесь:
##   • `layers()` — партии кода по именам меток. Метка, начатая подчёркиванием
##     (`_lead:`), в Strudel заглушена: движок её не играет. Но взять её можно,
##     и она приходит целой — с нотами, голосом и всеми параметрами.
##   • `trigger()` — сыграть событие немедленно, вне всякого паттерна, тем же
##     путём, каким играются ноты трека. Голос любой: синтез, волновая
##     таблица, сэмпл.
##
## Отсюда и весь приём: трек идёт своим чередом, а лид звучит тогда, когда
## нажал человек, и ровно тем голосом, который задуман в треке.
##
## Пробел или щелчок — сыграть следующую ноту лида. Esc — выход.

const CODE := """setcpm(110/4)

// Ритм и бас играет движок.
$: s("bd ~ [bd bd] ~").gain(0.9)
$: s("hh*8").gain(0.28).pan(sine.slow(4))
$: note("<c2 c2 ab1 bb1>").s("sawtooth").lpf(600).gain(0.5)

// А ЭТУ партию движок не играет: метка начата подчёркиванием. Её ноты
// выдаются по нажатию — см. `_hit()`.
_lead: note("c4 eb4 g4 bb4 c5 bb4 g4 eb4").s("triangle").gain(0.7).room(0.3)
"""

var music: StrudelPlayer
var _lead: StrudelPattern = null
var _notes: Array = []
var _next := 0
var _played := 0
var _flash := 0.0
var _last := ""
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	music = StrudelPlayer.new()
	music.samples_path = "res://examples/02_own_samples"
	add_child(music)

	if not music.play(CODE):
		push_error("Strudel: " + music.last_error())
		return

	# Партия по имени метки — без подчёркивания, оно только глушит.
	_lead = music.layer("lead")
	if _lead == null:
		push_error("не нашлась партия \"lead\"")
		return
	# Ноты берём на один круг вперёд и раздаём по нажатию. Круг кончится —
	# начнём его заново: партия зациклена, как и всё в Strudel.
	_notes = _lead.query_arc(0.0, 1.0)
	print("Партий в коде: %s. Нот у лида: %d. Пробел — сыграть, Esc — выход."
		% [str(music.layers().keys()), _notes.size()])
	set_process(true)


func _hit() -> void:
	if _notes.is_empty():
		return
	var hap = _notes[_next % _notes.size()]
	_next += 1
	_played += 1
	# То же событие, что сыграл бы движок сам, — только в наш миг.
	music.trigger(hap.value, 0.35)
	_flash = 1.0
	var value: Dictionary = hap.value if hap.value is Dictionary else {}
	_last = "%s · %s" % [
		StrudelUtil.text(value.get("s", "—")),
		str(value.get("note", "—")),
	]
	queue_redraw()


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.065, 0.09))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.66, 0.92, _flash * 0.12))

	draw_string(_font, Vector2(48, 74), "Лид ведёт игрок",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.90, 0.93, 0.96))
	draw_string(_font, Vector2(48, 112),
		"трек играет всё, кроме главной партии — её выдаёт нажатие",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.52, 0.58, 0.67))

	var mid := size * 0.5
	var r := 46.0 + _flash * 26.0
	draw_circle(mid, r, Color(0.52, 0.86, 0.68, 0.25 + _flash * 0.6))
	draw_string(_font, Vector2(48, size.y - 96),
		"нот сыграно: %d   следующая: %d из %d" % [_played, (_next % maxi(_notes.size(), 1)) + 1, _notes.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.72, 0.78, 0.86))
	if _last != "":
		draw_string(_font, Vector2(48, size.y - 68), "последняя: " + _last,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.52, 0.58, 0.67))
	draw_string(_font, Vector2(48, size.y - 40), "ПРОБЕЛ или щелчок — сыграть   ·   ESC — выход",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.42, 0.47, 0.56))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_hit()
			KEY_ESCAPE:
				get_tree().quit()
	elif event is InputEventMouseButton and event.pressed:
		_hit()
