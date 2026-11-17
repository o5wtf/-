class_name SettingsStore
extends RefCounted
## user://config.cfg. Ключ хранится в файле настроек и не печатается.

const PATH := "user://config.cfg"

var provider: String = "gemini"
var api_key: String = ""
var dialogue_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var text_scale: float = 1.0
## Строка времени хода на допросе. Включена, чтобы замер был виден без отдельной настройки.
var timing_debug: bool = true
## Системная озвучка реплик. Выключена, пока игрок сам её не включит.
var voice_enabled: bool = false


static func load_current() -> SettingsStore:
	var store := SettingsStore.new()
	var config := LLMConfig.load_settings()
	store.provider = config.provider
	store.api_key = config.api_key
	store.dialogue_model = config.dialogue_model
	var file := ConfigFile.new()
	if file.load(PATH) == OK and file.has_section_key("ui", "text_scale"):
		store.text_scale = clampf(float(file.get_value("ui", "text_scale")), 0.85, 1.4)
	if file.load(PATH) == OK and file.has_section_key("llm", "timing_debug"):
		store.timing_debug = bool(file.get_value("llm", "timing_debug"))
	if file.load(PATH) == OK and file.has_section_key("voice", "enabled"):
		store.voice_enabled = bool(file.get_value("voice", "enabled"))
	return store


static func save_values(provider: String, api_key: String, dialogue_model: String, text_scale: float, timing_debug: Variant = null, voice_enabled: Variant = null) -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("llm", "provider", provider)
	file.set_value("llm", "api_key", api_key)
	var model := LLMConfig.canonical_model(dialogue_model)
	file.set_value("llm", "dialogue_model", model)
	file.set_value("llm", "summary_model", model)
	file.set_value("llm", "settings_version", LLMConfig.SETTINGS_VERSION)
	file.set_value("ui", "text_scale", clampf(text_scale, 0.85, 1.4))
	if timing_debug != null:
		file.set_value("llm", "timing_debug", bool(timing_debug))
	if voice_enabled != null:
		file.set_value("voice", "enabled", bool(voice_enabled))
	file.save(PATH)


static func remember_thinking(model: String, level: String) -> void:
	if not LLMConfig.is_dialogue_model(model):
		return
	var file := ConfigFile.new()
	file.load(PATH)
	var accepted := _thinking_map(str(file.get_value("llm", "thinking_accepted", "")))
	accepted[model] = level
	file.set_value("llm", "thinking_accepted", _thinking_text(accepted))
	file.save(PATH)


static func load_thinking() -> Dictionary:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return {}
	return _thinking_map(str(file.get_value("llm", "thinking_accepted", "")))


static func _thinking_map(raw: String) -> Dictionary:
	var accepted := {}
	for piece in raw.split(",", false):
		var pair := piece.split("=", true, 1)
		if pair.size() != 2:
			continue
		var model := pair[0].strip_edges()
		var level := pair[1].strip_edges()
		if LLMConfig.is_dialogue_model(model) and level != "":
			accepted[model] = level
	return accepted


static func _thinking_text(accepted: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for model in LLMConfig.DIALOGUE_MODELS:
		if accepted.has(model):
			parts.append("%s=%s" % [model, str(accepted[model])])
	return ",".join(parts)


static func has_playable_key() -> bool:
	var store := load_current()
	return store.provider == "mock" or store.api_key.strip_edges() != ""
