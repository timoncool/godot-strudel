@tool
class_name StrudelSoundFont
extends RefCounted

## Саундфонт (.sf2) — адресация `sf:<банк>:<программа>`, как в Strudel.
##
## 🔴 Звуки грузятся ЛЕНИВО, по одному. У саундфонта игры Osmo 32 МБ звуковых
## данных; развернув их все в float, получили бы 128 МБ в памяти на пустом
## месте. Заголовки (пресеты, инструменты, описания сэмплов) читаются сразу —
## они занимают меньше четверти мегабайта, — а сам звук вынимается из файла
## тогда, когда его впервые попросили.
##
## Формат — RIFF: `sdta/smpl` держит 16-битные отсчёты подряд, `pdta` —
## таблицы. Разбирается подмножество, которого хватает для игры нотами:
## пресет → инструмент → сэмпл, диапазон клавиш, основной тон и подстройка.

## Опкоды генераторов SF2, которые здесь используются.
const GEN_KEY_RANGE := 43
const GEN_INSTRUMENT := 41
const GEN_SAMPLE_ID := 53
const GEN_ROOT_KEY := 58
const GEN_COARSE_TUNE := 51
const GEN_FINE_TUNE := 52
const GEN_SAMPLE_MODES := 54
const GEN_ATTENUATION := 48

var loaded := false
var path := ""

var _smpl_offset := 0
var _smpl_frames := 0
## Описания сэмплов: {start, end, loop_start, loop_end, rate, root, correction, link, type}
var _samples: Array = []
## Пресеты: ключ (банк * 1000 + программа) → массив зон.
var _presets: Dictionary = {}
var _cache: Dictionary = {}


func load_file(file_path: String) -> bool:
	## Читает заголовки. Звук остаётся в файле до первого обращения.
	path = file_path
	loaded = false
	_samples.clear()
	_presets.clear()
	_cache.clear()

	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		push_warning("Strudel: не нашёл саундфонт %s" % file_path)
		return false
	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		push_warning("Strudel: %s — не RIFF" % file_path)
		f.close()
		return false
	var total := f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "sfbk":
		push_warning("Strudel: %s — не саундфонт" % file_path)
		f.close()
		return false

	var chunks := {}
	var end := mini(total + 8, int(f.get_length()))
	_walk(f, 12, end, chunks)

	if not chunks.has("smpl"):
		push_warning("Strudel: в саундфонте нет звуковых данных")
		f.close()
		return false
	_smpl_offset = int(chunks["smpl"][0])
	_smpl_frames = int(chunks["smpl"][1]) / 2

	for needed in ["phdr", "pbag", "pgen", "inst", "ibag", "igen", "shdr"]:
		if not chunks.has(needed):
			push_warning("Strudel: в саундфонте нет таблицы %s" % needed)
			f.close()
			return false

	var phdr := _read(f, chunks["phdr"])
	var pbag := _read(f, chunks["pbag"])
	var pgen := _read(f, chunks["pgen"])
	var inst := _read(f, chunks["inst"])
	var ibag := _read(f, chunks["ibag"])
	var igen := _read(f, chunks["igen"])
	var shdr := _read(f, chunks["shdr"])
	f.close()

	_parse_samples(shdr)
	_parse_presets(phdr, pbag, pgen, inst, ibag, igen)
	loaded = not _presets.is_empty()
	return loaded


func preset_count() -> int:
	return _presets.size()


func sample_count() -> int:
	return _samples.size()


func has_preset(bank: int, program: int) -> bool:
	return _presets.has(bank * 1000 + program)


func programs() -> Array:
	## Список доступных пар [банк, программа] — чтобы было что показать.
	var out: Array = []
	for key in _presets:
		out.append([int(key) / 1000, int(key) % 1000])
	out.sort_custom(func(a, b): return a[0] * 1000 + a[1] < b[0] * 1000 + b[1])
	return out


func resolve(bank: int, program: int, midi_note: float) -> Dictionary:
	## → {data, rate, speed, loop, loop_start, loop_end} либо пустой словарь.
	var key := bank * 1000 + program
	if not _presets.has(key):
		return {}
	var note := int(round(midi_note))
	var zones: Array = _presets[key]
	var chosen: Dictionary = {}
	for zone in zones:
		if note >= int(zone["key_lo"]) and note <= int(zone["key_hi"]):
			chosen = zone
			break
	if chosen.is_empty():
		# Ни одна зона не покрывает ноту — берём ближайшую по середине диапазона.
		var best := 1e9
		for zone in zones:
			var middle := (float(zone["key_lo"]) + float(zone["key_hi"])) * 0.5
			var diff := absf(middle - midi_note)
			if diff < best:
				best = diff
				chosen = zone
	if chosen.is_empty():
		return {}

	var index := int(chosen["sample"])
	if index < 0 or index >= _samples.size():
		return {}
	var info: Dictionary = _samples[index]
	var data := _sample_data(index)
	if data.is_empty():
		return {}

	var root := int(chosen["root"]) if int(chosen["root"]) >= 0 else int(info["root"])
	var cents := float(info["correction"]) + float(chosen["fine"]) + float(chosen["coarse"]) * 100.0
	var speed: float = pow(2.0, (midi_note - float(root) + cents / 100.0) / 12.0)

	return {
		"data": data,
		"rate": float(info["rate"]),
		"speed": speed,
		"loop": int(chosen["modes"]) == 1 or int(chosen["modes"]) == 3,
		"attenuation_db": -float(chosen["attenuation"]) / 10.0,
	}


