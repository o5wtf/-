extends TestCase

const SECRET := "unit-test-key"


func test_config_key_order() -> void:
	var user_key := LLMConfig.from_sources(_cfg("user-key", "model-from-user"), "env-key", _cfg("dev-key", "model-from-dev"), true)
	assert_eq(user_key.key_source, "user")
	assert_true(user_key.api_key == "user-key", "ключ из user://")
	assert_eq(user_key.dialogue_model, "model-from-user")
	var env_key := LLMConfig.from_sources(_cfg("", "model-from-user"), "env-key", _cfg("dev-key", "model-from-dev"), true)
	assert_eq(env_key.key_source, "env")
	assert_true(env_key.api_key == "env-key", "ключ из окружения")
	assert_eq(env_key.dialogue_model, "model-from-user")
	var dev_key := LLMConfig.from_sources("", "", _cfg("dev-key", "model-from-dev"), true)
	assert_eq(dev_key.key_source, "dev")
	assert_true(dev_key.api_key == "dev-key", "ключ из dev.cfg")
	assert_eq(dev_key.dialogue_model, "model-from-dev")
	var release := LLMConfig.from_sources("", "", _cfg("dev-key", "model-from-dev"), false)
	assert_eq(release.key_source, "none")
	assert_eq(release.api_key, "")
	assert_eq(release.dialogue_model, LLMConfig.DEFAULT_DIALOGUE_MODEL)
	assert_eq(LLMConfig.DEFAULT_DIALOGUE_MODEL, "gemini-3.5-flash-lite")
	assert_eq(release.thinking_level, "MINIMAL")
	assert_eq(release.min_interval_s, 0.0)
	var gemini := LLMConfig.create_client(user_key)
	assert_true(gemini is GeminiClient)
	gemini.free()
	user_key.provider = "mock"
	var mock := LLMConfig.create_client(user_key)
	assert_true(mock is MockLLMClient)
	mock.free()


func test_request_body_uses_config_models_and_schema() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"да\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "да")
	assert_eq(transport.seen.size(), 1)
	var call: Dictionary = transport.seen[0]
	assert_true(str(call["url"]).contains("/dialogue-model:generateContent"), "адрес модели")
	assert_false(str(call["url"]).contains(SECRET), "ключ в адресе")
	var headers: Dictionary = call["headers"]
	assert_eq(headers["Content-Type"], "application/json")
	assert_true(headers["x-goog-api-key"] == SECRET, "заголовок ключа")
	var body: Dictionary = JSON.parse_string(call["body"])
	assert_true(body.has("systemInstruction"))
	assert_eq(body["systemInstruction"]["parts"][0]["text"], "система")
	assert_eq(body["contents"][0]["role"], "user")
	assert_eq(body["contents"][0]["parts"][0]["text"], "вопрос")
	var generation: Dictionary = body["generationConfig"]
	assert_eq(generation["responseMimeType"], "application/json")
	assert_true(generation.has("responseJsonSchema"))
	assert_eq(generation["responseJsonSchema"]["required"], ["reply"])
	assert_eq(generation["thinkingConfig"]["thinkingLevel"], "LOW")
	assert_eq(generation["temperature"], 0.9)
	assert_eq(generation["maxOutputTokens"], 2048)
	var safety: Array = body["safetySettings"]
	assert_eq(safety.size(), 4)
	assert_eq(safety[0]["threshold"], "BLOCK_ONLY_HIGH")
	assert_false(JSON.stringify(result).contains(SECRET), "ключ попал в результат")
	client.free()


func test_summary_model_and_thought_parts() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"кратко\"}", true))
	var request := _request("summary")
	var result: Dictionary = await client.generate(request)
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "кратко")
	assert_false(result["raw_text"].contains("скрытые рассуждения"))
	assert_true(str(transport.seen[0]["url"]).contains("/summary-model:generateContent"))
	client.free()


func test_finish_and_block_reasons() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_candidate("{\"reply\":\"x\"}", "MAX_TOKENS"))
	var truncated: Dictionary = await client.generate(_request("dialogue"))
	assert_true(truncated["ok"])
	assert_eq(truncated["json"]["reply"], "x")
	transport.push(_candidate("{\"reply\":\"x\"}", "SAFETY"))
	var safety: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(safety["error"], "blocked")
	transport.push(_blocked_prompt())
	var blocked: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(blocked["error"], "blocked")
	client.free()


