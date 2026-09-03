@tool
class_name StrudelTimeSpan
extends RefCounted

## Отрезок времени в циклах. Перенос `packages/core/timespan.mjs`.
##
## Границы — только дроби. Отрезок нулевой длины (`begin == end`) осмыслен и
## обрабатывается отдельно: на нём стоят аналоговые сигналы.

var begin: StrudelFraction
var end: StrudelFraction


func _init(from_time: Variant = 0, to_time: Variant = 1) -> void:
	begin = StrudelFraction.of(from_time)
	end = StrudelFraction.of(to_time)


func duration() -> StrudelFraction:
	return end.sub(begin)


func span_cycles() -> Array:
	## Режет отрезок по границам циклов. Многие расчёты выражаются проще, когда
	## каждое событие заведомо лежит внутри одного цикла.
	var spans: Array = []
	var b := begin
	var end_sam := end.sam()

	# Отрезок нулевой длины сохраняется как есть — иначе пропадают сигналы.
	if b.eq(end):
		spans.append(StrudelTimeSpan.new(b, end))
		return spans

	while end.gt(b):
		if b.sam().eq(end_sam):
			spans.append(StrudelTimeSpan.new(b, end))
			break
		var next_begin := b.next_sam()
		spans.append(StrudelTimeSpan.new(b, next_begin))
		b = next_begin
	return spans


func cycle_arc() -> StrudelTimeSpan:
	## Сдвигает отрезок в нулевой цикл, сохраняя длину.
	var b := begin.cycle_pos()
	return StrudelTimeSpan.new(b, b.add(duration()))


func with_time(fn: Callable) -> StrudelTimeSpan:
	return StrudelTimeSpan.new(fn.call(begin), fn.call(end))


func with_end(fn: Callable) -> StrudelTimeSpan:
	return StrudelTimeSpan.new(begin, fn.call(end))


func with_cycle(fn: Callable) -> StrudelTimeSpan:
	## Как with_time, но время отсчитывается от начала цикла.
	var sam := begin.sam()
	return StrudelTimeSpan.new(
		sam.add(fn.call(begin.sub(sam))),
		sam.add(fn.call(end.sub(sam)))
	)


func intersection(other: StrudelTimeSpan) -> StrudelTimeSpan:
	## Пересечение; null, если отрезки не пересекаются.
	var b := begin.max_(other.begin)
	var e := end.min_(other.end)

	if b.gt(e):
		return null
	if b.eq(e):
		# Касание в точке не считается пересечением, если это КОНЕЦ ненулевого
		# отрезка: иначе событие дублируется на границе цикла.
		if b.eq(end) and begin.lt(end):
			return null
		if b.eq(other.end) and other.begin.lt(other.end):
			return null
	return StrudelTimeSpan.new(b, e)


func intersection_e(other: StrudelTimeSpan) -> StrudelTimeSpan:
	var result := intersection(other)
	if result == null:
		push_error("StrudelTimeSpan: отрезки не пересекаются (%s и %s)" % [show(), other.show()])
	return result


func midpoint() -> StrudelFraction:
	return begin.add(duration().div(2))


func equals(other: StrudelTimeSpan) -> bool:
	if other == null:
		return false
	return begin.eq(other.begin) and end.eq(other.end)


func show() -> String:
	return begin.show() + " → " + end.show()


func _to_string() -> String:
	return show()
