@tool
class_name StrudelRuntime
extends RefCounted

## Исполнение кода Strudel: имена, цепочки через точку, стрелочные функции.
##
## Цель — чтобы код, написанный в Strudel или Булке, вставлялся сюда БЕЗ
## ПРАВОК. Поэтому имена функций сохраняют исходный вид (`degradeBy`, а не
## `degrade_by`): переименование сломало бы ровно то, ради чего всё делается.
## Godot-стиль (`snake_case`) живёт в программном API — на самом классе
## StrudelPattern.

## Циклов в секунду. `setcpm(76/4)` кладёт сюда 76/4/60.
var cps := 0.5
## Имена, объявленные через const.
var scope: Dictionary = {}
## Ошибка исполнения, если была.
var error := ""


static func run(source: String) -> Dictionary:
	## → {ok=true, pattern=StrudelPattern, cps=float} либо {ok=false, error=…}
	var rt := StrudelRuntime.new()
	return rt.execute(source)


func execute(source: String) -> Dictionary:
	var parsed := StrudelCodeParser.parse(source)
	if not parsed.get("ok", false):
		return {
			"ok": false,
			"error": "строка %d: %s" % [parsed.get("line", 0), parsed.get("error", "?")],
		}

	var outputs: Array = []
	var last: Variant = null
	var had_label := false

	for st in parsed["program"]:
		if error != "":
			return {"ok": false, "error": error}
		match String(st["t"]):
			"const":
				scope[String(st["name"])] = _eval(st["value"])
			"expr":
				var value: Variant = _eval(st["value"])
				var label := String(st.get("label", ""))
				if label != "":
					had_label = true
					if value is StrudelPattern:
						outputs.append(value)
				else:
					last = value

	if error != "":
		return {"ok": false, "error": error}

	if not had_label and last is StrudelPattern:
		outputs.append(last)
	elif had_label and outputs.is_empty() and last is StrudelPattern:
		outputs.append(last)

	if outputs.is_empty():
		return {"ok": false, "error": "код не дал ни одного паттерна"}

	var pattern: StrudelPattern = outputs[0] if outputs.size() == 1 else StrudelPattern.stack(outputs)
	return {"ok": true, "pattern": pattern, "cps": cps}


func _fail(message: String) -> Variant:
	if error == "":
		error = message
	return null


# ═══════════════════════════════════════════════════════════════════════════
# Вычисление узлов
# ═══════════════════════════════════════════════════════════════════════════

func _eval(node: Variant, locals: Dictionary = {}) -> Variant:
	if error != "":
		return null
	if not node is Dictionary:
		return node
	var n: Dictionary = node
	match String(n.get("t", "")):
		"num":
			return n["v"]
		"str":
			# Строка в коде Strudel — это mini-нотация.
			# Ошибку разбора НЕ проглатываем: чужой пользователь должен
			# увидеть, что именно у него не так и в каком месте строки.
			var attempt := StrudelMini.try_mini(String(n["v"]))
			if not attempt.get("ok", false):
				return _fail("в строке \"%s\": %s (позиция %d)"
					% [String(n["v"]), attempt.get("error", "?"), attempt.get("pos", -1)])
			return attempt["pattern"]
		"bool", "null":
			return n["v"]
		"id":
			return _lookup(String(n["name"]), locals)
		"array":
			var items: Array = []
			for it in n["items"]:
				items.append(_eval(it, locals))
			return items
		"object":
			var obj: Dictionary = {}
			for pair in n["pairs"]:
				obj[String(pair[0])] = _eval(pair[1], locals)
			return obj
		"arrow":
			var params: Array = n["params"]
			var body: Variant = n["body"]
			var captured := locals.duplicate()
			return func(args: Array) -> Variant:
				var inner := captured.duplicate()
				for i in params.size():
					inner[String(params[i])] = args[i] if i < args.size() else null
				return _eval(body, inner)
		"unary":
			return _unary(String(n["op"]), _eval(n["arg"], locals))
		"bin":
			return _binary(String(n["op"]), _eval(n["l"], locals), _eval(n["r"], locals))
		"member":
			return _member(_eval(n["obj"], locals), String(n["name"]))
		"index":
			var obj: Variant = _eval(n["obj"], locals)
			var key: Variant = _eval(n["key"], locals)
			if obj is Array:
				return (obj as Array)[int(_as_float(key))]
			if obj is Dictionary:
				return (obj as Dictionary).get(_as_text(key))
			return _fail("нельзя взять элемент у этого значения")
		"call":
			return _call(n, locals)
	return _fail("непонятный узел \"%s\"" % str(n.get("t")))


