extends Node
## Сессия партии: ход, сигналы для UI, блокнот. Экранов здесь нет.

signal agent_replied(agent_id: String, text: String, remark: String)
signal reply_preview(agent_id: String, text: String)
signal events(list: Array)
signal llm_error(kind: String, message: String)
signal busy_changed(is_busy: bool)

var case_data: CaseData = null
var state: GameState = null
var notebook: Notebook = null
var case_path: String = ""

var _engine: RulesEngine = null
var _dialogues: Dictionary = {}
var _leak_max_stems: int = 1
var _log_leaks: bool = true
var last_mentioned_evidence: Array[String] = []
var last_requested_evidence: String = ""
var _stream_agent: String = ""
var _stream_emotion: String = "neutral"
var _stream_reply: String = ""
var _voiced_len: int = 0
var _send_ms: int = 0
var _voice_stream: bool = false
var _speculating: bool = false
var _spec_epoch: int = 0
var _spec_agent: String = ""
var _spec_candidate: String = ""
var _spec_norm: String = ""
var _spec_stamp: int = 0
var _spec_started: bool = false
var _spec_pending: bool = false
var _spec_arming: bool = false
var _spec_result: Dictionary = {}


func open_case(path: String) -> CaseLoader.Result:
	var loaded := CaseLoader.load_case(path)
	if not loaded.ok:
		case_data = null
		state = null
		notebook = null
		case_path = ""
		_engine = null
		_dialogues = {}
		return loaded
	case_data = loaded.case_data
	case_path = path
	state = GameState.new()
	state.case_id = case_data.id
	state.case_version_hash = SaveState.file_hash(path)
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


func begin_hearing(agent_id: String) -> void:
	_spec_epoch += 1
	_spec_agent = agent_id
	_spec_candidate = ""
	_spec_norm = ""
	_spec_stamp = 0
	_spec_started = false
	_spec_result = {}
	_spec_arming = false


func note_hearing(agent_id: String, text: String) -> void:
	if _engine == null or agent_id == "" or not Speculation.usable(text):
		return
	_spec_agent = agent_id
	_spec_candidate = text.strip_edges()
	_spec_stamp = Time.get_ticks_msec()
	if _spec_arming or _spec_started:
		return
	_spec_arming = true
	_arm_speculation()


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
	var report := _engine.try_manual_contradiction(a, b)
	_autosave()
	return report


func accuse(killer_id: String, motive_id: String, method_id: String) -> Dictionary:
	if _engine == null:
		return {"killer_ok": false, "motive_ok": false, "method_ok": false, "solved": false}
	var report := _engine.check_accusation(killer_id, motive_id, method_id)
	_autosave()
	return report


func continue_case(path: String) -> Dictionary:
	var case_id := SaveState.case_id_from_path(path)
	if case_id == "":
		return {"ok": false, "reason": "case"}
	var saved := SaveState.read(case_id)
	if not saved.ok:
		return saved
	var current_hash := SaveState.file_hash(path)
	if str(saved.get("hash", "")) != current_hash or str(saved.get("case_id", "")) != case_id:
		return {"ok": false, "reason": "hash"}
	var loaded := open_case(path)
	if not loaded.ok:
		return {"ok": false, "reason": "case"}
	_replace_state(saved.get("state", {}))
	return {"ok": true, "reason": ""}


func _turn(agent_id: String, player_text: String, event_note: String, evidence_id: String) -> void:
	if _engine == null or not _dialogues.has(agent_id):
		llm_error.emit("no_case", "Дело не открыто.")
		return
	busy_changed.emit(true)
	Voice.prepare_speech()
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
	var kept := _spec_matches(agent_id, player_text)
	if not kept:
		_drop_speculation()
	_begin_stream(agent_id, str(state.emotion.get(agent_id, agent_emotion(agent_id))))
	_voice_stream = not kept
	var result: Dictionary = await _take_speculation() if kept else await _generate(request)
	if kept and not result.get("ok", false):
		_voice_stream = true
		result = await _generate(request)
	TurnTiming.span("send_to_reply", _send_ms)
	_drop_speculation()
	if _is_network_error(result):
		_abort_stream()
		_restore(snapshot)
		llm_error.emit(str(result.get("error", "")), str(result.get("message", "")))
		busy_changed.emit(false)
		return
	if str(result.get("error", "")) == "blocked":
		result = await _generate(_with_suffix(request, "Отвечай сдержаннее, без откровенных подробностей."))
		if _is_network_error(result):
			_abort_stream()
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
			_abort_stream()
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
	_autosave()
	_speak_unsaid(agent, reply, remark, emotion)
	_stream_agent = ""
	agent_replied.emit(agent_id, reply, remark)
	events.emit(turn_events)
	busy_changed.emit(false)


func _autosave() -> void:
	if state == null:
		return
	SaveState.write_state(state)


func _replace_state(data: Variant) -> void:
	if data is not Dictionary:
		return
	state = GameState.from_dict(data)
	state.case_id = case_data.id
	state.case_version_hash = SaveState.file_hash(case_path)
	_engine = RulesEngine.new(case_data, state)
	_dialogues = {}
	for agent in case_data.agents:
		var saved: Variant = state.dialogues.get(agent.id, {})
		if saved is Dictionary:
			_dialogues[agent.id] = DialogueState.from_dict(saved)
		else:
			_dialogues[agent.id] = DialogueState.new()
		state.dialogues[agent.id] = (_dialogues[agent.id] as DialogueState).to_dict()
	notebook = Notebook.new(case_data, state)


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


