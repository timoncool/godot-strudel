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


static func is_control(name: String) -> bool:
	return StrudelControlsTable.is_control(name)
