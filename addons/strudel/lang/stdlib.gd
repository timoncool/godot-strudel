@tool
class_name StrudelStdlib
extends RefCounted

## Словарь имён Strudel: что можно позвать и что это делает.
##
## Имена сохраняют исходный вид (`degradeBy`, `iterBack`, `swingBy`) — иначе
## чужой код перестанет вставляться без правок, а это и есть смысл плагина.

## Выравнивания слияния: `.add.out(...)`, `.set.squeeze(...)`.
const ALIGNMENTS := ["in", "out", "mix", "squeeze", "squeezeout", "squeezein",
	"reset", "restart", "poly"]

## Операции слияния, у которых бывает выравнивание.
const OPS := {
	"set": "set", "keep": "keep", "keepif": "keepif",
	"add": "add", "sub": "sub", "mul": "mul", "div": "div",
	"mod": "mod", "pow": "pow",
	"band": "band", "bor": "bor", "bxor": "bxor",
	"blshift": "blshift", "brshift": "brshift",
	"lt": "lt", "gt": "gt", "lte": "lte", "gte": "gte",
	"eq": "eq", "ne": "ne", "and": "and", "or": "or",
}

## Методы, которые можно передать как значение: `jux(rev)`, `every(3, press)`.
const BARE_METHODS := ["rev", "revv", "press", "palindrome", "brak", "hurry",
	"degrade", "undegrade", "invert", "inv", "round", "floor", "ceil"]

## Показ и отладка — на звук не влияют, но встречаются в чужом коде сплошь и
## рядом. Их надо ПРОПУСКАТЬ, а не падать на них.
const PASSTHROUGH := ["_punchcard", "punchcard", "_pianoroll",
	"pianoroll", "_spiral", "spiral", "log", "logValues",
	"onTrigger", "tag", "_pitchwheel", "pitchwheel", "markcss",
	# 🔴 `_spectrum` тут не было, и ЛЮБОЙ трек с ней не запускался вовсе:
	# «не знаю метода». Показывалки своей картинки у плагина нет, но падать
	# на них нельзя — в чужих треках они стоят сплошь и рядом.
	"_spectrum", "spectrum"]

## Осциллоскоп. Своей картинки у плагина нет, но пометку он ставит ТУ ЖЕ, что
## Булка (`analyze: 1`), — иначе значения событий расходятся с эталоном на
## ровном месте. Игра вольна прочитать её и нарисовать свою волну.
const SCOPE_METHODS := ["_scope", "scope"]


static func is_method_name(name: String) -> bool:
	return BARE_METHODS.has(name)


static func global_value(name: String) -> Variant:
	## Имена, которые сами по себе значения: сигналы, тишина, Math.
	match name:
		"silence": return StrudelPattern.silence()
		"nothing": return StrudelPattern.nothing()
		"sine": return StrudelSignal.sine()
		"sine2": return StrudelSignal.sine2()
		"cosine": return StrudelSignal.cosine()
		"cosine2": return StrudelSignal.cosine2()
		"saw": return StrudelSignal.saw()
		"saw2": return StrudelSignal.saw2()
		"isaw": return StrudelSignal.isaw()
		"isaw2": return StrudelSignal.isaw2()
		"tri": return StrudelSignal.tri()
		"tri2": return StrudelSignal.tri2()
		"itri": return StrudelSignal.itri()
		"square": return StrudelSignal.square()
		"square2": return StrudelSignal.square2()
		"isquare": return StrudelSignal.isquare()
		"rand": return StrudelSignal.rand()
		"rand2": return StrudelSignal.rand2()
		"brand": return StrudelSignal.brand()
		"perlin": return StrudelSignal.perlin()
		"berlin": return StrudelSignal.berlin()
		"time": return StrudelSignal.time()
		"Math": return {"__ns": "Math"}
	return null


static func math_call(name: String, args: Array) -> Variant:
	var a := _f(args[0]) if args.size() > 0 else 0.0
	var b := _f(args[1]) if args.size() > 1 else 0.0
	match name:
		"pow": return pow(a, b)
		"abs": return absf(a)
		"floor": return floor(a)
		"ceil": return ceil(a)
		"round": return round(a)
		"min": return minf(a, b)
		"max": return maxf(a, b)
		"sqrt": return sqrt(a)
		"log": return log(a)
		"log2": return log(a) / log(2.0)
		"log10": return log(a) / log(10.0)
		"exp": return exp(a)
		"sin": return sin(a)
		"cos": return cos(a)
		"tan": return tan(a)
		# Общий генератор игры не трогаем — см. StrudelVoice._rng.
		"random": return StrudelVoice.random()
		"sign": return signf(a)
		"trunc": return float(int(a))
	push_error("Strudel: Math.%s не поддержана" % name)
	return 0.0


# ═══════════════════════════════════════════════════════════════════════════
# Верхнеуровневые функции
# ═══════════════════════════════════════════════════════════════════════════

