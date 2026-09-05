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
	##
	## 🔴 ОДНО число берётся ПО МОДУЛЮ, а несколько — как есть
	## (`__timeToRandsPrime`, `signal.mjs:277`). Это не описка оригинала, а
	## его поведение: `rand` всегда неотрицателен, а `randL` может дать
	## минус. Пока модуль стоял у вызывающих, шум «берлин» уходил в минус.
	var seed := _time_to_int_seed(t)
	if n == 1:
		return [absf(_int_seed_to_rand(seed))]
	var out: Array = []
	for i in n:
		out.append(_int_seed_to_rand(seed))
		seed = _xorwise(seed)
	return out


## Какой лад случайного включён. «legacy» — тот, что в Strudel по умолчанию.
static var rng_mode := "legacy"


static func use_rng(mode: String = "legacy") -> void:
	## Переключение лада случайного (`useRNG`).
	##
	## 🔴 «legacy» — УМОЛЧАНИЕ, и менять его без нужды нельзя: на нём стоит
	## вся сверка с Булкой. «precise» ровнее по статистике, но даёт другие
	## числа, а значит и другую партию.
	if mode != "legacy" and mode != "precise":
		push_warning("Strudel: не знаю лада случайного \"%s\" — оставляю legacy" % mode)
		return
	rng_mode = mode


static func rands_at_time(t: float, n: int = 1, seed_offset: float = 0.0) -> Array:
	if rng_mode == "precise":
		return _precise_rands(t, n, seed_offset)
	return time_to_rands(t + seed_offset, n)


static func _precise_rands(t: float, n: int, seed: float) -> Array:
	## Лад «precise»: время переводится в целое, потом хеш Мурмура.
	##
	## 🔴 Время берётся с шагом 1/2²⁹ — так задумано: соседние доли круга
	## должны давать РАЗНЫЕ числа, а не одно и то же.
	var big := int(floor(t * 536870912.0))
	var s := int(seed)
	if n == 1:
		return [_rand_at(big, 0, s)]
	var out: Array = []
	for i in n:
		out.append(_rand_at(big, i, s))
	return out


static func _rand_at(big_t: int, i: int, seed: int) -> float:
	return float(_murmur_final(_decorrelate(big_t, i, seed))) / 4294967296.0


static func _decorrelate(big_t: int, i: int, seed: int) -> int:
	## Развести близкие время, номер и зерно, чтобы хеш их не слепил.
	var low := StrudelUtil.u32(big_t)
	var high := StrudelUtil.u32(int(floor(float(big_t) / 4294967296.0)))
	var key := low ^ StrudelUtil.u32(StrudelUtil.imul32(high ^ 0x85ebca6b, 0xc2b2ae35))
	key ^= StrudelUtil.u32(StrudelUtil.imul32(i ^ 0x7f4a7c15, 0x9e3779b9))
	key ^= StrudelUtil.u32(StrudelUtil.imul32(seed ^ 0x165667b1, 0x27d4eb2d))
	return StrudelUtil.u32(key)


static func _murmur_final(x: int) -> int:
	## Завершающая мешалка хеша Мурмура — вся в тридцати двух битах.
	var v := StrudelUtil.u32(x)
	v ^= StrudelUtil.ushr32(v, 16)
	v = StrudelUtil.u32(StrudelUtil.imul32(v, 0x85ebca6b))
	v ^= StrudelUtil.ushr32(v, 13)
	v = StrudelUtil.u32(StrudelUtil.imul32(v, 0xc2b2ae35))
	v ^= StrudelUtil.ushr32(v, 16)
	return StrudelUtil.u32(v)


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


static func berlin() -> StrudelPattern:
	## Шум «берлин»: тот же перлин, но переходы ПРЯМЫЕ, а не сглаженные,
	## и каждая ступень строится от предыдущей. Выходит лесенка вверх —
	## отсюда и восходящие арпеджио, ради которых его завели.
	return make_signal(func(t: StrudelFraction, controls: Dictionary):
		var off: float = float(controls.get("randSeed", 0.0))
		var x := t.to_float()
		var prev := floor(x)
		var bottom: float = rands_at_time(prev, 1, off)[0]
		var height: float = rands_at_time(prev + 1.0, 1, off)[0]
		var top: float = bottom + height
		var frac: float = x - prev
		return (bottom + frac * (top - bottom)) / 2.0
	)


