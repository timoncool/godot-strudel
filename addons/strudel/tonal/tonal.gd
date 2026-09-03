@tool
class_name StrudelTonal
extends RefCounted

## Тональные функции: аккорды, раскладки, лады.
## Перенос `packages/tonal/tonleiter.mjs` и `voicings.mjs`.
##
## 🔴 Раскладка обязана совпадать с Булкой ПО НОТАМ, а не «звучать похоже».
## Поэтому здесь ровно та же арифметика: выбор раскладки по наименьшему
## смещению верхнего голоса, привязка к якорю, режимы below/above/root.

const PCS := ["c", "db", "d", "eb", "e", "f", "gb", "g", "ab", "a", "bb", "b"]
const FLATS := ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
## Полутоны чистых/больших интервалов внутри октавы: 1P 2M 3M 4P 5P 6M 7M.
const BASE_SEMITONES := [0, 2, 4, 5, 7, 9, 11]
## Интервалы, у которых «чистое» качество (остальные — большие/малые).
const PERFECT := [1, 4, 5, 8]


# ═══════════════════════════════════════════════════════════════════════════
# Ноты и интервалы
# ═══════════════════════════════════════════════════════════════════════════

static func pc_to_chroma(pc: String) -> int:
	if pc.is_empty():
		return 0
	var letter := pc.substr(0, 1).to_lower()
	var chroma := PCS.find(letter)
	if chroma < 0:
		chroma = 0
	for i in range(1, pc.length()):
		var ch := pc[i]
		if ch == "#":
			chroma += 1
		elif ch == "b":
			chroma -= 1
	return chroma


static func midi_to_note(midi: int) -> String:
	var octave := int(floor(float(midi) / 12.0)) - 1
	return FLATS[StrudelUtil.mod_i(midi, 12)] + str(octave)


static func interval_semitones(step: String) -> int:
	## "3m" → 3, "5P" → 7, "9M" → 14, "5d" → 6, "11A" → 18.
	##
	## Составные интервалы (9, 11, 13…) — это простые плюс октавы; качество
	## меняет полутон: малый на один вниз от большого, уменьшённый на один от
	## чистого и на два от большого.
	var num_text := ""
	var quality := ""
	for i in step.length():
		var c := step[i]
		if c >= "0" and c <= "9":
			num_text += c
		else:
			quality += c
	if num_text.is_empty():
		if step.is_valid_float():
			return int(step.to_float())
		return 0
	var number := num_text.to_int()
	if number <= 0:
		return 0
	var simple := StrudelUtil.mod_i(number - 1, 7) + 1
	var octaves := int(floor(float(number - 1) / 7.0))
	var semis: int = BASE_SEMITONES[simple - 1] + 12 * octaves
	var is_perfect := PERFECT.has(simple)
	for i in quality.length():
		match quality[i]:
			"P", "M":
				pass
			"m":
				semis -= 1
			"A":
				semis += 1
			"d":
				semis -= 1 if is_perfect else 2
	return semis


static func tokenize_chord(chord: String) -> Array:
	## "C^7" → ["C", "^7"], "Am7" → ["A", "m7"], "C/G" → ["C", "", "G"].
	var re := RegEx.create_from_string("^([A-G][b#]*)([^/]*)[/]?([A-G][b#]*)?$")
	var m := re.search(chord)
	if m == null:
		return []
	return [m.get_string(1), m.get_string(2), m.get_string(3)]


static func note_or_midi(value: Variant, default_octave: int = 3) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String or value is StringName:
		return StrudelUtil.note_to_midi(String(value), default_octave)
	if value is Dictionary and (value as Dictionary).has("note"):
		return note_or_midi((value as Dictionary)["note"], default_octave)
	return 0


# ═══════════════════════════════════════════════════════════════════════════
# Раскладка аккорда
# ═══════════════════════════════════════════════════════════════════════════

const _MODE_TARGET_LAST := ["below", "duck"]


