@tool
class_name StrudelEngine
extends RefCounted

## Планировщик и сведение.
##
## 🔴 Время берётся от СЧЁТЧИКА КАДРОВ ЗВУКА, а не от `_process`. Кадр движка
## плавает на десятки миллисекунд, а доли плавать не должны: событие ставится
## на точный отсчёт внутри буфера. Побочная выгода — при просадке кадров
## музыка не сбивается с ритма.
##
## Расчёт идёт ВПЕРЁД окном упреждения: паттерн опрашивается блоками по
## пол-цикла, а не на каждый буфер. Опрос паттерна стоит заметно дороже
## самого сведения, и дробить его на сотни кусочков в цикле — впустую.

signal event_started(value: Dictionary, seconds_from_now: float)
signal voices_exhausted(wanted: int, limit: int)

## Циклов в секунду.
var cps := 0.5
## На сколько секунд вперёд считаются события.
var lookahead := 0.2
## Предел одновременно звучащих голосов.
var max_voices := 64

var mix_rate := 48000.0
var pattern: StrudelPattern = null
var bank: StrudelSampleBank = null
## Саундфонт для голосов вида `sf:<банк>:<программа>`.
var soundfont: StrudelSoundFont = null
## Пресеты webaudiofont для голосов `gm_*` (`@strudel/soundfonts`).
var gm_fonts: StrudelGMFonts = null

## Сколько раз пришлось вытеснять голос — видно в отладке, а не «молча».
var stolen_voices := 0
var played_events := 0
## Сколько отсчётов вышло за предел. Strudel лимитера НЕ имеет (проверено:
## superdoughoutput.mjs:194 — только громкость и выход), поэтому по умолчанию
## плагин ведёт себя так же. Но молча портить звук в игре нельзя, поэтому
## перегруз считается и о нём сообщают.
var clipped_frames := 0
## Мягкое ограничение на выходе. Выключено по умолчанию: с ним звук перестаёт
## быть побитово тем же, что в Strudel, а это цена сверки.
var master_limiter := false
## Зал и эхо орбит считает НЕ движок, а тот, кто его слушает: движок тогда
## лишь копит посылы (`orbit_send`), а сводит их штатный узел Godot на шине.
## Так устроен и Strudel — зал у него нативный узел браузера, а не скрипт.
## Выключено — зал и эхо считаются здесь, как в оффлайн-рендере, где шин нет.
var wet_external := false
## Где сейчас главный поток внутри движка. Пишется одним словом на стадию и
## читается сторожем из другого потока: когда игра виснет намертво, лог
## обрывается молча, и только эта метка говорит, В КАКОМ МЕСТЕ встали.
var stage := "idle"

var _voices: Array[StrudelVoice] = []
var _frames_written := 0
var _scheduled: Array = []
## События, поданные руками: играются в ближайшем же блоке.
var _instant: Array = []
## Сколько секунд считать зал и эхо ПОСЛЕ того, как на орбиту перестали
## посылать. Больше самого длинного хвоста: зал до 5.5 с, эхо до 2 с.
const TAIL_SEC := 8.0
var _sched_cycle_end := 0.0
var _sched_frame_end := 0
# Привязка «кадр ↔ цикл»: нужна, чтобы смена темпа не рвала такт.
var _anchor_frame := 0
var _anchor_cycle := 0.0

var _left := PackedFloat32Array()
var _right := PackedFloat32Array()
## Орбиты: у каждой СВОИ эхо и зал.
##
## 🔴 В Strudel эхо и зал живут не на игру, а на ОРБИТУ (`orbit`), и их
## настройки берутся у последнего события, которое туда пришло
## (`superdough.mjs:925`). Одна общая линия задержки на всё смешивала бы
## барабаны с клавишами: у них разное время эха.
var _orbits: Dictionary = {}

## Умолчания эха, пока никто не задал своих (`superdough.mjs:196`).
var delay_time := 0.25
var delay_feedback := 0.5


func _init() -> void:
	pass