func agent_emotion(agent_id: String) -> String:
	if state == null or case_data == null:
		return "neutral"
	var agent: CaseData.Agent = case_data.agent_by_id.get(agent_id) as CaseData.Agent
	var fallback := agent.starting_emotion if agent != null else "neutral"
	return str(state.emotion.get(agent_id, fallback))


func _begin_stream(agent_id: String, emotion: String) -> void:
	_stream_agent = agent_id
	_stream_emotion = emotion
	_stream_reply = ""
	_voiced_len = 0
	_voice_stream = true
	_send_ms = Time.get_ticks_msec()
	if LLM.client != null and LLM.client.has_signal("reply_text") and not LLM.client.reply_text.is_connected(_on_reply_text):
		LLM.client.reply_text.connect(_on_reply_text)


func _on_reply_text(text: String) -> void:
	if not _voice_stream or _speculating or _stream_agent == "" or text == _stream_reply:
		return
	if _stream_reply == "":
		TurnTiming.span("send_to_first_token", _send_ms)
	_stream_reply = text
	reply_preview.emit(_stream_agent, text)
	if text.length() < _voiced_len:
		return
	var fresh := text.substr(_voiced_len)
	var taken := GeminiClient.take_sentences(fresh)
	var ready: PackedStringArray = taken["ready"]
	for sentence in ready:
		_queue_speech(sentence, _stream_emotion, "")
	_voiced_len += fresh.length() - str(taken.get("rest", "")).length()


func _abort_stream() -> void:
	if _voiced_len > 0:
		Voice.stop_speaking()
	_stream_agent = ""
	_voiced_len = 0


func _speak_unsaid(agent: CaseData.Agent, reply: String, remark: String, emotion: String) -> void:
	var aligned := _voiced_len > 0 and _stream_reply != "" and reply.begins_with(_stream_reply.substr(0, mini(_voiced_len, _stream_reply.length())))
	if _voiced_len > 0 and not aligned:
		Voice.stop_speaking()
		_voiced_len = 0
	var tail := reply.substr(_voiced_len).strip_edges() if _voiced_len > 0 and aligned else reply
	if tail != "":
		_queue_speech(tail, emotion, remark)
	_voiced_len = reply.length()


func _queue_speech(text: String, emotion: String, remark: String) -> void:
	if _stream_agent == "" or text.strip_edges() == "":
		return
	var agent: CaseData.Agent = case_data.agent_by_id.get(_stream_agent) as CaseData.Agent
	if agent == null:
		return
	Voice.speak_agent(agent, text, remark, emotion)


func _arm_speculation() -> void:
	var epoch := _spec_epoch
	await get_tree().create_timer(float(Speculation.DEBOUNCE_MS) / 1000.0).timeout
	if epoch != _spec_epoch:
		_spec_arming = false
		return
	var stable := Time.get_ticks_msec() - _spec_stamp
	if not Speculation.should_launch(_spec_candidate, _spec_started, _spec_pending, stable):
		if not _spec_started and stable < Speculation.DEBOUNCE_MS:
			_arm_speculation()
			return
		_spec_arming = false
		return
	_spec_arming = false
	_spec_started = true
	_launch_speculation(epoch)


func _launch_speculation(epoch: int) -> void:
	if _engine == null or not _dialogues.has(_spec_agent):
		return
	_spec_pending = true
	_speculating = true
	_spec_norm = Speculation.normalize(_spec_candidate)
	var dialogue: DialogueState = _dialogues[_spec_agent]
	var packet: Array = _engine.get_packet(_spec_agent)
	var request := PromptBuilder.build_turn(case_data, state, _spec_agent, packet, dialogue, _spec_candidate, "")
	var result: Dictionary = await _generate(request)
	_speculating = false
	_spec_pending = false
	if epoch != _spec_epoch:
		return
	_spec_result = result


func _spec_matches(agent_id: String, player_text: String) -> bool:
	if _spec_agent != agent_id:
		return false
	var heard := _spec_norm if _spec_norm != "" else _spec_candidate
	if not Speculation.same_input(player_text, heard):
		return false
	return _spec_pending or not _spec_result.is_empty()


func _take_speculation() -> Dictionary:
	var epoch := _spec_epoch
	while _spec_pending and epoch == _spec_epoch:
		await get_tree().process_frame
	if epoch != _spec_epoch:
		return {}
	return _spec_result


func _drop_speculation() -> void:
	_spec_epoch += 1
	_spec_started = true
	_spec_arming = false
	_spec_result = {}
	_spec_norm = ""


func _generate(request: Dictionary) -> Dictionary:
	if _voiced_len > 0:
		Voice.stop_speaking()
		_voiced_len = 0
		_stream_reply = ""
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
	return code == "offline" or code == "timeout" or code == "rate_limited" or code == "auth" or code == "server" or code == "unavailable" or code == "overloaded" or code == "rejected"


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
