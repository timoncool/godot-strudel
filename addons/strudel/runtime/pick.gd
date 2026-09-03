@tool
class_name StrudelPick
extends RefCounted

## Выбор паттерна по номеру или имени — семейство `pick` (`core/pick.mjs`).
##
## Один паттерн работает указателем: его значения выбирают, ЧТО играть, из
## списка или таблицы. Отличаются варианты только тем, как выбранное
## сшивается обратно (`innerJoin`, `outerJoin`, `squeezeJoin`, `resetJoin`,
## `restartJoin`) и что делать с номером за пределами списка:
##
## - `pick` — номер ПРИЖИМАЕТСЯ к краям списка;
## - `pickmod` — номер идёт по кругу.
##
## 🔴 Остаток берётся ЯЗЫКОВОЙ, а не математический: в JS `-1 % 3` это −1, а
## не 2, и такой номер не попадает в список вовсе — событие пропадает. Мера
## та же и здесь, иначе отрицательные номера звучали бы иначе, чем в Булке.


static func _lookup_size(lookup: Variant) -> int:
	if lookup is Array:
		return (lookup as Array).size()
	if lookup is Dictionary:
		return (lookup as Dictionary).size()
	return 0


static func _js_round(x: float) -> int:
	## Округление как в JS: половина всегда вверх, а не «от нуля».
	return int(floor(x + 0.5))


static func _pick(lookup: Variant, pat: StrudelPattern, modulo: bool) -> StrudelPattern:
	var size := _lookup_size(lookup)
	if size == 0:
		return StrudelPattern.silence()

	var list: Array = []
	var map: Dictionary = {}
	if lookup is Array:
		for x in lookup:
			list.append(StrudelPattern.reify(x))
	else:
		for k in (lookup as Dictionary):
			map[String(k)] = StrudelPattern.reify((lookup as Dictionary)[k])

	var is_array := lookup is Array
	return pat.fmap(func(i) -> StrudelPattern:
		if not is_array:
			return map.get(StrudelUtil.text(i), StrudelPattern.silence())
		var r := _js_round(StrudelPattern._num(i))
		var index := (r % size) if modulo else clampi(r, 0, size - 1)
		if index < 0 or index >= size:
			return StrudelPattern.silence()
		return list[index]
	)


static func pick(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, false).inner_join()


static func pickmod(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, true).inner_join()


static func pick_out(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, false).outer_join()


static func pickmod_out(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, true).outer_join()


static func pick_restart(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, false).restart_join()


static func pickmod_restart(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, true).restart_join()


static func pick_reset(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, false).reset_join()


static func pickmod_reset(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	return _pick(lookup, pat, true).reset_join()


static func inhabit(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	## Он же `pickSqueeze`: выбранное ВЖИМАЕТСЯ в длину события-указателя.
	return _pick(lookup, pat, false).squeeze_join()


static func inhabitmod(lookup: Variant, pat: StrudelPattern) -> StrudelPattern:
	## Он же `pickmodSqueeze`.
	return _pick(lookup, pat, true).squeeze_join()


static func pick_f(pat: StrudelPattern, pick_pattern: Variant, lookup: Variant) -> StrudelPattern:
	## Выбор ДЕЙСТВИЯ по номеру: `.pickF("<0 1>", [rev, fast(2)])`.
	return pat.apply(pick(lookup, StrudelPattern.reify(pick_pattern)))


static func pickmod_f(pat: StrudelPattern, pick_pattern: Variant, lookup: Variant) -> StrudelPattern:
	return pat.apply(pickmod(lookup, StrudelPattern.reify(pick_pattern)))
