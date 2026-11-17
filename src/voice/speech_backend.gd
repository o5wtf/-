class_name SpeechBackend
extends Node
## Сменный синтез речи. Озвучка вызывает speak и stop и слушает сигналы.
## Игровой код выбирает реализацию снаружи: следующая может быть Gemini TTS.


signal started(line_id: String)
signal finished(line_id: String)
signal speech_error(line_id: String, kind: String)


func speak(_line_id: String, _text: String, _voice_hint: String = "") -> void:
	pass


func stop() -> void:
	pass


func speaking() -> bool:
	return false
