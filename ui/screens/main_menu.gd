extends Control

signal new_case_pressed
signal settings_pressed


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var center := CenterContainer.new()
	UiWidgets.fill(center)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	var title := UiWidgets.label("Детектив")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	box.add_child(_spacer(24))
	var new_case := UiWidgets.button(UiStrings.NEW_CASE, "NewCaseButton")
	new_case.pressed.connect(func() -> void: new_case_pressed.emit())
	box.add_child(new_case)
	var continue_button := UiWidgets.button(UiStrings.CONTINUE, "ContinueButton")
	continue_button.visible = false
	continue_button.focus_mode = Control.FOCUS_NONE
	box.add_child(continue_button)
	var settings := UiWidgets.button(UiStrings.SETTINGS, "SettingsButton")
	settings.pressed.connect(func() -> void: settings_pressed.emit())
	box.add_child(settings)
	for child in box.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = Vector2(280, 48)


func _spacer(height: float) -> Control:
	var control := Control.new()
	control.custom_minimum_size = Vector2(0, height)
	return control
