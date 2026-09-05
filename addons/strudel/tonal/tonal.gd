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


static func interval_parts(step: String) -> Array:
	## → [номер ступени, полутоны]. "3m" → [3, 3], "4A" → [4, 6], "9M" → [9, 14].
	var num_text := ""
	for i in step.length():
		var c := step[i]
		if c >= "0" and c <= "9":
			num_text += c
	var number := num_text.to_int() if num_text != "" else 1
	return [number, interval_semitones(step)]


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
		return StrudelUtil.note_to_midi(StrudelUtil.text(value), default_octave)
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
			"chord": StrudelUtil.text(v.get("chord", "")),
			"dictionary": StrudelVoicingTable.dictionary(StrudelUtil.text(dict_name)),
			"mode": StrudelUtil.text(v.get("mode", "below")),
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
		var chord_text := StrudelUtil.text(value["chord"]) if (value is Dictionary and (value as Dictionary).has("chord")) else StrudelUtil.text(value)
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
	var interval := interval_from_semitones(semitones)
	return transpose_by(note, int(interval[0]), semitones)


static func transpose_by(note: String, interval_number: int, semitones: int) -> String:
	## Сдвиг по ЯВНОМУ интервалу: отдельно ступень, отдельно полутоны.
	##
	## 🔴 Одному числу полутонов отвечают РАЗНЫЕ названия: увеличенная кварта
	## (4A) и уменьшённая квинта (5d) — обе шесть полутонов, но первая от C
	## даёт F#, а вторая Gb. Лады пользуются именно этим, поэтому ступень
	## нельзя выводить из полутонов — её задаёт сам интервал лада.
	var parts := StrudelUtil.tokenize_note(note)
	if parts.is_empty():
		return note
	var octave: int = parts[2] if parts[2] != null else 3
	var letter_index := LETTERS.find(String(parts[0]).to_upper())
	if letter_index < 0:
		return note
	var total: int = letter_index + interval_number - 1
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
		# 🔴 ИНТЕРВАЛ БЫВАЕТ СТРОКОЙ, И ЭТО НЕ ЧИСЛО ПОЛУТОНОВ.
		#
		# `transpose("4P")` — чистая кварта, `"3m"` — малая терция, `"-2M"` —
		# большая секунда вниз. Раньше строка шла через `_num`, тот принимал
		# её за НОТУ и отдавал номер по MIDI: `transpose("4P")` давало ноту
		# `Ebbbbbb…` с гирляндой бемолей. В оригинале (`tonal.mjs:137`)
		# строка идёт в `Note.transpose` целиком, и от неё берутся ОБА числа —
		# ступень и полутоны, — иначе увеличенная кварта и уменьшённая квинта
		# (обе по шесть полутонов) дали бы одно и то же имя.
		var raw: Variant = vals[0]
		var as_text := String(raw) if (raw is String or raw is StringName) else ""
		var by_interval := as_text != "" and not as_text.is_valid_float() 			and not StrudelUtil.is_note(as_text)
		var step_number := 0
		var semis := 0
		if by_interval:
			var parts := interval_parts(as_text)
			step_number = int(parts[0])
			semis = int(parts[1])
			if as_text.begins_with("-"):
				step_number = -step_number
				semis = -absi(semis)
		else:
			semis = int(StrudelPattern._num(raw))
		return pat.fmap(func(value):
			var note: Variant = value
			if value is Dictionary and (value as Dictionary).has("note"):
				note = (value as Dictionary)["note"]
			var shifted: Variant
			if note is String or note is StringName:
				if not StrudelUtil.is_note(String(note)):
					return value
				shifted = transpose_by(String(note), step_number, semis) 					if by_interval else transpose_note(String(note), semis)
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
				var value: Variant = _apply_scale(hap.value, text)
				if value == null:
					continue  # лад не разобрался — событие выброшено
				var ctx := (hap as StrudelHap).context.duplicate()
				ctx["scale"] = text
				out.append(StrudelHap.new(hap.whole, hap.part, value, ctx))
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


static func get_scale(scale_name: String) -> Dictionary:
	## Разбор имени лада по правилам Tonal (`getScale`, `tonal.mjs:23`).
	##
	## → {ok, tonic_pc, octave, tokens} либо {ok=false}.
	##
	## 🔴 ТОНИКА НЕОБЯЗАТЕЛЬНА. «bebop» — полноценное имя лада, тоника тогда
	## «C», октава третья. А вот «C» — имя НЕПОЛНОЕ (лада с таким названием
	## нет), и такое событие Булка выбрасывает.
	var name := scale_name.replace(":", " ").strip_edges()
	var parts := name.split(" ", false)
	if parts.is_empty():
		return {"ok": false}
	var tonic_text := ""
	var type_name := name
	if StrudelUtil.is_note(String(parts[0])):
		tonic_text = String(parts[0])
		type_name = " ".join(Array(parts.slice(1)))
	var intervals_text := StrudelScaleTable.intervals(type_name)
	if intervals_text.is_empty():
		return {"ok": false}
	var octave := 3
	var tonic_pc := "C"
	if tonic_text != "":
		var tp := StrudelUtil.tokenize_note(tonic_text)
		if tp.is_empty():
			return {"ok": false}
		tonic_pc = String(tp[0]).to_upper() + String(tp[1])
		if tp[2] != null:
			octave = int(tp[2])
	return {
		"ok": true,
		"tonic_pc": tonic_pc,
		"octave": octave,
		"tokens": intervals_text.split(" ", false),
	}


static func _apply_scale(value: Variant, scale_name: String) -> Variant:
	## 🔴 Что вернуть — решает ВХОД. Пришло простое значение (число или строка)
	## — лад отдаёт СТРОКУ-НОТУ; пришёл словарь — словарь с полем note
	## (`tonal.mjs:320`). Спутать это значит получить `{note:{note:"B3"}}`
	## после следующего `.note()`.
	##
	## `null` на выходе значит ВЫБРОСИТЬ событие: имя лада не разобралось.
	## Так делает и Булка (`errorLogger` плюс `removeUndefineds`), и на этом
	## держится вся раскладка `.scale('C bebop major')` — из трёх долей
	## остаётся одна.
	var is_object := value is Dictionary
	var v: Dictionary = value if is_object else {"n": value}
	var step: Variant = v.get("note", v.get("n", v.get("value")))
	if step == null:
		return value

	var sc := get_scale(scale_name)
	if not sc.get("ok", false):
		# 🔴 Ветка «на входе нота» в оригинале НЕ обёрнута try/catch
		# (`tonal.mjs:303`): исключение оттуда уносит весь запрос. Ветка
		# «на входе ступень» обёрнута — там событие просто выбрасывается.
		if (step is String or step is StringName) and StrudelUtil.is_note(String(step)):
			StrudelPattern.fault("не знаю лада \"%s\"" % scale_name)
		return null
	var tokens: PackedStringArray = sc["tokens"]
	var tonic_pc: String = sc["tonic_pc"]
	var octave: int = sc["octave"]

	var note_name: String
	if (step is String or step is StringName) and StrudelUtil.is_note(String(step)):
		# Нота на входе — подтягиваем к ближайшей ступени лада.
		note_name = _nearest_scale_note(tokens, tonic_pc, String(step))
	elif step is String or step is StringName:
		var pair := _step_and_offset(String(step))
		note_name = _scale_step(tokens, tonic_pc, octave, int(pair[0]))
		if int(pair[1]) != 0:
			note_name = transpose_note(note_name, int(pair[1]))
	else:
		note_name = _scale_step(tokens, tonic_pc, octave,
			int(ceil(StrudelPattern._num(step))))

	if not is_object:
		return note_name
	var out := {}
	for k in v:
		if k in ["n", "value", "note"]:
			continue
		out[k] = v[k]
	out["note"] = note_name
	return out


static func _scale_step(tokens: PackedStringArray, tonic_pc: String,
		tonic_octave: int, step: int) -> String:
	## Ступень лада по номеру, с переносом октав. Перенос `scaleStep`
	## (`tonal.mjs:36`): название берётся сложением ИНТЕРВАЛА, а не полутонов.
	var count := tokens.size()
	if count == 0:
		return tonic_pc + str(tonic_octave)
	var oct_offset := int(floor(float(step) / float(count)))
	var pos := StrudelUtil.mod_i(step, count)
	var parts := interval_parts(String(tokens[pos]))
	var number: int = int(parts[0]) + oct_offset * 7
	var semis: int = int(parts[1]) + oct_offset * 12
	return transpose_by(tonic_pc + str(tonic_octave), number, semis)


static func _nearest_scale_note(tokens: PackedStringArray, tonic_pc: String,
		note: String) -> String:
	## Подтянуть ноту к ближайшей ступени лада (`_getNearestScaleNote`).
	var target := StrudelUtil.note_to_midi(note, 3)
	var names: Array = []
	var midis: Array = []
	for token in tokens:
		var ip := interval_parts(String(token))
		var n := transpose_by(tonic_pc + "0", int(ip[0]), int(ip[1]))
		names.append(n)
		midis.append(StrudelUtil.note_to_midi(n, 0))
	var octave_note := transpose_by(tonic_pc + "0", 8, 12)
	names.append(octave_note)
	midis.append(StrudelUtil.note_to_midi(octave_note, 0))

	var root: int = int(midis[0])
	var oct_diff := int(floor(float(target - root) / 12.0))
	var best := 0
	var best_diff := 1e9
	for i in midis.size():
		var m: int = int(midis[i]) + 12 * oct_diff
		var d := absf(float(m - target))
		if d <= best_diff:
			best_diff = d
			best = i
	var chosen := String(names[best])
	var cp := StrudelUtil.tokenize_note(chosen)
	var base_oct: int = cp[2] if cp[2] != null else 0
	return String(cp[0]) + String(cp[1]) + str(base_oct + oct_diff)


static func _step_and_offset(text: String) -> Array:
	## "0" → [0, 0]; "0#" → [0, +1]; "2b" → [2, −1].
	var digits := ""
	var offset := 0
	for i in text.length():
		var c := text[i]
		if (c >= "0" and c <= "9") or c == "-":
			digits += c
		elif c == "#" or c == "s":
			offset += 1
		elif c == "b" or c == "f":
			offset -= 1
	return [digits.to_int() if digits != "" else 0, offset]

static func arp_with(pat: StrudelPattern, fn: Callable) -> StrudelPattern:
	## Разбор созвучия СВОИМ правилом: на вход даётся список одновременных
	## событий, на выход — что из них играть. `arp` — частный случай.
	return pat.collect().fmap(func(v) -> StrudelPattern:
		return StrudelPattern.reify(fn.call(v))
	).inner_join().with_hap(func(h: StrudelHap) -> StrudelHap:
		# 🔴 Внутри значения лежит СОБЫТИЕ, а не готовое значение: список от
		# `collect` состоит из событий, и правило возвращает одно из них.
		# Разворачиваем и подмешиваем его окружение.
		if not h.value is StrudelHap:
			return h
		var inner: StrudelHap = h.value
		var ctx: Dictionary = (h.context as Dictionary).duplicate()
		for k in inner.context:
			if not ctx.has(k):
				ctx[k] = inner.context[k]
		return StrudelHap.new(h.whole, h.part, inner.value, ctx)
	)


static func voicings(pat: StrudelPattern, dictionary: Variant) -> StrudelPattern:
	## Устаревший путь: символы аккордов → ноты с ПЛАВНЫМ ВЕДЕНИЕМ голосов.
	##
	## 🔴 Память о прошлой раскладке общая на всю игру — так и в оригинале
	## (`voicings.mjs:145`, «this now has to be global»): `register`
	## пересобирает функцию на каждый вызов, и местная память обнулялась бы.
	## Рекомендуемый путь — `voicing`, он без памяти.
	var name := StrudelUtil.text(dictionary)
	if name == "":
		name = "ireal"
	return pat.fmap(func(value) -> StrudelPattern:
		var chord_text := StrudelUtil.text(value["chord"]) \
			if (value is Dictionary and (value as Dictionary).has("chord")) \
			else StrudelUtil.text(value)
		var notes := render_voicing({
			"chord": chord_text,
			"dictionary": StrudelVoicingTable.dictionary(name),
			"mode": "below",
			"anchor": _last_voicing[0] if _last_voicing[0] != null else "c5",
		})
		if notes.is_empty():
			return StrudelPattern.silence()
		_last_voicing[0] = notes[notes.size() - 1]
		var layers: Array = []
		for n in notes:
			layers.append(StrudelPattern.pure(n))
		return StrudelPattern.stack(layers)
	).outer_join()


## Последняя сыгранная раскладка — к ней подтягивается следующая.
static var _last_voicing: Array = [null]


static func arp(pat: StrudelPattern, indices: Variant) -> StrudelPattern:
	## Разбивает созвучие на голоса по номерам.
	##
	## 🔴 ЧЕРЕЗ `arp_with`, А НЕ СВОИМ СБОРОМ. Раньше здесь был собственный
	## «столбик» и разворот, и он отдавал ЗНАЧЕНИЕ события вместо самого
	## события — вместе с ним пропадало окружение, в котором лежит метка
	## лада. Замерено: `n("[0,2,4]").scale("C:major").arp("0 1 2")
	## .scaleTranspose(1)` давало НОЛЬ событий, потому что `scaleTranspose`
	## не находил лада и срывал запрос. `arp_with` возвращает событие целиком
	## и подмешивает его окружение обратно — в оригинале `arp` построен
	## именно на нём.
	var index_pat := StrudelPattern.reify(indices)
	return arp_with(pat, func(haps: Array) -> StrudelPattern:
		return index_pat.fmap(func(i) -> Variant:
			if haps.is_empty():
				return null
			var k := StrudelUtil.mod_i(int(StrudelPattern._num(i)), haps.size())
			return haps[k]
		)
	)


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

# ═══════════════════════════════════════════════════════════════════════════
# Готовые сокращения
# ═══════════════════════════════════════════════════════════════════════════

## Верхняя нота фортепианного диапазона, по которой считается панорама.
const PIANO_TOP := 108.0


static func piano(pat: StrudelPattern) -> StrudelPattern:
	## `.piano()` — не просто звук.
	##
	## Кроме `s("piano")` он ставит `clip` (если не задан), короткое отпускание
	## и РАСКЛАДЫВАЕТ НОТЫ ПО ПАНОРАМЕ ПО ВЫСОТЕ: низкие левее, высокие правее.
	## Формула снята с живой Булки и сверена на шести нотах:
	##   pan = (заданный pan или 1) × (0.5 + (min(midi/108, 1) − 0.5) × 0.5)
	return pat.fmap(func(v):
		var d: Dictionary = (v as Dictionary).duplicate() if v is Dictionary else {"value": v}
		if not d.has("clip"):
			d["clip"] = 1
		return d
	).ctrl("s", "piano").ctrl("release", 0.1).fmap(func(v):
		if not v is Dictionary:
			return v
		var d: Dictionary = (v as Dictionary).duplicate()
		var midi := float(note_or_midi(d.get("note", 60)))
		var x: float = minf(round(midi) / PIANO_TOP, 1.0)
		var spread := 0.5 + (x - 0.5) * 0.5
		var existing := float(d["pan"]) if d.has("pan") else 1.0
		d["pan"] = existing * spread
		return d
	)


static func scale_transpose(pat: StrudelPattern, offset: Variant) -> StrudelPattern:
	## Сдвиг ПО СТУПЕНЯМ лада, а не по полутонам. Требует, чтобы до него уже
	## был вызван `.scale(...)` — имя лада берётся из контекста события.
	return pat._patternify([offset], func(vals: Array) -> StrudelPattern:
		var steps := int(StrudelPattern._num(vals[0]))
		return pat.with_haps(func(haps: Array, _state) -> Array:
			var out: Array = []
			for hap in haps:
				var scale_name := String((hap as StrudelHap).context.get("scale", ""))
				if scale_name == "":
					StrudelPattern.fault("scaleTranspose без предшествующего scale")
					return []
				var value = hap.value
				if value is Dictionary:
					var d: Dictionary = (value as Dictionary).duplicate()
					var moved := _scale_offset(scale_name, steps, StrudelUtil.text(d.get("note", "")))
					if moved == "":
						return []
					d["note"] = moved
					out.append(StrudelHap.new(hap.whole, hap.part, d, hap.context))
				elif value is String or value is StringName:
					var moved2 := _scale_offset(scale_name, steps, String(value))
					if moved2 == "":
						return []
					out.append(StrudelHap.new(hap.whole, hap.part, moved2, hap.context))
				else:
					# 🔴 Оригинал здесь БРОСАЕТ («can only use scaleTranspose
					# with notes»), а не пропускает событие мимо.
					StrudelPattern.fault("scaleTranspose не по нотам")
					return []
			return out
		)
	)


static func _scale_offset(scale_name: String, offset: int, note: String) -> String:
	## Шаг по ступеням лада с переносом октавы. Перенос `scaleOffset`
	## из `tonal.mjs:49` — включая правило «октава меняется на ноте C».
	##
	## Пустая строка на выходе значит СРЫВ запроса: оригинал в этих случаях
	## бросает исключение, и оно уносит весь запрос целиком.
	var sc := get_scale(scale_name)
	if not sc.get("ok", false):
		StrudelPattern.fault("не знаю лада \"%s\"" % scale_name)
		return ""
	var tonic_pc: String = sc["tonic_pc"]
	var tokens: PackedStringArray = sc["tokens"]

	# 🔴 Ступени лада — НАЗВАНИЯ нот, а не хроматические номера. У соль мажора
	# седьмая ступень «F#», а не «Gb»; сравнение в оригинале строковое, и по
	# хроме нота бы не нашлась.
	var names: Array = []
	for token in tokens:
		var ip := interval_parts(String(token))
		var n := transpose_by(tonic_pc + "0", int(ip[0]), int(ip[1]))
		var np := StrudelUtil.tokenize_note(n)
		names.append(String(np[0]) + String(np[1]))

	var tok := StrudelUtil.tokenize_note(note)
	if tok.is_empty():
		StrudelPattern.fault("\"%s\" — не нота" % note)
		return ""
	var from_pc := String(tok[0]).to_upper() + String(tok[1])
	var octave: int = tok[2] if tok[2] != null else 3
	var index := names.find(from_pc)
	if index < 0:
		StrudelPattern.fault("нота \"%s\" не входит в лад \"%s\"" % [note, scale_name])
		return ""

	var i := index
	var o := octave
	var n2 := from_pc
	var direction := signi(offset)
	while absi(i - index) < absi(offset):
		i += direction
		var idx := StrudelUtil.mod_i(i, names.size())
		if direction < 0 and n2.begins_with("C"):
			o += direction
		n2 = String(names[idx])
		if direction > 0 and n2.begins_with("C"):
			o += direction
	return n2 + str(o)
