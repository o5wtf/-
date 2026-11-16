class_name GeminiLive
extends Node
## Сессия Gemini Live (WebSocket). Ключ в адрес и заголовок не печатается.
## Разбор сообщений не требует сети и проверяется тестами.

const ENDPOINT := "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
const SPEAK_MODELS: PackedStringArray = [
	"gemini-3.8-live",
	"gemini-3.1-flash-live-preview",
	"gemini-2.5-flash-native-audio-preview-12-2025",
]
const LISTEN_MODELS: PackedStringArray = [
	"gemini-3.5-transcribe-live",
]
const CONNECT_MS := 4000
const FIRST_AUDIO_MS := 12000
## Удержание кнопки: сервер не режет фразу сам. 500 мс — нижняя граница, если VAD включат снова.
const SILENCE_DURATION_MS := 500
const PUSH_TO_TALK := {
	"disabled": true,
}

## Тесты выключают сеть: тогда сессия сразу отвечает «недоступна», без сокета.
static var network_enabled: bool = true

signal audio_chunk(pcm: PackedByteArray, mix_rate: int)
signal partial_text(text: String)
signal final_text(text: String)
signal playback_reset

var _peer: WebSocketPeer = null
var _api_key: String = ""
var _closed: bool = true
var _session_key: String = ""
var _resume_handle: String = ""
var _go_away: bool = false
var _setup_sent: bool = false
var _segments: PackedStringArray = PackedStringArray()
var _turn_done: bool = false
var _listen_language: String = "ru-RU"
var _listen_vocab: PackedStringArray = PackedStringArray()


static func parse_server(raw: String) -> Array:
	var events: Array = []
	var data = JSON.parse_string(raw)
	if data is not Dictionary:
		return events
	var body := data as Dictionary
	if body.has("setupComplete") or body.has("setup_complete"):
		events.append({"kind": "setup"})
	if body.has("goAway") or body.has("go_away"):
		events.append({"kind": "go_away"})
	var update: Variant = body.get("sessionResumptionUpdate", body.get("session_resumption_update", {}))
	if update is Dictionary:
		var handle := str((update as Dictionary).get("newHandle", (update as Dictionary).get("new_handle", ""))).strip_edges()
		if handle != "" and (update as Dictionary).get("resumable", true) != false:
			events.append({"kind": "resume", "handle": handle})
	if body.has("error"):
		events.append(_error_event(body["error"]))
		return events
	var server: Variant = body.get("serverContent", body.get("server_content", {}))
	if server is not Dictionary:
		return events
	var content := server as Dictionary
	var turn: Variant = content.get("modelTurn", content.get("model_turn", {}))
	if turn is Dictionary:
		var parts: Variant = (turn as Dictionary).get("parts", [])
		if parts is Array:
			for part in parts:
				if part is not Dictionary:
					continue
				var audio := _inline_audio(part as Dictionary)
				if not audio.is_empty():
					events.append(audio)
	var interim := _transcript_text(content, "interimInputTranscription", "interim_input_transcription")
	if interim != "":
		events.append({"kind": "interim", "text": interim})
	var final_text := _transcript_text(content, "inputTranscription", "input_transcription")
	if final_text != "":
		events.append({"kind": "transcript", "text": final_text})
	var spoken := _transcript_text(content, "outputTranscription", "output_transcription")
	if spoken != "":
		events.append({"kind": "output_transcript", "text": spoken})
	if content.get("generationComplete", content.get("generation_complete", false)) == true:
		events.append({"kind": "generation_complete"})
	if content.get("turnComplete", content.get("turn_complete", false)) == true:
		events.append({"kind": "turn_complete"})
	return events


