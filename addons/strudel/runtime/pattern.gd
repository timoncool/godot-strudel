@tool
class_name StrudelPattern
extends RefCounted

## Паттерн — ФУНКЦИЯ ЗАПРОСА НА ИНТЕРВАЛЕ, а не список нот.
## Перенос `packages/core/pattern.mjs`.
##
## 🔴 Это главное решение всей библиотеки. Развернуть паттерн в плоский список
## событий на старте нельзя: паттерны бывают бесконечными и вероятностными, а
## живая замена и смена темпа опираются на то, что события считаются по запросу
## того куска времени, который сейчас нужен.
##
## `query` принимает `StrudelState` (отрезок + управляющие значения) и
## возвращает массив `StrudelHap`.

## Функция запроса: (StrudelState) -> Array[StrudelHap]
var query: Callable
## Число шагов в цикле, если оно определено (нужно stepwise-функциям).
var steps: StrudelFraction = null

# Признак «паттерн получен из pure(значение)». Оригинал (`__pure`) использует
# его как быструю ветку в register(): когда все аргументы — простые значения,
# незачем гонять их через innerJoin.
var _pure_value: Variant = null
var _has_pure := false

static var _string_parser: Callable = Callable()


func _init(query_fn: Callable = Callable(), step_count: Variant = null) -> void:
	query = query_fn
	set_steps(step_count)


func set_steps(step_count: Variant) -> StrudelPattern:
	steps = null if step_count == null else StrudelFraction.of(step_count)
	return self


func has_steps() -> bool:
	return steps != null


static func set_string_parser(parser: Callable) -> void:
	## Подключает разбор строк как mini-нотации. Ставится один раз при загрузке.
	_string_parser = parser


# ═══════════════════════════════════════════════════════════════════════════
# Запрос
# ═══════════════════════════════════════════════════════════════════════════

func query_arc(from_time: Variant, to_time: Variant, controls: Dictionary = {}) -> Array:
	## Спросить события на отрезке. Точка входа для всего снаружи.
	var span := StrudelTimeSpan.new(StrudelFraction.of(from_time), StrudelFraction.of(to_time))
	return query.call(StrudelState.new(span, controls))


func first_cycle() -> Array:
	return query_arc(0, 1)


func split_queries() -> StrudelPattern:
	## Разбивает запрос по границам циклов: дальше каждое событие заведомо
	## лежит внутри одного цикла, и расчёты выражаются проще.
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for sub in state.span.span_cycles():
			out.append_array(inner.query.call(state.set_span(sub)))
		return out
	)


func with_query_span(fn: Callable) -> StrudelPattern:
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		return inner.query.call(state.with_span(fn))
	)


func with_query_span_maybe(fn: Callable) -> StrudelPattern:
	## Как with_query_span, но функция вправе вернуть null — тогда событий нет.
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var new_span = fn.call(state.span)
		if new_span == null:
			return []
		return inner.query.call(state.set_span(new_span))
	)


func with_query_time(fn: Callable) -> StrudelPattern:
	return with_query_span(func(span: StrudelTimeSpan) -> StrudelTimeSpan:
		return span.with_time(fn)
	)


func with_hap_span(fn: Callable) -> StrudelPattern:
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for hap in inner.query.call(state):
			out.append(hap.with_span(fn))
		return out
	)


func with_hap_time(fn: Callable) -> StrudelPattern:
	return with_hap_span(func(span: StrudelTimeSpan) -> StrudelTimeSpan:
		return span.with_time(fn)
	)


func with_haps(fn: Callable) -> StrudelPattern:
	var inner := self
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		return fn.call(inner.query.call(state), state)
	)
	result.steps = steps
	return result


func with_hap(fn: Callable) -> StrudelPattern:
	return with_haps(func(haps: Array, _state) -> Array:
		var out: Array = []
		for h in haps:
			out.append(fn.call(h))
		return out
	)


func with_state(fn: Callable) -> StrudelPattern:
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		return inner.query.call(fn.call(state))
	)


func with_value(fn: Callable) -> StrudelPattern:
	var inner := self
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for hap in inner.query.call(state):
			out.append(hap.with_value(fn))
		return out
	)
	result.steps = steps
	return result


func fmap(fn: Callable) -> StrudelPattern:
	return with_value(fn)


func filter_haps(test: Callable) -> StrudelPattern:
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for hap in inner.query.call(state):
			if test.call(hap):
				out.append(hap)
		return out
	)


func filter_values(test: Callable) -> StrudelPattern:
	var inner := self
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for hap in inner.query.call(state):
			if test.call(hap.value):
				out.append(hap)
		return out
	)
	result.steps = steps
	return result


func remove_undefineds() -> StrudelPattern:
	return filter_values(func(v): return v != null)


func onsets_only() -> StrudelPattern:
	## Только события, содержащие своё начало. Играются именно они.
	return filter_haps(func(h: StrudelHap) -> bool: return h.has_onset())


func discrete_only() -> StrudelPattern:
	## Выбрасывает аналоговые (непрерывные) события — у них нет `whole`.
	return filter_haps(func(h: StrudelHap) -> bool: return h.whole != null)


func set_context(ctx: Dictionary) -> StrudelPattern:
	return with_hap(func(h: StrudelHap) -> StrudelHap: return h.set_context(ctx))


func with_context(fn: Callable) -> StrudelPattern:
	var result := with_hap(func(h: StrudelHap) -> StrudelHap:
		return h.set_context(fn.call(h.context))
	)
	result._has_pure = _has_pure
	result._pure_value = _pure_value
	return result


func strip_context() -> StrudelPattern:
	return with_hap(func(h: StrudelHap) -> StrudelHap: return h.set_context({}))


func sort_haps_by_part() -> StrudelPattern:
	return with_haps(func(haps: Array, _state) -> Array:
		var copy := haps.duplicate()
		copy.sort_custom(func(a: StrudelHap, b: StrudelHap) -> bool:
			var c := a.part.begin.compare(b.part.begin)
			if c != 0:
				return c < 0
			c = a.part.end.compare(b.part.end)
			if c != 0:
				return c < 0
			if a.whole == null or b.whole == null:
				return false
			c = a.whole.begin.compare(b.whole.begin)
			if c != 0:
				return c < 0
			return a.whole.end.compare(b.whole.end) < 0
		)
		return copy
	)


