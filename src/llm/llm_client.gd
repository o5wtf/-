class_name LLMClient
extends Node
## Общий интерфейс запроса к модели. Настоящей сети здесь нет.

signal finished(result: Dictionary)


func generate(request: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"json": {},
		"raw_text": "",
		"error": "bad_response",
		"retry_after_s": 0.0,
	}
	finished.emit(result)
	return result
