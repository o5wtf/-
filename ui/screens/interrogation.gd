extends Control

signal evidence_requested
signal notebook_requested
signal contradiction_requested
signal suspects_requested

var agent_id: String = ""

var _header: Label
var _feed_box: VBoxContainer
var _scroll: ScrollContainer
var _prompt: ChatInput
var _hint: HBoxContainer
var _hint_label: Label
var _thinking: Label
var _timing: Label
var _voice_error: Label
var _voice_retry: Button
var _error: Label
var _retry: Button
var _busy: bool = false
var _hint_id: String = ""
var _dismissed: String = ""
var _last: Dictionary = {}
var _feeds: Dictionary = {}


func _ready() -> void:
	UiWidgets.fill(self)
	var column := VBoxContainer.new()
	UiWidgets.fill(column)
	add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var back := UiWidgets.button("←", "BackButton")
	back.pressed.connect(func() -> void: suspects_requested.emit())
	top.add_child(back)
	_header = UiWidgets.label("", "HeaderLabel")
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_feed_box = VBoxContainer.new()
	_feed_box.name = "Feed"
	_feed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll = UiWidgets.scrolling(_feed_box)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_thinking = UiWidgets.label("", "ThinkingLabel")
	_thinking.add_theme_color_override("font_color", NoirTheme.GOLD)
	_thinking.visible = false
	column.add_child(_thinking)
	_timing = UiWidgets.label("", "TurnTimingLabel")
	_timing.add_theme_color_override("font_color", NoirTheme.MUTED)
	_timing.visible = false
	column.add_child(_timing)
	_voice_error = UiWidgets.label("", "VoiceErrorLabel")
	_voice_error.add_theme_color_override("font_color", NoirTheme.GOLD)
	_voice_error.visible = false
	column.add_child(_voice_error)
	_voice_retry = UiWidgets.button(UiStrings.VOICE_RETRY, "VoiceRetryButton")
	_voice_retry.visible = false
	_voice_retry.pressed.connect(func() -> void: Speaker.retry_failed())
	column.add_child(_voice_retry)
	_error = UiWidgets.label("", "ErrorLabel")
	_error.add_theme_color_override("font_color", NoirTheme.GOLD)
	_error.visible = false
	column.add_child(_error)
	_retry = UiWidgets.button(UiStrings.RETRY, "RetryButton")
	_retry.visible = false
	_retry.pressed.connect(_retry_last)
	column.add_child(_retry)
	_hint = HBoxContainer.new()
	_hint.name = "HintBar"
	_hint.visible = false
	column.add_child(_hint)
	_hint_label = UiWidgets.label("", "HintLabel")
	_hint.add_child(_hint_label)
	var yes := UiWidgets.button(UiStrings.YES, "HintYesButton")
	yes.pressed.connect(_confirm_hint)
	_hint.add_child(yes)
	var dismiss := UiWidgets.button(UiStrings.DISMISS, "HintDismissButton")
	dismiss.pressed.connect(_dismiss_hint)
	_hint.add_child(dismiss)
	var input_row := HBoxContainer.new()
	column.add_child(input_row)
	_prompt = ChatInput.new()
	_prompt.name = "PromptField"
	_prompt.text_changed.connect(func() -> void: _refresh_hint_from_text())
	_prompt.submit_pressed.connect(_send)
	input_row.add_child(_prompt)
	var send := UiWidgets.button(UiStrings.SEND, "SendButton")
	send.pressed.connect(_send)
	input_row.add_child(send)
	var tools := HBoxContainer.new()
	column.add_child(tools)
	var evidence := UiWidgets.button(UiStrings.EVIDENCE, "EvidenceButton")
	evidence.pressed.connect(func() -> void: evidence_requested.emit())
	tools.add_child(evidence)
	var notebook := UiWidgets.button(UiStrings.NOTEBOOK, "NotebookButton")
	notebook.pressed.connect(func() -> void: notebook_requested.emit())
	tools.add_child(notebook)
	var contradiction := UiWidgets.button(UiStrings.CONTRADICTION, "ContradictionButton")
	contradiction.pressed.connect(func() -> void: contradiction_requested.emit())
	tools.add_child(contradiction)
	var stop_speech := UiWidgets.button(UiStrings.STOP_SPEECH, "StopSpeechButton")
	stop_speech.pressed.connect(func() -> void: Speaker.stop_and_clear())
	tools.add_child(stop_speech)
	if Speaker.last_error != "":
		_show_voice_error(Speaker.last_error)
	if not Speaker.voice_error.is_connected(_show_voice_error):
		Speaker.voice_error.connect(_show_voice_error)
	_voice_retry.visible = not Speaker.retry_line.is_empty()
	if not Speaker.voice_retry_available.is_connected(_show_voice_retry):
		Speaker.voice_retry_available.connect(_show_voice_retry)
	if not Game.agent_replied.is_connected(_on_replied):
		Game.agent_replied.connect(_on_replied)
		Game.events.connect(_on_events)
		Game.llm_error.connect(_on_error)
		Game.busy_changed.connect(_on_busy)