# ═══════════════════════════════════════════════════════════════════════════
# Аппликативы: как две структуры складываются в одну
# ═══════════════════════════════════════════════════════════════════════════
#
# 🔴 Здесь порты расходятся чаще всего. `app_left` берёт структуру ЛЕВОГО
# паттерна, `app_right` — правого, `app_both` — пересечение. От выбора зависит,
# кто задаёт доли: `n("0 1").gain("0.5")` звучит двумя нотами, а
# `n("0 1").gain.out("0.5 0.9")` — по структуре громкости.

func app_whole(whole_fn: Callable, pat_val: StrudelPattern) -> StrudelPattern:
	var pat_func := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var hap_funcs: Array = pat_func.query.call(state)
		var hap_vals: Array = pat_val.query.call(state)
		var out: Array = []
		for hf in hap_funcs:
			for hv in hap_vals:
				var part = hf.part.intersection(hv.part)
				if part == null:
					continue
				out.append(StrudelHap.new(
					whole_fn.call(hf.whole, hv.whole),
					part,
					(hf.value as Callable).call(hv.value),
					hv.combine_context(hf)
				))
		return out
	)


func app_both(pat_val: StrudelPattern) -> StrudelPattern:
	var result := app_whole(func(a, b):
		if a == null or b == null:
			return null
		return (a as StrudelTimeSpan).intersection_e(b)
	, pat_val)
	result.steps = _lcm_steps([steps, pat_val.steps])
	return result


func app_left(pat_val: StrudelPattern) -> StrudelPattern:
	## Структура сохраняется от левого (внутреннего) паттерна.
	var pat_func := self
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for hf in pat_func.query.call(state):
			for hv in pat_val.query.call(state.set_span(hf.whole_or_part())):
				var part = hf.part.intersection(hv.part)
				if part == null:
					continue
				out.append(StrudelHap.new(
					hf.whole, part,
					(hf.value as Callable).call(hv.value),
					hv.combine_context(hf)
				))
		return out
	)
	result.steps = steps
	return result


func app_right(pat_val: StrudelPattern) -> StrudelPattern:
	## Структура сохраняется от правого (внешнего) паттерна.
	var pat_func := self
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for hv in pat_val.query.call(state):
			for hf in pat_func.query.call(state.set_span(hv.whole_or_part())):
				var part = hf.part.intersection(hv.part)
				if part == null:
					continue
				out.append(StrudelHap.new(
					hv.whole, part,
					(hf.value as Callable).call(hv.value),
					hv.combine_context(hf)
				))
		return out
	)
	result.steps = pat_val.steps
	return result


# ═══════════════════════════════════════════════════════════════════════════
# Склейки паттернов из паттернов
# ═══════════════════════════════════════════════════════════════════════════

func bind_whole(choose_whole: Callable, fn: Callable) -> StrudelPattern:
	var pat_val := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for a in pat_val.query.call(state):
			var inner: StrudelPattern = fn.call(a.value)
			for b in inner.query.call(state.set_span(a.part)):
				out.append(StrudelHap.new(
					choose_whole.call(a.whole, b.whole),
					b.part, b.value, a.combine_context(b)
				))
		return out
	)


func bind(fn: Callable) -> StrudelPattern:
	return bind_whole(func(a, b):
		if a == null or b == null:
			return null
		return (a as StrudelTimeSpan).intersection_e(b)
	, fn)


func join() -> StrudelPattern:
	return bind(func(x): return x)


func outer_bind(fn: Callable) -> StrudelPattern:
	return bind_whole(func(a, _b): return a, fn).set_steps(steps)


func outer_join() -> StrudelPattern:
	return outer_bind(func(x): return x)


func inner_bind(fn: Callable) -> StrudelPattern:
	return bind_whole(func(_a, b): return b, fn)


func inner_join() -> StrudelPattern:
	return inner_bind(func(x): return x)


func reset_join(restart: bool = false) -> StrudelPattern:
	## Внутренний паттерн перезапускается на каждом начале внешнего.
	var pat_of_pats := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for outer in pat_of_pats.discrete_only().query.call(state):
			var shift: StrudelFraction = outer.whole.begin if restart else outer.whole.begin.cycle_pos()
			var inner: StrudelPattern = (outer.value as StrudelPattern)._late(shift)
			for ih in inner.query.call(state):
				var w = null
				if ih.whole != null:
					w = ih.whole.intersection(outer.whole)
				var part = ih.part.intersection(outer.part)
				if part == null:
					continue
				out.append(StrudelHap.new(w, part, ih.value, outer.combine_context(ih)))
		return out
	)


func restart_join() -> StrudelPattern:
	return reset_join(true)


func squeeze_join() -> StrudelPattern:
	## Целый цикл внутреннего паттерна ужимается в каждое событие внешнего.
	var pat_of_pats := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for outer in pat_of_pats.discrete_only().query.call(state):
			var inner_pat: StrudelPattern = (outer.value as StrudelPattern)._focus_span(outer.whole_or_part())
			for inner in inner_pat.query.call(state.set_span(outer.part)):
				var whole = null
				if inner.whole != null and outer.whole != null:
					whole = inner.whole.intersection(outer.whole)
					if whole == null:
						continue
				var part = inner.part.intersection(outer.part)
				if part == null:
					continue
				out.append(StrudelHap.new(whole, part, inner.value, inner.combine_context(outer)))
		return out
	)


func squeeze_bind(fn: Callable) -> StrudelPattern:
	return fmap(fn).squeeze_join()


# ═══════════════════════════════════════════════════════════════════════════
# Создание паттернов
# ═══════════════════════════════════════════════════════════════════════════

static func gap(step_count: Variant) -> StrudelPattern:
	return StrudelPattern.new(func(_state) -> Array: return [], step_count)


static func silence() -> StrudelPattern:
	return gap(1)


static func nothing() -> StrudelPattern:
	return gap(0)


