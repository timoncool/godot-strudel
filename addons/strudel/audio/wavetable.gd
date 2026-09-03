@tool
class_name StrudelWavetable
extends RefCounted

## Волны синтеза — ОГРАНИЧЕННЫЕ ПО ПОЛОСЕ, как `createOscillator` в WebAudio.
##
## 🔴 Прямой отсчёт («пила это 2·фаза−1») звучит НЕ ТАК: у него гармоники
## выше половины частоты дискретизации заворачиваются обратно и слышны как
## призвуки. WebAudio строит волну сложением синусов до предела слышимого и
## держит по таблице на октаву, перетекая между соседними. Сверка звука с
## Булкой показывала на пиле лишние 1.4 дБ и до 2 дБ в полосе — ровно из-за
## этого.
##
## 🔴 ГРОМКОСТЬ ЗАДАЁТ САМАЯ ПОДРОБНАЯ ТАБЛИЦА. WebAudio приводит волну к
## единичному пику ОДНИМ множителем на все таблицы, и берётся он с той, где
## гармоник больше всего: у пилы её пик из-за явления Гиббса около 1.09, то
## есть вся волна тише на три четверти децибела. Нормировать каждую таблицу
## по себе — значит разойтись с эталоном по громкости.

## Длина таблицы. Столько же в WebAudio (`periodicWaveSize`).
const SIZE := 4096
## Больше половины длины гармоник не выразить.
const MAX_PARTIALS := SIZE / 2
## Полос НА ОКТАВУ. Три, а не одна: так в Chrome (`kNumberOfOctaveBands`).
const BANDS_PER_OCTAVE := 3
## Центов на полосу.
const CENTS_PER_RANGE := 1200.0 / float(BANDS_PER_OCTAVE)
## Сколько всего таблиц: три на каждую октаву длины.
const RANGES := 36

## Сколько гармоник берётся для замера пика. Явление Гиббса сходится быстро:
## после пятисот гармоник пик меняется меньше чем на сотую долю процента, а
## считать все две тысячи — секунды впустую на первой же ноте.
const NORM_PARTIALS := 512

enum Kind { SAW, SQUARE, TRIANGLE, SINE, USER }

## Готовые таблицы: "вид:номер_полосы" → отсчёты.
static var _tables: Dictionary = {}
## Множитель громкости на вид волны.
static var _norm: Dictionary = {}


static func partials_for_range(range_index: int) -> int:
	## 🔴 Гармоники убывают НЕ вдвое на полосу, а в корень кубический из
	## двух: полос на октаву три. С делением надвое волна выходила глухой —
	## сверка показывала минус шесть децибел в полосе 5-12 кГц.
	var culling := pow(2.0, -float(range_index) * CENTS_PER_RANGE / 1200.0)
	return maxi(int(float(MAX_PARTIALS) * culling), 1)


static func range_position(frequency: float, mix_rate: float) -> float:
	## Где эта частота лежит на лестнице таблиц. Целая часть — номер
	## таблицы, дробная — насколько перетечь к следующей.
	var lowest := mix_rate / float(SIZE)
	if frequency <= 0.0 or lowest <= 0.0:
		return 0.0
	var ratio := frequency / lowest
	if ratio <= 0.0:
		return 0.0
	# Плюс единица — чтобы округление уходило В СЛЕДУЮЩУЮ полосу раньше,
	# чем гармоники начнут заворачиваться (так же в Chrome).
	return 1.0 + (log(ratio) / log(2.0)) * 1200.0 / CENTS_PER_RANGE


static func table(kind: int, range_index: int) -> PackedFloat32Array:
	var key := "%d:%d" % [kind, range_index]
	if _tables.has(key):
		return _tables[key]
	var built := _build(kind, partials_for_range(range_index), _scale(kind))
	_tables[key] = built
	return built


static func _scale(kind: int) -> float:
	if _norm.has(kind):
		return _norm[kind]
	var probe := _build(kind, NORM_PARTIALS, 1.0)
	var peak := 0.0
	for v in probe:
		peak = maxf(peak, absf(v))
	var s := 1.0 / peak if peak > 0.0 else 1.0
	_norm[kind] = s
	return s


