class_name SttBackend
extends Node
## Расшифровка речи. Реализация подменяется, ход игры её не выбирает.


func transcribe(_wav: PackedByteArray) -> Dictionary:
	return {"ok": false, "text": "", "error": "offline", "usage": {}}


func listens_live() -> bool:
	return false


func start_listen() -> void:
	pass


func finish_listen() -> Dictionary:
	return {"ok": false, "text": "", "error": "offline", "message": "", "usage": {}}


func partial_text() -> String:
	return ""


func recover() -> Dictionary:
	return {"ok": false, "text": "", "error": "offline", "message": "", "usage": {}}