static func pure(value: Variant) -> StrudelPattern:
	## Значение, звучащее раз в цикл.
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for sub in state.span.span_cycles():
			var cycle := StrudelTimeSpan.new(sub.begin.sam(), sub.begin.next_sam())
			out.append(StrudelHap.new(cycle, sub, value))
		return out
	, 1)
	result._has_pure = true
	result._pure_value = value
	return result


static func reify(thing: Variant) -> StrudelPattern:
	## Приводит что угодно к паттерну. Строка разбирается как mini-нотация,
	## если разборщик подключён (см. set_string_parser).
	if thing is StrudelPattern:
		return thing
	if thing is Array:
		return sequence(thing)
	if (thing is String or thing is StringName) and _string_parser.is_valid():
		return _string_parser.call(String(thing))
	return pure(thing)


static func stack(pats: Array) -> StrudelPattern:
	## Всё звучит одновременно.
	var list: Array = []
	for p in pats:
		list.append(reify(p))
	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var out: Array = []
		for p in list:
			out.append_array(p.query.call(state))
		return out
	)
	var st: Array = []
	for p in list:
		st.append(p.steps)
	result.steps = _lcm_steps(st)
	return result


static func slowcat(pats: Array) -> StrudelPattern:
	## По одному паттерну на цикл.
	var list: Array = []
	for p in pats:
		list.append(sequence(p) if p is Array else reify(p))
	if list.is_empty():
		return silence()
	if list.size() == 1:
		return list[0]

	var result := StrudelPattern.new(func(state: StrudelState) -> Array:
		var span := state.span
		var n := list.size()
		var pat_n := StrudelUtil.mod_i(span.begin.sam().to_int(), n)
		var pat: StrudelPattern = list[pat_n]
		# Сдвиг, чтобы циклы составляющих паттернов не пропускались:
		# четвёртый цикл склейки из трёх — это ВТОРОЙ цикл первого паттерна.
		var offset := span.begin.floor_().sub(span.begin.div(n).floor_())
		var shifted := pat.with_hap_time(func(t: StrudelFraction) -> StrudelFraction:
			return t.add(offset)
		)
		return shifted.query.call(state.set_span(span.with_time(
			func(t: StrudelFraction) -> StrudelFraction: return t.sub(offset)
		)))
	).split_queries()
	var st: Array = []
	for p in list:
		st.append(p.steps)
	result.steps = _lcm_steps(st)
	return result


static func slowcat_prime(pats: Array) -> StrudelPattern:
	## Как slowcat, но циклы пропускаются (нужен для every/lastOf).
	var list: Array = []
	for p in pats:
		list.append(reify(p))
	if list.is_empty():
		return silence()
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var pat_n := StrudelUtil.mod_i(int(floor(state.span.begin.to_float())), list.size())
		return (list[pat_n] as StrudelPattern).query.call(state)
	).split_queries()


static func cat(pats: Array) -> StrudelPattern:
	return slowcat(pats)


static func fastcat(pats: Array) -> StrudelPattern:
	## Все паттерны втискиваются в один цикл.
	var result := slowcat(pats)
	if pats.size() > 1:
		result = result._fast(pats.size())
		result.steps = StrudelFraction.new(pats.size())
	return result


static func sequence(pats: Variant) -> StrudelPattern:
	if pats is Array:
		return fastcat(pats)
	return fastcat([pats])


static func stepcat(time_pats: Array) -> StrudelPattern:
	## Склейка с весами: stepcat([[3,"e3"],[1,"g3"]]) — то же, что "e3@3 g3".
	if time_pats.is_empty():
		return nothing()
	var pairs: Array = []
	for x in time_pats:
		if x is Array and x.size() == 2:
			pairs.append([StrudelFraction.of(x[0]), reify(x[1])])
		else:
			var p := reify(x)
			pairs.append([p.steps if p.steps != null else StrudelFraction.new(1), p])

	if pairs.size() == 1:
		var only: StrudelPattern = pairs[0][1]
		only.steps = pairs[0][0]
		return only

	var total := StrudelFraction.new(0)
	for pr in pairs:
		total = total.add(pr[0])
	if total.is_zero():
		return nothing()

	var begin := StrudelFraction.new(0)
	var parts: Array = []
	for pr in pairs:
		var t: StrudelFraction = pr[0]
		if t.is_zero():
			continue
		var end := begin.add(t)
		parts.append((pr[1] as StrudelPattern)._compress(begin.div(total), end.div(total)))
		begin = end
	var result := stack(parts)
	result.steps = total
	return result


static func timecat(time_pats: Array) -> StrudelPattern:
	return stepcat(time_pats)


static func arrange(sections: Array) -> StrudelPattern:
	## Форма трека: arrange([[4, часть_а], [4, часть_б], ...]) — длина в циклах.
	var total := 0.0
	for s in sections:
		total += float(s[0])
	var scaled: Array = []
	for s in sections:
		scaled.append([StrudelFraction.of(s[0]), reify(s[1])._fast(s[0])])
	return stepcat(scaled)._slow(total)


static func polymeter(pats: Array, steps_per_cycle: Variant = null) -> StrudelPattern:
	## Выравнивает шаги паттернов — получается полиметрия.
	var list: Array = []
	for p in pats:
		list.append(reify(p))
	var with_steps: Array = []
	for p in list:
		if p.has_steps():
			with_steps.append(p)
	if with_steps.is_empty():
		return silence()

	var target: StrudelFraction
	if steps_per_cycle != null:
		target = StrudelFraction.of(steps_per_cycle)
	else:
		var st: Array = []
		for p in with_steps:
			st.append(p.steps)
		target = _lcm_steps(st)
	if target == null or target.is_zero():
		return nothing()

	var aligned: Array = []
	for p in with_steps:
		aligned.append(p.pace(target))
	var result := stack(aligned)
	result.steps = target
	return result


static func _lcm_steps(list: Array) -> StrudelFraction:
	var acc: StrudelFraction = null
	for s in list:
		if s == null:
			return null
		acc = s if acc == null else acc.lcm(s)
	return acc


