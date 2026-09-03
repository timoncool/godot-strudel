@tool
extends StrudelTestBase

## Ядро паттернов, собранное вручную (без mini-нотации — она проверяется отдельно).
## Ожидаемые значения сверены с живой Булкой.


func dump(pat: StrudelPattern, from_time: Variant = 0, to_time: Variant = 1) -> String:
	var parts: Array[String] = []
	for row in dump_haps(pat, from_time, to_time):
		var w: String = "~" if row["wb"] == "" else row["wb"] + ".." + row["we"]
		parts.append("%s=%s" % [w, row["v"]])
	return " | ".join(parts)


func test_pure_и_цикл() -> void:
	eq(dump(StrudelPattern.pure("a")), '0/1..1/1="a"', "pure раз в цикл")
	eq(dump(StrudelPattern.pure("a"), 0, 2), '0/1..1/1="a" | 1/1..2/1="a"', "два цикла")
	eq(dump(StrudelPattern.silence()), "", "тишина пуста")


func test_fastcat_и_slowcat() -> void:
	var abc := [StrudelPattern.pure("a"), StrudelPattern.pure("b"), StrudelPattern.pure("c")]
	eq(dump(StrudelPattern.fastcat(abc)),
		'0/1..1/3="a" | 1/3..2/3="b" | 2/3..1/1="c"', "fastcat в один цикл")
	eq(dump(StrudelPattern.slowcat(abc), 0, 3),
		'0/1..1/1="a" | 1/1..2/1="b" | 2/1..3/1="c"', "slowcat по циклу на каждый")
	# Четвёртый цикл склейки из трёх — это ВТОРОЙ цикл первого паттерна.
	eq(dump(StrudelPattern.slowcat([
			StrudelPattern.fastcat([StrudelPattern.pure("a"), StrudelPattern.pure("b")]),
			StrudelPattern.pure("c")
		]), 2, 3),
		'2/1..5/2="a" | 5/2..3/1="b"', "цикл составляющего не пропускается")


func test_stack() -> void:
	eq(dump(StrudelPattern.stack([StrudelPattern.pure("a"), StrudelPattern.pure("b")])),
		'0/1..1/1="a" | 0/1..1/1="b"', "оба одновременно")


func test_время() -> void:
	var ab := StrudelPattern.fastcat([StrudelPattern.pure("a"), StrudelPattern.pure("b")])
	eq(dump(ab._fast(2)),
		'0/1..1/4="a" | 1/4..1/2="b" | 1/2..3/4="a" | 3/4..1/1="b"', "fast(2)")
	eq(dump(ab._slow(2), 0, 2),
		'0/1..1/1="a" | 1/1..2/1="b"', "slow(2)")
	eq(dump(ab.rev()),
		'0/1..1/2="b" | 1/2..1/1="a"', "rev переворачивает цикл")
	eq(dump(ab._late(StrudelFraction.new("1/4"))),
		'-1/4..1/4="b" | 1/4..3/4="a" | 3/4..5/4="b"', "late(1/4)")


func test_timecat_веса() -> void:
	eq(dump(StrudelPattern.stepcat([[3, StrudelPattern.pure("e3")], [1, StrudelPattern.pure("g3")]])),
		'0/1..3/4="e3" | 3/4..1/1="g3"', "e3@3 g3")


func test_struct_и_mask() -> void:
	# struct берёт структуру СПРАВА, mask — слева. Перепутать нельзя.
	var note := StrudelPattern.pure(0)
	var rhythm := StrudelPattern.fastcat([
		StrudelPattern.pure(true), StrudelPattern.pure(false),
		StrudelPattern.pure(true), StrudelPattern.pure(true)
	])
	eq(dump(note.struct_([rhythm])),
		'0/1..1/4=0 | 1/2..3/4=0 | 3/4..1/1=0', "struct даёт три удара")
	var four := StrudelPattern.fastcat([
		StrudelPattern.pure(0), StrudelPattern.pure(1),
		StrudelPattern.pure(2), StrudelPattern.pure(3)
	])
	eq(dump(four.mask_([rhythm])),
		'0/1..1/4=0 | 1/2..3/4=2 | 3/4..1/1=3', "mask сохраняет свои доли")


func test_слияние_словарей() -> void:
	var base := StrudelPattern.pure({"s": "bd"})
	eq(dump(base.gain(0.5)), '0/1..1/1={"s":"bd","gain":0.5}', "gain добавляется")
	eq(dump(base.set_([StrudelPattern.pure({"s": "sd"})])),
		'0/1..1/1={"s":"sd"}', "set перекрывает")
	eq(dump(StrudelPattern.pure({"n": 1}).add([StrudelPattern.pure({"n": 2})])),
		'0/1..1/1={"n":3}', "add складывает общие ключи")


func test_ply_и_segment() -> void:
	var ab := StrudelPattern.fastcat([StrudelPattern.pure("a"), StrudelPattern.pure("b")])
	eq(dump(ab._ply(2)),
		'0/1..1/4="a" | 1/4..1/2="a" | 1/2..3/4="b" | 3/4..1/1="b"', "ply(2)")


func test_iter() -> void:
	var abcd := StrudelPattern.fastcat([
		StrudelPattern.pure(0), StrudelPattern.pure(1),
		StrudelPattern.pure(2), StrudelPattern.pure(3)
	])
	eq(dump(abcd._iter(4), 1, 2),
		'1/1..5/4=1 | 5/4..3/2=2 | 3/2..7/4=3 | 7/4..2/1=0', "iter(4) на втором цикле")


func test_патернифицированный_аргумент() -> void:
	# fast("<1 2>") — скорость сама паттерн.
	var ab := StrudelPattern.fastcat([StrudelPattern.pure("a"), StrudelPattern.pure("b")])
	var speeds := StrudelPattern.slowcat([StrudelPattern.pure(1), StrudelPattern.pure(2)])
	eq(dump(ab.fast(speeds), 0, 1), '0/1..1/2="a" | 1/2..1/1="b"', "первый цикл — обычная скорость")
	eq(dump(ab.fast(speeds), 1, 2),
		'1/1..5/4="a" | 5/4..3/2="b" | 3/2..7/4="a" | 7/4..2/1="b"', "второй цикл — вдвое быстрее")
