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
			# 🔴 У ВЛОЖЕННОЙ ЗАПИСИ БЫВАЕТ СВОЙ `_base` И СПИСОК ФАЙЛОВ НА НОТУ.
			# Настоящие карты Strudel выглядят так:
			#   "stage73": {"_base": "https://…/", "c2": ["quiet.mp3", "loud.mp3"]}
			# Служебный ключ уходил в `note_to_midi("_base")` — ошибка «не нота»
			# при каждой загрузке папки и запись с высотой 0, перехватывавшая
			# низкие ноты. А список файлов превращался в путь из его текстовой
			# записи, то есть в несуществующий файл.
			var inner: Dictionary = value
			var sub := folder
			var inner_base := String(inner.get("_base", ""))
			if inner_base != "" and not inner_base.begins_with("http"):
				sub = folder.path_join(inner_base)
			for note in inner:
				var note_name := String(note)
				if note_name.begins_with("_"):
					continue
				var midi := StrudelUtil.note_to_midi(note_name, 3)
				var one: Variant = inner[note]
				# Список на одну ноту — это варианты записи; берём первый, как
				# и в остальном сэмплере при `n = 0`.
				if one is Array:
					var list_one: Array = one
					if list_one.is_empty():
						continue
					one = list_one[0]
				entry["pitched"][midi] = sub.path_join(_decode(String(one)))
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


## ── ПРОГРЕВ ────────────────────────────────────────────────────────────────
##
## 🔴 Разбор файла идёт при ПЕРВОЙ ноте нужной высоты. У многосэмплированного
## инструмента таких высот десятки, и каждая обходится в сотню миллисекунд —
## на слух игра замирает в паузе и ждёт следующего звука. Считать заранее
## нечего: сколько бы ни было запаса по скорости счёта, чтение файла всё равно
## встанет посреди фразы.
##
## Поэтому банк разбирает свои файлы наперёд, в отдельном потоке: музыка уже
## играет, а сэмплы доезжают следом. К моменту, когда фраза дойдёт до верхнего
## регистра, он давно разобран.

var _prime_thread: Thread
var _prime_stop := false
var _mutex := Mutex.new()


var _prime_only: PackedStringArray = []


func prime_async(names: PackedStringArray = []) -> void:
	## Разобрать файлы наперёд, не задерживая старт.
	##
	## 🔴 СПИСОК ИМЁН ОБЯЗАТЕЛЕН, КОГДА БАНК БОЛЬШОЙ. Банк игры — 267 наборов и
	## тысячи файлов на несколько гигабайт; прогревать его целиком ради трека,
	## которому нужен один рояль, значит молотить диск всю партию. Пустой
	## список означает «весь банк» и годится только для маленьких паков.
	if _prime_thread != null:
		return
	_prime_only = names
	_prime_stop = false
	_prime_thread = Thread.new()
	_prime_thread.start(_prime_loop)


func prime_stop() -> void:
	if _prime_thread == null:
		return
	_prime_stop = true
	_prime_thread.wait_to_finish()
	_prime_thread = null


func _prime_loop() -> void:
	var keys: Array = Array(_prime_only) if not _prime_only.is_empty() else entries.keys()
	for key in keys:
		if _prime_stop or not entries.has(key):
			if _prime_stop:
				return
			continue
		var entry: Dictionary = entries[key]
		for path in (entry.get("pitched", {}) as Dictionary).values():
			if _prime_stop:
				return
			_pcm(String(path))
		for path in (entry.get("files", []) as Array):
			if _prime_stop:
				return
			_pcm(String(path))


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


func _pcm_resource(path: String) -> PackedFloat32Array:
	## Отсчёты из импортированного ресурса. Путь к файлу приводим к `res://`:
	## банк игры отдаёт абсолютные пути, а движок знает свои.
	var res := path
	if not res.begins_with("res://"):
		var base := ProjectSettings.globalize_path("res://")
		if not path.begins_with(base):
			return PackedFloat32Array()
		res = "res://" + path.substr(base.length()).replace("\\", "/")
	if not ResourceLoader.exists(res):
		return PackedFloat32Array()
	var stream := load(res)
	if stream == null or not (stream is AudioStream):
		return PackedFloat32Array()
	var out := _decode_stream(stream)
	if out.is_empty():
		return out
	_mutex.lock()
	_cache[path] = out
	_rates[path] = float(AudioServer.get_mix_rate())
	_mutex.unlock()
	return out


