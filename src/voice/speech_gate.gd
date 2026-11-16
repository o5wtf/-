class_name SpeechGate
extends RefCounted
## Один владелец озвучки на реплику. Повтор того же текста отбрасывается.

var _active: int = 0
var _heard: Dictionary = {}
var _logged: Dictionary = {}


func open() -> int:
	_active += 1
	_heard[_active] = ""
	return _active


func accept(line_id: int, text: String) -> bool:
	if line_id != _active:
		return false
	var piece := normalize(text)
	if piece == "":
		return false
	var have := str(_heard.get(line_id, ""))
	if have == piece or _contains(have, piece) or (have != "" and piece.begins_with(have)):
		return false
	_heard[line_id] = (have + " " + piece).strip_edges()
	return true


func log_once(line_id: int, engine: String) -> String:
	if line_id <= 0 or _logged.has(line_id):
		return ""
	_logged[line_id] = true
	return "озвучка начата id=%d движок=%s" % [line_id, engine]


static func unsaid(reply: String, voiced: String) -> String:
	if voiced.strip_edges() == "":
		return reply.strip_edges()
	if reply.begins_with(voiced):
		return reply.substr(voiced.length()).strip_edges()
	return ""


static func engines_played(choice: String, reader_ok: bool, live_ok: bool) -> PackedStringArray:
	var played := PackedStringArray()
	if choice == VoiceRoute.READER and reader_ok:
		played.append(VoiceRoute.READER)
		return played
	if live_ok:
		played.append(VoiceRoute.LIVE)
		return played
	if reader_ok:
		played.append(VoiceRoute.READER)
	return played


static func connect_once(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback)


static func normalize(text: String) -> String:
	var folded := text.to_lower().replace("ё", "е")
	var kept := ""
	for index in folded.length():
		var ch := folded.substr(index, 1)
		if ch == " " or ch == "\n" or ch == "\t":
			kept += " "
		elif _letter(ch):
			kept += ch
	return " ".join(kept.split(" ", false))


static func _contains(have: String, piece: String) -> bool:
	if have == "" or piece == "":
		return false
	return (" " + have + " ").contains(" " + piece + " ")


static func _letter(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or (ch >= "а" and ch <= "я")