static func global_call(rt, name: String, args: Array) -> Variant:
	match name:
		"stack", "polyrhythm", "pr":
			return StrudelPattern.stack(_flat(args))
		"cat", "slowcat":
			return StrudelPattern.slowcat(_flat(args))
		"fastcat", "sequence", "seq":
			return StrudelPattern.fastcat(_flat(args))
		"timeCat", "timecat", "stepcat", "s_cat":
			return StrudelPattern.stepcat(_pairs(args))
		"arrange":
			return StrudelPattern.arrange(_pairs(args))
		"polymeter", "pm":
			return StrudelPattern.polymeter(_flat(args))
		"stepalt", "s_alt":
			return StrudelPattern.stepcat(_pairs(args))
		"pure":
			return StrudelPattern.pure(args[0] if not args.is_empty() else null)
		"reify", "minify":
			return StrudelPattern.reify(args[0] if not args.is_empty() else null)
		"mini", "m", "h":
			return StrudelMini.mini(_s(args[0]))
		"silence":
			return StrudelPattern.silence()
		"run":
			return StrudelSignal.run(_arg(args, 0))
		"irand":
			return StrudelSignal.irand(_arg(args, 0))
		"brandBy":
			return StrudelSignal.brand_by(_arg(args, 0))
		"choose":
			return StrudelSignal.choose(args)
		"chooseCycles", "randcat":
			return StrudelSignal.choose_cycles(args)
		"chooseIn":
			return StrudelSignal.choose_in_with(StrudelSignal.rand(), args)
		"chooseWith":
			return StrudelSignal.choose_with(_pat(args[0]), args.slice(1))
		"xfade":
			if args.size() >= 3:
				return _xfade(_pat(args[0]), args[1], _pat(args[2]))
			return null
		"id":
			return args[0] if not args.is_empty() else null
		# Операции слияния как ВЕРХНЕУРОВНЕВЫЕ функции: `add(7)` отдаёт
		# преобразование, которое потом применяют к паттерну — так их
		# и пишут в чужих треках: `.off(1/8, add(7))`.
		"add", "sub", "mul", "div", "mod", "pow", "set", "keep", "keepif", 		"band", "bor", "bxor", "blshift", "brshift", 		"lt", "gt", "lte", "gte", "eq", "ne", "and", "or":
			return func(inner: Array) -> Variant:
				if inner.is_empty() or not (inner[0] is StrudelPattern):
					push_error("Strudel: \"%s\" ждёт паттерн" % name)
					return null
				return (inner[0] as StrudelPattern)._compose(name, "in", args)
		"struct":
			return func(inner: Array) -> Variant:
				return (inner[0] as StrudelPattern).struct_(args)
		"mask":
			return func(inner: Array) -> Variant:
				return (inner[0] as StrudelPattern).mask_(args)
		"scaleTranspose", "scaleTrans", "strans":
			return func(inner: Array) -> Variant:
				return StrudelTonal.scale_transpose(inner[0], _arg(args, 0))
		"setVoicingRange", "setDefaultVoicings", "addVoicings", "registerVoicings", 		"setGainCurve", "resetDefaults", "setDefaultValue", "setDefaultValues", 		"registerSynthSounds", "setMasterVolume", "loadCsound", "loadOrc", 		"loadSoundfont", "aliasBank", "setcpm2", "enableAudioWorklets":
			# Настройки, которые на СОБЫТИЯ не влияют: пропускаем, чтобы чужой
			# код не падал на строке, которая ничего не значит для нот.
			return null
		# тональные
		"chord", "voicing", "mode", "scale", "rootNotes", "transpose", "arp", "arpWith", "note", "n":
			return _tonal_or_control(rt, name, args)
		"morph":
			# 🔴 В оригинале `morph(frompat, topat, bypat)` —
			# ВЕРХНЕУРОВНЕВАЯ функция трёх паттернов (`pattern.mjs:3860`), а не
			# метод. Записанная только в словарь методов, она давала «код не
			# дал ни одного паттерна» на любом треке, где её звали сверху.
			if args.size() < 3:
				return {"__unknown": true}
			return StrudelPattern.morph_pats(
				_pat(args[0]), _pat(args[1]), _pat(args[2]))
		"randL": return StrudelSignal.rand_list(_arg(args, 0))
		"zip", "s_zip": return StrudelStepwise.zip(_flat(args))
		"tour", "s_tour":
			var many := _flat(args)
			if many.is_empty():
				return StrudelPattern.silence()
			return StrudelStepwise.tour(_pat(many[0]), many.slice(1))
		"randrun": return StrudelSignal.randrun(int(_f(_arg(args, 0))))
		"binary": return StrudelSignal.binary_(_arg(args, 0))
		"binaryN":
			return StrudelSignal.binary_n(_arg(args, 0),
				_arg(args, 1) if args.size() > 1 else 16)
		"binaryL": return StrudelSignal.binary_list(_arg(args, 0))
		"binaryNL":
			return StrudelSignal.binary_n_list(_arg(args, 0),
				_arg(args, 1) if args.size() > 1 else 16)
		"wchoose":
			# 🔴 Доводы здесь — ПАРЫ «значение, вес», и разворачивать их
			# нельзя: получился бы плоский ряд, где вес играет нотой.
			return StrudelSignal.wchoose(args)
		"wchooseCycles", "wrandcat":
			return StrudelSignal.wchoose_cycles(args)
		"useRNG":
			StrudelSignal.use_rng(StrudelUtil.text(_arg(args, 0)))
			return null
		"initHydra", "hush", "all", "samples", "setDefaultJoin", "calculateSteps":
			# Не влияет на события: тихо пропускаем, чтобы чужой код не падал.
			return null

	# Всё остальное — либо параметр, либо метод, взятый как функция.
	if StrudelControls.is_control(name):
		return StrudelControls.make(name, _arg(args, 0))
	if _is_pattern_method(name):
		# `fast(2)` как значение → функция, применяемая к паттерну.
		return func(inner: Array) -> Variant:
			if inner.is_empty() or not (inner[0] is StrudelPattern):
				push_error("Strudel: \"%s\" ждёт паттерн" % name)
				return null
			return method_call(rt, inner[0], name, args)
	return {"__unknown": true}


