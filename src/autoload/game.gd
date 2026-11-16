extends Node
## Сессия партии: ход, сигналы для UI, блокнот. Экранов здесь нет.

signal agent_replied(agent_id: String, text: String, remark: String)
signal events(list: Array)
signal llm_error(kind: String, message: String)
signal busy_changed(is_busy: bool)

var case_data: CaseData = null
var state: GameState = null
var notebook: Notebook = null

var _engine: RulesEngine = null
var _dialogues: Dictionary = {}
var _leak_max_stems: int = 1
var _log_leaks: bool = true
var last_mentioned_evidence: Array[String] = []
var last_requested_evidence: String = ""


func open_case(path: String) -> CaseLoader.Result:
	var loaded := CaseLoader.load_case(path)
	if not loaded.ok:
		case_data = null
		state = null
		notebook = null
		_engine = null
		_dialogues = {}
		return loaded
	case_data = loaded.case_data
	state = GameState.new()
	_engine = RulesEngine.new(case_data, state)
	_engine.start_new()
	_dialogues = {}
	for agent in case_data.agents:
		_dialogues[agent.id] = DialogueState.new()
		state.dialogues[agent.id] = (_dialogues[agent.id] as DialogueState).to_dict()
	notebook = Notebook.new(case_data, state)
	var config := LLMConfig.load_settings()
	_leak_max_stems = 1
	_log_leaks = true
	if config != null:
		pass
	return loaded


func mentioned_evidence(text: String) -> Array[String]:
	if case_data == null or state == null:
		return []
	var open: Array = []
	for evidence in case_data.evidence:
		if state.unlocked_evidence.has(evidence.id):
			open.append(evidence)
	return EvidenceMatcher.find_mentioned(text, open)


func ask(agent_id: String, player_text: String) -> void:
	await _turn(agent_id, player_text, "", "")


func present(agent_id: String, evidence_id: String, player_text: String = "") -> void:
	var question := player_text.strip_edges()
	if question == "":
		question = "Что скажете?"
	var note := ""
	if case_data != null and case_data.evidence_by_id.has(evidence_id):
		var evidence: CaseData.EvidenceItem = case_data.evidence_by_id[evidence_id]
		note = "Следователь предъявляет улику «%s»: %s" % [evidence.title, evidence.full_text]
	await _turn(agent_id, question, note, evidence_id)


func mark_contradiction(a: Dictionary, b: Dictionary) -> Dictionary:
	if _engine == null:
		return {"ok": false}
	return _engine.try_manual_contradiction(a, b)


func accuse(killer_id: String, motive_id: String, method_id: String) -> Dictionary:
	if _engine == null:
		return {"killer_ok": false, "motive_ok": false, "method_ok": false, "solved": false}
	return _engine.check_accusation(killer_id, motive_id, method_id)


func _turn(agent_id: String, player_text: String, event_note: String, evidence_id: String) -> void:
	if _engine == null or not _dialogues.has(agent_id):
		llm_error.emit("no_case", "Дело не открыто.")
		return
	busy_changed.emit(true)
	last_mentioned_evidence = []
	last_requested_evidence = ""
	_sync_dialogues()
	var snapshot := state.to_dict()
	var turn_events: Array = []
	if evidence_id != "":
		turn_events.append_array(_engine.present_evidence(agent_id, evidence_id))
	turn_events.append_array(_engine.note_question(agent_id))
	var dialogue: DialogueState = _dialogues[agent_id]
	if dialogue.needs_summary():
		await _refresh_summary(agent_id, dialogue)
	var packet: Array = _engine.get_packet(agent_id)
	var request := PromptBuilder.build_turn(case_data, state, agent_id, packet, dialogue, player_text, event_note)
	var result := await _generate(request)
	if _is_network_error(result):
		_restore(snapshot)
		llm_error.emit(str(result.get("error", "")), str(result.get("message", "")))
		busy_changed.emit(false)
		return
	if str(result.get("error", "")) == "blocked":
		result = await _generate(_with_suffix(request, "Отвечай сдержаннее, без откровенных подробностей."))
		if _is_network_error(result):
			_restore(snapshot)
			llm_error.emit(str(result.get("error", "")), str(result.get("message", "")))
			busy_changed.emit(false)
			return
	var agent: CaseData.Agent = case_data.agent_by_id[agent_id]
	var report := _validate_result(result, packet, agent_id, dialogue, player_text)
	if not report["ok"]:
		var retry := _with_suffix(request, ResponseValidator.repair_note(report["violations"]))
		result = await _generate(retry)
		if _is_network_error(result):
			_restore(snapshot)
			llm_error.emit(str(result.get("error", "")), str(result.get("message", "")))
			busy_changed.emit(false)
			return
		report = _validate_result(result, packet, agent_id, dialogue, player_text)
	var reply := ""
	var remark := ""
	var tone := 0
	var emotion := str(state.emotion.get(agent_id, agent.starting_emotion))
	var statements: Array = []
	if report["ok"] and result.get("ok", false):
		reply = str(report["reply"])
		remark = str(report["remark"])
		tone = int(report["tone"])
		emotion = str(report["emotion"])
		statements = report["statements"]
		for item in report["mentioned_evidence"]:
			last_mentioned_evidence.append(str(item))
		last_requested_evidence = str(report.get("requested_evidence", ""))
	else:
		reply = ResponseValidator.fallback_reply(int(state.pressure.get(agent_id, 0)))
		remark = "молчит"
		tone = 0
		emotion = str(state.emotion.get(agent_id, agent.starting_emotion))
	state.turn += 1
	if not statements.is_empty():
		turn_events.append_array(_engine.register_statements(agent_id, statements))
	turn_events.append_array(_engine.apply_tone(agent_id, tone))
	if Balance.emotion_allowed(emotion):
		_engine.set_emotion(agent_id, emotion)
	dialogue.append_message("player", player_text, state.turn)
	dialogue.append_message("agent", reply, state.turn, remark)
	_sync_dialogues()
	agent_replied.emit(agent_id, reply, remark)
	events.emit(turn_events)
	busy_changed.emit(false)


