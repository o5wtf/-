extends TestCase

const FIXTURE := "res://tests/fixtures/turn_flow.json"


func test_question_records_lie_then_truth_unlocks_evidence() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var mock := _use_mock()
	mock.enqueue(_reply("k1", "lie", "Я держусь своей версии."))
	await Game.ask("a", "Где вы были?")
	assert_true(_heard("a", "fa", "lie"))
	assert_false(Game.state.contradictions.has("c1"))
	assert_false(Game.state.unlocked_evidence.has("ev"))
	var notebook_text := ""
	for row in Game.notebook.entries():
		if str(row["fact_id"]) == "fa":
			notebook_text = str(row["text"])
	assert_eq(notebook_text, "Меня там не было.")
	assert_false(notebook_text.contains("допоздна"))
	mock.enqueue(_reply("k1", "basic", "Я это уже говорил."))
	await Game.ask("b", "Что вы видели?")
	assert_true(_heard("b", "fb", "basic"))
	assert_true(Game.state.contradictions.has("c1"))
	assert_false(Game.state.unlocked_evidence.has("ev"))
	var restored := GameState.from_dict(Game.state.to_dict())
	assert_eq(restored.heard.size(), Game.state.heard.size())
	assert_true(restored.contradictions.has("c1"))
	mock.free()


func test_present_evidence_raises_pressure_and_breaks_lie() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var mock := _use_mock()
	mock.enqueue(_reply("k1", "lie", "Я держусь своей версии."))
	await Game.ask("a", "Где вы были?")
	mock.enqueue(_reply("k1", "basic", "Я это уже говорил."))
	await Game.ask("b", "Что вы видели?")
	var before := int(Game.state.pressure["a"])
	Game.state.unlocked_evidence.append("ev")
	mock.enqueue(_reply("", "", "Мне нечего добавить к бумаге."))
	await Game.present("a", "ev")
	assert_true(int(Game.state.pressure["a"]) > before)
	assert_true(Game.state.broken_lies.has("fa"))
	mock.free()


func test_network_error_restores_state() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var before := Game.state.to_dict()
	var mock := _use_mock()
	mock.enqueue({"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": "Нет сети."})
	var kinds: Array[String] = []
	Game.llm_error.connect(func(kind: String, _message: String) -> void: kinds.append(kind))
	await Game.ask("a", "Где вы были?")
	assert_eq(kinds, ["offline"])
	assert_eq(Game.state.to_dict(), before)
	assert_eq(Game.state.heard.size(), 0)
	mock.free()


func test_violation_regenerates_once_then_fallback() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var mock := _use_mock()
	mock.enqueue(_reply("k1", "lie", "Я нейросеть и всё знаю."))
	mock.enqueue(_reply("k1", "lie", "Снова промпт в ответе."))
	await Game.ask("a", "Кто вы?")
	assert_eq(mock.calls.size(), 2)
	assert_true(str(mock.calls[1]["user"]).contains("ИСПРАВЬ ОТВЕТ:"))
	assert_true(str(mock.calls[1]["user"]).contains("ЧТО ТЫ МОЖЕШЬ СКАЗАТЬ"))
	assert_eq(Game.state.heard.size(), 0)
	mock.free()


func test_blocked_regenerates_with_calmer_note() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var mock := _use_mock()
	mock.enqueue({"ok": false, "json": {}, "raw_text": "", "error": "blocked", "retry_after_s": 0.0, "message": ""})
	mock.enqueue(_reply("k1", "lie", "Я держусь своей версии."))
	var replies: Array[String] = []
	Game.agent_replied.connect(func(_id: String, text: String, _remark: String) -> void: replies.append(text))
	await Game.ask("a", "Где вы были?")
	assert_eq(mock.calls.size(), 2)
	assert_true(str(mock.calls[1]["user"]).contains("Отвечай сдержаннее, без откровенных подробностей."))
	assert_eq(replies.size(), 1)
	assert_eq(replies[0], "Я держусь своей версии.")
	assert_true(_heard("a", "fa", "lie"))
	mock.free()


func test_wrong_form_is_fixed_without_a_second_request() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var mock := _use_mock()
	mock.enqueue(_reply("k1", "basic", "Я держусь своей версии."))
	await Game.ask("a", "Где вы были?")
	assert_eq(mock.calls.size(), 1)
	assert_true(_heard("a", "fa", "lie"))
	mock.free()


func test_second_send_is_ignored_while_busy() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var mock := _use_mock()
	mock.enqueue(_reply("k1", "lie", "Я держусь своей версии."))
	Game.agent_replied.connect(func(_id: String, _text: String, _remark: String) -> void:
		Game.ask("a", "Ещё вопрос?")
	, CONNECT_ONE_SHOT)
	await Game.ask("a", "Где вы были?")
	assert_eq(mock.calls.size(), 1)
	assert_false(Game.is_busy)
	mock.free()


func test_summary_runs_after_the_reply_and_falls_back() -> void:
	assert_true(_boot(), "фикстура хода не открылась")
	var dialogue: DialogueState = Game._dialogues["a"]
	for index in 10:
		dialogue.append_message("player" if index % 2 == 0 else "agent", "реплика", 1)
	var mock := _use_mock()
	mock.enqueue(_reply("k1", "lie", "Я держусь своей версии."))
	mock.enqueue({"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": ""})
	var replies: Array[String] = []
	Game.agent_replied.connect(func(_id: String, text: String, _remark: String) -> void:
		replies.append(text)
		assert_eq(mock.calls.size(), 1)
	, CONNECT_ONE_SHOT)
	await Game.ask("a", "Где вы были?")
	assert_eq(replies.size(), 1)
	assert_eq(mock.calls.size(), 2)
	assert_eq(str(mock.calls[0].get("model_role", "")), "dialogue")
	assert_eq(str(mock.calls[1].get("model_role", "")), "summary")
	var live: DialogueState = Game._dialogues["a"]
	assert_eq(live.messages.size(), 12)
	assert_eq(live.summarized_count, 6)
	assert_false(live.needs_summary())
	assert_true(live.summary.contains("Меня там не было."))
	assert_true(_heard("a", "fa", "lie"))
	mock.free()


func _boot() -> bool:
	var loaded := Game.open_case(FIXTURE)
	return loaded.ok


func _use_mock() -> MockLLMClient:
	var mock := MockLLMClient.new()
	LLM.add_child(mock)
	LLM.client = mock
	return mock


func _reply(key: String, form: String, text: String) -> Dictionary:
	var stated: Array = []
	if key != "":
		stated.append({"key": key, "form": form})
	return {
		"ok": true,
		"json": {
			"player_tone": 0,
			"reply": text,
			"remark": "кивает",
			"emotion": "neutral",
			"stated": stated,
			"mentioned_evidence": [],
			"requested_evidence": null,
		},
		"raw_text": "",
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
	}


func _heard(agent_id: String, fact_id: String, form: String) -> bool:
	for row in Game.state.heard:
		if str(row["agent_id"]) == agent_id and str(row["fact_id"]) == fact_id and str(row["form"]) == form:
			return true
	return false