func _show_voice_retry(show_button: bool) -> void:
	_voice_retry.visible = show_button


func _show_voice_error(kind: String) -> void:
	var text := kind.strip_edges()
	_voice_error.text = "" if text == "" else "Голос: %s" % text
	_voice_error.visible = text != ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		Speaker.stop_and_clear(false)


func open_agent(next_id: String) -> void:
	agent_id = next_id
	if not _feeds.has(next_id):
		_feeds[next_id] = _saved_lines(next_id)
	_render_header()
	_render_feed()


func _saved_lines(id: String) -> Array:
	var lines: Array = []
	if Game.state == null:
		return lines
	var saved: Variant = Game.state.dialogues.get(id, {})
	if saved is not Dictionary:
		return lines
	var messages: Variant = (saved as Dictionary).get("messages", [])
	if messages is not Array:
		return lines
	for message in messages:
		if message is not Dictionary:
			continue
		var role := str((message as Dictionary).get("role", ""))
		if role == "player":
			lines.append({"kind": "player", "text": str((message as Dictionary).get("text", ""))})
		elif role == "agent":
			lines.append({
				"kind": "agent",
				"text": str((message as Dictionary).get("text", "")),
				"remark": str((message as Dictionary).get("remark", "")),
			})
	return lines


func set_back_visible(show_back: bool) -> void:
	var back := find_child("BackButton", true, false) as Button
	if back != null:
		back.visible = show_back


func _render_header() -> void:
	if Game.case_data == null or agent_id == "":
		_header.text = ""
		return
	var agent: CaseData.Agent = Game.case_data.agent_by_id[agent_id]
	var band := Balance.band(int(Game.state.pressure.get(agent_id, 0)))
	var emotion := str(Game.state.emotion.get(agent_id, agent.starting_emotion))
	_header.text = "%s, %s   %s" % [agent.name, agent.role, UiStrings.state_remark(band, emotion)]


func _send() -> void:
	if _busy or agent_id == "":
		return
	var text := _prompt.text.strip_edges()
	if text == "":
		return
	_prompt.text = ""
	_hide_hint()
	_clear_error()
	_last = {"kind": "ask", "text": text}
	_push({"kind": "player", "text": text})
	await Game.ask(agent_id, text)


func _confirm_from_board(evidence_id: String) -> void:
	if _busy or agent_id == "":
		return
	_clear_error()
	_last = {"kind": "present", "text": "", "evidence_id": evidence_id}
	_push({"kind": "system", "text": "Вы: %s" % UiStrings.presented_line(_evidence_title(evidence_id))})
	await Game.present(agent_id, evidence_id, "")


func _confirm_hint() -> void:
	if _busy or _hint_id == "" or agent_id == "":
		return
	var text := _prompt.text.strip_edges()
	var evidence_id := _hint_id
	_prompt.text = ""
	_hide_hint()
	_clear_error()
	_last = {"kind": "present", "text": text, "evidence_id": evidence_id}
	var title := _evidence_title(evidence_id)
	_push({"kind": "system", "text": "Вы: %s" % UiStrings.presented_line(title)})
	await Game.present(agent_id, evidence_id, text)


func _retry_last() -> void:
	if _last.is_empty() or _busy:
		return
	_clear_error()
	if str(_last.get("kind", "")) == "present":
		await Game.present(agent_id, str(_last.get("evidence_id", "")), str(_last.get("text", "")))
	else:
		_push({"kind": "player", "text": str(_last.get("text", ""))})
		await Game.ask(agent_id, str(_last.get("text", "")))


func _refresh_hint_from_text() -> void:
	if Game.case_data == null:
		return
	var found := Game.mentioned_evidence(_prompt.text)
	if found.is_empty():
		if _hint.visible:
			_hide_hint()
		return
	var evidence_id := str(found[0])
	if evidence_id == _dismissed:
		return
	_show_hint(evidence_id)


func _show_hint(evidence_id: String) -> void:
	_hint_id = evidence_id
	_hint_label.text = UiStrings.present_hint(_evidence_title(evidence_id))
	_hint.visible = true


func _dismiss_hint() -> void:
	_dismissed = _hint_id
	_hide_hint()


func _hide_hint() -> void:
	_hint_id = ""
	_hint.visible = false


func _on_replied(reply_agent: String, text: String, remark: String) -> void:
	if reply_agent != agent_id:
		_push_to(reply_agent, {"kind": "agent", "text": text, "remark": remark})
		return
	_push({"kind": "agent", "text": text, "remark": remark})
	_render_header()
	_show_turn_timing()
	_apply_model_hints()


func _on_events(list: Array) -> void:
	for event in list:
		if event is not Dictionary:
			continue
		var line := _event_line(event as Dictionary)
		if line != "":
			_push({"kind": "system", "text": line})
	_render_header()


func _on_error(kind: String, message: String) -> void:
	_pop_player_line()
	var text := message.strip_edges()
	if text == "":
		text = UiStrings.error_text(kind)
	_error.text = text
	_error.visible = true
	_retry.visible = true
	_show_turn_timing()


