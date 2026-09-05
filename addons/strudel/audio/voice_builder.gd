@tool
class_name StrudelVoiceBuilder
extends RefCounted

## Превращает значение события в настроенный голос.
##
## Здесь сходятся две стороны плагина: слева — словарь параметров, каким его
## выдал паттерн (`{s: "bd", n: 3, gain: 0.5, lpf: 600, …}`), справа — то, что
## умеет звучать.

## Умолчания Strudel (`superdough.mjs:185`) — не «на глаз», а из таблицы.
const DEFAULT_GAIN := 0.8
const DEFAULT_SOUND := "triangle"
## Приглушение синтеза перед огибающей (`synth.mjs:54`).
const SYNTH_ATTENUATION := 0.3

## Имена синтезов Strudel → источники голоса.
const SYNTHS := {
	"sine": StrudelVoice.Source.SINE,
	"sawtooth": StrudelVoice.Source.SAW,
	"saw": StrudelVoice.Source.SAW,
	"square": StrudelVoice.Source.SQUARE,
	"triangle": StrudelVoice.Source.TRIANGLE,
	"tri": StrudelVoice.Source.TRIANGLE,
	"white": StrudelVoice.Source.WHITE,
	"pink": StrudelVoice.Source.PINK,
	"brown": StrudelVoice.Source.BROWN,
	"supersaw": StrudelVoice.Source.SUPERSAW,
	# «user» — волна целиком из своих обертонов (`partials`).
	"user": StrudelVoice.Source.CUSTOM,
	"one": StrudelVoice.Source.SILENCE,
}

## Формы волны для голосов модуляции: имя → номер в голосе.
const FM_WAVES := {"sine": 0, "sawtooth": 1, "saw": 1, "square": 2,
	"triangle": 3, "tri": 3}