func test_malformed_json_and_schema_fallback() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push({"ok": true, "status": 200, "body": "not-json", "headers": {}, "error": ""})
	var broken: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(broken["error"], "bad_response")
	transport.push(_candidate("not-json-object", "STOP"))
	var broken_text: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(broken_text["error"], "bad_response")
	transport.push(_status(400, "{\"error\":{\"message\":\"Invalid JSON payload. Unknown name responseJsonSchema\"}}"))
	transport.push(_ok("{\"reply\":\"через старую схему\"}"))
	var switched: Dictionary = await client.generate(_request("dialogue"))
	assert_true(switched["ok"])
	var first: Dictionary = JSON.parse_string(transport.seen[2]["body"])
	var second: Dictionary = JSON.parse_string(transport.seen[3]["body"])
	assert_true(first["generationConfig"].has("responseJsonSchema"))
	assert_false(first["generationConfig"].has("responseSchema"))
	assert_true(second["generationConfig"].has("responseSchema"))
	assert_false(second["generationConfig"].has("responseJsonSchema"))
	client.free()


func test_invalid_key_statuses() -> void:
	for status in [400, 401, 403]:
		var client := await _client()
		var transport: FakeTransport = client._transport
		transport.push(_status(status, "{\"error\":{\"status\":\"API_KEY_INVALID\",\"message\":\"API key not valid. Please pass a valid API key.\"}}"))
		var result: Dictionary = await client.generate(_request("dialogue"))
		assert_false(result["ok"], "статус %d" % status)
		assert_eq(result["error"], "auth", "статус %d" % status)
		assert_true(str(result["message"]).contains("Ключ"), "понятный текст")
		assert_false(JSON.stringify(result).contains(SECRET), "ключ попал в результат")
		assert_eq(transport.seen.size(), 1, "без повторов")
		client.free()


func test_missing_key_does_not_call_network() -> void:
	var client := await _client("")
	var transport: FakeTransport = client._transport
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "auth")
	assert_true(str(result["message"]).contains("Не задан ключ"))
	assert_eq(transport.seen.size(), 0)
	client.free()


func test_rate_limit_then_fallback_model() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(429, "{\"error\":{\"message\":\"quota\"}}"))
	transport.push(_ok("{\"reply\":\"запасная\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "запасная")
	assert_eq(result["model"], "gemini-3.5-flash")
	assert_eq(client.waits.size(), 0)
	assert_eq(transport.seen.size(), 2)
	assert_true(str(transport.seen[0]["url"]).contains("/dialogue-model:"))
	assert_true(str(transport.seen[1]["url"]).contains("/gemini-3.5-flash:"))
	client.free()


func test_rate_limit_exhausted_is_rate_limited() -> void:
	var client := await _client()
	client.fallback_model = client.dialogue_model
	var transport: FakeTransport = client._transport
	for _i in 3:
		transport.push(_status(429, "{}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "rate_limited")
	assert_eq(transport.seen.size(), 3)
	assert_true(str(result["message"]).contains("dialogue-model"))
	client.free()


func test_server_error_retries_twice() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(500, ""))
	transport.push(_status(500, ""))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "server")
	assert_eq(transport.seen.size(), 2)
	assert_eq(client.waits, [GeminiClient.SERVER_PAUSE_S])
	assert_true(str(transport.seen[1]["url"]).contains("/dialogue-model:"))
	transport.push(_status(500, ""))
	transport.push(_ok("{\"reply\":\"после сбоя\"}"))
	var recovered: Dictionary = await client.generate(_request("dialogue"))
	assert_true(recovered["ok"])
	client.free()


func test_timeout_and_offline() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"})
	transport.push(_ok("{\"reply\":\"успел\"}"))
	var timed_out: Dictionary = await client.generate(_request("dialogue"))
	assert_true(timed_out["ok"])
	assert_eq(timed_out["model"], "gemini-3.5-flash")
	assert_eq(transport.seen.size(), 2)
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"})
	var offline: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(offline["error"], "offline")
	assert_eq(transport.seen.size(), 3)
	client.free()


func test_min_interval_between_requests() -> void:
	var client := await _client()
	client.min_interval_s = 5.0
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"раз\"}"))
	transport.push(_ok("{\"reply\":\"два\"}"))
	var first: Dictionary = await client.generate(_request("dialogue"))
	var second: Dictionary = await client.generate(_request("dialogue"))
	assert_true(first["ok"] and second["ok"])
	assert_eq(client.waits, [5.0])
	client.free()


