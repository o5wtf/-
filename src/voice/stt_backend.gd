class_name SttBackend
extends Node
## Расшифровка речи. Реализация подменяется, ход игры её не выбирает.


func transcribe(_wav: PackedByteArray) -> Dictionary:
	return {"ok": false, "text": "", "error": "offline", "usage": {}}
