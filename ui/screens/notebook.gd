extends Control

var _rows: VBoxContainer
var _filter: OptionButton
var _result: Label
var _pick: bool = false
var _selected: Array[Dictionary] = []


func _ready() -> void:
	UiWidgets.fill(self)
	var column := VBoxContainer.new()
	UiWidgets.fill(column)
	add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	top.add_child(UiWidgets.label(UiStrings.NOTEBOOK))
	_filter = OptionButton.new()
	_filter.name = "FilterButton"
	_filter.custom_minimum_size = Vector2(160, 48)
	_filter.item_selected.connect(func(_index: int) -> void: refresh())
	top.add_child(_filter)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiWidgets.scrolling(_rows))
	_result = UiWidgets.label("", "ResultLabel")
	column.add_child(_result)
	var check := UiWidgets.button(UiStrings.CHECK, "CheckButton")
	check.pressed.connect(_check)
	column.add_child(check)
	refresh()


func enter_pick_mode() -> void:
	_pick = true
	_selected.clear()
	_result.text = UiStrings.PICK_TWO
	refresh()


func refresh() -> void:
	if _filter == null:
		return
	var current := _filter.get_selected_id()
	_filter.clear()
	_filter.add_item(UiStrings.ALL_AGENTS, 0)
	if Game.case_data != null:
		var index := 1
		for agent in Game.case_data.agents:
			_filter.add_item(agent.name, index)
			_filter.set_item_metadata(index, agent.id)
			index += 1
	if current >= 0 and current < _filter.item_count:
		_filter.select(current)
	else:
		_filter.select(0)
	for child in _rows.get_children():
		child.queue_free()
	if Game.notebook == null:
		_rows.add_child(UiWidgets.label(UiStrings.NO_NOTES))
		return
	var agent_filter := ""
	if _filter.selected > 0:
		agent_filter = str(_filter.get_item_metadata(_filter.selected))
	var any := false
	for entry in Game.notebook.entries():
		if agent_filter != "" and str(entry.get("agent_id", "")) != agent_filter:
			continue
		any = true
		_rows.add_child(_entry_button(entry))
	if not any:
		_rows.add_child(UiWidgets.label(UiStrings.NO_NOTES))
	_rows.add_child(UiWidgets.label(UiStrings.CONTRADICTIONS))
	var found := false
	if Game.case_data != null and Game.state != null:
		for contradiction in Game.case_data.contradictions:
			if not Game.state.contradictions.has(contradiction.id):
				continue
			found = true
			var line := UiWidgets.label("✓ %s" % contradiction.description)
			line.add_theme_color_override("font_color", NoirTheme.GOOD)
			_rows.add_child(line)
	if not found:
		_rows.add_child(UiWidgets.label("—"))


func _entry_button(entry: Dictionary) -> Button:
	var agent_name := str(entry.get("agent_id", ""))
	if Game.case_data != null and Game.case_data.agent_by_id.has(agent_name):
		agent_name = (Game.case_data.agent_by_id[agent_name] as CaseData.Agent).name
	var button := UiWidgets.button("%s, ход %s:  «%s»" % [agent_name, str(entry.get("turn", 0)), str(entry.get("text", ""))], "Note")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _is_selected(entry):
		button.modulate = NoirTheme.GOLD
	button.pressed.connect(func() -> void: _toggle(entry))
	return button


func _toggle(entry: Dictionary) -> void:
	_pick = true
	var index := _selected_index(entry)
	if index >= 0:
		_selected.remove_at(index)
	elif _selected.size() < 2:
		_selected.append(entry)
	refresh()


func _check() -> void:
	if _selected.size() != 2:
		_result.text = UiStrings.PICK_TWO
		return
	var report := Game.mark_contradiction(_selected[0], _selected[1])
	if not report.get("ok", false):
		_result.text = UiStrings.NO_CONTRADICTION
		return
	var description := ""
	var found: CaseData.Contradiction = Game.case_data.contradiction_by_id.get(str(report.get("contradiction_id", ""))) as CaseData.Contradiction
	if found != null:
		description = found.description
	_result.text = "%s. %s" % [UiStrings.CONTRADICTION_FOUND, description]
	_selected.clear()
	refresh()


func _is_selected(entry: Dictionary) -> bool:
	return _selected_index(entry) >= 0


func _selected_index(entry: Dictionary) -> int:
	for index in _selected.size():
		var row := _selected[index]
		if str(row.get("fact_id", "")) == str(entry.get("fact_id", "")) and str(row.get("form", "")) == str(entry.get("form", "")) and str(row.get("agent_id", "")) == str(entry.get("agent_id", "")):
			return index
	return -1
