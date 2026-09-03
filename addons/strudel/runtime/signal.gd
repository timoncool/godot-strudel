@tool
class_name StrudelSignal
extends RefCounted

## Непрерывные сигналы и случайное. Перенос `packages/core/signal.mjs`.
##
## Сигнал — паттерн БЕЗ структуры: у его событий нет `whole`. Он не звучит сам,
## а служит источником значений (`.range()`, `.segment()`), либо накладывается
## на чужую структуру.
##
## 🔴 Значение берётся в НАЧАЛЕ запрошенного отрезка (`signal.mjs:20`), а не в
## середине. От этого зависит, какое именно число достанется событию.


static func make_signal(fn: Callable) -> StrudelPattern:
	## Строит непрерывный сигнал из функции времени.
	## (Имя не `signal` — это ключевое слово GDScript.)
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		return [StrudelHap.new(null, state.span, fn.call(state.span.begin, state.controls))]
	)


static func steady(value: Variant) -> StrudelPattern:
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		return [StrudelHap.new(null, state.span, value)]
	)


# ═══════════════════════════════════════════════════════════════════════════
# Периодические
# ═══════════════════════════════════════════════════════════════════════════

static func saw() -> StrudelPattern:
	return make_signal(func(t: StrudelFraction, _c): return StrudelUtil.mod_f(t.to_float(), 1.0))


static func isaw() -> StrudelPattern:
	return make_signal(func(t: StrudelFraction, _c): return 1.0 - StrudelUtil.mod_f(t.to_float(), 1.0))


static func sine2() -> StrudelPattern:
	return make_signal(func(t: StrudelFraction, _c): return sin(TAU * t.to_float()))


static func sine() -> StrudelPattern:
	return sine2().from_bipolar()


static func cosine() -> StrudelPattern:
	return sine()._early(StrudelFraction.make(1, 4))


static func cosine2() -> StrudelPattern:
	return sine2()._early(StrudelFraction.make(1, 4))


static func square() -> StrudelPattern:
	return make_signal(func(t: StrudelFraction, _c): return floor(StrudelUtil.mod_f(t.to_float() * 2.0, 2.0)))


static func isquare() -> StrudelPattern:
	return make_signal(func(t: StrudelFraction, _c): return 1.0 - floor(StrudelUtil.mod_f(t.to_float() * 2.0, 2.0)))


static func tri() -> StrudelPattern:
	return StrudelPattern.fastcat([saw(), isaw()])


static func itri() -> StrudelPattern:
	return StrudelPattern.fastcat([isaw(), saw()])


static func saw2() -> StrudelPattern:
	return saw().to_bipolar()


static func isaw2() -> StrudelPattern:
	return isaw().to_bipolar()


static func square2() -> StrudelPattern:
	return square().to_bipolar()


static func tri2() -> StrudelPattern:
	return StrudelPattern.fastcat([saw2(), isaw2()])


static func time() -> StrudelPattern:
	return make_signal(func(t: StrudelFraction, _c): return t.to_float())


# ═══════════════════════════════════════════════════════════════════════════
# Случайное — legacy-генератор Strudel, бит в бит
# ═══════════════════════════════════════════════════════════════════════════
#
# 🔴 По умолчанию Strudel работает в режиме `legacy` (`signal.mjs:601`), и
# переносится именно он. Все операции 32-битные со знаком; на 64-битных int
# GDScript последовательность разошлась бы уже на первом цикле.
#
# Вход — ЧИСЛО С ПЛАВАЮЩЕЙ ТОЧКОЙ: в JS `Fraction + number` даёт Number, то
# есть legacy-RNG и в оригинале считает по float-времени. Это не упрощение.

const _CYCLE := 536870912  # 2^29


static func _xorwise(x: int) -> int:
	var a := StrudelUtil.i32(StrudelUtil.shl32(x, 13) ^ StrudelUtil.i32(x))
	var b := StrudelUtil.i32(StrudelUtil.shr32(a, 17) ^ a)
	return StrudelUtil.i32(StrudelUtil.shl32(b, 5) ^ b)


static func _time_to_int_seed(x: float) -> int:
	var frac := x / 300.0
	frac = frac - float(int(frac))  # Math.trunc, а не floor
	return _xorwise(int(frac * float(_CYCLE)))


static func _int_seed_to_rand(x: int) -> float:
	return float(x % _CYCLE) / float(_CYCLE)


