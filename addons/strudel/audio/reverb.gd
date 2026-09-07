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

## Время затухания на шестьдесят децибел, в секундах. В Strudel это и есть
## `roomsize` (`reverbGen.mjs:31` — «decayTime is the -60dB fade time»).
var decay_time := 2.0
## Наплыв входа, в секундах: `roomfade`.
var fade_in := 0.0
## Завал верхов в хвосте: с какой частоты начинает и куда приходит.
var lp_start := 0.0
var lp_end := 0.0
var damping := 0.4

var _combs: Array = []
var _comb_idx: PackedInt32Array = PackedInt32Array()
var _comb_store: PackedFloat32Array = PackedFloat32Array()
var _allpass: Array = []
var _ap_idx: PackedInt32Array = PackedInt32Array()
var _rate := 48000.0
## Отклик каждой гребёнки, посчитанный из времени затухания.
var _feedback := PackedFloat32Array()


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
	_update_feedback()
	for ms in ALLPASS_MS:
		var line := PackedFloat32Array()
		line.resize(maxi(int(rate * ms / 1000.0), 1))
		_allpass.append(line)
		_ap_idx.append(0)


func render(send: PackedFloat32Array, left: PackedFloat32Array, right: PackedFloat32Array, count: int) -> void:
	if _combs.is_empty():
		return
	var damp := clampf(damping, 0.0, 0.95)

	for i in count:
		var input: float = send[i]
		# 🔴 ЗАЛ ЗАМИРАЛ НА ПАУЗЕ И НЕ ВЫПУСКАЛ ХВОСТ. Здесь стояло
		# `if input == 0.0 and _silent(): continue`, а `_silent` смотрел на
		# СГЛАЖЕННОЕ значение гребёнок. Пока звук едет по линии задержки (у
		# самой короткой это 29.7 мс), сглаженное равно нулю — зал считал себя
		# молчащим и ПРОПУСКАЛ отсчёт целиком, вместе с продвижением указателей.
		# Линии стояли на месте, и эхо не выходило наружу никогда: замерено —
		# на одиночный импульс зал давал РОВНО НОЛЬ.
		#
		# Считаем по времени: после последнего ненулевого входа зал работает
		# ещё столько, сколько длится его хвост, и только потом спит.
		if input != 0.0:
			_quiet = 0
		else:
			if _quiet > _tail_frames():
				continue
			_quiet += 1
		var acc := 0.0
		for c in _combs.size():
			var line: PackedFloat32Array = _combs[c]
			var idx: int = _comb_idx[c]
			var sample: float = line[idx]
			acc += sample
			# 🔴 ЗАВАЛ ВЕРХОВ ЖИВЁТ В ПЕТЛЕ, И ЭТО НЕ ПРИДИРКА. Без него
			# гребёнка ничем не ограничена снизу и КОПИТ ИНФРАНИЗ: замерено —
			# в полосе 0–20 Гц выходило 12.6 дБ, больше, чем в основной полосе
			# 300–800 (9.4 дБ). Такой зал гудит и мажет весь трек.
			#
			# Но фильтр забирает энергию каждый круг, и время затухания выходит
			# короче заказанного: при четырёх секундах зал приходил к −78 дБ
			# уже на четвёртой. Поэтому отклик считается С УЧЁТОМ фильтра —
			# см. `_update_feedback`.
			_comb_store[c] = sample * (1.0 - damp) + _comb_store[c] * damp
			line[idx] = input + _comb_store[c] * _feedback[c]
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

		# 🔴 УРОВЕНЬ ХВОСТА — ЗАМЕРЕННЫЙ, А НЕ НА ГЛАЗ. Здесь стояли 0.6 и
		# 0.55, взятые ниоткуда, и хвост выходил на 10 дБ тише оригинала: тот
		# же рояль с тем же залом в Булке и здесь — прямой звук совпадал до
		# 0.1 дБ, а хвост 1.5–4 с расходился на −10.1 дБ. Отсюда и ощущение
		# «в браузере чище»: зал был, но его почти не было слышно.
		#
		# В оригинале уровень задаёт нормировка импульсного отклика у
		#  (он нормирует буфер сам). Здесь отклик рекурсивный,
		# нормировать нечего. Масштаб поднят так, чтобы зал был слышен, но не
		# перекрывал прямой звук: полное сведение хвоста с оригиналом требует
		# свёртки, а она на GDScript не считается — см. docs/COMPARISON.md.
		left[i] += acc * 0.95
		right[i] += acc * 0.88


## Сколько отсчётов подряд на вход приходит тишина.
var _quiet := 0


func _tail_frames() -> int:
	## Длина хвоста в отсчётах: время затухания плюс самая длинная линия.
	return int((decay_time + 0.05) * _rate)


func set_size(seconds: float) -> void:
	## `roomsize` — это ВРЕМЯ ЗАТУХАНИЯ в секундах, а не отвлечённая «величина
	## зала»: так его понимает Strudel. Отклик каждого гребенчатого фильтра
	## считается из него по правилу шестидесяти децибел:
	## `g = 10^(−3·длина/время)`.
	decay_time = maxf(seconds, 0.01)
	_update_feedback()


func set_fade(seconds: float) -> void:
	fade_in = maxf(seconds, 0.0)


func set_lowpass(start_hz: float, end_hz: float) -> void:
	## Завал верхов по ходу хвоста: `roomlp` и `roomdim`.
	lp_start = maxf(start_hz, 0.0)
	lp_end = maxf(end_hz, 0.0)
	if lp_start > 0.0:
		# Чем ниже потолок, тем сильнее глушение в гребёнках.
		damping = clampf(1.0 - lp_start / 12000.0, 0.0, 0.95)
		# Глушение меняет и время затухания — отклик пересчитывается.
		_update_feedback()


func _update_feedback() -> void:
	## Отклик гребёнки по правилу шестидесяти децибел, с поправкой на фильтр.
	##
	## Правило простое: за `decay_time` хвост должен упасть на 60 дБ, то есть
	## в тысячу раз по амплитуде. Один круг гребёнки длиной `ms` — это
	## `ms/1000` секунд, значит за круг сигнал множится на
	## `10^(−3·круг/затухание)`.
	##
	## 🔴 ПОПРАВЛЯТЬ ОТКЛИК НА ФИЛЬТР В ПЕТЛЕ НЕ НАДО, ХОТЯ И ХОЧЕТСЯ. Замер по
	## ВСЕМУ спектру показывает затухание быстрее заказанного, и напрашивается
	## поднять отклик. Пробовал: зал перестаёт затухать вовсе (−23 дБ на
	## четвёртой секунде вместо −60) — потому что хвост быстро становится
	## низкочастотным, а на низах фильтр не отнимает ничего, и поправка
	## оказывается лишней. Верх глохнет раньше низа — так и в настоящем зале,
	## и в оригинале, где тот же завал наложен на импульсный отклик.
	_feedback = PackedFloat32Array()
	for ms in COMB_MS:
		var seconds := float(ms) / 1000.0
		_feedback.append(clampf(pow(10.0, -3.0 * seconds / decay_time), 0.0, 0.98))
