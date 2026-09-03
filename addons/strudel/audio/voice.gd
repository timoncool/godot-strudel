@tool
class_name StrudelVoice
extends RefCounted

## Один звучащий голос: источник, огибающая, цепь эффектов, панорама.
##
## Цепь идёт В ТОМ ЖЕ ПОРЯДКЕ, что в `packages/superdough/superdough.mjs`
## (номера строк оригинала):
##
##   источник → gain(706) → lpf(737) → hpf(774) → bpf(809) → vowel(823)
##   → coarse(830) → crush(835) → shape(840) → distort(845) → tremolo(878)
##   → compressor(891) → pan(899) → phaser(913) → delay(925) → room(960)
##   → release(973) → postgain(979)
##
## 🔴 Порядок менять «как удобнее» нельзя: `crush` до фильтра и после фильтра
## звучат по-разному, и это слышно.
##
## Пила, меандр и треугольник берутся из таблиц с ограниченной полосой —
## см. StrudelWavetable. Наивные «зубцы» дают призвуки на высоких
## (алиасинг), а PolyBLEP, который стоял здесь раньше, звучит громче
## эталона: WebAudio приводит волну к единичному пику, и у пилы это
## −0.75 дБ, которых у PolyBLEP нет.

enum Source { SILENCE, SINE, SAW, SQUARE, TRIANGLE, WHITE, PINK, BROWN, SAMPLE,
	SUPERSAW, CUSTOM }

## Что звучит.
var source: Source = Source.SINE
## Данные сэмпла (моно, уже приведённые к частоте движка при загрузке).
var sample: PackedFloat32Array = PackedFloat32Array()
var sample_rate := 48000.0
var sample_loop := false

var frequency := 440.0
var speed := 1.0
var gain := 1.0
var postgain := 1.0
## Панорама. Отрицательное значение — «панорамы НЕТ».
##
## 🔴 Strudel вставляет панораматор ТОЛЬКО когда `pan` задан явно
## (`superdough.mjs:898`, `if (fx.pan !== undefined)`). Если панорамировать
## всегда, равномощная панорама в середине даёт множитель 1/√2 — ровно
## три децибела тише эталона по ВСЕМ полосам. Так это и нашлось сверкой.
var pan := -1.0

var envelope: StrudelEnvelope = null
var note_length := 0.5

## Фильтры: 0 — выключен.
var lpf := 0.0
var lpq := 1.0
var hpf := 0.0
var hpq := 1.0

var bpf := 0.0
var bpq := 1.0
## Гласная: "a", "e", "i", "o", "u", "ae", "aa", "oe", "ue", "y"… Пусто — нет.
var vowel := ""

var crush := 0.0
var coarse := 0.0
var shape := 0.0

## Отправки на общие эффекты.
## Перегруз: величина, громкость после него и НОМЕР КРИВОЙ.
## Кривых девять, порядок как в `helpers.mjs:573` — от него зависит, что
## значит число в `.distorttype(3)`.
var distort := 0.0
var distortvol := 1.0
var distort_type := 0

## Тремоло: частота, глубина, перекос, форма и начальная фаза.
var tremolo := 0.0
var tremolo_depth := 1.0
var tremolo_skew := -1.0
var tremolo_shape := -1
var tremolo_phase := 0.0

## Сжатие. Порог в децибелах; NAN значит «выключено».
var compressor := NAN
var compressor_ratio := 10.0
var compressor_knee := 10.0
var compressor_attack := 0.005
var compressor_release := 0.05

## Фазер: частота качания, глубина, середина и размах.
var phaser_rate := -1.0
var phaser_depth := 0.75
var phaser_center := 1000.0
var phaser_sweep := 2000.0

## Огибающие фильтров: [величина, атака, спад, удержание, отпускание, якорь]
## для НЧ, ВЧ и полосового. Пустой массив — огибающей нет, срез постоянный.
var lp_env: Array = []
var hp_env: Array = []
var bp_env: Array = []

## Своя волна: веса обертонов и их фазы. Пусто — волна обычная.
var wave_partials: Array = []
var wave_phases: Array = []
## Какой ряд коэффициентов берётся за основу своей волны.
var wave_base_kind := StrudelWavetable.Kind.USER

## Пила-стая: сколько голосов, насколько разведены по высоте и по панораме.
var unison := 5
var freq_spread := 0.18
var pan_spread := 0.6

## Огибающая ВЫСОТЫ: [полутонов, атака, спад, удержание, отпускание, якорь].
var pitch_env: Array = []
## Дрожание высоты: частота и размах в полутонах.
var vibrato := 0.0
var vibrato_depth := 0.5

## Частотная модуляция. Каждый источник — словарь
## {ratio, wave, adsr}; связи — тройки [откуда, куда, сила].
## Ноль в «куда» значит саму ноту.
var fm_sources: Array = []
var fm_routes: Array = []

var room := 0.0
var delay_send := 0.0
var orbit := 0

## Голос ещё звучит.
var active := false
## Сколько отсчётов уже сыграно.
var _pos := 0
## Сколько отсчётов молчать перед началом — так удар попадает на ТОЧНЫЙ
## отсчёт внутри буфера, а не на его границу.
var start_delay := 0
var _phase := 0.0
## Какая таблица волны нужна и как перетечь к следующей.
var _wave_kind := -1
var _wave_lo := 0
var _wave_hi := 0
var _wave_mix := 0.0
var _wave_key := ""
var _super_phase := PackedFloat32Array()
var _fm_phase := PackedFloat32Array()
var _vib_phase := 0.0
## Последние отсчёты стаи по ушам — панораму она делает сама.
var _super_l := 0.0
var _super_r := 0.0
var _sample_pos := 0.0
var _rate := 48000.0
var _brown := 0.0
var _pink := PackedFloat32Array()
# Состояния биквадов (по два прошлых входа и выхода).
var _lp := [0.0, 0.0, 0.0, 0.0]
var _hp := [0.0, 0.0, 0.0, 0.0]
var _lp_coef := PackedFloat32Array()
var _hp_coef := PackedFloat32Array()
var _bp := [0.0, 0.0, 0.0, 0.0]
var _bp_coef := PackedFloat32Array()
# Гласная — пять параллельных полосовых, их состояния лежат подряд.
var _vw_coef := PackedFloat32Array()
var _vw_gain := PackedFloat32Array()
var _vw_state := PackedFloat32Array()
## Сколько отсчётов держится один пересчёт управляющих величин.
const ENV_BLOCK := 32

