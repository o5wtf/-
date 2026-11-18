class_name GeminiSseDecoder
extends RefCounted
## Разбор потока Gemini TTS. События Google разделены \r\n\r\n,
## а кусок HTTP может разрезать событие посередине.


var usage: Dictionary = {}
var audio_parts: int = 0
var event_count: int = 0
var _raw: String = ""


func push(chunk: PackedByteArray) -> Array[PackedByteArray]:
	if chunk.is_empty():
		return []
	_raw += chunk.get_string_from_utf8()
	return _collect(false)


func finish() -> Array[PackedByteArray]:
	return _collect(true)


static func event_data(event: String) -> String:
	var lines := PackedStringArray()
	for line in event.split("\n", false):
		if line.begins_with("data:"):
			lines.append(line.substr(5).strip_edges())
	return "\n".join(lines)


static func audio_payloads(root: Dictionary) -> Array[PackedByteArray]:
	var found: Array[PackedByteArray] = []
	var candidates: Variant = root.get("candidates", [])
	if candidates is not Array:
		return found
	for candidate in candidates:
		if candidate is not Dictionary:
			continue
		var content: Variant = (candidate as Dictionary).get("content", {})
		if content is not Dictionary:
			continue
		var parts: Variant = (content as Dictionary).get("parts", [])
		if parts is not Array:
			continue
		for part in parts:
			if part is not Dictionary:
				continue
			var inline: Variant = (part as Dictionary).get("inlineData", {})
			if inline is not Dictionary:
				continue
			var encoded := str((inline as Dictionary).get("data", "")).strip_edges()
			if encoded == "":
				continue
			var pcm := Marshalls.base64_to_raw(encoded)
			if pcm.is_empty():
				continue
			found.append(pcm)
	return found


func _collect(flush: bool) -> Array[PackedByteArray]:
	var packets: Array[PackedByteArray] = []
	for event in _take_events(flush):
		var data := event_data(event)
		if data == "" or data == "[DONE]":
			continue
		var parsed: Variant = JSON.parse_string(data)
		if parsed is not Dictionary:
			continue
		var root := parsed as Dictionary
		if root.get("usageMetadata") is Dictionary:
			usage = root["usageMetadata"]
		for pcm in audio_payloads(root):
			audio_parts += 1
			packets.append(pcm)
	return packets


func _take_events(flush: bool) -> PackedStringArray:
	var held := ""
	var body := _raw
	if not flush and body.ends_with("\r"):
		held = "\r"
		body = body.substr(0, body.length() - 1)
	var normalized := body.replace("\r\n", "\n").replace("\r", "\n")
	var events := PackedStringArray()
	var start := 0
	while true:
		var idx := normalized.find("\n\n", start)
		if idx < 0:
			break
		events.append(normalized.substr(start, idx - start))
		event_count += 1
		start = idx + 2
	var tail := normalized.substr(start)
	if flush:
		if tail.strip_edges() != "":
			events.append(tail)
			event_count += 1
		_raw = ""
	else:
		_raw = tail + held
	return events