static func render_voicing(opts: Dictionary) -> Array:
	## → список нот (строк) либо одна миди-нота, если задан `n`.
	var chord := String(opts.get("chord", ""))
	var parts := tokenize_chord(chord)
	if parts.is_empty():
		return []
	var root := String(parts[0])
	var symbol := String(parts[1])
	var root_chroma := pc_to_chroma(root)

	var dict: Dictionary = opts.get("dictionary", StrudelVoicingTable.IREAL)
	if not dict.has(symbol):
		return []

	var mode := String(opts.get("mode", "below"))
	var anchor := note_or_midi(opts.get("anchor", "c5"), 4)
	var anchor_chroma := StrudelUtil.mod_i(anchor, 12)
	var offset := int(opts.get("offset", 0))
	var octaves := int(opts.get("octaves", 1))

	var voicings: Array = []
	for text in dict[symbol]:
		var semis: Array = []
		for token in String(text).split(" ", false):
			semis.append(interval_semitones(token))
		voicings.append(semis)
	if voicings.is_empty():
		return []

	var mult := 1 if (mode == "below" or mode == "duck" or mode == "oldabove" or mode == "oldroot") else -1
	var take_last := _MODE_TARGET_LAST.has(mode)

	var chroma_diffs: Array = []
	var min_distance := -1
	var best_index := 0
	for i in voicings.size():
		var v: Array = voicings[i]
		var target_step: int = v[v.size() - 1] if take_last else v[0]
		var diff := StrudelUtil.mod_i((anchor_chroma - target_step - root_chroma) * mult, 12)
		if min_distance < 0 or diff < min_distance:
			min_distance = diff
			best_index = i
		chroma_diffs.append(diff * mult)
	if mode == "root" or mode == "oldroot":
		best_index = 0

	var oct_diff := int(ceil(float(offset) / float(voicings.size()))) * 12
	var index := StrudelUtil.mod_i(best_index + offset, voicings.size())
	var voicing: Array = voicings[index]
	var target: int = voicing[voicing.size() - 1] if take_last else voicing[0]
	var anchor_midi: int = anchor - int(chroma_diffs[index]) + oct_diff

	var voicing_midi: Array = []
	for v in voicing:
		voicing_midi.append(anchor_midi - target + int(v))

	var notes: Array = []
	for i in voicing_midi.size():
		if mode == "duck" and int(voicing_midi[i]) == anchor:
			continue
		notes.append(midi_to_note(int(voicing_midi[i])))

	if opts.has("n") and opts["n"] != null:
		return [scale_step(notes, int(StrudelPattern._num(opts["n"])), octaves)]
	return notes


static func scale_step(notes: Array, offset: int, octaves: int = 1) -> int:
	## Играет раскладку как лад: номера сверх её длины уходят в октаву.
	if notes.is_empty():
		return 0
	var midi: Array = []
	for n in notes:
		midi.append(note_or_midi(n))
	var oct_offset := int(floor(float(offset) / float(midi.size()))) * octaves * 12
	var idx := StrudelUtil.mod_i(offset, midi.size())
	return int(midi[idx]) + oct_offset


# ═══════════════════════════════════════════════════════════════════════════
# Функции для паттернов
# ═══════════════════════════════════════════════════════════════════════════

static func chord(pat: StrudelPattern) -> StrudelPattern:
	## Помечает значения как аккорды: "C^7" → {chord: "C^7"}.
	return StrudelControls.make("chord", pat)


static func voicing(pat: StrudelPattern) -> StrudelPattern:
	## Превращает символы аккордов в конкретные ноты.
	return pat.fmap(func(value) -> StrudelPattern:
		var v: Dictionary = value if value is Dictionary else {"chord": value}
		var dict_name: Variant = v.get("dictionary", "ireal")
		var opts := {
			"chord": String(v.get("chord", "")),
			"dictionary": StrudelVoicingTable.dictionary(String(dict_name)),
			"mode": String(v.get("mode", "below")),
			"anchor": v.get("anchor", "c5"),
			"offset": int(StrudelPattern._num(v.get("offset", 0))),
			"octaves": int(StrudelPattern._num(v.get("octaves", 1))),
		}
		if v.has("n"):
			opts["n"] = v["n"]
		var notes := render_voicing(opts)
		if notes.is_empty():
			push_warning("Strudel: не знаю аккорда \"%s\"" % str(v.get("chord")))
			return StrudelPattern.silence()

		# Остальные параметры (звук, громкость…) переезжают на ноты.
		var rest := {}
		for k in v:
			if k in ["chord", "dictionary", "anchor", "offset", "mode", "n", "octaves"]:
				continue
			rest[k] = v[k]

		var layers: Array = []
		for note in notes:
			var d := rest.duplicate()
			d["note"] = note
			layers.append(StrudelPattern.pure(d))
		return StrudelPattern.stack(layers)
	).outer_join()


