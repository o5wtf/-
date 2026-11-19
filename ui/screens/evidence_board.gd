extends Control

signal present_requested(evidence_id: String)

var agent_id: String = ""

var _grid: VBoxContainer
var _detail: PanelContainer
var _detail_title: Label
var _detail_body: Label
var _detail_shown: Label
var _present: Button
var _open_id: String = ""


func _ready() -> void:
	UiWidgets.fill(self)
	var column := VBoxContainer.new()
	UiWidgets.fill(column)
	add_child(column)
	column.add_child(UiWidgets.label(UiStrings.EVIDENCE))
	_grid = VBoxContainer.new()
	_grid.name = "Grid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UiWidgets.scrolling(_grid))
	_detail = PanelContainer.new()
	_detail.name = "Detail"
	_detail.visible = false
	column.add_child(_detail)
	var detail_box := VBoxContainer.new()
	_detail.add_child(detail_box)
	_detail_title = UiWidgets.label("", "DetailTitle")
	detail_box.add_child(_detail_title)
	_detail_body = UiWidgets.label("", "DetailBody")
	detail_box.add_child(_detail_body)
	_detail_shown = UiWidgets.label("", "DetailShown")
	detail_box.add_child(_detail_shown)
	_present = UiWidgets.button(UiStrings.PRESENT, "PresentButton")
	_present.pressed.connect(func() -> void: present_requested.emit(_open_id))
	detail_box.add_child(_present)
	refresh()


func refresh() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	if Game.case_data == null or Game.state == null:
		return
	var any := false
	for evidence in Game.case_data.evidence:
		if not Game.state.unlocked_evidence.has(evidence.id):
			continue
		any = true
		_grid.add_child(_card(evidence))
	if not any:
		_grid.add_child(UiWidgets.label(UiStrings.NO_EVIDENCE))
	if _open_id != "":
		_detail_shown.text = "%s%s" % [UiStrings.SHOWN_TO, _shown_names(_open_id)]
	_update_present_caption()


func _card(evidence: CaseData.EvidenceItem) -> Button:
	var shown := _shown_mark(evidence.id)
	var button := UiWidgets.button("%s\n%s\n%s" % [UiStrings.evidence_kind(evidence.type), evidence.title, evidence.short_description], "Evidence_%s" % evidence.id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if shown != "":
		button.text += "\n" + shown
	button.pressed.connect(func() -> void: _open(evidence))
	return button


func _open(evidence: CaseData.EvidenceItem) -> void:
	_open_id = evidence.id
	_detail_title.text = "%s — %s" % [UiStrings.evidence_kind(evidence.type), evidence.title]
	_detail_body.text = evidence.full_text
	_detail_shown.text = "%s%s" % [UiStrings.SHOWN_TO, _shown_names(evidence.id)]
	_detail.visible = true
	_update_present_caption()


func _update_present_caption() -> void:
	if _present == null:
		return
	_present.visible = agent_id != "" and _open_id != ""
	if agent_id == "" or Game.case_data == null:
		return
	var agent: CaseData.Agent = Game.case_data.agent_by_id.get(agent_id) as CaseData.Agent
	if agent == null:
		return
	_present.text = "%s %s" % [UiStrings.PRESENT, agent.name]


func _shown_names(evidence_id: String) -> String:
	var names: PackedStringArray = PackedStringArray()
	var shown: Array = Game.state.shown.get(evidence_id, [])
	for agent_id_value in shown:
		var agent: CaseData.Agent = Game.case_data.agent_by_id.get(str(agent_id_value)) as CaseData.Agent
		if agent != null:
			names.append(agent.name)
	if names.is_empty():
		return UiStrings.NOBODY
	return ", ".join(names)


func _shown_mark(evidence_id: String) -> String:
	if agent_id == "":
		return ""
	var shown: Array = Game.state.shown.get(evidence_id, [])
	if shown.has(agent_id):
		return "уже показана"
	return ""
