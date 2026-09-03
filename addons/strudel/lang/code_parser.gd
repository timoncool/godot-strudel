@tool
class_name StrudelCodeParser
extends RefCounted

## Разбор кода Strudel — того самого, что пишут в браузере.
##
## Strudel — это JavaScript, но код паттернов пользуется узкой его частью:
## вызовы, цепочки через точку, стрелочные функции, литералы, арифметика,
## `const`, метки `$:`. Именно эта часть и разбирается — полноценного движка
## JavaScript здесь нет и не нужно.
##
## Что поддержано, а что нет — перечислено в docs/SYNTAX.md. Ошибка всегда
## несёт позицию: строку и столбец.
##
## Узлы дерева:
##   {t="num"|"str"|"bool"|"null", v}
##   {t="id", name}
##   {t="member", obj, name}
##   {t="index", obj, key}
##   {t="call", callee, args}
##   {t="arrow", params, body}
##   {t="array", items}
##   {t="object", pairs}
##   {t="bin", op, l, r}   {t="unary", op, arg}
## Инструкции:
##   {t="const", name, value}
##   {t="expr", value, label}

var _src := ""
var _toks: Array = []
var _i := 0
var error := ""
var error_line := 0
var error_col := 0


static func parse(source: String) -> Dictionary:
	## → {ok=true, program=[инструкции]} либо {ok=false, error, line, col}
	var p := StrudelCodeParser.new()
	return p._run(source)


func _run(source: String) -> Dictionary:
	_src = source
	_toks = _tokenize(source)
	if error != "":
		return _err()
	_i = 0
	var program: Array = []
	while not _done():
		_skip_semis()
		if _done():
			break
		var st := _statement()
		if error != "":
			return _err()
		if not st.is_empty():
			program.append(st)
	if error != "":
		return _err()
	return {"ok": true, "program": program}


func _err() -> Dictionary:
	return {"ok": false, "error": error, "line": error_line, "col": error_col}


func _fail(message: String, tok: Dictionary = {}) -> void:
	if error != "":
		return
	error = message
	error_line = int(tok.get("line", 0)) if not tok.is_empty() else _cur_line()
	error_col = int(tok.get("col", 0)) if not tok.is_empty() else 0


func _cur_line() -> int:
	if _i < _toks.size():
		return int(_toks[_i].get("line", 0))
	if not _toks.is_empty():
		return int(_toks[_toks.size() - 1].get("line", 0))
	return 1


# ═══════════════════════════════════════════════════════════════════════════
# Лексика
# ═══════════════════════════════════════════════════════════════════════════

const _PUNCT := [
	"=>", "===", "!==", "==", "!=", "<=", ">=", "&&", "||", "??",
	"(", ")", "[", "]", "{", "}", ",", ".", ":", ";",
	"+", "-", "*", "/", "%", "<", ">", "=", "!", "?",
]


