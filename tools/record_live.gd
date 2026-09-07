@tool
extends SceneTree

## Записать ЖИВОЙ выход плеера — со штатными залом и эхом на шинах — в WAV.
##
##   godot --path . --script res://tools/record_live.gd -- \
##         --file=<код.js> --samples=<папка> --out=<файл.wav> --seconds=8 [--native=0]
##
## Зачем отдельно от `render_wav.gd`: тот считает звук без звукового сервера
## и штатных узлов не видит. Здесь всё как у игрока: узел StrudelPlayer,
## шины, узлы Godot, — и запись снимается с мастера. Именно этим файлом
## сверяется с записью из Булки то, что человек слышит на самом деле.
## `--native=0` — тот же путь, но зал и эхо считает сам плагин.

var _out := ""
var _seconds := 8.0
var _code := ""
var _samples := ""
var _native := true
var _rec: AudioEffectRecord = null
var _music: StrudelPlayer = null
var _t := 0.0
var _started := false


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var s := String(arg)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--seconds="):
			_seconds = s.substr(10).to_float()
		elif s.begins_with("--samples="):
			_samples = s.substr(10)
		elif s.begins_with("--native="):
			_native = s.substr(9) != "0"
		elif s.begins_with("--code="):
			_code = s.substr(7)
		elif s.begins_with("--file="):
			var f := FileAccess.open(s.substr(7), FileAccess.READ)
			if f == null:
				printerr("[живая запись] не прочитал ", s.substr(7))
				quit(1)
				return
			_code = f.get_as_text()
			f.close()
	_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, _rec)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_music = StrudelPlayer.new()
		_music.max_voices = 96
		_music.native_effects = _native
		if _samples != "":
			_music.samples_path = _samples
		root.add_child(_music)
		if not _music.play(_code):
			printerr("[живая запись] код не принят: ", _music.last_error())
			quit(1)
			return true
		_rec.set_recording_active(true)
		return false
	_t += delta
	if _t < _seconds:
		return false
	_rec.set_recording_active(false)
	_music.stop()
	var wav: AudioStreamWAV = _rec.get_recording()
	if wav == null:
		printerr("[живая запись] запись пуста")
		quit(1)
		return true
	wav.save_to_wav(_out)
	print("[живая запись] %s: %.1f с, зал %s" % [_out, _seconds, "штатный" if _native else "свой"])
	quit(0)
	return true