func _orbit(index: int) -> Dictionary:
	## Орбита по номеру; заводится при первом обращении.
	if _orbits.has(index):
		return _orbits[index]
	var reverb := StrudelReverb.new()
	reverb.setup(mix_rate)
	var line := PackedFloat32Array()
	line.resize(maxi(int(mix_rate * 2.0), 1))
	var made := {
		"room": PackedFloat32Array(),
		"delay": PackedFloat32Array(),
		"line": line,
		"head": 0,
		"reverb": reverb,
		"time": delay_time,
		"feedback": delay_feedback,
	}
	_orbits[index] = made
	return made


func setup(rate: float) -> void:
	mix_rate = rate
	_voices.clear()
	for i in max_voices:
		_voices.append(StrudelVoice.new())
	_orbits.clear()
	reset_clock()


func reset_clock() -> void:
	_q_invalidate()
	_q_join()
	_instant.clear()
	# 🔴 ХВОСТЫ ОРБИТ ТОЖЕ СБРАСЫВАЮТСЯ. Голоса глушились, а в орбитах
	# оставались до двух секунд записанного эха и звенящие гребёнки зала —
	# и они звучали уже в СЛЕДУЮЩЕМ треке: линия задержки читалась ровно с
	# того места, где её бросили, и подмешивалась в выход независимо от того,
	# посылает ли туда что-нибудь новый паттерн. Правка терялась при переносе
	# соундфонтов — её держит тест `test_сброс_часов_уносит_хвост_эха`.
	for key in _orbits:
		var orb: Dictionary = _orbits[key]
		var line: PackedFloat32Array = orb["line"]
		line.fill(0.0)
		orb["head"] = 0
		var rev = orb.get("reverb")
		if rev != null and rev.has_method("setup"):
			rev.setup(mix_rate)
	clipped_frames = 0
	_frames_written = 0
	_scheduled.clear()
	_sched_cycle_end = 0.0
	_sched_frame_end = 0
	_anchor_frame = 0
	_anchor_cycle = 0.0
	stolen_voices = 0
	played_events = 0
	for v in _voices:
		v.active = false


func set_cps(new_cps: float) -> void:
	## Смена темпа на ходу: такт НЕ сбрасывается — новая скорость идёт от
	## текущего места, а не от нуля.
	if new_cps <= 0.0 or is_equal_approx(new_cps, cps):
		return
	_anchor_cycle = cycle_at_frame(_frames_written)
	_anchor_frame = _frames_written
	cps = new_cps
	# Всё, что было запланировано вперёд по старому темпу, пересчитываем.
	_q_invalidate()
	_scheduled.clear()
	_sched_cycle_end = _anchor_cycle
	_sched_frame_end = _frames_written


func set_pattern(new_pattern: StrudelPattern) -> void:
	## Живая замена: уже звучащие голоса доигрывают, такт не сбрасывается.
	pattern = new_pattern
	_q_invalidate()
	_scheduled.clear()
	_sched_cycle_end = cycle_at_frame(_frames_written)
	_sched_frame_end = _frames_written
	# Новый паттерн — сразу рабочему, чтобы к следующему `fill` был ответ.
	_q_request(_sched_cycle_end, _sched_cycle_end + _BLOCK_CYCLES)


func cycle_at_frame(frame: int) -> float:
	return _anchor_cycle + float(frame - _anchor_frame) / mix_rate * cps


func frame_at_cycle(cycle: float) -> int:
	return _anchor_frame + int((cycle - _anchor_cycle) / cps * mix_rate)


func current_cycle() -> float:
	return cycle_at_frame(_frames_written)


# ═══════════════════════════════════════════════════════════════════════════
# Планирование
# ═══════════════════════════════════════════════════════════════════════════

const _BLOCK_CYCLES := 0.5
## Блок, который считается НА МЕСТЕ, когда впрок ничего нет: после смены
## паттерна или темпа. Цена опроса растёт с длиной блока, и полцикла на
## главном потоке — это и был фриз (замерено 25–48 мс). Восьмушка цикла
## укладывается в кадр, а дальше блоки снова считает рабочий поток.
const _FIRST_BLOCK_CYCLES := 0.125