func _tokenize(src: String) -> Array:
	var toks: Array = []
	var i := 0
	var line := 1
	var line_start := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "\n":
			line += 1
			i += 1
			line_start = i
			continue
		if c == " " or c == "\t" or c == "\r":
			i += 1
			continue
		# комментарии
		if c == "/" and i + 1 < n and src[i + 1] == "/":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "/" and i + 1 < n and src[i + 1] == "*":
			i += 2
			while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
				if src[i] == "\n":
					line += 1
				i += 1
			i += 2
			continue
		var col := i - line_start
		# строки
		if c == "\"" or c == "'" or c == "`":
			var quote := c
			var j := i + 1
			var text := ""
			while j < n and src[j] != quote:
				if src[j] == "\\" and j + 1 < n:
					var esc := src[j + 1]
					match esc:
						"n": text += "\n"
						"t": text += "\t"
						"r": text += "\r"
						"\\": text += "\\"
						"'": text += "'"
						"\"": text += "\""
						"`": text += "`"
						_: text += esc
					j += 2
					continue
				if src[j] == "\n":
					line += 1
				text += src[j]
				j += 1
			if j >= n:
				_fail("не закрыта кавычка", {"line": line, "col": col})
				return toks
			if quote == "`" and text.contains("${"):
				_fail("шаблонные строки со вставками ${…} не поддержаны", {"line": line, "col": col})
				return toks
			toks.append({"t": "str", "v": text, "line": line, "col": col})
			i = j + 1
			continue
		# числа
		if _is_digit(c) or (c == "." and i + 1 < n and _is_digit(src[i + 1])):
			var j2 := i
			var num := ""
			while j2 < n and (_is_digit(src[j2]) or src[j2] == "."):
				num += src[j2]
				j2 += 1
			if j2 < n and (src[j2] == "e" or src[j2] == "E"):
				num += src[j2]
				j2 += 1
				if j2 < n and (src[j2] == "+" or src[j2] == "-"):
					num += src[j2]
					j2 += 1
				while j2 < n and _is_digit(src[j2]):
					num += src[j2]
					j2 += 1
			toks.append({"t": "num", "v": num.to_float(), "raw": num, "line": line, "col": col})
			i = j2
			continue
		# имена
		if _is_ident_start(c):
			var j3 := i
			var name := ""
			while j3 < n and _is_ident_char(src[j3]):
				name += src[j3]
				j3 += 1
			toks.append({"t": "id", "v": name, "line": line, "col": col})
			i = j3
			continue
		# знаки
		var matched := ""
		for p in _PUNCT:
			if src.substr(i, p.length()) == p:
				matched = p
				break
		if matched == "":
			_fail("непонятный символ \"%s\"" % c, {"line": line, "col": col})
			return toks
		toks.append({"t": "p", "v": matched, "line": line, "col": col})
		i += matched.length()
	return toks


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_ident_start(c: String) -> bool:
	return c == "_" or c == "$" or c.to_upper() != c.to_lower()


static func _is_ident_char(c: String) -> bool:
	return _is_ident_start(c) or _is_digit(c)


# ═══════════════════════════════════════════════════════════════════════════
# Разбор
# ═══════════════════════════════════════════════════════════════════════════

func _done() -> bool:
	return _i >= _toks.size()


func _peek(offset: int = 0) -> Dictionary:
	var k := _i + offset
	return _toks[k] if k < _toks.size() else {}


func _is_p(value: String, offset: int = 0) -> bool:
	var t := _peek(offset)
	return t.get("t", "") == "p" and t.get("v", "") == value


func _is_id(value: String, offset: int = 0) -> bool:
	var t := _peek(offset)
	return t.get("t", "") == "id" and t.get("v", "") == value


func _take() -> Dictionary:
	var t := _peek()
	_i += 1
	return t


func _expect(value: String) -> bool:
	if _is_p(value):
		_i += 1
		return true
	_fail("ожидал \"%s\"" % value, _peek())
	return false


func _skip_semis() -> void:
	while _is_p(";"):
		_i += 1


func _statement() -> Dictionary:
	# const / let / var
	if _is_id("const") or _is_id("let") or _is_id("var"):
		_i += 1
		var name_tok := _take()
		if name_tok.get("t", "") != "id":
			_fail("после const ожидал имя", name_tok)
			return {}
		if not _expect("="):
			return {}
		var value := _expression()
		if error != "":
			return {}
		_skip_semis()
		return {"t": "const", "name": String(name_tok["v"]), "value": value}

	# метка вывода: "$: …" либо "имя: …"
	var label := ""
	if _is_p("$") and _is_p(":", 1):
		label = "$"
		_i += 2
	elif _peek().get("t", "") == "id" and _is_p(":", 1) and not _is_p("(", 2):
		label = String(_peek()["v"])
		_i += 2

	var expr := _expression()
	if error != "":
		return {}
	_skip_semis()
	return {"t": "expr", "value": expr, "label": label}


func _expression() -> Dictionary:
	return _arrow_or_binary()


func _arrow_or_binary() -> Dictionary:
	# Стрелочная функция: "x => …" или "(a, b) => …"
	var save := _i
	var params := _try_arrow_params()
	if params != null:
		var body := _expression()
		if error != "":
			return {}
		return {"t": "arrow", "params": params, "body": body}
	_i = save
	return _binary(0)


func _try_arrow_params() -> Variant:
	if _peek().get("t", "") == "id" and _is_p("=>", 1):
		var one := String(_take()["v"])
		_i += 1
		return [one]
	if _is_p("("):
		var save := _i
		_i += 1
		var names: Array = []
		if _is_p(")"):
			_i += 1
		else:
			while true:
				var t := _peek()
				if t.get("t", "") != "id":
					_i = save
					return null
				names.append(String(t["v"]))
				_i += 1
				if _is_p(","):
					_i += 1
					continue
				break
			if not _is_p(")"):
				_i = save
				return null
			_i += 1
		if _is_p("=>"):
			_i += 1
			return names
		_i = save
		return null
	return null


