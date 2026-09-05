@tool
class_name StrudelGMFonts
extends RefCounted

## Голоса `gm_*` — перенос `@strudel/soundfonts` (`fontloader.mjs`).
##
## В Strudel имена вида `gm_acoustic_bass` — это не саундфонт SF2, а пресеты
## webaudiofont: файл `.js` с зонами, в каждой — mp3 в base64, высота записи в
## центах, диапазон клавиш, петля. Список пресетов на имя — `gm.mjs` (здесь
## `soundfonts/gm_presets.json`); `.n(k)` выбирает k-й пресет списка.
##
## 🔴 Сети нет: пресеты лежат ЛОКАЛЬНО в папке, указанной в
## [member StrudelPlayer.gm_fonts_path], под своими именами
## (`0320_JCLive_sf2_file.js`). Скачать их — забота проекта.
##
## Что воспроизведено из fontloader.mjs один в один:
##   зона — по ДИАПАЗОНУ клавиш (`keyRangeLow <= midi <= keyRangeHigh + 1`),
##     первая подходящая, а не ближайшая по высоте;
##   скорость — `2^((100·midi − baseDetune) / 1200)`,
##     `baseDetune = originalPitch − 100·coarseTune − fineTune`;
##   петля — если `loopStart > 1` и `loopStart < loopEnd`, границы в секундах
##     `loopStart / sampleRate` зоны;
##   огибающая — ADSR из паттерна с умолчаниями сэмплера (`getADSRValues`).

const PRESETS_PATH := "res://addons/strudel/soundfonts/gm_presets.json"

## имя → список пресетов
var presets: Dictionary = {}
## пресет → массив зон {lo, hi, pitch_cents, coarse, fine, rate, loop_start, loop_end, bytes/data}
var _zones: Dictionary = {}
var _folder := ""
var _missing: Dictionary = {}
var loaded := false


func load_folder(path: String) -> int:
	## Папка с `.js`-пресетами. → сколько пресетов нашлось на диске.
	_folder = path
	var f := FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if f == null:
		push_warning("Strudel: нет списка пресетов %s" % PRESETS_PATH)
		return 0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		presets = parsed
	var found := 0
	for name in presets:
		for preset in presets[name]:
			if FileAccess.file_exists(_folder.path_join(String(preset) + ".js")):
				found += 1
	loaded = found > 0
	return found


func has(name: String) -> bool:
	## Есть ли такое имя `gm_*` и хотя бы один его пресет на диске.
	if not presets.has(name):
		return false
	for preset in presets[name]:
		if FileAccess.file_exists(_folder.path_join(String(preset) + ".js")):
			return true
	return false


func resolve(name: String, index: int, midi: float) -> Dictionary:
	## → {data, rate, speed, loop, loop_begin, loop_end} либо пустой словарь.
	var list: Array = presets.get(name, [])
	if list.is_empty():
		return {}
	# `.n(k)` — k-й пресет списка по кругу (`getSoundIndex`).
	var preset := String(list[StrudelUtil.mod_i(index, list.size())])
	var zones := _preset_zones(preset)
	if zones.is_empty():
		return {}
	var zone: Dictionary = {}
	for z in zones:
		if float(z["lo"]) <= midi and float(z["hi"]) + 1.0 >= midi:
			zone = z
			break
	if zone.is_empty():
		return {}
	var data: PackedFloat32Array = _zone_pcm(zone)
	if data.is_empty():
		return {}
	var base_detune: float = float(zone["pitch_cents"]) - 100.0 * float(zone["coarse"]) - float(zone["fine"])
	var speed := pow(2.0, (100.0 * midi - base_detune) / 1200.0)
	var out := {"data": data, "rate": float(AudioServer.get_mix_rate()), "speed": speed, "loop": false}
	var ls := float(zone["loop_start"])
	var le := float(zone["loop_end"])
	if ls > 1.0 and ls < le:
		var zr := maxf(float(zone["rate"]), 1.0)
		out["loop"] = true
		out["loop_begin"] = ls / zr * float(AudioServer.get_mix_rate())
		out["loop_end"] = le / zr * float(AudioServer.get_mix_rate())
	return out


func _preset_zones(preset: String) -> Array:
	if _zones.has(preset):
		return _zones[preset]
	var path := _folder.path_join(preset + ".js")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		if not _missing.has(preset):
			_missing[preset] = true
			push_warning("Strudel: пресета «%s.js» нет в %s — имя gm_* играет тишиной" % [preset, _folder])
		_zones[preset] = []
		return []
	var text := f.get_as_text()
	f.close()
	var zones: Array = []
	# Зона — блок `{ … file:'…' … }`. Порядок полей внутри произвольный.
	var block_re := RegEx.create_from_string("\\{[^{}]*?file:'[^']*'[^{}]*?\\}")
	for m in block_re.search_all(text):
		var b := m.get_string()
		zones.append({
			"lo": _field(b, "keyRangeLow", 0.0),
			"hi": _field(b, "keyRangeHigh", 127.0),
			"pitch_cents": _field(b, "originalPitch", 6000.0),
			"coarse": _field(b, "coarseTune", 0.0),
			"fine": _field(b, "fineTune", 0.0),
			"rate": _field(b, "sampleRate", 44100.0),
			"loop_start": _field(b, "loopStart", -1.0),
			"loop_end": _field(b, "loopEnd", -1.0),
			"file": _text_field(b, "file"),
			"data": PackedFloat32Array(),
		})
	_zones[preset] = zones
	return zones


func _zone_pcm(zone: Dictionary) -> PackedFloat32Array:
	## mp3/ogg из base64 → отсчёты на частоте движка. Разбирается один раз.
	var cached: PackedFloat32Array = zone["data"]
	if not cached.is_empty():
		return cached
	var bytes := Marshalls.base64_to_raw(String(zone["file"]))
	if bytes.is_empty():
		return PackedFloat32Array()
	var stream: AudioStream = null
	if bytes.size() > 4 and bytes.slice(0, 4).get_string_from_ascii() == "OggS":
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	else:
		stream = AudioStreamMP3.load_from_buffer(bytes)
	if stream == null:
		return PackedFloat32Array()
	var pcm := StrudelSampleBank._decode_stream(stream)
	zone["data"] = pcm
	zone["file"] = ""            # base64 больше не нужен
	return pcm


static func _field(block: String, key: String, fallback: float) -> float:
	var re := RegEx.create_from_string(key + "\\s*:\\s*(-?[0-9.]+)")
	var m := re.search(block)
	return float(m.get_string(1)) if m != null else fallback


static func _text_field(block: String, key: String) -> String:
	var re := RegEx.create_from_string(key + "\\s*:\\s*'([^']*)'")
	var m := re.search(block)
	return m.get_string(1) if m != null else ""
