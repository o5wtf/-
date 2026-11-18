extends SceneTree
## Живая проверка меток и стиля. Запуск только вручную.
## godot --headless --path . -s res://tests/manual/tts_tag_probe.gd
## Ключ берётся из GEMINI_PAID_API_KEY и в вывод не попадает.
## Если ключа нет, скрипт ничего не запрашивает.

func _initialize() -> void:
	var paid := OS.get_environment("GEMINI_PAID_API_KEY").strip_edges()
	if paid == "":
		print("tts_tag_probe skipped: GEMINI_PAID_API_KEY is empty")
		quit(0)
		return
	print("tts_tag_probe: paid key is set, but this runner does not call Gemini")
	quit(0)
