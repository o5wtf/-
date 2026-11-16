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
var timeout_s: float = 45.0
var ping_timeout_s: float = 32.0
var min_interval_s: float = 1.0
var base_url: String = BASE_URL
## Модель, которая уже ответила в этой сессии. Следующий ход начинается с неё.
var session_model: String = ""

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
	ping_timeout_s = config.ping_timeout_s
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
	var chain := _chain(_model_for(request))
	var schema_field := "responseJsonSchema"
	var started := Time.get_ticks_msec()
	var last := _failure("bad_response", "Запрос к Gemini не завершился.")
	var tried := PackedStringArray()
	for model in chain:
		tried.append(model)
		var disable_thinking := bool(request.get("probe", false))
		var raise_tokens := false
		var server_attempts := 0
		var next_model := false
		while not next_model:
			await _pace()
			var call_started := Time.get_ticks_msec()
			var outcome: Dictionary = await _post(model, request, schema_field, not disable_thinking, raise_tokens)
			var transport_error := str(outcome.get("error", ""))
			if transport_error == "offline":
				return _with_meta(_failure("offline", "Нет сети. Проверьте подключение и повторите."), model, call_started)
			if transport_error == "timeout":
				last = _failure("timeout", "Модель «%s» не ответила за %d с." % [model, int(_timeout_for(request))])
				next_model = true
				break
			var status := int(outcome.get("status", 0))
			var body := _redact(str(outcome.get("body", "")))
			var google := _google_status(body)
			var reason := _google_reason(body)
			if status == 200:
				var parsed := _parse_success(body)
				if parsed.get("ok", false):
					session_model = model
					return _with_meta(parsed, model, call_started)
				if str(parsed.get("error", "")) == "truncated" and not disable_thinking:
					disable_thinking = true
					raise_tokens = true
					continue
				if str(parsed.get("error", "")) == "blocked" or str(parsed.get("error", "")) == "bad_response":
					return _with_meta(parsed, model, call_started)
				last = parsed
				next_model = true
				break
			if status == 400 and schema_field == "responseJsonSchema" and _is_schema_rejection(body):
				schema_field = "responseSchema"
				continue
			if _is_auth(status, google, reason):
				return _with_meta(_failure("auth", _with_reason("Ключ API отклонён.", reason)), model, call_started)
			if status == 404 or google == "NOT_FOUND":
				last = _failure("unavailable", _with_reason("Модель «%s» недоступна." % model, reason))
				next_model = true
				break
			if status == 429:
				last = _failure("rate_limited", _with_reason("Слишком много запросов к «%s»." % model, reason))
				next_model = true
				break
			if status == 503 or status == 502 or status == 504:
				last = _failure("overloaded", _with_reason("Модель «%s» перегружена." % model, reason))
				next_model = true
				break
			if status >= 500:
				server_attempts += 1
				if server_attempts < SERVER_ATTEMPTS:
					await _wait(SERVER_PAUSE_S)
					continue
				return _with_meta(_failure("server", _with_reason("Сервис Gemini временно недоступен.", reason)), model, call_started)
			if status == 400:
				if not disable_thinking and reason.to_lower().contains("thinking"):
					disable_thinking = true
					continue
				return _with_meta(_failure("rejected", _with_reason("Запрос отклонён.", reason)), model, call_started)
			last = _failure("bad_response", _with_reason("Неожиданный ответ сервиса.", reason))
			next_model = true
			break
	if tried.size() > 1:
		last["message"] = "%s Пробовали: %s." % [str(last.get("message", "")).strip_edges(), ", ".join(tried)]
	var last_model := tried[tried.size() - 1] if tried.size() > 0 else ""
	return _with_meta(last, last_model, started)


func _chain(primary: String) -> PackedStringArray:
	var chain := PackedStringArray()
	_push_model(chain, session_model)
	_push_model(chain, primary)
	_push_model(chain, LLMConfig.FAST_MODEL)
	_push_model(chain, fallback_model)
	_push_model(chain, LLMConfig.LITE_MODEL)
	if chain.is_empty() and primary != "":
		chain.append(primary)
	return chain


func _push_model(chain: PackedStringArray, model: String) -> void:
	var name := model.strip_edges()
	if name == "" or chain.has(name):
		return
	chain.append(name)


func _post(model: String, request: Dictionary, schema_field: String, use_thinking: bool, raise_tokens: bool) -> Dictionary:
	var url := "%s/%s:generateContent" % [base_url.trim_suffix("/"), model]
	var headers := {
		"Content-Type": "application/json",
		"x-goog-api-key": api_key,
	}
	var payload := JSON.stringify(_body(request, schema_field, use_thinking, raise_tokens))
	var pending: Variant = _transport.call("request", url, headers, payload, _timeout_for(request))
	if pending is Dictionary:
		return pending
	return await pending


