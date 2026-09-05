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

var _voices: Array[StrudelVoice] = []
var _frames_written := 0
var _scheduled: Array = []
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
var _q_task := -1
var _q_gen := 0
var _q_mutex := Mutex.new()
var _q_c0 := 0.0
var _q_c1 := 0.0
var _q_gen_done := -1
var _q_out: Array = []


func _query_block(pat: StrudelPattern, c0: float, c1: float) -> Array:
	## События с началом внутри [c0, c1): начало в циклах, длина в циклах.
	var out: Array = []
	for hap in pat.query_arc(c0, c1):
		if not hap.has_onset():
			continue
		var begin: float = hap.whole.begin.to_float()
		if begin < c0 or begin >= c1:
			continue
		out.append({"begin": begin, "value": hap.value,
			"dur": hap.duration().to_float()})
	return out


func _q_worker(pat: StrudelPattern, c0: float, c1: float, gen: int) -> void:
	var res := _query_block(pat, c0, c1)
	_q_mutex.lock()
	if gen == _q_gen:
		_q_out = res
		_q_c0 = c0
		_q_c1 = c1
		_q_gen_done = gen
	_q_mutex.unlock()


func _q_join() -> void:
	## Дождаться рабочего, если он ещё считает.
	if _q_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_q_task)
		_q_task = -1


func shutdown() -> void:
	## Погасить рабочий поток. 🔴 Без этого игра падала на выходе: движок
	## освобождался, а задача опроса ещё считала по его паттерну.
	_q_invalidate()
	_q_join()


func _q_invalidate() -> void:
	## Паттерн или темп сменились: посчитанное впрок больше не годится.
	_q_gen += 1


func _q_request(c0: float, c1: float) -> void:
	if _q_task >= 0 or pattern == null:
		return
	_q_task = WorkerThreadPool.add_task(_q_worker.bind(pattern, c0, c1, _q_gen),
		false, "Strudel: опрос паттерна")


func _q_take(c0: float, c1: float) -> Variant:
	## Готовый блок ровно на [c0, c1) нынешнего поколения, иначе null.
	if _q_task < 0:
		return null
	_q_join()
	_q_mutex.lock()
	var ok := _q_gen_done == _q_gen and is_equal_approx(_q_c0, c0) \
		and is_equal_approx(_q_c1, c1)
	var res: Array = _q_out if ok else []
	_q_mutex.unlock()
	return res if ok else null


func _ensure_scheduled(until_frame: int) -> void:
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
			# Впрок ничего нет (первый блок, или паттерн только что сменился):
			# считаем на месте, но КОРОТКИЙ кусок — он влезает в кадр. Рабочий
			# к этому моменту уже остановлен: опрос не ведётся вдвоём.
			_q_join()
			c1 = c0 + _FIRST_BLOCK_CYCLES
			haps = _query_block(pattern, c0, c1)
		for h in haps:
			_scheduled.append({
				"frame": frame_at_cycle(float(h["begin"])),
				"value": h["value"],
				"length": float(h["dur"]) / cps,
			})
		_sched_cycle_end = c1
		_sched_frame_end = frame_at_cycle(c1)
	_scheduled.sort_custom(func(a, b): return int(a["frame"]) < int(b["frame"]))
	# Следующий блок — в фон, пока этот звучит.
	_q_request(_sched_cycle_end, _sched_cycle_end + _BLOCK_CYCLES)


# ═══════════════════════════════════════════════════════════════════════════
# Сведение
# ═══════════════════════════════════════════════════════════════════════════

func fill(playback: AudioStreamGeneratorPlayback) -> void:
	var available := playback.get_frames_available()
	if available <= 0:
		return
	_render(available)
	for i in available:
		playback.push_frame(Vector2(_left[i], _right[i]))
	_frames_written += available


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

	_ensure_scheduled(_frames_written + count + int(lookahead * mix_rate))

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

	for v in _voices:
		if v.active:
			var orb := _orbit(v.orbit)
			v.render(_left, _right, 0, count, orb["room"], orb["delay"])

	for key in _orbits:
		var orb2: Dictionary = _orbits[key]
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
		_left[i] += echoed * 0.5
		_right[i] += echoed * 0.5
		head = (head + 1) % size
	orb["head"] = head


func _trigger(value: Variant, length: float, offset_in_buffer: int, count: int) -> void:
	if not value is Dictionary:
		return
	var voice := _take_voice()
	if voice == null:
		return
	StrudelVoiceBuilder.configure(voice, value, length, bank, mix_rate, soundfont, gm_fonts, cps)
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
