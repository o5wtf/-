class_name SpeechBackend
extends Node
## Сменный синтез речи. Озвучка вызывает speak и stop и слушает сигналы.
## Игровой код выбирает реализацию снаружи: следующая может быть Gemini TTS.


signal started(line_id: String)
signal finished(line_id: String)
signal speech_error(line_id: String, kind: String)

## Gemini не подменяется системным голосом: неудачная реплика ждёт кнопку повтора.
var keeps_failed_line: bool = false


func speak(_line_id: String, _text: String, _voice_hint: String = "", _style: String = "") -> void:
	pass


func stop() -> void:
	pass


func speaking() -> bool:
	return false
