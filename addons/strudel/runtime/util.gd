@tool
class_name StrudelUtil
extends RefCounted

## Мелочи, на которых стоит остальное. Перенос `packages/core/util.mjs`
## плюс 32-битная арифметика, без которой не совпадает случайное.

const CHROMAS := {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
const ACCIDENTALS := {"#": 1, "b": -1, "s": 1, "f": -1}


# ── 32-битная арифметика ─────────────────────────────────────────────────────
#
# 🔴 В JavaScript `<<`, `>>`, `^` и `Math.imul` работают в 32 битах со знаком,
# а в GDScript int — 64-битный. Без приведения последовательность случайных
# чисел расходится с оригиналом уже на первом цикле.
# Замерено в браузере: 1<<31 = -2147483648, (-1)>>17 = -1, (-1)>>>16 = 65535,
# Math.imul(0x85ebca6b, 3) = -1849467071.

const _U32 := 0x100000000
const _I32_MAX := 0x7FFFFFFF


static func i32(x: int) -> int:
	## Приводит к 32-битному знаковому, как это делает JS перед битовой операцией.
	var v := x & 0xFFFFFFFF
	return v - _U32 if v > _I32_MAX else v


static func u32(x: int) -> int:
	## Беззнаковое 32-битное (аналог `>>> 0`).
	return x & 0xFFFFFFFF


static func shl32(x: int, bits: int) -> int:
	return i32(x << bits)


static func shr32(x: int, bits: int) -> int:
	## Арифметический сдвиг вправо: знак сохраняется, как `>>` в JS.
	return i32(x) >> bits


static func ushr32(x: int, bits: int) -> int:
	## Логический сдвиг вправо, как `>>>` в JS.
	return u32(x) >> bits


static func imul32(a: int, b: int) -> int:
	## Аналог Math.imul: перемножение как 32-битных со знаком.
	return i32(i32(a) * i32(b))


# ── числа ────────────────────────────────────────────────────────────────────

static func mod_i(n: int, m: int) -> int:
	## Остаток, который для отрицательных даёт положительный результат:
	## mod_i(-1, 3) == 2. Обычный `%` в GDScript вернул бы -1.
	if m == 0:
		return 0
	return ((n % m) + m) % m


static func mod_f(n: float, m: float) -> float:
	if m == 0.0:
		return 0.0
	return fposmod(n, m)


static func parse_numeral(x: Variant) -> Variant:
	## Строку, похожую на число, превращает в число; остальное оставляет как есть.
	if x is String:
		var s: String = x
		if s.is_valid_float():
			var f := s.to_float()
			return int(f) if s.is_valid_int() else f
		return x
	return x


# ── ноты ─────────────────────────────────────────────────────────────────────

static func is_note(name: String) -> bool:
	var re := RegEx.create_from_string("^[a-gA-G][#bsf]*-?[0-9]*$")
	return re.search(name) != null


static func tokenize_note(note: String) -> Array:
	## → [ступень, знаки, октава или null]. Пустой массив, если это не нота.
	var re := RegEx.create_from_string("^([a-gA-G])([#bsf]*)(-?[0-9]*)$")
	var m := re.search(note)
	if m == null:
		return []
	var oct_text := m.get_string(3)
	var octave: Variant = int(oct_text) if oct_text != "" else null
	return [m.get_string(1), m.get_string(2), octave]


static func accidentals_offset(accidentals: String) -> int:
	var total := 0
	for ch in accidentals:
		total += ACCIDENTALS.get(ch, 0)
	return total


static func note_to_midi(note: String, default_octave: int = 3) -> int:
	## "c3" → 48. Октава по умолчанию — третья, как в Strudel.
	var parts := tokenize_note(note)
	if parts.is_empty():
		push_error("Strudel: \"%s\" — не нота" % note)
		return 0
	var octave: int = parts[2] if parts[2] != null else default_octave
	var chroma: int = CHROMAS.get(String(parts[0]).to_lower(), 0)
	return (octave + 1) * 12 + chroma + accidentals_offset(parts[1])


static func midi_to_freq(midi: float) -> float:
	return pow(2.0, (midi - 69.0) / 12.0) * 440.0


static func freq_to_midi(freq: float) -> float:
	return 12.0 * log(freq / 440.0) / log(2.0) + 69.0


# ── списки ───────────────────────────────────────────────────────────────────

static func list_range(from_n: int, to_n: int) -> Array:
	## Включительно с обоих концов — как listRange в оригинале.
	var out: Array = []
	var i := from_n
	while i <= to_n:
		out.append(i)
		i += 1
	return out


static func rotate_array(list: Array, by: int) -> Array:
	if list.is_empty():
		return []
	var k := mod_i(by, list.size())
	return list.slice(k) + list.slice(0, k)


static func flatten(list: Array) -> Array:
	var out: Array = []
	for item in list:
		if item is Array:
			out.append_array(item)
		else:
			out.append(item)
	return out
