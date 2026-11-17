class_name SystemTtsBackend
extends SpeechBackend
## Системный голос через DisplayServer.tts_speak. Сначала русский голос, иначе любой.
## Если голосов нет, speak сообщает no_voice и не вызывает движок.


var driver: Object = null
var _utterances: Dictionary = {}
var _next_utterance: int = 1
var _active: int = 0


func _ready() -> void:
	if driver == null:
		driver = DisplayTtsDriver.new()
	driver.call("bind", _on_started, _on_finished, _on_canceled)


func speak(line_id: String, text: String, voice_hint: String = "") -> void:
	var spoken := text.strip_edges()
	if spoken == "":
		speech_error.emit(line_id, "empty")
		return
	var voice := choose_voice(voice_hint, _voices("ru"), _voices(""))
	if voice == "" and voice_hint.strip_edges() == "":
		speech_error.emit(line_id, "no_voice")
		return
	if voice == "":
		voice = voice_hint.strip_edges()
	var utterance := _next_utterance
	_next_utterance += 1
	_utterances[utterance] = line_id
	_active = utterance
	driver.call("speak", spoken, voice, utterance)


func stop() -> void:
	_active = 0
	_utterances.clear()
	driver.call("stop")


func speaking() -> bool:
	return _active != 0


static func choose_voice(hint: String, russian: Array, any_voices: Array) -> String:
	var wanted := hint.strip_edges()
	if wanted != "":
		var matched := _match(wanted, russian)
		if matched == "":
			matched = _match(wanted, any_voices)
		if matched != "":
			return matched
	if not russian.is_empty():
		return _voice_id(russian[0])
	if not any_voices.is_empty():
		return _voice_id(any_voices[0])
	return ""


func _voices(language: String) -> Array:
	var listed: Variant = driver.call("voices", language)
	if listed is Array:
		return listed
	return []


func _on_started(utterance_id: int) -> void:
	var line_id := str(_utterances.get(utterance_id, ""))
	if line_id == "":
		return
	started.emit(line_id)


func _on_finished(utterance_id: int) -> void:
	_complete(utterance_id, false)


func _on_canceled(utterance_id: int) -> void:
	_complete(utterance_id, true)


func _complete(utterance_id: int, canceled: bool) -> void:
	var line_id := str(_utterances.get(utterance_id, ""))
	if line_id == "":
		return
	_utterances.erase(utterance_id)
	if _active == utterance_id:
		_active = 0
	finished.emit(line_id)


static func _match(hint: String, voices: Array) -> String:
	for voice in voices:
		if voice is not Dictionary:
			continue
		var body := voice as Dictionary
		if str(body.get("id", "")) == hint or str(body.get("name", "")) == hint:
			return _voice_id(body)
	return ""


static func _voice_id(voice: Variant) -> String:
	if voice is not Dictionary:
		return ""
	return str((voice as Dictionary).get("id", "")).strip_edges()


class DisplayTtsDriver:
	extends RefCounted

	func voices(language: String) -> Array:
		if not _available():
			return []
		if language == "":
			return DisplayServer.tts_get_voices()
		var exact: Array = DisplayServer.tts_get_voices_for_language(language)
		if not exact.is_empty():
			return exact
		if language != "ru":
			return []
		var russian: Array = []
		for voice in DisplayServer.tts_get_voices():
			if voice is not Dictionary:
				continue
			var code := str((voice as Dictionary).get("language", "")).to_lower().replace("-", "_")
			if code.begins_with("ru"):
				russian.append(voice)
		return russian


	func speak(text: String, voice_id: String, utterance_id: int) -> void:
		if not _available():
			return
		DisplayServer.tts_speak(text, voice_id, 50, 1.0, 1.0, utterance_id, false)


	func stop() -> void:
		if not _available():
			return
		DisplayServer.tts_stop()


	func bind(started: Callable, finished: Callable, canceled: Callable) -> void:
		if not _available():
			return
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, started)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, finished)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, canceled)


	func _available() -> bool:
		return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
