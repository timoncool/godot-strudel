@tool
class_name StrudelKrillParser
extends RefCounted

## Разбор mini-нотации. Перенос грамматики `packages/mini/krill.pegjs`
## рекурсивным спуском, узел в узел.
##
## Возвращает дерево из словарей либо ошибку С ПОЗИЦИЕЙ В СТРОКЕ: без позиции
## чужой пользователь не отладит свой код, а это плагин для чужих людей.
##
## Узлы:
##   {t="atom",    src=String, from=int, to=int}
##   {t="element", src=узел, ops=Array, weight=float, reps=int}
##   {t="pattern", align=String, src=Array, seed=int}
## Выравнивания: "fastcat", "stack", "rand", "feet", "polymeter",
##               "polymeter_slowcat".

const SPECIAL := "[]<>{}(),|.@!*/?:~^_#-"

var _text := ""
var _pos := 0
var _seed := 0
var error := ""
var error_pos := -1


static func parse(text: String) -> Dictionary:
	## → {ok=true, ast=...} либо {ok=false, error=..., pos=...}
	var p := StrudelKrillParser.new()
	return p._parse(text)


func _parse(text: String) -> Dictionary:
	_text = text
	_pos = 0
	_seed = 0
	error = ""
	error_pos = -1

	var ast := _stack_or_choose()
	if error != "":
		return {"ok": false, "error": error, "pos": error_pos}
	_skip_ws()
	if _pos < _text.length():
		return _fail("лишний символ \"%s\"" % _text[_pos], _pos)
	if ast.is_empty():
		return _fail("пустой паттерн", 0)
	return {"ok": true, "ast": ast}


func _fail(message: String, pos: int) -> Dictionary:
	if error == "":
		error = message
		error_pos = pos
	return {"ok": false, "error": error, "pos": error_pos}


# ── символы ──────────────────────────────────────────────────────────────────

func _at_end() -> bool:
	return _pos >= _text.length()


func _peek() -> String:
	return "" if _at_end() else _text[_pos]


func _skip_ws() -> void:
	while not _at_end():
		var c := _text[_pos]
		if c == " " or c == "\t" or c == "\n" or c == "\r" or c == " ":
			_pos += 1
		else:
			break


static func _is_letter(c: String) -> bool:
	# Приём на «букву любого алфавита»: у не-букв верхний и нижний регистр
	# совпадают. Это покрывает и кириллицу, и латиницу.
	return c.to_upper() != c.to_lower()


static func _is_step_char(c: String) -> bool:
	if c == "":
		return false
	if c >= "0" and c <= "9":
		return true
	if c == "~" or c == "-" or c == "#" or c == "." or c == "^" or c == "_":
		return true
	return _is_letter(c)


# ── верхний уровень ──────────────────────────────────────────────────────────

func _stack_or_choose() -> Dictionary:
	var head := _sequence()
	if error != "":
		return {}
	_skip_ws()
	var c := _peek()
	if c == ",":
		return _tail_of(head, ",", "stack")
	if c == "|":
		return _tail_of(head, "|", "rand")
	if c == ".":
		# Точка — «стопа» только если это НЕ начало диапазона "..".
		if _pos + 1 < _text.length() and _text[_pos + 1] == ".":
			return head
		return _tail_of(head, ".", "feet")
	return head


func _tail_of(head: Dictionary, sep: String, align: String) -> Dictionary:
	var items: Array = [head]
	while true:
		_skip_ws()
		if _peek() != sep:
			break
		if sep == "." and _pos + 1 < _text.length() and _text[_pos + 1] == ".":
			break
		_pos += 1
		_skip_ws()
		var next := _sequence()
		if error != "":
			return {}
		items.append(next)
	var node := {"t": "pattern", "align": align, "src": items}
	# 🔴 Счётчик зерна общий на весь разбор и растёт также на "|" и ".",
	# не только на "?" — иначе случайное разойдётся с оригиналом.
	if align == "rand" or align == "feet":
		node["seed"] = _seed
		_seed += 1
	return node


