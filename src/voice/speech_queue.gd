class_name SpeechQueue
extends RefCounted
## Очередь реплик. Каждая line_id принимается один раз и звучит по порядку.
## stop очищает очередь и текущую реплику. reset забывает уже принятые id.


var current_id: String = ""
var pending: Array[Dictionary] = []
var _seen: Dictionary = {}


func enqueue(line_id: String, text: String, voice_hint: String = "") -> bool:
	var id := line_id.strip_edges()
	if id == "" or text.strip_edges() == "":
		return false
	if _seen.has(id):
		return false
	_seen[id] = true
	pending.append({"id": id, "text": text, "voice_hint": voice_hint})
	return true


func has(line_id: String) -> bool:
	return _seen.has(line_id.strip_edges())


func take_next() -> Dictionary:
	if current_id != "" or pending.is_empty():
		return {}
	var item: Dictionary = pending.pop_front()
	current_id = str(item.get("id", ""))
	return item


func finish(line_id: String) -> void:
	if current_id == line_id:
		current_id = ""


func stop() -> void:
	pending.clear()
	current_id = ""


func reset() -> void:
	stop()
	_seen.clear()