static func setup_message(model: String, voice_name: String, listen: bool, emotion: String = "", remark: String = "", handle: String = "", language: String = "ru-RU", vocabulary: PackedStringArray = PackedStringArray()) -> Dictionary:
	var generation := {"responseModalities": ["TEXT" if listen else "AUDIO"]}
	if not listen and voice_name != "":
		generation["speechConfig"] = {
			"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice_name}},
		}
	var setup := {
		"model": "models/%s" % model,
		"generationConfig": generation,
	}
	var resume := {}
	if handle.strip_edges() != "":
		resume["handle"] = handle.strip_edges()
	setup["sessionResumption"] = resume
	setup["contextWindowCompression"] = {"slidingWindow": {}}
	if listen:
		var transcription := {"languageCodes": [language if language != "" else "ru-RU"]}
		if not vocabulary.is_empty():
			transcription["customVocabulary"] = vocabulary
		setup["inputAudioTranscription"] = transcription
		setup["realtimeInputConfig"] = {"automaticActivityDetection": PUSH_TO_TALK}
	else:
		setup["outputAudioTranscription"] = {}
		setup["systemInstruction"] = {"parts": [{"text": VoiceProfiles.live_instruction(emotion, remark)}]}
	return {"setup": setup}


static func session_key(model: String, voice_name: String, listen: bool, emotion: String, remark: String) -> String:
	if listen:
		return "listen|%s" % model
	return "speak|%s|%s|%s" % [model, voice_name, VoiceProfiles.live_instruction(emotion, remark)]


static func can_resume(previous_key: String, next_key: String, handle: String) -> bool:
	return previous_key != "" and previous_key == next_key and handle.strip_edges() != ""


static func normalize_speech(text: String) -> String:
	var folded := text.to_lower().replace("ё", "е")
	var kept := ""
	for index in folded.length():
		var ch := folded.substr(index, 1)
		if ch == " " or ch == "\n" or ch == "\t":
			kept += " "
		elif _is_letter_or_digit(ch):
			kept += ch
	return " ".join(kept.split(" ", false))


static func verbatim_ok(expected: String, heard: String) -> bool:
	var left := normalize_speech(expected)
	var right := normalize_speech(heard)
	if left == "" or right == "":
		return false
	if left == right:
		return true
	var limit := maxi(2, int(float(left.length()) * 0.15))
	return _distance(left, right) <= limit


static func should_fallback(had_audio: bool, turn_done: bool, heard: String, expected: String) -> bool:
	if not had_audio or not turn_done:
		return true
	if heard.strip_edges() == "":
		return false
	return not verbatim_ok(expected, heard)


static func socket_url() -> String:
	return ENDPOINT


static func classify_close(code: int, reason: String) -> Dictionary:
	var blob := reason.to_lower()
	if code == 1008 or blob.contains("api key"):
		return {"error": "auth", "message": reason}
	if blob.contains("quota") or blob.contains("resource_exhausted"):
		return {"error": "rate_limited", "message": reason}
	if code == 1007:
		return {"error": "unavailable", "message": reason}
	return {"error": "offline", "message": reason}


static func join_transcripts(parts: PackedStringArray) -> String:
	var clean := PackedStringArray()
	for part in parts:
		var text := str(part).strip_edges()
		if text != "":
			clean.append(text)
	return " ".join(clean)


static func collect_transcript(existing: PackedStringArray, events: Array) -> Dictionary:
	var parts := existing.duplicate()
	var done := false
	var interim := ""
	for event in events:
		var kind := str(event.get("kind", ""))
		if kind == "transcript":
			var text := str(event.get("text", "")).strip_edges()
			if text != "":
				parts.append(text)
		elif kind == "interim":
			interim = str(event.get("text", "")).strip_edges()
		elif kind == "turn_complete" or kind == "generation_complete":
			done = true
	var caption := parts.duplicate()
	if interim != "":
		caption.append(interim)
	return {"parts": parts, "done": done, "text": join_transcripts(parts), "caption": join_transcripts(caption)}


static func activity_start() -> Dictionary:
	return {"realtimeInput": {"activityStart": {}}}


static func activity_end() -> Dictionary:
	return {"realtimeInput": {"activityEnd": {}}}


static func line_message(line: String) -> Dictionary:
	return {
		"clientContent": {
			"turns": [{"role": "user", "parts": [{"text": line}]}],
			"turnComplete": true,
		},
	}