static func root_notes(pat: StrudelPattern, octave: Variant) -> StrudelPattern:
	## Основные тоны аккордов в заданной октаве.
	var oct := int(StrudelPattern._num(octave))
	return pat.fmap(func(value):
		var chord_text := String(value["chord"]) if (value is Dictionary and (value as Dictionary).has("chord")) else String(value)
		var re := RegEx.create_from_string("^([a-gA-G][b#]?).*$")
		var m := re.search(chord_text)
		if m == null:
			return value
		var note := m.get_string(1) + str(oct)
		if value is Dictionary and (value as Dictionary).has("chord"):
			return {"note": note}
		return note
	)


const LETTERS := ["C", "D", "E", "F", "G", "A", "B"]
const LETTER_SEMITONES := [0, 2, 4, 5, 7, 9, 11]
## Полутоны → «естественный» интервал, как Interval.fromSemitones у tonal.
const SEMITONE_INTERVAL := ["1P", "2m", "2M", "3m", "3M", "4P", "5d", "5P", "6m", "6M", "7m", "7M"]


static func interval_from_semitones(semitones: int) -> Array:
	## → [номер ступени, полутоны]. 5 → [4, 5] («чистая кварта»).
	var octaves := int(floor(float(semitones) / 12.0))
	var rest := StrudelUtil.mod_i(semitones, 12)
	var name := String(SEMITONE_INTERVAL[rest])
	var number := name.substr(0, 1).to_int() + octaves * 7
	return [number, semitones]


static func transpose_note(note: String, semitones: int) -> String:
	## Сдвиг ноты С СОХРАНЕНИЕМ НАЗВАНИЯ: c3 + 5 полутонов = F3, а не 53.
	##
	## Ноту нельзя просто перевести в число: Булка отдаёт имена, и запись
	## «F3» против «53» — это расхождение в сверке на ровном месте.
	var parts := StrudelUtil.tokenize_note(note)
	if parts.is_empty():
		return note
	var octave: int = parts[2] if parts[2] != null else 3
	var letter_index := LETTERS.find(String(parts[0]).to_upper())
	if letter_index < 0:
		return note
	var interval := interval_from_semitones(semitones)
	var total: int = letter_index + int(interval[0]) - 1
	var target_index := StrudelUtil.mod_i(total, 7)
	var octave_carry := int(floor(float(total) / 7.0))
	var target_octave := octave + octave_carry
	var target_midi := StrudelUtil.note_to_midi(note, 3) + semitones
	var natural_midi: int = (target_octave + 1) * 12 + int(LETTER_SEMITONES[target_index])
	var accidental := target_midi - natural_midi
	var marks := ""
	if accidental > 0:
		marks = "#".repeat(accidental)
	elif accidental < 0:
		marks = "b".repeat(-accidental)
	return String(LETTERS[target_index]) + marks + str(target_octave)


static func transpose(pat: StrudelPattern, amount: Variant) -> StrudelPattern:
	## Сдвиг по полутонам. Ноты-имена остаются именами, числа — числами.
	return pat._patternify([amount], func(vals: Array) -> StrudelPattern:
		var semis := int(StrudelPattern._num(vals[0]))
		return pat.fmap(func(value):
			var note: Variant = value
			if value is Dictionary and (value as Dictionary).has("note"):
				note = (value as Dictionary)["note"]
			var shifted: Variant
			if note is String or note is StringName:
				if not StrudelUtil.is_note(String(note)):
					return value
				shifted = transpose_note(String(note), semis)
			else:
				shifted = StrudelPattern._num(note) + float(semis)
			if value is Dictionary:
				var d: Dictionary = (value as Dictionary).duplicate()
				d["note"] = shifted
				return d
			return shifted
		)
	)