static func configure(voice: StrudelVoice, value: Dictionary, length: float,
		bank: StrudelSampleBank, mix_rate: float, soundfont: StrudelSoundFont = null,
		gm_fonts: StrudelGMFonts = null,
		cps: float = 0.5) -> void:
	var note_midi := _midi_of(value)
	voice.frequency = StrudelUtil.midi_to_freq(note_midi)
	# Умолчание громкости в Strudel — 0.8, а не единица (`superdough.mjs:186`).
	voice.gain = _num(value, "gain", DEFAULT_GAIN) * _num(value, "velocity", 1.0)
	voice.postgain = _num(value, "postgain", 1.0)
	# Панорамы нет, пока её не попросили: см. StrudelVoice.pan.
	voice.pan = clampf(_num(value, "pan", 0.5), 0.0, 1.0) if value.has("pan") else -1.0
	voice.speed = _num(value, "speed", 1.0)
	voice.lpf = _num(value, "cutoff", 0.0)
	voice.lpq = _num(value, "resonance", 1.0)
	voice.hpf = _num(value, "hcutoff", 0.0)
	voice.hpq = _num(value, "hresonance", 1.0)
	voice.bpf = _num(value, "bandf", 0.0)
	voice.bpq = _num(value, "bandq", 1.0)
	voice.vowel = StrudelUtil.text(value.get("vowel", ""))
	voice.crush = _num(value, "crush", 0.0)
	voice.coarse = _num(value, "coarse", 0.0)
	voice.shape = _num(value, "shape", 0.0)
	voice.room = _num(value, "room", 0.0)
	voice.delay_send = _num(value, "delay", 0.0)
	voice.orbit = int(_num(value, "orbit", 0.0))

	# ── перегруз ──
	voice.distort = _num(value, "distort", 0.0)
	voice.distortvol = _num(value, "distortvol", 1.0)
	voice.distort_type = StrudelVoice.distort_index(value.get("distorttype", 0))

	# ── тремоло ──
	# 🔴 `tremolosync` задаёт частоту В ДОЛЯХ КРУГА, а не в герцах: чтобы
	# качание держалось темпа, оно множится на круги в секунду.
	if value.has("tremolosync"):
		voice.tremolo = _num(value, "tremolosync", 0.0) * cps
	else:
		voice.tremolo = _num(value, "tremolo", 0.0)
	voice.tremolo_depth = _num(value, "tremolodepth", 1.0)
	voice.tremolo_skew = _num(value, "tremoloskew", -1.0) if value.has("tremoloskew") else -1.0
	voice.tremolo_shape = _shape_index(value.get("tremoloshape", null))
	voice.tremolo_phase = _num(value, "tremolophase", 0.0)

	# ── сжатие ──
	voice.compressor = _num(value, "compressor", NAN) if value.has("compressor") else NAN
	voice.compressor_ratio = _num(value, "compressorRatio", 10.0)
	voice.compressor_knee = _num(value, "compressorKnee", 10.0)
	voice.compressor_attack = _num(value, "compressorAttack", 0.005)
	voice.compressor_release = _num(value, "compressorRelease", 0.05)

	# ── фазер ──
	voice.phaser_rate = _num(value, "phaserrate", -1.0) if value.has("phaserrate") else -1.0
	voice.phaser_depth = _num(value, "phaserdepth", 0.75)
	voice.phaser_center = _num(value, "phasercenter", 1000.0)
	voice.phaser_sweep = _num(value, "phasersweep", 2000.0)

	# ── огибающие фильтров ──
	# ── синтез: своя волна, стая, модуляция ──
	voice.wave_partials = _list_of(value.get("partials", null))
	voice.wave_phases = _list_of(value.get("phases", null))
	voice.unison = int(_num(value, "unison", 5.0))
	# 🔴 Разброс стаи берётся из `detune`, а если его нет — из `n`, и только
	# потом из умолчания 0.18 (`synth.mjs:157`). Поэтому `s("supersaw").n(1)`
	# разводит голоса на полутон, а не выбирает сэмпл.
	if value.has("detune"):
		voice.freq_spread = _num(value, "detune", 0.18)
	elif value.has("n"):
		voice.freq_spread = _num(value, "n", 0.18)
	else:
		voice.freq_spread = 0.18
	voice.pan_spread = _num(value, "spread", 0.6)
	voice.vibrato = _num(value, "vib", 0.0)
	voice.vibrato_depth = _num(value, "vibmod", 0.5)
	voice.pitch_env = _pitch_env(value)
	var fm := _fm_matrix(value)
	voice.fm_sources = fm[0]
	voice.fm_routes = fm[1]

	voice.lp_env = _filter_env(value, "lp", "lpenv")
	voice.hp_env = _filter_env(value, "hp", "hpenv")
	voice.bp_env = _filter_env(value, "bp", "bpenv")
	voice.note_length = maxf(length, 0.01)
	voice.sample = PackedFloat32Array()
	voice.sample_loop = false
	voice.sample_loop_begin = 0.0
	voice.sample_loop_end = 0.0

	# Умолчание звука в Strudel — треугольник (`superdough.mjs:185`).
	var sound := StrudelUtil.text(value.get("s", value.get("sound", DEFAULT_SOUND)))
	var is_synth := sound == "" or SYNTHS.has(sound)
	var picked := {}

	# Голоса `gm_*` — пресеты webaudiofont, как `@strudel/soundfonts` в
	# Strudel: зона по диапазону клавиш, петля, высота в центах.
	if sound.begins_with("gm_") and gm_fonts != null and gm_fonts.has(sound):
		picked = gm_fonts.resolve(sound, int(_num(value, "n", 0.0)), note_midi)
		if not picked.is_empty():
			voice.envelope = StrudelEnvelope.from_values(
				value.get("attack"), value.get("decay"),
				value.get("sustain"), value.get("release")
			)
			voice.source = StrudelVoice.Source.SAMPLE
			voice.sample = picked["data"]
			voice.sample_rate = float(picked["rate"])
			voice.sample_loop = bool(picked.get("loop", false))
			voice.sample_loop_begin = float(picked.get("loop_begin", 0.0))
			voice.sample_loop_end = float(picked.get("loop_end", 0.0))
			voice.speed = voice.speed * float(picked.get("speed", 1.0))
			return

	# Саундфонт: адресация "sf:<банк>:<программа>", как в Strudel.
	if sound.begins_with("sf:") and soundfont != null and soundfont.loaded:
		var parts := sound.split(":")
		var sf_bank := int(parts[1]) if parts.size() > 1 else 0
		var sf_program := int(parts[2]) if parts.size() > 2 else 0
		picked = soundfont.resolve(sf_bank, sf_program, note_midi)
		if not picked.is_empty():
			voice.envelope = StrudelEnvelope.from_values(
				value.get("attack"), value.get("decay"),
				value.get("sustain"), value.get("release")
			)
			voice.source = StrudelVoice.Source.SAMPLE
			voice.sample = picked["data"]
			voice.sample_rate = float(picked["rate"])
			voice.sample_loop = bool(picked.get("loop", false))
			voice.speed = voice.speed * float(picked.get("speed", 1.0))
			# Собственное ослабление пресета — в децибелах, как в SF2.
			voice.gain *= db_to_linear(float(picked.get("attenuation_db", 0.0)))
			return

	if not is_synth and bank != null and not bank.is_empty():
		picked = bank.resolve(
			sound,
			int(_num(value, "n", 0.0)),
			StrudelUtil.text(value.get("bank", "")),
			note_midi
		)

	if picked.is_empty():
		# Синтез — сам по себе, либо потому что сэмпла нет. Пустой банк это
		# ШТАТНОЕ состояние (мобильная сборка, свежая установка).
		voice.source = SYNTHS.get(sound, StrudelVoice.Source.TRIANGLE)
		# 🔴 Свои обертоны ПРЕВРАЩАЮТ любой из встроенных видов в свою волну:
		# вид задаёт исходные коэффициенты, `partials` их множит
		# (`synth.mjs:503`). Без обертонов «user» звучал бы тишиной, поэтому
		# оригинал подменяет его треугольником — делаем так же.
		if not voice.wave_partials.is_empty():
			voice.wave_base_kind = _wave_kind_of(sound)
			voice.source = StrudelVoice.Source.CUSTOM
		elif voice.source == StrudelVoice.Source.CUSTOM:
			push_warning("Strudel: у синтеза \"user\" не заданы partials — играю треугольник")
			voice.source = StrudelVoice.Source.TRIANGLE
		# 🔴 Синтез в Strudel ПРИГЛУШЁН на 0.3 (`synth.mjs:54`, «turn down»),
		# и огибающая у него своя. Без этих двух вещей синтез выходит на
		# одиннадцать децибел громче эталона — замерено сверкой звука.
		voice.gain *= SYNTH_ATTENUATION
		voice.envelope = StrudelEnvelope.from_values(
			value.get("attack"), value.get("decay"),
			value.get("sustain"), value.get("release"),
			StrudelEnvelope.SYNTH_DEFAULTS
		)
		return

	voice.envelope = StrudelEnvelope.from_values(
		value.get("attack"), value.get("decay"),
		value.get("sustain"), value.get("release")
	)
	voice.source = StrudelVoice.Source.SAMPLE
	voice.sample = picked["data"]
	voice.sample_rate = float(picked["rate"])
	# Растяжка по высоте у многосэмплированных складывается со .speed().
	voice.speed = voice.speed * float(picked.get("speed", 1.0))


