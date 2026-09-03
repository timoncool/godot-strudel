@tool
extends StrudelTestBase

## Дроби. Числа взяты не из головы: они сняты с живой Булки
## (см. tools/judge/golden/haps.json) либо посчитаны по формулам fraction.js.



func test_создание_и_сокращение() -> void:
	eq(StrudelFraction.make(6, 8).show(), "3/4", "6/8 сокращается")
	eq(StrudelFraction.make(-6, 8).show(), "-3/4", "знак уходит в s")
	eq(StrudelFraction.make(6, -8).show(), "-3/4", "знак из знаменателя")
	eq(StrudelFraction.new(0).show(), "0/1", "ноль")
	eq(StrudelFraction.new(5).show(), "5/1", "целое")
	eq(StrudelFraction.new("23/800").show(), "23/800", "строка-дробь")
	eq(StrudelFraction.new("-3/4").show(), "-3/4", "отрицательная строка")


func test_фарей_даёт_ровные_дроби() -> void:
	# Ключевая проверка: swingBy(0.23, 4) обязан дать 23/800.
	# Без разбора чисел последовательностями Фарея вышло бы 0.11499999999999999.
	eq(StrudelFraction.new(0.115).show(), "23/200", "0.115 → 23/200")
	eq(StrudelFraction.new(0.23).show(), "23/100", "0.23 → 23/100")
	eq(StrudelFraction.new(0.25).show(), "1/4", "0.25 → 1/4")
	eq(StrudelFraction.new(0.125).show(), "1/8", "0.125 → 1/8")
	eq(StrudelFraction.new(1.0 / 3.0).show(), "1/3", "1/3 → 1/3")
	eq(StrudelFraction.new(0.0003).show(), "3/10000", "смещение ? в mini-нотации")
	eq(StrudelFraction.new(1.5).show(), "3/2", "1.5 → 3/2")
	eq(StrudelFraction.new(-0.75).show(), "-3/4", "отрицательное с плавающей точкой")


func test_арифметика() -> void:
	eq(StrudelFraction.new("1/3").add("1/7").show(), "10/21", "сложение")
	eq(StrudelFraction.new("1/2").sub("1/3").show(), "1/6", "вычитание")
	eq(StrudelFraction.new("2/3").mul("3/4").show(), "1/2", "умножение")
	eq(StrudelFraction.new("2/3").div("4/5").show(), "5/6", "деление")
	eq(StrudelFraction.new("1/3").add("1/7").mul(StrudelFraction.new("99991/99989")).show(), "999910/2099769", "цепочка как в Булке")
	eq(StrudelFraction.new(1).sub(2).show(), "-1/1", "отрицательный результат")


func test_остаток() -> void:
	eq(StrudelFraction.new("7/2").mod(1).show(), "1/2", "7/2 mod 1")
	eq(StrudelFraction.new("3/4").mod("1/2").show(), "1/4", "3/4 mod 1/2")


func test_округление_вниз_у_отрицательных() -> void:
	# На этом стоит разбивка запроса по циклам: floor(-3/4) обязан быть -1.
	eq(StrudelFraction.new("-3/4").floor_().show(), "-1/1", "floor(-3/4)")
	eq(StrudelFraction.new("3/4").floor_().show(), "0/1", "floor(3/4)")
	eq(StrudelFraction.new(-2).floor_().show(), "-2/1", "floor(-2)")
	eq(StrudelFraction.new("-3/4").ceil_().show(), "0/1", "ceil(-3/4)")
	eq(StrudelFraction.new("3/4").ceil_().show(), "1/1", "ceil(3/4)")


func test_время_цикла() -> void:
	eq(StrudelFraction.new("5/4").sam().show(), "1/1", "sam(5/4)")
	eq(StrudelFraction.new("5/4").next_sam().show(), "2/1", "next_sam(5/4)")
	eq(StrudelFraction.new("5/4").cycle_pos().show(), "1/4", "cycle_pos(5/4)")
	eq(StrudelFraction.new("-1/4").sam().show(), "-1/1", "sam у отрицательного времени")
	eq(StrudelFraction.new("-1/4").cycle_pos().show(), "3/4", "cycle_pos у отрицательного времени")


func test_сравнение() -> void:
	check(StrudelFraction.new("1/3").lt(StrudelFraction.new("1/2")), "1/3 < 1/2")
	check(StrudelFraction.new("-1/3").lt(StrudelFraction.new("1/300")), "отрицательное меньше положительного")
	check(StrudelFraction.new("2/4").eq(StrudelFraction.new("1/2")), "2/4 == 1/2")
	check(not StrudelFraction.new("2/4").ne(StrudelFraction.new("1/2")), "2/4 не отличается от 1/2")
	eq(StrudelFraction.new("1/3").max_(StrudelFraction.new("1/2")).show(), "1/2", "max")
	eq(StrudelFraction.new("1/3").min_(StrudelFraction.new("1/2")).show(), "1/3", "min")
	eq(StrudelFraction.new(0).or_(StrudelFraction.new("1/2")).show(), "1/2", "ноль уступает")
	eq(StrudelFraction.new("1/4").or_(StrudelFraction.new("1/2")).show(), "1/4", "не-ноль остаётся")


func test_gcd_lcm() -> void:
	eq(StrudelFraction.new("1/2").gcd(StrudelFraction.new("1/3")).show(), "1/6", "gcd(1/2,1/3)")
	eq(StrudelFraction.new("1/2").lcm(StrudelFraction.new("1/3")).show(), "1/1", "lcm(1/2,1/3)")
	eq(StrudelFraction.new(4).lcm(StrudelFraction.new(6)).show(), "12/1", "lcm(4,6)")


func test_большие_знаменатели_не_переполняются() -> void:
	# Длинная форма: 16 секций по 4 цикла со свингом 23/800 — знаменатели
	# перемножаются. Проверяем, что сокращение крест-накрест держит int64.
	var acc := StrudelFraction.new("23/800")
	for i in 40:
		acc = acc.add(StrudelFraction.make(1, 3 + i)).mul(StrudelFraction.make(i + 1, i + 2))
	check(acc.d > 0 and acc.n >= 0, "знаменатель остался осмысленным: " + acc.show())
	check(acc.to_float() > 0.0, "значение положительное: %f" % acc.to_float())
