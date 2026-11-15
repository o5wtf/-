class_name LLMConfig
extends RefCounted
## Ключ и модели. Ключ не пишется в логи.
## Порядок ключа: user://config.cfg, затем GEMINI_API_KEY, затем res://config/dev.cfg только в отладочной сборке.

const DEFAULT_DIALOGUE_MODEL := "gemini-3.8-flash"
const DEFAULT_SUMMARY_MODEL := "gemini-3.5-flash-lite"
const DEFAULT_FALLBACK_MODEL := "gemini-3.5-flash-lite"

var provider: String = "gemini"
var api_key: String = ""
var key_source: String = "none"
var dialogue_model: String = DEFAULT_DIALOGUE_MODEL
var summary_model: String = DEFAULT_SUMMARY_MODEL
var fallback_model: String = DEFAULT_FALLBACK_MODEL
var thinking_level: String = "LOW"
var timeout_s: float = 30.0
var min_interval_s: float = 1.0


static func live_smoke_enabled(env_key: String) -> bool:
	return env_key.strip_edges() != ""


static func load_settings() -> LLMConfig:
	var user_text := _read_text("user://config.cfg")
	var debug := OS.is_debug_build()
	var dev_text := _read_text("res://config/dev.cfg") if debug else ""
	return from_sources(user_text, OS.get_environment("GEMINI_API_KEY"), dev_text, debug)


static func from_sources(user_text: String, env_key: String, dev_text: String, debug: bool) -> LLMConfig:
	var config := LLMConfig.new()
	var user := _section(user_text)
	var dev := _section(dev_text) if debug else {}
	config.provider = _first_string(user, dev, "provider", "gemini")
	config.dialogue_model = _first_string(user, dev, "dialogue_model", DEFAULT_DIALOGUE_MODEL)
	config.summary_model = _first_string(user, dev, "summary_model", DEFAULT_SUMMARY_MODEL)
	config.fallback_model = _first_string(user, dev, "fallback_model", DEFAULT_FALLBACK_MODEL)
	config.thinking_level = _first_string(user, dev, "thinking_level", "LOW")
	config.timeout_s = _first_number(user, dev, "timeout_s", 30.0)
	config.min_interval_s = _first_number(user, dev, "min_interval_s", 1.0)
	var user_key := str(user.get("api_key", "")).strip_edges()
	var env := env_key.strip_edges()
	var dev_key := str(dev.get("api_key", "")).strip_edges()
	if user_key != "":
		config.api_key = user_key
		config.key_source = "user"
	elif env != "":
		config.api_key = env
		config.key_source = "env"
	elif debug and dev_key != "":
		config.api_key = dev_key
		config.key_source = "dev"
	return config


static func create_client(config: LLMConfig) -> LLMClient:
	if config.provider == "mock":
		return MockLLMClient.new()
	var client := GeminiClient.new()
	client.apply_config(config)
	return client


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func _section(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var file := ConfigFile.new()
	if file.parse(text) != OK:
		return {}
	var values := {}
	if not file.has_section("llm"):
		return values
	for key in file.get_section_keys("llm"):
		values[key] = file.get_value("llm", key)
	return values


static func _first_string(user: Dictionary, dev: Dictionary, key: String, fallback: String) -> String:
	if user.has(key) and str(user[key]).strip_edges() != "":
		return str(user[key]).strip_edges()
	if dev.has(key) and str(dev[key]).strip_edges() != "":
		return str(dev[key]).strip_edges()
	return fallback


static func _first_number(user: Dictionary, dev: Dictionary, key: String, fallback: float) -> float:
	if user.has(key):
		return float(user[key])
	if dev.has(key):
		return float(dev[key])
	return fallback
