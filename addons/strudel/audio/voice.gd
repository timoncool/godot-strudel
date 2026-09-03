@tool
class_name StrudelVoice
extends RefCounted

## Один звучащий голос: источник, огибающая, цепь эффектов, панорама.
##
## Цепь идёт В ТОМ ЖЕ ПОРЯДКЕ, что в `packages/superdough/superdough.mjs`
## (номера строк оригинала):
##
##   источник → gain(706) → lpf(737) → hpf(774) → bpf(809) → vowel(823)
##   → coarse(830) → crush(835) → shape(840) → distort(845) → tremolo(878)
##   → compressor(891) → pan(899) → phaser(913) → delay(925) → room(960)
##   → release(973) → postgain(979)
##
## 🔴 Порядок менять «как удобнее» нельзя: `crush` до фильтра и после фильтра
## звучат по-разному, и это слышно.
##
## Пила и меандр строятся с PolyBLEP — скруглением скачка. Наивные «зубцы»
## дают призвуки на высоких (алиасинг): сверка со звуком Булки показывала
## лишние 8-12 дБ выше двух килогерц, потому что в WebAudio осцилляторы
## ограничены по полосе, а прямой отсчёт `2*фаза-1` — нет.

enum Source { SILENCE, SINE, SAW, SQUARE, TRIANGLE, WHITE, PINK, BROWN, SAMPLE }

## Что звучит.
var source: Source = Source.SINE
## Данные сэмпла (моно, уже приведённые к частоте движка при загрузке).
var sample: PackedFloat32Array = PackedFloat32Array()
var sample_rate := 48000.0
var sample_loop := false

var frequency := 440.0
var speed := 1.0
var gain := 1.0
var postgain := 1.0
## Панорама. Отрицательное значение — «панорамы НЕТ».
##
## 🔴 Strudel вставляет панораматор ТОЛЬКО когда `pan` задан явно
## (`superdough.mjs:898`, `if (fx.pan !== undefined)`). Если панорамировать
## всегда, равномощная панорама в середине даёт множитель 1/√2 — ровно
## три децибела тише эталона по ВСЕМ полосам. Так это и нашлось сверкой.
var pan := -1.0

var envelope: StrudelEnvelope = null
var note_length := 0.5

## Фильтры: 0 — выключен.
var lpf := 0.0
var lpq := 1.0
var hpf := 0.0
var hpq := 1.0

var crush := 0.0
var coarse := 0.0
var shape := 0.0

## Отправки на общие эффекты.
var room := 0.0
var delay_send := 0.0
var orbit := 0

## Голос ещё звучит.
var active := false
## Сколько отсчётов уже сыграно.
var _pos := 0
## Сколько отсчётов молчать перед началом — так удар попадает на ТОЧНЫЙ
## отсчёт внутри буфера, а не на его границу.
var start_delay := 0
var _phase := 0.0
var _sample_pos := 0.0
var _rate := 48000.0
var _brown := 0.0
var _pink := PackedFloat32Array()
# Состояния биквадов (по два прошлых входа и выхода).
var _lp := [0.0, 0.0, 0.0, 0.0]
var _hp := [0.0, 0.0, 0.0, 0.0]
var _lp_coef := PackedFloat32Array()
var _hp_coef := PackedFloat32Array()
var _coarse_hold := 0.0
var _coarse_count := 0


func start(mix_rate: float) -> void:
	_rate = mix_rate
	_pos = 0
	_phase = 0.0
	_sample_pos = 0.0
	_brown = 0.0
	_pink = PackedFloat32Array()
	_pink.resize(7)
	_lp = [0.0, 0.0, 0.0, 0.0]
	_hp = [0.0, 0.0, 0.0, 0.0]
	_coarse_hold = 0.0
	_coarse_count = 0
	if envelope == null:
		envelope = StrudelEnvelope.new()
	_lp_coef = _biquad_lowpass(lpf, lpq) if lpf > 0.0 else PackedFloat32Array()
	_hp_coef = _biquad_highpass(hpf, hpq) if hpf > 0.0 else PackedFloat32Array()
	active = true


func total_frames() -> int:
	return int(envelope.total_length(note_length) * _rate)


