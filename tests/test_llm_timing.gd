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