func _sequence() -> Dictionary:
	_skip_ws()
	var steps_flag := false
	if _peek() == "^":
		# "^" помечает источник числа шагов; но одинокая "^" — обычный шаг.
		if _pos + 1 < _text.length() and not _is_step_char(_text[_pos + 1]):
			steps_flag = true
			_pos += 1
	var items: Array = []
	while true:
		var save := _pos
		var el := _slice_with_ops()
		if error != "":
			return {}
		if el.is_empty():
			_pos = save
			break
		items.append(el)
	if items.is_empty():
		return _fail("ожидал шаг", _pos)
	return {"t": "pattern", "align": "fastcat", "src": items, "steps_flag": steps_flag}


func _slice_with_ops() -> Dictionary:
	var slice := _slice()
	if error != "" or slice.is_empty():
		return {}
	var element := {"t": "element", "src": slice, "ops": [], "weight": 1.0, "reps": 1}
	while true:
		if not _slice_op(element):
			break
		if error != "":
			return {}
	return element


func _slice() -> Dictionary:
	_skip_ws()
	var c := _peek()
	if c == "[":
		return _sub_cycle()
	if c == "{":
		return _polymeter()
	if c == "<":
		return _slow_sequence()
	return _step()


func _step() -> Dictionary:
	_skip_ws()
	var start := _pos
	var chars := ""
	while _is_step_char(_peek()):
		chars += _text[_pos]
		_pos += 1
	if chars == "":
		return {}
	# Одинокие "." и "_" — это операторы, а не шаги.
	if chars == "." or chars == "_":
		_pos = start
		return {}
	var stop := _pos
	_skip_ws()
	return {"t": "atom", "src": chars, "from": start, "to": stop}


func _sub_cycle() -> Dictionary:
	_pos += 1  # "["
	_skip_ws()
	var inner := _stack_or_choose()
	if error != "":
		return {}
	_skip_ws()
	if _peek() != "]":
		return _fail("не закрыта скобка \"[\"", _pos)
	_pos += 1
	_skip_ws()
	return inner


func _polymeter() -> Dictionary:
	var open_at := _pos
	_pos += 1  # "{"
	var node := _polymeter_stack()
	if error != "":
		return {}
	_skip_ws()
	if _peek() != "}":
		return _fail("не закрыта скобка \"{\"", open_at)
	_pos += 1
	node["align"] = "polymeter"
	if _peek() == "%":
		_pos += 1
		var amount := _slice()
		if error != "":
			return {}
		if amount.is_empty():
			return _fail("после \"%\" нужно число шагов", _pos)
		node["steps_per_cycle"] = amount
	_skip_ws()
	return node


func _slow_sequence() -> Dictionary:
	var open_at := _pos
	_pos += 1  # "<"
	var node := _polymeter_stack()
	if error != "":
		return {}
	_skip_ws()
	if _peek() != ">":
		return _fail("не закрыта скобка \"<\"", open_at)
	_pos += 1
	_skip_ws()
	node["align"] = "polymeter_slowcat"
	return node


func _polymeter_stack() -> Dictionary:
	_skip_ws()
	var items: Array = [_sequence()]
	if error != "":
		return {}
	while true:
		_skip_ws()
		if _peek() != ",":
			break
		_pos += 1
		_skip_ws()
		items.append(_sequence())
		if error != "":
			return {}
	return {"t": "pattern", "align": "polymeter", "src": items}


# ── модификаторы шага ────────────────────────────────────────────────────────

