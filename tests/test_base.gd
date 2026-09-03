@tool
extends RefCounted
class_name StrudelTestBase

## Общая часть набора тестов: сверки и доступ к прогонщику.

var _runner = null
var _case := ""


func check(condition: bool, message: String) -> void:
	_runner.note_check()
	if not condition:
		_runner.fail(_case, message)


func eq(actual: Variant, expected: Variant, what: String) -> void:
	_runner.note_check()
	if str(actual) != str(expected):
		_runner.fail(_case, "%s: ждал %s, получил %s" % [what, str(expected), str(actual)])


static func js_number(v: Variant) -> String:
	## Печатает число так же, как JSON.stringify в JavaScript: там один
	## числовой тип, и 3.0 выводится как "3". Без этого сверка с эталоном
	## спотыкается на каждом целом значении.
	if v is int:
		return str(v)
	var f: float = v
	if is_nan(f) or is_inf(f):
		return "null"
	if f == floor(f) and absf(f) < 1e15:
		return str(int(f))
	# 🔴 JavaScript печатает КРАТЧАЙШУЮ запись, которая читается обратно в то же
	# число: 0.6852155700325966, а не 0.68521557003259659. Без этого сверка с
	# эталоном краснеет на верных значениях — расхождение чисто в печати.
	for decimals in range(1, 21):
		var s := String.num(f, decimals)
		if s.to_float() == f:
			return s
	return String.num(f, 17)


static func exact_number(v: Variant) -> String:
	## Точные биты числа (IEEE754, little-endian, hex).
	##
	## 🔴 Сверять числа десятичной записью НЕЛЬЗЯ: `String.num` на 18 знаках
	## сам ошибается в последнем разряде (проверено: печатает
	## 0.008339818690274109 вместо 0.008339818690274114). Биты не врут.
	var f: float = float(v)
	return PackedFloat64Array([f]).to_byte_array().hex_encode()


static func js_json(v: Variant) -> String:
	## Значение события в том же виде, в каком его печатает Булка.
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is int or v is float:
		return js_number(v)
	if v is String or v is StringName:
		return JSON.stringify(String(v))
	if v is Array:
		var items: Array[String] = []
		for x in v:
			items.append(js_json(x))
		return "[" + ",".join(items) + "]"
	if v is Dictionary:
		# Порядок ключей — как их положили, БЕЗ сортировки:
		# Godot сортирует по умолчанию, JavaScript — нет.
		var pairs: Array[String] = []
		for k in v:
			pairs.append(JSON.stringify(String(k)) + ":" + js_json(v[k]))
		return "{" + ",".join(pairs) + "}"
	return JSON.stringify(str(v))


static func dump_haps(pat: StrudelPattern, from_time: Variant = 0, to_time: Variant = 1) -> Array:
	## Список событий в устойчивом порядке.
	##
	## 🔴 Порядок событий внутри одного запроса НЕ является частью смысла:
	## у `rev` и `stack` он зависит от того, как обходились ветви. Сам Strudel
	## сравнивает паттерны через sortHapsByPart. Поэтому сверка сортирует.
	var rows: Array = []
	for h in pat.query_arc(from_time, to_time):
		rows.append({
			"wb": "" if h.whole == null else h.whole.begin.show(),
			"we": "" if h.whole == null else h.whole.end.show(),
			"pb": h.part.begin.show(),
			"pe": h.part.end.show(),
			"v": js_json(h.value),
			"k": [
				h.part.begin.to_float(), h.part.end.to_float(),
				(h.whole.begin.to_float() if h.whole != null else -1e18),
			],
		})
	rows.sort_custom(func(a, b):
		for i in 3:
			if a["k"][i] != b["k"][i]:
				return a["k"][i] < b["k"][i]
		return String(a["v"]) < String(b["v"])
	)
	return rows


func eq_num(actual: float, expected: float, tol: float, what: String) -> void:
	_runner.note_check()
	if absf(actual - expected) > tol:
		_runner.fail(_case, "%s: ждал %s ± %s, получил %s" % [what, expected, tol, actual])
