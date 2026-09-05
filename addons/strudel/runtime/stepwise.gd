@tool
class_name StrudelStepwise
extends RefCounted

## Пошаговые действия — семья `take`/`drop`/`grow`/`shrink`/`tour`/`zip`
## (`core/pattern.mjs`, раздел «Stepwise functions»).
##
## Обычные действия Strudel меряют время ДОЛЯМИ КРУГА. Эти — ШАГАМИ: у
## паттерна есть число шагов (`steps`), и `"bd cp ht mt".take(2)` берёт
## два шага из четырёх, а не половину круга. Разница видна, как только
## паттерны склеиваются: `stepcat` кладёт их встык по шагам.
##
## 🔴 Без числа шагов эти действия отдают ПУСТОТУ, а не паттерн целиком.
## Так в оригинале: шагов нет — считать нечего.


static func take(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## Взять N шагов: положительное — с начала, отрицательное — с конца.
	return _step_patternify(pat, amount, func(p: StrudelPattern, i: StrudelFraction) -> StrudelPattern:
		if p.steps == null or p.steps.to_float() <= 0.0 or i.is_zero():
			return StrudelPattern.nothing()
		var flip := i.to_float() < 0.0
		var n := i.abs_() if flip else i
		var frac := n.div(p.steps)
		if frac.to_float() <= 0.0:
			return StrudelPattern.nothing()
		if frac.to_float() >= 1.0:
			return p
		if flip:
			return p.zoom(StrudelFraction.new(1).sub(frac), StrudelFraction.new(1))
		return p.zoom(StrudelFraction.new(0), frac)
	)


static func drop(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## Выбросить N шагов: положительное — с начала, отрицательное — с конца.
	return _step_patternify(pat, amount, func(p: StrudelPattern, i: StrudelFraction) -> StrudelPattern:
		if p.steps == null:
			return StrudelPattern.nothing()
		if i.to_float() < 0.0:
			return take(p, p.steps.add(i))
		return take(p, StrudelFraction.new(0).sub(p.steps.sub(i)))
	)


static func shrinklist(pat: StrudelPattern, amount: Variant) -> Array:
	## Ряд всё более коротких кусков паттерна.
	##
	## Довод парой (`"1:3"` в mini-нотации) значит «по стольку шагов, столько
	## раз»; одно число — «пока не кончатся шаги».
	if pat.steps == null:
		return [pat]
	var value: Variant = amount
	var times: Variant = pat.steps
	if amount is Array and (amount as Array).size() >= 2:
		value = amount[0]
		times = amount[1]
	var a := StrudelFraction.of(value)
	# 🔴 ЧИСЛО ПРОХОДОВ ОКРУГЛЯЕТСЯ ВВЕРХ, А НЕ ОБРЕЗАЕТСЯ. В оригинале
	# (`pattern.mjs:3338`) счётчик сравнивается с ДРОБЬЮ: `for (let i = 0;
	# i < times; ++i)`, и при 2.5 шагах проходов выходит три, а не два.
	var count := int(ceil(StrudelPattern._num(times) - 1e-9))
	# 🔴 НУЛЕВОЙ ДОВОД НЕ ОБРЫВАЕТ РЯД. В оригинале проверка написана как
	# `amountv === 0`, где слева ОБЪЕКТ-дробь, — она не срабатывает никогда,
	# и при нуле выходит столько копий целого паттерна, сколько шагов.
	# Повторяем это: обрывает ряд только `times == 0`.
	if count == 0:
		return [pat]

	var ranges: Array = []
	if a.to_float() > 0.0:
		var seg := StrudelFraction.new(1).div(pat.steps).mul(a)
		for i in count:
			var s := seg.mul(StrudelFraction.new(i))
			if s.to_float() > 1.0:
				break
			ranges.append([s, StrudelFraction.new(1)])
	else:
		var av := StrudelFraction.new(0).sub(a)
		var seg2 := StrudelFraction.new(1).div(pat.steps).mul(av)
		for i in count:
			var e := StrudelFraction.new(1).sub(seg2.mul(StrudelFraction.new(i)))
			if e.to_float() < 0.0:
				break
			ranges.append([StrudelFraction.new(0), e])

	var out: Array = []
	for r in ranges:
		out.append(pat.zoom(r[0], r[1]))
	return out


static func growlist(pat: StrudelPattern, amount: Variant) -> Array:
	## `shrinklist` задом наперёд.
	var list := shrinklist(pat, amount)
	list.reverse()
	return list


static func shrink(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## Паттерн, укорачивающийся с каждым повтором.
	# Довод может прийти ПАРОЙ («по стольку шагов, столько раз»), поэтому тип
	# здесь свободный: `shrinklist` разбирает обе формы сам.
	return _step_patternify(pat, amount, func(p: StrudelPattern, i: Variant) -> StrudelPattern:
		if p.steps == null:
			return StrudelPattern.nothing()
		return _cat_list(shrinklist(p, i))
	)


static func grow(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## Паттерн, дорастающий до целого.
	return _step_patternify(pat, amount, func(p: StrudelPattern, i: Variant) -> StrudelPattern:
		if p.steps == null:
			return StrudelPattern.nothing()
		# У пары отрицается только ВЕЛИЧИНА, число проходов остаётся.
		var neg: Variant
		if i is Array:
			var pair: Array = i
			neg = [StrudelFraction.new(0).sub(StrudelFraction.of(pair[0])), pair[1]]
		else:
			neg = StrudelFraction.new(0).sub(StrudelFraction.of(i))
		var list := shrinklist(p, neg)
		list.reverse()
		return _cat_list(list)
	)


static func tour(pat: StrudelPattern, many: Array) -> StrudelPattern:
	## Вставить паттерн в ряд других и вести его НАЗАД по ряду, повтор за
	## повтором. Всё умещается в один круг, поэтому обычно рядом ставят
	## `pace`.
	var parts: Array = []
	for i in many.size():
		var tail_len := many.size() - i
		for j in tail_len:
			parts.append(many[j])
		parts.append(pat)
		for j in range(tail_len, many.size()):
			parts.append(many[j])
	parts.append(pat)
	for x in many:
		parts.append(x)
	return StrudelPattern.stepcat(parts)


static func zip(pats: Array) -> StrudelPattern:
	## Сшить шаги нескольких паттернов вперемежку.
	var list: Array = []
	for p in pats:
		var pp := StrudelPattern._as_pat(p)
		if pp.steps != null:
			list.append(pp)
	if list.is_empty():
		return StrudelPattern.nothing()
	var slowed: Array = []
	var steps: StrudelFraction = list[0].steps
	for p in list:
		slowed.append(p._slow(p.steps))
		steps = steps.lcm(p.steps)
	return StrudelPattern.slowcat(slowed)._fast(steps).set_steps(steps)


static func _cat_list(list: Array) -> StrudelPattern:
	var result := StrudelPattern.stepcat(list)
	var total := StrudelFraction.new(0)
	for p in list:
		if (p as StrudelPattern).steps != null:
			total = total.add((p as StrudelPattern).steps)
	result.steps = total
	return result


static func _step_patternify(pat: StrudelPattern, amount: Variant, fn: Callable) -> StrudelPattern:
	## Как `register` с `stepJoin`: довод — паттерн, склейка ПОШАГОВАЯ.
	# 🔴 ПАРУ ДОВОДОВ НЕЛЬЗЯ ПРИВОДИТЬ К ДРОБИ. `shrink("1:3")` в
	# mini-нотации даёт СПИСОК [1, 3] — «по стольку шагов, столько раз», — а
	# `StrudelFraction.of` превращал его в одно число, и вторая половина
	# довода пропадала: замерено, `shrink("1:3")` звучал как `shrink(1)`.
	# Пропускаем список как есть, приводим только одиночные числа.
	var as_arg := func(v: Variant) -> Variant:
		return v if v is Array else StrudelFraction.of(v)
	var arg := StrudelPattern.reify(amount)
	if arg._has_pure:
		return fn.call(pat, as_arg.call(arg._pure_value))
	return arg.fmap(func(v) -> StrudelPattern:
		return fn.call(pat, as_arg.call(v))
	).step_join()
