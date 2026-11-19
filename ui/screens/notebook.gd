extends Control

var _rows: VBoxContainer
var _filter: OptionButton
var _tabs: TabBar
var _tab: int = 0


func _ready() -> void:
	UiWidgets.fill(self)
	var column := VBoxContainer.new()
	UiWidgets.fill(column)
	add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	_tabs = TabBar.new()
	_tabs.name = "NotebookTabs"
	_tabs.custom_minimum_size = Vector2(0, 48)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_tab(UiStrings.NOTES_TAB)
	_tabs.add_tab(UiStrings.CONTRADICTIONS_TAB)
	_tabs.tab_changed.connect(_on_tab)
	top.add_child(_tabs)
	_filter = OptionButton.new()
	_filter.name = "FilterButton"
	_filter.custom_minimum_size = Vector2(140, 48)
	_filter.item_selected.connect(func(_index: int) -> void: refresh())
	top.add_child(_filter)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiWidgets.scrolling(_rows))
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
	if _tab == 0:
		_fill_notes(_agent_filter())
	else:
		_fill_contradictions(_agent_filter())


func _on_tab(index: int) -> void:
	_tab = index
	refresh()


func _agent_filter() -> String:
	if _filter.selected <= 0:
		return ""
	return str(_filter.get_item_metadata(_filter.selected))


func _fill_notes(agent_filter: String) -> void:
	if Game.notebook == null:
		_rows.add_child(_plain(UiStrings.NO_NOTES))
		return
	var any := false
	for entry in Game.notebook.entries():
		if agent_filter != "" and str(entry.get("agent_id", "")) != agent_filter:
			continue
		any = true
		_rows.add_child(_note_row(entry))
	if not any:
		_rows.add_child(_plain(UiStrings.NO_NOTES))


func _fill_contradictions(agent_filter: String) -> void:
	var rows: Array[Dictionary] = []
	if Game.notebook != null:
		rows = Game.notebook.found_contradictions(agent_filter)
	if rows.is_empty():
		_rows.add_child(_plain("—"))
		return
	for row in rows:
		_rows.add_child(_contradiction_row(row))


func _note_row(entry: Dictionary) -> Label:
	var agent_name := str(entry.get("agent_id", ""))
	if Game.case_data != null and Game.case_data.agent_by_id.has(agent_name):
		agent_name = (Game.case_data.agent_by_id[agent_name] as CaseData.Agent).name
	return _plain("%s, ход %s:  «%s»" % [agent_name, str(entry.get("turn", 0)), str(entry.get("text", ""))])


func _contradiction_row(row: Dictionary) -> Label:
	var text := "✓ %s" % str(row.get("description", ""))
	var turn := int(row.get("turn", -1))
	if turn >= 0:
		text = "%s, ход %d" % [text, turn]
	var line := _plain(text)
	line.add_theme_color_override("font_color", NoirTheme.GOOD)
	return line


func _plain(text: String) -> Label:
	var line := UiWidgets.label(text)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