func test_only_one_request_in_flight() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"reply\":\"после очереди\"}"))
	client._busy = true
	var waiting: Variant = client.call("generate", _request("dialogue"))
	assert_eq(transport.calls, 0, "второй запрос не стартовал, пока первый в полёте")
	client._busy = false
	(Engine.get_main_loop() as SceneTree).process_frame.connect(func() -> void: client._released.emit(), CONNECT_ONE_SHOT)
	var result: Dictionary = await waiting
	assert_true(result["ok"])
	assert_eq(transport.calls, 1)
	assert_false(JSON.stringify(result).contains(SECRET), "ключ попал в результат")
	await (Engine.get_main_loop() as SceneTree).process_frame
	client.free()


func test_lite_shape_is_accepted() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	var fenced := "```json\n{\"player_tone\": \"1\", \"reply\": \"Я ничего не видел.\", \"remark\": \"отводит взгляд\", \"emotion\": \"Neutral\"}\n```"
	var parts: Array = [
		{"thought": true, "text": "скрытые рассуждения"},
		{"text": fenced, "thoughtSignature": "sig"},
	]
	var payload := {"candidates": [{"content": {"parts": parts}, "finishReason": "MAX_TOKENS"}]}
	transport.push({"ok": true, "status": 200, "body": JSON.stringify(payload), "headers": {}, "error": ""})
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "Я ничего не видел.")
	assert_eq(result["json"]["player_tone"], 1)
	assert_eq(result["json"]["emotion"], "neutral")
	assert_false(str(result["raw_text"]).contains("скрытые рассуждения"))
	client.free()


