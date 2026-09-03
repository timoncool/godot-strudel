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
	"pianoroll", "_spiral", "color", "log", "logValues",
	"onTrigger", "tag", "_pitchwheel", "markcss"]

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
		"random": return randf()
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
		# тональные
		"chord", "voicing", "mode", "scale", "rootNotes", "transpose", "arp", "arpWith", "note", "n":
			return _tonal_or_control(rt, name, args)
		"initHydra", "hush", "all", "samples", "setDefaultJoin", "useRNG", "calculateSteps":
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
	# voicing/mode/rootNotes/transpose/arp имеют смысл только на паттерне
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
	"arp": 1, "arpWith": 1, "chord": 1,
}


static func method_call(rt, pat: StrudelPattern, name: String, args: Array) -> Variant:
	if PASSTHROUGH.has(name):
		return pat
	if SCOPE_METHODS.has(name):
		return StrudelControls.apply(pat, "analyze", 1)

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
		"degradeBy": return StrudelSignal.degrade_by(pat, _f(_arg(args, 0)))
		"degrade": return StrudelSignal.degrade(pat)
		"undegradeBy": return StrudelSignal.undegrade_by(pat, _f(_arg(args, 0)))
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

		# — тональное —
		"chord": return StrudelTonal.chord(pat)
		"voicing": return StrudelTonal.voicing(pat)
		"mode": return StrudelTonal.mode(pat, _arg(args, 0))
		"rootNotes": return StrudelTonal.root_notes(pat, _arg(args, 0))
		"transpose": return StrudelTonal.transpose(pat, _arg(args, 0))
		"scale": return StrudelTonal.scale(pat, _arg(args, 0))
		"arp": return StrudelTonal.arp(pat, _arg(args, 0))

		# — запрос —
		"queryArc": return pat.query_arc(_arg(args, 0), _arg(args, 1))
		"firstCycle": return pat.first_cycle()

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
