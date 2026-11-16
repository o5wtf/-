extends Control

signal back_pressed
signal saved

var explain_key: bool = false

var _key: LineEdit
var _model: LineEdit
var _scale: HSlider
var _mock: CheckBox
var _voice_on: CheckBox
var _intonation: CheckBox
var _source: OptionButton
var _stt: OptionButton
var _volume: HSlider
var _rate: HSlider
var _status: Label
var _show: Button
var _testing: bool = false
var _voice_done: bool = false
var _voice_failed: bool = false
var _voice_message: String = ""


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
	scroll_box.add_child(UiWidgets.label(UiStrings.VOICE_NOTICE))
	_voice_on = CheckBox.new()
	_voice_on.name = "VoiceToggle"
	_voice_on.text = UiStrings.VOICE_TOGGLE
	_voice_on.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_voice_on)
	_intonation = CheckBox.new()
	_intonation.name = "IntonationToggle"
	_intonation.text = UiStrings.VOICE_INTONATION
	_intonation.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_intonation)
	scroll_box.add_child(UiWidgets.label(UiStrings.VOICE_SOURCE))
	_source = OptionButton.new()
	_source.name = "VoiceSource"
	_source.custom_minimum_size = Vector2(0, 48)
	_source.add_item(UiStrings.VOICE_CLOUD, 0)
	_source.add_item(UiStrings.VOICE_BUILTIN, 1)
	scroll_box.add_child(_source)
	scroll_box.add_child(UiWidgets.label(UiStrings.VOICE_INPUT))
	_stt = OptionButton.new()
	_stt.name = "VoiceInput"
	_stt.custom_minimum_size = Vector2(0, 48)
	_stt.add_item(UiStrings.VOICE_STT_GEMINI, 0)
	_stt.add_item(UiStrings.VOICE_STT_CLOUD, 1)
	_stt.add_item(UiStrings.VOICE_STT_BUILTIN, 2)
	_stt.set_item_disabled(2, true)
	scroll_box.add_child(_stt)
	var test_voice := UiWidgets.button(UiStrings.TEST_VOICE, "TestVoiceButton")
	test_voice.pressed.connect(_test_voice)
	scroll_box.add_child(test_voice)
	scroll_box.add_child(UiWidgets.label(UiStrings.VOICE_VOLUME))
	_volume = HSlider.new()
	_volume.name = "VoiceVolume"
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_volume)
	scroll_box.add_child(UiWidgets.label(UiStrings.VOICE_RATE))
	_rate = HSlider.new()
	_rate.name = "VoiceRate"
	_rate.min_value = 0.8
	_rate.max_value = 1.3
	_rate.step = 0.05
	_rate.custom_minimum_size = Vector2(0, 48)
	scroll_box.add_child(_rate)
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
	_voice_on.button_pressed = store.voice_enabled
	_intonation.button_pressed = store.style_mode != VoiceProfiles.STYLE_PLAIN
	_source.select(1 if store.voice_provider == "builtin" else 0)
	_stt.select(_stt_index(store.stt_mode))
	_volume.value = store.voice_volume
	_rate.value = store.voice_rate


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
	SettingsStore.save_values(provider, key, _model.text, _scale.value, _voice_payload())
	Voice.reload()
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
	SettingsStore.save_values(provider, key, model, _scale.value, _voice_payload())
	Voice.reload()
	LLM.reload_client()
	var message := UiStrings.LINK_MOCK
	if provider != "mock":
		var result: Dictionary = await LLM.client.generate(_ping_request())
		message = UiStrings.connection_message(provider, result)
		message = _without_secret(message, key)
	_status.text = message
	_testing = false


func _test_voice() -> void:
	if _testing:
		return
	_testing = true
	_save()
	_status.text = UiStrings.CHECKING
	var secret := SettingsStore.load_current().api_key
	_voice_done = false
	_voice_failed = false
	_voice_message = ""
	if not Voice.voice_error.is_connected(_on_voice_probe_error):
		Voice.voice_error.connect(_on_voice_probe_error)
		Voice.speech_finished.connect(_on_voice_probe_spoken)
	var utterance_id := Voice.speak_sample()
	if utterance_id < 0 and not _voice_done:
		_voice_message = "Синтез речи недоступен."
		_voice_done = true
	while not _voice_done:
		await get_tree().process_frame
	if Voice.voice_error.is_connected(_on_voice_probe_error):
		Voice.voice_error.disconnect(_on_voice_probe_error)
		Voice.speech_finished.disconnect(_on_voice_probe_spoken)
	_status.text = _without_secret(_voice_message, secret)
	_testing = false


func _on_voice_probe_error(kind: String, text: String) -> void:
	_voice_failed = true
	_voice_message = UiStrings.VOICE_SKIPPED if kind == "rate_limited" else text
	if _voice_message.strip_edges() == "":
		_voice_message = kind
	_voice_done = true


func _on_voice_probe_spoken(_utterance_id: int) -> void:
	if _voice_failed:
		return
	_voice_message = "Голос ответил."
	_voice_done = true


func _voice_payload() -> Dictionary:
	return {
		"enabled": _voice_on.button_pressed,
		"provider": "builtin" if _source.selected == 1 else "cloud",
		"stt_mode": _stt_mode(_stt.selected),
		"volume": _volume.value,
		"rate": _rate.value,
		"tts_model": SettingsStore.load_current().tts_model,
		"style_mode": _style_mode_to_save(),
	}


func _style_mode_to_save() -> String:
	if not _intonation.button_pressed:
		return VoiceProfiles.STYLE_PLAIN
	var current := SettingsStore.load_current().style_mode
	if current == VoiceProfiles.STYLE_ENGLISH_TAGS:
		return current
	return VoiceProfiles.DEFAULT_STYLE_MODE


func _stt_index(mode: String) -> int:
	if mode == "cloud":
		return 1
	if mode == "builtin":
		return 2
	return 0


func _stt_mode(index: int) -> String:
	if index == 1:
		return "cloud"
	if index == 2:
		return "builtin"
	return "gemini_audio"


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
