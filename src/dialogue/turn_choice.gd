class_name TurnChoice
extends RefCounted
## Разбор поля chosen с начала потока. Пока реплика не целая, решение не применяется.

var raw: String = ""
var ended: bool = false


func push(chunk: String) -> void:
	raw += chunk


func finish() -> void:
	ended = true


func choice_ready() -> bool:
	return not _chosen_slice().is_empty()


func chosen() -> Array[int]:
	var slice := _chosen_slice()
	if slice == "":
		return []
	var parsed: Variant = JSON.parse_string(slice)
	var numbers: Array[int] = []
	if parsed is float or parsed is int:
		numbers.append(int(parsed))
		return numbers
	if parsed is Array:
		for item in parsed:
			numbers.append(int(item))
	return numbers


func reply_complete() -> bool:
	var body := payload()
	if body.is_empty():
		return false
	return str(body.get("reply", "")).strip_edges() != ""


func payload() -> Dictionary:
	var text := raw.strip_edges()
	if text.begins_with("```"):
		text = text.trim_prefix("```json").trim_prefix("```").trim_suffix("```").strip_edges()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


func _chosen_slice() -> String:
	var key := raw.find("\"chosen\"")
	if key < 0:
		return ""
	var colon := raw.find(":", key)
	if colon < 0:
		return ""
	var index := colon + 1
	while index < raw.length() and (raw[index] == " " or raw[index] == "\n" or raw[index] == "\t"):
		index += 1
	if index >= raw.length():
		return ""
	if raw[index] == "[":
		var end := _close(raw, index, "[", "]")
		if end < 0:
			return ""
		return raw.substr(index, end - index + 1)
	var end := index
	while end < raw.length() and raw[end] != "," and raw[end] != "}" and raw[end] != " " and raw[end] != "\n":
		end += 1
	if end == index:
		return ""
	return raw.substr(index, end - index)


func _close(text: String, start: int, opener: String, closer: String) -> int:
	var depth := 0
	var quote := false
	var escaped := false
	for index in range(start, text.length()):
		var ch := text[index]
		if quote:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				quote = false
			continue
		if ch == "\"":
			quote = true
			continue
		if ch == opener:
			depth += 1
		elif ch == closer:
			depth -= 1
			if depth == 0:
				return index
	return -1