func _show_turn_timing() -> void:
	var enabled := SettingsStore.load_current().timing_debug
	_timing.text = Game.last_turn_line
	_timing.visible = enabled and Game.last_turn_line != ""


func _on_busy(is_busy: bool) -> void:
	_busy = is_busy
	_prompt.editable = not is_busy
	var send := find_child("SendButton", true, false) as Button
	if send != null:
		send.disabled = is_busy
	if is_busy and agent_id != "":
		var agent: CaseData.Agent = Game.case_data.agent_by_id.get(agent_id) as CaseData.Agent
		_thinking.text = UiStrings.thinking(agent.name if agent != null else "")
		_thinking.visible = true
	else:
		_thinking.visible = false


func _apply_model_hints() -> void:
	if Game.last_requested_evidence != "":
		var requested := _evidence_by_key(Game.last_requested_evidence)
		if requested != null:
			var agent: CaseData.Agent = Game.case_data.agent_by_id[agent_id]
			_push({"kind": "system", "text": UiStrings.demands(agent.name)})
			_show_hint(requested.id)
			return
	for key in Game.last_mentioned_evidence:
		var mentioned := _evidence_by_key(str(key))
		if mentioned != null:
			_show_hint(mentioned.id)
			return


func _event_line(event: Dictionary) -> String:
	var type_name := str(event.get("type", ""))
	if type_name == "evidence_unlocked":
		return UiStrings.evidence_opened(_evidence_title(str(event.get("evidence_id", ""))))
	if type_name == "contradiction_registered":
		var found: CaseData.Contradiction = Game.case_data.contradiction_by_id.get(str(event.get("contradiction_id", ""))) as CaseData.Contradiction
		if found == null:
			return ""
		return UiStrings.contradiction_line(found.description)
	if type_name == "lie_broken":
		var owner := str(event.get("agent_id", ""))
		var agent: CaseData.Agent = Game.case_data.agent_by_id.get(owner) as CaseData.Agent
		if agent == null:
			return ""
		return UiStrings.lie_broken(agent.name)
	return ""


func _push(line: Dictionary) -> void:
	_push_to(agent_id, line)
	if line.get("kind") != "player":
		_render_feed()
	else:
		_render_feed()


func _push_to(owner: String, line: Dictionary) -> void:
	if owner == "":
		return
	if not _feeds.has(owner):
		_feeds[owner] = []
	(_feeds[owner] as Array).append(line)


func _pop_player_line() -> void:
	if not _feeds.has(agent_id):
		return
	var rows: Array = _feeds[agent_id]
	if rows.is_empty():
		return
	var last: Dictionary = rows[rows.size() - 1]
	if str(last.get("kind", "")) == "player":
		rows.pop_back()
		_render_feed()


func _render_feed() -> void:
	if _feed_box == null:
		return
	for child in _feed_box.get_children():
		child.queue_free()
	var rows: Array = _feeds.get(agent_id, [])
	for row in rows:
		var kind := str(row.get("kind", ""))
		if kind == "player":
			_feed_box.add_child(UiWidgets.label("Вы: %s" % str(row.get("text", ""))))
		elif kind == "agent":
			var agent: CaseData.Agent = Game.case_data.agent_by_id.get(agent_id) as CaseData.Agent
			var name := agent.name if agent != null else ""
			var shown := VocalTags.visible(str(row.get("text", "")))
			_feed_box.add_child(UiWidgets.label("%s: %s" % [name, shown]))
			var remark := str(row.get("remark", ""))
			if remark != "":
				var note := UiWidgets.label("(%s)" % remark)
				note.add_theme_font_override("font", NoirTheme.italic())
				note.add_theme_color_override("font_color", NoirTheme.MUTED)
				_feed_box.add_child(note)
		else:
			var system := UiWidgets.label(str(row.get("text", "")))
			system.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			system.add_theme_color_override("font_color", NoirTheme.GOLD)
			_feed_box.add_child(system)
	call_deferred("_scroll_down")


func _scroll_down() -> void:
	if _scroll == null:
		return
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _clear_error() -> void:
	_error.visible = false
	_retry.visible = false


func _evidence_title(evidence_id: String) -> String:
	if Game.case_data == null or not Game.case_data.evidence_by_id.has(evidence_id):
		return evidence_id
	return (Game.case_data.evidence_by_id[evidence_id] as CaseData.EvidenceItem).title


func _evidence_by_key(key: String) -> CaseData.EvidenceItem:
	if Game.case_data == null or Game.state == null:
		return null
	if key.length() < 2 or not key.begins_with("e"):
		return null
	var index := key.substr(1).to_int() - 1
	var open: Array[CaseData.EvidenceItem] = []
	for evidence in Game.case_data.evidence:
		if Game.state.unlocked_evidence.has(evidence.id):
			open.append(evidence)
	if index < 0 or index >= open.size():
		return null
	return open[index]