var _trem_phase := 0.0
var _comp_env := 1.0
var _phaser_phase := 0.0
var _phaser_state := [0.0, 0.0, 0.0, 0.0]
var _coarse_hold := 0.0
var _coarse_count := 0


func start(mix_rate: float) -> void:
	_rate = mix_rate
	_pos = 0
	_phase = 0.0
	_sample_pos = 0.0
	_brown = 0.0
	_pink = PackedFloat32Array()
	_pink.resize(7)
	_lp = [0.0, 0.0, 0.0, 0.0]
	_hp = [0.0, 0.0, 0.0, 0.0]
	_coarse_hold = 0.0
	_coarse_count = 0
	if envelope == null:
		envelope = StrudelEnvelope.new()
	_lp_coef = _biquad_lowpass(lpf, lpq) if lpf > 0.0 else PackedFloat32Array()
	_hp_coef = _biquad_highpass(hpf, hpq) if hpf > 0.0 else PackedFloat32Array()
	_bp_coef = _biquad_bandpass(bpf, bpq) if bpf > 0.0 else PackedFloat32Array()
	_bp = [0.0, 0.0, 0.0, 0.0]
	_setup_vowel()
	_setup_wavetable()
	_super_phase = PackedFloat32Array()
	if source == Source.SUPERSAW:
		var count := clampi(unison, 1, 100)
		_super_phase.resize(count)
		for i in count:
			# 🔴 Начальные фазы СЛУЧАЙНЫ — так в оригинале. Одинаковые фазы
			# дали бы в первый миг сложение всех голосов в один щелчок.
			_super_phase[i] = randf()
	_fm_phase = PackedFloat32Array()
	if not fm_sources.is_empty():
		_fm_phase.resize(fm_sources.size())
	active = true


func _setup_wavetable() -> void:
	## Выбор двух соседних таблиц и веса перетекания — по частоте ноты.
	##
	## 🔴 Считается ОДИН РАЗ на ноту, а не на отсчёт: у WebAudio таблица
	## тоже выбирается по частоте осциллятора, а она за ноту не меняется.
	_wave_kind = -1
	_wave_key = ""
	match source:
		Source.SAW: _wave_kind = StrudelWavetable.Kind.SAW
		Source.SQUARE: _wave_kind = StrudelWavetable.Kind.SQUARE
		Source.TRIANGLE: _wave_kind = StrudelWavetable.Kind.TRIANGLE
		Source.CUSTOM: _wave_kind = StrudelWavetable.Kind.USER
	if _wave_kind < 0:
		return
	var f := absf(frequency * speed)
	var pos := StrudelWavetable.range_position(f, _rate)
	_wave_lo = clampi(int(floor(pos)), 0, StrudelWavetable.RANGES - 1)
	_wave_hi = clampi(_wave_lo + 1, 0, StrudelWavetable.RANGES - 1)
	_wave_mix = clampf(pos - float(_wave_lo), 0.0, 1.0)
	if source == Source.CUSTOM:
		_wave_kind = wave_base_kind
		_wave_key = StrudelWavetable.custom_key(wave_partials, wave_phases, _wave_kind)
		StrudelWavetable.custom_table(_wave_key, wave_partials, wave_phases,
			_wave_kind, _wave_lo)
		StrudelWavetable.custom_table(_wave_key, wave_partials, wave_phases,
			_wave_kind, _wave_hi)
		return
	# Таблицы строятся заранее, чтобы не считать их посреди буфера.
	StrudelWavetable.table(_wave_kind, _wave_lo)
	StrudelWavetable.table(_wave_kind, _wave_hi)


func _setup_vowel() -> void:
	_vw_coef = PackedFloat32Array()
	_vw_gain = PackedFloat32Array()
	_vw_state = PackedFloat32Array()
	if vowel == "":
		return
	var formant: Dictionary = StrudelVowels.get_formant(vowel)
	if formant.is_empty():
		push_warning("Strudel: не знаю гласной \"%s\"" % vowel)
		return
	var freqs: Array = formant["freqs"]
	var qs: Array = formant["qs"]
	var gains: Array = formant["gains"]
	for i in freqs.size():
		var c := _biquad_bandpass(float(freqs[i]), float(qs[i]))
		for k in 5:
			_vw_coef.append(c[k])
		_vw_gain.append(float(gains[i]))
		for k in 4:
			_vw_state.append(0.0)


func total_frames() -> int:
	return int(envelope.total_length(note_length) * _rate)