static func _tonal_or_control(rt, name: String, args: Array) -> Variant:
	match name:
		"note", "n":
			return StrudelControls.make(name, _arg(args, 0))
		"chord":
			return StrudelTonal.chord(_pat(args[0]))
		"scale":
			return StrudelTonal.scale(_pat(args[0]), _arg(args, 1))
	# 🔴 ЭТИ ИМЕНА РАБОТАЮТ И СВЕРХУ, а не только методом.
	#
	# `register` в оригинале (`pattern.mjs:1744`) делает обе формы сразу:
	# `pat.f(a)` и `f(a, pat)`, причём ПАТТЕРН ИДЁТ ПОСЛЕДНИМ доводом
	# (`const pat = args[args.length - 1]`). Раньше тут стояло «имеют смысл
	# только на паттерне», и `voicing(chord("<C^7>"))` роняло весь трек
	# сообщением «не знаю функции».
	if not args.is_empty():
		var tail: Variant = args[args.size() - 1]
		var pat := _pat(tail)
		if pat != null:
			return method_call(rt, pat, name, args.slice(0, args.size() - 1))
	return {"__unknown": true}


static func _xfade(a: StrudelPattern, pos: Variant, b: StrudelPattern) -> StrudelPattern:
	var p := StrudelPattern.reify(pos)
	var fade := func(x: float) -> float:
		return 1.0 if x < 0.5 else 1.0 - (x - 0.5) / 0.5
	return StrudelPattern.stack([
		a.mul([p.fmap(func(v): return {"gain": fade.call(_f(v))})]),
		b.mul([p.fmap(func(v): return {"gain": fade.call(1.0 - _f(v))})]),
	])


# ═══════════════════════════════════════════════════════════════════════════
# Методы паттерна
# ═══════════════════════════════════════════════════════════════════════════

static func _is_pattern_method(name: String) -> bool:
	return _METHODS.has(name)