## ── ОПРОС ПАТТЕРНА В ФОНЕ ──────────────────────────────────────────────────
##
## 🔴 Опрос блока на полцикла вперёд стоил 30–50 мс НА ГЛАВНОМ ПОТОКЕ каждые
## полтора такта. Замер на целом треке: 31 пик за 45 с — ровно по числу
## полуциклов при 84 BPM; сведение при одном-четырёх голосах укладывалось в
## единицы миллисекунд. Дорог сам `query_arc` в GDScript: дроби, объекты
## событий, вложенные `arrange`/`stack`. На слух это микрофризы игры.
##
## Теперь блок считает рабочий поток, пока предыдущий звучит, а главный
## только забирает готовое. Опрос идёт ОДИН за раз: у паттернов есть
## статическое состояние (`_timelines`, `_last_voicing` в раскладках), и два
## одновременных опроса дрались бы за него — поэтому главный поток не
## опрашивает сам, пока жив рабочий, а ждёт его.
##
## Смена паттерна или темпа поднимает поколение: блок, посчитанный по
## старому, выбрасывается, и первый блок нового считается на месте.
## 🔴 ОПРОС ПАТТЕРНА — В СВОЁМ ПОТОКЕ, И ГЛАВНЫЙ ЕГО НИКОГДА НЕ ЖДЁТ.
## Раньше опрос уходил задачей в `WorkerThreadPool`, а главный поток ЖДАЛ её
## (`wait_for_task_completion`) перед каждым блоком. На плотном треке это
## стояние в кадре, а при подмене паттерна — ещё и два опроса разом (см. замок
## в `StrudelPattern.query_arc`). Теперь: постоянный поток, один слот заказа,
## один слот ответа; главный лишь кладёт заказ и забирает ответ, если он готов.
## Не готов — события подъедут следующим `fill` (опоздавшее играется сразу,
## это уже умеет `_render`). Синхронно главный опрашивает только когда впереди
## головки воспроизведения ПУСТО — при старте и после смены паттерна.
var _q_thread: Thread = null
var _q_wake := Semaphore.new()
var _q_quit := false
var _q_mutex := Mutex.new()
var _q_gen := 0
var _q_req: Dictionary = {}
var _q_res: Dictionary = {}
## Рабочий сигналит сюда о каждом готовом ответе. На это ждёт ТОЛЬКО
## оффлайн-рендер: там нет кадров, и подождать блок дешевле, чем считать его
## вдвоём. В реальном времени (`fill`) не ждёт никто и никогда.
var _q_done := Semaphore.new()
var _q_busy_c0 := -1.0
var _realtime := false
## Больше этого звука за один `fill` не считаем: после долгой просадки кадра
## буфер догоняется в несколько вызовов, а не одним рывком на полкадра.
const MAX_FILL_SEC := 0.25


func _query_block(pat: StrudelPattern, c0: float, c1: float) -> Array:
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		stage = "query:main %.3f-%.3f" % [c0, c1]
	## События с началом внутри [c0, c1): начало в циклах, длина в циклах.
	var out: Array = []
	# 🔴 ТЕМП ЕДЕТ В ЗАПРОС. `fit()`, `loopAt()` и прочие «уложить в круг»
	# считают скорость из `state.controls._cps` (`pattern.mjs:3711`). Без него
	# они брали умолчание, и брейк растягивался не в два круга, а как попало.
	for hap in pat.query_arc(c0, c1, {"_cps": cps}):
		if not hap.has_onset():
			continue
		var begin: float = hap.whole.begin.to_float()
		if begin < c0 or begin >= c1:
			continue
		out.append({"begin": begin, "value": hap.value,
			"dur": hap.duration().to_float()})
	return out


