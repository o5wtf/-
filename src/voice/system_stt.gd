class_name SystemStt
extends SttBackend
## Системный SpeechRecognizer Android. На рабочем столе плагина нет: это не ошибка запуска.


const PLUGIN := "SystemSpeech"

var bridge: Object = null
var prefer_offline: bool = false
var partial: String = ""
var _attached: bool = false

signal _done(payload: Dictionary)


func listens_live() -> bool:
	return true


static func plugin_available() -> bool:
	if not Engine.has_singleton(PLUGIN):
		return false
	var live: Object = Engine.get_singleton(PLUGIN)
	if live == null or not live.has_method("isAvailable"):
		return false
	return bool(live.call("isAvailable"))


static func hint_for_code(code: String) -> String:
	match code:
		"no_match":
			return "Не расслышал, повторите"
		"network":
			return "Нет сети для распознавания"
		"busy":
			return "Распознавание занято"
		"permissions":
			return "Нет разрешения на микрофон"
		"unavailable":
			return "Системное распознавание недоступно"
		_:
			return "Не удалось распознать."


static func code_from_android(error_code: int) -> String:
	match error_code:
		1, 2:
			return "network"
		7:
			return "no_match"
		8:
			return "busy"
		9:
			return "permissions"
		_:
			return "unavailable"


static func system_option_disabled(available: bool, selected_system: bool) -> bool:
	return not available and not selected_system


func start_listen() -> void:
	partial = ""
	_ensure_bridge()
	if bridge == null or not bool(bridge.call("isAvailable")):
		_done.emit(_failure("unavailable"))
		return
	bridge.call("startListening", prefer_offline)


func finish_listen() -> Dictionary:
	_ensure_bridge()
	if bridge == null or not bool(bridge.call("isAvailable")):
		return _failure("unavailable")
	bridge.call("stopListening")
	var payload: Dictionary = await _done
	return payload


func partial_text() -> String:
	if bridge != null and bridge.has_method("partialText"):
		var live := str(bridge.call("partialText"))
		if live != "":
			partial = live
	return partial


func recover() -> Dictionary:
	_ensure_bridge()
	if bridge != null and bridge.has_method("recover"):
		var pending: Variant = bridge.call("recover")
		if pending is Dictionary:
			return pending
		return await pending
	return _failure("unavailable")


func transcribe(_wav: PackedByteArray) -> Dictionary:
	return await recover()


func _ensure_bridge() -> void:
	if bridge != null:
		_attach(bridge)
		return
	if Engine.has_singleton(PLUGIN):
		bridge = Engine.get_singleton(PLUGIN)
		_attach(bridge)


func _attach(target: Object) -> void:
	if _attached or target == null:
		return
	_attached = true
	if target.has_signal("partial"):
		target.connect("partial", _on_partial)
	if target.has_signal("finished"):
		target.connect("finished", _on_finished)
	if target.has_signal("failed"):
		target.connect("failed", _on_failed)


func _on_partial(text: String) -> void:
	partial = text


func _on_finished(text: String) -> void:
	partial = text
	_done.emit({"ok": true, "text": text, "error": "", "message": "", "usage": {}})


func _on_failed(code: String) -> void:
	_done.emit(_failure(code))


func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"text": "",
		"error": code,
		"message": hint_for_code(code),
		"usage": {},
	}