const _METHODS := {
	"fast": 1, "density": 1, "slow": 1, "sparsity": 1, "early": 1, "late": 1,
	"rev": 1, "revv": 1, "iter": 1, "iterBack": 1, "iterback": 1, "ply": 1,
	"off": 1, "jux": 1, "juxBy": 1, "juxby": 1, "superimpose": 1, "layer": 1,
	"struct": 1, "structAll": 1, "mask": 1, "maskAll": 1, "segment": 1, "seg": 1,
	"striate": 1, "chop": 1, "compress": 1, "fastGap": 1, "fastgap": 1,
	"focus": 1, "zoom": 1, "linger": 1, "echo": 1, "echoWith": 1, "stut": 1,
	"every": 1, "firstOf": 1, "lastOf": 1, "when": 1, "chunk": 1, "chunkBack": 1,
	"repeatCycles": 1, "palindrome": 1, "press": 1, "pressBy": 1,
	"inside": 1, "outside": 1, "ribbon": 1, "rib": 1, "hurry": 1,
	"apply": 1, "applyN": 1, "within": 1, "range": 1, "rangex": 1, "range2": 1,
	"round": 1, "floor": 1, "ceil": 1, "toBipolar": 1, "fromBipolar": 1,
	"euclid": 1, "euclidRot": 1, "euclidLegato": 1,
	"degradeBy": 1, "degrade": 1, "undegradeBy": 1, "undegrade": 1,
	"sometimesBy": 1, "sometimes": 1, "often": 1, "rarely": 1,
	"almostNever": 1, "almostAlways": 1, "never": 1, "always": 1,
	"someCyclesBy": 1, "someCycles": 1, "shuffle": 1, "scramble": 1, "seed": 1,
	"swingBy": 1, "swing": 1, "brak": 1, "stack": 1, "cat": 1, "slowcat": 1,
	"fastcat": 1, "sequence": 1, "seq": 1, "pace": 1, "steps": 1,
	"expand": 1, "contract": 1, "extend": 1, "filter": 1, "filterWhen": 1,
	"queryArc": 1, "firstCycle": 1, "invert": 1, "inv": 1,
	"voicing": 1, "mode": 1, "rootNotes": 1, "transpose": 1, "scale": 1,
	"arp": 1, "arpWith": 1, "chord": 1, "piano": 1,
	"scaleTranspose": 1, "scaleTrans": 1, "strans": 1,
	"euclidLegatoRot": 1, "loopAt": 1, "loopat": 1, "loopAtCps": 1,
	"fit": 1, "slice": 1, "splice": 1, "bite": 1,
	"hush": 1, "reset": 1, "restart": 1, "resetAll": 1, "restartAll": 1,
	"csound": 1,
	# — куски круга и вложенные паттерны —
	"chunkInto": 1, "chunkinto": 1, "chunkBackInto": 1, "chunkbackinto": 1,
	"fastChunk": 1, "fastchunk": 1, "slowChunk": 1, "slowchunk": 1,
	"chunkback": 1, "unjoin": 1, "into": 1,
	"compressSpan": 1, "compressspan": 1, "focusSpan": 1, "focusspan": 1,
	"zoomArc": 1, "zoomarc": 1,
	"echowith": 1, "stutWith": 1, "stutwith": 1,
	"plyWith": 1, "plywith": 1, "plyForEach": 1, "plyforeach": 1,
	"juxFlip": 1, "juxflip": 1, "flux": 1,
	"juxFlipBy": 1, "juxflipby": 1, "fluxBy": 1, "fluxby": 1,
	"collect": 1, "xfade": 1, "beat": 1, "ratio": 1, "log2": 1, "cpm": 1,
	"hsl": 1, "hsla": 1, "bypass": 1, "morph": 1,
	# — эвклидовы —
	"bjork": 1, "euclidish": 1, "eish": 1, "euclidrot": 1,
	# — выбор по указателю —
	"pick": 1, "pickmod": 1, "pickOut": 1, "pickmodOut": 1,
	"pickRestart": 1, "pickmodRestart": 1, "pickReset": 1, "pickmodReset": 1,
	"inhabit": 1, "pickSqueeze": 1, "inhabitmod": 1, "pickmodSqueeze": 1,
	"pickF": 1, "pickmodF": 1,
	# — вероятностное и клавиши —
	"degradeByWith": 1, "keyDown": 1, "whenKey": 1,
	# — огибающие и параметры пачкой —
	"adsr": 1, "ad": 1, "ds": 1, "ar": 1, "control": 1, "as": 1, "scrub": 1,
	"lfo": 1, "env": 1, "bmod": 1, "modulate": 1,
	# — пошаговые —
	"take": 1, "drop": 1, "grow": 1, "shrink": 1,
	"growlist": 1, "shrinklist": 1, "tour": 1, "zip": 1,
	"s_add": 1, "s_sub": 1, "s_expand": 1, "s_extend": 1, "s_contract": 1,
	"s_polymeter": 1, "s_taper": 1, "s_taperlist": 1, "s_tour": 1, "s_zip": 1,
	"stepBind": 1, "stepJoin": 1,
	# — тембр —
	"partials": 1, "phases": 1, "FX": 1,
	# — тональное —
	"voicings": 1, "trans": 1, "_transpose": 1,
	# — живой код и внешний мир —
	"choose": 1, "choose2": 1, "p": 1, "q": 1,
	"d1": 1, "d2": 1, "d3": 1, "d4": 1, "d5": 1,
	"d6": 1, "d7": 1, "d8": 1, "d9": 1,
	"timeline": 1, "worklet": 1, "speak": 1, "sysex": 1,
	"onTriggerTime": 1,
}


