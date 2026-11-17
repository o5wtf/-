extends TestCase


func test_request_line_has_counters_and_no_secret() -> void:
	var secret := "unit-test-key"
	var line := LlmTiming.request_line({
		"model": "gemini-3.5-flash-lite",
		"thinking": "LOW",
		"http": 200,
		"response_ms": 900,
		"total_ms": 1900,
		"prompt_tokens": 120,
		"thought_tokens": 30,
		"output_tokens": 40,
		"finish": "STOP",
		"retry": "none",
	})
	assert_true(line.contains("model=gemini-3.5-flash-lite"))
	assert_true(line.contains("thinking=LOW"))
	assert_true(line.contains("http=200"))
	assert_true(line.contains("response_ms=900"))
	assert_true(line.contains("total_ms=1900"))
	assert_true(line.contains("prompt_tokens=120"))
	assert_true(line.contains("thought_tokens=30"))
	assert_true(line.contains("output_tokens=40"))
	assert_true(line.contains("finish=STOP"))
	assert_true(line.contains("retry=none"))
	assert_false(line.contains(secret))


func test_usage_and_turn_counters() -> void:
	var body := JSON.stringify({
		"usageMetadata": {
			"promptTokenCount": 11,
			"thoughtsTokenCount": 4,
			"candidatesTokenCount": 7,
		},
		"candidates": [{"finishReason": "STOP"}],
	})
	var usage := LlmTiming.usage_from_body(body)
	assert_eq(usage["prompt_tokens"], 11)
	assert_eq(usage["thought_tokens"], 4)
	assert_eq(usage["output_tokens"], 7)
	assert_eq(usage["finish"], "STOP")
	var tally := LlmTiming.empty_tally()
	LlmTiming.note_request(tally, "summary", "summary")
	LlmTiming.note_request(tally, "reply", "reply")
	LlmTiming.note_request(tally, "regen", "validation")
	assert_eq(tally["requests"], 3)
	assert_eq(tally["summary"], 1)
	assert_eq(tally["regen"], 1)
	var turn := LlmTiming.turn_line(1300, "gemini-3.5-flash-lite", tally)
	assert_true(turn.begins_with("llm timing ask_to_text_ms=1300"))
	assert_true(turn.contains("model=gemini-3.5-flash-lite"))
	assert_true(turn.contains("requests=3"))
	assert_true(turn.contains("summary=1"))
	assert_true(turn.contains("regen=1"))
	assert_true(turn.contains("reasons=validation"))
	assert_eq(LlmTiming.screen_line(1300, 1, "gemini-3.5-flash-lite"), "ход 1,3 с · 1 запр. · gemini-3.5-flash-lite")
	assert_eq(LlmTiming.median_int([100, 400, 200]), 200)
	assert_true(SettingsStore.new().timing_debug)
	assert_eq(LLMConfig.DEFAULT_DIALOGUE_MODEL, "gemini-3.5-flash-lite")
	assert_eq(LLMConfig.DIALOGUE_MODELS.size(), 3)
	var blank := LLMConfig.from_sources("", "", "", false)
	assert_eq(blank.thinking_level, "MINIMAL")
	assert_true(blank.summary_after_reply)
	assert_true(blank.local_fixes)
	assert_true(absf(SpendMeter.cost_usd("gemini-3.5-flash-lite", 1000000, 0, 0) - 0.30) < 0.000001)
	assert_true(absf(SpendMeter.cost_usd("gemini-3.5-flash-lite", 0, 1000000, 0) - 2.50) < 0.000001)
	assert_true(absf(SpendMeter.cost_usd("gemini-3.1-flash-lite", 1000000, 0, 1000000) - 1.75) < 0.000001)
	var flash_input := 0.75 if int(Time.get_date_dict_from_system()["year"]) < 2027 else 1.50
	assert_true(absf(SpendMeter.cost_usd("gemini-3.6-flash", 1000000, 0, 0) - flash_input) < 0.000001)
	assert_eq(SpendMeter.cost_usd("dialogue-model", 1000000, 0, 0), 0.0)
	var previous_spend_path := SpendMeter.store_path
	var spend_path := "user://spend-meter-test.cfg"
	if FileAccess.file_exists(spend_path):
		DirAccess.remove_absolute(spend_path)
	SpendMeter.store_path = spend_path
	var before_session := SpendMeter.session_usd
	SpendMeter.note("gemini-3.5-flash-lite", 1000000, 0, 0)
	assert_true(absf(SpendMeter.session_usd - before_session - 0.30) < 0.000001)
	assert_true(absf(SpendMeter.total_usd() - 0.30) < 0.000001)
	SpendMeter.session_usd = before_session
	DirAccess.remove_absolute(spend_path)
	SpendMeter.store_path = previous_spend_path
	assert_true(load("res://tests/manual/turn_benchmark.gd") != null)
	_assert_flash_model_migrates()


func _assert_flash_model_migrates() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var file := ConfigFile.new()
	file.parse(previous)
	file.set_value("llm", "dialogue_model", "gemini-3.5-flash")
	file.set_value("llm", "api_key", "migrate-key")
	file.set_value("llm", "settings_version", 1)
	file.save(path)
	var loaded := SettingsStore.load_current()
	assert_eq(loaded.dialogue_model, "gemini-3.5-flash-lite")
	assert_eq(loaded.api_key, "migrate-key")
	var check := ConfigFile.new()
	assert_eq(check.load(path), OK)
	assert_eq(int(check.get_value("llm", "settings_version", 0)), LLMConfig.SETTINGS_VERSION)
	assert_false(bool(check.get_value("voice", "enabled", true)))
	assert_eq(str(check.get_value("voice", "engine", "")), "system")
	assert_true(bool(check.get_value("voice", "intonation", false)))
	assert_eq(str(check.get_value("llm", "dialogue_model", "")), "gemini-3.5-flash-lite")
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()