static func time_to_rands(t: float, n: int) -> Array:
	## n случайных чисел в момент t. Порядок и значения — как в Strudel.
	var seed := _time_to_int_seed(t)
	var out: Array = []
	for i in n:
		out.append(_int_seed_to_rand(seed))
		seed = _xorwise(seed)
	return out


static func rands_at_time(t: float, n: int = 1, seed_offset: float = 0.0) -> Array:
	return time_to_rands(t + seed_offset, n)


static func rand() -> StrudelPattern:
	## Непрерывный поток случайных чисел 0..1.
	return make_signal(func(t: StrudelFraction, controls: Dictionary):
		var off: float = float(controls.get("randSeed", 0.0))
		return absf(rands_at_time(t.to_float(), 1, off)[0])
	)


static func rand2() -> StrudelPattern:
	return rand().to_bipolar()


static func irand(n: Variant) -> StrudelPattern:
	## Случайные целые 0..n-1.
	return StrudelPattern.reify(n).fmap(func(i) -> StrudelPattern:
		var limit := float(i)
		return rand().fmap(func(x): return int(float(x) * limit))
	).inner_join()


static func brand_by(probability: Variant) -> StrudelPattern:
	return StrudelPattern.reify(probability).fmap(func(p) -> StrudelPattern:
		var lim := float(p)
		return rand().fmap(func(x): return float(x) < lim)
	).inner_join()


static func brand() -> StrudelPattern:
	return brand_by(0.5)


static func _perlin_at(t: float, seed_offset: float) -> float:
	var ta: float = floor(t)
	var tb: float = ta + 1.0
	var ra: float = absf(rands_at_time(ta, 1, seed_offset)[0])
	var rb: float = absf(rands_at_time(tb, 1, seed_offset)[0])
	var x: float = t - ta
	var smooth := 6.0 * StrudelUtil.pow_i(x, 5) - 15.0 * StrudelUtil.pow_i(x, 4) + 10.0 * StrudelUtil.pow_i(x, 3)
	return ra + smooth * (rb - ra)


static func perlin() -> StrudelPattern:
	## Плавный шум 0..1 — им хорошо «дышат» параметры.
	return make_signal(func(t: StrudelFraction, controls: Dictionary):
		return _perlin_at(t.to_float(), float(controls.get("randSeed", 0.0)))
	)


static func run(n: Variant) -> StrudelPattern:
	## Дискретный ряд 0..n-1 за цикл.
	return saw().range_(0, n).round_()._segment(n)


static func seed_(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	## Меняет зерно случайного для этого паттерна.
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		return pat.query.call(state.set_controls({"randSeed": float(value)}))
	, pat.steps)


# ═══════════════════════════════════════════════════════════════════════════
# Прореживание
# ═══════════════════════════════════════════════════════════════════════════

static func degrade_by_with(pat: StrudelPattern, with_pat: StrudelPattern, amount: float) -> StrudelPattern:
	## Основа всего вероятностного: событие остаётся, если случайное > amount.
	return pat.fmap(func(a) -> Callable:
		return func(_b): return a
	).app_left(with_pat.filter_values(func(v): return float(v) > amount))