func _slice_op(element: Dictionary) -> bool:
	# Перед знаком веса грамматика допускает пробел (`op_weight = ws ("@"/"_")`),
	# и на этом стоит запись "bd _ _ sd" — три доли под одну вещь.
	# У остальных модификаторов пробела быть не должно.
	var save := _pos
	_skip_ws()
	if _peek() == "@" or _peek() == "_":
		_pos += 1
		var w := _opt_number()
		element["weight"] = float(element["weight"]) + (w if w != null else 2.0) - 1.0
		return true
	_pos = save

	var c := _peek()
	match c:
		"@", "_":
			_pos += 1
			var amount := _opt_number()
			# Формула оригинала: вес = былой + (число или 2) - 1.
			# Поэтому "x@3" даёт 3, а одинокое "_" прибавляет единицу.
			element["weight"] = float(element["weight"]) + (amount if amount != null else 2.0) - 1.0
			return true
		"!":
			_pos += 1
			var amount := _opt_number()
			var reps: int = int(float(element["reps"]) + (amount if amount != null else 2.0) - 1.0)
			element["reps"] = reps
			# Повтор ВЫТЕСНЯЕТ прежний: "x!!" — это три копии, а не две по две.
			var kept: Array = []
			for op in element["ops"]:
				if op["t"] != "replicate":
					kept.append(op)
			kept.append({"t": "replicate", "amount": reps})
			element["ops"] = kept
			element["weight"] = float(reps)
			return true
		"(":
			return _op_bjorklund(element)
		"/":
			_pos += 1
			var amount_node := _slice()
			if amount_node.is_empty():
				_fail("после \"/\" нужно число", _pos)
				return false
			element["ops"].append({"t": "stretch", "type": "slow", "amount": amount_node})
			return true
		"*":
			_pos += 1
			var amount_node := _slice()
			if amount_node.is_empty():
				_fail("после \"*\" нужно число", _pos)
				return false
			element["ops"].append({"t": "stretch", "type": "fast", "amount": amount_node})
			return true
		"?":
			_pos += 1
			var amount := _opt_number()
			element["ops"].append({"t": "degradeBy", "amount": amount, "seed": _seed})
			_seed += 1
			return true
		":":
			_pos += 1
			var tail_node := _slice()
			if tail_node.is_empty():
				_fail("после \":\" нужен индекс", _pos)
				return false
			element["ops"].append({"t": "tail", "element": tail_node})
			return true
		".":
			if _pos + 1 < _text.length() and _text[_pos + 1] == ".":
				_pos += 2
				var to_node := _slice()
				if to_node.is_empty():
					_fail("после \"..\" нужен конец диапазона", _pos)
					return false
				element["ops"].append({"t": "range", "element": to_node})
				return true
			return false
	return false


func _op_bjorklund(element: Dictionary) -> bool:
	var open_at := _pos
	_pos += 1  # "("
	_skip_ws()
	var pulse := _slice_with_ops()
	if error != "" or pulse.is_empty():
		_fail("в скобках эвклидова ритма нужно число ударов", open_at)
		return false
	_skip_ws()
	if _peek() != ",":
		_fail("эвклидов ритм пишется как (удары,шаги) или (удары,шаги,сдвиг)", open_at)
		return false
	_pos += 1
	_skip_ws()
	var step_count := _slice_with_ops()
	if error != "" or step_count.is_empty():
		_fail("в скобках эвклидова ритма нужно число шагов", open_at)
		return false
	_skip_ws()
	var rotation: Variant = null
	if _peek() == ",":
		_pos += 1
		_skip_ws()
		rotation = _slice_with_ops()
		if error != "" or (rotation as Dictionary).is_empty():
			_fail("после второй запятой нужен сдвиг", open_at)
			return false
	_skip_ws()
	if _peek() != ")":
		_fail("не закрыта скобка эвклидова ритма", open_at)
		return false
	_pos += 1
	_skip_ws()
	element["ops"].append({
		"t": "bjorklund", "pulse": pulse, "step": step_count, "rotation": rotation
	})
	return true


func _opt_number() -> Variant:
	## Число сразу после модификатора; null, если его нет.
	var start := _pos
	var text := ""
	if _peek() == "-":
		text += "-"
		_pos += 1
	while not _at_end() and ((_peek() >= "0" and _peek() <= "9") or _peek() == "."):
		text += _text[_pos]
		_pos += 1
	if text == "" or text == "-" or text == ".":
		_pos = start
		return null
	return text.to_float()
