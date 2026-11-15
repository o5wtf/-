class_name MockLLMClient
extends LLMClient
## Ответы из очереди. Пустая очередь — bad_response, без сети.

var queue: Array[Dictionary] = []
var calls: Array[Dictionary] = []


func enqueue(result: Dictionary) -> void:
	queue.append(result.duplicate(true))


func generate(request: Dictionary) -> Dictionary:
	calls.append(request.duplicate(true))
	var result: Dictionary
	if queue.is_empty():
		result = {
			"ok": false,
			"json": {},
			"raw_text": "",
			"error": "bad_response",
			"retry_after_s": 0.0,
		}
	else:
		result = queue.pop_front()
	finished.emit(result)
	return result