func render(left: PackedFloat32Array, right: PackedFloat32Array, from_frame: int, count: int,
		room_bus: PackedFloat32Array, delay_bus: PackedFloat32Array) -> void:
	## Досыпает свой звук в общий буфер, начиная с кадра from_frame.
	if not active:
		return
	var total := total_frames()
	# Панорама равной мощности — как StereoPanner в WebAudio, но только если
	# её просили: без `pan` сигнал идёт в оба канала целиком.
	var gl := 1.0
	var gr := 1.0
	if pan >= 0.0:
		var angle := pan * (PI * 0.5)
		gl = cos(angle)
		gr = sin(angle)

	# 🔴 Всё, что можно, вынесено ИЗ цикла и развёрнуто в локальные переменные.
	# Вызов функции в GDScript стоит дороже самой арифметики: пока огибающая,
	# биквад и источник звука были отдельными методами, голос обходился вшестеро
	# дороже, чем та же математика в теле цикла (замерено tools/bench_audio.gd).
	var buf_len := left.size()
	var pos := _pos
	var phase := _phase
	var spos := _sample_pos
	var rate := _rate
	var src := source
	var g := gain
	var post := postgain
	var freq_step := frequency * speed / rate
	var sample_step := speed * (sample_rate / rate)
	var sample_last := sample.size() - 1
	var wave_lo := StrudelWavetable.table(_wave_kind, _wave_lo) if _wave_kind >= 0 \
		else PackedFloat32Array()
	var wave_hi := StrudelWavetable.table(_wave_kind, _wave_hi) if _wave_kind >= 0 \
		else PackedFloat32Array()
	var wave_mix := _wave_mix
	var wave_size := StrudelWavetable.SIZE
	if _wave_kind >= 0 and _wave_key != "":
		wave_lo = StrudelWavetable.custom_table(_wave_key, wave_partials,
			wave_phases, _wave_kind, _wave_lo)
		wave_hi = StrudelWavetable.custom_table(_wave_key, wave_partials,
			wave_phases, _wave_kind, _wave_hi)

	# ── частотная модуляция ──
	var use_fm := not fm_sources.is_empty() and not fm_routes.is_empty()
	var fm_count := fm_sources.size()
	var fm_phase := _fm_phase
	var fm_out := PackedFloat32Array()
	var fm_dev := PackedFloat32Array()
	if use_fm:
		fm_out.resize(fm_count)
		fm_dev.resize(fm_count + 1)

	# ── дрожание и огибающая высоты: сдвиг в ПОЛУТОНАХ ──
	var use_vib := vibrato > 0.0
	var vib_step := vibrato / rate if use_vib else 0.0
	var vib_phase := _vib_phase
	var use_penv := not pitch_env.is_empty()

	# ── пила-стая ──
	var super_count := _super_phase.size()
	var super_scale := 1.0 / sqrt(float(maxi(super_count, 1)))
	var super_spread := clampf(pan_spread, 0.0, 1.0) if super_count > 1 else 0.0
	var super_detune := freq_spread
	var base_freq := frequency

	# огибающая — в отсчётах, без деления на каждом шаге
	var a_end := envelope.attack * rate
	var d_end := a_end + envelope.decay * rate
	var sus := envelope.sustain
	var note_end := note_length * rate
	var rel := envelope.release * rate
	# Уровень, С КОТОРОГО начинается отпускание. У короткой ноты она гаснет
	# ещё на подъёме или на спаде, и брать сустейн нельзя — иначе на коротких
	# нотах звук на треть децибела громче, чем должен быть.
	var rel_from := sus
	if note_end < a_end:
		rel_from = note_end / a_end
	elif note_end < d_end:
		rel_from = 1.0 + (sus - 1.0) * ((note_end - a_end) / (d_end - a_end))

	var use_lp := not _lp_coef.is_empty()
	var use_hp := not _hp_coef.is_empty()
	var lb0 := _lp_coef[0] if use_lp else 0.0
	var lb1 := _lp_coef[1] if use_lp else 0.0
	var lb2 := _lp_coef[2] if use_lp else 0.0
	var la1 := _lp_coef[3] if use_lp else 0.0
	var la2 := _lp_coef[4] if use_lp else 0.0
	var lx1: float = _lp[0]
	var lx2: float = _lp[1]
	var ly1: float = _lp[2]
	var ly2: float = _lp[3]
	var hb0 := _hp_coef[0] if use_hp else 0.0
	var hb1 := _hp_coef[1] if use_hp else 0.0
	var hb2 := _hp_coef[2] if use_hp else 0.0
	var ha1 := _hp_coef[3] if use_hp else 0.0
	var ha2 := _hp_coef[4] if use_hp else 0.0
	var hx1: float = _hp[0]
	var hx2: float = _hp[1]
	var hy1: float = _hp[2]
	var hy2: float = _hp[3]

	var use_bp := not _bp_coef.is_empty()
	var pb0 := _bp_coef[0] if use_bp else 0.0
	var pb1 := _bp_coef[1] if use_bp else 0.0
	var pb2 := _bp_coef[2] if use_bp else 0.0
	var pa1 := _bp_coef[3] if use_bp else 0.0
	var pa2 := _bp_coef[4] if use_bp else 0.0
	var px1: float = _bp[0]
	var px2: float = _bp[1]
	var py1: float = _bp[2]
	var py2: float = _bp[3]
	var use_vowel := not _vw_gain.is_empty()
	var vowel_bands := _vw_gain.size()

	var use_crush := crush > 0.0
	var crush_steps := pow(2.0, crush - 1.0) if use_crush else 1.0
	var use_shape := shape > 0.0
	var shape_k := clampf(shape, 0.0, 0.99)
	var shape_f := 2.0 * shape_k / (1.0 - shape_k) if use_shape else 0.0
	var use_coarse := coarse > 1.0
	var coarse_n := int(coarse) if use_coarse else 1
	var use_room := room > 0.0
	var use_delay := delay_send > 0.0

	# ── перегруз ──
	var use_distort := distort != 0.0
	var distort_k := exp(distort) - 1.0 if use_distort else 0.0
	var distort_gain := clampf(distortvol, 0.001, 1.0)
	var distort_algo := distort_type

	# ── тремоло ──
	# 🔴 Глубина ВЫЧИТАЕТСЯ из единицы, а качание ПРИБАВЛЯЕТСЯ к ней
	# (`superdough.mjs:878`): при глубине 1 звук уходит в ноль на дне
	# волны, а не просто становится тише.
	var use_tremolo := tremolo > 0.0
	var trem_base := maxf(1.0 - tremolo_depth, 0.0)
	var trem_skew := tremolo_skew if tremolo_skew >= 0.0 \
		else (0.5 if tremolo_shape >= 0 else 1.0)
	var trem_shape := tremolo_shape if tremolo_shape >= 0 else 0
	var trem_step := tremolo / rate if use_tremolo else 0.0
	var trem_phase := _trem_phase

	# ── сжатие ──
	var use_comp := not is_nan(compressor)
	var comp_thresh := compressor
	var comp_ratio := maxf(compressor_ratio, 1.0)
	var comp_knee := maxf(compressor_knee, 0.0)
	var comp_att := maxf(compressor_attack, 0.0001)
	var comp_rel := maxf(compressor_release, 0.0001)
	var comp_att_c := exp(-1.0 / (comp_att * rate))
	var comp_rel_c := exp(-1.0 / (comp_rel * rate))
	var comp_env := _comp_env
	var comp_curve: Array = _compressor_curve(comp_thresh, comp_knee, comp_ratio) \
		if use_comp else []
	var comp_makeup := float(comp_curve[3]) if use_comp else 1.0

	# ── фазер ──
	var use_phaser := phaser_rate > 0.0 and phaser_depth > 0.0
	var phaser_q := 2.0 - clampf(phaser_depth * 2.0, 0.0, 1.9)
	var phaser_base := phaser_center + 282.0
	var phaser_step := phaser_rate / rate if use_phaser else 0.0
	var phaser_ph := _phaser_phase
	var fb0 := 0.0
	var fb1 := 0.0
	var fb2 := 0.0
	var fa1 := 0.0
	var fa2 := 0.0
	var fx1: float = _phaser_state[0]
	var fx2: float = _phaser_state[1]
	var fy1: float = _phaser_state[2]
	var fy2: float = _phaser_state[3]

	# ── огибающие фильтров ──
	# Пересчёт коэффициентов идёт не каждый отсчёт, а раз в BLOCK: WebAudio
	# так же меряет управляющие величины раз в квант (128 отсчётов), и
	# считать чаще незачем.
	var lp_has_env := not lp_env.is_empty() and lpf > 0.0
	var hp_has_env := not hp_env.is_empty() and hpf > 0.0
	var bp_has_env := not bp_env.is_empty() and bpf > 0.0
	var env_block := 0

	var i := 0
	while i < count:
		if start_delay > 0:
			start_delay -= 1
			i += 1
			continue
		if pos >= total:
			active = false
			break
		var idx := from_frame + i
		if idx >= buf_len:
			break

		if (lp_has_env or hp_has_env or bp_has_env) and env_block == 0:
			var sec := float(pos) / rate
			if lp_has_env:
				var c := _biquad_lowpass(_filter_env_value(sec, lp_env, lpf), lpq)
				lb0 = c[0]
				lb1 = c[1]
				lb2 = c[2]
				la1 = c[3]
				la2 = c[4]
				use_lp = true
			if hp_has_env:
				var ch := _biquad_highpass(_filter_env_value(sec, hp_env, hpf), hpq)
				hb0 = ch[0]
				hb1 = ch[1]
				hb2 = ch[2]
				ha1 = ch[3]
				ha2 = ch[4]
				use_hp = true
			if bp_has_env:
				var cb := _biquad_bandpass(_filter_env_value(sec, bp_env, bpf), bpq)
				pb0 = cb[0]
				pb1 = cb[1]
				pb2 = cb[2]
				pa1 = cb[3]
				pa2 = cb[4]
				use_bp = true
		if use_phaser and env_block == 0:
			# Качание идёт в ЦЕНТАХ (`detune`), поэтому частота множится на
			# два в степени «центы делить на тысячу двести».
			var lv := lfo_shape(0, phaser_ph, 0.5) - 0.5
			var cents := lv * phaser_sweep * 2.0
			var cf := clampf(phaser_base * pow(2.0, cents / 1200.0), 10.0, 20000.0)
			var cn := _biquad_notch(cf, phaser_q)
			fb0 = cn[0]
			fb1 = cn[1]
			fb2 = cn[2]
			fa1 = cn[3]
			fa2 = cn[4]
		env_block += 1
		if env_block >= ENV_BLOCK:
			env_block = 0

		# ── сдвиг высоты: вибрато и огибающая, оба в ПОЛУТОНАХ ──
		var semis := 0.0
		if use_vib:
			semis += sin(TAU * vib_phase) * vibrato_depth
			vib_phase += vib_step
			if vib_phase >= 1.0:
				vib_phase -= 1.0
		if use_penv:
			semis += _pitch_env_value(float(pos) / rate) / 100.0
		var pitch_mul := pow(2.0, semis / 12.0) if semis != 0.0 else 1.0

		# ── частотная модуляция ──
		# 🔴 Сперва снимаются ВСЕ голоса модуляции по их нынешним фазам, и
		# только потом фазы двигаются: источники могут качать друг друга, и
		# при последовательном обходе порядок решал бы звук.
		var carrier_dev := 0.0
		if use_fm:
			for k in fm_count:
				var srcd: Dictionary = fm_sources[k]
				fm_out[k] = _fm_source_sample(k, fm_phase[k], float(pos) / rate, srcd)
				fm_dev[k + 1] = 0.0
			fm_dev[0] = 0.0
			for r in fm_routes:
				var from_i: int = r[0]
				var to_i: int = r[1]
				var amt: float = r[2]
				var srcd2: Dictionary = fm_sources[from_i]
				var mod_freq: float = base_freq * float(srcd2.get("ratio", 1.0))
				fm_dev[to_i] += fm_out[from_i] * amt * mod_freq
			carrier_dev = fm_dev[0]
			for k in fm_count:
				var srcd3: Dictionary = fm_sources[k]
				var f_k: float = base_freq * float(srcd3.get("ratio", 1.0)) + fm_dev[k + 1]
				var p_k: float = fm_phase[k] + f_k / rate
				p_k = p_k - floor(p_k)
				fm_phase[k] = p_k

		var step := freq_step
		if pitch_mul != 1.0 or carrier_dev != 0.0:
			step = (base_freq * pitch_mul + carrier_dev) * speed / rate

		# ── источник ──
		var raw := 0.0
		if src == Source.SAMPLE:
			var si := int(spos)
			if si >= sample_last:
				if sample_loop and sample_last > 0:
					spos = fmod(spos, float(sample_last))
					si = int(spos)
				else:
					active = false
					break
			var fr := spos - float(si)
			raw = sample[si] * (1.0 - fr) + sample[si + 1] * fr
			spos += sample_step
		elif src == Source.SINE:
			raw = sin(TAU * phase)
			phase += step
			if phase >= 1.0:
				phase -= 1.0
		elif src == Source.SUPERSAW:
			# Стая пил, разведённых по высоте; панорама голосов чередуется.
			var spread_half := super_spread * 0.5 + 0.5
			var g1 := sqrt(1.0 - spread_half)
			var g2 := sqrt(spread_half)
			var f_base := base_freq * pitch_mul * pow(2.0, 0.0)
			# растяжка стаи: от −половины до +половины разброса
			var scale_v := super_detune / float(maxi(super_count - 1, 1))
			var center := super_detune * 0.5
			var accl := 0.0
			var accr := 0.0
			for v in super_count:
				var dt_v := float(v) * scale_v - center if super_count > 1 else 0.0
				var f_v := f_base * pow(2.0, dt_v / 12.0)
				var dtn := f_v / rate
				dtn = dtn - floor(dtn)
				var ph_v: float = _super_phase[v]
				var vv := 2.0 * ph_v - 1.0 - _poly_blep(ph_v, dtn)
				accl += vv * g1
				accr += vv * g2
				var pn := ph_v + dtn
				if pn >= 1.0:
					pn -= 1.0
				_super_phase[v] = pn
				var tmp_g := g1
				g1 = g2
				g2 = tmp_g
			# Оба уха уже собраны; дальше цепь мономерная, поэтому берём
			# полусумму, а разведение возвращаем панорамой на выходе.
			raw = (accl + accr) * 0.5 * super_scale
			_super_l = accl * super_scale
			_super_r = accr * super_scale
		elif src == Source.SAW or src == Source.SQUARE or src == Source.TRIANGLE \
				or src == Source.CUSTOM:
			# Две соседние таблицы и перетекание между ними — как в
			# WebAudio: одна на октаву, вес по дробной части номера.
			var x := phase * float(wave_size)
			var wi := int(x)
			if wi < 0:
				wi = 0
			elif wi >= wave_size:
				wi = wave_size - 1
			var wf := x - float(wi)
			var lo_v: float = wave_lo[wi] * (1.0 - wf) + wave_lo[wi + 1] * wf
			var hi_v: float = wave_hi[wi] * (1.0 - wf) + wave_hi[wi + 1] * wf
			raw = lo_v + (hi_v - lo_v) * wave_mix
			phase += step
			if phase >= 1.0:
				phase -= 1.0
		elif src == Source.WHITE:
			raw = randf() * 2.0 - 1.0
		elif src == Source.PINK:
			raw = _pink_sample()
		elif src == Source.BROWN:
			_brown = clampf(_brown + (randf() * 2.0 - 1.0) * 0.02, -1.0, 1.0)
			raw = _brown * 3.0

		# ── огибающая (тот же расчёт, что в StrudelEnvelope) ──
		var fpos := float(pos)
		var env := 0.0
		if fpos < a_end:
			env = fpos / a_end
		elif fpos < d_end:
			env = 1.0 + (sus - 1.0) * ((fpos - a_end) / (d_end - a_end))
		elif fpos < note_end:
			env = sus
		else:
			var since := fpos - note_end
			env = rel_from * (1.0 - since / rel) if since < rel else 0.0

		var s := raw * g * env

		# ── цепь, в порядке superdough ──
		if use_lp:
			var ly := lb0 * s + lb1 * lx1 + lb2 * lx2 - la1 * ly1 - la2 * ly2
			lx2 = lx1
			lx1 = s
			ly2 = ly1
			ly1 = ly
			s = ly
		if use_hp:
			var hy := hb0 * s + hb1 * hx1 + hb2 * hx2 - ha1 * hy1 - ha2 * hy2
			hx2 = hx1
			hx1 = s
			hy2 = hy1
			hy1 = hy
			s = hy
		if use_bp:
			var py := pb0 * s + pb1 * px1 + pb2 * px2 - pa1 * py1 - pa2 * py2
			px2 = px1
			px1 = s
			py2 = py1
			py1 = py
			s = py
		if use_vowel:
			# Гласная — пять полосовых ПАРАЛЛЕЛЬНО, сумма с весами и подъёмом
			# на восемь (`vowel.mjs:66`). Последовательно они дали бы тишину.
			var acc := 0.0
			for band in vowel_bands:
				var ci := band * 5
				var si := band * 4
				var xin := s
				var yv: float = (_vw_coef[ci] * xin + _vw_coef[ci + 1] * _vw_state[si]
					+ _vw_coef[ci + 2] * _vw_state[si + 1]
					- _vw_coef[ci + 3] * _vw_state[si + 2]
					- _vw_coef[ci + 4] * _vw_state[si + 3])
				_vw_state[si + 1] = _vw_state[si]
				_vw_state[si] = xin
				_vw_state[si + 3] = _vw_state[si + 2]
				_vw_state[si + 2] = yv
				acc += yv * _vw_gain[band]
			s = acc * 8.0
		if use_coarse:
			if _coarse_count % coarse_n == 0:
				_coarse_hold = s
			_coarse_count += 1
			s = _coarse_hold
		if use_crush and crush_steps >= 1.0:
			s = round(s * crush_steps) / crush_steps
		if use_shape:
			s = (1.0 + shape_f) * s / (1.0 + shape_f * absf(s))
		if use_distort:
			s = distort_gain * distort_sample(s, distort_k, distort_algo)
		if use_tremolo:
			var mv := (lfo_shape(trem_shape, trem_phase, trem_skew)) * tremolo_depth
			mv = pow(maxf(mv, 0.0), 1.5)
			s *= trem_base + clampf(mv, 0.0, 1.0)
			trem_phase += trem_step
			if trem_phase >= 1.0:
				trem_phase -= 1.0
		if use_comp:
			var mag := absf(s)
			# Во сколько раз кривая душит этот отсчёт; единица — не душит.
			var want := _compressor_gain(mag, comp_curve)
			var coef := comp_att_c if want < comp_env else comp_rel_c
			comp_env = want + coef * (comp_env - want)
			s *= comp_env * comp_makeup
		if use_phaser:
			var fy := fb0 * s + fb1 * fx1 + fb2 * fx2 - fa1 * fy1 - fa2 * fy2
			fx2 = fx1
			fx1 = s
			fy2 = fy1
			fy1 = fy
			s = fy
			phaser_ph += phaser_step
			if phaser_ph >= 1.0:
				phaser_ph -= 1.0
		s *= post

		if src == Source.SUPERSAW and absf(raw) > 1e-9:
			# 🔴 Стая пил СТЕРЕО САМА: голоса раскиданы по ушам через один.
			# Цепь эффектов у нас одноканальная, поэтому к ушам возвращается
			# та же разница, помноженная на то, во сколько раз цепь изменила
			# отсчёт. Для линейной цепи это точно, для перегруза — близко.
			var ratio := s / raw
			left[idx] += _super_l * ratio * gl
			right[idx] += _super_r * ratio * gr
		else:
			left[idx] += s * gl
			right[idx] += s * gr
		if use_room:
			room_bus[idx] += s * room
		if use_delay:
			delay_bus[idx] += s * delay_send
		pos += 1
		i += 1

	_pos = pos
	_phase = phase
	_sample_pos = spos
	_lp[0] = lx1
	_lp[1] = lx2
	_lp[2] = ly1
	_lp[3] = ly2
	_hp[0] = hx1
	_hp[1] = hx2
	_hp[2] = hy1
	_hp[3] = hy2
	_bp[0] = px1
	_bp[1] = px2
	_bp[2] = py1
	_bp[3] = py2
	_vib_phase = vib_phase
	_trem_phase = trem_phase
	_comp_env = comp_env
	_phaser_phase = phaser_ph
	_phaser_state[0] = fx1
	_phaser_state[1] = fx2
	_phaser_state[2] = fy1
	_phaser_state[3] = fy2


