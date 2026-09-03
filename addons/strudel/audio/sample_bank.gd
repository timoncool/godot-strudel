@tool
class_name StrudelSampleBank
extends RefCounted

## Банк сэмплов: своя папка пользователя плюс карты формата Strudel.
##
## 🔴 Сети здесь нет и не будет. Strudel тянет сэмплы по ссылкам из карт —
## плагин берёт ТОЛЬКО локальные файлы: путь `_base` считается папкой рядом с
## картой, а не адресом.
##
## Формат карт — тот же, что у Strudel (`strudel.json`, `vcsl.json`,
## `tidal-drum-machines.json`, `piano.json`):
##
##   {"bd": ["bd/kick.wav", "bd/kick2.wav"]}        — индекс выбирается через :n
##   {"piano": {"C4": "C4.wav", "A4": "A4.wav"}}    — многосэмплированный
##   {"_base": "подпапка/"}                          — общий префикс
##
## Пустой банк — ШТАТНОЕ состояние (мобильная сборка, свежая установка):
## плагин не падает, а честно сообщает и играет синтезом.

## имя → {files: [пути], pitched: {midi: путь}}
var entries: Dictionary = {}
## Уже разобранные в PCM сэмплы: путь → PackedFloat32Array
var _cache: Dictionary = {}
var _rates: Dictionary = {}
## Что не удалось загрузить — говорим один раз, а не на каждую ноту.
var _complained: Dictionary = {}

var root_path := ""


func is_empty() -> bool:
	return entries.is_empty()


func count() -> int:
	return entries.size()


## Какие звуковые файлы берутся из папки. WAV разбирается сам, ogg и mp3 —
## через проигрыватель движка.
const AUDIO_EXTS := ["wav", "ogg", "mp3"]


func load_folder(path: String) -> int:
	## Загружает все карты (*.json) и все звуки из папки. → сколько имён вышло.
	root_path = path
	entries.clear()
	_cache.clear()
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Strudel: папки сэмплов нет — %s. Играю синтезом." % path)
		return 0

	# 1) карты формата Strudel
	for file in _list(path, [".json"]):
		_load_map(file)
	var from_maps := {}
	for key in entries:
		from_maps[key] = true
	# 2) отдельные звуки: имя папки или файла становится именем инструмента.
	# 🔴 Только то, чего НЕТ в картах: иначе один и тот же звук попадает в
	# список дважды, и `bd:1` начинает указывать не на тот файл.
	_scan_audio(path, "", from_maps)
	return entries.size()