static func audio_message(pcm: PackedByteArray) -> Dictionary:
	return {
		"realtimeInput": {
			"audio": {
				"mimeType": "audio/pcm;rate=16000",
				"data": Marshalls.raw_to_base64(pcm),
			},
		},
	}


func speak_line(api_key: String, line: String, voice_name: String, emotion: String = "neutral", remark: String = "") -> Dictionary:
	if api_key.strip_edges() == "":
		return _fail("auth", "Не задан ключ API. Укажите его в настройках или в переменной GEMINI_API_KEY.")
	if not network_enabled:
		return _fail("unavailable", "Live отключён.")
	var last := _fail("unavailable", "Live-сессия не открылась.")
	for model in SPEAK_MODELS:
		playback_reset.emit()
		var result := await _speak_model(api_key, model, line, voice_name, emotion, remark)
		if result.get("ok", false):
			return result
		last = result
		if str(result.get("error", "")) == "auth":
			return result
		_close()
	return last


func prepare_socket(api_key: String) -> void:
	if api_key.strip_edges() == "" or not network_enabled:
		return
	if _peer != null and (_peer.get_ready_state() == WebSocketPeer.STATE_OPEN or _peer.get_ready_state() == WebSocketPeer.STATE_CONNECTING):
		return
	_begin_connect(api_key)


func listen_open(api_key: String, language: String = "ru-RU", vocabulary: PackedStringArray = PackedStringArray()) -> Dictionary:
	if api_key.strip_edges() == "":
		return _fail("auth", "Не задан ключ API. Укажите его в настройках или в переменной GEMINI_API_KEY.")
	if not network_enabled:
		return _fail("unavailable", "Live отключён.")
	_listen_language = language if language != "" else "ru-RU"
	_listen_vocab = vocabulary
	_segments = PackedStringArray()
	_turn_done = false
	var last := _fail("unavailable", "Live-сессия не открылась.")
	for model in LISTEN_MODELS:
		var opened := await _open(api_key, model, "", true)
		if opened.get("ok", false):
			return {"ok": true, "model": model, "error": "", "message": ""}
		last = opened
		if str(opened.get("error", "")) == "auth":
			return opened
		_close()
	return last


func listen_audio(pcm16k: PackedByteArray) -> void:
	if _closed or pcm16k.is_empty():
		return
	_send(audio_message(pcm16k))
	_absorb(_drain_packets())


func listen_finish() -> String:
	if _closed:
		return join_transcripts(_segments)
	_send(activity_end())
	var started := Time.get_ticks_msec()
	while not _turn_done and Time.get_ticks_msec() - started < 4000:
		if _socket_closed():
			break
		_absorb(_drain_packets())
		if _turn_done:
			break
		await get_tree().process_frame
	var text := join_transcripts(_segments)
	_segments = PackedStringArray()
	_turn_done = false
	_close()
	return text


func _absorb(events: Array) -> void:
	var collected := collect_transcript(_segments, events)
	_segments = collected["parts"]
	_turn_done = _turn_done or bool(collected["done"])
	var caption := str(collected["caption"])
	if caption != "":
		partial_text.emit(caption)


