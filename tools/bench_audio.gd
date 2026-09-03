@tool
extends SceneTree

## Замер, которым выбирается устройство звука: GDScript против нативного кода.
##
##   godot --headless --path <проект> --script res://tools/bench_audio.gd
##
## Считаем ЧЕСТНО: сколько процессорного времени уходит на выработку одной
## секунды звука при разном числе голосов. Бюджет — одна секунда звука должна
## обходиться заметно дешевле секунды реального времени, иначе на игру ничего
## не останется.

const RATE := 48000
const SECONDS := 1.0


func _init() -> void:
	print("[замер] частота %d Гц, отрезок %.0f с" % [RATE, SECONDS])
	print("")

	# Сэмпл, по которому ходим (одна секунда пилы — лишь бы читать из памяти).
	var sample := PackedFloat32Array()
	sample.resize(RATE)
	for i in RATE:
		sample[i] = fmod(float(i) / 100.0, 1.0) * 2.0 - 1.0

	print("сведение сэмплов с интерполяцией, огибающей и панорамой:")
	for voices in [1, 8, 16, 32, 64, 128]:
		var ms := _bench_sampler(sample, voices)
		_report(voices, ms)

	print("")
	print("синтез пилы посэмплно (без сэмплов, чистая арифметика):")
	for voices in [1, 8, 16, 32, 64]:
		var ms := _bench_synth(voices)
		_report(voices, ms)

	print("")
	print("тот же синтез, но через PackedFloat32Array целиком (без пер-сэмплового цикла на голос):")
	var ms_bulk := _bench_bulk(16)
	_report(16, ms_bulk)

	quit(0)


func _report(voices: int, ms: float) -> void:
	var realtime := SECONDS * 1000.0
	var share := ms / realtime * 100.0
	var verdict := "укладывается"
	if share > 50.0:
		verdict = "НЕ УКЛАДЫВАЕТСЯ"
	elif share > 20.0:
		verdict = "впритык"
	print("  голосов %3d: %8.1f мс на секунду звука — %6.1f%% реального времени, %s"
		% [voices, ms, share, verdict])


func _bench_sampler(sample: PackedFloat32Array, voices: int) -> float:
	var frames := int(RATE * SECONDS)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(frames)
	right.resize(frames)

	var positions := PackedFloat64Array()
	var rates := PackedFloat64Array()
	var pans := PackedFloat32Array()
	positions.resize(voices)
	rates.resize(voices)
	pans.resize(voices)
	for v in voices:
		positions[v] = 0.0
		rates[v] = 0.5 + float(v) * 0.01
		pans[v] = float(v) / float(maxi(voices - 1, 1))

	var started := Time.get_ticks_usec()
	var size := sample.size()
	for v in voices:
		var pos: float = positions[v]
		var rate: float = rates[v]
		var pan: float = pans[v]
		var gl := sqrt(1.0 - pan)
		var gr := sqrt(pan)
		for i in frames:
			var idx := int(pos)
			if idx >= size - 1:
				break
			# линейная интерполяция между соседними отсчётами
			var frac := pos - float(idx)
			var s: float = sample[idx] * (1.0 - frac) + sample[idx + 1] * frac
			# простая огибающая: спад за секунду
			var env := 1.0 - float(i) / float(frames)
			s *= env
			left[i] += s * gl
			right[i] += s * gr
			pos += rate
	return (Time.get_ticks_usec() - started) / 1000.0


func _bench_synth(voices: int) -> float:
	var frames := int(RATE * SECONDS)
	var out := PackedFloat32Array()
	out.resize(frames)
	var started := Time.get_ticks_usec()
	for v in voices:
		var phase := 0.0
		var step := (110.0 * (1.0 + float(v) * 0.05)) / float(RATE)
		for i in frames:
			phase += step
			if phase >= 1.0:
				phase -= 1.0
			out[i] += (phase * 2.0 - 1.0) * 0.1
	return (Time.get_ticks_usec() - started) / 1000.0


func _bench_bulk(voices: int) -> float:
	## Тот же объём работы, но с минимумом обращений к массиву на итерацию.
	var frames := int(RATE * SECONDS)
	var out := PackedFloat32Array()
	out.resize(frames)
	var started := Time.get_ticks_usec()
	for v in voices:
		var phase := 0.0
		var step := (110.0 * (1.0 + float(v) * 0.05)) / float(RATE)
		var i := 0
		while i < frames:
			phase += step
			if phase >= 1.0:
				phase -= 1.0
			out[i] = out[i] + (phase * 2.0 - 1.0) * 0.1
			i += 1
	return (Time.get_ticks_usec() - started) / 1000.0
