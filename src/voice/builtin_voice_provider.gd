class_name BuiltinVoiceProvider
extends VoiceProvider
## Системный синтез. Распознавание на устройстве появится отдельным шагом, сейчас его нет.

var host: Object = null
var _next_id: int = 1


func is_tts_available() -> bool:
	return not _voices().is_empty()


func is_stt_available() -> bool:
	return false


func speak(text: String, profile: VoiceProfiles.Profile, emotion: String, remark: String = "") -> int:
	var line := VoiceProfiles.spoken_text(text)
	if line == "":
		return -1
	if not is_tts_available():
		voice_error.emit("unsupported", "На устройстве нет синтеза речи.")
		return -1
	var utterance_id := _next_id
	_next_id += 1
	var voice := _pick_voice(profile)
	var volume := int(clampf(VoiceProfiles.playback_volume(emotion, user_volume) * 100.0, 0.0, 100.0))
	var rate := VoiceProfiles.playback_rate(emotion, user_rate)
	if host != null:
		host.call("speak", line, voice, volume, profile.pitch, rate, utterance_id)
		speech_finished.emit(utterance_id)
		return utterance_id
	DisplayServer.tts_speak(line, voice, volume, profile.pitch, rate, utterance_id, true)
	return utterance_id


func stop_speaking() -> void:
	if host != null:
		host.call("stop")
		return
	DisplayServer.tts_stop()


func start_listening(language: String = "ru-RU") -> void:
	voice_error.emit("unsupported", "Голосовой ввод недоступен на этом устройстве.")


func stop_listening() -> void:
	pass


func _ready() -> void:
	if host != null:
		return
	if not DisplayServer.has_method("tts_set_utterance_callback"):
		return
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, Callable(self, "_on_ended"))
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, Callable(self, "_on_ended"))


func _on_ended(utterance_id: int) -> void:
	speech_finished.emit(utterance_id)


func _voices() -> Array:
	if host != null:
		var listed: Variant = host.call("voices", "ru")
		return listed if listed is Array else []
	var found: Array = DisplayServer.tts_get_voices_for_language("ru")
	if found.is_empty():
		found = DisplayServer.tts_get_voices_for_language("ru_RU")
	return found


func _pick_voice(profile: VoiceProfiles.Profile) -> String:
	var voices := _voices()
	if voices.is_empty():
		return ""
	var want := "female" if profile.gender == "female" else "male"
	for voice in voices:
		if voice is not Dictionary:
			continue
		var blob := str((voice as Dictionary).get("name", "")).to_lower()
		if blob.contains(want):
			return str((voice as Dictionary).get("id", (voice as Dictionary).get("name", "")))
	var first: Dictionary = voices[0]
	return str(first.get("id", first.get("name", "")))
