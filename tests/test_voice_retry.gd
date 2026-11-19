extends TestCase


func test_retry_stays_with_its_character_until_a_new_line_or_turn() -> void:
	assert_true(Game.open_case("res://tests/fixtures/turn_flow.json").ok)
	Speaker.dismiss_retry()
	Speaker.retry_line = {
		"id": "case:a:1",
		"agent_id": "a",
		"text": "Первая реплика.",
		"voice_hint": "Kore",
		"style": "",
	}
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var button := screen.find_child("VoiceRetryButton", true, false) as Button
	screen.open_agent("a")
	assert_true(button.visible)
	screen.open_agent("b")
	assert_false(button.visible)
	screen.open_agent("a")
	assert_true(button.visible)
	Speaker._on_started("case:a:2")
	assert_true(Speaker.retry_line.is_empty())
	assert_false(button.visible)
	Speaker.retry_line = {
		"id": "case:a:1",
		"agent_id": "a",
		"text": "Первая реплика.",
		"voice_hint": "Kore",
		"style": "",
	}
	screen.open_agent("a")
	assert_true(button.visible)
	var was := Speaker.enabled
	Speaker.enabled = false
	var loaded := Game.open_case("res://tests/fixtures/turn_flow.json")
	assert_true(loaded.ok)
	var mock := MockLLMClient.new()
	LLM.add_child(mock)
	LLM.client = mock
	mock.enqueue({
		"ok": true,
		"json": {
			"player_tone": 0,
			"reply": "Я был дома.",
			"remark": "",
			"emotion": "neutral",
			"stated": [],
			"mentioned_evidence": [],
			"requested_evidence": null,
		},
		"raw_text": "",
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
	})
	await Game.ask("a", "Где вы были?")
	assert_true(Speaker.retry_line.is_empty())
	assert_false(button.visible)
	Speaker.enabled = was
	mock.free()
	screen.free()
	Speaker.stop_and_clear()


func test_switching_suspect_cancels_playback() -> void:
	assert_true(Game.open_case("res://tests/fixtures/turn_flow.json").ok)
	var previous: Node = Speaker.backend
	var spy := _Spy.new()
	Speaker.backend = spy
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/interrogation.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	screen.open_agent("a")
	screen.open_agent("b")
	assert_true(spy.stops >= 1)
	Speaker._inflight = {"id": "case:a:1", "text": "Реплика.", "voice_hint": "Kore", "style": ""}
	Speaker.skip_current()
	assert_true(spy.stops >= 2)
	Speaker.backend = previous
	spy.free()
	screen.free()
	Speaker.dismiss_retry()
	Speaker._inflight = {}


class _Spy:
	extends SpeechBackend

	var stops: int = 0

	func speak(_line_id: String, _text: String, _voice_hint: String = "", _style: String = "") -> void:
		pass

	func stop() -> void:
		stops += 1