func test_truncated_json_retries_without_thinking() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_candidate("{", "MAX_TOKENS"))
	transport.push(_ok("{\"reply\":\"после повтора\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "после повтора")
	var retry: Dictionary = JSON.parse_string(transport.seen[1]["body"])
	assert_false(retry["generationConfig"].has("thinkingConfig"))
	assert_true(int(retry["generationConfig"]["maxOutputTokens"]) >= 8192)
	client.free()


func test_overloaded_and_missing_model_switch() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(503, "{\"error\":{\"message\":\"high demand\",\"status\":\"UNAVAILABLE\"}}"))
	transport.push(_status(404, "{\"error\":{\"message\":\"no longer available to new users\",\"status\":\"NOT_FOUND\"}}"))
	transport.push(_ok("{\"reply\":\"есть\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["model"], "fallback-model")
	assert_true(str(transport.seen[0]["url"]).contains("/dialogue-model:"))
	assert_true(str(transport.seen[1]["url"]).contains("/gemini-3.5-flash:"))
	client.free()


func test_plain_400_is_not_an_auth_error() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(400, "{\"error\":{\"status\":\"INVALID_ARGUMENT\",\"message\":\"thinkingLevel is not supported\"}}"))
	transport.push(_ok("{\"reply\":\"без рассуждений\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	var retry: Dictionary = JSON.parse_string(transport.seen[1]["body"])
	assert_false(retry["generationConfig"].has("thinkingConfig"))
	assert_eq(transport.seen.size(), 2)
	client.free()


func test_timeout_names_the_model() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	for _i in 4:
		transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"})
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "timeout")
	assert_true(str(result["message"]).contains("dialogue-model"))
	assert_true(str(result["message"]).contains("Пробовали"))
	assert_false(str(result["message"]).contains("Нет сети"))
	client.free()


func test_session_remembers_the_model_that_answered() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"})
	transport.push(_ok("{\"reply\":\"успел\"}"))
	var first: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(first["model"], "gemini-3.5-flash")
	transport.push(_ok("{\"reply\":\"снова\"}"))
	var second: Dictionary = await client.generate(_request("dialogue"))
	assert_true(second["ok"])
	assert_true(str(transport.seen[2]["url"]).contains("/gemini-3.5-flash:"))
	client.free()


func test_probe_uses_a_short_timeout_without_thinking() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_ok("{\"ok\":\"да\"}"))
	var request := _request("dialogue")
	request["probe"] = true
	request["timeout_s"] = 12.0
	var result: Dictionary = await client.generate(request)
	assert_true(result["ok"])
	assert_eq(transport.seen[0]["timeout"], 12.0)
	var body: Dictionary = JSON.parse_string(transport.seen[0]["body"])
	assert_false(body["generationConfig"].has("thinkingConfig"))
	client.free()


func test_stream_extracts_reply_without_waiting_for_the_tail() -> void:
	var first_event := {"candidates": [{"content": {"parts": [{"text": "{\"player_tone\":0,\"reply\":\"Хватит. "}]}}]}
	var partial := GeminiClient.push_sse({"pending": "", "text": ""}, "data: %s\n" % JSON.stringify(first_event))
	assert_eq(GeminiClient.reply_so_far(str(partial["text"])), "Хватит. ")
	var second_event := {"candidates": [{"content": {"parts": [{"text": "Ещё.\"}"}]}}]}
	var more := GeminiClient.push_sse(partial, "data: %s\n\n" % JSON.stringify(second_event))
	assert_eq(GeminiClient.reply_so_far(str(more["text"])), "Хватит. Ещё.")
	var taken: Dictionary = GeminiClient.take_sentences("Хватит. Ещё")
	assert_eq((taken["ready"] as PackedStringArray)[0], "Хватит.")
	assert_eq(taken["rest"], " Ещё")
	var client := await _client()
	var transport: FakeTransport = client._transport
	var model_json := JSON.stringify({"reply": "Да."})
	var envelope := {"candidates": [{"content": {"parts": [{"text": model_json}]}}]}
	var sse := "data: %s\n\n" % JSON.stringify(envelope)
	transport.push({"ok": true, "status": 200, "body": sse, "headers": {}, "error": ""})
	var request := _request("dialogue")
	request["stream"] = true
	var heard: Array = []
	client.reply_text.connect(func(text: String) -> void: heard.append(text))
	var result: Dictionary = await client.generate(request)
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "Да.")
	assert_eq(heard[0], "Да.")
	assert_true(str(transport.seen[0]["url"]).contains(":streamGenerateContent"))
	assert_false(str(transport.seen[0]["url"]).contains(SECRET))
	client.free()


func test_live_smoke_is_skipped_without_env_key() -> void:
	assert_false(LLMConfig.live_smoke_enabled(""))
	assert_false(LLMConfig.live_smoke_enabled("   "))
	assert_true(LLMConfig.live_smoke_enabled("present"))
	var env_key := OS.get_environment("GEMINI_API_KEY").strip_edges()
	if env_key == "":
		assert_false(LLMConfig.live_smoke_enabled(env_key), "без ключа живой тест не запускается")


func _client(key: String = SECRET) -> GeminiClient:
	var config := LLMConfig.new()
	config.api_key = key
	config.dialogue_model = "dialogue-model"
	config.summary_model = "summary-model"
	config.fallback_model = "fallback-model"
	config.thinking_level = "LOW"
	config.timeout_s = 30.0
	config.min_interval_s = 0.0
	var client := GeminiClient.new()
	client.apply_config(config)
	client._instant_wait = true
	var transport := FakeTransport.new()
	client.set_transport(transport)
	(Engine.get_main_loop() as SceneTree).root.add_child(client)
	return client


func _request(role: String) -> Dictionary:
	return {
		"system": "система",
		"user": "вопрос",
		"schema": {"type": "object", "properties": {"reply": {"type": "string"}}, "required": ["reply"]},
		"model_role": role,
		"temperature": 0.9,
		"max_output_tokens": 2048,
	}


func _ok(text: String, with_thought: bool = false) -> Dictionary:
	return _candidate(text, "STOP", with_thought)


func _candidate(text: String, finish: String, with_thought: bool = false) -> Dictionary:
	var parts: Array = []
	if with_thought:
		parts.append({"thought": true, "text": "скрытые рассуждения"})
	parts.append({"text": text})
	var payload := {
		"candidates": [{
			"content": {"parts": parts},
			"finishReason": finish,
		}],
	}
	return {"ok": true, "status": 200, "body": JSON.stringify(payload), "headers": {}, "error": ""}


func _blocked_prompt() -> Dictionary:
	var payload := {"promptFeedback": {"blockReason": "SAFETY"}}
	return {"ok": true, "status": 200, "body": JSON.stringify(payload), "headers": {}, "error": ""}


func _status(code: int, body: String, headers: Dictionary = {}) -> Dictionary:
	return {"ok": true, "status": code, "body": body, "headers": headers, "error": ""}


func _cfg(key: String, model: String) -> String:
	return "[llm]\napi_key=\"%s\"\ndialogue_model=\"%s\"\nsummary_model=\"summary-model\"\nfallback_model=\"fallback-model\"\nthinking_level=\"LOW\"\ntimeout_s=30\nmin_interval_s=1.0\n" % [key, model]


class FakeTransport:
	extends RefCounted

	var scripted: Array = []
	var seen: Array = []
	var calls: int = 0

	func push(outcome: Dictionary) -> void:
		scripted.append(outcome)

	func request(url: String, headers: Dictionary, body: String, timeout_s: float) -> Dictionary:
		calls += 1
		seen.append({"url": url, "headers": headers, "body": body, "timeout": timeout_s})
		if scripted.is_empty():
			return {"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"}
		return scripted.pop_front()