func _speak_model(api_key: String, model: String, line: String, voice_name: String, emotion: String, remark: String) -> Dictionary:
	var opened := await _open(api_key, model, voice_name, false, emotion, remark)
	if not opened.get("ok", false):
		return opened
	var spoken_line := VoiceProfiles.spoken_text(line)
	_send(line_message(VoiceProfiles.marked_line(spoken_line)))
	var pcm := PackedByteArray()
	var rate := 24000
	var heard := ""
	var started := Time.get_ticks_msec()
	var limit := FIRST_AUDIO_MS
	var done := false
	while Time.get_ticks_msec() - started < limit:
		for event in _drain_packets():
			var kind := str(event.get("kind", ""))
			if kind == "audio":
				var chunk: PackedByteArray = event.get("pcm", PackedByteArray())
				pcm.append_array(chunk)
				rate = int(event.get("mix_rate", 24000))
				limit = maxi(limit, 20000)
			elif kind == "output_transcript":
				heard = str(event.get("text", ""))
			elif kind == "turn_complete" or kind == "generation_complete":
				done = true
			elif kind == "error":
				_drop_session()
				return _fail(str(event.get("error", "server")), str(event.get("message", "")))
		if done:
			break
		if _socket_closed():
			_drop_session()
			return _fail_closed(model)
		await get_tree().process_frame
	if should_fallback(not pcm.is_empty(), done, heard, spoken_line):
		_drop_session()
		return _fail("bad_response", "Модель «%s» не повторила реплику." % model)
	var offset := 0
	var piece := 4800
	while offset < pcm.size():
		var count := mini(piece, pcm.size() - offset)
		audio_chunk.emit(pcm.slice(offset, offset + count), rate)
		offset += count
	if _go_away:
		var kept_handle := _resume_handle
		var kept_key := _session_key
		_close()
		_resume_handle = kept_handle
		_session_key = kept_key
	return {"ok": true, "pcm": pcm, "mix_rate": rate, "model": model, "error": "", "message": ""}


func _open(api_key: String, model: String, voice_name: String, listen: bool, emotion: String = "", remark: String = "") -> Dictionary:
	var key := session_key(model, voice_name, listen, emotion, remark)
	if _reusable(key):
		return {"ok": true, "error": "", "message": ""}
	var handle := ""
	if can_resume(_session_key, key, _resume_handle):
		handle = _resume_handle
	else:
		_resume_handle = ""
	var keep_socket := _peer != null and not _setup_sent and not _go_away and (_peer.get_ready_state() == WebSocketPeer.STATE_CONNECTING or _peer.get_ready_state() == WebSocketPeer.STATE_OPEN)
	if not keep_socket:
		_close()
		if not _begin_connect(api_key):
			return _fail("offline", "Нет сети. Проверьте подключение и повторите.")
	_session_key = key
	var started := Time.get_ticks_msec()
	while _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_peer.poll()
		if _socket_closed():
			return _fail_closed(model)
		if Time.get_ticks_msec() - started > CONNECT_MS:
			_close()
			return _fail("timeout", "Модель «%s» не ответила за %d с." % [model, int(CONNECT_MS / 1000.0)])
		await get_tree().process_frame
	if _socket_closed():
		return _fail_closed(model)
	if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_close()
		return _fail("offline", "Нет сети. Проверьте подключение и повторите.")
	_send(setup_message(model, voice_name, listen, emotion, remark, handle, _listen_language, _listen_vocab))
	_setup_sent = true
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < CONNECT_MS:
		if _socket_closed():
			return _fail_closed(model)
		for event in _drain_packets():
			var kind := str(event.get("kind", ""))
			if kind == "setup":
				if listen:
					_send(activity_start())
				return {"ok": true, "error": "", "message": ""}
			if kind == "error":
				_close()
				return _fail(str(event.get("error", "server")), str(event.get("message", "")))
		await get_tree().process_frame
	_close()
	return _fail("timeout", "Модель «%s» не ответила за %d с." % [model, int(CONNECT_MS / 1000.0)])


func _begin_connect(api_key: String) -> bool:
	_api_key = api_key
	_closed = false
	_setup_sent = false
	_peer = WebSocketPeer.new()
	_peer.handshake_headers = PackedStringArray(["x-goog-api-key: %s" % api_key])
	_peer.outbound_buffer_size = 1024 * 1024
	_peer.inbound_buffer_size = 2 * 1024 * 1024
	return _peer.connect_to_url(socket_url()) == OK


func _socket_closed() -> bool:
	return _peer == null or _peer.get_ready_state() == WebSocketPeer.STATE_CLOSED


func _fail_closed(model: String) -> Dictionary:
	var code := 0
	var reason := ""
	if _peer != null:
		code = _peer.get_close_code()
		reason = _redact(_peer.get_close_reason())
	var mapped := classify_close(code, reason)
	_close()
	var message := str(mapped.get("message", ""))
	if message == "":
		message = "Модель «%s» закрыла соединение." % model
	return _fail(str(mapped.get("error", "offline")), message)


