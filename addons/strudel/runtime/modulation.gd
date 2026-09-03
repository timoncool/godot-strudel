@tool
class_name StrudelModulation
extends RefCounted

## Настройка модуляторов: `lfo`, `env`, `bmod` (`core/controls.mjs:3111`).
##
## Каждый из них не делает звука сам — он КЛАДЁТ В СОБЫТИЕ описание того,
## что и чем шевелить: какой параметр, с какой скоростью, глубиной и формой.
## Читает это уже звуковая часть.
##
## 🔴 ПАРАМЕТР ПО УМОЛЧАНИЮ — ТОТ, ЧТО ПОСТАВИЛИ ПЕРЕД ЭТИМ. `s("saw").lpf(500).lfo()`
## качает именно срез, потому что `lpf` — последний ключ значения. Порядок
## ключей поэтому значим, и словари GDScript его как раз хранят.
##
## 🔴 Список меток модуляторов (`__ids`) — СПИСОК, а не множество: в
## оригинале это Set, но важен там только порядок вставки, а он у списка
## естественный.

## Виды модуляторов. Чужое имя — не беда: партия играет дальше без модуляции.
const KINDS := ["lfo", "env", "bmod"]

## Сокращения настроек, скопированы из `controls.mjs:3073`. Таблица
## крошечная и в апстриме не движется — генератор для неё был бы дороже.
const SUB_ALIASES := {
	"lfo": {
		"c": "control", "sc": "subControl", "r": "rate",
		"dep": "depth", "dr": "depth", "da": "depthabs", "dc": "dcoffset",
		"sh": "shape", "sk": "skew", "cu": "curve", "s": "sync", "rt": "retrig",
	},
	"env": {
		"c": "control", "sc": "subControl",
		"att": "attack", "a": "attack", "dec": "decay", "d": "decay",
		"sus": "sustain", "s": "sustain", "rel": "release", "r": "release",
		"dep": "depth", "dr": "depth", "da": "depthabs",
		"ac": "acurve", "dc": "dcurve", "rc": "rcurve",
	},
	"bmod": {
		"b": "bus", "c": "control", "sc": "subControl",
		"dep": "depth", "dr": "depth", "da": "depthabs",
	},
}


static func main_sub_name(kind: String, key: String) -> String:
	var map: Dictionary = SUB_ALIASES.get(kind, {})
	return String(map.get(key.to_lower(), key))


static func modulate(pat: StrudelPattern, kind: String, config: Variant,
		id_pat: Variant = null) -> StrudelPattern:
	## Собрать описание модулятора в значении события.
	if not KINDS.has(kind):
		push_warning("Strudel: не знаю модуляции \"%s\" — жду lfo, env или bmod" % kind)
		return pat
	var cfg: Dictionary = config if config is Dictionary else {}

	# 🔴 `control` идёт ПЕРВЫМ ключом даже когда его не задали: так в
	# оригинале (`{ control: undefined, ...config }`), и от этого зависит,
	# какой параметр окажется «тем самым, что перед модулятором».
	var keys: Array = ["control"]
	for k in cfg:
		if String(k) != "control":
			keys.append(String(k))

	# Значение временно едет в обёртке {v, id}: метка одна на всю настройку.
	var out := pat.fmap(func(v) -> Callable:
		return func(id): return {"v": v, "id": id}
	).app_left(StrudelPattern.reify(id_pat))

	# Умолчание считается один раз на сборку, как замыкание в оригинале.
	var default_holder: Array = [null]

	for raw_key in keys:
		var key := main_sub_name(kind, String(raw_key))
		var value_pat := StrudelPattern.reify(cfg.get(raw_key, null))
		out = out.fmap(func(pair: Dictionary) -> Callable:
			return func(c) -> Dictionary:
				var v: Dictionary = (pair["v"] as Dictionary).duplicate(true) \
					if pair["v"] is Dictionary else {"value": pair["v"]}
				var id: Variant = pair["id"]
				if default_holder[0] == null:
					default_holder[0] = _last_control(v, kind)
				if not v.has(kind):
					v[kind] = {"__ids": []}
				var slot: Dictionary = v[kind]
				if id == null:
					id = (slot["__ids"] as Array).size()
				var id_key := StrudelUtil.text(id)
				if not slot.has(id_key):
					slot[id_key] = {"control": default_holder[0]}
				if not (slot["__ids"] as Array).has(id_key):
					(slot["__ids"] as Array).append(id_key)
				if c == null:
					return {"v": v, "id": id}
				if key == "control" or key == "subControl":
					slot[id_key][key] = StrudelControls.main_name(StrudelUtil.text(c))
				else:
					slot[id_key][key] = c
				return {"v": v, "id": id}
		).app_left(value_pat)

	return out.fmap(func(pair: Dictionary) -> Variant:
		return pair["v"]
	)


static func _last_control(value: Dictionary, kind: String) -> String:
	## Имя параметра, поставленного ПЕРЕД модулятором.
	var keys: Array = value.keys()
	if keys.is_empty():
		return ""
	var last := StrudelControls.main_name(String(keys[keys.size() - 1]))
	if KINDS.has(last) and value[keys[keys.size() - 1]] is Dictionary:
		# Модулятор поверх модулятора: цепляемся к последней его метке.
		var ids: Array = (value[keys[keys.size() - 1]] as Dictionary).get("__ids", [])
		if not ids.is_empty():
			return "%s_%s" % [last, ids[ids.size() - 1]]
	return last
