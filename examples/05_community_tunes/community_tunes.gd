extends Node

## Пример 7 — ЧУЖИЕ ТРЕКИ. Коллекция Strudel играет в Godot как есть.
##
## В `examples/05_community_tunes/tunes/` лежат тридцать два куска из `website/src/repl/tunes.mjs`
## — партии живых авторов, взятые БЕЗ ЕДИНОЙ ПРАВКИ. Это и есть настоящая
## приёмка порта: не один подогнанный трек, а чужой код.
##
## Пробел — следующий трек, стрелки — соседний, Esc — выход.
## Можно и с ключом запуска: `-- --tune=giantSteps`.

const TUNES_DIR := "res://examples/05_community_tunes/tunes"

var music: StrudelPlayer
var _names: PackedStringArray = PackedStringArray()
var _current := 0
var _events := 0


func _ready() -> void:
	_names = _list_tunes()
	if _names.is_empty():
		push_error("нет треков в " + TUNES_DIR)
		return

	music = StrudelPlayer.new()
	# 🔴 Голосов нужно много: у чужих треков бывает по десятку слоёв, и на
	# пределе в тридцать два голоса начало бы вытеснять живые ноты.
	music.max_voices = 96
	add_child(music)
	music.event_played.connect(func(_v: Dictionary) -> void: _events += 1)

	_current = _pick_from_args()
	_play(_current)
	print("Треков: %d. Пробел — следующий, стрелки — соседний, Esc — выход."
		% _names.size())


func _list_tunes() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TUNES_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		# 🔴 В собранной игре у файлов появляется хвост `.remap`: движок
		# кладёт рядом с ресурсом пометку о переносе. Без обрезки список
		# в сборке выходил пустым.
		var clean := name.trim_suffix(".remap")
		if clean.ends_with(".js"):
			out.append(clean)
	out.sort()
	return out


func _pick_from_args() -> int:
	for arg in OS.get_cmdline_user_args():
		if not String(arg).begins_with("--tune="):
			continue
		var want := String(arg).substr(7)
		for i in _names.size():
			if _names[i].get_basename() == want:
				return i
		push_warning("нет трека \"%s\" — играю первый" % want)
	return 0


func _play(index: int) -> void:
	var path := TUNES_DIR.path_join(_names[index])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("не прочитал " + path)
		return
	var code := file.get_as_text()
	file.close()
	_events = 0
	music.play(code)
	print("▶ %s (%d из %d)" % [_names[index].get_basename(), index + 1, _names.size()])


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_SPACE, KEY_RIGHT:
			_current = (_current + 1) % _names.size()
			_play(_current)
		KEY_LEFT:
			_current = (_current - 1 + _names.size()) % _names.size()
			_play(_current)


func _exit_tree() -> void:
	if music != null:
		print("событий у последнего трека: %d" % _events)