func _q_loop() -> void:
	## Тело потока опроса: ждать заказ, посчитать, положить ответ.
	while true:
		_q_wake.wait()
		if _q_quit:
			return
		_q_mutex.lock()
		var req := _q_req
		_q_req = {}
		if not req.is_empty():
			_q_busy_c0 = float(req["c0"])
		_q_mutex.unlock()
		if req.is_empty():
			continue
		var haps := _query_block(req["pat"], float(req["c0"]), float(req["c1"]))
		_q_mutex.lock()
		# Ответ на устаревший заказ (паттерн сменился) выбрасывается.
		if int(req["gen"]) == _q_gen:
			_q_res = {"c0": req["c0"], "c1": req["c1"], "haps": haps}
		_q_busy_c0 = -1.0
		_q_mutex.unlock()
		_q_done.post()


func _q_start() -> void:
	if _q_thread != null:
		return
	_q_quit = false
	_q_thread = Thread.new()
	_q_thread.start(_q_loop)


func _q_join() -> void:
	## Погасить поток опроса. Единственное место, где его ждут, — выключение.
	if _q_thread == null:
		return
	_q_quit = true
	_q_wake.post()
	_q_thread.wait_to_finish()
	_q_thread = null
	_q_mutex.lock()
	_q_req = {}
	_q_res = {}
	_q_busy_c0 = -1.0
	_q_mutex.unlock()


func shutdown() -> void:
	## Погасить рабочий поток. 🔴 Без этого игра падала на выходе: движок
	## освобождался, а задача опроса ещё считала по его паттерну.
	_q_invalidate()
	_q_join()


func _q_invalidate() -> void:
	## Паттерн или темп сменились: посчитанное впрок больше не годится.
	_q_mutex.lock()
	_q_gen += 1
	_q_req = {}
	_q_res = {}
	_q_mutex.unlock()


func _q_request(c0: float, c1: float) -> void:
	if pattern == null:
		return
	_q_start()
	_q_mutex.lock()
	var busy := not _q_req.is_empty() or _q_busy_c0 >= 0.0 \
		or (not _q_res.is_empty() and is_equal_approx(float(_q_res["c0"]), c0))
	if not busy:
		_q_req = {"pat": pattern, "c0": c0, "c1": c1, "gen": _q_gen}
	_q_mutex.unlock()
	if not busy:
		_q_wake.post()


func _q_take(c0: float, c1: float) -> Variant:
	## Готовый блок ровно на [c0, c1) нынешнего поколения, иначе null.
	if _q_thread == null:
		return null
	stage = "sched:take"
	if not _realtime:
		# Оффлайн: заказ на этот блок в работе — дождаться, а не считать вдвоём.
		while true:
			_q_mutex.lock()
			var pending := _q_res.is_empty() and (is_equal_approx(_q_busy_c0, c0) \
				or (not _q_req.is_empty() and is_equal_approx(float(_q_req["c0"]), c0)))
			_q_mutex.unlock()
			if not pending:
				break
			_q_done.wait()
	_q_mutex.lock()
	var ok := not _q_res.is_empty() and is_equal_approx(float(_q_res["c0"]), c0) \
		and is_equal_approx(float(_q_res["c1"]), c1)
	var res: Array = _q_res["haps"] if ok else []
	if ok:
		_q_res = {}
	_q_mutex.unlock()
	return res if ok else null


func _ensure_scheduled(until_frame: int, count_hint: int = 0) -> void:
	if pattern == null:
		return
	var guard := 0
	while _sched_frame_end < until_frame and guard < 64:
		guard += 1
		var c0 := _sched_cycle_end
		var c1 := c0 + _BLOCK_CYCLES
		var got: Variant = _q_take(c0, c1)
		var haps: Array
		if got != null:
			haps = got
		else:
			# Ответа нет. Синхронно считаем ТОЛЬКО если впереди головки
			# воспроизведения уже пусто — старт, смена паттерна, оффлайн.
			# Иначе не ждём: заказываем и выходим, события догонят следующим
			# `fill` (опоздавшее играется сразу).
			var starving := (not _realtime) or _sched_frame_end <= _frames_written + count_hint
			if not starving:
				break
			c1 = c0 + _FIRST_BLOCK_CYCLES
			stage = "sched:sync-query"
			haps = _query_block(pattern, c0, c1)
		for h in haps:
			_scheduled.append({
				"frame": frame_at_cycle(float(h["begin"])),
				"value": h["value"],
				"length": float(h["dur"]) / cps,
			})
		_sched_cycle_end = c1
		_sched_frame_end = frame_at_cycle(c1)
	stage = "sched:sort(%d)" % _scheduled.size()
	_scheduled.sort_custom(func(a, b): return int(a["frame"]) < int(b["frame"]))
	# Следующий блок — в фон, пока этот звучит.
	stage = "sched:request"
	_q_request(_sched_cycle_end, _sched_cycle_end + _BLOCK_CYCLES)


