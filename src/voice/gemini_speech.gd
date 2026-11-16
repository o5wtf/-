class_name GeminiSpeech
extends Node
## Gemini TTS и расшифровка тем же ключом, что и диалог. Ключ в тело и логи не пишется.

const BASE_URL := "https://generativelanguage.googleapis.com/v1beta/models"
const DEFAULT_TTS_MODEL := "gemini-3.8-flash-lite-tts"
const TTS_MODELS: PackedStringArray = [
	"gemini-3.8-flash-lite-tts",
	"gemini-3.8-flash-tts",
	"gemini-3.1-flash-tts-preview",
	"gemini-2.5-flash-preview-tts",
]
const TRANSCRIBE_LITE := "gemini-3.5-flash-lite"
const TRANSCRIBE_MODEL := "gemini-3.5-transcribe"
const TRANSCRIBE_PROMPT := "Дословно расшифруй русскую речь. Верни только текст."
const TRANSCRIBE_TIMEOUT_S := 15.0
const SERVER_PAUSE_S := 2.0

var api_key: String = ""
var tts_model: String = DEFAULT_TTS_MODEL
var dialogue_model: String = LLMConfig.DEFAULT_DIALOGUE_MODEL
var timeout_s: float = 20.0
var min_interval_s: float = 1.0
var session_tts_model: String = ""
var base_url: String = BASE_URL

var _transport: Object = null
var _instant_wait: bool = false
var _clock_s: float = 0.0
var _last_request_s: float = -1.0
var _prompt: String = ""
var _voice_name: String = ""
var _wav: PackedByteArray = PackedByteArray()
var _use_thinking: bool = true


func set_transport(transport: Object) -> void:
	_transport = transport


func _ready() -> void:
	if _transport != null:
		return
	var http := Transport.new()
	add_child(http)
	_transport = http


func synthesize(reply: String, voice_name: String, emotion: String, remark: String, timeout: float = -1.0, style_mode: String = "") -> Dictionary:
	var mode := style_mode if style_mode != "" else VoiceProfiles.DEFAULT_STYLE_MODE
	_prompt = VoiceProfiles.style_prompt(reply, emotion, remark, mode)
	_voice_name = voice_name
	var chain := _chain(session_tts_model, tts_model, TTS_MODELS)
	var limit := timeout_s if timeout < 0.0 else timeout
	return await _walk(chain, limit, "tts", true)


func transcribe_wav(wav: PackedByteArray, timeout: float = -1.0) -> Dictionary:
	_wav = wav
	_use_thinking = true
	var chain := _chain("", TRANSCRIBE_LITE, PackedStringArray([TRANSCRIBE_MODEL, dialogue_model]))
	var limit := TRANSCRIBE_TIMEOUT_S if timeout < 0.0 else timeout
	return await _walk(chain, limit, "transcript", false)


func _walk(chain: PackedStringArray, limit: float, mode: String, remember: bool) -> Dictionary:
	if api_key.strip_edges() == "":
		return _failure("auth", "Не задан ключ API. Укажите его в настройках или в переменной GEMINI_API_KEY.")
	var last := _failure("bad_response", "Запрос к Gemini не завершился.")
	var tried: PackedStringArray = PackedStringArray()
	for model in chain:
		tried.append(model)
		var server_attempts := 0
		var advance := false
		while not advance:
			await _pace()
			var outcome: Dictionary = await _post(model, _body_for(mode, model), limit)
			var transport_error := str(outcome.get("error", ""))
			if transport_error == "offline":
				return _failure("offline", "Нет сети. Проверьте подключение и повторите.")
			if transport_error == "timeout":
				last = _failure("timeout", "Модель «%s» не ответила за %d с." % [model, int(limit)])
				advance = true
				break
			var status := int(outcome.get("status", 0))
			var body := _redact(str(outcome.get("body", "")))
			var google := _google_status(body)
			var reason := _google_reason(body)
			if status == 200:
				var parsed: Dictionary = _parse_mode(mode, body)
				if parsed.get("ok", false):
					if remember:
						session_tts_model = model
					parsed["model"] = model
					return parsed
				last = parsed
				advance = true
				break
			if _is_developer_instruction(status, reason):
				return _failure("rejected", _with_reason("Запрос отклонён.", reason))
			if mode == "transcript" and _retry_without_thinking(status, reason):
				continue
			if _is_auth(status, google, reason):
				return _failure("auth", _with_reason("Ключ API отклонён.", reason))
			if status == 404 or google == "NOT_FOUND":
				last = _failure("unavailable", _with_reason("Модель «%s» недоступна." % model, reason))
				advance = true
				break
			if status == 429:
				last = _failure("rate_limited", _with_reason("Слишком много запросов к «%s»." % model, reason))
				advance = true
				break
			if status == 503 or status == 502 or status == 504:
				last = _failure("overloaded", _with_reason("Модель «%s» перегружена." % model, reason))
				advance = true
				break
			if status >= 500:
				server_attempts += 1
				if server_attempts < 2:
					await _wait(SERVER_PAUSE_S)
					continue
				return _failure("server", _with_reason("Сервис Gemini временно недоступен.", reason))
			last = _failure("rejected", _with_reason("Запрос отклонён.", reason))
			advance = true
			break
	if tried.size() > 1:
		last["message"] = "%s Пробовали: %s." % [str(last.get("message", "")).strip_edges(), ", ".join(tried)]
	return last


