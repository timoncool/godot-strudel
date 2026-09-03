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
}


static func configure(voice: StrudelVoice, value: Dictionary, length: float,
		bank: StrudelSampleBank, mix_rate: float, soundfont: StrudelSoundFont = null,
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
	voice.lp_env = _filter_env(value, "lp", "lpenv")
	voice.hp_env = _filter_env(value, "hp", "hpenv")
	voice.bp_env = _filter_env(value, "bp", "bpenv")
	voice.note_length = maxf(length, 0.01)
	voice.sample = PackedFloat32Array()
	voice.sample_loop = false

	# Умолчание звука в Strudel — треугольник (`superdough.mjs:185`).
	var sound := StrudelUtil.text(value.get("s", value.get("sound", DEFAULT_SOUND)))
	var is_synth := sound == "" or SYNTHS.has(sound)
	var picked := {}

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