static func _midi_of(value: Dictionary) -> float:
	if value.has("freq"):
		return StrudelUtil.freq_to_midi(float(value["freq"]))
	if value.has("note"):
		var n = value["note"]
		if n is String or n is StringName:
			return float(StrudelUtil.note_to_midi(String(n)))
		return float(n)
	# `n` без ноты — это индекс сэмпла, а не высота: высота тогда средняя.
	return 60.0


static func _num(value: Dictionary, key: String, fallback: float) -> float:
	if not value.has(key):
		return fallback
	var v = value[key]
	if v is int or v is float:
		return float(v)
	if v is String or v is StringName:
		var s := String(v)
		return s.to_float() if s.is_valid_float() else fallback
	if v is bool:
		return 1.0 if v else 0.0
	return fallback


## Умолчания огибающей ФИЛЬТРА — свои, не такие, как у громкости
## (`helpers.mjs:266`): короткая атака, заметный спад, нулевое удержание.
const FILTER_ADSR := [0.005, 0.14, 0.0, 0.1]


static func _filter_env(value: Dictionary, prefix: String, env_key: String) -> Array:
	## → [величина, атака, спад, удержание, отпускание, якорь] либо пусто.
	##
	## 🔴 Огибающая включается, если задано ХОТЬ ЧТО-ТО из неё, включая сам
	## `lpenv`. Иначе срез стоит на месте.
	var keys := [env_key, prefix + "attack", prefix + "decay",
		prefix + "sustain", prefix + "release"]
	var any := false
	for k in keys:
		if value.has(k):
			any = true
			break
	if not any:
		return []
	var a: Variant = value.get(prefix + "attack", null)
	var d: Variant = value.get(prefix + "decay", null)
	var s: Variant = value.get(prefix + "sustain", null)
	var r: Variant = value.get(prefix + "release", null)
	var adsr := _adsr_values(a, d, s, r)
	return [
		_num(value, env_key, 1.0),
		adsr[0], adsr[1], adsr[2], adsr[3],
		_num(value, "fanchor", 0.0),
	]


static func _adsr_values(a: Variant, d: Variant, s: Variant, r: Variant) -> Array:
	## Перенос `getADSRValues` для фильтров: ничего не задано — умолчания;
	## задана только атака — удержание в единице; иначе почти в нуле.
	const ENV_MIN := 0.001
	const RELEASE_MIN := 0.01
	if a == null and d == null and s == null and r == null:
		return FILTER_ADSR
	var sustain: float
	if s != null:
		sustain = StrudelPattern._num(s)
	elif (a != null and d == null) or (a == null and d == null):
		sustain = 1.0
	else:
		sustain = ENV_MIN
	return [
		maxf(StrudelPattern._num(a) if a != null else 0.0, ENV_MIN),
		maxf(StrudelPattern._num(d) if d != null else 0.0, ENV_MIN),
		minf(sustain, 1.0),
		maxf(StrudelPattern._num(r) if r != null else 0.0, RELEASE_MIN),
	]


