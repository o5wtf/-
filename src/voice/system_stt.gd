class_name SystemStt
extends SttBackend
## Системный SpeechRecognizer Android. На рабочем столе плагина нет: это не ошибка запуска.


const PLUGIN := "SystemSpeech"

var bridge: Object = null
var prefer_offline: bool = false
var partial: String = ""
var listen_timeout_s: float = 8.0
var _attached: bool = false
var _session: int = 0
var _closed: bool = false
var _cached: Dictionary = {}
var _has_cached: bool = false

signal _done(payload: Dictionary)


func listens_live() -> bool:
	return true


static func plugin_available() -> bool:
	return available_from_report(_ensure_report())


static func refresh_report() -> void:
	_report_ready = false
	_report = _pull_report()
	_report_ready = true


static func available_from_report(report: Dictionary) -> bool:
	if bool(report.get("is_recognition_available", false)):
		return true
	if bool(report.get("on_device_available", false)):
		return true
	var services: Variant = report.get("services", [])
	return services is Array and not (services as Array).is_empty()


static func user_hint() -> String:
	if not Engine.has_singleton(PLUGIN):
		return "Системное распознавание не встроено в сборку"
	var report := _ensure_report()
	if str(report.get("activity", "")) == "missing":
		return "Системное распознавание ещё не готово. Нажмите «Проверить снова»."
	if available_from_report(report):
		return ""
	return "Служба распознавания речи не видна приложению"


static func status_lines() -> PackedStringArray:
	return lines_from_report(_ensure_report(), _record_state())


static func lines_from_report(report: Dictionary, record_audio: String) -> PackedStringArray:
	if report.is_empty():
		return PackedStringArray([
			"plugin=missing",
			"sdk_int=n/a",
			"manufacturer=",
			"model=",
			"activity=missing",
			"is_recognition_available=no",
			"is_recognition_available_error=",
			"on_device_available=no",
			"on_device_available_error=",
			"services=",
			"services_error=",
			"voice_recognition_service=",
			"voice_recognition_service_error=",
			"record_audio=%s" % record_audio,
			"причина=плагин не загружен",
		])
	var lines := PackedStringArray([
		"plugin=loaded",
		"sdk_int=%s" % str(report.get("sdk_int", "n/a")),
		"manufacturer=%s" % str(report.get("manufacturer", "")),
		"model=%s" % str(report.get("model", "")),
		"activity=%s" % str(report.get("activity", "")),
		"is_recognition_available=%s" % _yes_no(report.get("is_recognition_available", false)),
		"is_recognition_available_error=%s" % str(report.get("is_recognition_available_error", "")),
		"on_device_available=%s" % _yes_no(report.get("on_device_available", false)),
		"on_device_available_error=%s" % str(report.get("on_device_available_error", "")),
		"services=%s" % _service_text(report.get("services", [])),
		"services_error=%s" % str(report.get("services_error", "")),
		"voice_recognition_service=%s" % str(report.get("voice_recognition_service", "")),
		"voice_recognition_service_error=%s" % str(report.get("voice_recognition_service_error", "")),
		"record_audio=%s" % record_audio,
		"причина=%s" % _reason(report),
	])
	return lines


static func _yes_no(value: Variant) -> String:
	return "yes" if bool(value) else "no"


static func _service_text(value: Variant) -> String:
	if value is not Array:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for item in value:
		if item is Dictionary:
			parts.append("%s/%s" % [str(item.get("package", "")), str(item.get("class", ""))])
	return ",".join(parts)


static func _reason(report: Dictionary) -> String:
	if str(report.get("activity", "")) == "missing":
		return "нет activity"
	if available_from_report(report):
		return "доступно"
	if str(report.get("services_error", "")) != "":
		return str(report.get("services_error", ""))
	return "служба распознавания не найдена"


static var _report: Dictionary = {}
static var _report_ready: bool = false


static func _ensure_report() -> Dictionary:
	if not _report_ready:
		refresh_report()
	return _report


static func _pull_report() -> Dictionary:
	if not Engine.has_singleton(PLUGIN):
		return {}
	var live: Object = Engine.get_singleton(PLUGIN)
	if live == null:
		return {}
	var raw := str(live.call("diagnosticsJson"))
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {"parse_error": raw}