# ═══════════════════════════════════════════════════════════════════════════
# Патернификация аргументов
# ═══════════════════════════════════════════════════════════════════════════
#
# 🔴 В Strudel ЛЮБОЙ аргумент может быть паттерном: `fast("<1 2 3>")` меняет
# скорость по циклам. Реализация повторяет register() из pattern.mjs:1690:
# если все аргументы «простые» — прямая ветка, иначе они собираются
# аппликативом и склеиваются innerJoin.

func _patternify(args: Array, fn: Callable, join_mode: String = "inner") -> StrudelPattern:
	var pats: Array = []
	for a in args:
		pats.append(StrudelPattern.reify(a))

	var all_pure := true
	for p in pats:
		if not p._has_pure:
			all_pure = false
			break
	if all_pure:
		var vals: Array = []
		for p in pats:
			vals.append(p._pure_value)
		return fn.call(vals)

	var acc: StrudelPattern = (pats[0] as StrudelPattern).fmap(func(v): return [v])
	for i in range(1, pats.size()):
		acc = acc.fmap(func(list: Array) -> Callable:
			return func(v): return list + [v]
		).app_left(pats[i])
	var built := acc.fmap(func(vals: Array) -> StrudelPattern:
		return fn.call(vals)
	)
	match join_mode:
		"outer":
			return built.outer_join()
		"squeeze":
			return built.squeeze_join()
		_:
			return built.inner_join()


# ═══════════════════════════════════════════════════════════════════════════
# Время
# ═══════════════════════════════════════════════════════════════════════════

func _fast(factor: Variant) -> StrudelPattern:
	var f := StrudelFraction.of(factor)
	if f.is_zero():
		return StrudelPattern.silence()
	return with_query_time(func(t: StrudelFraction) -> StrudelFraction:
		return t.mul(f)
	).with_hap_time(func(t: StrudelFraction) -> StrudelFraction:
		return t.div(f)
	).set_steps(steps)


func fast(factor: Variant) -> StrudelPattern:
	## Ускорить в N раз. То же, что `*` в mini-нотации.
	var me := self
	return _patternify([factor], func(vals: Array) -> StrudelPattern:
		return me._fast(vals[0])
	)


func _slow(factor: Variant) -> StrudelPattern:
	var f := StrudelFraction.of(factor)
	if f.is_zero():
		return StrudelPattern.silence()
	return _fast(StrudelFraction.new(1).div(f))


func slow(factor: Variant) -> StrudelPattern:
	## Замедлить. То же, что `/` в mini-нотации.
	var me := self
	return _patternify([factor], func(vals: Array) -> StrudelPattern:
		return me._slow(vals[0])
	)


func _early(offset: Variant) -> StrudelPattern:
	var o := StrudelFraction.of(offset)
	return with_query_time(func(t: StrudelFraction) -> StrudelFraction:
		return t.add(o)
	).with_hap_time(func(t: StrudelFraction) -> StrudelFraction:
		return t.sub(o)
	).set_steps(steps)


func early(offset: Variant) -> StrudelPattern:
	## Сдвинуть раньше на долю цикла.
	var me := self
	return _patternify([offset], func(vals: Array) -> StrudelPattern:
		return me._early(vals[0])
	)


func _late(offset: Variant) -> StrudelPattern:
	return _early(StrudelFraction.new(0).sub(StrudelFraction.of(offset)))


func late(offset: Variant) -> StrudelPattern:
	## Сдвинуть позже на долю цикла.
	var me := self
	return _patternify([offset], func(vals: Array) -> StrudelPattern:
		return me._late(vals[0])
	)


func rev() -> StrudelPattern:
	## Развернуть каждый цикл задом наперёд.
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var span := state.span
		var cycle := span.begin.sam()
		var next_cycle := span.begin.next_sam()
		var reflect := func(ts: StrudelTimeSpan) -> StrudelTimeSpan:
			# Отражение переворачивает концы местами.
			var b := cycle.add(next_cycle.sub(ts.begin))
			var e := cycle.add(next_cycle.sub(ts.end))
			return StrudelTimeSpan.new(e, b)
		var out: Array = []
		for hap in inner.query.call(state.set_span(reflect.call(span))):
			out.append(hap.with_span(reflect))
		return out
	).split_queries().set_steps(steps)


func revv() -> StrudelPattern:
	## Развернуть паттерн целиком, а не по циклам.
	var negate := func(ts: StrudelTimeSpan) -> StrudelTimeSpan:
		return StrudelTimeSpan.new(
			StrudelFraction.new(0).sub(ts.end),
			StrudelFraction.new(0).sub(ts.begin)
		)
	return with_query_span(negate).with_hap_span(negate)


func _compress(from_pos: Variant, to_pos: Variant) -> StrudelPattern:
	## Ужать цикл в отрезок, оставив тишину вокруг.
	var b := StrudelFraction.of(from_pos)
	var e := StrudelFraction.of(to_pos)
	if b.gt(e) or b.gt(1) or e.gt(1) or b.lt(0) or e.lt(0):
		return StrudelPattern.silence()
	return _fast_gap(StrudelFraction.new(1).div(e.sub(b)))._late(b)


func compress(from_pos: Variant, to_pos: Variant) -> StrudelPattern:
	var me := self
	return _patternify([from_pos, to_pos], func(vals: Array) -> StrudelPattern:
		return me._compress(vals[0], vals[1])
	)


func _fast_gap(factor: Variant) -> StrudelPattern:
	## Ускоряет, но вместо повтора оставляет тишину в остатке цикла.
	var f := StrudelFraction.of(factor)
	if f.lte(0):
		return StrudelPattern.silence()
	var qf := func(span: StrudelTimeSpan):
		var cycle := span.begin.sam()
		var bpos := span.begin.sub(cycle).mul(f).min_(StrudelFraction.new(1))
		var epos := span.end.sub(cycle).mul(f).min_(StrudelFraction.new(1))
		if bpos.gte(1):
			return null
		return StrudelTimeSpan.new(cycle.add(bpos), cycle.add(epos))
	var ef := func(hap: StrudelHap) -> StrudelHap:
		var begin := hap.part.begin
		var end := hap.part.end
		var cycle := begin.sam()
		var bp := begin.sub(cycle).div(f).min_(StrudelFraction.new(1))
		var ep := end.sub(cycle).div(f).min_(StrudelFraction.new(1))
		var new_part := StrudelTimeSpan.new(cycle.add(bp), cycle.add(ep))
		var new_whole = null
		if hap.whole != null:
			new_whole = StrudelTimeSpan.new(
				new_part.begin.sub(begin.sub(hap.whole.begin).div(f)),
				new_part.end.add(hap.whole.end.sub(end).div(f))
			)
		return StrudelHap.new(new_whole, new_part, hap.value, hap.context)
	return with_query_span_maybe(qf).with_hap(ef).split_queries()