func _refresh_summary(agent_id: String, dialogue: DialogueState) -> void:
	var agent: CaseData.Agent = case_data.agent_by_id[agent_id]
	var fold_until := dialogue.messages.size() - 6
	var folded: Array = dialogue.messages.slice(dialogue.summarized_count, fold_until)
	var request := Summarizer.build_request(agent.name, dialogue.summary, folded)
	var result := await _generate(request)
	if not result.get("ok", false) or result.get("json") is not Dictionary:
		return
	var summary := str((result["json"] as Dictionary).get("summary", "")).strip_edges()
	if summary == "":
		return
	dialogue.summary = summary
	dialogue.summarized_count = fold_until


func _validate_result(result: Dictionary, packet: Array, agent_id: String, dialogue: DialogueState, player_text: String) -> Dictionary:
	if not result.get("ok", false):
		return {"ok": false, "violations": PackedStringArray(["ответ модели не получен"]), "statements": []}
	return ResponseValidator.validate(result.get("json", {}), packet, {
		"case_data": case_data,
		"state": state,
		"agent_id": agent_id,
		"dialogue": dialogue,
		"player_text": player_text,
		"previous_emotion": str(state.emotion.get(agent_id, "neutral")),
		"leak_max_stems": _leak_max_stems,
		"log_leaks": _log_leaks,
		"evidence_keys": PromptBuilder.evidence_keys(case_data, state),
	})


func _generate(request: Dictionary) -> Dictionary:
	if LLM.client == null:
		return {"ok": false, "json": {}, "raw_text": "", "error": "offline", "retry_after_s": 0.0, "message": "Клиент модели не создан."}
	var pending: Variant = LLM.client.call("generate", request)
	if pending is Dictionary:
		return pending
	return await pending


func _with_suffix(request: Dictionary, suffix: String) -> Dictionary:
	var copy := request.duplicate(true)
	copy["user"] = str(copy.get("user", "")) + "\n" + suffix
	return copy


func _is_network_error(result: Dictionary) -> bool:
	if result.get("ok", false):
		return false
	var code := str(result.get("error", ""))
	return code == "offline" or code == "timeout" or code == "rate_limited" or code == "auth" or code == "server"


func _sync_dialogues() -> void:
	if state == null:
		return
	for agent_id in _dialogues:
		state.dialogues[agent_id] = (_dialogues[agent_id] as DialogueState).to_dict()


func _restore(snapshot: Dictionary) -> void:
	var fresh := GameState.from_dict(snapshot)
	state.pressure = fresh.pressure
	state.emotion = fresh.emotion
	state.fatigue = fresh.fatigue
	state.unlocked_evidence = fresh.unlocked_evidence
	state.shown = fresh.shown
	state.broken_lies = fresh.broken_lies
	state.fact_levels = fresh.fact_levels
	state.heard = fresh.heard
	state.contradictions = fresh.contradictions
	state.talked_to = fresh.talked_to
	state.accusation = fresh.accusation
	state.dialogues = fresh.dialogues
	state.turn = fresh.turn
	state.case_id = fresh.case_id
	state.case_version_hash = fresh.case_version_hash
	for agent_id in _dialogues.keys():
		var saved: Variant = fresh.dialogues.get(agent_id, {})
		if saved is Dictionary:
			_dialogues[agent_id] = DialogueState.from_dict(saved)
