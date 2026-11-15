extends TestCase


func test_recent_is_last_six_messages() -> void:
	var dialogue := DialogueState.new()
	for index in 8:
		dialogue.append_message("player" if index % 2 == 0 else "agent", "реплика %d" % index, index)
	var recent := dialogue.recent()
	assert_eq(recent.size(), 6)
	assert_eq(int(recent[0]["turn"]), 2)
	assert_eq(int(recent[5]["turn"]), 7)
	assert_eq(dialogue.recent(2).size(), 2)
	var short := DialogueState.new()
	short.append_message("player", "один", 1)
	assert_eq(short.recent().size(), 1)


func test_needs_summary_uses_six_outside_the_window() -> void:
	var dialogue := DialogueState.new()
	assert_false(dialogue.needs_summary())
	_fill(dialogue, 6)
	assert_false(dialogue.needs_summary())
	_fill(dialogue, 5)
	assert_eq(dialogue.messages.size(), 11)
	assert_false(dialogue.needs_summary())
	_fill(dialogue, 1)
	assert_eq(dialogue.messages.size(), 12)
	assert_true(dialogue.needs_summary())
	dialogue.summarized_count = 6
	assert_false(dialogue.needs_summary())
	_fill(dialogue, 5)
	assert_eq(dialogue.messages.size(), 17)
	assert_false(dialogue.needs_summary())
	_fill(dialogue, 1)
	assert_eq(dialogue.messages.size(), 18)
	assert_true(dialogue.needs_summary())


func test_fallback_summary_does_not_call_a_model() -> void:
	var dialogue := DialogueState.new()
	dialogue.summary = "Старое резюме допроса."
	_fill(dialogue, 12)
	var heard: Array[Dictionary] = [
		{"turn": 0, "text": "Сказал, что был дома."},
		{"turn": 3, "text": "Признал, что видел свет."},
		{"turn": 11, "text": "Эта реплика ещё в окне и не должна попасть в резюме."},
	]
	assert_true(dialogue.needs_summary())
	Summarizer.apply_fallback(dialogue, "Анна", heard)
	assert_false(dialogue.needs_summary())
	assert_eq(dialogue.summarized_count, 6)
	assert_true(dialogue.summary.contains("Старое резюме допроса."))
	assert_true(dialogue.summary.contains("Анна сказал(а): Сказал, что был дома."))
	assert_true(dialogue.summary.contains("Анна сказал(а): Признал, что видел свет."))
	assert_false(dialogue.summary.contains("ещё в окне"))
	var request := Summarizer.build_request("Анна", "Старое резюме допроса.", dialogue.recent())
	assert_eq(request["model_role"], "summary")
	assert_eq(request["temperature"], 0.2)
	assert_true(str(request["system"]).contains("Сожми разговор в краткое резюме"))
	assert_true(str(request["user"]).contains("ПРЕДЫДУЩЕЕ РЕЗЮМЕ: Старое резюме допроса."))
	assert_true(str(request["user"]).contains("НОВЫЕ РЕПЛИКИ:"))
	assert_true(str(request["user"]).contains("Следователь:"))
	var schema: Dictionary = request["schema"]
	assert_eq(schema["required"], ["summary"])


func _fill(dialogue: DialogueState, count: int) -> void:
	var start := dialogue.messages.size()
	for index in count:
		var turn := start + index
		var role := "player" if index % 2 == 0 else "agent"
		dialogue.append_message(role, "реплика %d" % turn, turn)
