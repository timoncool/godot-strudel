@tool
extends SceneTree

## Уход долей на длинной форме.
##
##   godot --headless --path <проект> --script res://tools/check_drift.gd
##
## Планировщик ставит удар на ЦЕЛЫЙ отсчёт, а точное время события — дробь.
## Разница между ними и есть уход. Мерить его надо на КОНЦЕ длинной формы:
## если время считается накоплением, к шестнадцатой секции набежит слышимое.

const TRACK := "res://examples/04_full_track/track/kuvshinka.js"
const RATE := 48000.0


func _init() -> void:
	var f := FileAccess.open(TRACK, FileAccess.READ)
	if f == null:
		printerr("[уход] не прочитал ", TRACK)
		quit(1)
		return
	var code := f.get_as_text()
	f.close()

	var run: Dictionary = StrudelRuntime.run(code)
	if not run.get("ok", false):
		printerr("[уход] трек не собрался")
		quit(1)
		return
	var pat: StrudelPattern = run["pattern"]
	var cps: float = run.get("cps", 0.5)

	var engine := StrudelEngine.new()
	engine.setup(RATE)
	engine.set_pattern(pat)
	engine.set_cps(cps)

	print("[уход] темп %.6f цикла в секунду, длина цикла %.4f с" % [cps, 1.0 / cps])

	# Сравниваем ТОЧНОЕ время события (дробь) с тем отсчётом, куда его поставили.
	for section in [0, 4, 8, 12, 15]:
		var cycle_from: int = section * 4
		var worst := 0.0
		var total := 0.0
		var count := 0
		for c in range(cycle_from, cycle_from + 4):
			for hap in pat.query_arc(c, c + 1):
				if not hap.has_onset():
					continue
				var exact_cycle: StrudelFraction = hap.whole.begin
				# точное время в секундах — дробью, без накопления
				var exact_frame: float = exact_cycle.to_float() / cps * RATE
				var placed := float(engine.frame_at_cycle(exact_cycle.to_float()))
				var drift_ms := absf(placed - exact_frame) / RATE * 1000.0
				worst = maxf(worst, drift_ms)
				total += drift_ms
				count += 1
		var avg := total / float(maxi(count, 1))
		print("[уход] секция %2d (циклы %2d-%2d): событий %3d, средний %.5f мс, худший %.5f мс"
			% [section + 1, cycle_from, cycle_from + 3, count, avg, worst])

	# Отдельно: не накапливается ли ошибка в самих звуковых часах.
	var frames := int(RATE * 200.0)
	var expected_cycle := float(frames) / RATE * cps
	var actual_cycle := engine.cycle_at_frame(frames)
	# %g в форматировании GDScript нет — печатаем строкой.
	print("[уход] через 200 с звука: цикл ожидаемый %s, полученный %s, разница %s"
		% [String.num(expected_cycle, 9), String.num(actual_cycle, 9),
		   String.num(absf(actual_cycle - expected_cycle), 12)])
	quit(0)
