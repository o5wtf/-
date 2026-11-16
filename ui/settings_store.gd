class_name SettingsStore
extends RefCounted
## user://config.cfg. Ключ хранится в файле настроек и не печатается.

const PATH := "user://config.cfg"

var provider: String = "gemini"
var api_key: String = ""
var dialogue_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var text_scale: float = 1.0
var voice_enabled: bool = true
var voice_provider: String = "cloud"
var stt_mode: String = "gemini_audio"
var voice_volume: float = 1.0
var voice_rate: float = 1.0
var tts_model: String = "gemini-3.8-flash-lite-tts"
var style_mode: String = VoiceProfiles.DEFAULT_STYLE_MODE
var pause_ms: int = Handsfree.DEFAULT_PAUSE_MS


static func load_current() -> SettingsStore:
	var store := SettingsStore.new()
	var config := LLMConfig.load_settings()
	store.provider = config.provider
	store.api_key = config.api_key
	store.dialogue_model = config.dialogue_model
	var file := ConfigFile.new()
	if file.load(PATH) == OK and file.has_section_key("ui", "text_scale"):
		store.text_scale = clampf(float(file.get_value("ui", "text_scale")), 0.85, 1.4)
	if file.load(PATH) == OK:
		store.voice_enabled = bool(file.get_value("voice", "enabled", true))
		store.voice_provider = str(file.get_value("voice", "provider", "cloud"))
		store.stt_mode = str(file.get_value("voice", "stt_mode", "gemini_audio"))
		store.voice_volume = clampf(float(file.get_value("voice", "volume", 1.0)), 0.0, 1.0)
		store.voice_rate = clampf(float(file.get_value("voice", "rate", 1.0)), 0.8, 1.3)
		var model := str(file.get_value("voice", "tts_model", store.tts_model)).strip_edges()
		if model != "":
			store.tts_model = model
		store.style_mode = VoiceProfiles.normalize_style(str(file.get_value("voice", "style_mode", store.style_mode)))
		store.pause_ms = Handsfree.clamp_pause(int(file.get_value("voice", "pause_ms", store.pause_ms)))
	return store


static func save_values(provider: String, api_key: String, dialogue_model: String, text_scale: float, voice: Dictionary = {}) -> void:
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("llm", "provider", provider)
	file.set_value("llm", "api_key", api_key)
	var model := dialogue_model.strip_edges()
	if model == "":
		model = LLMConfig.DEFAULT_DIALOGUE_MODEL
	file.set_value("llm", "dialogue_model", model)
	file.set_value("ui", "text_scale", clampf(text_scale, 0.85, 1.4))
	if not voice.is_empty():
		file.set_value("voice", "enabled", bool(voice.get("enabled", true)))
		file.set_value("voice", "provider", str(voice.get("provider", "cloud")))
		file.set_value("voice", "stt_mode", str(voice.get("stt_mode", "gemini_audio")))
		file.set_value("voice", "volume", clampf(float(voice.get("volume", 1.0)), 0.0, 1.0))
		file.set_value("voice", "rate", clampf(float(voice.get("rate", 1.0)), 0.8, 1.3))
		file.set_value("voice", "tts_model", str(voice.get("tts_model", "gemini-3.8-flash-lite-tts")))
		file.set_value("voice", "cloud_vendor", "gemini")
		if voice.has("style_mode"):
			file.set_value("voice", "style_mode", VoiceProfiles.normalize_style(str(voice["style_mode"])))
		if voice.has("pause_ms"):
			file.set_value("voice", "pause_ms", Handsfree.clamp_pause(int(voice["pause_ms"])))
	file.save(PATH)


static func has_playable_key() -> bool:
	var store := load_current()
	return store.provider == "mock" or store.api_key.strip_edges() != ""