func _list(path: String, suffixes: Array) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			for suffix in suffixes:
				if name.to_lower().ends_with(suffix):
					out.append(path.path_join(name))
					break
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _scan_audio(path: String, prefix: String, skip: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var touched := {}
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_audio(full, name, skip)
		elif AUDIO_EXTS.has(name.get_extension().to_lower()):
			var key := prefix if prefix != "" else name.get_basename()
			if not skip.has(key):
				if not entries.has(key):
					entries[key] = {"files": [], "pitched": {}}
				(entries[key]["files"] as Array).append(full)
				touched[key] = true
		name = dir.get_next()
	dir.list_dir_end()
	for key in touched:
		(entries[key]["files"] as Array).sort()


func _load_map(json_path: String) -> void:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_warning("Strudel: карта сэмплов не разобралась — %s" % json_path)
		return
	var map: Dictionary = parsed
	var base := String(map.get("_base", ""))
	# `_base` в оригинале — ссылка. Здесь это ПАПКА рядом с картой: сети нет.
	if base.begins_with("http"):
		base = ""
	var folder := json_path.get_base_dir()
	if base != "":
		folder = folder.path_join(base)

	for key in map:
		var k := String(key)
		if k.begins_with("_"):
			continue
		var value = map[key]
		var entry := {"files": [], "pitched": {}}
		if value is Array:
			for item in value:
				entry["files"].append(folder.path_join(_decode(String(item))))
		elif value is Dictionary:
			for note in value:
				var midi := StrudelUtil.note_to_midi(String(note), 3)
				entry["pitched"][midi] = folder.path_join(_decode(String(value[note])))
		else:
			continue
		entries[k] = entry


static func _decode(text: String) -> String:
	## В картах Strudel пути закодированы как в ссылке (%20 вместо пробела).
	return text.uri_decode()


# ═══════════════════════════════════════════════════════════════════════════
# Выбор звука
# ═══════════════════════════════════════════════════════════════════════════

func resolve(name: String, index: int, bank_name: String, midi_note: float) -> Dictionary:
	## → {data, rate, speed} либо пустой словарь, если звука нет.
	var key := name
	if bank_name != "":
		# Так адресуются наборы: bank("RolandTR909") + s("bd") → RolandTR909_bd
		var joined := bank_name + "_" + name
		if entries.has(joined):
			key = joined
		elif entries.has(bank_name.to_lower() + "_" + name):
			key = bank_name.to_lower() + "_" + name
	if not entries.has(key):
		return {}

	var entry: Dictionary = entries[key]
	var pitched: Dictionary = entry["pitched"]
	if not pitched.is_empty():
		# Многосэмплированный: берём ближайшую записанную высоту
		# и растягиваем её по частоте — как это делает Strudel.
		var best_midi := 0
		var best_diff := 1e9
		for m in pitched:
			var diff: float = absf(float(m) - midi_note)
			if diff < best_diff:
				best_diff = diff
				best_midi = int(m)
		var data := _pcm(String(pitched[best_midi]))
		if data.is_empty():
			return {}
		return {
			"data": data,
			"rate": float(_rates.get(String(pitched[best_midi]), 48000.0)),
			"speed": pow(2.0, (midi_note - float(best_midi)) / 12.0),
		}

	var files: Array = entry["files"]
	if files.is_empty():
		return {}
	var path := String(files[StrudelUtil.mod_i(index, files.size())])
	var pcm := _pcm(path)
	if pcm.is_empty():
		return {}
	return {"data": pcm, "rate": float(_rates.get(path, 48000.0)), "speed": 1.0}


func pcm_of(path: String) -> PackedFloat32Array:
	## Отсчёты файла по пути. Открытая дверь для проверок и для игры,
	## которой понадобился сэмпл сам по себе.
	return _pcm(path)


func rate_of(path: String) -> float:
	## Частота дискретизации файла. Читается ПОСЛЕ разбора: у сжатых
	## форматов она известна только оттуда.
	if not _rates.has(path):
		_pcm(path)
	return float(_rates.get(path, 44100.0))


func _pcm(path: String) -> PackedFloat32Array:
	if _cache.has(path):
		return _cache[path]
	var ext := path.get_extension().to_lower()
	if ext == "wav":
		var wav := AudioStreamWAV.load_from_file(path)
		if wav == null:
			return _no_pcm(path, "не прочитал")
		var out := _decode_wav(wav)
		_cache[path] = out
		_rates[path] = float(wav.mix_rate)
		return out

	if not AUDIO_EXTS.has(ext):
		return _no_pcm(path, "не знаю такого расширения")

	# 🔴 У ogg и mp3 отсчётов НАПРЯМУЮ не достать: разбор живёт внутри
	# движка. Зато проигрыватель отдаёт уже разобранные кадры
	# (`AudioStreamPlayback.mix_audio`) — этим и пользуемся. Частота при
	# этом ВСЕГДА серверная: `mix_audio` пересчитывает сам.
	var stream: AudioStream = null
	if ext == "ogg":
		stream = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "mp3":
		stream = AudioStreamMP3.load_from_file(path)
	if stream == null:
		return _no_pcm(path, "не прочитал")
	var decoded := _decode_stream(stream)
	if decoded.is_empty():
		return _no_pcm(path, "разобрался пустым")
	_cache[path] = decoded
	_rates[path] = AudioServer.get_mix_rate()
	return decoded


func _no_pcm(path: String, why: String) -> PackedFloat32Array:
	## Пожаловаться ОДИН раз на файл и запомнить пустоту, чтобы не читать
	## битый файл на каждой ноте.
	if not _complained.has(path):
		_complained[path] = true
		push_warning("Strudel: \"%s\" — %s" % [path.get_file(), why])
	_cache[path] = PackedFloat32Array()
	return _cache[path]


## Сколько кадров берётся за раз при разборе сжатого файла.
const DECODE_CHUNK := 4096
## Предел длины сэмпла — десять минут. Защита от зацикленного потока:
## `mix_audio` у петли не кончается никогда.
const DECODE_LIMIT := 10 * 60


static func _decode_stream(stream: AudioStream) -> PackedFloat32Array:
	## Разбор сжатого потока в моно с плавающей точкой.
	var playback := stream.instantiate_playback()
	if playback == null:
		return PackedFloat32Array()
	playback.start(0.0)
	var out := PackedFloat32Array()
	var limit := int(AudioServer.get_mix_rate() * float(DECODE_LIMIT))
	while playback.is_playing() and out.size() < limit:
		var chunk: PackedVector2Array = playback.mix_audio(1.0, DECODE_CHUNK)
		if chunk.is_empty():
			break
		var base := out.size()
		out.resize(base + chunk.size())
		for i in chunk.size():
			# Голос панорамирует сам, поэтому уши складываются пополам.
			out[base + i] = (chunk[i].x + chunk[i].y) * 0.5
	playback.stop()
	return out


static func _decode_wav(wav: AudioStreamWAV) -> PackedFloat32Array:
	## Разбор в моно с плавающей точкой: голос всё равно панорамирует сам.
	var bytes := wav.data
	var out := PackedFloat32Array()
	var channels := 2 if wav.stereo else 1

	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			var frames := bytes.size() / channels
			out.resize(frames)
			for i in frames:
				var acc := 0.0
				for c in channels:
					acc += float(bytes.decode_s8(i * channels + c)) / 128.0
				out[i] = acc / float(channels)
		AudioStreamWAV.FORMAT_16_BITS:
			var frames16 := bytes.size() / (2 * channels)
			out.resize(frames16)
			for i in frames16:
				var acc16 := 0.0
				for c in channels:
					acc16 += float(bytes.decode_s16((i * channels + c) * 2)) / 32768.0
				out[i] = acc16 / float(channels)
		_:
			push_warning("Strudel: формат WAV %d пока не разбирается (нужен 8 или 16 бит)" % wav.format)
	return out
