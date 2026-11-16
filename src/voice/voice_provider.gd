class_name VoiceProvider
extends Node
## Общий интерфейс синтеза и распознавания. Игровой ход от голоса не зависит.

signal speech_finished(utterance_id: int)
signal transcript_ready(text: String, is_final: bool)
signal voice_error(kind: String, message: String)

var user_volume: float = 1.0
var user_rate: float = 1.0


func is_tts_available() -> bool:
	return false


func is_stt_available() -> bool:
	return false


func speak(text: String, profile: VoiceProfiles.Profile, emotion: String, remark: String = "") -> int:
	return -1


func stop_speaking() -> void:
	pass


func start_listening(language: String = "ru-RU") -> void:
	pass


func stop_listening() -> void:
	pass
