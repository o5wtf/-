extends SceneTree
## Headless-раннер тестов.
## Запуск: godot --headless --path . -s res://tests/run_tests.gd

const TESTS_DIR := "res://tests"

var _method_regex := RegEx.new()


func _initialize() -> void:
	if _method_regex.compile("(?m)^func (test_[A-Za-z0-9_]+)\\s*\\(") != OK:
		print("FAIL раннер")
		print("  не скомпилировалось регулярное выражение методов")
		print("Итог: прошло 0, упало 1")
		quit(1)
		return
	var code := await _run_all()
	quit(code)


func _run_all() -> int:
	var passed := 0
	var failed := 0
	for file_name in _test_files():
		var path := "%s/%s" % [TESTS_DIR, file_name]
		var script := load(path) as GDScript
		if script == null:
			print("FAIL %s" % file_name)
			print("  не удалось загрузить скрипт")
			failed += 1
			continue
		var instance: Variant = script.new()
		if not (instance is TestCase):
			print("FAIL %s" % file_name)
			print("  скрипт не наследует TestCase")
			failed += 1
			_release(instance)
			continue
		var test_case := instance as TestCase
		for method_name in _test_methods(script):
			test_case.reset()
			var label := "%s:%s" % [file_name, method_name]
			if not test_case.has_method(method_name):
				print("FAIL %s" % label)
				print("  метод не найден")
				failed += 1
				continue
			# Godot 4.7: call() у корутины возвращает GDScriptFunctionState.
			# await подходит и для обычного метода, и для метода с await.
			await test_case.call(method_name)
			if test_case.has_failed():
				print("FAIL %s" % label)
				for message in test_case.failure_messages():
					print("  %s" % message)
				failed += 1
			else:
				print("PASS %s" % label)
				passed += 1
		_release(instance)
	if passed + failed == 0:
		print("FAIL тесты не найдены")
		print("Итог: прошло 0, упало 1")
		return 1
	print("Итог: прошло %d, упало %d" % [passed, failed])
	return 0 if failed == 0 else 1


func _test_files() -> PackedStringArray:
	var found := PackedStringArray()
	for file_name in DirAccess.get_files_at(TESTS_DIR):
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			found.append(file_name)
	found.sort()
	return found


func _test_methods(script: GDScript) -> PackedStringArray:
	var methods := PackedStringArray()
	for match in _method_regex.search_all(script.source_code):
		methods.append(match.get_string(1))
	return methods


func _release(instance: Variant) -> void:
	if instance is Node:
		(instance as Node).free()