func _pcm(path: String) -> PackedFloat32Array:
	# Кэш общий для потока прогрева и для счёта звука — читаем и пишем под
	# замком, иначе словарь правится из двух потоков разом.
	_mutex.lock()
	var ready: bool = _cache.has(path)
	var hit: PackedFloat32Array = _cache[path] if ready else PackedFloat32Array()
	_mutex.unlock()
	if ready:
		return hit
	var ext := path.get_extension().to_lower()
	if ext == "wav":
		# 🔴 WAV РАЗБИРАЕТСЯ САМИМ ПЛАГИНОМ, а не движком.
		#
		# `AudioStreamWAV.load_from_file` умеет отдавать только 8 и 16 бит:
		# 24-битный файл он ужимает до 16 (проверено — формат приходит 1 при
		# честных 24 битах в файле). Библиотеки живых инструментов пишутся в
		# 24 бита и с большим запасом по уровню: у сэмпла псалтериума пик
		# 0.083, то есть от шестнадцати бит работают одиннадцать, и всё, что
		# тише пика на полсотни децибел, уходит в ступеньку квантования.
		# Замерено сверкой с Булкой: у ноты пропадала основная частота —
		# 22 дБ разницы там, где остальной спектр сходился до децибела.
		# 🔴 СНАЧАЛА — ИМПОРТИРОВАННЫЙ РЕСУРС ДВИЖКА, а не файл с диска.
		#
		# Godot разобрал сэмплы при импорте, держит их в своём кэше и умеет
		# отдавать отсчёты сам: `load()` + проигрывание через `mix_audio`.
		# Замер на банке игры: движком 28 мс, чтением файла 64 мс — вдвое
		# дешевле, и это тот же тракт, которым звук берёт сама игра.
		# Важнее скорости другое: в собранной игре исходных `.wav` нет вовсе,
		# едут только импортированные ресурсы, — читать файл там было бы
		# нечего.
		var from_res := _pcm_resource(path)
		if not from_res.is_empty():
			return from_res
		var wav := AudioStreamWAV.load_from_file(path)
		if wav != null:
			var out := _decode_wav(wav)
			if not out.is_empty():
				_mutex.lock()
				_cache[path] = out
				_rates[path] = float(wav.mix_rate)
				_mutex.unlock()
				return out
		var mine := _read_wav(path)
		if not mine.is_empty():
			_mutex.lock()
			_cache[path] = mine["data"]
			_rates[path] = float(mine["rate"])
			_mutex.unlock()
			return mine["data"]
		return _no_pcm(path, "не прочитал")

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


static func _read_wav(path: String) -> Dictionary:
	## Свой разбор RIFF/WAVE. → {data: моно float, rate: частота} либо пусто,
	## если вид не наш (сжатый) — тогда пусть пробует движок.
	##
	## Берётся то, чего не отдаёт `AudioStreamWAV`: 24 бита, 32 бита целыми и
	## 32/64 бита с плавающей точкой. Именно в них пишутся банки живых
	## инструментов, и именно на них движковая загрузка теряет тихое.
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var size := f.get_length()
	if size < 44 or f.get_buffer(4).get_string_from_ascii() != "RIFF":
		f.close()
		return {}
	f.seek(8)
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		f.close()
		return {}

	var fmt := 0
	var channels := 0
	var rate := 0
	var bits := 0
	var data_at := -1
	var data_len := 0
	var pos := 12
	while pos + 8 <= size:
		f.seek(pos)
		var cid := f.get_buffer(4).get_string_from_ascii()
		var clen := f.get_32()
		var body := pos + 8
		if cid == "fmt ":
			f.seek(body)
			fmt = f.get_16()
			channels = f.get_16()
			rate = f.get_32()
			f.get_32()  # средняя скорость
			f.get_16()  # выравнивание блока
			bits = f.get_16()
			if fmt == 0xFFFE and clen >= 40:
				# Расширенный вид: настоящий номер лежит в GUID.
				f.seek(body + 24)
				fmt = f.get_16()
		elif cid == "data":
			data_at = body
			data_len = clen
		pos = body + clen + (clen & 1)

	if data_at < 0 or channels <= 0 or rate <= 0:
		f.close()
		return {}
	data_len = mini(data_len, size - data_at)
	# 1 — целые со знаком, 3 — с плавающей точкой. Остальное (ADPCM и прочее)
	# отдаём движку.
	if fmt != 1 and fmt != 3:
		f.close()
		return {}
	var step := bits / 8
	if step <= 0 or (fmt == 3 and bits != 32 and bits != 64):
		f.close()
		return {}

	f.seek(data_at)
	var raw := f.get_buffer(data_len)
	f.close()
	var frames := data_len / (step * channels)
	var out := PackedFloat32Array()
	out.resize(frames)
	var inv := 1.0 / float(channels)
	for i in frames:
		var acc := 0.0
		for c in channels:
			var at := (i * channels + c) * step
			match [fmt, bits]:
				[1, 8]:
					# 8 бит в WAV — БЕЗ знака, смещены на 128.
					acc += (float(raw.decode_u8(at)) - 128.0) / 128.0
				[1, 16]:
					acc += float(raw.decode_s16(at)) / 32768.0
				[1, 24]:
					var v := int(raw.decode_u8(at)) 						| (int(raw.decode_u8(at + 1)) << 8) 						| (int(raw.decode_u8(at + 2)) << 16)
					if v >= 0x800000:
						v -= 0x1000000
					acc += float(v) / 8388608.0
				[1, 32]:
					acc += float(raw.decode_s32(at)) / 2147483648.0
				[3, 32]:
					acc += raw.decode_float(at)
				[3, 64]:
					acc += raw.decode_double(at)
				_:
					return {}
		out[i] = acc * inv
	return {"data": out, "rate": rate}
