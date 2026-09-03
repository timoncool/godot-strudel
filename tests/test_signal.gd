@tool
extends StrudelTestBase

## Сигналы и случайное.
##
## 🔴 Числа НЕ придуманы: они сняты с живой Булки через queryArc
## (tools/judge/golden/haps.json, записи sig/* и rand/*). Если генератор
## разойдётся хоть в одном разряде, `degradeBy` выбросит другие ноты и трек
## зазвучит иначе — на слух это не поймать.


func vals(pat: StrudelPattern, from_time: Variant = 0, to_time: Variant = 1) -> Array:
	var out: Array = []
	for row in dump_haps(pat, from_time, to_time):
		out.append(row["v"])
	return out


func test_периодические() -> void:
	eq(vals(StrudelSignal.saw()._segment(4)), ["0", "0.25", "0.5", "0.75"], "saw")
	eq(vals(StrudelSignal.isaw()._segment(4)), ["1", "0.75", "0.5", "0.25"], "isaw")
	eq(vals(StrudelSignal.square()._segment(4)), ["0", "0", "1", "1"], "square")
	var sine_vals := vals(StrudelSignal.sine()._segment(4))
	eq(sine_vals[0], "0.5", "sine в нуле — середина")
	eq(sine_vals[1], "1", "sine в четверти — максимум")


func test_rand_совпадает_с_булкой() -> void:
	# Эталон: sig/rand-seg — rand.segment(8), первые восемь значений.
	var got := vals(StrudelSignal.rand()._segment(8))
	var want := ["0", "0.6852155700325966", "0.36975969187915325", "0.40139251574873924",
		"0.2604806162416935", "0.1356358677148819", "0.19582648016512394", "0.3976310808211565"]
	for i in 8:
		eq(got[i], want[i], "rand[%d]" % i)


func test_irand_совпадает_с_булкой() -> void:
	# Эталон: sig/irand-seg
	eq(vals(StrudelSignal.irand(8)._segment(8)),
		["0", "5", "2", "3", "2", "1", "1", "3"], "irand(8)")


func test_perlin_совпадает_с_булкой() -> void:
	# Эталон: sig/perlin-seg. Сверка по БИТАМ, а не по десятичной записи:
	# String.num на восемнадцати знаках ошибается сам (проверено).
	var want := [0.0, 0.008339818690274114, 0.05378073193423916, 0.14298191054922427,
		0.25977108255028725, 0.3765602545513502, 0.46576143316633534, 0.5112023464103004]
	var rows := dump_haps(StrudelSignal.perlin()._segment(8))
	for i in 8:
		var got: float = StrudelSignal._perlin_at(float(i) / 8.0, 0.0)
		eq_num(got, want[i], 1e-15, "perlin[%d]" % i)
	eq(rows.size(), 8, "восемь значений за цикл")


func test_degrade_by_выбрасывает_те_же_события() -> void:
	# Эталон: rand/degradeBy — s("hh*8").degradeBy(0.25) на четырёх циклах.
	# Из восьми ударов первого цикла выпадают шестой и седьмой (0-й и 5-й индексы).
	var hh := StrudelPattern.pure({"s": "hh"})._fast(8)
	var rows := dump_haps(StrudelSignal.degrade_by(hh, 0.25), 0, 1)
	var starts: Array = []
	for r in rows:
		starts.append(r["wb"])
	eq(starts, ["1/8", "1/4", "3/8", "1/2", "7/8"], "остались ровно те доли, что в Булке")


func test_run() -> void:
	eq(vals(StrudelSignal.run(4)), ["0", "1", "2", "3"], "run(4)")


func test_32_битный_xorshift_не_переполняется() -> void:
	# Значения обязаны лежать в 0..1 на всём разумном диапазоне времени.
	for cycle in [0, 1, 7, 299, 300, 301, 1000]:
		var r: float = StrudelSignal.rands_at_time(float(cycle), 1)[0]
		check(r > -1.0001 and r < 1.0001, "rand на цикле %d в пределах: %f" % [cycle, r])


func test_precise_совпадает_с_булкой() -> void:
	# Второй лад случайного (`useRNG("precise")`): время переводится в целое
	# с шагом 1/2²⁹, дальше хеш Мурмура. Числа сняты с живой Булки.
	#
	# 🔴 Лад ОБЩИЙ на весь плагин, поэтому в конце его надо вернуть: иначе
	# следующая проверка считала бы другим случайным.
	const WANT := [0.388089305, 0.654663742, 0.129392430,
		0.854245374, 0.326895113, 0.697713275]
	StrudelSignal.use_rng("precise")
	for i in WANT.size():
		var got: float = StrudelSignal.rands_at_time(float(i) / 8.0, 1, 0.0)[0]
		eq_num(got, WANT[i], 1e-9, "precise[%d]" % i)
	StrudelSignal.use_rng("legacy")
	var back: float = StrudelSignal.rands_at_time(0.0, 1, 0.0)[0]
	check(absf(back - WANT[0]) > 1e-6, "лад вернулся к legacy")
