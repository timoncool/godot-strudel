@tool
extends SceneTree

## Выводит код Strudel в WAV без звуковой карты.
##
##   godot --headless --path <проект> --script res://tools/render_wav.gd -- \
##         --code='s("bd sd*2, hh*8")' --out=D:/out.wav --seconds=8
##   godot ... -- --file=res://examples/full_track/kuvshinka.js --out=... --seconds=30
##
## Зачем: доказать, что звук ЕСТЬ, не имея устройства вывода (в CI его нет),
## и получить файл, который сверяется по спектру и уровню с записью из Булки.

var _code := ""
var _out := ""
var _seconds := 8.0
var _samples := ""
var _cpm := 0.0


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--code="):
			_code = arg.substr(7)
		elif arg.begins_with("--file="):
			var f := FileAccess.open(arg.substr(7), FileAccess.READ)
			if f == null:
				printerr("[рендер] не прочитал ", arg.substr(7))
				quit(1)
				return
			_code = f.get_as_text()
			f.close()
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--seconds="):
			_seconds = arg.substr(10).to_float()
		elif arg.begins_with("--samples="):
			_samples = arg.substr(10)
		elif arg.begins_with("--cpm="):
			_cpm = arg.substr(6).to_float()

	if _code == "" or _out == "":
		printerr("[рендер] нужны --code=… или --file=…, и --out=…")
		quit(1)
		return

	var run: Dictionary = StrudelRuntime.run(_code)
	if not run.get("ok", false):
		printerr("[рендер] код не разобрался: ", run.get("error", "?"))
		quit(1)
		return

	var rate := 48000.0
	var engine := StrudelEngine.new()
	engine.max_voices = 128
	engine.setup(rate)
	if _samples != "":
		var bank := StrudelSampleBank.new()
		var n := bank.load_folder(_samples)
		engine.bank = bank
		print("[рендер] сэмплов в банке: ", n)
	engine.set_pattern(run["pattern"])
	var cps: float = run.get("cps", 0.0)
	if _cpm > 0.0:
		cps = _cpm / 60.0
	if cps > 0.0:
		engine.set_cps(cps)

	var frames := int(_seconds * rate)
	var block := 2048
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(frames)
	right.resize(frames)

	var started := Time.get_ticks_usec()
	var done := 0
	while done < frames:
		var n := mini(block, frames - done)
		var chunk: Array = engine.render_block(n)
		var cl: PackedFloat32Array = chunk[0]
		var cr: PackedFloat32Array = chunk[1]
		for i in n:
			left[done + i] = cl[i]
			right[done + i] = cr[i]
		done += n
	var spent := (Time.get_ticks_usec() - started) / 1000.0

	var peak := 0.0
	var sum_sq := 0.0
	for i in frames:
		peak = maxf(peak, maxf(absf(left[i]), absf(right[i])))
		sum_sq += left[i] * left[i] + right[i] * right[i]
	var rms := sqrt(sum_sq / float(frames * 2))

	_write_wav(_out, left, right, int(rate))

	print("[рендер] %.1f с звука за %.0f мс (%.1f%% реального времени)"
		% [_seconds, spent, spent / (_seconds * 1000.0) * 100.0])
	print("[рендер] пик %.4f (%.1f дБ), СКЗ %.5f (%.1f дБ)"
		% [peak, linear_to_db(maxf(peak, 1e-9)), rms, linear_to_db(maxf(rms, 1e-9))])
	print("[рендер] событий %d, вытеснено голосов %d"
		% [engine.played_events, engine.stolen_voices])
	if peak < 1e-6:
		printerr("[рендер] ТИШИНА — звука нет")
		quit(1)
		return
	print("[рендер] записано: ", _out)
	quit(0)


func _write_wav(path: String, left: PackedFloat32Array, right: PackedFloat32Array, rate: int) -> void:
	## 16-битный стерео WAV — понимает всё, чем потом смотрят спектр.
	var frames := left.size()
	var data := PackedByteArray()
	data.resize(frames * 4)
	for i in frames:
		var l := int(clampf(left[i], -1.0, 1.0) * 32767.0)
		var r := int(clampf(right[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 4, l)
		data.encode_s16(i * 4 + 2, r)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[рендер] не открыл на запись: ", path)
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)          # длина блока формата
	f.store_16(1)           # PCM
	f.store_16(2)           # каналов
	f.store_32(rate)
	f.store_32(rate * 4)    # байт в секунду
	f.store_16(4)           # выравнивание кадра
	f.store_16(16)          # бит на отсчёт
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
