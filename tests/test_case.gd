class_name TestCase
extends RefCounted
## Базовый класс набора тестов.
## Раннер создаёт экземпляр, вызывает методы test_* и читает провалы.

var _failed: bool = false
var _failures: PackedStringArray = PackedStringArray()
var _async_pending: bool = false


func reset() -> void:
	_failed = false
	_failures = PackedStringArray()
	_async_pending = false


## Пометить асинхронный тест до первого await.
## Если раннер не дождётся метода, провал останется.
func begin_async() -> void:
	_async_pending = true


## Снять пометку в конце асинхронного теста, после последнего await.
func end_async() -> void:
	_async_pending = false


func has_failed() -> bool:
	return _failed or _async_pending


func failure_messages() -> PackedStringArray:
	var messages := _failures.duplicate()
	if _async_pending:
		messages.append("асинхронный тест не дошёл до конца")
	return messages


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_record(_decorate("assert_eq: ожидалось %s, получено %s" % [_show(expected), _show(actual)], message))


func assert_true(value: bool, message: String = "") -> void:
	if not value:
		_record(_decorate("assert_true: ожидалось true", message))


func assert_false(value: bool, message: String = "") -> void:
	if value:
		_record(_decorate("assert_false: ожидалось false", message))


## Dictionary — ключ, Array и PackedStringArray — элемент, String — подстрока.
func assert_has(container: Variant, item: Variant, message: String = "") -> void:
	var found := _lookup(container, item)
	if found == -1:
		_record(_decorate("assert_has: контейнер типа %s не поддерживается" % type_string(typeof(container)), message))
		return
	if found == 0:
		_record(_decorate("assert_has: не найдено %s" % _show(item), message))


func fail(message: String = "") -> void:
	_record(message if message != "" else "fail")


func _lookup(container: Variant, item: Variant) -> int:
	if container is Dictionary:
		return 1 if (container as Dictionary).has(item) else 0
	if container is Array:
		return 1 if (container as Array).has(item) else 0
	if container is PackedStringArray:
		return 1 if (container as PackedStringArray).has(str(item)) else 0
	if container is String:
		return 1 if (container as String).contains(str(item)) else 0
	return -1


func _record(message: String) -> void:
	_failed = true
	_failures.append(message)


func _decorate(detail: String, message: String) -> String:
	if message == "":
		return detail
	return "%s. %s" % [detail, message]


func _show(value: Variant) -> String:
	if value is String:
		return "\"%s\"" % value
	return str(value)