func _send(payload: Dictionary) -> void:
	if _peer == null:
		return
	_peer.poll()
	_peer.send_text(JSON.stringify(payload))


func _drain_packets() -> Array:
	var events: Array = []
	if _peer == null:
		return events
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var packet := _peer.get_packet()
		var text := packet.get_string_from_utf8()
		for event in parse_server(text):
			events.append(event)
			var kind := str(event.get("kind", ""))
			if kind == "interim":
				partial_text.emit(str(event.get("text", "")))
			elif kind == "transcript":
				final_text.emit(str(event.get("text", "")))
			elif kind == "resume":
				_resume_handle = str(event.get("handle", ""))
			elif kind == "go_away":
				_go_away = true
	return events


func _reusable(key: String) -> bool:
	return _setup_sent and not _closed and not _go_away and _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN and _session_key == key


func _drop_session() -> void:
	_resume_handle = ""
	_session_key = ""
	_close()


func _close() -> void:
	_closed = true
	_go_away = false
	_setup_sent = false
	if _peer != null:
		_peer.close()
		_peer = null


func _fail(kind: String, message: String) -> Dictionary:
	return {"ok": false, "error": kind, "message": _redact(message), "pcm": PackedByteArray(), "mix_rate": 0}


func _redact(text: String) -> String:
	var secret := _api_key.strip_edges()
	if secret == "":
		return text
	return text.replace(secret, "[redacted]")


static func _is_letter_or_digit(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or (ch >= "а" and ch <= "я")


static func _distance(left: String, right: String) -> int:
	var width := right.length() + 1
	var row: Array = []
	row.resize(width)
	for index in width:
		row[index] = index
	for i in left.length():
		var next: Array = []
		next.resize(width)
		next[0] = i + 1
		for j in right.length():
			var cost := 0 if left.substr(i, 1) == right.substr(j, 1) else 1
			next[j + 1] = mini(mini(int(next[j]) + 1, int(row[j + 1]) + 1), int(row[j]) + cost)
		row = next
	return int(row[width - 1])


static func _transcript_text(content: Dictionary, camel: String, snake: String) -> String:
	var body: Variant = content.get(camel, content.get(snake, {}))
	if body is String:
		return str(body).strip_edges()
	if body is Dictionary:
		return str((body as Dictionary).get("text", "")).strip_edges()
	return ""


static func _inline_audio(part: Dictionary) -> Dictionary:
	for key in ["inlineData", "inline_data"]:
		var inline: Variant = part.get(key, {})
		if inline is not Dictionary:
			continue
		var data := str((inline as Dictionary).get("data", ""))
		if data == "":
			continue
		var mime := str((inline as Dictionary).get("mimeType", (inline as Dictionary).get("mime_type", "audio/pcm;rate=24000")))
		var audio := VoiceAudio.pcm_from_mime(mime, data)
		if not audio.get("ok", false):
			continue
		return {"kind": "audio", "pcm": audio["pcm"], "mix_rate": int(audio.get("mix_rate", 24000))}
	return {}


static func _error_event(err: Variant) -> Dictionary:
	var status := ""
	var message := ""
	var code := 0
	if err is Dictionary:
		status = str((err as Dictionary).get("status", ""))
		message = str((err as Dictionary).get("message", ""))
		code = int((err as Dictionary).get("code", 0))
	else:
		message = str(err)
	var blob := ("%s %s" % [status, message]).to_lower()
	var kind := "server"
	if code == 401 or code == 403 or blob.contains("api key") or blob.contains("api_key"):
		kind = "auth"
	elif code == 429 or blob.contains("resource_exhausted") or blob.contains("quota"):
		kind = "rate_limited"
	elif code == 404 or blob.contains("not_found") or blob.contains("not found"):
		kind = "unavailable"
	return {"kind": "error", "error": kind, "message": message.strip_edges()}
