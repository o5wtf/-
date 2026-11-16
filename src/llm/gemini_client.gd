class_name GeminiClient
extends LLMClient
## REST generateContent. Транспорт подменяется в тестах. Ключ в логи не попадает.

const BASE_URL := "https://generativelanguage.googleapis.com/v1beta/models"
const RATE_DELAYS: Array[float] = [2.0, 4.0, 8.0]
const SERVER_PAUSE_S := 2.0
const RATE_ATTEMPTS := 3
const SERVER_ATTEMPTS := 2

var api_key: String = ""
var dialogue_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var summary_model: String = LLMConfig.DEFAULT_SUMMARY_MODEL
var fallback_model: String = LLMConfig.DEFAULT_FALLBACK_MODEL
var thinking_level: String = "LOW"
var timeout_s: float = 30.0
var min_interval_s: float = 1.0
var base_url: String = BASE_URL

var _transport: Object = null
var _busy: bool = false
var _instant_wait: bool = false
var _clock_s: float = 0.0
var _last_request_s: float = -1.0
var waits: Array[float] = []

signal _released


func apply_config(config: LLMConfig) -> void:
	api_key = config.api_key
	dialogue_model = config.dialogue_model
	summary_model = config.summary_model
	fallback_model = config.fallback_model
	thinking_level = config.thinking_level
	timeout_s = config.timeout_s
	min_interval_s = config.min_interval_s


func set_transport(transport: Object) -> void:
	_transport = transport


func _ready() -> void:
	if _transport != null:
		return
	var http := Transport.new()
	add_child(http)
	_transport = http


func generate(request: Dictionary) -> Dictionary:
	while _busy:
		await _released
	_busy = true
	var result := await _generate_body(request)
	_busy = false
	_released.emit()
	finished.emit(result)
	return result


func _generate_body(request: Dictionary) -> Dictionary:
	if api_key.strip_edges() == "":
		return _failure("auth", "Не задан ключ API. Укажите его в настройках или в переменной GEMINI_API_KEY.")
	var model := _model_for(request)
	var schema_field := "responseJsonSchema"
	var tried_fallback := false
	while true:
		var rate_attempts := 0
		var server_attempts := 0
		var switch_model := false
		while true:
			await _pace()
			var outcome: Dictionary = await _post(model, request, schema_field)
			var transport_error := str(outcome.get("error", ""))
			if transport_error == "timeout":
				return _failure("timeout", "Нет ответа от Gemini за отведённое время.")
			if transport_error == "offline":
				return _failure("offline", "Нет сети. Проверьте подключение и повторите.")
			var status := int(outcome.get("status", 0))
			var body := _redact(str(outcome.get("body", "")))
			if status == 200:
				return _parse_success(body)
			if status == 400 and schema_field == "responseJsonSchema" and _is_schema_rejection(body):
				schema_field = "responseSchema"
				continue
			if status == 400 or status == 401 or status == 403:
				return _failure("auth", "Ключ API отклонён. Проверьте ключ в настройках.")
			if status == 429:
				rate_attempts += 1
				if rate_attempts >= RATE_ATTEMPTS:
					switch_model = true
					break
				await _wait(_retry_delay(outcome, rate_attempts))
				continue
			if status >= 500:
				server_attempts += 1
				if server_attempts >= SERVER_ATTEMPTS:
					return _failure("server", "Сервис Gemini временно недоступен.")
				await _wait(SERVER_PAUSE_S)
				continue
			return _failure("bad_response", "Неожиданный ответ сервиса.")
		if switch_model and not tried_fallback and fallback_model != "" and fallback_model != model:
			tried_fallback = true
			model = fallback_model
			continue
		return _failure("rate_limited", "Слишком много запросов. Подождите и повторите.")
	return _failure("bad_response", "Запрос к Gemini не завершился.")


func _post(model: String, request: Dictionary, schema_field: String) -> Dictionary:
	var url := "%s/%s:generateContent" % [base_url.trim_suffix("/"), model]
	var headers := {
		"Content-Type": "application/json",
		"x-goog-api-key": api_key,
	}
	var payload := JSON.stringify(_body(request, schema_field))
	var pending: Variant = _transport.call("request", url, headers, payload, timeout_s)
	if pending is Dictionary:
		return pending
	return await pending


func _body(request: Dictionary, schema_field: String) -> Dictionary:
	var schema: Dictionary = request.get("schema", {})
	var generation := {
		"responseMimeType": "application/json",
		schema_field: schema,
		"temperature": float(request.get("temperature", 0.9)),
		"maxOutputTokens": int(request.get("max_output_tokens", 2048)),
		"thinkingConfig": {"thinkingLevel": thinking_level},
	}
	return {
		"systemInstruction": {"parts": [{"text": str(request.get("system", ""))}]},
		"contents": [{"role": "user", "parts": [{"text": str(request.get("user", ""))}]}],
		"generationConfig": generation,
		"safetySettings": _safety_settings(),
	}


