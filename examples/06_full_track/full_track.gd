extends Node

## Пример 6 — ГЛАВНАЯ ПРИЁМКА: целый трек из Strudel играет в Godot.
##
## Файл kuvshinka.js — настоящий трек: стек из десяти партий, форма из
## шестнадцати секций, аккордовый круг, свинг, вероятностное прореживание.
## Он вставлен сюда БЕЗ ЕДИНОЙ ПРАВКИ — тот же текст, что в браузере.

const TRACK := "res://examples/full_track/kuvshinka.js"

var music: StrudelPlayer


func _ready() -> void:
	var file := FileAccess.open(TRACK, FileAccess.READ)
	if file == null:
		push_error("не нашёл трек: " + TRACK)
		return

	music = StrudelPlayer.new()
	music.max_voices = 96
	add_child(music)
	music.play(file.get_as_text())
	file.close()

	# Музыка может вести игру: сигнал приходит на каждое событие паттерна.
	music.event_played.connect(_on_event)

	print("Кувшинка · lofi — 16 секций, около 3 минут 22 секунд.")
	print("Esc — выход.")


var _beats := 0

func _on_event(value: Dictionary) -> void:
	if String(value.get("s", "")) == "bd":
		_beats += 1


func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()


func _exit_tree() -> void:
	if music != null:
		print("сыграно событий: %d, из них бочек: %d" % [music.stats().get("событий_сыграно", 0), _beats])
