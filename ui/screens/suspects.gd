extends Control

signal agent_chosen(agent_id: String)

var _list: VBoxContainer


func _ready() -> void:
	UiWidgets.fill(self)
	var box := VBoxContainer.new()
	UiWidgets.fill(box)
	add_child(box)
	box.add_child(UiWidgets.label("Подозреваемые"))
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UiWidgets.scrolling(_list))
	refresh("", {})


func refresh(active_id: String, news: Dictionary) -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if Game.case_data == null:
		return
	var ordered: Array = []
	var first := Game.case_data.starting_agent_id
	for agent in Game.case_data.agents:
		if agent.id == first:
			ordered.push_front(agent)
		else:
			ordered.append(agent)
	for agent in ordered:
		_list.add_child(_card(agent, active_id, bool(news.get(agent.id, false))))


func _card(agent: CaseData.Agent, active_id: String, has_news: bool) -> Control:
	var root := PanelContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 128)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(stack)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(box)
	var name_label := UiWidgets.label(agent.name)
	name_label.add_theme_font_size_override("font_size", 20)
	box.add_child(name_label)
	var role := UiWidgets.label(agent.role)
	role.add_theme_color_override("font_color", NoirTheme.MUTED)
	box.add_child(role)
	var band := Balance.band(int(Game.state.pressure.get(agent.id, 0)))
	var emotion := str(Game.state.emotion.get(agent.id, agent.starting_emotion))
	var pressure_value := int(Game.state.pressure.get(agent.id, 0))
	box.add_child(UiWidgets.label(UiStrings.state_line(band, emotion, pressure_value, SettingsStore.load_current().developer)))
	if has_news:
		var news_label := UiWidgets.label("● %s" % UiStrings.NEWS)
		news_label.add_theme_color_override("font_color", NoirTheme.GOLD)
		box.add_child(news_label)
	var hit := UiWidgets.button("", "Agent_%s" % agent.id)
	hit.flat = true
	hit.tooltip_text = agent.role
	hit.pressed.connect(func() -> void: agent_chosen.emit(agent.id))
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(hit)
	if agent.id == Game.case_data.starting_agent_id or agent.id == active_id:
		var border := StyleBoxFlat.new()
		border.bg_color = NoirTheme.PANEL
		border.border_color = NoirTheme.GOLD
		border.set_border_width_all(2)
		border.set_corner_radius_all(6)
		border.content_margin_left = 10
		border.content_margin_top = 8
		border.content_margin_right = 10
		border.content_margin_bottom = 8
		root.add_theme_stylebox_override("panel", border)
	return root
