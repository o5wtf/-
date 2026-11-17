extends Node
## Очередь озвучки реплик. Бэкенд подменяется, игровой ход его не знает.
## Сигнал is_speaking нужен будущему микрофону; самого микрофона здесь нет.

signal is_speaking(active: bool)
signal voice_error(kind: String)

var backend: SpeechBackend
var enabled: bool = false
var speaking: bool = false
var last_error: String = ""
var listen_to_game: bool = true
var queue: SpeechQueue = SpeechQueue.new()
var _lengths: Dictionary = {}


func _ready() -> void:
	enabled = SettingsStore.load_current().voice_enabled
	if backend == null:
		backend = SystemTtsBackend.new()
	if backend.get_parent() == null:
		add_child(backend)
	_bind_backend()
	if listen_to_game and not Game.agent_replied.is_connected(_on_replied):
		Game.agent_replied.connect(_on_replied)


func use_backend(next: SpeechBackend) -> void:
	if backend != null and is_instance_valid(backend) and backend.get_parent() == self:
		backend.queue_free()
	backend = next
	if next.get_parent() != self:
		add_child(next)
	_bind_backend()


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop_and_clear()


func speak_test() -> String:
	stop_and_clear()
	var text := "Проверка голоса."
	_lengths["voice-test"] = text.length()
	if backend != null:
		await backend.speak("voice-test", text, "")
	return voice_status_line()


func voice_status_line() -> String:
	var info := {}
	if backend != null and backend.has_method("diagnostics"):
		info = backend.call("diagnostics")
	var feature := "yes" if bool(info.get("has_feature", false)) else "no"
	var voice := str(info.get("voice_id", ""))
	if voice == "":
		voice = "-"
	var err := str(info.get("error", ""))
	if err == "":
		err = "none"
	last_error = "" if err == "none" else err
	return "TEXT_TO_SPEECH %s · voices %d · russian %d · voice %s · error %s" % [
		feature,
		int(info.get("voices", 0)),
		int(info.get("russian", 0)),
		voice,
		err,
	]


func speak_reply(agent_id: String, reply: String) -> void:
	if not enabled:
		return
	var line_id := line_id_for(agent_id)
	var text := SpeechText.clean(reply)
	if not queue.enqueue(line_id, text):
		return
	_lengths[line_id] = text.length()
	_pump()


func stop_and_clear() -> void:
	var current := queue.current_id
	queue.stop()
	if current != "":
		_lengths.erase(current)
	if backend != null:
		backend.stop()
	_set_speaking(false)


func reset_for_case() -> void:
	stop_and_clear()
	queue.reset()
	_lengths.clear()


func line_id_for(agent_id: String) -> String:
	var case_id := ""
	var turn := 0
	if Game.state != null:
		case_id = str(Game.state.case_id)
		turn = int(Game.state.turn)
	return "%s:%s:%d" % [case_id, agent_id, turn]


func _on_replied(agent_id: String, text: String, _remark: String) -> void:
	speak_reply(agent_id, text)


func _pump() -> void:
	if queue.current_id != "":
		return
	var item := queue.take_next()
	if item.is_empty():
		_set_speaking(false)
		return
	_set_speaking(true)
	backend.speak(str(item["id"]), str(item["text"]), str(item.get("voice_hint", "")))


func _bind_backend() -> void:
	if backend == null:
		return
	if not backend.started.is_connected(_on_started):
		backend.started.connect(_on_started)
	if not backend.finished.is_connected(_on_finished):
		backend.finished.connect(_on_finished)
	if not backend.speech_error.is_connected(_on_error):
		backend.speech_error.connect(_on_error)


func _on_started(line_id: String) -> void:
	if last_error != "":
		last_error = ""
		voice_error.emit("")
	print("voice start id=%s len=%d" % [line_id, int(_lengths.get(line_id, 0))])


func _on_finished(line_id: String) -> void:
	if queue.current_id != line_id:
		return
	print("voice finish id=%s len=%d" % [line_id, int(_lengths.get(line_id, 0))])
	_lengths.erase(line_id)
	queue.finish(line_id)
	_pump()


func _on_error(line_id: String, kind: String) -> void:
	last_error = kind
	voice_error.emit(kind)
	print("voice error id=%s len=%d kind=%s" % [line_id, int(_lengths.get(line_id, 0)), kind])
	if kind == "no_voice":
		queue.stop()
		_lengths.clear()
		_set_speaking(false)
		return
	if queue.current_id != line_id:
		return
	_lengths.erase(line_id)
	queue.finish(line_id)
	_pump()


func _set_speaking(active: bool) -> void:
	if queue.current_id == "" and queue.pending.is_empty():
		active = false
	if active == speaking:
		return
	speaking = active
	is_speaking.emit(active)
