extends SceneTree
## Один живой запрос к Gemini. Без GEMINI_API_KEY печатает SKIP и выходит с кодом 0.
## Windows, из корня репозитория:
##   set GEMINI_API_KEY=ключ
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/manual/gemini_smoke.gd
## Ключ в вывод не попадает. Файл config/dev.cfg в git не класть.


func _initialize() -> void:
	var env_key := OS.get_environment("GEMINI_API_KEY")
	if not LLMConfig.live_smoke_enabled(env_key):
		print("SKIP gemini_smoke")
		quit(0)
		return
	var code := await _run()
	quit(code)


func _run() -> int:
	var config := LLMConfig.new()
	config.api_key = OS.get_environment("GEMINI_API_KEY").strip_edges()
	config.provider = "gemini"
	config.timeout_s = 30.0
	config.min_interval_s = 0.0
	var client := GeminiClient.new()
	client.apply_config(config)
	root.add_child(client)
	var request := {
		"system": "Отвечай только JSON по схеме.",
		"user": "Верни объект, у которого поле ok равно true.",
		"schema": {
			"type": "object",
			"properties": {"ok": {"type": "boolean"}},
			"required": ["ok"],
		},
		"model_role": "dialogue",
		"temperature": 0.0,
		"max_output_tokens": 64,
	}
	var result: Dictionary = await client.generate(request)
	if not result["ok"]:
		print("FAIL gemini_smoke %s" % str(result.get("error", "")))
		return 1
	var payload: Dictionary = result["json"]
	if payload.get("ok", false) != true:
		print("FAIL gemini_smoke bad_response")
		return 1
	print("PASS gemini_smoke")
	return 0
