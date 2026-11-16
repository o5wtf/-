extends Control

signal back_pressed
signal saved

var explain_key: bool = false

var _key: LineEdit
var _model: LineEdit
var _scale: HSlider
var _mock: CheckBox
var _timing: CheckBox
var _status: Label
var _show: Button
var _testing: bool = false


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var margin := MarginContainer.new()
	UiWidgets.fill(margin)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var scroll_box := VBoxContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(UiWidgets.scrolling(scroll_box))
	scroll_box.add_child(UiWidgets.label(UiStrings.SETTINGS))
	var hint := UiWidgets.label("", "KeyHint")
	hint.add_theme_color_override("font_color", NoirTheme.MUTED)
	hint.visible = explain_key
	hint.text = UiStrings.KEY_HINT
	scroll_box.add_child(hint)
	scroll_box.add_child(UiWidgets.label(UiStrings.KEY_LABEL))
	var key_row := HBoxContainer.new()
	scroll_box.add_child(key_row)
	_key = LineEdit.new()
	_key.name = "KeyField"
	_key.secret = true
	_key.secret_character = "•"
	_key.custom_minimum_size = Vector2(0, 48)
	_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_row.add_child(_key)
	_show = UiWidgets.button(UiStrings.SHOW_KEY, "ShowKeyButton")
	_show.pressed.connect(_toggle_key)
	key_row.add_child(_show)
	var test := UiWidgets.button(UiStrings.TEST_LINK, "TestConnectionButton")
	test.pressed.connect(_test_connection)
	scroll_box.add_child(test)
	scroll_box.add_child(UiWidgets.label(UiStrings.MODEL_LABEL))
	_model = LineEdit.new()
	_model.name = "ModelField"
	_model.placeholder_text = UiStrings.MODEL_PLACEHOLDER
	_model.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_model)
	scroll_box.add_child(UiWidgets.label(UiStrings.SCALE_LABEL))
	_scale = HSlider.new()
	_scale.name = "ScaleSlider"
	_scale.min_value = 0.85
	_scale.max_value = 1.4
	_scale.step = 0.05
	_scale.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_scale)
	_mock = CheckBox.new()
	_mock.name = "MockCheck"
	_mock.text = UiStrings.MOCK_LABEL
	_mock.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_mock)
	_timing = CheckBox.new()
	_timing.name = "TimingDebug"
	_timing.text = UiStrings.TIMING_DEBUG
	_timing.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_timing)
	_status = UiWidgets.label("", "StatusLabel")
	scroll_box.add_child(_status)
	var save := UiWidgets.button(UiStrings.SAVE, "SaveButton")
	save.pressed.connect(_save)
	scroll_box.add_child(save)
	var back := UiWidgets.button(UiStrings.BACK, "BackButton")
	back.pressed.connect(func() -> void: back_pressed.emit())
	scroll_box.add_child(back)
	_load_fields()


func _load_fields() -> void:
	var store := SettingsStore.load_current()
	_key.placeholder_text = UiStrings.KEY_SAVED_PLACEHOLDER if store.api_key != "" else UiStrings.KEY_PLACEHOLDER
	_key.text = ""
	_model.text = store.dialogue_model
	_scale.value = store.text_scale
	_mock.button_pressed = store.provider == "mock"
	_timing.button_pressed = store.timing_debug


func _toggle_key() -> void:
	if _key.secret:
		if _key.text == "":
			_key.text = SettingsStore.load_current().api_key
		_key.secret = false
		_show.text = UiStrings.HIDE_KEY
	else:
		_key.secret = true
		_show.text = UiStrings.SHOW_KEY


func _save() -> void:
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _model.text, _scale.value, _timing.button_pressed)
	_key.text = ""
	_key.secret = true
	_show.text = UiStrings.SHOW_KEY
	_load_fields()
	_status.text = UiStrings.SAVED
	saved.emit()


func _test_connection() -> void:
	if _testing:
		return
	_testing = true
	_status.text = UiStrings.CHECKING
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	if provider != "mock" and key == "":
		_status.text = UiStrings.LINK_NEED_KEY
		_testing = false
		return
	var model := _model.text.strip_edges()
	if model == "":
		model = LLMConfig.DEFAULT_DIALOGUE_MODEL
	SettingsStore.save_values(provider, key, model, _scale.value)
	LLM.reload_client()
	var message := UiStrings.LINK_MOCK
	if provider != "mock":
		var result: Dictionary = await LLM.client.generate(_ping_request())
		message = UiStrings.connection_message(provider, result)
		message = _without_secret(message, key)
	_status.text = message
	_testing = false


func _ping_timeout() -> float:
	if LLM.client is GeminiClient:
		return (LLM.client as GeminiClient).ping_timeout_s
	return 32.0


func _ping_request() -> Dictionary:
	return {
		"system": "Верни короткий JSON.",
		"user": "ping",
		"probe": true,
		"timeout_s": _ping_timeout(),
		"temperature": 0.0,
		"max_output_tokens": 64,
		"schema": {
			"type": "object",
			"properties": {"ok": {"type": "string"}},
			"required": ["ok"],
		},
	}


func _without_secret(text: String, secret: String) -> String:
	var clean := secret.strip_edges()
	if clean == "":
		return text
	return text.replace(clean, "")