# ═══════════════════════════════════════════════════════════════════════════
# Сведение
# ═══════════════════════════════════════════════════════════════════════════

func trigger(value: Dictionary, length: float = 0.25) -> void:
	## Сыграть событие НЕМЕДЛЕННО, вне всякого паттерна.
	##
	## Тем же путём, что и нота трека: `StrudelVoiceBuilder` разбирает событие
	## и заводит голос, поэтому доступно ВСЁ — синтез, супер-пила, волновые
	## таблицы, сэмплы, `gm_*`, `sf:`, огибающие, фильтры, орбиты.
	##
	## Ради этого движок и разделён на часы и голоса: под руку игрока часов
	## нет, есть только нажатие. Событие ложится в ближайший блок звука, то
	## есть задержка равна размеру буфера — те же десятки миллисекунд, с
	## которыми играет и сам трек.
	##
	## Пример — звук капли, шаг интерфейса, нота героя в ритм-игре:
	## [codeblock]
	## engine.trigger({"s": "wt_epiano", "note": 60, "gain": 0.8}, 0.4)
	## [/codeblock]
	if value.is_empty():
		return
	_instant.append({"value": value, "length": maxf(length, 0.01)})


func fill(playback: AudioStreamGeneratorPlayback) -> int:
	## Досчитать звук до полного буфера. → сколько отсчётов легло.
	var available := playback.get_frames_available()
	if available <= 0:
		return 0
	# 🔴 ЦЕНА ОДНОГО ВЫЗОВА ОГРАНИЧЕНА. После просадки кадра буфер просит
	# сразу много; отдать всё одним рывком — значит съесть следующий кадр и
	# уйти в штопор. Догоняем частями.
	available = mini(available, int(MAX_FILL_SEC * mix_rate))
	_realtime = true
	stage = "fill:render(%d)" % available
	_render(available)
	stage = "fill:push"
	for i in available:
		playback.push_frame(Vector2(_left[i], _right[i]))
	_frames_written += available
	stage = "fill:done"
	return available


func orbit_ids() -> Array:
	## Номера орбит, которые уже завелись.
	return _orbits.keys()


func orbit_send(index: int, kind: String) -> PackedFloat32Array:
	## Посыл орбиты за последний блок: "room" или "delay". Только при
	## [member wet_external] — иначе посылы уже сведены в выход.
	var orb: Dictionary = _orbits.get(index, {})
	return orb.get(kind, PackedFloat32Array())


func orbit_settings(index: int) -> Dictionary:
	## Настройки зала и эха орбиты — те, что пришли из событий.
	var orb: Dictionary = _orbits.get(index, {})
	if orb.is_empty():
		return {}
	var rev := orb["reverb"] as StrudelReverb
	return {
		"decay": rev.decay_time,
		"fade": rev.fade_in,
		"lp_start": rev.lp_start,
		"lp_end": rev.lp_end,
		"delay_time": float(orb["time"]),
		"delay_feedback": float(orb["feedback"]),
	}


func render_block(count: int) -> Array:
	## Считает кусок звука и отдаёт его наружу: [левый, правый].
	##
	## Нужен не только для проигрывания — им же трек выводится в файл без
	## звуковой карты, а значит его можно сверить со спектром эталона и
	## прогнать в CI, где никакого устройства вывода нет.
	_render(count)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(count)
	r.resize(count)
	for i in count:
		l[i] = _left[i]
		r[i] = _right[i]
	_frames_written += count
	return [l, r]