func render(left: PackedFloat32Array, right: PackedFloat32Array, from_frame: int, count: int,
		room_bus: PackedFloat32Array, delay_bus: PackedFloat32Array) -> void:
	## Досыпает свой звук в общий буфер, начиная с кадра from_frame.
	if not active:
		return
	var total := total_frames()
	# Панорама равной мощности — как StereoPanner в WebAudio, но только если
	# её просили: без `pan` сигнал идёт в оба канала целиком.
	var gl := 1.0
	var gr := 1.0
	if pan >= 0.0:
		var angle := pan * (PI * 0.5)
		gl = cos(angle)
		gr = sin(angle)

	# 🔴 Всё, что можно, вынесено ИЗ цикла и развёрнуто в локальные переменные.
	# Вызов функции в GDScript стоит дороже самой арифметики: пока огибающая,
	# биквад и источник звука были отдельными методами, голос обходился вшестеро
	# дороже, чем та же математика в теле цикла (замерено tools/bench_audio.gd).
	var buf_len := left.size()
	var pos := _pos
	var phase := _phase
	var spos := _sample_pos
	var rate := _rate
	var src := source
	var g := gain
	var post := postgain
	var freq_step := frequency * speed / rate
	var sample_step := speed * (sample_rate / rate)
	var sample_last := sample.size() - 1

	# огибающая — в отсчётах, без деления на каждом шаге
	var a_end := envelope.attack * rate
	var d_end := a_end + envelope.decay * rate
	var sus := envelope.sustain
	var note_end := note_length * rate
	var rel := envelope.release * rate
	# Уровень, С КОТОРОГО начинается отпускание. У короткой ноты она гаснет
	# ещё на подъёме или на спаде, и брать сустейн нельзя — иначе на коротких
	# нотах звук на треть децибела громче, чем должен быть.
	var rel_from := sus
	if note_end < a_end:
		rel_from = note_end / a_end
	elif note_end < d_end:
		rel_from = 1.0 + (sus - 1.0) * ((note_end - a_end) / (d_end - a_end))

	var use_lp := not _lp_coef.is_empty()
	var use_hp := not _hp_coef.is_empty()
	var lb0 := _lp_coef[0] if use_lp else 0.0
	var lb1 := _lp_coef[1] if use_lp else 0.0
	var lb2 := _lp_coef[2] if use_lp else 0.0
	var la1 := _lp_coef[3] if use_lp else 0.0
	var la2 := _lp_coef[4] if use_lp else 0.0
	var lx1: float = _lp[0]
	var lx2: float = _lp[1]
	var ly1: float = _lp[2]
	var ly2: float = _lp[3]
	var hb0 := _hp_coef[0] if use_hp else 0.0
	var hb1 := _hp_coef[1] if use_hp else 0.0
	var hb2 := _hp_coef[2] if use_hp else 0.0
	var ha1 := _hp_coef[3] if use_hp else 0.0
	var ha2 := _hp_coef[4] if use_hp else 0.0
	var hx1: float = _hp[0]
	var hx2: float = _hp[1]
	var hy1: float = _hp[2]
	var hy2: float = _hp[3]

	var use_crush := crush > 0.0
	var crush_steps := pow(2.0, crush - 1.0) if use_crush else 1.0
	var use_shape := shape > 0.0
	var shape_k := clampf(shape, 0.0, 0.99)
	var shape_f := 2.0 * shape_k / (1.0 - shape_k) if use_shape else 0.0
	var use_coarse := coarse > 1.0
	var coarse_n := int(coarse) if use_coarse else 1
	var use_room := room > 0.0
	var use_delay := delay_send > 0.0

	var i := 0
	while i < count:
		if start_delay > 0:
			start_delay -= 1
			i += 1
			continue
		if pos >= total:
			active = false
			break
		var idx := from_frame + i
		if idx >= buf_len:
			break

		# ── источник ──
		var raw := 0.0
		if src == Source.SAMPLE:
			var si := int(spos)
			if si >= sample_last:
				if sample_loop and sample_last > 0:
					spos = fmod(spos, float(sample_last))
					si = int(spos)
				else:
					active = false
					break
			var fr := spos - float(si)
			raw = sample[si] * (1.0 - fr) + sample[si + 1] * fr
			spos += sample_step
		elif src == Source.SINE:
			raw = sin(TAU * phase)
			phase += freq_step
			if phase >= 1.0:
				phase -= 1.0
		elif src == Source.SAW:
			# PolyBLEP: скругление скачка, чтобы пила не алиасила.
			raw = phase * 2.0 - 1.0
			var bl := 0.0
			if phase < freq_step:
				var q := phase / freq_step
				bl = q + q - q * q - 1.0
			elif phase > 1.0 - freq_step:
				var q2 := (phase - 1.0) / freq_step
				bl = q2 * q2 + q2 + q2 + 1.0
			raw -= bl
			phase += freq_step
			if phase >= 1.0:
				phase -= 1.0
		elif src == Source.SQUARE:
			raw = 1.0 if phase < 0.5 else -1.0
			var b1 := 0.0
			if phase < freq_step:
				var q3 := phase / freq_step
				b1 = q3 + q3 - q3 * q3 - 1.0
			elif phase > 1.0 - freq_step:
				var q4 := (phase - 1.0) / freq_step
				b1 = q4 * q4 + q4 + q4 + 1.0
			var ph2 := phase + 0.5
			if ph2 >= 1.0:
				ph2 -= 1.0
			var b2 := 0.0
			if ph2 < freq_step:
				var q5 := ph2 / freq_step
				b2 = q5 + q5 - q5 * q5 - 1.0
			elif ph2 > 1.0 - freq_step:
				var q6 := (ph2 - 1.0) / freq_step
				b2 = q6 * q6 + q6 + q6 + 1.0
			raw += b1 - b2
			phase += freq_step
			if phase >= 1.0:
				phase -= 1.0
		elif src == Source.TRIANGLE:
			raw = 4.0 * absf(phase - 0.5) - 1.0
			phase += freq_step
			if phase >= 1.0:
				phase -= 1.0
		elif src == Source.WHITE:
			raw = randf() * 2.0 - 1.0
		elif src == Source.PINK:
			raw = _pink_sample()
		elif src == Source.BROWN:
			_brown = clampf(_brown + (randf() * 2.0 - 1.0) * 0.02, -1.0, 1.0)
			raw = _brown * 3.0

		# ── огибающая (тот же расчёт, что в StrudelEnvelope) ──
		var fpos := float(pos)
		var env := 0.0
		if fpos < a_end:
			env = fpos / a_end
		elif fpos < d_end:
			env = 1.0 + (sus - 1.0) * ((fpos - a_end) / (d_end - a_end))
		elif fpos < note_end:
			env = sus
		else:
			var since := fpos - note_end
			env = rel_from * (1.0 - since / rel) if since < rel else 0.0

		var s := raw * g * env

		# ── цепь, в порядке superdough ──
		if use_lp:
			var ly := lb0 * s + lb1 * lx1 + lb2 * lx2 - la1 * ly1 - la2 * ly2
			lx2 = lx1
			lx1 = s
			ly2 = ly1
			ly1 = ly
			s = ly
		if use_hp:
			var hy := hb0 * s + hb1 * hx1 + hb2 * hx2 - ha1 * hy1 - ha2 * hy2
			hx2 = hx1
			hx1 = s
			hy2 = hy1
			hy1 = hy
			s = hy
		if use_coarse:
			if _coarse_count % coarse_n == 0:
				_coarse_hold = s
			_coarse_count += 1
			s = _coarse_hold
		if use_crush and crush_steps >= 1.0:
			s = round(s * crush_steps) / crush_steps
		if use_shape:
			s = (1.0 + shape_f) * s / (1.0 + shape_f * absf(s))
		s *= post

		left[idx] += s * gl
		right[idx] += s * gr
		if use_room:
			room_bus[idx] += s * room
		if use_delay:
			delay_bus[idx] += s * delay_send
		pos += 1
		i += 1

	_pos = pos
	_phase = phase
	_sample_pos = spos
	_lp[0] = lx1
	_lp[1] = lx2
	_lp[2] = ly1
	_lp[3] = ly2
	_hp[0] = hx1
	_hp[1] = hx2
	_hp[2] = hy1
	_hp[3] = hy2