static func method_call(rt, pat: StrudelPattern, name: String, args: Array) -> Variant:
	if PASSTHROUGH.has(name):
		return pat
	if SCOPE_METHODS.has(name):
		# 🔴 Значение `analyze` — это МЕТКА МЕСТА В ИСХОДНИКЕ, а не единица:
		# `_widget__scope_0_3971-3982`. Её ставит разбор кода (см.
		# WIDGET_METHODS в code_parser.gd), потому что так делает транспайлер
		# Strudel, и она попадает в само событие. Игра вольна прочитать метку
		# и нарисовать свою волну — а сверка с Булкой сходится битами.
		var tag: Variant = _arg(args, 0)
		return StrudelControls.apply(pat, "analyze", tag if tag is String else 1)

	match name:
		# — время —
		"fast", "density": return pat.fast(_arg(args, 0))
		"slow", "sparsity": return pat.slow(_arg(args, 0))
		"early": return pat.early(_arg(args, 0))
		"late": return pat.late(_arg(args, 0))
		"rev": return pat.rev()
		"revv": return pat.revv()
		"iter": return pat.iter(_arg(args, 0))
		"iterBack", "iterback": return pat.iter_back(_arg(args, 0))
		"ply": return pat.ply(_arg(args, 0))
		"segment", "seg": return pat.segment(_arg(args, 0))
		"compress": return pat.compress(_arg(args, 0), _arg(args, 1))
		"fastGap", "fastgap": return pat._fast_gap(_arg(args, 0))
		"focus": return pat._focus(_arg(args, 0), _arg(args, 1))
		"zoom": return pat.zoom(_arg(args, 0), _arg(args, 1))
		"linger": return pat.linger(_arg(args, 0))
		"repeatCycles": return pat.repeat_cycles(_arg(args, 0))
		"palindrome": return pat.palindrome()
		"press": return pat.press()
		"pressBy": return pat.press_by(_arg(args, 0))
		"swingBy": return pat.swing_by(_arg(args, 0), _arg(args, 1))
		"swing": return pat.swing(_arg(args, 0))
		"hurry": return pat.hurry(_arg(args, 0))
		"striate": return pat.striate(int(_f(_arg(args, 0))))
		"chop": return pat.chop(int(_f(_arg(args, 0))))
		"pace", "steps": return pat.pace(_arg(args, 0))
		"expand": return pat.expand(_arg(args, 0))
		"contract": return pat.contract(_arg(args, 0))
		"extend": return pat.extend(_arg(args, 0))
		"brak": return pat._when_pat(
			StrudelPattern.slowcat([StrudelPattern.pure(false), StrudelPattern.pure(true)]),
			func(p): return StrudelPattern.fastcat([p, StrudelPattern.silence()])._late(0.25))

		# — наложение —
		"off": return pat.off(_arg(args, 0), _fn1(args, 1))
		"jux": return pat.jux(_fn1(args, 0))
		"juxBy", "juxby": return pat.jux_by(_arg(args, 0), _fn1(args, 1))
		"superimpose": return pat.superimpose(_fns(args))
		"layer": return pat.layer(_fns(args))
		"stack": return StrudelPattern.stack([pat] + _flat(args))
		"cat", "slowcat": return StrudelPattern.slowcat([pat] + _flat(args))
		"fastcat", "sequence", "seq": return StrudelPattern.fastcat([pat] + _flat(args))
		"echo": return pat.echo(int(_f(_arg(args, 0))), _arg(args, 1), _f(_arg(args, 2)))
		"echoWith", "stutWith": return pat.echo_with(int(_f(_arg(args, 0))), _arg(args, 1), _fn2(args, 2))
		"stut": return pat.echo(int(_f(_arg(args, 0))), _arg(args, 2), _f(_arg(args, 1)))

		# — структура —
		"struct": return pat.struct_(args)
		"structAll": return pat.struct_all(args)
		"mask": return pat.mask_(args)
		"maskAll": return pat.mask_all(args)
		"euclid": return StrudelEuclid.apply(pat, int(_f(_arg(args, 0))), int(_f(_arg(args, 1))))
		"euclidRot": return StrudelEuclid.apply(pat, int(_f(_arg(args, 0))), int(_f(_arg(args, 1))), int(_f(_arg(args, 2))))
		"euclidLegato": return StrudelEuclid.apply_legato(pat, int(_f(_arg(args, 0))), int(_f(_arg(args, 1))))

		# — условное —
		"every", "firstOf": return pat.every(_arg(args, 0), _fn1(args, 1))
		"lastOf": return pat.last_of(_arg(args, 0), _fn1(args, 1))
		"when": return pat._when_pat(_pat(args[0]), _fn1(args, 1))
		"chunk": return pat.chunk(int(_f(_arg(args, 0))), _fn1(args, 1))
		"chunkBack": return pat.chunk(int(_f(_arg(args, 0))), _fn1(args, 1), true)
		"inside": return pat.inside(_arg(args, 0), _fn1(args, 1))
		"outside": return pat.outside(_arg(args, 0), _fn1(args, 1))
		"within": return pat.within(_arg(args, 0), _arg(args, 1), _fn1(args, 2))
		"apply": return pat.apply(_fn1(args, 0))
		"applyN": return pat.apply_n(int(_f(_arg(args, 0))), _fn1(args, 1))
		"ribbon", "rib": return pat.ribbon(_arg(args, 0), _arg(args, 1))
		"filterWhen": return pat.filter_when(_fnv(args, 0))
		"filter": return pat.filter_haps(_fnv(args, 0))

		# — вероятностное —
		"degradeBy": return StrudelSignal.degrade_by(pat, _arg(args, 0))
		"degrade": return StrudelSignal.degrade(pat)
		"undegradeBy": return StrudelSignal.undegrade_by(pat, _arg(args, 0))
		"undegrade": return StrudelSignal.undegrade(pat)
		"sometimesBy": return StrudelSignal.sometimes_by(pat, _arg(args, 0), _fn1(args, 1))
		"sometimes": return StrudelSignal.sometimes(pat, _fn1(args, 0))
		"often": return StrudelSignal.often(pat, _fn1(args, 0))
		"rarely": return StrudelSignal.rarely(pat, _fn1(args, 0))
		"almostNever": return StrudelSignal.almost_never(pat, _fn1(args, 0))
		"almostAlways": return StrudelSignal.almost_always(pat, _fn1(args, 0))
		"never": return pat
		"always": return _fn1(args, 0).call(pat)
		"someCyclesBy": return StrudelSignal.some_cycles_by(pat, _arg(args, 0), _fn1(args, 1))
		"someCycles": return StrudelSignal.some_cycles(pat, _fn1(args, 0))
		"shuffle": return StrudelSignal.shuffle(pat, int(_f(_arg(args, 0))))
		"scramble": return StrudelSignal.scramble(pat, int(_f(_arg(args, 0))))
		"seed": return StrudelSignal.seed_(pat, _f(_arg(args, 0)))

		# — числовое —
		"range": return pat.range_(_arg(args, 0), _arg(args, 1))
		"rangex": return pat.rangex(_arg(args, 0), _arg(args, 1))
		"range2": return pat.range2(_arg(args, 0), _arg(args, 1))
		"round": return pat.round_()
		"floor": return pat.floor_p()
		"ceil": return pat.ceil_p()
		"toBipolar": return pat.to_bipolar()
		"fromBipolar": return pat.from_bipolar()
		"invert", "inv": return pat.fmap(func(v): return not StrudelPattern.truthy(v))

		# — звуковые сокращения —
		"piano": return StrudelTonal.piano(pat)

		# — тональное —
		"chord":
			# 🔴 chord — ОБЫЧНЫЙ параметр, а не тональная функция. Без довода
			# (`seq(...).chord()`) он перекладывает значения самого паттерна, с
			# доводом (`n("0 1").chord("<Am7 C7>")`) — ставится поверх, как gain.
			# Пока метод игнорировал довод, аккорд до раскладки не доезжал вовсе
			# и весь слой arpoon молчал.
			return StrudelControls.apply(pat, "chord", _arg(args, 0))
		"voicing": return StrudelTonal.voicing(pat)
		"mode": return StrudelTonal.mode(pat, _arg(args, 0))
		"rootNotes": return StrudelTonal.root_notes(pat, _arg(args, 0))
		"transpose": return StrudelTonal.transpose(pat, _arg(args, 0))
		"scale": return StrudelTonal.scale(pat, _arg(args, 0))
		"arp": return StrudelTonal.arp(pat, _arg(args, 0))
		"scaleTranspose", "scaleTrans", "strans":
			return StrudelTonal.scale_transpose(pat, _arg(args, 0))
		"euclidLegatoRot":
			return StrudelEuclid.apply_legato(pat, int(_f(_arg(args, 0))),
				int(_f(_arg(args, 1))), int(_f(_arg(args, 2))))
		"loopAt", "loopat":
			return pat.loop_at(_arg(args, 0))
		"loopAtCps", "loopatcps":
			return pat.loop_at(_arg(args, 0), _f(_arg(args, 1)))
		"fit":
			return pat.fit()
		"slice":
			return pat.slice_(_arg(args, 0), _arg(args, 1))
		"splice":
			return pat.splice_(_arg(args, 0), _arg(args, 1))
		"bite":
			return pat.bite(_arg(args, 0), _arg(args, 1))
		"hush":
			# Заглушить целиком — так в чужих треках выключают партию, не
			# стирая её из кода.
			return StrudelPattern.silence()
		"reset": return pat.reset(args)
		"restart": return pat.restart(args)
		"resetAll": return pat._compose("keep", "reset", args)
		"restartAll": return pat._compose("keep", "restart", args)
		"csound":
			# Csound — внешний движок синтеза, в плагин он не входит. Партия
			# продолжает играть штатным путём, но своим тембром Csound не даёт.
			push_warning("Strudel: .csound() не поддержан — партия играет штатным звуком")
			return pat

		# — запрос —
		"queryArc": return pat.query_arc(_arg(args, 0), _arg(args, 1))
		"firstCycle": return pat.first_cycle()

	match name:
		# — куски круга —
		"chunkInto", "chunkinto":
			return pat.chunk_into(int(_f(_arg(args, 0))), _fn1(args, 1))
		"chunkBackInto", "chunkbackinto":
			return pat.chunk_back_into(int(_f(_arg(args, 0))), _fn1(args, 1))
		"fastChunk", "fastchunk":
			return pat.chunk(int(_f(_arg(args, 0))), _fn1(args, 1), false, true)
		"slowChunk", "slowchunk":
			return pat.chunk(int(_f(_arg(args, 0))), _fn1(args, 1))
		"chunkback":
			return pat.chunk(int(_f(_arg(args, 0))), _fn1(args, 1), true)
		"unjoin":
			return pat.unjoin(_pat(_arg(args, 0)),
				_fn1(args, 1) if args.size() > 1 else Callable())
		"into":
			return pat.into(_pat(_arg(args, 0)),
				_fn1(args, 1) if args.size() > 1 else Callable())
		"compressSpan", "compressspan": return pat.compress_span(_arg(args, 0))
		"focusSpan", "focusspan": return pat.focus_span(_arg(args, 0))
		"zoomArc", "zoomarc": return pat.zoom_arc(_arg(args, 0))
		"echowith", "stutWith", "stutwith":
			return pat.echo_with(_f(_arg(args, 0)), _arg(args, 1), _fn2(args, 2))
		"plyWith", "plywith":
			return pat.ply_with(_arg(args, 0), _fn1(args, 1))
		"plyForEach", "plyforeach":
			return pat.ply_for_each(_arg(args, 0), _fn2(args, 1))
		"juxFlip", "juxflip", "flux":
			return pat.jux_flip(_fn1(args, 0))
		"juxFlipBy", "juxflipby", "fluxBy", "fluxby":
			return pat.jux_flip_by(_arg(args, 0), _fn1(args, 1))
		"collect": return pat.collect()
		"xfade": return pat.xfade(_arg(args, 0), _arg(args, 1))
		"beat": return pat.beat(_arg(args, 0), _arg(args, 1))
		"ratio": return pat.ratio_()
		"log2": return pat.log2_()
		"cpm": return pat.cpm(_arg(args, 0))
		"hsl": return pat.hsl(_arg(args, 0), _arg(args, 1), _arg(args, 2))
		"hsla": return pat.hsla(_arg(args, 0), _arg(args, 1), _arg(args, 2), _arg(args, 3))
		"bypass": return pat.bypass(_arg(args, 0))

		# — эвклидовы —
		"bjork": return StrudelEuclid.bjork(pat, _arg(args, 0))
		"euclidish", "eish":
			return StrudelEuclid.apply_ish(pat, int(_f(_arg(args, 0))),
				int(_f(_arg(args, 1))), _arg(args, 2))
		"euclidrot":
			return StrudelEuclid.apply(pat, int(_f(_arg(args, 0))),
				int(_f(_arg(args, 1))), int(_f(_arg(args, 2))))

		# — выбор по указателю —
		"pick": return StrudelPick.pick(_arg(args, 0), pat)
		"pickmod": return StrudelPick.pickmod(_arg(args, 0), pat)
		"pickOut": return StrudelPick.pick_out(_arg(args, 0), pat)
		"pickmodOut": return StrudelPick.pickmod_out(_arg(args, 0), pat)
		"pickRestart": return StrudelPick.pick_restart(_arg(args, 0), pat)
		"pickmodRestart": return StrudelPick.pickmod_restart(_arg(args, 0), pat)
		"pickReset": return StrudelPick.pick_reset(_arg(args, 0), pat)
		"pickmodReset": return StrudelPick.pickmod_reset(_arg(args, 0), pat)
		"inhabit", "pickSqueeze": return StrudelPick.inhabit(_arg(args, 0), pat)
		"inhabitmod", "pickmodSqueeze": return StrudelPick.inhabitmod(_arg(args, 0), pat)
		"pickF": return StrudelPick.pick_f(pat, _arg(args, 0), _fn_list(_arg(args, 1)))
		"pickmodF": return StrudelPick.pickmod_f(pat, _arg(args, 0), _fn_list(_arg(args, 1)))

		# — вероятностное и клавиши —
		"degradeByWith":
			return StrudelSignal.degrade_by_with(pat, _arg(args, 0), _arg(args, 1))
		"keyDown": return StrudelSignal.key_down(pat)
		"whenKey": return StrudelSignal.when_key(pat, _arg(args, 0), _fn1(args, 1))

		# — огибающие и параметры пачкой —
		"adsr": return StrudelControls.adsr(pat, _arg(args, 0))
		"ad": return StrudelControls.ad(pat, _arg(args, 0))
		"ds": return StrudelControls.ds(pat, _arg(args, 0))
		"ar": return StrudelControls.ar(pat, _arg(args, 0))
		"control": return StrudelControls.control(pat, _arg(args, 0))
		"as": return StrudelControls.as_(pat, _arg(args, 0))
		"scrub": return StrudelControls.scrub(pat, _arg(args, 0))
		"lfo": return StrudelModulation.modulate(pat, "lfo", _arg(args, 0), _arg(args, 1))
		"env": return StrudelModulation.modulate(pat, "env", _arg(args, 0), _arg(args, 1))
		"bmod": return StrudelModulation.modulate(pat, "bmod", _arg(args, 0), _arg(args, 1))
		"modulate":
			return StrudelModulation.modulate(pat, StrudelUtil.text(_arg(args, 0)),
				_arg(args, 1), _arg(args, 2))

		# — пошаговые —
		"take", "s_add": return StrudelStepwise.take(pat, _arg(args, 0))
		"drop", "s_sub": return StrudelStepwise.drop(pat, _arg(args, 0))
		"grow": return StrudelStepwise.grow(pat, _arg(args, 0))
		"shrink", "s_taper": return StrudelStepwise.shrink(pat, _arg(args, 0))
		"growlist": return StrudelStepwise.growlist(pat, _arg(args, 0))
		"shrinklist", "s_taperlist": return StrudelStepwise.shrinklist(pat, _arg(args, 0))
		"tour", "s_tour": return StrudelStepwise.tour(pat, _flat(args))
		"zip", "s_zip": return StrudelStepwise.zip([pat] + _flat(args))
		"s_expand": return pat.expand(_arg(args, 0))
		"s_extend": return pat.extend(_arg(args, 0))
		"s_contract": return pat.contract(_arg(args, 0))
		"s_polymeter": return StrudelPattern.polymeter([pat] + _flat(args))
		"stepJoin": return pat.step_join()
		"stepBind": return pat.step_bind(_fn1(args, 0))

		# — тембр —
		"partials": return pat.partials(_arg(args, 0))
		"phases": return pat.phases(_arg(args, 0))
		"FX": return pat.fx(args)

		# — живой код и внешний мир —
		"choose": return StrudelSignal.choose_with(pat, _flat(args))
		"choose2":
			return StrudelSignal.choose_with(pat.from_bipolar(), _flat(args))
		"p", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9":
			return pat.p(_arg(args, 0) if not args.is_empty() else name)
		"q": return pat.q()
		"timeline": return pat.timeline(_arg(args, 0))
		"worklet": return pat.worklet(_arg(args, 0), args.slice(1))
		"speak":
			return StrudelSpeech.speak(pat, _arg(args, 0), _arg(args, 1))
		"sysex":
			var pair: Variant = _arg(args, 0)
			if not pair is Array or (pair as Array).size() < 2:
				push_warning("Strudel: sysex ждёт пару [номер, данные]")
				return pat
			return StrudelControls.apply(
				StrudelControls.apply(pat, "sysexid", pair[0]), "sysexdata", pair[1])
		"onTriggerTime":
			# Отклик на событие по времени. Своих часов у паттерна нет —
			# события отдаёт игра, — поэтому здесь партия просто едет дальше.
			return pat
		"arpWith": return StrudelTonal.arp_with(pat, _fn1(args, 0))

		# — тональное —
		"voicings": return StrudelTonal.voicings(pat, _arg(args, 0))
		"trans", "_transpose": return StrudelTonal.transpose(pat, _arg(args, 0))

	# Параметр звука: .gain(0.5), .lpf(600), .s("piano")…
	if StrudelControls.is_control(name):
		return StrudelControls.apply(pat, name, _arg(args, 0))
	return {"__unknown": true}


