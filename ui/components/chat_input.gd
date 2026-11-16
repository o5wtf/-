class_name ChatInput
extends TextEdit
## Enter отправляет, Shift+Enter оставляет новую строку.

signal submit_pressed


func _ready() -> void:
	custom_minimum_size = Vector2(0, 72)
	placeholder_text = UiStrings.QUESTION_PLACEHOLDER
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_fit_content_height = true
	context_menu_enabled = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ENTER and not key.shift_pressed:
			accept_event()
			submit_pressed.emit()