func _source_sample() -> float:
	match source:
		Source.SAMPLE:
			if sample.is_empty():
				return 0.0
			var idx := int(_sample_pos)
			if idx >= sample.size() - 1:
				if sample_loop:
					_sample_pos = fmod(_sample_pos, float(sample.size() - 1))
					idx = int(_sample_pos)
				else:
					active = false
					return 0.0
			var frac := _sample_pos - float(idx)
			var s: float = sample[idx] * (1.0 - frac) + sample[idx + 1] * frac
			_sample_pos += speed * (sample_rate / _rate)
			return s
		Source.SINE:
			var v := sin(TAU * _phase)
			_advance_phase()
			return v
		Source.SAW:
			var v2 := _phase * 2.0 - 1.0
			_advance_phase()
			return v2
		Source.SQUARE:
			var v3 := 1.0 if _phase < 0.5 else -1.0
			_advance_phase()
			return v3
		Source.TRIANGLE:
			var v4 := 4.0 * absf(_phase - 0.5) - 1.0
			_advance_phase()
			return v4
		Source.WHITE:
			return randf() * 2.0 - 1.0
		Source.PINK:
			return _pink_sample()
		Source.BROWN:
			_brown += (randf() * 2.0 - 1.0) * 0.02
			_brown = clampf(_brown, -1.0, 1.0)
			return _brown * 3.0
	return 0.0


