extends Node

## Пример 1 — самое короткое, что вообще можно написать.
##
## Три строки: создать узел, добавить в сцену, дать код Strudel.
## Никакой настройки не нужно — сэмплов нет, всё звучит синтезом.

var music: StrudelPlayer
var _elapsed := 0.0


func _ready() -> void:
	music = StrudelPlayer.new()
	add_child(music)
	music.play('s("bd sd*2, ~ hh")')

	# Дальше — только для проверки: сколько всего наиграло.
	print("Strudel: играю. Esc — выход.")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 1.0:
		_elapsed = 0.0
		var s := music.stats()
		print("цикл %.2f · голосов %d · событий %d · вытеснено %d"
			% [s.get("цикл", 0.0), s.get("голосов_звучит", 0),
			   s.get("событий_сыграно", 0), s.get("вытеснено", 0)])
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()