## Формы качания по именам — те же номера, что в `worklets.mjs:72`.
const SHAPE_NAMES := {"tri": 0, "triangle": 0, "sine": 1, "ramp": 2, "saw": 3,
	"square": 4}


static func _shape_index(v: Variant) -> int:
	## → номер формы, −1 если форму не задавали.
	if v == null:
		return -1
	if v is String or v is StringName:
		return int(SHAPE_NAMES.get(String(v), 0))
	return StrudelUtil.mod_i(int(StrudelPattern._num(v)), 5)


static func _wave_kind_of(sound: String) -> int:
	match sound:
		"sawtooth", "saw": return StrudelWavetable.Kind.SAW
		"square": return StrudelWavetable.Kind.SQUARE
		"triangle", "tri": return StrudelWavetable.Kind.TRIANGLE
	return StrudelWavetable.Kind.USER


static func _list_of(v: Variant) -> Array:
	if v is Array:
		return v
	if v == null:
		return []
	return [v]


## Умолчания огибающей ВЫСОТЫ (`helpers.mjs:349`): долгая атака, мгновенный
## спад — так получается «взлёт», а не щелчок.
const PITCH_ADSR := [0.2, 0.001, 1.0, 0.001]


static func _pitch_env(value: Dictionary) -> Array:
	## → [полутонов, атака, спад, удержание, отпускание, якорь, показательно].
	var keys := ["penv", "pattack", "pdecay", "psustain", "prelease"]
	var any := false
	for k in keys:
		if value.has(k):
			any = true
			break
	if not any:
		return []
	var adsr := _adsr_or(value, "p", PITCH_ADSR)
	# 🔴 Якорь по умолчанию РАВЕН УДЕРЖАНИЮ, а не нулю: иначе нота в покое
	# уезжала бы по высоте.
	var anchor := _num(value, "panchor", adsr[2])
	var expo := int(_num(value, "pcurve", 0.0)) != 0
	return [_num(value, "penv", 1.0), adsr[0], adsr[1], adsr[2], adsr[3],
		anchor, expo]


static func _adsr_or(value: Dictionary, prefix: String, defaults: Array) -> Array:
	return _adsr_values(
		value.get(prefix + "attack", null), value.get(prefix + "decay", null),
		value.get(prefix + "sustain", null), value.get(prefix + "release", null)
	) if (value.has(prefix + "attack") or value.has(prefix + "decay")
		or value.has(prefix + "sustain") or value.has(prefix + "release")) else defaults


static func _fm_matrix(value: Dictionary) -> Array:
	## Разбор восьми голосов модуляции и связей между ними.
	##
	## 🔴 Связь `fmi` без цифр — это «первый голос качает саму ноту».
	## Пара цифр `fmi<откуда><куда>` задаёт любую другую: ноль в «куда»
	## снова значит саму ноту. Так устроена матрица в `applyFM`.
	var sources: Array = []
	var index_of: Dictionary = {}
	var routes: Array = []
	for i in range(1, 9):
		for j in range(0, 9):
			var control := ""
			if i == j + 1:
				control = "fmi" if i == 1 else "fmi%d" % i
			else:
				control = "fmi%d%d" % [i, j]
			if not value.has(control):
				continue
			var amt := _num(value, control, 0.0)
			if amt == 0.0:
				continue
			var from_i := _fm_source(sources, index_of, i, value)
			var to_i := 0
			if j > 0:
				to_i = _fm_source(sources, index_of, j, value) + 1
			routes.append([from_i, to_i, amt])
	return [sources, routes]


static func _fm_source(sources: Array, index_of: Dictionary, n: int,
		value: Dictionary) -> int:
	if index_of.has(n):
		return index_of[n]
	var suffix := "" if n == 1 else str(n)
	var adsr: Array = []
	var keys := ["fmattack" + suffix, "fmdecay" + suffix, "fmsustain" + suffix,
		"fmrelease" + suffix]
	var any := false
	for k in keys:
		if value.has(k):
			any = true
			break
	if any:
		var v := _adsr_values(value.get(keys[0], null), value.get(keys[1], null),
			value.get(keys[2], null), value.get(keys[3], null))
		# `fmenv` выбирает вид перехода: «exp» (по умолчанию) или «lin».
		var kind := StrudelUtil.text(value.get("fmenv" + suffix, "exp"))
		adsr = [v[0], v[1], v[2], v[3], kind != "lin"]
	var wave_name := StrudelUtil.text(value.get("fmwave" + suffix, "sine"))
	var idx := sources.size()
	sources.append({
		"ratio": _num(value, "fmh" + suffix, 1.0),
		"wave": int(FM_WAVES.get(wave_name, 0)),
		"adsr": adsr,
	})
	index_of[n] = idx
	return idx
