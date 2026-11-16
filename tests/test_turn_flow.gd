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
	assert_true(Game.state.unlocked_evidence.has("ev"))
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
	assert_eq(int(Game.state.fatigue.get("a", 0)), 0)
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
