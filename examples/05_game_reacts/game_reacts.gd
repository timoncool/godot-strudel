extends Node2D

## Пример 5 — игра дышит в такт музыке.
##
## Плагин шлёт сигнал на КАЖДОЕ событие паттерна: имя звука, нота, громкость,
## панорама. Игре не нужно знать про доли и такты — она просто слушает.
##
## Здесь события выкладываются лентой: слева уходящее прошлое, справа — то,
## что только что прозвучало. Высота — это высота ноты, цвет — партия,
## размер — громкость.

const TRACK := """
setcpm(120/4)

const drums = stack(
  s("bd ~ bd ~"),
  s("~ sd ~ sd"),
  s("hh*8").gain(0.35)
)

const bass = note("<c2 eb2 g2 bb1>").s("sawtooth")
  .lpf(sine.range(300, 1400).slow(4)).gain(0.3)

const lead = n("0 2 4 <6 5>").scale("C4:minor").s("triangle")
  .struct("x ~ x x ~ x ~ ~").gain(0.22).room(0.4)

$: stack(drums, bass, lead)
"""

const KEEP := 240.0
const LANE_TOP := 0.16
const LANE_BOTTOM := 0.86

class Mark:
	var age := 0.0
	var height := 0.5
	var size := 6.0
	var color := Color.WHITE
	var pan := 0.5

var _marks: Array[Mark] = []
var _music: StrudelPlayer
var _font: Font
var _flash := 0.0

# Снимок для документации: --shot=<файл> --warm=<секунд>
var _shot_path := ""
var _shot_at := 4.0
var _clock := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_music = StrudelPlayer.new()
	_music.max_voices = 48
	add_child(_music)
	_music.event_played.connect(_on_event)
	_music.play(TRACK)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.substr(7)
		elif arg.begins_with("--warm="):
			_shot_at = arg.substr(7).to_float()


func _on_event(value: Dictionary) -> void:
	var mark := Mark.new()
	var sound := String(value.get("s", ""))
	var gain := clampf(float(value.get("gain", 0.5)), 0.02, 1.5)
	mark.pan = clampf(float(value.get("pan", 0.5)), 0.0, 1.0)

	match sound:
		"bd":
			mark.height = 0.06
			mark.size = 15.0
			mark.color = Color(0.45, 0.66, 0.92)
			_flash = 1.0
		"sd":
			mark.height = 0.30
			mark.size = 11.0
			mark.color = Color(0.94, 0.65, 0.38)
		"hh":
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
	_marks = _marks.filter(func(m: Mark): return m.age < KEEP)
	queue_redraw()

	if _shot_path != "" and _clock >= _shot_at:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(_shot_path)
		print("снимок: ", _shot_path)
		get_tree().quit()
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.065, 0.09))

	# лёгкая вспышка на бочке — «игра слышит музыку»
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.52, 0.78, _flash * 0.07))

	var top := size.y * LANE_TOP
	var bottom := size.y * LANE_BOTTOM
	var right := size.x - 60.0

	# направляющие
	for k in 5:
		var y := lerpf(top, bottom, float(k) / 4.0)
		draw_line(Vector2(60, y), Vector2(right, y), Color(1, 1, 1, 0.035), 1.0)

	# лента событий: справа — только что прозвучавшее
	for m in _marks:
		var x := right - m.age * ((right - 60.0) / KEEP)
		if x < 60.0:
			continue
		var y := lerpf(bottom, top, m.height)
		var fade := clampf(1.0 - m.age / KEEP, 0.0, 1.0)
		var c := m.color
		c.a = 0.25 + fade * 0.7
		draw_circle(Vector2(x, y), m.size * (0.55 + fade * 0.45), c)

	# «сейчас»
	draw_line(Vector2(right, top - 14), Vector2(right, bottom + 14), Color(1, 1, 1, 0.22), 2.0)

	var stats := _music.stats()
	draw_string(_font, Vector2(60, 52), "Strudel for Godot",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.90, 0.93, 0.96))
	draw_string(_font, Vector2(60, 80),
		"код Strudel вставлен без правок · цикл %.2f · голосов %d · событий %d"
			% [stats.get("цикл", 0.0), stats.get("голосов_звучит", 0), stats.get("событий_сыграно", 0)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.52, 0.58, 0.67))

	var legend := [
		["бочка", Color(0.45, 0.66, 0.92)],
		["снейр", Color(0.94, 0.65, 0.38)],
		["хэт", Color(0.62, 0.68, 0.78)],
		["ноты", Color(0.52, 0.86, 0.68)],
	]
	var lx := 60.0
	for item in legend:
		draw_circle(Vector2(lx, size.y - 40), 6.0, item[1])
		draw_string(_font, Vector2(lx + 14, size.y - 34), String(item[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.56, 0.65))
		lx += 110.0