# ═══════════════════════════════════════════════════════════════════════════
# Мелочи приведения
# ═══════════════════════════════════════════════════════════════════════════

static func _f(v: Variant) -> float:
	if v is float: return v
	if v is int: return float(v)
	if v is bool: return 1.0 if v else 0.0
	if v is String or v is StringName: return String(v).to_float()
	if v is StrudelPattern:
		var haps: Array = (v as StrudelPattern).query_arc(0, 1)
		if not haps.is_empty():
			return StrudelPattern._num((haps[0] as StrudelHap).value)
	return 0.0


static func _s(v: Variant) -> String:
	if v is String or v is StringName:
		return String(v)
	if v is StrudelPattern:
		var haps: Array = (v as StrudelPattern).query_arc(0, 1)
		if not haps.is_empty():
			return str((haps[0] as StrudelHap).value)
	return str(v)


static func _fn_list(v: Variant) -> Variant:
	## Список или таблица ДЕЙСТВИЙ для pickF: стрелочные функции из кода
	## приходят как Callable с одним доводом-списком, а паттерну нужен
	## обычный вызов.
	var wrap := func(x: Variant) -> Variant:
		if x is Callable:
			var c: Callable = x
			return func(p): return c.call([p])
		return x
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(wrap.call(x))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = wrap.call((v as Dictionary)[k])
		return d
	return wrap.call(v)