func _source_sample() -> float:
	match source:
		Source.SAMPLE:
			if sample.is_empty():
				return 0.0
			var idx := int(_sample_pos)
			if idx >= sample.size() - 1:
				if sample_loop:
					_sample_pos = fmod(_sample_pos, float(sample.size() - 1))
					idx = int(_sample_pos)
				else:
					active = false
					return 0.0
			var frac := _sample_pos - float(idx)
			var s: float = sample[idx] * (1.0 - frac) + sample[idx + 1] * frac
			_sample_pos += speed * (sample_rate / _rate)
			return s
		Source.SINE:
			var v := sin(TAU * _phase)
			_advance_phase()
			return v
		Source.SAW:
			var v2 := _phase * 2.0 - 1.0
			_advance_phase()
			return v2
		Source.SQUARE:
			var v3 := 1.0 if _phase < 0.5 else -1.0
			_advance_phase()
			return v3
		Source.TRIANGLE:
			var v4 := 4.0 * absf(_phase - 0.5) - 1.0
			_advance_phase()
			return v4
		Source.WHITE:
			return randf() * 2.0 - 1.0
		Source.PINK:
			return _pink_sample()
		Source.BROWN:
			_brown += (randf() * 2.0 - 1.0) * 0.02
			_brown = clampf(_brown, -1.0, 1.0)
			return _brown * 3.0
	return 0.0