func _chain(session_model: String, primary: String, extras: PackedStringArray) -> PackedStringArray:
	var chain := PackedStringArray()
	var names: Array = [session_model, primary]
	for extra in extras:
		names.append(extra)
	for item in names:
		var name := str(item).strip_edges()
		if name == "" or chain.has(name):
			continue
		chain.append(name)
	return chain


func _body_for(mode: String, model: String) -> Dictionary:
	if mode == "transcript":
		return _transcript_body(model)
	return _tts_body(_prompt, _voice_name)


func _parse_mode(mode: String, body: String) -> Dictionary:
	if mode == "transcript":
		return _parse_transcript(body)
	return _parse_audio(body)


func _is_developer_instruction(status: int, reason: String) -> bool:
	return status == 400 and reason.to_lower().contains("developer instruction")


func _retry_without_thinking(status: int, reason: String) -> bool:
	if status != 400 or not _use_thinking or not reason.to_lower().contains("thinking"):
		return false
	_use_thinking = false
	return true


func _tts_body(prompt: String, voice_name: String) -> Dictionary:
	return {
		"contents": [{"role": "user", "parts": [{"text": prompt}]}],
		"generationConfig": {
			"responseModalities": ["AUDIO"],
			"speechConfig": {
				"voiceConfig": {
					"prebuiltVoiceConfig": {"voiceName": voice_name},
				},
			},
		},
	}


func _transcript_body(model: String) -> Dictionary:
	var generation := {
		"temperature": 0.0,
		"maxOutputTokens": 512,
	}
	if _use_thinking and model != TRANSCRIBE_MODEL:
		generation["thinkingConfig"] = {"thinkingLevel": "MINIMAL"}
	return {
		"contents": [{"role": "user", "parts": [
			{"inlineData": {"mimeType": "audio/wav", "data": Marshalls.raw_to_base64(_wav)}},
			{"text": TRANSCRIBE_PROMPT},
		]}],
		"generationConfig": generation,
	}


func _post(model: String, payload: Dictionary, limit: float) -> Dictionary:
	var url := "%s/%s:generateContent" % [base_url.trim_suffix("/"), model]
	var headers := {
		"Content-Type": "application/json",
		"x-goog-api-key": api_key,
	}
	var pending: Variant = _transport.call("request", url, headers, JSON.stringify(payload), limit)
	if pending is Dictionary:
		return pending
	return await pending


func _parse_audio(body: String) -> Dictionary:
	var root = _parse_json(body)
	if root == null or root is not Dictionary:
		return _failure("bad_response", "Ответ синтеза не разобрался.")
	for part in _parts(root):
		var inline: Dictionary = _inline(part)
		if inline.is_empty():
			continue
		var audio := VoiceAudio.pcm_from_mime(str(inline.get("mime", "")), str(inline.get("data", "")))
		if not audio.get("ok", false):
			continue
		return {
			"ok": true,
			"pcm": audio["pcm"],
			"mix_rate": int(audio["mix_rate"]),
			"error": "",
			"message": "",
		}
	return _failure("bad_response", "В ответе синтеза нет звука.")


