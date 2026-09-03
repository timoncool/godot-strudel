@tool
class_name StrudelControls
extends RefCounted

## Управляющие функции: gain, lpf, room, note, s… Перенос `createParam`
## из `packages/core/controls.mjs`.
##
## Составные параметры — главное, что здесь легко потерять: `s("bd:3:0.7")`
## приходит списком ["bd", 3, 0.7] и раскладывается по трём именам
## ["s", "n", "gain"]. Без этого `:` в mini-нотации молча пропадает.


static func with_value(names: Array, xs: Variant) -> Dictionary:
	## Превращает значение события в словарь параметров.
	var bag: Dictionary = {}
	var value: Variant = xs

	# Безымянный параметр (.value) забирает своё имя, остальное сохраняется.
	if xs is Dictionary and (xs as Dictionary).has("value"):
		bag = (xs as Dictionary).duplicate()
		value = bag["value"]
		bag.erase("value")

	if names.size() > 1 and value is Array:
		var list: Array = value
		for i in list.size():
			if i < names.size():
				bag[String(names[i])] = list[i]
		return bag

	bag[String(names[0])] = value
	return bag


static func make(name: String, value: Variant) -> StrudelPattern:
	## Верхнеуровневый вызов: `s("bd sd")`, `note("c3 e3")`.
	var names := _names_for(name)
	return StrudelPattern.reify(value).with_value(func(v):
		return with_value(names, v)
	)


static func apply(pat: StrudelPattern, name: String, value: Variant) -> StrudelPattern:
	## Вызов на паттерне: `.gain(0.5)`, `.s("piano")`.
	var names := _names_for(name)
	if value == null:
		return pat.fmap(func(v): return with_value(names, v))
	return pat.set_([StrudelPattern.reify(value).with_value(func(v):
		return with_value(names, v)
	)])


static func _names_for(name: String) -> Array:
	var main := StrudelControlsTable.main_name(name)
	if main == "":
		# Неизвестное имя всё равно кладём как параметр: Strudel так же
		# пропускает вперёд то, чего не знает ядро, — этим живут расширения.
		return [name]
	return (StrudelControlsTable.CONTROLS[main] as Dictionary)["names"]


static func main_name(name: String) -> String:
	## Настоящее имя параметра по имени или псевдониму. Незнакомое имя
	## возвращается КАК ЕСТЬ: расширения Strudel живут ровно этим.
	var main := StrudelControlsTable.main_name(name)
	return main if main != "" else name


static func adsr(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	## Вся огибающая одним доводом: `.adsr(".1:.1:.5:.2")`.
	##
	## 🔴 Довод приходит ПАТТЕРНОМ, а не готовым списком: `.1:.1:.5:.2` — это
	## mini-нотация, и список появляется только при выборке события. Пока
	## список брался напрямую, весь паттерн уезжал в поле `attack`.
	return pat._patternify([value], func(vals: Array) -> StrudelPattern:
		var list: Array = vals[0] if vals[0] is Array else [vals[0]]
		var names := ["attack", "decay", "sustain", "release"]
		var fields := {}
		for i in mini(list.size(), names.size()):
			fields[names[i]] = list[i]
		return _set_fields(pat, fields)
	)


static func ad(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	## Атака и спад. Одно число значит «спад такой же, как атака».
	return pat._patternify([value], func(vals: Array) -> StrudelPattern:
		return _ad_of(pat, vals[0])
	)


static func _ad_of(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	var list: Array = value if value is Array else [value]
	if list.is_empty():
		return pat
	var attack: Variant = list[0]
	var decay: Variant = list[1] if list.size() > 1 else attack
	# 🔴 Именно `.attack(...).decay(...)` по очереди, а не общий `set`:
	# от порядка ключей зависит, какой параметр подхватит модулятор
	# без явного `control`.
	return apply(apply(pat, "attack", attack), "decay", decay)


static func ds(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	## Спад и уровень удержания. Одно число значит «удержание в нуле».
	return pat._patternify([value], func(vals: Array) -> StrudelPattern:
		return _ds_of(pat, vals[0])
	)


static func _ds_of(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	var list: Array = value if value is Array else [value]
	if list.is_empty():
		return pat
	return _set_fields(pat, {
		"decay": list[0],
		"sustain": list[1] if list.size() > 1 else 0,
	})


static func ar(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	## Атака и отпускание. Одно число значит «отпускание такое же».
	return pat._patternify([value], func(vals: Array) -> StrudelPattern:
		return _ar_of(pat, vals[0])
	)


static func _ar_of(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	var list: Array = value if value is Array else [value]
	if list.is_empty():
		return pat
	return _set_fields(pat, {
		"attack": list[0],
		"release": list[1] if list.size() > 1 else list[0],
	})


static func control(pat: StrudelPattern, args: Variant) -> StrudelPattern:
	## Пара MIDI-контроллера: `[номер, значение]`.
	if not args is Array or (args as Array).size() < 2:
		push_warning("Strudel: control ждёт пару [номер, значение]")
		return pat
	return apply(apply(pat, "ccn", args[0]), "ccv", args[1])


static func as_(pat: StrudelPattern, mapping: Variant) -> StrudelPattern:
	## Раздать значения события по именам параметров:
	## `"c:.5 a:1".as("note:clip")` — первое в note, второе в clip.
	##
	## 🔴 Имена приходят ПАТТЕРНОМ: `note:clip` — та же mini-нотация.
	return pat._patternify([mapping], func(vals: Array) -> StrudelPattern:
		return _as_of(pat, vals[0])
	)


static func _as_of(pat: StrudelPattern, mapping: Variant) -> StrudelPattern:
	var names: Array = mapping if mapping is Array else [mapping]
	return pat.fmap(func(v) -> Dictionary:
		var list: Array = v if v is Array else [v]
		var out := {}
		for i in names.size():
			if i < list.size() and list[i] != null:
				out[main_name(StrudelUtil.text(names[i]))] = list[i]
		return out
	)


static func scrub(pat: StrudelPattern, begin_pat: Variant) -> StrudelPattern:
	## Перемотка сэмпла, как ленты: значение — место в файле, второе
	## число пары — скорость.
	return StrudelPattern.reify(begin_pat).outer_bind(func(v) -> StrudelPattern:
		var list: Array = v if v is Array else [v]
		var begin: Variant = list[0] if not list.is_empty() else 0
		var speed_mul: Variant = list[1] if list.size() > 1 else 1
		return apply(pat, "begin", begin) \
			.mul([make("speed", speed_mul)]) \
			.ctrl("clip", 1)
	)


static func _set_fields(pat: StrudelPattern, fields: Dictionary) -> StrudelPattern:
	var out := pat
	for k in fields:
		out = apply(out, String(k), fields[k])
	return out


static func is_control(name: String) -> bool:
	return StrudelControlsTable.is_control(name)