func _timeout_for(request: Dictionary) -> float:
	if request.has("timeout_s"):
		return float(request["timeout_s"])
	if bool(request.get("probe", false)):
		return ping_timeout_s
	return timeout_s


func _body(request: Dictionary, schema_field: String, use_thinking: bool, raise_tokens: bool) -> Dictionary:
	var schema: Dictionary = request.get("schema", {})
	var tokens := int(request.get("max_output_tokens", 8192))
	if raise_tokens:
		tokens = maxi(tokens, 8192)
	var generation := {
		"responseMimeType": "application/json",
		schema_field: schema,
		"temperature": float(request.get("temperature", 0.9)),
		"maxOutputTokens": tokens,
	}
	if use_thinking:
		generation["thinkingConfig"] = {"thinkingLevel": thinking_level}
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
	if finish == "SAFETY" or finish == "PROHIBITED_CONTENT" or finish == "BLOCKLIST":
		return _failure("blocked", "Ответ заблокирован фильтром.")
	var text := _join_visible_text(candidate)
	var parsed: Variant = _parse_model_json(text)
	if finish == "MAX_TOKENS" and (parsed == null or parsed is not Dictionary):
		return _failure("truncated", "Ответ модели оборвался: не хватило места на текст.")
	if finish != "" and finish != "STOP" and finish != "MAX_TOKENS":
		return _failure("bad_response", "Ответ модели оборван или неполон.")
	if parsed == null or parsed is not Dictionary:
		return _failure("bad_response", "Текст ответа не является JSON-объектом.")
	return {
		"ok": true,
		"json": _normalize_reply(parsed),
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
		var body := part as Dictionary
		if body.get("thought", false) == true:
			continue
		var text := str(body.get("text", ""))
		if text == "":
			continue
		chunks.append(text)
	return "".join(chunks)


func _parse_model_json(text: String) -> Variant:
	var stripped := _strip_fences(text)
	var parsed: Variant = _parse_json(stripped)
	if parsed is Dictionary:
		return parsed
	return _parse_json(_extract_object(stripped))


func _strip_fences(text: String) -> String:
	var trimmed := text.strip_edges()
	if not trimmed.begins_with("```"):
		return trimmed
	var lines := trimmed.split("\n")
	if lines.size() >= 2 and lines[0].begins_with("```"):
		lines.remove_at(0)
	if lines.size() >= 1 and lines[lines.size() - 1].strip_edges() == "```":
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines).strip_edges()


func _extract_object(text: String) -> String:
	var start := text.find("{")
	var finish := text.rfind("}")
	if start < 0 or finish <= start:
		return text
	return text.substr(start, finish - start + 1)


func _normalize_reply(data: Dictionary) -> Dictionary:
	if not data.has("reply"):
		return data
	return ResponseValidator._normalize(data)


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


func _google_status(body: String) -> String:
	var parsed: Variant = _parse_json(body)
	if parsed is not Dictionary:
		return ""
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return ""
	return str((err as Dictionary).get("status", ""))


func _google_reason(body: String) -> String:
	var parsed: Variant = _parse_json(body)
	if parsed is not Dictionary:
		return ""
	var err: Variant = (parsed as Dictionary).get("error", {})
	if err is not Dictionary:
		return ""
	var message := _redact(str((err as Dictionary).get("message", ""))).strip_edges()
	var newline := message.find("\n")
	if newline > 0:
		message = message.substr(0, newline).strip_edges()
	if message.length() > 180:
		message = message.substr(0, 180).strip_edges()
	return message


func _is_auth(status: int, google: String, reason: String) -> bool:
	if status == 401 or status == 403:
		return true
	var blob := ("%s %s" % [google, reason]).to_lower()
	return blob.contains("api_key_invalid") or blob.contains("api key not valid") or blob.contains("permission_denied")


func _with_reason(lead: String, reason: String) -> String:
	if reason == "":
		return lead
	return "%s %s" % [lead, reason]


func _with_meta(result: Dictionary, model: String, started_ms: int) -> Dictionary:
	result["model"] = model
	result["elapsed_s"] = (Time.get_ticks_msec() - started_ms) / 1000.0
	result["message"] = _redact(str(result.get("message", "")))
	return result


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
	if trimmed.begins_with("{") and not trimmed.ends_with("}"):
		return null
	if trimmed.begins_with("[") and not trimmed.ends_with("]"):
		return null
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
