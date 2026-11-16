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
	return store


static func save_values(provider: String, api_key: String, dialogue_model: String, text_scale: float, timing_debug: Variant = null) -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("llm", "provider", provider)
	file.set_value("llm", "api_key", api_key)
	var model := dialogue_model.strip_edges()
	if model == "":
		model = LLMConfig.DEFAULT_DIALOGUE_MODEL
	file.set_value("llm", "dialogue_model", model)
	file.set_value("ui", "text_scale", clampf(text_scale, 0.85, 1.4))
	if timing_debug != null:
		file.set_value("llm", "timing_debug", bool(timing_debug))
	file.save(PATH)


static func has_playable_key() -> bool:
	var store := load_current()
	return store.provider == "mock" or store.api_key.strip_edges() != ""
