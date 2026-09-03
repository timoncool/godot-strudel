@tool
class_name StrudelFraction
extends RefCounted

## Точная дробь — время в Strudel считается только ею.
##
## Перенос `fraction.js` 5.2.1 (+ надстройки `packages/core/fraction.mjs`),
## на котором стоит весь Strudel. Плавающая точка в позициях событий не
## используется: на длинных формах доли уплывают уже к третьей минуте.
##
## Устройство повторяет оригинал: знак хранится ОТДЕЛЬНО, числитель и
## знаменатель всегда неотрицательные и всегда сокращённые. В оригинале они
## BigInt, здесь — 64-битные int, поэтому умножение идёт с сокращением
## крест-накрест: иначе промежуточное произведение вылетает за предел там,
## где результат помещается свободно.

## Знак: +1, -1 или (для нуля) +1.
var s: int = 1
## Числитель, всегда >= 0.
var n: int = 0
## Знаменатель, всегда > 0.
var d: int = 1

const _FAREY_N := 10000000


func _init(numerator: Variant = 0, denominator: Variant = null) -> void:
	# Горячий путь: целое без знаменателя. Через общий разбор он стоил бы
	# лишнего объекта на КАЖДУЮ арифметическую операцию — а их в запросе
	# паттерна десятки тысяч.
	if denominator == null and numerator is int:
		var i: int = numerator
		s = -1 if i < 0 else 1
		n = absi(i)
		d = 1
		return
	if denominator != null:
		var a := _to_frac(numerator)
		var b := _to_frac(denominator)
		if b.n == 0:
			push_error("StrudelFraction: деление на ноль в %s/%s" % [str(numerator), str(denominator)])
			_assign(1, 0, 1)
			return
		_assign(a.s * b.s, a.n * b.d, a.d * b.n)
		return
	var f := _to_frac(numerator)
	_assign(f.s, f.n, f.d)


# ── создание ─────────────────────────────────────────────────────────────────

static func of(value: Variant) -> StrudelFraction:
	## Приводит число, строку ("3/4", "1.5") или дробь к дроби.
	if value is StrudelFraction:
		return value
	return StrudelFraction.new(value)


static func make(numerator: int, denominator: int) -> StrudelFraction:
	## Дробь из пары целых.
	return StrudelFraction.new(numerator, denominator)


func _assign(sign_: int, num: int, den: int) -> void:
	if den < 0:
		den = -den
		sign_ = -sign_
	if num < 0:
		num = -num
		sign_ = -sign_
	if den == 0:
		push_error("StrudelFraction: нулевой знаменатель")
		den = 1
		num = 0
	var g := _gcd_int(num, den)
	if g > 1:
		num /= g
		den /= g
	if num == 0:
		sign_ = 1
	s = 1 if sign_ >= 0 else -1
	n = num
	d = den


