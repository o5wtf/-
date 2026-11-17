class_name SystemTtsBackend
extends SpeechBackend
## Системный голос через DisplayServer.tts_speak.
## Список голосов читается в момент speak, а не на старте: на Android движок поднимается с задержкой.
## Пустой список повторяется каждые 0.5 с около 5 с. Нет русского — берётся любой голос или пустой id.
## no_voice только если за это время голоса так и не появились.


const RETRY_INTERVAL_S := 0.5
const RETRY_WINDOW_S := 5.0

var driver: Object = null
var retry_interval_s: float = RETRY_INTERVAL_S
var retry_window_s: float = RETRY_WINDOW_S
var last_error: String = ""
var last_voice_id: String = ""
var last_voice_count: int = 0
var last_russian_count: int = 0
var _utterances: Dictionary = {}
var _next_utterance: int = 1
var _active: int = 0
var _generation: int = 0
var _instant: bool = false
var _clock_s: float = 0.0


func _ready() -> void:
	if driver == null:
		driver = DisplayTtsDriver.new()
	driver.call("bind", _on_started, _on_finished, _on_canceled)


func speak(line_id: String, text: String, voice_hint: String = "", _style: String = "") -> void:
	var token := _generation
	var spoken := text.strip_edges()
	if spoken == "":
		_fail(line_id, "empty")
		return
	var started := _now()
	var russian: Array = []
	var any_voices: Array = []
	while true:
		if token != _generation:
			return
		russian = _voices("ru")
		any_voices = _voices("")
		last_russian_count = russian.size()
		last_voice_count = any_voices.size()
		if not russian.is_empty() or not any_voices.is_empty():
			break
		if _now() - started >= retry_window_s:
			break
		if _instant:
			_clock_s += retry_interval_s
		else:
			await get_tree().create_timer(retry_interval_s).timeout
	if token != _generation:
		return
	if russian.is_empty() and any_voices.is_empty():
		last_voice_id = ""
		_fail(line_id, "no_voice")
		return
	var voice := choose_voice(voice_hint, russian, any_voices)
	last_voice_id = voice
	last_error = ""
	var utterance := _next_utterance
	_next_utterance += 1
	_utterances[utterance] = line_id
	_active = utterance
	driver.call("speak", spoken, voice, utterance)


func stop() -> void:
	_generation += 1
	_active = 0
	_utterances.clear()
	if driver != null:
		driver.call("stop")


func diagnostics() -> Dictionary:
	var feature := false
	if driver != null and driver.has_method("has_tts"):
		feature = bool(driver.call("has_tts"))
	return {
		"has_feature": feature,
		"voices": last_voice_count,
		"russian": last_russian_count,
		"voice_id": last_voice_id,
		"error": last_error,
	}


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


func _fail(line_id: String, kind: String) -> void:
	last_error = kind
	speech_error.emit(line_id, kind)


func _now() -> float:
	if _instant:
		return _clock_s
	return Time.get_ticks_msec() / 1000.0


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


func _complete(utterance_id: int, _canceled: bool) -> void:
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


	func has_tts() -> bool:
		return _available()


	func bind(started: Callable, finished: Callable, canceled: Callable) -> void:
		if not _available():
			return
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, started)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, finished)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, canceled)


	func _available() -> bool:
		return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