func _parse_transcript(body: String) -> Dictionary:
	var root = _parse_json(body)
	if root == null or root is not Dictionary:
		return _failure("bad_response", "Ответ расшифровки не разобрался.")
	var spoken := ""
	var plain := ""
	for part in _parts(root):
		if part.get("thought", false) == true:
			continue
		var heard := _audio_transcription(part)
		if heard != "":
			spoken = heard
		var text := str(part.get("text", "")).strip_edges()
		if text != "":
			plain = text
	if spoken != "":
		return _transcript_ok(spoken)
	if plain == "":
		return _failure("bad_response", "В ответе нет расшифровки.")
	var parsed: Variant = _parse_json(_extract_object(plain))
	if parsed is Dictionary and (parsed as Dictionary).has("transcript"):
		return _transcript_ok(str((parsed as Dictionary).get("transcript", "")))
	return _transcript_ok(plain)


func _audio_transcription(part: Dictionary) -> String:
	for key in ["audioTranscription", "audio_transcription"]:
		var body: Variant = part.get(key, {})
		if body is Dictionary:
			var text := str((body as Dictionary).get("text", "")).strip_edges()
			if text != "":
				return text
	return ""


func _transcript_ok(text: String) -> Dictionary:
	return {
		"ok": true,
		"transcript": text.strip_edges(),
		"error": "",
		"message": "",
	}


func _parts(root: Dictionary) -> Array:
	var candidates: Array = root.get("candidates", [])
	if candidates.is_empty() or candidates[0] is not Dictionary:
		return []
	var content: Dictionary = (candidates[0] as Dictionary).get("content", {})
	var parts: Variant = content.get("parts", [])
	return parts if parts is Array else []


func _inline(part: Dictionary) -> Dictionary:
	for key in ["inlineData", "inline_data"]:
		var inline: Variant = part.get(key, {})
		if inline is not Dictionary:
			continue
		var body := inline as Dictionary
		var data := str(body.get("data", ""))
		if data == "":
			continue
		var mime := str(body.get("mimeType", body.get("mime_type", "")))
		return {"mime": mime, "data": data}
	return {}


func _pace() -> void:
	if _last_request_s < 0.0 or min_interval_s <= 0.0:
		_last_request_s = _now()
		return
	var elapsed := _now() - _last_request_s
	if elapsed < min_interval_s:
		await _wait(min_interval_s - elapsed)
	_last_request_s = _now()


func _wait(seconds: float) -> void:
	if _instant_wait or seconds <= 0.0:
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


func _extract_object(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.begins_with("```"):
		var lines := trimmed.split("\n")
		if lines.size() >= 2 and lines[0].begins_with("```"):
			lines.remove_at(0)
		if lines.size() >= 1 and lines[lines.size() - 1].strip_edges() == "```":
			lines.remove_at(lines.size() - 1)
		trimmed = "\n".join(lines).strip_edges()
	var start := trimmed.find("{")
	var finish := trimmed.rfind("}")
	if start < 0 or finish <= start:
		return trimmed
	return trimmed.substr(start, finish - start + 1)


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


func _is_schema_rejection(body: String) -> bool:
	var lower := body.to_lower()
	if lower.contains("api_key") or lower.contains("api key"):
		return false
	return lower.contains("responsejsonschema") or lower.contains("unknown name") or lower.contains("invalid json payload")


func _with_reason(message: String, reason: String) -> String:
	if reason == "":
		return message
	return "%s %s" % [message, reason]


func _redact(text: String) -> String:
	var secret := api_key.strip_edges()
	if secret == "":
		return text
	return text.replace(secret, "[redacted]")


func _failure(error_code: String, message: String) -> Dictionary:
	return {"ok": false, "error": error_code, "message": _redact(message), "pcm": PackedByteArray(), "mix_rate": 0, "transcript": ""}


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
		var response_body: PackedByteArray = args[3]
		http.queue_free()
		if result_code == HTTPRequest.RESULT_TIMEOUT:
			return {"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"}
		if result_code != HTTPRequest.RESULT_SUCCESS:
			return {"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline"}
		return {"ok": true, "status": status, "body": response_body.get_string_from_utf8(), "headers": {}, "error": ""}
