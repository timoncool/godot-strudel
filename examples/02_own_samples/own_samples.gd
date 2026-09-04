extends Node

## Пример 2 — СВОЙ БАНК СЭМПЛОВ.
##
## Плагин читает карты в формате Strudel: `имя: [файлы]` — перебор по `n`,
## `имя: {нота: файл}` — многосэмплированный инструмент. Рядом лежит
## `mypack.json` ровно такого вида, а звуки к нему делает `make_pack.py`:
## ни одного чужого файла в поставке и ни одного обращения в сеть.
##
## Папка указывается одним полем `samples_path` — больше ничего не нужно.

const PACK := "res://examples/02_own_samples"

const CODE := """
setcpm(110/4)
$: s("bd ~ [bd bd] sd").gain(0.9)
$: s("hh*8").gain(0.35).pan(sine.slow(4))
$: note("<c3 g3 c4 g3>").s("bell").gain(0.6).room(0.4)
"""

var music: StrudelPlayer


func _ready() -> void:
	music = StrudelPlayer.new()
	# 🔴 Папка ставится ДО добавления в дерево: банк читается в `_ready`
	# самого узла, и после него поле уже не спросят.
	music.samples_path = PACK
	add_child(music)

	var bank := music.get_bank()
	if bank == null or bank.is_empty():
		push_error("пак не собран — запусти: python examples/02_own_samples/make_pack.py")
		return
	var names: Array = bank.entries.keys()
	names.sort()
	print("Свой банк: %d наборов — %s" % [bank.count(), ", ".join(PackedStringArray(names))])

	music.play(CODE)
	print("Играют СВОИ сэмплы: bd/sd/hh перебором, bell по нотам. Esc — выход.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()
