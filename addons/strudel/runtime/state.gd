@tool
class_name StrudelState
extends RefCounted

## Состояние запроса: отрезок времени плюс управляющие значения.
## Перенос `packages/core/state.mjs`.
##
## В `controls` живут вещи, о которых паттерн узнаёт только в момент запроса:
## текущий темп (`_cps`) и зерно случайного (`randSeed`).

var span: StrudelTimeSpan
var controls: Dictionary = {}


func _init(query_span: StrudelTimeSpan = null, query_controls: Dictionary = {}) -> void:
	span = query_span
	controls = query_controls


func set_span(new_span: StrudelTimeSpan) -> StrudelState:
	return StrudelState.new(new_span, controls)


func with_span(fn: Callable) -> StrudelState:
	return set_span(fn.call(span))


func set_controls(extra: Dictionary) -> StrudelState:
	var merged := controls.duplicate()
	for k in extra:
		merged[k] = extra[k]
	return StrudelState.new(span, merged)