func _advance_phase() -> void:
	_phase += frequency * speed / _rate
	if _phase >= 1.0:
		_phase -= floor(_phase)


func _pink_sample() -> float:
	## Розовый шум методом Восса—Маккартни (семь полос).
	var white := randf() * 2.0 - 1.0
	_pink[0] = 0.99886 * _pink[0] + white * 0.0555179
	_pink[1] = 0.99332 * _pink[1] + white * 0.0750759
	_pink[2] = 0.96900 * _pink[2] + white * 0.1538520
	_pink[3] = 0.86650 * _pink[3] + white * 0.3104856
	_pink[4] = 0.55000 * _pink[4] + white * 0.5329522
	_pink[5] = -0.7616 * _pink[5] - white * 0.0168980
	var out: float = _pink[0] + _pink[1] + _pink[2] + _pink[3] + _pink[4] + _pink[5] + _pink[6] + white * 0.5362
	_pink[6] = white * 0.115926
	return out * 0.11


func _apply_coarse(s: float) -> float:
	## Прореживание частоты дискретизации: каждый N-й отсчёт держится.
	var n := int(coarse)
	if n < 2:
		return s
	if _coarse_count % n == 0:
		_coarse_hold = s
	_coarse_count += 1
	return _coarse_hold


func _apply_crush(s: float) -> float:
	## Огрубление разрядности. Формула superdough: шаг = 2^(crush-1).
	var steps := pow(2.0, crush - 1.0)
	if steps < 1.0:
		return s
	return round(s * steps) / steps