static func rand_list(n: Variant) -> StrudelPattern:
	## `randL` — СПИСОК случайных чисел одним значением. Нужен там, где
	## параметр берёт список: веса обертонов, фазы.
	return make_signal(func(t: StrudelFraction, _controls: Dictionary) -> Callable:
		var time := t.to_float()
		return func(count) -> Array:
			var out: Array = []
			for v in rands_at_time(time, maxi(int(StrudelPattern._num(count)), 1)):
				out.append(absf(StrudelPattern._num(v)))
			return out
	).app_left(StrudelPattern.reify(n))


static func binary_n(n: Variant, bits: Variant = 16) -> StrudelPattern:
	## Число → ряд нулей и единиц, старший бит СПРАВА.
	var bits_pat := StrudelPattern.reify(bits)
	return bits_pat.fmap(func(b) -> StrudelPattern:
		var width := maxi(int(StrudelPattern._num(b)), 1)
		var order: Array = []
		for i in width:
			order.append(width - 1 - i)
		return StrudelPattern.reify(n)._segment(width).fmap(func(v) -> Callable:
			var num := int(StrudelPattern._num(v))
			return func(bit) -> int:
				return (num >> int(StrudelPattern._num(bit))) & 1
		).app_left(StrudelPattern.sequence(order))
	).inner_join()


static func binary_(n: Variant) -> StrudelPattern:
	## Столько разрядов, сколько нужно самому числу.
	return StrudelPattern.reify(n).fmap(func(v) -> StrudelPattern:
		return binary_n(v, _bit_width(StrudelPattern._num(v)))
	).inner_join()


static func binary_list(n: Variant) -> StrudelPattern:
	## То же, но СПИСКОМ в одном значении — для `partials`.
	return StrudelPattern.reify(n).fmap(func(v) -> StrudelPattern:
		return binary_n_list(v, _bit_width(StrudelPattern._num(v)))
	).inner_join()


static func binary_n_list(n: Variant, bits: Variant = 16) -> StrudelPattern:
	return StrudelPattern.reify(n).with_value(func(v) -> Callable:
		return func(b) -> Array:
			var width := maxi(int(StrudelPattern._num(b)), 1)
			var num := int(StrudelPattern._num(v))
			var out: Array = []
			for i in range(width - 1, -1, -1):
				out.append((num >> i) & 1)
			return out
	).app_left(StrudelPattern.reify(bits))


static func _bit_width(v: float) -> int:
	## Сколько разрядов занимает число.
	var num := maxi(int(v), 0)
	if num <= 0:
		return 1
	return int(floor(log(float(num)) / log(2.0))) + 1


static func wchoose_with(pat: StrudelPattern, pairs: Array) -> StrudelPattern:
	## Выбор из списка ПО ВЕСАМ, где указатель — заданный паттерн 0..1.
	##
	## 🔴 Веса накапливаются НАРАСТАЮЩИМ ИТОГОМ, и берётся первый, который
	## перевалил за долю: так вес прямо задаёт ширину участка.
	var values: Array = []
	var totals: Array = []
	var total := 0.0
	for pair in pairs:
		var p: Array = pair if pair is Array else [pair, 1]
		values.append(StrudelPattern.reify(p[0]))
		# 🔴 НЕЧИСЛОВОЙ ВЕС НЕ ДОЛЖЕН ОТРАВЛЯТЬ ВЕСЬ ИТОГ. Вес бывает
		# паттерном — так написан пример в самой справке Strudel:
		# `wchooseCycles(["bd(3,8)", "<5 0>"], …)`. `_num` отдавал на нём
		# NAN, нарастающий итог становился NAN целиком, и сравнение
		# `totals[i] > find` было ложным для ВСЕХ участков, включая ещё
		# конечные, — выбор молча садился на последний вариант навсегда.
		# Непонятный вес считаем единицей, как и отсутствующий.
		var w := StrudelPattern._num(p[1]) if p.size() > 1 else 1.0
		if is_nan(w) or is_inf(w):
			w = 1.0
		total += w
		totals.append(total)
	if values.is_empty():
		return StrudelPattern.silence()
	return pat.fmap(func(r) -> StrudelPattern:
		var find := total * StrudelPattern._num(r)
		for i in totals.size():
			if float(totals[i]) > find:
				return values[i]
		return values[values.size() - 1]
	)


static func wchoose(pairs: Array) -> StrudelPattern:
	## Непрерывный выбор по весам.
	return wchoose_with(rand(), pairs).outer_join()