static func _gcd_int(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a if a != 0 else 1


class _Parts:
	var s: int = 1
	var n: int = 0
	var d: int = 1

	func _init(sign_: int, num: int, den: int) -> void:
		s = sign_
		n = num
		d = den


func _to_frac(value: Variant) -> _Parts:
	if value is StrudelFraction:
		return _Parts.new(value.s, value.n, value.d)
	if value is int:
		var i: int = value
		return _Parts.new(-1 if i < 0 else 1, absi(i), 1)
	if value is float:
		return _from_float(value)
	if value is String or value is StringName:
		return _from_string(String(value))
	if value == null:
		return _Parts.new(1, 0, 1)
	push_error("StrudelFraction: не понимаю значение %s" % str(value))
	return _Parts.new(1, 0, 1)


static func _from_float(v: float) -> _Parts:
	## Перенос разбора чисел из fraction.js: последовательности Фарея
	## (поиск медиантой по дереву Штерна—Броко), предел знаменателя 10^7.
	##
	## Это не украшение: `swingBy(0.23, 4)` обязан дать РОВНО 23/800, а не
	## приближение из двоичной дроби. Проверено против живой Булки.
	if is_nan(v):
		push_error("StrudelFraction: NaN")
		return _Parts.new(1, 0, 1)
	if is_inf(v):
		push_error("StrudelFraction: бесконечность")
		return _Parts.new(1, 0, 1)

	var sign_ := 1
	if v < 0.0:
		sign_ = -1
		v = -v

	if fmod(v, 1.0) == 0.0:
		return _Parts.new(sign_, int(v), 1)

	var z := 1
	var a := 0
	var b := 1
	var c := 1
	var dd := 1
	var num := 0
	var den := 1

	if v >= 1.0:
		z = int(pow(10.0, floor(1.0 + log(v) / log(10.0))))
		v /= float(z)

	while b <= _FAREY_N and dd <= _FAREY_N:
		var m := float(a + c) / float(b + dd)
		if v == m:
			if b + dd <= _FAREY_N:
				num = a + c
				den = b + dd
			elif dd > b:
				num = c
				den = dd
			else:
				num = a
				den = b
			break
		if v > m:
			a += c
			b += dd
		else:
			c += a
			dd += b
		if b > _FAREY_N:
			num = c
			den = dd
		else:
			num = a
			den = b

	return _Parts.new(sign_, num * z, den)


static func _from_string(text: String) -> _Parts:
	var t := text.replace("_", "").strip_edges()
	if t.is_empty():
		return _Parts.new(1, 0, 1)
	var sign_ := 1
	if t.begins_with("-"):
		sign_ = -1
		t = t.substr(1)
	elif t.begins_with("+"):
		t = t.substr(1)
	if t.contains("/"):
		var bits := t.split("/", false, 2)
		if bits.size() == 2 and bits[0].is_valid_int() and bits[1].is_valid_int():
			return _Parts.new(sign_, bits[0].to_int(), bits[1].to_int())
	if t.is_valid_int():
		return _Parts.new(sign_, t.to_int(), 1)
	if t.is_valid_float():
		var f := _from_float(t.to_float())
		f.s *= sign_
		return f
	push_error("StrudelFraction: не разобрал строку \"%s\"" % text)
	return _Parts.new(1, 0, 1)


# ── арифметика ───────────────────────────────────────────────────────────────

func add(other: Variant) -> StrudelFraction:
	if other is StrudelFraction:
		var f: StrudelFraction = other
		if d == f.d:
			return _make(s * n + f.s * f.n, d)
		return _make(s * n * f.d + f.s * f.n * d, d * f.d)
	var o := _to_frac(other)
	return _make(s * n * o.d + o.s * o.n * d, d * o.d)


func sub(other: Variant) -> StrudelFraction:
	if other is StrudelFraction:
		var f: StrudelFraction = other
		if d == f.d:
			return _make(s * n - f.s * f.n, d)
		return _make(s * n * f.d - f.s * f.n * d, d * f.d)
	var o := _to_frac(other)
	return _make(s * n * o.d - o.s * o.n * d, d * o.d)


func mul(other: Variant) -> StrudelFraction:
	# Сокращение крест-накрест ДО умножения — держит числа в пределах int64.
	if other is StrudelFraction:
		var f: StrudelFraction = other
		var h1 := _gcd_int(n, f.d)
		var h2 := _gcd_int(f.n, d)
		return _make_signed(s * f.s, (n / h1) * (f.n / h2), (d / h2) * (f.d / h1))
	var o := _to_frac(other)
	var g1 := _gcd_int(n, o.d)
	var g2 := _gcd_int(o.n, d)
	return _make_signed(s * o.s, (n / g1) * (o.n / g2), (d / g2) * (o.d / g1))


func div(other: Variant) -> StrudelFraction:
	if other is StrudelFraction:
		var f: StrudelFraction = other
		if f.n == 0:
			push_error("StrudelFraction: деление на ноль")
			return StrudelFraction.new(0)
		var h1 := _gcd_int(n, f.n)
		var h2 := _gcd_int(f.d, d)
		return _make_signed(s * f.s, (n / h1) * (f.d / h2), (d / h2) * (f.n / h1))
	var o := _to_frac(other)
	if o.n == 0:
		push_error("StrudelFraction: деление на ноль")
		return StrudelFraction.new(0)
	var g1 := _gcd_int(n, o.n)
	var g2 := _gcd_int(o.d, d)
	return _make_signed(s * o.s, (n / g1) * (o.d / g2), (d / g2) * (o.n / g1))


static func _make(num: int, den: int) -> StrudelFraction:
	## Прямая сборка без разбора Variant — этим живёт весь горячий путь.
	var f := StrudelFraction.new()
	var sign_ := 1
	if num < 0:
		num = -num
		sign_ = -1
	if den < 0:
		den = -den
		sign_ = -sign_
	if den != 1:
		var g := _gcd_int(num, den)
		if g > 1:
			num /= g
			den /= g
	f.s = 1 if num == 0 else sign_
	f.n = num
	f.d = den if den != 0 else 1
	return f


static func _make_signed(sign_: int, num: int, den: int) -> StrudelFraction:
	var f := StrudelFraction.new()
	if num < 0:
		num = -num
		sign_ = -sign_
	if den < 0:
		den = -den
		sign_ = -sign_
	if den != 1:
		var g := _gcd_int(num, den)
		if g > 1:
			num /= g
			den /= g
	f.s = 1 if num == 0 else (1 if sign_ >= 0 else -1)
	f.n = num
	f.d = den if den != 0 else 1
	return f


func mod(other: Variant = null) -> StrudelFraction:
	## Остаток. Формула — из fraction.js: ((d2*n1) % (n2*d1)) / (d1*d2).
	if other == null:
		return _raw(s * n % d, 1)
	var o := _to_frac(other)
	if o.n * d == 0:
		push_error("StrudelFraction: остаток от нуля")
		return StrudelFraction.new(0)
	return _raw(s * (o.d * n) % (o.n * d), o.d * d)


func neg() -> StrudelFraction:
	return _raw_signed(-s, n, d)


func abs_() -> StrudelFraction:
	return _raw_signed(1, n, d)


func inverse() -> StrudelFraction:
	if n == 0:
		push_error("StrudelFraction: обращение нуля")
		return StrudelFraction.new(0)
	return _raw_signed(s, d, n)


func floor_() -> StrudelFraction:
	## Округление вниз. У отрицательных это НЕ отбрасывание дробной части:
	## floor(-3/4) = -1, и на этом стоит разбивка по циклам.
	var q := (s * n) / d
	if s < 0 and n % d > 0:
		q -= 1
	return StrudelFraction.new(q)


func ceil_() -> StrudelFraction:
	var q := (s * n) / d
	if s > 0 and n % d > 0:
		q += 1
	return _raw(q, 1)


func gcd(other: Variant) -> StrudelFraction:
	var o := _to_frac(other)
	return _raw(_gcd_int(o.n, n) * _gcd_int(o.d, d), o.d * d)


func lcm(other: Variant) -> StrudelFraction:
	var o := _to_frac(other)
	if o.n == 0 and n == 0:
		return StrudelFraction.new(0)
	return _raw(o.n * n, _gcd_int(o.n, n) * _gcd_int(o.d, d))


func _raw(num: int, den: int) -> StrudelFraction:
	var f := StrudelFraction.new()
	f._assign(1, num, den)
	return f


func _raw_signed(sign_: int, num: int, den: int) -> StrudelFraction:
	var f := StrudelFraction.new()
	f._assign(sign_, num, den)
	return f


# ── сравнение ────────────────────────────────────────────────────────────────

func compare(other: Variant) -> int:
	if other is StrudelFraction:
		var f: StrudelFraction = other
		var a := s * n * f.d
		var b := f.s * f.n * d
		if a < b:
			return -1
		return 1 if a > b else 0
	var o := _to_frac(other)
	var left := s * n * o.d
	var right := o.s * o.n * d
	if left < right:
		return -1
	return 1 if left > right else 0


func lt(other: Variant) -> bool:
	return compare(other) < 0


func gt(other: Variant) -> bool:
	return compare(other) > 0


func lte(other: Variant) -> bool:
	return compare(other) <= 0


func gte(other: Variant) -> bool:
	return compare(other) >= 0


func eq(other: Variant) -> bool:
	return compare(other) == 0


func ne(other: Variant) -> bool:
	return compare(other) != 0


func max_(other: Variant) -> StrudelFraction:
	var o := StrudelFraction.of(other)
	return self if gt(o) else o


func min_(other: Variant) -> StrudelFraction:
	var o := StrudelFraction.of(other)
	return self if lt(o) else o


func maximum(others: Array) -> StrudelFraction:
	var best: StrudelFraction = self
	for other in others:
		var o := StrudelFraction.of(other)
		if o.gt(best):
			best = o
	return best


func or_(other: Variant) -> StrudelFraction:
	## `a.or(b)` из fraction.mjs: ноль уступает место второму значению.
	return StrudelFraction.of(other) if eq(0) else self


# ── время цикла ──────────────────────────────────────────────────────────────

func sam() -> StrudelFraction:
	## Начало цикла, в котором лежит это время.
	return floor_()


func next_sam() -> StrudelFraction:
	## Начало следующего цикла.
	return sam().add(1)


func cycle_pos() -> StrudelFraction:
	## Положение внутри своего цикла, 0 <= x < 1.
	return sub(sam())


# ── прочее ───────────────────────────────────────────────────────────────────

func mul_maybe(other: Variant) -> StrudelFraction:
	return null if other == null else mul(other)


func div_maybe(other: Variant) -> StrudelFraction:
	return null if other == null else div(other)


func add_maybe(other: Variant) -> StrudelFraction:
	return null if other == null else add(other)


func sub_maybe(other: Variant) -> StrudelFraction:
	return null if other == null else sub(other)


func to_float() -> float:
	return float(s) * float(n) / float(d)


func to_int() -> int:
	return (s * n) / d


func is_zero() -> bool:
	return n == 0


func show() -> String:
	## Формат оригинала: "s*n/d". В нём же лежит эталон в tools/judge.
	return "%d/%d" % [s * n, d]


func _to_string() -> String:
	return show()


func duplicate_() -> StrudelFraction:
	return _raw_signed(s, n, d)