func _apply_shape(s: float) -> float:
	## Мягкое ограничение. shape в 0..1, ближе к единице — жёстче.
	var k := clampf(shape, 0.0, 0.99)
	var factor := 2.0 * k / (1.0 - k)
	return (1.0 + factor) * s / (1.0 + factor * absf(s))


# ── биквады (RBJ, как BiquadFilterNode в WebAudio) ───────────────────────────

func _biquad_lowpass(freq: float, q: float) -> PackedFloat32Array:
	## 🔴 У НЧ и ВЧ добротность задаётся В ДЕЦИБЕЛАХ, а не разом: так
	## записано в описании BiquadFilterNode — `alpha = sin(w)/(2·10^(Q/20))`.
	## У полосового, режекторного и остальных она обычная. Спутать это
	## значит получить другой подъём на срезе.
	var w := TAU * clampf(freq, 10.0, _rate * 0.45) / _rate
	var alpha := sin(w) / (2.0 * pow(10.0, q / 20.0))
	var cw := cos(w)
	var b1 := 1.0 - cw
	var b0 := b1 * 0.5
	var a0 := 1.0 + alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b0 / a0, (-2.0 * cw) / a0, (1.0 - alpha) / a0])


func _biquad_highpass(freq: float, q: float) -> PackedFloat32Array:
	## Добротность в децибелах — см. _biquad_lowpass.
	var w := TAU * clampf(freq, 10.0, _rate * 0.45) / _rate
	var alpha := sin(w) / (2.0 * pow(10.0, q / 20.0))
	var cw := cos(w)
	var b0 := (1.0 + cw) * 0.5
	var b1 := -(1.0 + cw)
	var a0 := 1.0 + alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b0 / a0, (-2.0 * cw) / a0, (1.0 - alpha) / a0])


func _biquad_bandpass(freq: float, q: float) -> PackedFloat32Array:
	## Полосовой с постоянным пиком — как BiquadFilterNode type="bandpass".
	var w := TAU * clampf(freq, 10.0, _rate * 0.45) / _rate
	var alpha := sin(w) / (2.0 * maxf(q, 0.0001))
	var cw := cos(w)
	var a0 := 1.0 + alpha
	return PackedFloat32Array([alpha / a0, 0.0, -alpha / a0, (-2.0 * cw) / a0, (1.0 - alpha) / a0])


func _biquad(x: float, c: PackedFloat32Array, state: Array) -> float:
	var y: float = c[0] * x + c[1] * state[0] + c[2] * state[1] - c[3] * state[2] - c[4] * state[3]
	state[1] = state[0]
	state[0] = x
	state[3] = state[2]
	state[2] = y
	return y


# ═══════════════════════════════════════════════════════════════════════════
# Перегруз, тремоло, сжатие, фазер — математика из superdough
# ═══════════════════════════════════════════════════════════════════════════

## Порядок кривых перегруза — из `helpers.mjs:573`. Номер `distorttype`
## отсчитывается ПО ЭТОМУ СПИСКУ и заворачивается по кругу.
const DISTORT_NAMES := ["scurve", "soft", "hard", "cubic", "diode", "asym",
	"fold", "sinefold", "chebyshev"]


static func distort_index(algo: Variant) -> int:
	if algo is String or algo is StringName:
		var i := DISTORT_NAMES.find(String(algo))
		if i < 0:
			push_warning("Strudel: не знаю перегруза \"%s\" — беру scurve" % algo)
			return 0
		return i
	return StrudelUtil.mod_i(int(StrudelPattern._num(algo)), DISTORT_NAMES.size())


static func _squash(x: float) -> float:
	return x / (1.0 + x)


static func _d_soft(x: float, k: float) -> float:
	return tanh(x * (1.0 + k))


static func _d_fold(x: float, k: float) -> float:
	var y := (1.0 + 0.5 * k) * x
	var window := fmod(fmod(y + 1.0, 4.0) + 4.0, 4.0)
	return 1.0 - absf(window - 2.0)


