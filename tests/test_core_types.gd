@tool
extends StrudelTestBase

## Отрезки, события, состояние и 32-битная арифметика.



func _spans(ts) -> String:
	var parts: Array[String] = []
	for s in ts.span_cycles():
		parts.append(s.show())
	return " ; ".join(parts)


func test_разбивка_по_циклам() -> void:
	eq(_spans(StrudelTimeSpan.new(0, 1)), "0/1 → 1/1", "ровно один цикл")
	eq(_spans(StrudelTimeSpan.new(0, 2)), "0/1 → 1/1 ; 1/1 → 2/1", "два цикла")
	eq(_spans(StrudelTimeSpan.new(StrudelFraction.new("1/2"), StrudelFraction.new("3/2"))), "1/2 → 1/1 ; 1/1 → 3/2", "через границу")
	eq(_spans(StrudelTimeSpan.new(StrudelFraction.new("1/4"), StrudelFraction.new("1/2"))), "1/4 → 1/2", "внутри цикла")
	# Отрезок нулевой длины обязан сохраниться: на нём стоят аналоговые сигналы.
	eq(_spans(StrudelTimeSpan.new(1, 1)), "1/1 → 1/1", "нулевая длина")
	eq(_spans(StrudelTimeSpan.new(-1, 1)), "-1/1 → 0/1 ; 0/1 → 1/1", "отрицательное время")


func test_пересечение() -> void:
	var a := StrudelTimeSpan.new(0, 1)
	eq(a.intersection(StrudelTimeSpan.new(StrudelFraction.new("1/2"), 2)).show(), "1/2 → 1/1", "частичное")
	check(a.intersection(StrudelTimeSpan.new(2, 3)) == null, "непересекающиеся дают null")
	# Касание в самом конце ненулевого отрезка — НЕ пересечение,
	# иначе событие задваивается на границе цикла.
	check(a.intersection(StrudelTimeSpan.new(1, 2)) == null, "касание в конце не считается")
	check(StrudelTimeSpan.new(1, 1).intersection(StrudelTimeSpan.new(0, 2)) != null, "точка внутри — считается")


func test_cycle_arc_и_with_cycle() -> void:
	eq(StrudelTimeSpan.new(StrudelFraction.new("5/4"), StrudelFraction.new("7/4")).cycle_arc().show(), "1/4 → 3/4", "сдвиг в нулевой цикл")
	var doubled = StrudelTimeSpan.new(StrudelFraction.new("5/4"), StrudelFraction.new("3/2")).with_cycle(func(t): return t.mul(2))
	eq(doubled.show(), "3/2 → 2/1", "with_cycle считает от начала цикла")


func test_событие_и_onset() -> void:
	var whole := StrudelTimeSpan.new(0, 1)
	var full := StrudelHap.new(whole, StrudelTimeSpan.new(0, 1), {"s": "bd"})
	var tail := StrudelHap.new(whole, StrudelTimeSpan.new(StrudelFraction.new("1/2"), 1), {"s": "bd"})
	check(full.has_onset(), "целое событие содержит начало")
	check(not tail.has_onset(), "хвост события начала не содержит")
	# Аналоговое событие: whole == null
	var cont := StrudelHap.new(null, StrudelTimeSpan.new(0, 1), 0.5)
	check(cont.whole == null, "аналоговое без whole")
	check(not cont.has_onset(), "аналоговое не имеет начала")
	eq(full.whole_or_part().show(), "0/1 → 1/1", "whole_or_part берёт whole")
	eq(cont.whole_or_part().show(), "0/1 → 1/1", "whole_or_part падает на part")


func test_длительность_с_clip() -> void:
	var h := StrudelHap.new(StrudelTimeSpan.new(0, StrudelFraction.new("1/2")), StrudelTimeSpan.new(0, StrudelFraction.new("1/2")), {"s": "x", "clip": 1.5})
	eq(h.duration().show(), "3/4", "clip растягивает длительность")
	var plain := StrudelHap.new(StrudelTimeSpan.new(0, StrudelFraction.new("1/2")), StrudelTimeSpan.new(0, StrudelFraction.new("1/2")), {"s": "x"})
	eq(plain.duration().show(), "1/2", "без clip — как whole")


func test_32_битная_арифметика() -> void:
	# Числа сняты в браузере на живой Булке.
	eq(StrudelUtil.shl32(1, 31), -2147483648, "1<<31")
	eq(StrudelUtil.shr32(-1, 17), -1, "(-1)>>17 арифметический")
	eq(StrudelUtil.ushr32(-1, 16), 65535, "(-1)>>>16 логический")
	eq(StrudelUtil.imul32(0x85ebca6b, 3), -1849467071, "Math.imul(0x85ebca6b,3)")
	eq(StrudelUtil.i32(0x100000000 + 5), 5, "срез до 32 бит")


func test_остаток_и_ноты() -> void:
	eq(StrudelUtil.mod_i(-1, 3), 2, "mod_i(-1,3)")
	eq(StrudelUtil.mod_i(7, 3), 1, "mod_i(7,3)")
	eq(StrudelUtil.note_to_midi("c3"), 48, "c3")
	eq(StrudelUtil.note_to_midi("a4"), 69, "a4")
	eq(StrudelUtil.note_to_midi("c#3"), 49, "c#3")
	eq(StrudelUtil.note_to_midi("eb3"), 51, "eb3")
	eq(StrudelUtil.note_to_midi("c"), 48, "нота без октавы — третья")
	eq_num(StrudelUtil.midi_to_freq(69.0), 440.0, 0.001, "midi 69 → 440 Гц")
