@tool
extends StrudelTestBase

## Планировщик и голоса: живая замена, смена темпа, вытеснение, пустой банк.
## Всё считается без звуковой карты — эти проверки должны идти и в CI.

const RATE := 48000.0


func _engine(code: String, voices: int = 32) -> StrudelEngine:
	var run: Dictionary = StrudelRuntime.run(code)
	check(run.get("ok", false), "код собрался: " + String(run.get("error", "")))
	var e := StrudelEngine.new()
	e.max_voices = voices
	e.setup(RATE)
	e.set_pattern(run["pattern"])
	var cps: float = run.get("cps", 0.0)
	if cps > 0.0:
		e.set_cps(cps)
	return e


func _peak(e: StrudelEngine, blocks: int, size: int = 4096) -> float:
	var peak := 0.0
	for b in blocks:
		var chunk: Array = e.render_block(size)
		var l: PackedFloat32Array = chunk[0]
		for i in l.size():
			peak = maxf(peak, absf(l[i]))
	return peak


func test_звук_вообще_есть() -> void:
	var e := _engine('setcpm(120/4)\n$: s("bd sd*2, ~ hh")')
	var peak := _peak(e, 12)
	check(peak > 0.01, "выход не тишина, пик %f" % peak)
	check(e.played_events > 0, "события сыграны: %d" % e.played_events)


func test_пустой_банк_не_роняет() -> void:
	# Сэмплов нет вовсе — ШТАТНОЕ состояние (мобильная сборка, свежая
	# установка). Плагин обязан играть синтезом, а не молчать и не падать.
	var e := _engine('setcpm(120/4)\n$: s("bd sd hh cp").bank("RolandTR909")')
	e.bank = StrudelSampleBank.new()
	var peak := _peak(e, 12)
	check(peak > 0.01, "с пустым банком звук есть, пик %f" % peak)


func test_несуществующий_сэмпл_не_роняет() -> void:
	var e := _engine('$: s("такогозвуканет ещёодин")')
	var peak := _peak(e, 8)
	check(peak >= 0.0, "не упало")


func test_живая_замена_не_сбрасывает_такт() -> void:
	# 🔴 Замена кода на ходу НЕ должна отматывать паттерн в начало: иначе
	# музыка спотыкается на каждой смене слоя.
	var e := _engine('setcpm(120/4)\n$: s("bd*4")')
	_peak(e, 20)
	var before := e.current_cycle()
	check(before > 0.5, "успели уйти вперёд: цикл %f" % before)

	var run: Dictionary = StrudelRuntime.run('$: s("hh*8")')
	e.set_pattern(run["pattern"])
	var after := e.current_cycle()
	eq_num(after, before, 0.0001, "такт после замены не сбросился")
	_peak(e, 8)
	check(e.current_cycle() > after, "и продолжил идти вперёд")


func test_смена_темпа_не_сбрасывает_такт() -> void:
	var e := _engine('setcpm(120/4)\n$: s("bd*4")')
	_peak(e, 20)
	var before := e.current_cycle()
	e.set_cps(1.0)
	eq_num(e.current_cycle(), before, 0.0001, "такт при смене темпа на месте")
	_peak(e, 10)
	check(e.current_cycle() > before, "и пошёл дальше уже быстрее")


func test_вытеснение_голосов_считается() -> void:
	# 🔴 Кража голоса не должна быть молчаливой: если нот больше, чем голосов,
	# это видно числом, а не «куда-то делись ноты».
	var e := _engine('setcpm(240/4)\n$: s("bd*64").release(4)', 4)
	_peak(e, 20)
	check(e.stolen_voices > 0, "вытеснения посчитаны: %d" % e.stolen_voices)
	check(e.active_voices() <= 4, "предел голосов соблюдён: %d" % e.active_voices())


func test_события_попадают_на_свои_отсчёты() -> void:
	# Четыре удара в цикл при 0.5 цикла/с — это ровно каждые 0.5 с.
	var run: Dictionary = StrudelRuntime.run('$: s("bd*4")')
	var e := StrudelEngine.new()
	e.setup(RATE)
	e.set_pattern(run["pattern"])
	e.set_cps(0.5)
	var starts: Array = []
	e.event_started.connect(func(_v, _d): starts.append(e.current_cycle()))
	# 24 блока по 4096 отсчётов — это 2.05 с; при 0.5 цикла/с и четырёх
	# ударах на цикл получается около четырёх ударов.
	for b in 24:
		e.render_block(4096)
	check(starts.size() >= 4, "ударов набралось: %d" % starts.size())
	check(starts.size() <= 6, "и не больше, чем помещается: %d" % starts.size())


func test_отсчёт_цикла_по_звуковым_часам() -> void:
	var e := _engine('$: s("bd")')
	e.set_cps(0.5)
	# Ровно секунда звука при 0.5 цикла/с — это половина цикла.
	var frames := int(RATE)
	var done := 0
	while done < frames:
		var n := mini(4096, frames - done)
		e.render_block(n)
		done += n
	eq_num(e.current_cycle(), 0.5, 0.001, "за секунду прошло полцикла")


func test_общий_генератор_игры_не_трогается() -> void:
	# 🔴 РЕГРЕССИЯ. Шум и стая пил тянули числа из `randf()`, а он один на всю
	# игру: той же чередой игра раскладывает свои вещи. Каждая сыгранная нота
	# сдвигала ход игры — гейт обхода в Osmo падал наложениями, и звук был
	# виноват. Проверка: череда общего генератора после сведения звука должна
	# остаться ТОЙ ЖЕ.
	seed(20260904)
	var want: Array = []
	for i in 8:
		want.append(randi())

	seed(20260904)
	var e := StrudelEngine.new()
	e.setup(48000.0)
	var run := StrudelRuntime.run('s("white pink brown supersaw").gain(0.5)')
	check(run.get("ok", false), "паттерн с шумом собрался")
	e.set_pattern(run["pattern"])
	for b in 8:
		e.render_block(2048)

	var got: Array = []
	for i in 8:
		got.append(randi())
	for i in want.size():
		eq(str(got[i]), str(want[i]), "общий генератор на месте, число %d" % i)
