@tool
class_name StrudelEuclid
extends RefCounted

## Эвклидовы ритмы. Перенос `packages/core/euclid.mjs`
## (алгоритм Бьорклунда в изложении Рохана Дрейпа).
##
## Раскладывает N ударов по M шагам как можно ровнее. Этим одним приёмом
## описывается огромная часть народных ритмов: (3,8) — кубинское трезильо,
## (5,8) — синкильо, (7,12) — западноафриканский колокол.


static func bjorklund(pulses: int, steps: int) -> Array:
	## → массив из 0 и 1 длиной `steps`.
	## Отрицательное число ударов переворачивает рисунок.
	var inverted := pulses < 0
	var ons := absi(pulses)
	var offs := steps - ons
	if steps <= 0 or ons <= 0:
		var empty: Array = []
		for i in maxi(steps, 0):
			empty.append(1 if inverted else 0)
		return empty
	if offs < 0:
		offs = 0

	var xs: Array = []
	for i in ons:
		xs.append([1])
	var ys: Array = []
	for i in offs:
		ys.append([0])

	var state := _recurse(ons, offs, xs, ys)
	var out: Array = []
	for group in state[2]:
		out.append_array(group)
	for group in state[3]:
		out.append_array(group)
	if inverted:
		for i in out.size():
			out[i] = 1 - int(out[i])
	return out


static func _recurse(ons: int, offs: int, xs: Array, ys: Array) -> Array:
	while mini(ons, offs) > 1:
		if ons > offs:
			# left: хвост xs откладывается, голова склеивается с ys
			var head := xs.slice(0, offs)
			var tail := xs.slice(offs)
			var merged: Array = []
			for i in head.size():
				merged.append((head[i] as Array) + (ys[i] as Array))
			var new_ons := offs
			var new_offs := ons - offs
			ons = new_ons
			offs = new_offs
			xs = merged
			ys = tail
		else:
			# right: голова ys склеивается с xs, хвост откладывается
			var head := ys.slice(0, ons)
			var tail := ys.slice(ons)
			var merged: Array = []
			for i in xs.size():
				merged.append((xs[i] as Array) + (head[i] as Array))
			offs = offs - ons
			xs = merged
			ys = tail
	return [ons, offs, xs, ys]


static func euclid_rot(pulses: int, steps: int, rotation: int = 0) -> Array:
	var b := bjorklund(pulses, steps)
	if rotation != 0:
		return StrudelUtil.rotate_array(b, -rotation)
	return b


static func apply(pat: StrudelPattern, pulses: int, steps: int, rotation: int = 0) -> StrudelPattern:
	## Наложить эвклидов рисунок на паттерн.
	return pat.struct_([StrudelPattern.sequence(euclid_rot(pulses, steps, rotation))])


static func bjork(pat: StrudelPattern, euc: Variant) -> StrudelPattern:
	## Рисунок ОДНИМ доводом: `[доли, шаги, поворот]`. Число вместо списка
	## значит «столько долей из стольких же шагов» — то есть ровный ряд.
	var list: Array = euc if euc is Array else [euc]
	if list.is_empty():
		return pat
	var pulses := int(StrudelPattern._num(list[0]))
	var steps := int(StrudelPattern._num(list[1])) if list.size() > 1 else pulses
	var rotation := int(StrudelPattern._num(list[2])) if list.size() > 2 else 0
	return apply(pat, pulses, steps, rotation)


static func apply_ish(pat: StrudelPattern, pulses: int, steps: int,
		groove: Variant) -> StrudelPattern:
	## `euclidish` — переход между эвклидовым рисунком и ровным пульсом.
	##
	## 🔴 Ноль даёт ЧИСТЫЙ euclid, единица — ровные доли; между ними доли
	## ползут от эвклидовых мест к ровным. Приём Малкольма Браффа: качание
	## задаётся не сдвигом отдельных нот, а натяжением всей сетки.
	var even: Array = []
	for _i in pulses:
		even.append(1)
	var morphed := StrudelPattern.morph(bjorklund(pulses, steps), even, groove)
	return pat.struct_([morphed]).set_steps(StrudelFraction.new(steps))


static func apply_legato(pat: StrudelPattern, pulses: int, steps: int, rotation: int = 0) -> StrudelPattern:
	## Как euclid, но нота тянется до следующей — без пауз.
	if pulses < 1:
		return StrudelPattern.silence()
	var bin := euclid_rot(pulses, steps, 0)
	var groups: Array = []
	var length := 0
	var started := false
	for v in bin:
		if int(v) == 1:
			if started:
				groups.append([length, StrudelPattern.pure(true)])
			started = true
			length = 1
		elif started:
			length += 1
	if started:
		groups.append([length, StrudelPattern.pure(true)])
	if groups.is_empty():
		return StrudelPattern.silence()
	return pat.struct_([StrudelPattern.stepcat(groups)])._late(StrudelFraction.make(rotation, steps))