# ═══════════════════════════════════════════════════════════════════════════
# Разбор
# ═══════════════════════════════════════════════════════════════════════════

func _walk(f: FileAccess, from_pos: int, to_pos: int, out: Dictionary) -> void:
	var pos := from_pos
	while pos + 8 <= to_pos:
		f.seek(pos)
		var id := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		var body := pos + 8
		if id == "LIST":
			# Вложенный список — заходим внутрь, пропустив его вид.
			_walk(f, body + 4, body + size, out)
		else:
			out[id] = [body, size]
		pos = body + size + (size & 1)


func _read(f: FileAccess, where: Array) -> PackedByteArray:
	f.seek(int(where[0]))
	return f.get_buffer(int(where[1]))


func _parse_samples(shdr: PackedByteArray) -> void:
	var count := shdr.size() / 46
	for i in count:
		var at := i * 46
		var name := shdr.slice(at, at + 20).get_string_from_ascii()
		if name.begins_with("EOS"):
			continue
		_samples.append({
			"name": name,
			"start": shdr.decode_u32(at + 20),
			"end": shdr.decode_u32(at + 24),
			"loop_start": shdr.decode_u32(at + 28),
			"loop_end": shdr.decode_u32(at + 32),
			"rate": shdr.decode_u32(at + 36),
			"root": shdr.decode_u8(at + 40),
			"correction": shdr.decode_s8(at + 41),
		})


func _parse_presets(phdr: PackedByteArray, pbag: PackedByteArray, pgen: PackedByteArray,
		inst: PackedByteArray, ibag: PackedByteArray, igen: PackedByteArray) -> void:
	var preset_count := phdr.size() / 38
	for p in preset_count - 1:  # последняя запись — служебная (EOP)
		var at := p * 38
		var program := phdr.decode_u16(at + 20)
		var bank := phdr.decode_u16(at + 22)
		var bag_from := phdr.decode_u16(at + 24)
		var bag_to := phdr.decode_u16(at + 38 + 24)

		var zones: Array = []
		for b in range(bag_from, bag_to):
			if (b + 1) * 4 > pbag.size():
				break
			var gen_from := pbag.decode_u16(b * 4)
			var gen_to := pbag.decode_u16((b + 1) * 4) if (b + 2) * 4 <= pbag.size() else gen_from
			var preset_gens := _gens(pgen, gen_from, gen_to)
			if not preset_gens.has(GEN_INSTRUMENT):
				continue  # глобальная зона пресета — правила по умолчанию
			var instrument := int(preset_gens[GEN_INSTRUMENT])
			zones.append_array(_instrument_zones(inst, ibag, igen, instrument, preset_gens))
		if not zones.is_empty():
			_presets[bank * 1000 + program] = zones


func _instrument_zones(inst: PackedByteArray, ibag: PackedByteArray, igen: PackedByteArray,
		index: int, from_preset: Dictionary) -> Array:
	var out: Array = []
	if (index + 1) * 22 + 20 > inst.size():
		return out
	var bag_from := inst.decode_u16(index * 22 + 20)
	var bag_to := inst.decode_u16((index + 1) * 22 + 20)

	for b in range(bag_from, bag_to):
		if (b + 1) * 4 > ibag.size():
			break
		var gen_from := ibag.decode_u16(b * 4)
		var gen_to := ibag.decode_u16((b + 1) * 4) if (b + 2) * 4 <= ibag.size() else gen_from
		var gens := _gens(igen, gen_from, gen_to)
		if not gens.has(GEN_SAMPLE_ID):
			continue
		var key_range := int(gens.get(GEN_KEY_RANGE, from_preset.get(GEN_KEY_RANGE, 0x7F00)))
		out.append({
			"sample": int(gens[GEN_SAMPLE_ID]),
			"key_lo": key_range & 0xFF,
			"key_hi": (key_range >> 8) & 0xFF,
			"root": int(gens.get(GEN_ROOT_KEY, -1)),
			"fine": _signed16(int(gens.get(GEN_FINE_TUNE, 0))),
			"coarse": _signed16(int(gens.get(GEN_COARSE_TUNE, 0))),
			"modes": int(gens.get(GEN_SAMPLE_MODES, 0)),
			"attenuation": int(gens.get(GEN_ATTENUATION, 0)),
		})
	return out


static func _gens(buf: PackedByteArray, from_index: int, to_index: int) -> Dictionary:
	var out := {}
	for g in range(from_index, to_index):
		var at := g * 4
		if at + 4 > buf.size():
			break
		out[buf.decode_u16(at)] = buf.decode_u16(at + 2)
	return out


static func _signed16(value: int) -> int:
	return value - 65536 if value > 32767 else value


func _sample_data(index: int) -> PackedFloat32Array:
	## Достаёт отсчёты одного сэмпла из файла — только когда попросили.
	if _cache.has(index):
		return _cache[index]
	var info: Dictionary = _samples[index]
	var start := int(info["start"])
	var end := int(info["end"])
	var frames := end - start
	var out := PackedFloat32Array()
	if frames <= 0 or start + frames > _smpl_frames:
		_cache[index] = out
		return out

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_cache[index] = out
		return out
	f.seek(_smpl_offset + start * 2)
	var bytes := f.get_buffer(frames * 2)
	f.close()

	out.resize(frames)
	for i in frames:
		out[i] = float(bytes.decode_s16(i * 2)) / 32768.0
	_cache[index] = out
	return out
