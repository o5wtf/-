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
	assert_false(truncated["ok"])
	assert_eq(truncated["error"], "bad_response")
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
	transport.push(_status(429, "{}", {"Retry-After": "3"}))
	transport.push(_status(429, "{}"))
	transport.push(_status(429, "{}"))
	transport.push(_ok("{\"reply\":\"запасная\"}"))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_true(result["ok"])
	assert_eq(result["json"]["reply"], "запасная")
	assert_eq(client.waits, [3.0, 4.0])
	assert_eq(transport.seen.size(), 4)
	assert_true(str(transport.seen[0]["url"]).contains("/dialogue-model:"))
	assert_true(str(transport.seen[2]["url"]).contains("/dialogue-model:"))
	assert_true(str(transport.seen[3]["url"]).contains("/fallback-model:"))
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
	assert_eq(client.waits, [2.0, 4.0])
	client.free()


func test_server_error_retries_twice() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push(_status(500, ""))
	transport.push(_status(503, ""))
	var result: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(result["error"], "server")
	assert_eq(transport.seen.size(), 2)
	assert_eq(client.waits, [GeminiClient.SERVER_PAUSE_S])
	transport.push(_status(500, ""))
	transport.push(_ok("{\"reply\":\"после сбоя\"}"))
	var recovered: Dictionary = await client.generate(_request("dialogue"))
	assert_true(recovered["ok"])
	client.free()


func test_timeout_and_offline() -> void:
	var client := await _client()
	var transport: FakeTransport = client._transport
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"})
	var timed_out: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(timed_out["error"], "timeout")
	assert_eq(transport.seen.size(), 1)
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"})
	var offline: Dictionary = await client.generate(_request("dialogue"))
	assert_eq(offline["error"], "offline")
	assert_eq(transport.seen.size(), 2)
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