static func wchoose_cycles(pairs: Array) -> StrudelPattern:
	## Выбор по весам РАЗ В КРУГ.
	return wchoose_with(rand()._segment(1), pairs).inner_join()


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

static func _degrade_with(pat: StrudelPattern, with_pat: StrudelPattern, amount: float) -> StrudelPattern:
	## Основа всего вероятностного: событие остаётся, если случайное > amount.
	return pat.fmap(func(a) -> Callable:
		return func(_b): return a
	).app_left(with_pat.filter_values(func(v): return float(v) > amount))


static func degrade_by_with(pat: StrudelPattern, with_pat: Variant,
		amount: Variant) -> StrudelPattern:
	## Прореживание ЧУЖИМ источником случайности — основа `someCyclesBy` и
	## всего, где нужен свой ритм выпадения.
	var src := StrudelPattern.reify(with_pat)
	return pat._patternify([amount], func(vals: Array) -> StrudelPattern:
		return _degrade_with(pat, src, StrudelPattern._num(vals[0]))
	)


## Как имена клавиш браузера зовутся в Godot. Остальные `OS.find_keycode_from_string`
## разбирает сам.
const KEY_ALIASES := {
	"control": "Ctrl", "arrowleft": "Left", "arrowright": "Right",
	"arrowup": "Up", "arrowdown": "Down", " ": "Space", "esc": "Escape",
}


static func is_key_down(keyname: Variant) -> bool:
	## Зажаты ли ВСЕ названные клавиши. Имена как в браузере: «Control:j»
	## значит Control И j одновременно.
	var names: Array = keyname if keyname is Array else [keyname]
	for raw in names:
		for part in StrudelUtil.text(raw).split(":", false):
			var name := String(part).strip_edges()
			var alias := String(KEY_ALIASES.get(name.to_lower(), name))
			var code := OS.find_keycode_from_string(alias)
			if code == KEY_NONE or not Input.is_key_pressed(code):
				return false
	return true


static func key_down(pat: StrudelPattern) -> StrudelPattern:
	## Значения-имена клавиш → «зажата или нет». Читается В МОМЕНТ ЗАПРОСА,
	## поэтому годится как живой переключатель прямо в игре.
	return pat.fmap(func(v) -> bool: return is_key_down(v))


static func when_key(pat: StrudelPattern, keyname: Variant, fn: Callable) -> StrudelPattern:
	## Применить действие, пока клавиша зажата.
	##
	## 🔴 Снимок берётся ОДИН РАЗ, при сборке паттерна, — так в оригинале
	## (`signal.mjs`, `pat.when(_keyDown(input), func)`). Живой отклик даёт
	## `key_down`, а не это.
	return pat.when_(is_key_down(keyname), fn)


static func degrade_by(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## 🔴 Доля — ПАТТЕРН, а не число. `degradeBy("0 0.1 .5 .1")` меняет порог
	## по четвертям круга; пока здесь стояло `float(amount)`, строка «0 0.1
	## .5 .1» превращалась в ноль, и не выбрасывалось ничего. На треке
	## amensister это давало лишние двадцать четыре события.
	# 🔴 ЧИСЛО ШАГОВ ПЕРЕЖИВАЕТ ПРОРЕЖИВАНИЕ. `degradeBy` ничего не делает с
	# долями, только выбрасывает события, поэтому в оригинале у результата
	# `_steps` остаётся прежним. Здесь при доле-ПАТТЕРНЕ шаги терялись
	# (`_patternify` идёт через склейку), и дальше `stepcat` подставлял
	# вместо «не задано» единицу: `stepcat(s("hh*8").degradeBy("<0 .5>"),
	# s("bd"))` делил круг 1:1 вместо 8:1.
	var out := pat._patternify([amount], func(vals: Array) -> StrudelPattern:
		return _degrade_with(pat, rand(), StrudelPattern._num(vals[0]))
	)
	out.steps = pat.steps
	return out


static func degrade(pat: StrudelPattern) -> StrudelPattern:
	return degrade_by(pat, 0.5)


static func undegrade_by(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## Обратное degradeBy: остаются ровно те события, что там выпадали.
	## Доля так же патернифицируется — см. degrade_by.
	return pat._patternify([amount], func(vals: Array) -> StrudelPattern:
		return _degrade_with(pat, rand().fmap(func(r): return 1.0 - float(r)),
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
			_degrade_with(pat, rand()._segment(1), p),
			fn.call(_degrade_with(pat, rand().fmap(func(r): return 1.0 - float(r))._segment(1), 1.0 - p))
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