func _focus(from_pos: Variant, to_pos: Variant) -> StrudelPattern:
	## Как compress, но без пауз и можно шире цикла.
	var b := StrudelFraction.of(from_pos)
	var e := StrudelFraction.of(to_pos)
	return _early(b.sam())._fast(StrudelFraction.new(1).div(e.sub(b)))._late(b)


func _focus_span(span: StrudelTimeSpan) -> StrudelPattern:
	return _focus(span.begin, span.end)


func _zoom(from_pos: Variant, to_pos: Variant) -> StrudelPattern:
	## Играет кусок паттерна, растянув его на весь цикл.
	var s := StrudelFraction.of(from_pos)
	var e := StrudelFraction.of(to_pos)
	if s.gte(e):
		return StrudelPattern.nothing()
	var d := e.sub(s)
	var new_steps = null if steps == null else steps.mul(d)
	return with_query_span(func(span: StrudelTimeSpan) -> StrudelTimeSpan:
		return span.with_cycle(func(t: StrudelFraction) -> StrudelFraction:
			return t.mul(d).add(s)
		)
	).with_hap_span(func(span: StrudelTimeSpan) -> StrudelTimeSpan:
		return span.with_cycle(func(t: StrudelFraction) -> StrudelFraction:
			return t.sub(s).div(d)
		)
	).split_queries().set_steps(new_steps)


func zoom(from_pos: Variant, to_pos: Variant) -> StrudelPattern:
	var me := self
	return _patternify([from_pos, to_pos], func(vals: Array) -> StrudelPattern:
		return me._zoom(vals[0], vals[1])
	)


func _ply(factor: Variant) -> StrudelPattern:
	var f := StrudelFraction.of(factor)
	var result := fmap(func(x) -> StrudelPattern:
		return StrudelPattern.pure(x)._fast(f)
	).squeeze_join()
	result.steps = null if steps == null else f.mul(steps)
	return result


func ply(factor: Variant) -> StrudelPattern:
	## Повторить каждое событие N раз внутри его же длительности.
	var me := self
	return _patternify([factor], func(vals: Array) -> StrudelPattern:
		return me._ply(vals[0])
	)


func _iter(times: Variant, back: bool = false) -> StrudelPattern:
	var n := StrudelFraction.of(times)
	var count := n.to_int()
	var list: Array = []
	for i in count:
		var shift := StrudelFraction.new(i).div(n)
		list.append(_late(shift) if back else _early(shift))
	return StrudelPattern.slowcat(list)


func iter(times: Variant) -> StrudelPattern:
	## Каждый цикл начинать со следующей доли.
	var me := self
	return _patternify([times], func(vals: Array) -> StrudelPattern:
		return me._iter(vals[0], false)
	)


func iter_back(times: Variant) -> StrudelPattern:
	var me := self
	return _patternify([times], func(vals: Array) -> StrudelPattern:
		return me._iter(vals[0], true)
	)


func _segment(rate: Variant) -> StrudelPattern:
	return struct_([StrudelPattern.pure(true)._fast(rate)]).set_steps(StrudelFraction.of(rate))


func segment(rate: Variant) -> StrudelPattern:
	## Нарезать непрерывный сигнал на N событий в цикле.
	var me := self
	return _patternify([rate], func(vals: Array) -> StrudelPattern:
		return me._segment(vals[0])
	)


func _repeat_cycles(n: int) -> StrudelPattern:
	var inner := self
	return StrudelPattern.new(func(state: StrudelState) -> Array:
		var cycle := state.span.begin.sam()
		var source_cycle := cycle.div(n).sam()
		var delta := cycle.sub(source_cycle)
		var shifted := state.with_span(func(span: StrudelTimeSpan) -> StrudelTimeSpan:
			return span.with_time(func(t: StrudelFraction) -> StrudelFraction:
				return t.sub(delta)
			)
		)
		var out: Array = []
		for hap in inner.query.call(shifted):
			out.append(hap.with_span(func(span: StrudelTimeSpan) -> StrudelTimeSpan:
				return span.with_time(func(t: StrudelFraction) -> StrudelFraction:
					return t.add(delta)
				)
			))
		return out
	).split_queries()


func repeat_cycles(n: Variant) -> StrudelPattern:
	var me := self
	return _patternify([n], func(vals: Array) -> StrudelPattern:
		return me._repeat_cycles(int(StrudelFraction.of(vals[0]).to_float()))
	)


func _linger(t: Variant) -> StrudelPattern:
	var f := StrudelFraction.of(t)
	if f.is_zero():
		return StrudelPattern.silence()
	if f.lt(0):
		return _zoom(f.add(1), 1)._slow(f)
	return _zoom(0, f)._slow(f)


func linger(t: Variant) -> StrudelPattern:
	var me := self
	return _patternify([t], func(vals: Array) -> StrudelPattern:
		return me._linger(vals[0])
	)


func _press_by(amount: Variant) -> StrudelPattern:
	var r := StrudelFraction.of(amount)
	return fmap(func(x) -> StrudelPattern:
		return StrudelPattern.pure(x)._compress(r, 1)
	).squeeze_join()


func press_by(amount: Variant) -> StrudelPattern:
	var me := self
	return _patternify([amount], func(vals: Array) -> StrudelPattern:
		return me._press_by(vals[0])
	)


func press() -> StrudelPattern:
	## Сдвинуть каждое событие на половину его длительности — синкопа.
	return _press_by(0.5)


func inside(factor: Variant, fn: Callable) -> StrudelPattern:
	## Выполнить действие «внутри» цикла.
	return (fn.call(_slow(factor)) as StrudelPattern)._fast(factor)