func _advance_phase() -> void:
	_phase += frequency * speed / _rate
	if _phase >= 1.0:
		_phase -= floor(_phase)


func _pink_sample() -> float:
	## Розовый шум методом Восса—Маккартни (семь полос).
	var white := randf() * 2.0 - 1.0
	_pink[0] = 0.99886 * _pink[0] + white * 0.0555179
	_pink[1] = 0.99332 * _pink[1] + white * 0.0750759
	_pink[2] = 0.96900 * _pink[2] + white * 0.1538520
	_pink[3] = 0.86650 * _pink[3] + white * 0.3104856
	_pink[4] = 0.55000 * _pink[4] + white * 0.5329522
	_pink[5] = -0.7616 * _pink[5] - white * 0.0168980
	var out: float = _pink[0] + _pink[1] + _pink[2] + _pink[3] + _pink[4] + _pink[5] + _pink[6] + white * 0.5362
	_pink[6] = white * 0.115926
	return out * 0.11


func _apply_coarse(s: float) -> float:
	## Прореживание частоты дискретизации: каждый N-й отсчёт держится.
	var n := int(coarse)
	if n < 2:
		return s
	if _coarse_count % n == 0:
		_coarse_hold = s
	_coarse_count += 1
	return _coarse_hold


func _apply_crush(s: float) -> float:
	## Огрубление разрядности. Формула superdough: шаг = 2^(crush-1).
	var steps := pow(2.0, crush - 1.0)
	if steps < 1.0:
		return s
	return round(s * steps) / steps


func _apply_shape(s: float) -> float:
	## Мягкое ограничение. shape в 0..1, ближе к единице — жёстче.
	var k := clampf(shape, 0.0, 0.99)
	var factor := 2.0 * k / (1.0 - k)
	return (1.0 + factor) * s / (1.0 + factor * absf(s))


# ── биквады (RBJ, как BiquadFilterNode в WebAudio) ───────────────────────────

func _biquad_lowpass(freq: float, q: float) -> PackedFloat32Array:
	var w := TAU * clampf(freq, 10.0, _rate * 0.45) / _rate
	var alpha := sin(w) / (2.0 * maxf(q, 0.0001))
	var cw := cos(w)
	var b1 := 1.0 - cw
	var b0 := b1 * 0.5
	var a0 := 1.0 + alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b0 / a0, (-2.0 * cw) / a0, (1.0 - alpha) / a0])


func _biquad_highpass(freq: float, q: float) -> PackedFloat32Array:
	var w := TAU * clampf(freq, 10.0, _rate * 0.45) / _rate
	var alpha := sin(w) / (2.0 * maxf(q, 0.0001))
	var cw := cos(w)
	var b0 := (1.0 + cw) * 0.5
	var b1 := -(1.0 + cw)
	var a0 := 1.0 + alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b0 / a0, (-2.0 * cw) / a0, (1.0 - alpha) / a0])


func _biquad(x: float, c: PackedFloat32Array, state: Array) -> float:
	var y: float = c[0] * x + c[1] * state[0] + c[2] * state[1] - c[3] * state[2] - c[4] * state[3]
	state[1] = state[0]
	state[0] = x
	state[3] = state[2]
	state[2] = y
	return y