static func degrade_by(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## 🔴 Доля — ПАТТЕРН, а не число. `degradeBy("0 0.1 .5 .1")` меняет порог
	## по четвертям круга; пока здесь стояло `float(amount)`, строка «0 0.1
	## .5 .1» превращалась в ноль, и не выбрасывалось ничего. На треке
	## amensister это давало лишние двадцать четыре события.
	return pat._patternify([amount], func(vals: Array) -> StrudelPattern:
		return degrade_by_with(pat, rand(), StrudelPattern._num(vals[0]))
	)


static func degrade(pat: StrudelPattern) -> StrudelPattern:
	return degrade_by(pat, 0.5)


static func undegrade_by(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## Обратное degradeBy: остаются ровно те события, что там выпадали.
	## Доля так же патернифицируется — см. degrade_by.
	return pat._patternify([amount], func(vals: Array) -> StrudelPattern:
		return degrade_by_with(pat, rand().fmap(func(r): return 1.0 - float(r)),
			StrudelPattern._num(vals[0]))
	)


static func undegrade(pat: StrudelPattern) -> StrudelPattern:
	return undegrade_by(pat, 0.5)


static func sometimes_by(pat: StrudelPattern, probability: Variant, fn: Callable) -> StrudelPattern:
	return StrudelPattern.reify(probability).fmap(func(x) -> StrudelPattern:
		var p := float(x)
		return StrudelPattern.stack([
			degrade_by(pat, p),
			fn.call(undegrade_by(pat, 1.0 - p))
		])
	).inner_join()


static func sometimes(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	return sometimes_by(pat, 0.5, fn)


static func often(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	return sometimes_by(pat, 0.75, fn)


static func rarely(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	return sometimes_by(pat, 0.25, fn)


static func almost_never(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	return sometimes_by(pat, 0.1, fn)


static func almost_always(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	return sometimes_by(pat, 0.9, fn)


static func never(pat: StrudelPattern, _fn: Callable) -> StrudelPattern:
	return pat


static func always(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	return fn.call(pat)


static func some_cycles_by(pat: StrudelPattern, probability: Variant, fn: Callable) -> StrudelPattern:
	return StrudelPattern.reify(probability).fmap(func(x) -> StrudelPattern:
		var p := float(x)
		return StrudelPattern.stack([
			degrade_by_with(pat, rand()._segment(1), p),
			fn.call(degrade_by_with(pat, rand().fmap(func(r): return 1.0 - float(r))._segment(1), 1.0 - p))
		])
	).inner_join()


static func some_cycles(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	return some_cycles_by(pat, 0.5, fn)


# ═══════════════════════════════════════════════════════════════════════════
# Выбор
# ═══════════════════════════════════════════════════════════════════════════

static func _choose_with(pat: StrudelPattern, options: Array) -> StrudelPattern:
	var list: Array = []
	for x in options:
		list.append(StrudelPattern.reify(x))
	if list.is_empty():
		return StrudelPattern.silence()
	return pat.range_(0, list.size()).fmap(func(i) -> StrudelPattern:
		var k := clampi(int(floor(float(i))), 0, list.size() - 1)
		return list[k]
	)


static func choose_with(pat: StrudelPattern, options: Array) -> StrudelPattern:
	return _choose_with(pat, options).outer_join()


static func choose_in_with(pat: StrudelPattern, options: Array) -> StrudelPattern:
	## Структура берётся у выбранного значения, а не у выбирающего сигнала.
	return _choose_with(pat, options).inner_join()


static func choose(options: Array) -> StrudelPattern:
	return choose_with(rand(), options)


static func choose_cycles(options: Array) -> StrudelPattern:
	## Один вариант на цикл. Это же стоит за `|` в mini-нотации.
	return choose_in_with(rand()._segment(1), options)


static func randcat(options: Array) -> StrudelPattern:
	return choose_cycles(options)


static func randrun(n: int) -> StrudelPattern:
	## Перестановка 0..n-1, своя на каждый цикл.
	return make_signal(func(t: StrudelFraction, controls: Dictionary):
		# Половина цикла добавляется, иначе первый цикл всегда 0,1,2,3…
		var rands := rands_at_time(t.floor_().add(StrudelFraction.make(1, 2)).to_float(), n,
			float(controls.get("randSeed", 0.0)))
		var order: Array = []
		for i in n:
			order.append([rands[i], i])
		order.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		var idx := StrudelUtil.mod_i(t.cycle_pos().mul(n).floor_().to_int(), n)
		return order[idx][1]
	)._segment(n)


static func _rearrange_with(index_pat: StrudelPattern, n: int, pat: StrudelPattern) -> StrudelPattern:
	var parts: Array = []
	for i in n:
		parts.append(pat._zoom(StrudelFraction.make(i, n), StrudelFraction.make(i + 1, n)))
	return index_pat.fmap(func(i) -> StrudelPattern:
		var k := clampi(int(i), 0, n - 1)
		return (parts[k] as StrudelPattern)._repeat_cycles(n)._fast(n)
	).inner_join()


static func shuffle(pat: StrudelPattern, n: int) -> StrudelPattern:
	## Куски играются вразнобой, но каждый ровно один раз за цикл.
	return _rearrange_with(randrun(n), n, pat)


static func scramble(pat: StrudelPattern, n: int) -> StrudelPattern:
	## Куски берутся наугад — какой-то может выпасть дважды, какой-то ни разу.
	return _rearrange_with(irand(n)._segment(n), n, pat)