func outside(factor: Variant, fn: Callable) -> StrudelPattern:
	return (fn.call(_fast(factor)) as StrudelPattern)._slow(factor)


func swing_by(amount: Variant, subdivision: Variant) -> StrudelPattern:
	## Свинг: вторая половина каждой доли запаздывает.
	var shift := StrudelFraction.of(amount).div(2)
	return inside(subdivision, func(p: StrudelPattern) -> StrudelPattern:
		return p.late(StrudelPattern.sequence([0, shift]))
	)


func swing(subdivision: Variant) -> StrudelPattern:
	return swing_by(1.0 / 3.0, subdivision)


func every(n: Variant, fn: Callable) -> StrudelPattern:
	## Применять действие каждый N-й цикл, начиная с первого.
	var count := int(StrudelFraction.of(n).to_float())
	if count <= 0:
		return self
	var list: Array = [fn.call(self)]
	for i in count - 1:
		list.append(self)
	return StrudelPattern.slowcat_prime(list)


func first_of(n: Variant, fn: Callable) -> StrudelPattern:
	return every(n, fn)


func last_of(n: Variant, fn: Callable) -> StrudelPattern:
	var count := int(StrudelFraction.of(n).to_float())
	if count <= 0:
		return self
	var list: Array = []
	for i in count - 1:
		list.append(self)
	list.append(fn.call(self))
	return StrudelPattern.slowcat_prime(list)


func when_(condition: bool, fn: Callable) -> StrudelPattern:
	return fn.call(self) if condition else self


func palindrome() -> StrudelPattern:
	return last_of(2, func(p: StrudelPattern) -> StrudelPattern: return p.rev())


func off(time_shift: Variant, fn: Callable) -> StrudelPattern:
	## Наложить сдвинутую копию, изменённую действием. Так делается эхо.
	return StrudelPattern.stack([self, fn.call(late(time_shift))])


func superimpose(fns: Array) -> StrudelPattern:
	var list: Array = [self]
	for f in fns:
		list.append(f.call(self))
	return StrudelPattern.stack(list)


func layer(fns: Array) -> StrudelPattern:
	## Как superimpose, но без исходного паттерна.
	var list: Array = []
	for f in fns:
		list.append(f.call(self))
	return StrudelPattern.stack(list)


func jux_by(amount: Variant, fn: Callable) -> StrudelPattern:
	## Стерео-раздвоение: изменённая копия уходит в другой канал.
	var by := StrudelFraction.of(amount).to_float() / 2.0
	var left := with_value(func(v):
		var d: Dictionary = (v as Dictionary).duplicate() if v is Dictionary else {"value": v}
		d["pan"] = float(d.get("pan", 0.5)) - by
		return d
	)
	var right_src := with_value(func(v):
		var d: Dictionary = (v as Dictionary).duplicate() if v is Dictionary else {"value": v}
		d["pan"] = float(d.get("pan", 0.5)) + by
		return d
	)
	var right: StrudelPattern = fn.call(right_src)
	var result := StrudelPattern.stack([left, right])
	result.steps = _lcm_steps([left.steps, right.steps])
	return result


func jux(fn: Callable) -> StrudelPattern:
	return jux_by(1, fn)


func echo_with(times: int, time_shift: Variant, fn: Callable) -> StrudelPattern:
	var list: Array = []
	for i in times:
		list.append(fn.call(late(StrudelFraction.of(time_shift).mul(i)), i))
	return StrudelPattern.stack(list)


func echo(times: int, time_shift: Variant, feedback: float) -> StrudelPattern:
	## Затухающее эхо.
	return echo_with(times, time_shift, func(p: StrudelPattern, i: int) -> StrudelPattern:
		return p.gain(pow(feedback, i))
	)


func chunk(n: int, fn: Callable, back: bool = false, fast_mode: bool = false) -> StrudelPattern:
	## Делит цикл на N частей и применяет действие к одной части за цикл.
	var binary: Array = [true]
	for i in n - 1:
		binary.append(false)
	var binary_pat := StrudelPattern.sequence(binary)._iter(n, not back)
	var target := self if fast_mode else _repeat_cycles(n)
	return target._when_pat(binary_pat, fn)


