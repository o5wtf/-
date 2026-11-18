class_name SpendMeter
extends RefCounted
## Расход по прайсу Gemini, paid tier. Ключ сюда не пишется.
## Цены за 1 млн токенов, USD, страница Google AI «Gemini API pricing» на 17 ноября 2026.
## Выход включает токены рассуждений. У gemini-3.6-flash до 31 декабря 2026 Introductory rate.

## Подменяется в тестах, чтобы не писать расход в настоящий user://config.cfg.
static var store_path: String = "user://config.cfg"


static var session_usd: float = 0.0
static var session_stt_usd: float = 0.0
static var now_override: int = -1

const CHIRP_USD_PER_MILLION_CHARS := 30.0
const CHIRP_FREE_CHARS := 1000000


static func cost_usd(model: String, prompt_tokens: int, thought_tokens: int, output_tokens: int) -> float:
	var prices := _prices(model)
	if prices.is_empty():
		return 0.0
	var prompt := maxi(prompt_tokens, 0)
	var output := maxi(thought_tokens, 0) + maxi(output_tokens, 0)
	return (float(prompt) * float(prices["input"]) + float(output) * float(prices["output"])) / 1000000.0


static func note(model: String, prompt_tokens: int, thought_tokens: int, output_tokens: int) -> void:
	var cost := cost_usd(model, prompt_tokens, thought_tokens, output_tokens)
	if cost <= 0.0:
		return
	session_usd += cost
	_add_total(cost)


static func note_stt(model: String, prompt_tokens: int, output_tokens: int) -> void:
	var cost := cost_usd(model, prompt_tokens, 0, output_tokens)
	if cost <= 0.0:
		return
	session_usd += cost
	session_stt_usd += cost
	_add_total(cost)
	_add_named("stt_usd", cost)


static func chirp_cost_usd(chars: int) -> float:
	return maxi(chars, 0) * CHIRP_USD_PER_MILLION_CHARS / 1000000.0


static func note_chirp(chars: int) -> void:
	var count := maxi(chars, 0)
	if count == 0:
		return
	var cost := chirp_cost_usd(count)
	session_usd += cost
	_add_total(cost)
	var file := _file()
	var month := _month()
	if str(file.get_value("spend", "chirp_month", "")) != month:
		file.set_value("spend", "chirp_month", month)
		file.set_value("spend", "chirp_chars", 0)
	file.set_value("spend", "chirp_chars", int(file.get_value("spend", "chirp_chars", 0)) + count)
	file.save(store_path)


static func chirp_chars_this_month() -> int:
	var file := ConfigFile.new()
	if file.load(store_path) != OK:
		return 0
	if str(file.get_value("spend", "chirp_month", "")) != _month():
		return 0
	return int(file.get_value("spend", "chirp_chars", 0))


static func _month() -> String:
	var unix := now_override if now_override >= 0 else int(Time.get_unix_time_from_system())
	var date := Time.get_date_dict_from_unix_time(unix)
	return "%04d-%02d" % [int(date.get("year", 1970)), int(date.get("month", 1))]


static func _file() -> ConfigFile:
	var file := ConfigFile.new()
	file.load(store_path)
	return file


static func stt_total_usd() -> float:
	var file := ConfigFile.new()
	if file.load(store_path) != OK:
		return 0.0
	return float(file.get_value("spend", "stt_usd", 0.0))


static func total_usd() -> float:
	var file := ConfigFile.new()
	if file.load(store_path) != OK:
		return 0.0
	return float(file.get_value("spend", "total_usd", 0.0))


static func format_usd(amount: float) -> String:
	return "$%.6f" % amount


static func _prices(model: String) -> Dictionary:
	match model:
		"gemini-3.5-flash-lite":
			return {"input": 0.30, "output": 2.50}
		"gemini-3.1-flash-lite":
			return {"input": 0.25, "output": 1.50}
		"gemini-3.6-flash":
			if _after_introductory_rate():
				return {"input": 1.50, "output": 7.50}
			return {"input": 0.75, "output": 3.75}
		"gemini-3.8-flash-lite-tts":
			return {"input": GeminiTtsBackend.INPUT_USD_PER_MILLION, "output": GeminiTtsBackend.OUTPUT_USD_PER_MILLION}
		"gemini-3.8-flash-tts":
			return {"input": GeminiTtsBackend.FLASH_INPUT_USD_PER_MILLION, "output": GeminiTtsBackend.FLASH_OUTPUT_USD_PER_MILLION}
		_:
			return {}


static func _after_introductory_rate() -> bool:
	var date := Time.get_date_dict_from_system()
	return int(date.get("year", 2026)) >= 2027


static func _add_total(cost: float) -> void:
	var file := ConfigFile.new()
	file.load(store_path)
	var total := float(file.get_value("spend", "total_usd", 0.0)) + cost
	file.set_value("spend", "total_usd", total)
	file.save(store_path)


static func _add_named(key: String, cost: float) -> void:
	var file := ConfigFile.new()
	file.load(store_path)
	var total := float(file.get_value("spend", key, 0.0)) + cost
	file.set_value("spend", key, total)
	file.save(store_path)