func _render(count: int) -> void:
	if _left.size() < count:
		_left.resize(count)
		_right.resize(count)
	for i in count:
		_left[i] = 0.0
		_right[i] = 0.0

	_ensure_scheduled(_frames_written + count + int(lookahead * mix_rate), count)

	# Запуск событий, попавших в этот буфер, — на ТОЧНЫЙ отсчёт.
	while not _scheduled.is_empty():
		var next: Dictionary = _scheduled[0]
		var frame: int = next["frame"]
		if frame >= _frames_written + count:
			break
		_scheduled.pop_front()
		if frame < _frames_written:
			frame = _frames_written  # опоздавшее — играем сразу, а не теряем
		_trigger(next["value"], next["length"], frame - _frames_written, count)

	# Поданные руками события — в начало этого же блока.
	if not _instant.is_empty():
		var taken := _instant
		_instant = []
		for item in taken:
			_trigger(item["value"], float(item["length"]), 0, count)

	# 🔴 Шины орбит готовятся ПОСЛЕ запуска событий, а не до: событие может
	# завести НОВУЮ орбиту, и её буферы иначе остались бы пустыми — голос
	# писал бы в них и ронял смешивание.
	for key in _orbits:
		var orb0: Dictionary = _orbits[key]
		var rb: PackedFloat32Array = orb0["room"]
		var db: PackedFloat32Array = orb0["delay"]
		if rb.size() < count:
			rb.resize(count)
			db.resize(count)
			orb0["room"] = rb
			orb0["delay"] = db
		for i in count:
			rb[i] = 0.0
			db[i] = 0.0

	stage = "render:voices"
	for v in _voices:
		if v.active:
			var orb := _orbit(v.orbit)
			v.render(_left, _right, 0, count, orb["room"], orb["delay"])
	stage = "render:orbits"

	# 🔴 МОЛЧАЩАЯ ОРБИТА НЕ СЧИТАЕТСЯ. Зал и эхо крутились каждый буфер, даже
	# когда на орбиту давно ничего не приходит: замерено — движок, у которого
	# НОЛЬ живых голосов, продолжал съедать 1.76% реального времени после
	# единственной отзвучавшей ноты. Для второго движка (отклики героя, звуки
	# мира, интерфейс) это чистый фон впустую: он молчит почти всё время.
	#
	# Просто бросить счёт нельзя — у зала и эха ХВОСТ, он оборвётся щелчком.
	# Поэтому: пришёл звук — заводим хвост на TAIL_SEC; тишина — доигрываем
	# его и только потом засыпаем.
	for key in _orbits:
		if wet_external:
			# Посылы уже лежат в буферах орбиты — их заберёт слушатель.
			break
		var orb2: Dictionary = _orbits[key]
		var has_in := false
		var in_room: PackedFloat32Array = orb2["room"]
		var in_delay: PackedFloat32Array = orb2["delay"]
		for i in count:
			if in_room[i] != 0.0 or in_delay[i] != 0.0:
				has_in = true
				break
		var tail: int = int(orb2.get("tail", 0))
		if has_in:
			tail = int(TAIL_SEC * mix_rate)
		elif tail > 0:
			tail -= count
		orb2["tail"] = maxi(tail, 0)
		if not has_in and tail <= 0:
			continue
		_mix_delay(orb2, count)
		(orb2["reverb"] as StrudelReverb).render(orb2["room"], _left, _right, count)

	for i in count:
		var l: float = _left[i]
		var r: float = _right[i]
		if absf(l) > 1.0 or absf(r) > 1.0:
			clipped_frames += 1
			if master_limiter:
				# Мягкое ограничение: тише, но без хруста.
				_left[i] = l / (1.0 + absf(l) - 1.0) if absf(l) > 1.0 else l
				_right[i] = r / (1.0 + absf(r) - 1.0) if absf(r) > 1.0 else r