static func _arg(args: Array, i: int) -> Variant:
	return args[i] if i < args.size() else null


static func _pat(v: Variant) -> StrudelPattern:
	return StrudelPattern.reify(v)


static func _flat(args: Array) -> Array:
	## Strudel одинаково принимает и список аргументов, и массив.
	var out: Array = []
	for a in args:
		if a is Array and not _looks_like_pair(a):
			out.append_array(a)
		else:
			out.append(a)
	return out


static func _looks_like_pair(a: Array) -> bool:
	return a.size() == 2 and (a[0] is int or a[0] is float)


static func _pairs(args: Array) -> Array:
	## Для arrange/timeCat: [[длина, паттерн], …].
	var out: Array = []
	for a in args:
		if a is Array and (a as Array).size() == 2:
			out.append([(a as Array)[0], (a as Array)[1]])
		else:
			out.append([1, a])
	return out


static func _fn1(args: Array, i: int) -> Callable:
	## Стрелочная функция из кода → Callable, принимающий паттерн.
	var v: Variant = _arg(args, i)
	if v is Callable:
		var c: Callable = v
		return func(p): return c.call([p])
	push_error("Strudel: здесь ожидалась функция")
	return func(p): return p


static func _fn2(args: Array, i: int) -> Callable:
	var v: Variant = _arg(args, i)
	if v is Callable:
		var c: Callable = v
		return func(p, k): return c.call([p, k])
	return func(p, _k): return p


static func _fnv(args: Array, i: int) -> Callable:
	var v: Variant = _arg(args, i)
	if v is Callable:
		var c: Callable = v
		return func(x): return StrudelPattern.truthy(c.call([x]))
	return func(_x): return true


static func _fns(args: Array) -> Array:
	var out: Array = []
	for a in args:
		if a is Callable:
			var c: Callable = a
			out.append(func(p): return c.call([p]))
	return out
