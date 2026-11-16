extends Node
## Какой VoiceProvider сейчас говорит и слушает. Смена в настройках без перезапуска.

signal voice_error(kind: String, message: String)
signal transcript_ready(text: String, is_final: bool)
signal speech_finished(utterance_id: int)

var enabled: bool = true
var provider: VoiceProvider
var volume: float = 1.0
var rate: float = 1.0
var stt_mode: String = "gemini_audio"
var style_mode: String = VoiceProfiles.DEFAULT_STYLE_MODE
var _gate := SpeechGate.new()


func _ready() -> void:
	reload()


func reload() -> void:
	var settings := SettingsStore.load_current()
	enabled = settings.voice_enabled
	volume = settings.voice_volume
	rate = settings.voice_rate
	stt_mode = settings.stt_mode
	style_mode = settings.style_mode
	var next := _make(settings.voice_provider)
	_detach()
	provider = next
	provider.user_volume = volume
	provider.user_rate = rate
	provider.style_mode = settings.style_mode
	add_child(provider)
	if provider.has_method("set_pause_ms"):
		provider.set_pause_ms(settings.pause_ms)
	provider.voice_error.connect(_on_error)
	provider.transcript_ready.connect(_on_transcript)
	provider.speech_finished.connect(_on_finished)


func prepare_speech() -> void:
	if provider != null and provider.has_method("prepare_connection"):
		provider.prepare_connection()


func open_line() -> int:
	return _gate.open()


func speak_agent(agent: CaseData.Agent, reply: String, remark: String, emotion: String, line_id: int = -1) -> int:
	if not enabled or provider == null:
		return -1
	var id := line_id if line_id > 0 else _gate.open()
	if not _gate.accept(id, reply):
		return -1
	provider.user_volume = volume
	provider.user_rate = rate
	provider.style_mode = style_mode
	if provider.has_method("speak_with_line"):
		return int(provider.call("speak_with_line", reply, VoiceProfiles.for_agent(agent), emotion, remark, id))
	return provider.speak(reply, VoiceProfiles.for_agent(agent), emotion, remark)


func speak_sample() -> int:
	if provider == null:
		return -1
	provider.user_volume = volume
	provider.user_rate = rate
	provider.style_mode = style_mode
	var profile := VoiceProfiles.for_person("sample", "Анна", "female", 40)
	return provider.speak(UiStrings.VOICE_SAMPLE, profile, "neutral", "")


func set_pause_ms(ms: int) -> void:
	if provider != null and provider.has_method("set_pause_ms"):
		provider.set_pause_ms(ms)


func input_held() -> bool:
	return provider != null and provider.has_method("input_held") and bool(provider.call("input_held"))


func speech_end_ms() -> int:
	if provider == null:
		return 0
	return int(provider.get("speech_end_ms"))


func start_listening() -> void:
	if provider == null:
		return
	if stt_mode == "builtin" or not provider.is_stt_available():
		voice_error.emit("unsupported", "Голосовой ввод недоступен на этом устройстве.")
		return
	provider.start_listening("ru-RU")


func listening() -> bool:
	return provider != null and provider.is_listening()


func stop_listening() -> void:
	if provider == null:
		return
	provider.stop_listening()


func stop() -> void:
	if provider != null:
		provider.stop_speaking()


func _make(which: String) -> VoiceProvider:
	if which == "builtin":
		return BuiltinVoiceProvider.new()
	return CloudVoiceProvider.new()


func _detach() -> void:
	if provider == null or not is_instance_valid(provider):
		provider = null
		return
	if provider.voice_error.is_connected(_on_error):
		provider.voice_error.disconnect(_on_error)
	if provider.transcript_ready.is_connected(_on_transcript):
		provider.transcript_ready.disconnect(_on_transcript)
	if provider.speech_finished.is_connected(_on_finished):
		provider.speech_finished.disconnect(_on_finished)
	provider.queue_free()
	provider = null


func _on_error(kind: String, message: String) -> void:
	voice_error.emit(kind, message)


func _on_transcript(text: String, is_final: bool) -> void:
	transcript_ready.emit(text, is_final)


func _on_finished(utterance_id: int) -> void:
	speech_finished.emit(utterance_id)