func _mix_delay(orb: Dictionary, count: int) -> void:
	var line: PackedFloat32Array = orb["line"]
	if line.is_empty():
		return
	var bus: PackedFloat32Array = orb["delay"]
	var size := line.size()
	var head: int = orb["head"]
	var offset := int(clampf(float(orb["time"]), 0.001, 1.9) * mix_rate)
	# 🔴 Отклик зажат по 0.98: при единице и выше эхо растёт само себя и
	# уходит в бесконечность. Так же зажимает Strudel.
	var fb := clampf(float(orb["feedback"]), 0.0, 0.98)
	for i in count:
		var read := (head - offset + size) % size
		var echoed: float = line[read]
		line[head] = bus[i] + echoed * fb
		# 🔴 ПЕРВОЕ ЭХО — В ПОЛНЫЙ ГОЛОС. В оригинале (`feedbackdelay.mjs`)
		# выход идёт через `delayGain` с весом `wet = 1`, а ослабление
		# `feedback` живёт только в петле. Здесь стояло `× 0.5`, взятое
		# ниоткуда: замерено, ряд эхо выходил 0.40 → 0.20 → 0.10 вместо
		# 0.80 → 0.40 → 0.20 при ударе 0.80 и обратной связи 0.5.
		_left[i] += echoed
		_right[i] += echoed
		head = (head + 1) % size
	orb["head"] = head


func _trigger(value: Variant, length: float, offset_in_buffer: int, count: int) -> void:
	if not value is Dictionary:
		return
	var voice := _take_voice()
	if voice == null:
		return
	stage = "trigger:configure(%s)" % str((value as Dictionary).get("s", "?"))
	StrudelVoiceBuilder.configure(voice, value, length, bank, mix_rate, soundfont, gm_fonts, cps)
	stage = "trigger:orbit"
	# Настройки эха и зала берёт ПОСЛЕДНЕЕ пришедшее на орбиту событие —
	# так же, как узлы в Strudel переиспользуются на орбиту.
	var dict: Dictionary = value
	var orb := _orbit(voice.orbit)
	if dict.has("delaytime"):
		orb["time"] = StrudelPattern._num(dict["delaytime"])
	elif dict.has("delaysync"):
		orb["time"] = StrudelPattern._num(dict["delaysync"]) / maxf(cps, 0.0001)
	if dict.has("delayfeedback"):
		orb["feedback"] = StrudelPattern._num(dict["delayfeedback"])
	var rev := orb["reverb"] as StrudelReverb
	if dict.has("roomsize") or dict.has("size") or dict.has("rsize"):
		var rs: Variant = dict.get("roomsize", dict.get("size", dict.get("rsize", 2.0)))
		rev.set_size(StrudelPattern._num(rs))
	if dict.has("roomfade") or dict.has("rfade"):
		rev.set_fade(StrudelPattern._num(dict.get("roomfade", dict.get("rfade", 0.0))))
	if dict.has("roomlp") or dict.has("roomdim"):
		rev.set_lowpass(StrudelPattern._num(dict.get("roomlp", 0.0)),
			StrudelPattern._num(dict.get("roomdim", 0.0)))
	voice.start(mix_rate)
	# Удар ставится на ТОЧНЫЙ отсчёт внутри буфера, а не на его границу:
	# иначе доли дрожали бы на размер буфера — это слышно как неровный ритм.
	voice.start_delay = clampi(offset_in_buffer, 0, count)
	played_events += 1
	event_started.emit(value, float(offset_in_buffer) / mix_rate)


func _take_voice() -> StrudelVoice:
	for v in _voices:
		if not v.active:
			return v
	# 🔴 Вытеснение ЯВНОЕ и считается. Молчаливая кража голоса — то, из-за
	# чего потом ищут несуществующий баг: ноты пропадают без следа.
	stolen_voices += 1
	voices_exhausted.emit(stolen_voices, max_voices)
	var oldest: StrudelVoice = _voices[0]
	for v in _voices:
		if v._pos > oldest._pos:
			oldest = v
	oldest.active = false
	return oldest


func active_voices() -> int:
	var n := 0
	for v in _voices:
		if v.active:
			n += 1
	return n