func _when_pat(binary_pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	var me := self
	return binary_pat.fmap(func(on) -> StrudelPattern:
		return fn.call(me) if StrudelPattern.truthy(on) else me
	).inner_join()


func ribbon(offset: Variant, cycles: Variant) -> StrudelPattern:
	## Зациклить кусок паттерна длиной `cycles`, начиная с `offset`.
	return early(offset).restart([StrudelPattern.pure(1)._slow(cycles)])


func apply(fn: Callable) -> StrudelPattern:
	return fn.call(self)


func apply_n(n: int, fn: Callable) -> StrudelPattern:
	var result: StrudelPattern = self
	for i in n:
		result = fn.call(result)
	return result


func hurry(factor: Variant) -> StrudelPattern:
	## Ускоряет и паттерн, и воспроизведение сэмпла.
	return _fast(factor).mul([StrudelPattern.pure({"speed": StrudelFraction.of(factor).to_float()})])


func pace(target_steps: Variant) -> StrudelPattern:
	## Подогнать паттерн под заданное число шагов в цикле.
	if steps == null:
		return self
	if steps.is_zero():
		return StrudelPattern.nothing()
	var t := StrudelFraction.of(target_steps)
	return _fast(t.div(steps)).set_steps(t)


func filter_when(test: Callable) -> StrudelPattern:
	return filter_haps(func(h: StrudelHap) -> bool:
		return test.call(h.whole.begin) if h.whole != null else false
	)


func within(from_pos: Variant, to_pos: Variant, fn: Callable) -> StrudelPattern:
	var a := StrudelFraction.of(from_pos)
	var b := StrudelFraction.of(to_pos)
	var inside_pat := filter_when(func(t: StrudelFraction) -> bool:
		var p := t.cycle_pos()
		return p.gte(a) and p.lte(b)
	)
	var outside_pat := filter_when(func(t: StrudelFraction) -> bool:
		var p := t.cycle_pos()
		return p.lt(a) or p.gt(b)
	)
	return StrudelPattern.stack([fn.call(inside_pat), outside_pat])


# ═══════════════════════════════════════════════════════════════════════════
# Нарезка сэмплов
# ═══════════════════════════════════════════════════════════════════════════

func chop(n: int) -> StrudelPattern:
	## Режет каждый сэмпл на N кусков.
	var slices: Array = []
	for i in n:
		slices.append({"begin": float(i) / n, "end": float(i + 1) / n})
	var result := squeeze_bind(func(o) -> StrudelPattern:
		var merged: Array = []
		for sl in slices:
			var b: Dictionary = (sl as Dictionary).duplicate()
			var base: Dictionary = o if o is Dictionary else {"value": o}
			if base.has("begin") and base.has("end"):
				var d: float = float(base["end"]) - float(base["begin"])
				b = {"begin": float(base["begin"]) + float(b["begin"]) * d,
					 "end": float(base["begin"]) + float(b["end"]) * d}
			var out := base.duplicate()
			for k in b:
				out[k] = b[k]
			merged.append(out)
		return StrudelPattern.sequence(merged)
	)
	result.steps = null if steps == null else StrudelFraction.new(n).mul(steps)
	return result


func striate(n: int) -> StrudelPattern:
	## Режет сэмплы и проигрывает соответственные куски по очереди.
	var slices: Array = []
	for i in n:
		slices.append({"begin": float(i) / n, "end": float(i + 1) / n})
	var slice_pat := StrudelPattern.slowcat(slices)
	var result := set_([slice_pat])._fast(n)
	result.steps = null if steps == null else StrudelFraction.new(n).mul(steps)
	return result


# ═══════════════════════════════════════════════════════════════════════════
# Истинность по правилам JavaScript
# ═══════════════════════════════════════════════════════════════════════════

static func truthy(v: Variant) -> bool:
	## 🔴 Правила JS, а не GDScript: 0 — ложь, "0" — ИСТИНА, "" — ложь.
	## На этом стоит `struct("1 0 1")` против `struct("x ~ x")`.
	if v == null:
		return false
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0 and not is_nan(v)
	if v is String or v is StringName:
		return String(v) != ""
	return true


# ═══════════════════════════════════════════════════════════════════════════
# Слияние управляющих паттернов
# ═══════════════════════════════════════════════════════════════════════════
#
# 🔴 Перенос таблицы COMPOSERS (pattern.mjs:1042) вместе с восемью
# выравниваниями. Выравнивание решает, КТО задаёт доли:
#   in       — левый (по умолчанию)
#   out      — правый
#   mix      — пересечение
#   squeeze  — правый ужимается в каждое событие левого
#   reset / restart — правый перезапускает левый
# `struct` — это keepif.out, `mask` — keepif.in. Перепутать их местами значит
# получить рисунок из другого паттерна.

const _ALIGNMENTS := ["in", "out", "mix", "squeeze", "squeezeout", "reset", "restart", "poly"]


static func _op_value(op_name: String, a: Variant, b: Variant) -> Variant:
	match op_name:
		"set": return b
		"keep": return a
		"keepif": return a if truthy(b) else null
		"add": return _numeral_op(a, b, "+")
		"sub": return _numeral_op(a, b, "-")
		"mul": return _numeral_op(a, b, "*")
		"div": return _numeral_op(a, b, "/")
		"mod": return _numeral_op(a, b, "%")
		"pow": return _numeral_op(a, b, "^")
		"band": return int(_num(a)) & int(_num(b))
		"bor": return int(_num(a)) | int(_num(b))
		"bxor": return int(_num(a)) ^ int(_num(b))
		"blshift": return int(_num(a)) << int(_num(b))
		"brshift": return int(_num(a)) >> int(_num(b))
		"lt": return _num(a) < _num(b)
		"gt": return _num(a) > _num(b)
		"lte": return _num(a) <= _num(b)
		"gte": return _num(a) >= _num(b)
		"eq": return a == b
		"ne": return a != b
		"and": return b if truthy(a) else a
		"or": return a if truthy(a) else b
	push_error("Strudel: неизвестная операция слияния \"%s\"" % op_name)
	return b


static func _num(x: Variant) -> float:
	if x is int or x is float:
		return float(x)
	if x is bool:
		return 1.0 if x else 0.0
	if x is String or x is StringName:
		var s := String(x)
		if s.is_valid_float():
			return s.to_float()
		if StrudelUtil.is_note(s):
			return float(StrudelUtil.note_to_midi(s))
	if x == null:
		return 0.0
	return NAN


static func _numeral_op(a: Variant, b: Variant, op: String) -> Variant:
	## `add` в Strudel умеет и числа, и склейку строк, и ноты.
	var na := _num(a)
	var nb := _num(b)
	if is_nan(na) or is_nan(nb):
		if op == "+" and (a is String or a is StringName) and (b is String or b is StringName):
			return String(a) + String(b)
		return b
	match op:
		"+": return na + nb
		"-": return na - nb
		"*": return na * nb
		"/": return na / nb if nb != 0.0 else 0.0
		"%": return StrudelUtil.mod_f(na, nb)
		"^": return pow(na, nb)
	return nb


static func _compose_op(a: Variant, b: Variant, op_name: String) -> Variant:
	## Если хоть одна сторона — словарь, сливаются словари; иначе — значения.
	if a is Dictionary or b is Dictionary:
		var da: Dictionary = a if a is Dictionary else {"value": a}
		var db: Dictionary = b if b is Dictionary else {"value": b}
		return _union_with(da, db, op_name)
	return _op_value(op_name, a, b)


static func _union_with(a: Dictionary, b: Dictionary, op_name: String) -> Dictionary:
	# 🔴 Правило оригинала (`value.mjs:12`): если справа ГОЛОЕ значение —
	# арифметика над управляющим паттерном НЕ делается, левое возвращается
	# как есть. Поэтому `n("0 2").add(7)` ничего не меняет, а `n("0 2").add(n(7))`
	# меняет. Выглядит неожиданно, но так ведёт себя Strudel, и трек на это
	# опирается: сверка с Булкой поймала это на девяти проверках сразу.
	if b.size() == 1 and b.has("value") and b["value"] != null:
		return a
	var out := a.duplicate()
	for k in b:
		if a.has(k):
			out[k] = _op_value(op_name, a[k], b[k])
		else:
			out[k] = b[k]
	return out


func _compose(op_name: String, how: String, others: Array) -> StrudelPattern:
	var other := StrudelPattern.sequence(others)
	var result: StrudelPattern
	if op_name == "keepif":
		result = _apply_alignment(how, other, func(a, b): return _op_value("keepif", a, b))
		result = result.remove_undefineds()
	else:
		result = _apply_alignment(how, other, func(a, b): return _compose_op(a, b, op_name))
	return result


func _apply_alignment(how: String, other: StrudelPattern, f: Callable) -> StrudelPattern:
	var me := self
	match how:
		"in":
			return fmap(func(a) -> Callable:
				return func(b): return f.call(a, b)
			).app_left(other)
		"out":
			return fmap(func(a) -> Callable:
				return func(b): return f.call(a, b)
			).app_right(other)
		"mix":
			return fmap(func(a) -> Callable:
				return func(b): return f.call(a, b)
			).app_both(other)
		"squeeze":
			return fmap(func(a) -> StrudelPattern:
				return other.fmap(func(b): return f.call(a, b))
			).squeeze_join()
		"squeezeout":
			return other.fmap(func(a) -> StrudelPattern:
				return me.fmap(func(b): return f.call(b, a))
			).squeeze_join()
		"reset":
			return other.fmap(func(b) -> StrudelPattern:
				return me.fmap(func(a): return f.call(a, b))
			).reset_join()
		"restart":
			return other.fmap(func(b) -> StrudelPattern:
				return me.fmap(func(a): return f.call(a, b))
			).restart_join()
		"poly":
			return fmap(func(b) -> StrudelPattern:
				return other.fmap(func(a): return f.call(a, b))
			).poly_join()
	push_error("Strudel: неизвестное выравнивание \"%s\"" % how)
	return self


func poly_join() -> StrudelPattern:
	var pp := self
	return fmap(func(p: StrudelPattern) -> StrudelPattern:
		if pp.steps == null or p.steps == null or p.steps.is_zero():
			return p
		return p.extend(pp.steps.div(p.steps))
	).outer_join()


func extend(factor: Variant) -> StrudelPattern:
	return _fast(factor).expand(factor)


func expand(factor: Variant) -> StrudelPattern:
	var f := StrudelFraction.of(factor)
	var out := StrudelPattern.new(query, null)
	out.steps = null if steps == null else steps.mul(f)
	return out


func contract(factor: Variant) -> StrudelPattern:
	var f := StrudelFraction.of(factor)
	var out := StrudelPattern.new(query, null)
	out.steps = null if steps == null else steps.div(f)
	return out


# — операции с выравниванием по умолчанию («in») и явные варианты —

func set_(others: Array, how: String = "in") -> StrudelPattern:
	## Значения справа перекрывают значения слева.
	return _compose("set", how, others)


func keep(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("keep", how, others)


func keepif(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("keepif", how, others)


func add(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("add", how, others)


func sub(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("sub", how, others)


func mul(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("mul", how, others)


func div(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("div", how, others)


func mod_(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("mod", how, others)


func pow_(others: Array, how: String = "in") -> StrudelPattern:
	return _compose("pow", how, others)


func struct_(others: Array) -> StrudelPattern:
	## Наложить ритмический рисунок: структура берётся СПРАВА.
	return _compose("keepif", "out", others)


func struct_all(others: Array) -> StrudelPattern:
	return _compose("keep", "out", others)


func mask_(others: Array) -> StrudelPattern:
	## Заглушить там, где маска ложна: структура остаётся СЛЕВА.
	return _compose("keepif", "in", others)


func mask_all(others: Array) -> StrudelPattern:
	return _compose("keep", "in", others)


func reset(others: Array) -> StrudelPattern:
	return _compose("keepif", "reset", others)


func restart(others: Array) -> StrudelPattern:
	return _compose("keepif", "restart", others)


# ═══════════════════════════════════════════════════════════════════════════
# Числовые преобразования
# ═══════════════════════════════════════════════════════════════════════════

func as_number() -> StrudelPattern:
	return fmap(func(v): return StrudelUtil.parse_numeral(v))


func round_() -> StrudelPattern:
	return as_number().fmap(func(v): return int(round(_num(v))))


func floor_p() -> StrudelPattern:
	return as_number().fmap(func(v): return int(floor(_num(v))))


func ceil_p() -> StrudelPattern:
	return as_number().fmap(func(v): return int(ceil(_num(v))))


func to_bipolar() -> StrudelPattern:
	return fmap(func(v): return _num(v) * 2.0 - 1.0)


func from_bipolar() -> StrudelPattern:
	return fmap(func(v): return (_num(v) + 1.0) / 2.0)


func range_(low: Variant, high: Variant) -> StrudelPattern:
	## Растянуть сигнал 0..1 в заданные границы.
	var lo := _num(low)
	var hi := _num(high)
	return mul([hi - lo]).add([lo])


func rangex(low: Variant, high: Variant) -> StrudelPattern:
	## То же, но по показательной кривой — так слышится частота фильтра.
	var lo := _num(low)
	var hi := _num(high)
	return range_(log(lo), log(hi)).fmap(func(v): return exp(_num(v)))


func range2(low: Variant, high: Variant) -> StrudelPattern:
	## Для сигналов -1..1.
	return from_bipolar().range_(low, high)


# ═══════════════════════════════════════════════════════════════════════════
# Управляющие значения
# ═══════════════════════════════════════════════════════════════════════════

func ctrl(name: String, value: Variant) -> StrudelPattern:
	## Общий путь: поставить любой параметр Strudel по имени.
	## Именованные обёртки (gain, lpf, room…) живут в StrudelControls.
	return set_([StrudelPattern.reify(value).fmap(func(v): return {name: v})])


func gain(value: Variant) -> StrudelPattern:
	## Громкость события.
	return ctrl("gain", value)


func _to_string() -> String:
	return "StrudelPattern(steps=%s)" % (steps.show() if steps != null else "—")