static func mode(pat: StrudelPattern, value: Variant) -> StrudelPattern:
	## `mode("root:c2")` — как раскладка прижимается к якорю.
	## Составной параметр: имя режима и якорь через двоеточие раскладываются
	## по двум именам ["mode", "anchor"].
	return StrudelControls.apply(pat, "mode", value)


static func scale(pat: StrudelPattern, name: Variant) -> StrudelPattern:
	## Номера ступеней → ноты лада.
	##
	## 🔴 Структура остаётся у ПАТТЕРНА, а имя лада — только значение.
	## Если перепутать (взять структуру у имени), весь строй схлопнется в одну
	## ноту на цикл: сверка с Булкой поймала это сразу.
	return pat._patternify([name], func(vals: Array) -> StrudelPattern:
		var text := _scale_text(vals[0])
		return pat.with_haps(func(haps: Array, _state) -> Array:
			var out: Array = []
			for hap in haps:
				var ctx := (hap as StrudelHap).context.duplicate()
				ctx["scale"] = text
				out.append(StrudelHap.new(hap.whole, hap.part,
					_apply_scale(hap.value, text), ctx))
			return out
		)
	)


static func _scale_text(v: Variant) -> String:
	if v is Array:
		var parts: Array[String] = []
		for x in v:
			parts.append(str(x))
		return " ".join(parts)
	return String(v).replace(":", " ")


static func _apply_scale(value: Variant, scale_name: String) -> Variant:
	var v: Dictionary = value if value is Dictionary else {"n": value}
	var step: Variant = v.get("note", v.get("n", v.get("value")))
	if step == null:
		return value
	var parts := scale_name.strip_edges().split(" ", false)
	if parts.is_empty():
		return value
	var tonic := String(parts[0])
	var rest_name := " ".join(Array(parts.slice(1)))
	var intervals_text := StrudelScaleTable.intervals(rest_name)
	if intervals_text.is_empty():
		push_warning("Strudel: не знаю лада \"%s\"" % rest_name)
		return value
	var intervals: Array = []
	for token in intervals_text.split(" ", false):
		intervals.append(interval_semitones(token))

	var tonic_midi := StrudelUtil.note_to_midi(tonic, 3)
	var idx := int(StrudelPattern._num(step))
	var oct_offset := int(floor(float(idx) / float(intervals.size()))) * 12
	var pos := StrudelUtil.mod_i(idx, intervals.size())
	var note_midi: int = tonic_midi + int(intervals[pos]) + oct_offset

	var out := {}
	for k in v:
		if k in ["n", "value"]:
			continue
		out[k] = v[k]
	out["note"] = midi_to_note(note_midi)
	return out


static func arp(pat: StrudelPattern, indices: Variant) -> StrudelPattern:
	## Разбивает созвучие на голоса по номерам.
	var index_pat := StrudelPattern.reify(indices)
	return _collect(pat).fmap(func(haps: Array) -> StrudelPattern:
		return index_pat.fmap(func(i) -> Variant:
			if haps.is_empty():
				return null
			var k := StrudelUtil.mod_i(int(StrudelPattern._num(i)), haps.size())
			return (haps[k] as StrudelHap).value
		)
	).inner_join()


static func _collect(pat: StrudelPattern) -> StrudelPattern:
	## Группирует одновременные события в одно со списком.
	return pat.with_haps(func(haps: Array, _state) -> Array:
		var groups: Array = []
		for hap in haps:
			var found := false
			for g in groups:
				if (g[0] as StrudelHap).span_equals(hap):
					(g as Array).append(hap)
					found = true
					break
			if not found:
				groups.append([hap])
		var out: Array = []
		for g in groups:
			var first: StrudelHap = g[0]
			out.append(StrudelHap.new(first.whole, first.part, g, {}))
		return out
	)