static func _d_diode(x: float, k: float, asym: bool) -> float:
	var g := 1.0 + 2.0 * k
	var tt := _squash(log(1.0 + k))
	var bias := 0.07 * tt
	var pos := _d_soft(x + bias, 2.0 * k)
	var neg := _d_soft(bias if asym else -x + bias, 2.0 * k)
	var y := pos - neg
	# 🔴 Делим на производную в нуле, чтобы тихое осталось неискажённым.
	var sech := 1.0 / cosh(g * bias)
	var denom := maxf(1e-8, (1.0 if asym else 2.0) * g * sech * sech)
	return _d_soft(y / denom, k)


static func distort_sample(x: float, k: float, algo: int) -> float:
	match algo:
		0: return ((1.0 + k) * x) / (1.0 + k * absf(x))
		1: return _d_soft(x, k)
		2: return clampf((1.0 + k) * x, -1.0, 1.0)
		3:
			var tt := _squash(log(1.0 + k))
			var cubic := (x - (tt / 3.0) * x * x * x) / (1.0 - tt / 3.0)
			return _d_soft(cubic, k)
		4: return _d_diode(x, k, false)
		5: return _d_diode(x, k, true)
		6: return _d_fold(x, k)
		7: return sin((PI / 2.0) * _d_fold(x, k))
		8:
			# Чебышёвские полиномы: гармоники добавляются по рекуррентной
			# формуле, чётные — с убывающим весом.
			var kl := 10.0 * log(1.0 + k)
			var tnm1 := 1.0
			var tnm2 := x
			var y := 0.0
			for i in range(1, 64):
				if i < 2:
					y += tnm2
					continue
				var tn := 2.0 * x * tnm1 - tnm2
				tnm2 = tnm1
				tnm1 = tn
				if i % 2 == 0:
					y += minf(1.3 * kl / float(i), 2.0) * tn
			return _d_soft(y, kl / 20.0)
	return x


## Формы качания у LFO — те же и в тех же номерах, что в `worklets.mjs:72`.
static func lfo_shape(kind: int, phase: float, skew: float) -> float:
	match kind:
		1: return sin(TAU * phase) * 0.5 + 0.5
		2: return phase
		3: return 1.0 - phase
		4: return 0.0 if phase >= skew else 1.0
	# треугольник с перекосом
	var x := 1.0 - skew
	if phase >= skew:
		return 1.0 / x - phase / x if x != 0.0 else 0.0
	return phase / skew if skew != 0.0 else 0.0


func _filter_env_value(pos_sec: float, spec: Array, base_freq: float) -> float:
	## Срез фильтра в этот миг: показательная огибающая, как её строит
	## `getParamADSR` в WebAudio (`helpers.mjs:55`).
	##
	## 🔴 Переходы ПОКАЗАТЕЛЬНЫЕ, а не прямые: ухо слышит частоту
	## логарифмически, и прямой переход даёт совсем другое движение.
	var env: float = spec[0]
	var att: float = spec[1]
	var dec: float = spec[2]
	var sus: float = spec[3]
	var rel: float = spec[4]
	var anchor: float = spec[5]
	var env_abs := absf(env)
	var offset := env_abs * anchor
	var lo := clampf(pow(2.0, -offset) * base_freq, 0.0, 20000.0)
	var hi := clampf(pow(2.0, env_abs - offset) * base_freq, 0.0, 20000.0)
	if env < 0.0:
		var tmp := lo
		lo = hi
		hi = tmp
	if lo == 0.0:
		lo = 0.001
	if hi == 0.0:
		hi = 0.001
	var sustain_val := lo + sus * (hi - lo)
	if sustain_val <= 0.0:
		sustain_val = 0.001
	var duration := note_length

	if pos_sec <= 0.0:
		return lo
	if att > duration:
		var v_end := _env_val_at(duration, att, dec, lo, hi, sustain_val)
		return _exp_ramp(lo, v_end, 0.0, duration, pos_sec) if pos_sec < duration \
			else _exp_ramp(v_end, lo, duration, duration + rel, pos_sec)
	if att + dec > duration:
		if pos_sec < att:
			return _exp_ramp(lo, hi, 0.0, att, pos_sec)
		var v_end2 := _env_val_at(duration, att, dec, lo, hi, sustain_val)
		if pos_sec < duration:
			return _exp_ramp(hi, v_end2, att, duration, pos_sec)
		return _exp_ramp(v_end2, lo, duration, duration + rel, pos_sec)
	if pos_sec < att:
		return _exp_ramp(lo, hi, 0.0, att, pos_sec)
	if pos_sec < att + dec:
		return _exp_ramp(hi, sustain_val, att, att + dec, pos_sec)
	if pos_sec < duration:
		return sustain_val
	return _exp_ramp(sustain_val, lo, duration, duration + rel, pos_sec)


static func _env_val_at(t: float, att: float, dec: float, lo: float, hi: float,
		sustain_val: float) -> float:
	if att > t:
		var slope := (hi - lo) / att if att != 0.0 else 0.0
		return maxf(t * slope + lo, 0.001)
	var slope2 := (sustain_val - hi) / dec if dec != 0.0 else 0.0
	return maxf((t - att) * slope2 + hi, 0.001)


static func _exp_ramp(v0: float, v1: float, t0: float, t1: float, t: float) -> float:
	## Показательный переход WebAudio: `v0 * (v1/v0)^((t-t0)/(t1-t0))`.
	if t1 <= t0:
		return v1
	if t >= t1:
		return v1
	if t <= t0:
		return v0
	if v0 <= 0.0 or v1 <= 0.0:
		return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
	return v0 * pow(v1 / v0, (t - t0) / (t1 - t0))


func _biquad_notch(freq: float, q: float) -> PackedFloat32Array:
	## Режекторный биквад — им и делается фазер (`superdough.mjs:388`).
	var w := TAU * clampf(freq, 10.0, _rate * 0.49) / _rate
	var cw := cos(w)
	var alpha := sin(w) / (2.0 * maxf(q, 0.0001))
	var a0 := 1.0 + alpha
	return PackedFloat32Array([1.0 / a0, -2.0 * cw / a0, 1.0 / a0,
		-2.0 * cw / a0, (1.0 - alpha) / a0])


## Сколько шагов уточнения крутизны колена. Столько же в Chrome.
const COMP_K_STEPS := 15


