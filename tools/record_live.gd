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
var _gmfonts := ""
var _rec: AudioEffectRecord = null
var _music: StrudelPlayer = null
var _t := 0.0
var _started := false
## Сторож: отдельный поток печатает стадию движка и простой главного потока.
var _watch := false
var _dog: Thread = null
var _dog_stop := false
var _last_tick := 0
## Сколько миллисекунд жечь в каждом кадре — подделка под тяжёлую игру.
var _burn := 0.0
## Каждые N секунд заново разобрать код и подменить паттерн — как игра при
## смене состава. Ноль — не подменять.
var _swap := 0.0
var _swap_at := 0.0
var _swaps := 0


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
		elif s.begins_with("--gmfonts="):
			_gmfonts = s.substr(10)
		elif s.begins_with("--watch="):
			_watch = s.substr(8) != "0"
		elif s.begins_with("--burn="):
			_burn = s.substr(7).to_float()
		elif s.begins_with("--swap="):
			_swap = s.substr(7).to_float()
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


func _dog_loop() -> void:
	## Каждую секунду: стадия движка, отсчётов написано, простой главного потока,
	## кто держит замок опроса и жив ли рабочий. Если главный поток встал
	## намертво, эти строки всё равно идут — и показывают место клинча.
	var t0 := Time.get_ticks_msec()
	var main_id := str(OS.get_main_thread_id())
	while not _dog_stop:
		OS.delay_msec(1000)
		var eng = _music._engine if _music != null else null
		var stage := str(eng.stage) if eng != null else "-"
		var frames := int(eng._frames_written) if eng != null else 0
		var stall := Time.get_ticks_msec() - _last_tick
		var live := 0
		if eng != null:
			for v in eng._voices:
				if v.active:
					live += 1
		var holder := String(StrudelPattern.lock_holder)
		var h := "-" if holder == "" else ("главный" if holder == main_id else "рабочий")
		var worker := "нет"
		if eng != null and eng._q_thread != null:
			worker = ("жив" if eng._q_thread.is_alive() else "мёртв") + " занят=%.3f" % float(eng._q_busy_c0)
		var line := "[сторож] %4ds стадия=%-24s кадров=%9d голосов=%2d простой=%5d мс замок=%s рабочий=%s" % [
			(Time.get_ticks_msec() - t0) / 1000, stage, frames, live, stall, h, worker]
		if stall > 3000:
			line += "  ◀ ГЛАВНЫЙ ПОТОК СТОИТ"
		print(line)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_music = StrudelPlayer.new()
		_music.max_voices = 96
		_music.native_effects = _native
		if _samples != "":
			_music.samples_path = _samples
		if _gmfonts != "":
			_music.gm_fonts_path = _gmfonts
		root.add_child(_music)
		if not _music.play(_code):
			printerr("[живая запись] код не принят: ", _music.last_error())
			quit(1)
			return true
		_rec.set_recording_active(true)
		if _watch:
			_dog = Thread.new()
			_dog.start(_dog_loop)
		return false
	_last_tick = Time.get_ticks_msec()
	if _burn > 0.0:
		# Занять главный поток, как это делает игра: физика, вода, отклики.
		var until := Time.get_ticks_usec() + int(_burn * 1000.0)
		while Time.get_ticks_usec() < until:
			pass
	_t += delta
	if _swap > 0.0 and _t - _swap_at >= _swap:
		_swap_at = _t
		_swaps += 1
		# Новый объект паттерна из того же кода: ровно то, что делает игра
		# через set_mood → _build → set_pattern.
		var run: Dictionary = StrudelRuntime.run(_code)
		if run.get("ok", false):
			_music.set_pattern(run["pattern"])
	if _t < _seconds:
		return false
	_rec.set_recording_active(false)
	_dog_stop = true
	if _dog != null:
		_dog.wait_to_finish()
	_music.stop()
	var wav: AudioStreamWAV = _rec.get_recording()
	if wav == null:
		printerr("[живая запись] запись пуста")
		quit(1)
		return true
	wav.save_to_wav(_out)
	print("[живая запись] %s: %.1f с, зал %s, подмен паттерна %d" % [_out, _seconds, "штатный" if _native else "свой", _swaps])
	quit(0)
	return true
