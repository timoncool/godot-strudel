@tool
class_name StrudelReverb
extends RefCounted

## Реверберация по схеме Шрёдера: четыре гребенчатых фильтра и два всепропускающих.
##
## В Strudel `room` — это ОТПРАВКА на общий ревербератор с импульсным откликом
## (`reverbGen.mjs`), а не эффект на голос. Здесь то же устройство отправки, но
## сам ревербератор — рекурсивный: свёртка с откликом на GDScript обошлась бы
## дороже всего остального вместе взятого.
##
## Расхождение с оригиналом честно записано в docs/COMPARISON.md: хвост звучит
## близко, но не тождественно.

const COMB_MS := [29.7, 37.1, 41.1, 43.7]
const ALLPASS_MS := [5.0, 1.7]

var room_size := 0.7
var damping := 0.4

var _combs: Array = []
var _comb_idx: PackedInt32Array = PackedInt32Array()
var _comb_store: PackedFloat32Array = PackedFloat32Array()
var _allpass: Array = []
var _ap_idx: PackedInt32Array = PackedInt32Array()
var _rate := 48000.0


func setup(rate: float) -> void:
	_rate = rate
	_combs.clear()
	_allpass.clear()
	_comb_idx = PackedInt32Array()
	_ap_idx = PackedInt32Array()
	_comb_store = PackedFloat32Array()
	for ms in COMB_MS:
		var line := PackedFloat32Array()
		line.resize(maxi(int(rate * ms / 1000.0), 1))
		_combs.append(line)
		_comb_idx.append(0)
		_comb_store.append(0.0)
	for ms in ALLPASS_MS:
		var line := PackedFloat32Array()
		line.resize(maxi(int(rate * ms / 1000.0), 1))
		_allpass.append(line)
		_ap_idx.append(0)


func render(send: PackedFloat32Array, left: PackedFloat32Array, right: PackedFloat32Array, count: int) -> void:
	if _combs.is_empty():
		return
	var feedback := clampf(0.7 + room_size * 0.28, 0.0, 0.98)
	var damp := clampf(damping, 0.0, 0.95)

	for i in count:
		var input: float = send[i]
		if input == 0.0 and _silent():
			continue
		var acc := 0.0
		for c in _combs.size():
			var line: PackedFloat32Array = _combs[c]
			var idx: int = _comb_idx[c]
			var sample: float = line[idx]
			acc += sample
			# затухание высоких в хвосте
			_comb_store[c] = sample * (1.0 - damp) + _comb_store[c] * damp
			line[idx] = input + _comb_store[c] * feedback
			_comb_idx[c] = (idx + 1) % line.size()
		acc /= float(_combs.size())

		for a in _allpass.size():
			var line2: PackedFloat32Array = _allpass[a]
			var idx2: int = _ap_idx[a]
			var buffered: float = line2[idx2]
			var out := buffered - acc
			line2[idx2] = acc + buffered * 0.5
			_ap_idx[a] = (idx2 + 1) % line2.size()
			acc = out

		# Лёгкое расхождение каналов — иначе хвост звучит «в точке».
		left[i] += acc * 0.6
		right[i] += acc * 0.55


func _silent() -> bool:
	for v in _comb_store:
		if absf(v) > 1e-6:
			return false
	return true
