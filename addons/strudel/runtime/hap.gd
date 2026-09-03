@tool
class_name StrudelHap
extends RefCounted

## Событие: значение, звучащее на отрезке `part`. Перенос `packages/core/hap.mjs`.
##
## `whole` — полная длительность события, `part` — тот его кусок, который попал
## в запрос. `part` никогда не выходит за `whole`.
##
## 🔴 `whole == null` означает АНАЛОГОВОЕ событие — непрерывный сигнал
## (`sine`, `rand`, `perlin`), у которого нет ни начала, ни конца. Такие события
## не играются сами и отбрасываются там, где нужна структура (`discrete_only`).
## Спутать их с дискретными — значит получить щелчки на каждом кадре.

var whole: StrudelTimeSpan = null
var part: StrudelTimeSpan = null
var value: Variant = null
var context: Dictionary = {}


func _init(
	whole_span: StrudelTimeSpan = null,
	part_span: StrudelTimeSpan = null,
	hap_value: Variant = null,
	hap_context: Dictionary = {}
) -> void:
	whole = whole_span
	part = part_span
	value = hap_value
	context = hap_context


func duration() -> StrudelFraction:
	## Длительность с поправкой на `clip`/`duration` в самом значении.
	var dur: StrudelFraction
	if value is Dictionary and value.has("duration") and (value["duration"] is int or value["duration"] is float):
		dur = StrudelFraction.of(value["duration"])
	elif whole != null:
		dur = whole.end.sub(whole.begin)
	else:
		dur = StrudelFraction.new(0)
	if value is Dictionary and value.has("clip") and (value["clip"] is int or value["clip"] is float):
		return dur.mul(value["clip"])
	return dur


func end_clipped() -> StrudelFraction:
	return whole.begin.add(duration())


func whole_or_part() -> StrudelTimeSpan:
	return whole if whole != null else part


func with_span(fn: Callable) -> StrudelHap:
	var new_whole: StrudelTimeSpan = fn.call(whole) if whole != null else null
	return StrudelHap.new(new_whole, fn.call(part), value, context)


func with_value(fn: Callable) -> StrudelHap:
	return StrudelHap.new(whole, part, fn.call(value), context)


func has_onset() -> bool:
	## Содержит ли кусок само начало события. Только такие события играются.
	return whole != null and whole.begin.eq(part.begin)


func has_tag(tag: String) -> bool:
	var tags: Array = context.get("tags", [])
	return tags.has(tag)


func span_equals(other: StrudelHap) -> bool:
	if whole == null and other.whole == null:
		return true
	if whole == null or other.whole == null:
		return false
	return whole.equals(other.whole)


func equals(other: StrudelHap) -> bool:
	return span_equals(other) and part.equals(other.part) and value == other.value


func combine_context(other: StrudelHap) -> Dictionary:
	var out := context.duplicate()
	for k in other.context:
		out[k] = other.context[k]
	var mine: Array = context.get("locations", [])
	var theirs: Array = other.context.get("locations", [])
	if not mine.is_empty() or not theirs.is_empty():
		out["locations"] = mine + theirs
	return out


func set_context(new_context: Dictionary) -> StrudelHap:
	return StrudelHap.new(whole, part, value, new_context)


func show() -> String:
	var v := JSON.stringify(value) if value is Dictionary or value is Array else str(value)
	if whole == null:
		return "[ ~%s | %s ]" % [part.show(), v]
	var spans := ""
	var is_whole := whole.begin.eq(part.begin) and whole.end.eq(part.end)
	if not whole.begin.eq(part.begin):
		spans += whole.begin.show() + " ⇜ "
	if not is_whole:
		spans += "("
	spans += part.show()
	if not is_whole:
		spans += ")"
	if not whole.end.eq(part.end):
		spans += " ⇝ " + whole.end.show()
	return "[ %s | %s ]" % [spans, v]


func _to_string() -> String:
	return show()