static func _record_state() -> String:
	if OS.get_name() != "Android":
		return "n/a"
	if OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
		return "granted"
	return "denied"


static func hint_for_code(code: String) -> String:
	match code:
		"no_match":
			return "Не расслышал, повторите"
		"network":
			return "Нет сети для распознавания"
		"network_timeout":
			return "Истекло время сети распознавания"
		"audio":
			return "Не слышно микрофон. Говорите ближе"
		"client":
			return "Сбой распознавания на устройстве"
		"server":
			return "Сервер распознавания не ответил"
		"server_disconnected":
			return "Сервер распознавания отключился"
		"speech_timeout":
			return "Речь не началась"
		"busy":
			return "Распознавание занято"
		"permissions":
			return "Нет разрешения на микрофон"
		"language_not_supported":
			return "Язык распознавания не поддерживается"
		"language_unavailable":
			return "Язык распознавания недоступен"
		"cannot_check":
			return "Не удалось проверить распознавание"
		"cannot_listen_to_download_events":
			return "Не удалось слушать загрузку языка"
		"too_many_requests":
			return "Слишком много запросов к распознаванию"
		"timeout":
			return "Повторить распознавание"
		"unavailable":
			return "Системное распознавание недоступно"
		"cancelled":
			return ""
		_:
			return "Не удалось распознать."


static func code_from_android(error_code: int) -> String:
	match error_code:
		1:
			return "network_timeout"
		2:
			return "network"
		3:
			return "audio"
		4:
			return "server"
		5:
			return "client"
		6:
			return "speech_timeout"
		7:
			return "no_match"
		8:
			return "busy"
		9:
			return "permissions"
		10:
			return "too_many_requests"
		11:
			return "server_disconnected"
		12:
			return "language_not_supported"
		13:
			return "language_unavailable"
		14:
			return "cannot_check"
		15:
			return "cannot_listen_to_download_events"
		_:
			return "unavailable"


static func system_option_disabled(available: bool, selected_system: bool) -> bool:
	return not available and not selected_system


func start_listen() -> void:
	_session += 1
	_closed = false
	_has_cached = false
	_cached = {}
	partial = ""
	_ensure_bridge()
	if bridge == null or not bool(bridge.call("isAvailable")):
		_remember(_failure("unavailable"))
		return
	bridge.call("startListening", prefer_offline)


func finish_listen() -> Dictionary:
	var token := _session
	if _has_cached and not _closed and token == _session:
		return _take_cached()
	_ensure_bridge()
	if bridge == null or not bool(bridge.call("isAvailable")):
		return _failure("unavailable")
	bridge.call("stopListening")
	var started := Time.get_ticks_msec()
	var limit := int(maxf(listen_timeout_s, 0.05) * 1000.0)
	while token == _session and not _closed and not _has_cached:
		if Time.get_ticks_msec() - started >= limit:
			return _failure("timeout")
		if get_tree() == null:
			return _failure("timeout")
		await get_tree().process_frame
	if _closed or token != _session:
		return {"ok": false, "text": "", "error": "cancelled", "message": "", "usage": {}}
	if _has_cached:
		return _take_cached()
	return _failure("timeout")


func partial_text() -> String:
	if bridge != null and bridge.has_method("partialText"):
		var live := str(bridge.call("partialText"))
		if live != "":
			partial = live
	return partial


func cancel_listen() -> void:
	_closed = true
	_session += 1
	_has_cached = false
	_cached = {}
	partial = ""
	if bridge != null and bridge.has_method("cancelListening"):
		bridge.call("cancelListening")


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
	if _closed:
		return
	partial = text


func _on_finished(text: String) -> void:
	if _closed:
		return
	partial = text
	_remember({"ok": true, "text": text, "error": "", "message": "", "usage": {}})


func _on_failed(code: String) -> void:
	if _closed:
		return
	_remember(_failure(code))


func _remember(payload: Dictionary) -> void:
	if _closed:
		return
	_cached = payload.duplicate(true)
	_has_cached = true
	_done.emit(payload)


func _take_cached() -> Dictionary:
	var ready: Dictionary = _cached.duplicate(true)
	_has_cached = false
	_cached = {}
	return ready


func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"text": "",
		"error": code,
		"message": hint_for_code(code),
		"usage": {},
	}
