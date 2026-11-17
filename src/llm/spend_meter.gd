class_name SpendMeter
extends RefCounted
## Расход по прайсу Gemini, paid tier. Ключ сюда не пишется.
## Цены за 1 млн токенов, USD, страница Google AI «Gemini API pricing» на 17 ноября 2026.
## Выход включает токены рассуждений. У gemini-3.6-flash до 31 декабря 2026 Introductory rate.

## Подменяется в тестах, чтобы не писать расход в настоящий user://config.cfg.
static var store_path: String = "user://config.cfg"


static var session_usd: float = 0.0


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
