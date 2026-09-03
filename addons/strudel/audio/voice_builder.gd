@tool
class_name StrudelVoiceBuilder
extends RefCounted

## Превращает значение события в настроенный голос.
##
## Здесь сходятся две стороны плагина: слева — словарь параметров, каким его
## выдал паттерн (`{s: "bd", n: 3, gain: 0.5, lpf: 600, …}`), справа — то, что
## умеет звучать.

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
		bank: StrudelSampleBank, mix_rate: float) -> void:
	var note_midi := _midi_of(value)
	voice.frequency = StrudelUtil.midi_to_freq(note_midi)
	voice.gain = _num(value, "gain", 1.0) * _num(value, "velocity", 1.0)
	voice.postgain = _num(value, "postgain", 1.0)
	voice.pan = clampf(_num(value, "pan", 0.5), 0.0, 1.0)
	voice.speed = _num(value, "speed", 1.0)
	voice.lpf = _num(value, "cutoff", 0.0)
	voice.lpq = _num(value, "resonance", 1.0)
	voice.hpf = _num(value, "hcutoff", 0.0)
	voice.hpq = _num(value, "hresonance", 1.0)
	voice.crush = _num(value, "crush", 0.0)
	voice.coarse = _num(value, "coarse", 0.0)
	voice.shape = _num(value, "shape", 0.0)
	voice.room = _num(value, "room", 0.0)
	voice.delay_send = _num(value, "delay", 0.0)
	voice.orbit = int(_num(value, "orbit", 0.0))
	voice.note_length = maxf(length, 0.01)
	voice.envelope = StrudelEnvelope.from_values(
		value.get("attack"), value.get("decay"),
		value.get("sustain"), value.get("release")
	)
	voice.sample = PackedFloat32Array()
	voice.sample_loop = false

	var sound := String(value.get("s", value.get("sound", "")))
	if sound == "":
		# Ноты без явного звука Strudel играет треугольником.
		voice.source = StrudelVoice.Source.TRIANGLE
		return
	if SYNTHS.has(sound):
		voice.source = SYNTHS[sound]
		return

	# Сэмпл
	if bank == null or bank.is_empty():
		# Пустой банк — ШТАТНОЕ состояние: играем синтезом, а не молчим.
		voice.source = StrudelVoice.Source.TRIANGLE
		return
	var picked := bank.resolve(
		sound,
		int(_num(value, "n", 0.0)),
		String(value.get("bank", "")),
		note_midi
	)
	if picked.is_empty():
		voice.source = StrudelVoice.Source.TRIANGLE
		return
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
