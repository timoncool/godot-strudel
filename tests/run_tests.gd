@tool
extends SceneTree

## Прогон тестов плагина без редактора.
##
##   godot --headless --path <проект> --script res://tests/run_tests.gd
##
## Каждый файл tests/test_*.gd — объект с методами `test_*`. Падение — это
## непустой список бед, который печатается целиком: обрезанный вывод прячет
## причину.

var _failures: Array[String] = []
var _checks := 0
var _cases := 0


func _init() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)

	var files := _test_files()
	if files.is_empty():
		print("[тесты] не нашёл ни одного tests/test_*.gd")
		quit(1)
		return

	for path in files:
		if only != "" and not path.contains(only):
			continue
		_run_file(path)

	print("")
	print("[тесты] проверок %d, случаев %d, бед %d" % [_checks, _cases, _failures.size()])
	if not _failures.is_empty():
		print("")
		for f in _failures:
			print("  ✗ " + f)
	quit(0 if _failures.is_empty() else 1)


func _test_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("test_") and name.ends_with(".gd"):
			out.append("res://tests/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		_failures.append("%s: не загрузился (ошибка разбора — см. вывод выше)" % path)
		return
	var suite = script.new()
	suite.set("_runner", self)
	var short := path.get_file()
	for m in suite.get_method_list():
		var mname: String = m.get("name", "")
		if not mname.begins_with("test_"):
			continue
		_cases += 1
		var before := _failures.size()
		var checks_before := _checks
		suite.set("_case", "%s::%s" % [short, mname])
		suite.call(mname)
		if _checks == checks_before:
			# Ни одной сверки — значит случай оборвался ошибкой движка.
			# Молчаливое «✓» здесь опаснее падения.
			_failures.append("%s::%s — не сделал ни одной сверки (оборвался?)" % [short, mname])
		if _failures.size() == before:
			print("  ✓ %s::%s" % [short, mname])
		else:
			print("  ✗ %s::%s" % [short, mname])


func fail(case_name: String, message: String) -> void:
	_failures.append("%s — %s" % [case_name, message])


func note_check() -> void:
	_checks += 1
