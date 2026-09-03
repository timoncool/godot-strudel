@tool
class_name StrudelMini
extends RefCounted

## Сборка паттерна из дерева mini-нотации. Перенос `packages/mini/mini.mjs`.
##
## 🔴 Смещение случайного у "?" — 0.0003 на каждый знак вопроса по порядку в
## строке (`mini.mjs:11`). Поэтому `s("hh*8?")` и `s("hh*8").degradeBy(0.5)`
## выбрасывают РАЗНЫЕ события, хотя вероятность одна.

const RAND_OFFSET := 0.0003


static func mini(text: String) -> StrudelPattern:
	## Строка mini-нотации → паттерн. Ошибка разбора сообщается с позицией.
	##
	var parsed := StrudelKrillParser.parse(text)
	if not parsed.get("ok", false):
		var pos: int = parsed.get("pos", -1)
		push_error("Strudel: ошибка в mini-нотации на позиции %d: %s\n  %s\n  %s^"
			% [pos, parsed.get("error", "?"), text, " ".repeat(maxi(pos, 0))])
		return StrudelPattern.silence()
	return to_pattern(parsed["ast"])


static func try_mini(text: String) -> Dictionary:
	## Как mini(), но ошибку возвращает, а не печатает. Для тестов и редактора.
	var parsed := StrudelKrillParser.parse(text)
	if not parsed.get("ok", false):
		return parsed
	return {"ok": true, "pattern": to_pattern(parsed["ast"])}


static func to_pattern(node: Dictionary) -> StrudelPattern:
	match String(node.get("t", "")):
		"atom":
			return _atom(node)
		"element":
			return to_pattern(node["src"])
		"pattern":
			return _pattern_node(node)
	push_error("Strudel: неизвестный узел mini-нотации \"%s\"" % str(node.get("t")))
	return StrudelPattern.silence()


static func _atom(node: Dictionary) -> StrudelPattern:
	var src := String(node["src"])
	# И "~", и "-" означают паузу.
	if src == "~" or src == "-":
		return StrudelPattern.silence()
	return StrudelPattern.pure(_value_of(src))


static func _value_of(src: String) -> Variant:
	## Числа становятся числами, остальное остаётся строкой.
	if src.is_valid_int():
		return src.to_int()
	if src.is_valid_float():
		return src.to_float()
	return src


static func _pattern_node(node: Dictionary) -> StrudelPattern:
	var sources: Array = node.get("src", [])
	var children: Array = []
	for i in sources.size():
		var child := to_pattern(sources[i])
		child = _apply_options(child, sources[i])
		children.append(child)

	var align := String(node.get("align", "fastcat"))
	match align:
		"stack":
			return StrudelPattern.stack(children)
		"feet":
			return StrudelPattern.fastcat(children)
		"rand":
			# Один вариант на цикл, выбор — тем же случайным, что в оригинале.
			var seed := int(node.get("seed", 0))
			var chooser := StrudelSignal.rand()._early(RAND_OFFSET * seed)._segment(1)
			return StrudelSignal.choose_in_with(chooser, children)
		"polymeter_slowcat":
			# "<a b c>" — по одному шагу за цикл. Каждая дорожка замедляется на
			# СВОЙ вес, поэтому "<a b, c d e>" даёт полиритм по циклам.
			var slowed: Array = []
			for i in children.size():
				var w := _weight_sum(sources[i])
				slowed.append((children[i] as StrudelPattern)._slow(w))
			return StrudelPattern.stack(slowed)
		"polymeter":
			var target: StrudelPattern
			if node.has("steps_per_cycle"):
				target = to_pattern(node["steps_per_cycle"])
			else:
				var first_w := _weight_sum(sources[0]) if sources.size() > 0 else 1.0
				target = StrudelPattern.pure(first_w)
			var aligned: Array = []
			for i in children.size():
				var w := _weight_sum(sources[i])
				aligned.append((children[i] as StrudelPattern).fast(
					target.fmap(func(x): return float(x) / w)
				))
			return StrudelPattern.stack(aligned)

	# fastcat: элементы с весами укладываются пропорционально.
	var weighted: Array = []
	var total := 0.0
	for i in sources.size():
		var w := float((sources[i] as Dictionary).get("weight", 1.0))
		total += w
		weighted.append([w, children[i]])
	var result := StrudelPattern.stepcat(weighted)
	result.steps = StrudelFraction.of(total)
	return result


static func _weight_sum(node: Dictionary) -> float:
	## Суммарный вес последовательности — им меряется её «длина в шагах».
	if String(node.get("t", "")) != "pattern":
		return float(node.get("weight", 1.0))
	var sources: Array = node.get("src", [])
	if String(node.get("align", "fastcat")) != "fastcat":
		return float(maxi(sources.size(), 1))
	var total := 0.0
	for s in sources:
		total += float((s as Dictionary).get("weight", 1.0))
	return total if total > 0.0 else 1.0


static func _apply_options(pat: StrudelPattern, node: Dictionary) -> StrudelPattern:
	if String(node.get("t", "")) != "element":
		return pat
	var ops: Array = node.get("ops", [])
	for op in ops:
		pat = _apply_op(pat, op)
	return pat


static func _apply_op(pat: StrudelPattern, op: Dictionary) -> StrudelPattern:
	match String(op.get("t", "")):
		"stretch":
			var amount := to_pattern(op["amount"])
			return pat.fast(amount) if String(op["type"]) == "fast" else pat.slow(amount)
		"replicate":
			var amount := int(op["amount"])
			return pat._repeat_cycles(amount)._fast(amount)
		"bjorklund":
			var pulses := _static_int(op["pulse"])
			var step_count := _static_int(op["step"])
			var rotation := 0
			if op.get("rotation") != null:
				rotation = _static_int(op["rotation"])
			return StrudelEuclid.apply(pat, pulses, step_count, rotation)
		"degradeBy":
			var amount: Variant = op.get("amount")
			var seed := int(op.get("seed", 0))
			var chance: float = float(amount) if amount != null else 0.5
			return StrudelSignal.degrade_by_with(
				pat, StrudelSignal.rand()._early(RAND_OFFSET * seed), chance
			)
		"tail":
			# "bd:3" — значение становится списком ["bd", 3], который потом
			# разбирают управляющие функции (s → {s:"bd", n:3}).
			var friend := to_pattern(op["element"])
			return pat.fmap(func(a) -> Callable:
				return func(b):
					if a is Array:
						return (a as Array) + [b]
					return [a, b]
			).app_left(friend)
		"range":
			# "0 .. 3" — разворачивается в последовательность 0 1 2 3.
			var to_pat := to_pattern(op["element"])
			return pat.squeeze_bind(func(a) -> StrudelPattern:
				return to_pat.bind(func(b) -> StrudelPattern:
					return StrudelPattern.fastcat(_range_list(a, b))
				)
			)
	push_warning("Strudel: модификатор \"%s\" пока не поддержан" % str(op.get("t")))
	return pat


static func _range_list(from_v: Variant, to_v: Variant) -> Array:
	var a := int(float(from_v))
	var b := int(float(to_v))
	var out: Array = []
	if a <= b:
		for i in range(a, b + 1):
			out.append(i)
	else:
		for i in range(a, b - 1, -1):
			out.append(i)
	return out


static func _static_int(node: Dictionary) -> int:
	## Числовой аргумент модификатора. Эвклидовы ритмы в оригинале тоже
	## принимают паттерн; здесь берётся первое значение первого цикла.
	var pat := to_pattern(node)
	var haps := pat.query_arc(0, 1)
	if haps.is_empty():
		return 0
	return int(float((haps[0] as StrudelHap).value))