func _parse_success(body: String) -> Dictionary:
	var root = _parse_json(body)
	if root == null or root is not Dictionary:
		return _failure("bad_response", "Ответ Gemini не разобрался как JSON.")
	var data := root as Dictionary
	var feedback: Dictionary = data.get("promptFeedback", {})
	if str(feedback.get("blockReason", "")) != "":
		return _failure("blocked", "Запрос заблокирован фильтром.")
	var candidates: Array = data.get("candidates", [])
	if candidates.is_empty() or candidates[0] is not Dictionary:
		return _failure("bad_response", "В ответе Gemini нет кандидата.")
	var candidate := candidates[0] as Dictionary
	var finish := str(candidate.get("finishReason", "STOP"))
	var finish_error := _finish_error(finish)
	if finish_error != "":
		return _failure(finish_error, _finish_message(finish_error))
	var text := _join_visible_text(candidate)
	var parsed = _parse_json(text)
	if parsed == null or parsed is not Dictionary:
		return _failure("bad_response", "Текст ответа не является JSON-объектом.")
	return {
		"ok": true,
		"json": parsed,
		"raw_text": _redact(text),
		"error": "",
		"retry_after_s": 0.0,
		"message": "",
	}


func _join_visible_text(candidate: Dictionary) -> String:
	var content: Dictionary = candidate.get("content", {})
	var parts: Array = content.get("parts", [])
	var chunks: PackedStringArray = PackedStringArray()
	for part in parts:
		if part is not Dictionary:
			continue
		if (part as Dictionary).get("thought", false) == true:
			continue
		var text := str((part as Dictionary).get("text", ""))
		if text != "":
			chunks.append(text)
	return "".join(chunks)


func _finish_error(finish: String) -> String:
	if finish == "" or finish == "STOP":
		return ""
	if finish == "SAFETY" or finish == "PROHIBITED_CONTENT" or finish == "BLOCKLIST":
		return "blocked"
	return "bad_response"


func _finish_message(error_code: String) -> String:
	if error_code == "blocked":
		return "Ответ заблокирован фильтром."
	return "Ответ модели оборван или неполон."


func _retry_delay(outcome: Dictionary, attempt: int) -> float:
	var headers: Dictionary = outcome.get("headers", {})
	for key in headers:
		if str(key).to_lower() == "retry-after":
			var seconds := float(headers[key])
			if seconds > 0.0:
				return seconds
	var index := attempt - 1
	if index < 0:
		index = 0
	if index >= RATE_DELAYS.size():
		index = RATE_DELAYS.size() - 1
	return RATE_DELAYS[index]


func _is_schema_rejection(body: String) -> bool:
	var lower := body.to_lower()
	if lower.contains("api_key") or lower.contains("api key"):
		return false
	return lower.contains("responsejsonschema") or lower.contains("unknown name") or lower.contains("invalid json payload")


func _model_for(request: Dictionary) -> String:
	if str(request.get("model_role", "dialogue")) == "summary":
		return summary_model
	return dialogue_model


func _pace() -> void:
	if _last_request_s >= 0.0:
		var gap := _now() - _last_request_s
		if gap < min_interval_s:
			await _wait(min_interval_s - gap)
	_last_request_s = _now()


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	waits.append(seconds)
	if _instant_wait:
		_clock_s += seconds
		return
	await get_tree().create_timer(seconds).timeout


func _now() -> float:
	if _instant_wait:
		return _clock_s
	return Time.get_ticks_msec() / 1000.0


func _parse_json(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if not trimmed.begins_with("{") and not trimmed.begins_with("["):
		return null
	return JSON.parse_string(trimmed)


func _redact(text: String) -> String:
	var secret := api_key.strip_edges()
	if secret == "":
		return text
	return text.replace(secret, "[redacted]")


func _failure(error_code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"json": {},
		"raw_text": "",
		"error": error_code,
		"retry_after_s": 0.0,
		"message": message,
	}


func _safety_settings() -> Array:
	var settings: Array = []
	for category in [
		"HARM_CATEGORY_HARASSMENT",
		"HARM_CATEGORY_HATE_SPEECH",
		"HARM_CATEGORY_SEXUALLY_EXPLICIT",
		"HARM_CATEGORY_DANGEROUS_CONTENT",
	]:
		settings.append({"category": category, "threshold": "BLOCK_ONLY_HIGH"})
	return settings


class Transport:
	extends Node

	func request(url: String, headers: Dictionary, body: String, timeout_s: float) -> Dictionary:
		var http := HTTPRequest.new()
		http.timeout = timeout_s
		add_child(http)
		var lines: PackedStringArray = PackedStringArray()
		for key in headers:
			lines.append("%s: %s" % [str(key), str(headers[key])])
		var err := http.request(url, lines, HTTPClient.METHOD_POST, body)
		if err != OK:
			http.queue_free()
			return {"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"}
		var args: Array = await http.request_completed
		var result_code := int(args[0])
		var status := int(args[1])
		var response_headers: PackedStringArray = args[2]
		var response_body: PackedByteArray = args[3]
		http.queue_free()
		if result_code == HTTPRequest.RESULT_TIMEOUT:
			return {"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"}
		if result_code != HTTPRequest.RESULT_SUCCESS:
			return {"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"}
		return {
			"ok": true,
			"status": status,
			"body": response_body.get_string_from_utf8(),
			"headers": _header_map(response_headers),
			"error": "",
		}


	func _header_map(lines: PackedStringArray) -> Dictionary:
		var mapped := {}
		for line in lines:
			var parts := line.split(":", true, 1)
			if parts.size() == 2:
				mapped[parts[0].strip_edges()] = parts[1].strip_edges()
		return mapped
