extends Control

signal back_pressed
signal saved

var explain_key: bool = false

var _key: LineEdit
var _model: OptionButton
var _spend: Label
var _loading: bool = false
var _scale: HSlider
var _mock: CheckBox
var _timing: CheckBox
var _voice: CheckBox
var _engine: OptionButton
var _voice_status: Label
var _voice_busy: bool = false
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
	_model = OptionButton.new()
	_model.name = "ModelField"
	_model.custom_minimum_size = Vector2(0, 48)
	for model_id in LLMConfig.DIALOGUE_MODELS:
		_model.add_item(model_id)
	_model.item_selected.connect(_on_model_picked)
	scroll_box.add_child(_model)
	_spend = UiWidgets.label("", "SpendLabel")
	scroll_box.add_child(_spend)
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
	_voice = CheckBox.new()
	_voice.name = "VoiceEnabled"
	_voice.text = UiStrings.VOICE_ENABLED
	_voice.custom_minimum_size = Vector2(0, 48)
	_voice.toggled.connect(_on_voice_toggled)
	scroll_box.add_child(_voice)
	scroll_box.add_child(UiWidgets.label(UiStrings.VOICE_ENGINE))
	_engine = OptionButton.new()
	_engine.name = "VoiceEngine"
	_engine.custom_minimum_size = Vector2(0, 48)
	_engine.add_item(UiStrings.VOICE_SYSTEM)
	_engine.add_item(UiStrings.VOICE_GEMINI)
	_engine.item_selected.connect(_on_engine_picked)
	scroll_box.add_child(_engine)
	var voice_check := UiWidgets.button(UiStrings.VOICE_CHECK, "VoiceCheckButton")
	voice_check.pressed.connect(_check_voice)
	scroll_box.add_child(voice_check)
	_voice_status = UiWidgets.label("", "VoiceStatusLabel")
	_voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_status.add_theme_color_override("font_color", NoirTheme.MUTED)
	scroll_box.add_child(_voice_status)
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
	_loading = true
	_model.select(_model_index(store.dialogue_model))
	_voice.button_pressed = store.voice_enabled
	_engine.select(1 if store.voice_engine == "gemini" else 0)
	_loading = false
	_spend.text = _spend_text()
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
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, _voice.button_pressed, _engine_value())
	Speaker.apply_settings()
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
	var model := _selected_model()
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


func _check_voice() -> void:
	if _voice_busy:
		return
	_voice_busy = true
	_voice_status.text = UiStrings.CHECKING
	var line: String = await Speaker.speak_test()
	_voice_status.text = line
	_voice_busy = false


func _on_voice_toggled(pressed: bool) -> void:
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, pressed, _engine_value())
	Speaker.apply_settings()


func _on_engine_picked(_index: int) -> void:
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed, _voice.button_pressed, _engine_value())
	Speaker.apply_settings()


func _engine_value() -> String:
	return "gemini" if _engine.selected == 1 else "system"


func _selected_model() -> String:
	var index := _model.selected
	if index < 0 or index >= LLMConfig.DIALOGUE_MODELS.size():
		return LLMConfig.DEFAULT_DIALOGUE_MODEL
	return LLMConfig.DIALOGUE_MODELS[index]


func _model_index(model: String) -> int:
	var canonical := LLMConfig.canonical_model(model)
	var index := LLMConfig.DIALOGUE_MODELS.find(canonical)
	return index if index >= 0 else 0


func _on_model_picked(_index: int) -> void:
	if _loading:
		return
	var previous := SettingsStore.load_current()
	var key := _key.text.strip_edges()
	if key == "":
		key = previous.api_key
	var provider := "mock" if _mock.button_pressed else "gemini"
	SettingsStore.save_values(provider, key, _selected_model(), _scale.value, _timing.button_pressed)
	LLM.reload_client()
	_spend.text = _spend_text()


func _spend_text() -> String:
	return "%s: сессия %s · всего %s" % [
		UiStrings.SPEND_LABEL,
		SpendMeter.format_usd(SpendMeter.session_usd),
		SpendMeter.format_usd(SpendMeter.total_usd()),
	]


func _without_secret(text: String, secret: String) -> String:
	var clean := secret.strip_edges()
	if clean == "":
		return text
	return text.replace(clean, "")