static func _compressor_curve(threshold_db: float, knee_db: float,
		ratio: float) -> Array:
	## → [порог, крутизна колена k, порог колена, догоняющее усиление].
	##
	## 🔴 Кривая взята из Chrome (`DynamicsCompressorKernel`), а не из
	## учебника: у WebAudio колено ПОКАЗАТЕЛЬНОЕ, а не квадратичное, и
	## крутизна `k` подбирается ПОИСКОМ так, чтобы за коленом наклон совпал
	## с заданным отношением. С учебниковой формулой партия расходилась с
	## эталоном на девять децибел.
	##
	## 🔴 Догоняющее усиление берётся в СТЕПЕНИ 0.6 от обратной величины
	## кривой на полной шкале — тоже из Chrome, «эмпирический расчёт».
	var lin_threshold := db_to_linear(threshold_db)
	var slope := 1.0 / maxf(ratio, 1.0)
	var knee_threshold := db_to_linear(threshold_db + knee_db)

	var min_k := 0.1
	var max_k := 10000.0
	var k := 5.0
	for _i in COMP_K_STEPS:
		if _knee_slope(knee_threshold, k, lin_threshold) < slope:
			max_k = k
		else:
			min_k = k
		k = sqrt(min_k * max_k)

	var yknee_db := linear_to_db(_knee_curve(knee_threshold, k, lin_threshold))
	var curve := [lin_threshold, k, knee_threshold, 1.0, slope, yknee_db,
		threshold_db + knee_db]
	var full := _compressor_saturate(1.0, curve)
	curve[3] = pow(1.0 / maxf(full, 1e-6), 0.6)
	return curve


static func _knee_curve(x: float, k: float, lin_threshold: float) -> float:
	if x < lin_threshold:
		return x
	return lin_threshold + (1.0 - exp(-k * (x - lin_threshold))) / k


static func _knee_slope(x: float, k: float, lin_threshold: float) -> float:
	if x < lin_threshold:
		return 1.0
	var x2 := x * 1.001
	var x_db := linear_to_db(x)
	var x2_db := linear_to_db(x2)
	var y_db := linear_to_db(_knee_curve(x, k, lin_threshold))
	var y2_db := linear_to_db(_knee_curve(x2, k, lin_threshold))
	return (y2_db - y_db) / (x2_db - x_db)


static func _compressor_saturate(x: float, curve: Array) -> float:
	var lin_threshold: float = curve[0]
	var k: float = curve[1]
	var knee_threshold: float = curve[2]
	if x < knee_threshold:
		return _knee_curve(x, k, lin_threshold)
	var slope: float = curve[4]
	var yknee_db: float = curve[5]
	var knee_db: float = curve[6]
	return db_to_linear(yknee_db + slope * (linear_to_db(x) - knee_db))


static func _compressor_gain(x: float, curve: Array) -> float:
	if x < 1e-9:
		return 1.0
	return _compressor_saturate(x, curve) / x


static func db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)


static func linear_to_db(x: float) -> float:
	if x <= 0.0:
		return -1000.0
	return 20.0 * log(x) / log(10.0)


func _poly_blep(phase: float, dt: float) -> float:
	## Скругление скачка пилы (`worklets.mjs:53`). Стая пил строится так же,
	## как в оригинале, — таблицами её там не делают.
	var d := minf(dt, 1.0 - dt)
	if d <= 0.0:
		return 0.0
	var inv := 1.0 / d
	if phase < d:
		var p := phase * inv
		return 2.0 * p - p * p - 1.0
	if phase > 1.0 - d:
		var p2 := (phase - 1.0) * inv
		return p2 * p2 + 2.0 * p2 + 1.0
	return 0.0


func _fm_source_sample(index: int, phase: float, pos_sec: float,
		spec: Dictionary) -> float:
	## Голос модуляции: форма волны и своя огибающая.
	var wave: int = spec.get("wave", 0)
	var v := 0.0
	match wave:
		1: v = 2.0 * phase - 1.0
		2: v = 1.0 if phase < 0.5 else -1.0
		3: v = 4.0 * absf(phase - 0.5) - 1.0
		_: v = sin(TAU * phase)
	var adsr: Array = spec.get("adsr", [])
	if adsr.is_empty():
		return v
	return v * _fm_env_value(pos_sec, adsr)


func _fm_env_value(pos_sec: float, adsr: Array) -> float:
	## Огибающая модулятора: от нуля до единицы, переход показательный или
	## прямой — по `fmenv`.
	var att: float = adsr[0]
	var dec: float = adsr[1]
	var sus: float = adsr[2]
	var rel: float = adsr[3]
	var expo: bool = bool(adsr[4]) if adsr.size() > 4 else true
	var lo := 0.001 if expo else 0.0
	var hi := 1.0
	var sustain_val := lo + sus * (hi - lo)
	var dur := note_length
	if pos_sec <= 0.0:
		return lo
	if pos_sec < att:
		return _ramp(lo, hi, 0.0, att, pos_sec, expo)
	if pos_sec < att + dec:
		return _ramp(hi, sustain_val, att, att + dec, pos_sec, expo)
	if pos_sec < dur:
		return sustain_val
	return _ramp(sustain_val, lo, dur, dur + rel, pos_sec, expo)


func _pitch_env_value(pos_sec: float) -> float:
	## Сдвиг высоты В ЦЕНТАХ. Якорь решает, куда смотрит нота в покое:
	## при единице огибающая ПАДАЕТ к ней сверху, при нуле — растёт снизу.
	var penv: float = pitch_env[0]
	var att: float = pitch_env[1]
	var dec: float = pitch_env[2]
	var sus: float = pitch_env[3]
	var rel: float = pitch_env[4]
	var anchor: float = pitch_env[5]
	var expo: bool = bool(pitch_env[6]) if pitch_env.size() > 6 else false
	var cents := penv * 100.0
	var lo := 0.0 - cents * anchor
	var hi := cents - cents * anchor
	var sustain_val := lo + sus * (hi - lo)
	var dur := note_length
	if pos_sec <= 0.0:
		return lo
	if pos_sec < att:
		return _ramp(lo, hi, 0.0, att, pos_sec, expo)
	if pos_sec < att + dec:
		return _ramp(hi, sustain_val, att, att + dec, pos_sec, expo)
	if pos_sec < dur:
		return sustain_val
	return _ramp(sustain_val, lo, dur, dur + rel, pos_sec, expo)


static func _ramp(v0: float, v1: float, t0: float, t1: float, t: float,
		expo: bool) -> float:
	if expo:
		return _exp_ramp(v0, v1, t0, t1, t)
	if t1 <= t0:
		return v1
	if t >= t1:
		return v1
	if t <= t0:
		return v0
	return v0 + (v1 - v0) * (t - t0) / (t1 - t0)