static func _build(kind: int, partials: int, scale: float) -> PackedFloat32Array:
	## Сложение гармоник ПОВОРОТОМ, а не вызовом синуса на каждый отсчёт:
	## синус считается дважды на гармонику, дальше идёт рекуррентный шаг.
	## Иначе первая же нота стоила бы секунды.
	var out := PackedFloat32Array()
	out.resize(SIZE + 1)
	if kind == Kind.SINE:
		for i in SIZE:
			out[i] = sin(TAU * float(i) / float(SIZE))
		out[SIZE] = out[0]
		return out

	var count := mini(partials, MAX_PARTIALS)
	for n in range(1, count + 1):
		var real := 0.0
		var imag := 0.0
		match kind:
			Kind.SAW:
				imag = -1.0 / float(n)
			Kind.SQUARE:
				imag = 0.0 if n % 2 == 0 else 1.0 / float(n)
			Kind.TRIANGLE:
				real = 0.0 if n % 2 == 0 else 1.0 / float(n * n)
		if real == 0.0 and imag == 0.0:
			continue
		var w := TAU * float(n) / float(SIZE)
		var cw := cos(w)
		var sw := sin(w)
		# Поворот единичного вектора: (cos kw, sin kw) на шаге k.
		var c := 1.0
		var s := 0.0
		for i in SIZE:
			# 🔴 Знак мнимой части. Chrome кладёт в обратное преобразование
			# пару (real, −imag), и на выходе получается `Σ real·cos +
			# imag·sin`. Перепутать знак — получить пилу задом наперёд.
			out[i] += real * c + imag * s
			var nc := c * cw - s * sw
			s = s * cw + c * sw
			c = nc
	if scale != 1.0:
		for i in SIZE:
			out[i] *= scale
	out[SIZE] = out[0]
	return out


static func sample_at(kind: int, range_index: int, phase: float) -> float:
	## Отсчёт одной таблицы с линейной прокладкой между точками.
	var tbl := table(kind, range_index)
	var x := phase * float(SIZE)
	var i := int(x)
	if i < 0:
		i = 0
	elif i >= SIZE:
		i = SIZE - 1
	var fr := x - float(i)
	return tbl[i] * (1.0 - fr) + tbl[i + 1] * fr


## Готовые СВОИ волны: отпечаток набора → таблицы по полосам.
static var _custom: Dictionary = {}
## Множители громкости своих волн.
static var _custom_norm: Dictionary = {}


static func custom_key(partials: Array, phases: Array, kind: int) -> String:
	## Отпечаток набора: по нему таблица находится второй раз без пересчёта.
	var parts := PackedStringArray()
	for v in partials:
		parts.append(str(v))
	parts.append("|")
	for v in phases:
		parts.append(str(v))
	return "%d|%s" % [kind, "_".join(parts)]


static func custom_table(key: String, partials: Array, phases: Array, kind: int,
		range_index: int) -> PackedFloat32Array:
	## Волна по СВОИМ весам обертонов (`waveformN` в `synth.mjs:457`).
	##
	## Вид задаёт исходные коэффициенты гармоники, веса их множат, а фазы
	## ПОВОРАЧИВАЮТ пару (действительная, мнимая) — от этого меняется форма
	## волны, но не её спектр по величине.
	var full := "%s:%d" % [key, range_index]
	if _custom.has(full):
		return _custom[full]
	var scale := _custom_scale(key, partials, phases, kind)
	var built := _build_custom(partials, phases, kind, partials_for_range(range_index), scale)
	_custom[full] = built
	return built


static func _custom_scale(key: String, partials: Array, phases: Array,
		kind: int) -> float:
	if _custom_norm.has(key):
		return _custom_norm[key]
	var probe := _build_custom(partials, phases, kind, MAX_PARTIALS, 1.0)
	var peak := 0.0
	for v in probe:
		peak = maxf(peak, absf(v))
	var s := 1.0 / peak if peak > 0.0 else 1.0
	_custom_norm[key] = s
	return s


static func _build_custom(partials: Array, phases: Array, kind: int,
		limit: int, scale: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SIZE + 1)
	var count := mini(mini(partials.size(), limit), MAX_PARTIALS)
	for idx in count:
		var n := idx + 1
		var mag := StrudelPattern._num(partials[idx])
		var real := 0.0
		var imag := 0.0
		match kind:
			Kind.SAW:
				imag = -1.0 / float(n)
			Kind.SQUARE:
				imag = 0.0 if n % 2 == 0 else 1.0 / float(n)
			Kind.TRIANGLE:
				real = 0.0 if n % 2 == 0 else 1.0 / float(n * n)
			_:
				# «user» — голые единицы: форму задают только веса и фазы.
				imag = 1.0
		real *= mag
		imag *= mag
		if idx < phases.size():
			var ph := StrudelPattern._num(phases[idx])
			if ph != 0.0:
				var c := cos(TAU * ph)
				var s := sin(TAU * ph)
				var r0 := real
				var i0 := imag
				real = c * r0 - s * i0
				imag = s * r0 + c * i0
		if real == 0.0 and imag == 0.0:
			continue
		var w := TAU * float(n) / float(SIZE)
		var cw := cos(w)
		var sw := sin(w)
		var cc := 1.0
		var ss := 0.0
		for i in SIZE:
			out[i] += real * cc + imag * ss
			var nc := cc * cw - ss * sw
			ss = ss * cw + cc * sw
			cc = nc
	if scale != 1.0:
		for i in SIZE:
			out[i] *= scale
	out[SIZE] = out[0]
	return out
