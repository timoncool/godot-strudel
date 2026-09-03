@tool
extends StrudelTestBase

## Ошибки и края.
##
## 🔴 Битая строка обязана давать ПОНЯТНОЕ сообщение С МЕСТОМ, а не тишину и не
## падение: это плагин для чужих людей, и отлаживать свой код они будут по
## этому сообщению.


func _err(code: String) -> String:
	var run: Dictionary = StrudelRuntime.run(code)
	if run.get("ok", false):
		return ""
	return String(run.get("error", ""))


func test_ошибка_mini_нотации_с_позицией() -> void:
	var cases := {
		's("bd [sd")': "не закрыта",
		's("bd <sd")': "не закрыта",
		's("bd {sd")': "не закрыта",
		's("bd(3")': "эвклид",
		's("")': "пуст",
	}
	for code in cases:
		var message := _err(code)
		check(message != "", "%s — ошибка есть" % code)
		check(message.contains("позиция") or message.contains("пуст"),
			"%s — сказано, ГДЕ: %s" % [code, message])


func test_ошибка_кода_с_номером_строки() -> void:
	var message := _err("const a = 1\n$: s(\"bd\"")
	check(message != "", "незакрытая скобка замечена")
	check(message.contains("строка"), "указана строка: " + message)


func test_неизвестное_имя_названо() -> void:
	var message := _err('$: такойфункциинет("bd")')
	check(message.contains("не знаю"), "сказано, что имя незнакомо: " + message)
	check(message.contains("такойфункциинет"), "названо само имя: " + message)


func test_пустой_паттерн_и_одна_пауза() -> void:
	var only_rest: Dictionary = StrudelRuntime.run('$: s("~")')
	check(only_rest.get("ok", false), "одна пауза — законный паттерн")
	eq((only_rest["pattern"] as StrudelPattern).query_arc(0, 1).size(), 0, "и событий не даёт")

	var silence: Dictionary = StrudelRuntime.run("$: silence")
	check(silence.get("ok", false), "silence разбирается")
	eq((silence["pattern"] as StrudelPattern).query_arc(0, 1).size(), 0, "и молчит")


func test_странные_значения_не_роняют() -> void:
	var cases := [
		'$: s("bd").gain(0)',
		'$: s("bd").gain(-1)',
		'$: s("bd sd").fast(0)',
		'$: s("bd sd").slow(0)',
		'$: s("bd").speed(0)',
		'$: s("bd").lpf(0)',
		'$: n("0").scale("такоголаданет")',
		'$: n("0").set(chord("Хм7")).voicing()',
	]
	for code in cases:
		var run: Dictionary = StrudelRuntime.run(code)
		check(run.get("ok", false), "разобралось: " + code)
		if run.get("ok", false):
			var n := (run["pattern"] as StrudelPattern).query_arc(0, 2).size()
			check(n >= 0, "запрос отработал: " + code)


func test_глубокая_вложенность() -> void:
	var run: Dictionary = StrudelRuntime.run('$: s("[[[[[bd sd] hh] cp] bd] sd]")')
	check(run.get("ok", false), "глубокая вложенность разобралась")
	check((run["pattern"] as StrudelPattern).query_arc(0, 1).size() > 0, "и дала события")


func test_отрицательное_и_дробное_окно_запроса() -> void:
	var run: Dictionary = StrudelRuntime.run('$: s("bd sd")')
	var pat: StrudelPattern = run["pattern"]
	eq(pat.query_arc(-2, 0).size(), 4, "отрицательные циклы считаются")
	check(pat.query_arc(0.3, 0.8).size() > 0, "дробное окно работает")
	# Окно НУЛЕВОЙ длины отдаёт событие — и это не странность, а нужное
	# поведение: так снимаются значения непрерывных сигналов в точке.
	# Проверено на живой Булке: queryArc(1,1) там тоже даёт одно событие.
	eq(pat.query_arc(1, 1).size(), 1, "окно нулевой длины даёт одно событие")
	eq(pat.query_arc(0.25, 0.25).size(), 1, "и в середине доли тоже")