func _lookup(name: String, locals: Dictionary) -> Variant:
	if locals.has(name):
		return locals[name]
	if scope.has(name):
		return scope[name]
	var built := StrudelStdlib.global_value(name)
	if built != null:
		return built
	# Голое имя функции-преобразования: `jux(rev)`, `every(3, press)`.
	if StrudelStdlib.is_method_name(name):
		return func(args: Array) -> Variant:
			if args.size() != 1 or not (args[0] is StrudelPattern):
				return _fail("\"%s\" ждёт паттерн" % name)
			return _method(args[0], name, [])
	return _fail("не знаю имени \"%s\"" % name)


func _unary(op: String, value: Variant) -> Variant:
	match op:
		"-":
			if value is StrudelPattern:
				return (value as StrudelPattern).fmap(func(v): return -StrudelPattern._num(v))
			return -_as_float(value)
		"+":
			return _as_float(value)
		"!":
			return not StrudelPattern.truthy(value)
	return _fail("непонятная операция \"%s\"" % op)


func _binary(op: String, l: Variant, r: Variant) -> Variant:
	# Паттерн в арифметике — это слияние паттернов, а не число.
	if l is StrudelPattern or r is StrudelPattern:
		var lp := StrudelPattern.reify(l)
		match op:
			"+": return lp.add([r])
			"-": return lp.sub([r])
			"*": return lp.mul([r])
			"/": return lp.div([r])
			"%": return lp.mod_([r])
	match op:
		"+":
			if (l is String or l is StringName) or (r is String or r is StringName):
				return _as_text(l) + _as_text(r)
			return _as_float(l) + _as_float(r)
		"-": return _as_float(l) - _as_float(r)
		"*": return _as_float(l) * _as_float(r)
		"/": return _as_float(l) / _as_float(r) if _as_float(r) != 0.0 else 0.0
		"%": return StrudelUtil.mod_f(_as_float(l), _as_float(r))
		"<": return _as_float(l) < _as_float(r)
		">": return _as_float(l) > _as_float(r)
		"<=": return _as_float(l) <= _as_float(r)
		">=": return _as_float(l) >= _as_float(r)
		"==", "===": return l == r
		"!=", "!==": return l != r
		"&&": return r if StrudelPattern.truthy(l) else l
		"||": return l if StrudelPattern.truthy(l) else r
		"??": return r if l == null else l
	return _fail("непонятная операция \"%s\"" % op)


# ═══════════════════════════════════════════════════════════════════════════
# Доступ через точку и вызовы
# ═══════════════════════════════════════════════════════════════════════════

func _member(target: Variant, name: String) -> Variant:
	# Math.pow и подобное
	if target is Dictionary and (target as Dictionary).get("__ns", "") == "Math":
		return {"__math": name}
	# Явное выравнивание: n("0").add.out("…")
	if target is Dictionary and (target as Dictionary).has("__op"):
		var d: Dictionary = target
		if StrudelStdlib.ALIGNMENTS.has(name):
			return {"__op": d["__op"], "pat": d["pat"], "how": name}
		return _fail("у операции нет варианта \"%s\"" % name)
	if target is StrudelPattern:
		if StrudelStdlib.OPS.has(name):
			return {"__op": name, "pat": target, "how": "in"}
		# Метод без вызова — превращаем в отложенный вызов через _member+call.
		return {"__method": name, "pat": target}
	if target is Dictionary:
		return (target as Dictionary).get(name)
	return _fail("нельзя обратиться к \"%s\"" % name)


