class_name SettingsStore
extends RefCounted
## user://config.cfg. Ключ хранится в файле настроек и не печатается.

const PATH := "user://config.cfg"

var provider: String = "gemini"
var api_key: String = ""
var dialogue_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var text_scale: float = 1.0


static func load_current() -> SettingsStore:
	var store := SettingsStore.new()
	var config := LLMConfig.load_settings()
	store.provider = config.provider
	store.api_key = config.api_key
	store.dialogue_model = config.dialogue_model
	var file := ConfigFile.new()
	if file.load(PATH) == OK and file.has_section_key("ui", "text_scale"):
		store.text_scale = clampf(float(file.get_value("ui", "text_scale")), 0.85, 1.4)
	return store


static func save_values(provider: String, api_key: String, dialogue_model: String, text_scale: float) -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("llm", "provider", provider)
	file.set_value("llm", "api_key", api_key)
	var model := dialogue_model.strip_edges()
	if model == "":
		model = LLMConfig.DEFAULT_DIALOGUE_MODEL
	file.set_value("llm", "dialogue_model", model)
	file.set_value("ui", "text_scale", clampf(text_scale, 0.85, 1.4))
	file.save(PATH)


static func has_playable_key() -> bool:
	var store := load_current()
	return store.provider == "mock" or store.api_key.strip_edges() != ""