const _LEVELS := [
	["||", "??"],
	["&&"],
	["==", "!=", "===", "!=="],
	["<", ">", "<=", ">="],
	["+", "-"],
	["*", "/", "%"],
]


func _binary(level: int) -> Dictionary:
	if level >= _LEVELS.size():
		return _unary()
	var left := _binary(level + 1)
	if error != "":
		return {}
	while true:
		var t := _peek()
		if t.get("t", "") != "p":
			break
		var op := String(t.get("v", ""))
		if not (_LEVELS[level] as Array).has(op):
			break
		_i += 1
		var right := _binary(level + 1)
		if error != "":
			return {}
		left = {"t": "bin", "op": op, "l": left, "r": right}
	return left


func _unary() -> Dictionary:
	if _is_p("-") or _is_p("!") or _is_p("+"):
		var op := String(_take()["v"])
		var arg := _unary()
		if error != "":
			return {}
		return {"t": "unary", "op": op, "arg": arg}
	return _postfix()


func _postfix() -> Dictionary:
	var node := _primary()
	if error != "":
		return {}
	while true:
		if _is_p("."):
			_i += 1
			var name_tok := _take()
			if name_tok.get("t", "") != "id":
				_fail("после точки ожидал имя", name_tok)
				return {}
			node = {"t": "member", "obj": node, "name": String(name_tok["v"])}
			continue
		if _is_p("("):
			_i += 1
			var args: Array = []
			if _is_p(")"):
				_i += 1
			else:
				while true:
					args.append(_expression())
					if error != "":
						return {}
					if _is_p(","):
						_i += 1
						continue
					break
				if not _expect(")"):
					return {}
			node = {"t": "call", "callee": node, "args": args}
			continue
		if _is_p("["):
			_i += 1
			var key := _expression()
			if error != "":
				return {}
			if not _expect("]"):
				return {}
			node = {"t": "index", "obj": node, "key": key}
			continue
		break
	return node


func _primary() -> Dictionary:
	var t := _peek()
	if t.is_empty():
		_fail("код оборвался")
		return {}
	match String(t.get("t", "")):
		"num":
			_i += 1
			return {"t": "num", "v": t["v"]}
		"str":
			_i += 1
			return {"t": "str", "v": t["v"]}
		"id":
			var name := String(t["v"])
			_i += 1
			if name == "true":
				return {"t": "bool", "v": true}
			if name == "false":
				return {"t": "bool", "v": false}
			if name == "null" or name == "undefined":
				return {"t": "null", "v": null}
			return {"t": "id", "name": name}
		"p":
			var v := String(t.get("v", ""))
			if v == "(":
				_i += 1
				var inner := _expression()
				if error != "":
					return {}
				if not _expect(")"):
					return {}
				return inner
			if v == "[":
				_i += 1
				var items: Array = []
				if _is_p("]"):
					_i += 1
				else:
					while true:
						items.append(_expression())
						if error != "":
							return {}
						if _is_p(","):
							_i += 1
							if _is_p("]"):
								break
							continue
						break
					if not _expect("]"):
						return {}
				return {"t": "array", "items": items}
			if v == "{":
				return _object()
	_fail("не ожидал здесь \"%s\"" % str(t.get("v", "")), t)
	return {}


func _object() -> Dictionary:
	_i += 1  # "{"
	var pairs: Array = []
	if _is_p("}"):
		_i += 1
		return {"t": "object", "pairs": pairs}
	while true:
		var key_tok := _take()
		var key := ""
		match String(key_tok.get("t", "")):
			"id", "str":
				key = String(key_tok["v"])
			"num":
				key = String(key_tok.get("raw", str(key_tok["v"])))
			_:
				_fail("ожидал имя поля", key_tok)
				return {}
		if not _expect(":"):
			return {}
		var value := _expression()
		if error != "":
			return {}
		pairs.append([key, value])
		if _is_p(","):
			_i += 1
			if _is_p("}"):
				break
			continue
		break
	if not _expect("}"):
		return {}
	return {"t": "object", "pairs": pairs}