func _call(node: Dictionary, locals: Dictionary) -> Variant:
	var callee: Dictionary = node["callee"]
	var args: Array = []
	for a in node["args"]:
		args.append(_eval(a, locals))
	if error != "":
		return null

	# Вызов метода: obj.name(...)
	if String(callee.get("t", "")) == "member":
		var target: Variant = _eval(callee["obj"], locals)
		if error != "":
			return null
		var name := String(callee["name"])

		if target is Dictionary and (target as Dictionary).get("__ns", "") == "Math":
			return StrudelStdlib.math_call(name, args)

		# n("0").add.out("…") — выравнивание уже выбрано
		if target is Dictionary and (target as Dictionary).has("__op"):
			var d: Dictionary = target
			if StrudelStdlib.ALIGNMENTS.has(name):
				return _op_call(d["pat"], String(d["__op"]), name, args)
			return _fail("у операции нет варианта \"%s\"" % name)

		if target is StrudelPattern:
			if StrudelStdlib.OPS.has(name):
				return _op_call(target, name, "in", args)
			return _method(target, name, args)

		if target is Dictionary:
			var f: Variant = (target as Dictionary).get(name)
			if f is Callable:
				return (f as Callable).call(args)
		return _fail("не знаю метода \"%s\"" % name)

	# Обычный вызов по имени
	if String(callee.get("t", "")) == "id":
		var name2 := String(callee["name"])
		if locals.has(name2) or scope.has(name2):
			var f2: Variant = locals.get(name2, scope.get(name2))
			if f2 is Callable:
				return (f2 as Callable).call(args)
			if f2 is StrudelPattern and StrudelStdlib.is_method_name(name2):
				return _method(f2, name2, args)
		return _global_call(name2, args)

	# Вызов выражения (например результата стрелки)
	var value: Variant = _eval(callee, locals)
	if value is Callable:
		return (value as Callable).call(args)
	return _fail("это не функция")


func _op_call(pat: StrudelPattern, op: String, how: String, args: Array) -> Variant:
	return pat._compose(StrudelStdlib.OPS[op], how, args)


func _global_call(name: String, args: Array) -> Variant:
	# Темп задаётся кодом и запоминается в исполнителе.
	if name == "setcpm":
		cps = _as_float(args[0]) / 60.0 if not args.is_empty() else cps
		return null
	if name == "setcps":
		cps = _as_float(args[0]) if not args.is_empty() else cps
		return null
	var result: Variant = StrudelStdlib.global_call(self, name, args)
	if result is Dictionary and (result as Dictionary).get("__unknown", false):
		return _fail("не знаю функции \"%s\"" % name)
	return result


func _method(pat: StrudelPattern, name: String, args: Array) -> Variant:
	var result: Variant = StrudelStdlib.method_call(self, pat, name, args)
	if result is Dictionary and (result as Dictionary).get("__unknown", false):
		return _fail("не знаю метода \".%s\"" % name)
	return result


# ═══════════════════════════════════════════════════════════════════════════
# Приведения
# ═══════════════════════════════════════════════════════════════════════════

func _as_float(v: Variant) -> float:
	if v is float:
		return v
	if v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String or v is StringName:
		return String(v).to_float()
	if v is StrudelPattern:
		var haps: Array = (v as StrudelPattern).query_arc(0, 1)
		if not haps.is_empty():
			return StrudelPattern._num((haps[0] as StrudelHap).value)
	return 0.0


func _as_text(v: Variant) -> String:
	if v is String or v is StringName:
		return String(v)
	if v is float:
		return str(v)
	return str(v)
