class_name GeminiTtsBackend
extends SpeechBackend
## Gemini 3.8 Flash-Lite TTS. Поток PCM 24 кГц, воспроизведение с первого куска.
## При ошибке после повторов системный голос не включается: это решает очередь.


const MODEL := "gemini-3.8-flash-lite-tts"
const SAMPLE_RATE := 24000
const MAX_ATTEMPTS := 3
const INPUT_USD_PER_MILLION := 0.50
const OUTPUT_USD_PER_MILLION := 6.0

var transport: Object = null
var api_key: String = ""
var limiter: VoiceRateLimiter = VoiceRateLimiter.new()
var sink: Object = null
var _instant: bool = false
var _clock_s: float = 0.0
var _generation: int = 0
var _player: AudioStreamPlayer = null
var _playback: AudioStreamGeneratorPlayback = null
var _line_id: String = ""
var _started_line: bool = false


func _ready() -> void:
	keeps_failed_line = true
	if api_key == "":
		var config := LLMConfig.load_settings()
		api_key = config.api_key
	if transport == null:
		var live := GeminiTtsTransport.new()
		transport = live
		add_child(live)


func speak(line_id: String, text: String, voice_hint: String = "", style: String = "") -> void:
	var token := _generation
	var spoken := text.strip_edges()
	_line_id = line_id
	_started_line = false
	if spoken == "":
		speech_error.emit(line_id, "empty")
		return
	if api_key.strip_edges() == "":
		speech_error.emit(line_id, "auth")
		return
	var voice := voice_hint.strip_edges()
	if voice == "":
		voice = VoiceCast.FEMALE
	var attempt := 0
	while attempt < MAX_ATTEMPTS:
		if token != _generation:
			return
		var wait := limiter.delay_for(_now())
		if wait > 0.0:
			if _instant:
				_clock_s += wait
			else:
				await get_tree().create_timer(wait).timeout
		if token != _generation:
			return
		limiter.mark(_now())
		var result: Dictionary = await _send(spoken, voice, style)
		if token != _generation or str(result.get("error", "")) == "stopped":
			return
		if result.get("ok", false):
			_note_usage(result.get("usage", {}))
			if _started_line:
				finished.emit(line_id)
			else:
				speech_error.emit(line_id, "bad_response")
			return
		var kind := str(result.get("error", "bad_response"))
		attempt += 1
		if attempt >= MAX_ATTEMPTS or not _retries(kind):
			speech_error.emit(line_id, kind)
			return
		var pause := float(result.get("retry_after", 1.0))
		if pause < 0.0:
			pause = 1.0
		if _instant:
			_clock_s += pause
		else:
			await get_tree().create_timer(pause).timeout
	speech_error.emit(line_id, "bad_response")


func stop() -> void:
	_generation += 1
	_started_line = false
	_close_playback()
	if transport != null and transport.has_method("cancel"):
		transport.call("cancel")


func diagnostics() -> Dictionary:
	return {"has_feature": true, "voices": 0, "russian": 0, "voice_id": "", "error": ""}


static func build_request(text: String, voice_name: String, style: String) -> Dictionary:
	var body := {
		"contents": [{"role": "user", "parts": [{"text": text}]}],
		"generationConfig": {
			"responseModalities": ["AUDIO"],
			"speechConfig": {
				"voiceConfig": {
					"prebuiltVoiceConfig": {"voiceName": voice_name},
				},
			},
		},
	}
	var tone := style.strip_edges()
	if tone != "":
		body["speech_metadata"] = {"style": tone}
	return body


static func pcm16_to_frames(bytes: PackedByteArray) -> PackedVector2Array:
	var count := int(bytes.size() / 2)
	var frames := PackedVector2Array()
	frames.resize(count)
	for index in count:
		var sample := int(bytes[index * 2]) | (int(bytes[index * 2 + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		var amp := float(sample) / 32768.0
		frames[index] = Vector2(amp, amp)
	return frames


func _send(text: String, voice_name: String, style: String) -> Dictionary:
	var request := {
		"path": "/v1beta/models/%s:streamGenerateContent?alt=sse" % MODEL,
		"body": build_request(text, voice_name, style),
		"timeout_s": 30.0,
		"api_key": api_key,
		"on_chunk": _push_pcm,
	}
	var pending: Variant = transport.call("stream", request)
	if pending is Dictionary:
		return pending
	return await pending


func _push_pcm(bytes: PackedByteArray) -> void:
	if bytes.is_empty() or _line_id == "":
		return
	var frames := pcm16_to_frames(bytes)
	if frames.is_empty():
		return
	if not _started_line:
		_started_line = true
		_open_playback()
		started.emit(_line_id)
	if sink != null and sink.has_method("push"):
		sink.call("push", frames)
		return
	if _playback != null:
		_playback.push_buffer(frames)


func _open_playback() -> void:
	if sink != null:
		if sink.has_method("start"):
			sink.call("start")
		return
	if _player == null:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = SAMPLE_RATE
		generator.buffer_length = 0.4
		_player = AudioStreamPlayer.new()
		_player.stream = generator
		add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _close_playback() -> void:
	_playback = null
	if _player != null and is_instance_valid(_player):
		_player.stop()


func _note_usage(usage: Variant) -> void:
	if usage is not Dictionary:
		return
	var counts := usage as Dictionary
	var prompt := int(counts.get("promptTokenCount", counts.get("prompt", 0)))
	var output := int(counts.get("candidatesTokenCount", counts.get("output", 0)))
	SpendMeter.note(MODEL, prompt, 0, output)


func _retries(kind: String) -> bool:
	return kind == "rate_limited" or kind == "overloaded" or kind == "timeout"


func _now() -> float:
	if _instant:
		return _clock_s
	return Time.get_ticks_msec() / 1000.0


class GeminiTtsTransport:
	extends Node

	var cancelled: bool = false

	func cancel() -> void:
		cancelled = true

	func stream(request: Dictionary) -> Dictionary:
		cancelled = false
		var http := HTTPClient.new()
		var err := http.connect_to_host("generativelanguage.googleapis.com", 443, TLSOptions.client())
		if err != OK:
			return _outcome(false, 0, "offline", 0.0, {})
		var deadline := Time.get_ticks_msec() + int(float(request.get("timeout_s", 30.0)) * 1000.0)
		while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
			if cancelled:
				return _outcome(false, 0, "stopped", 0.0, {})
			if Time.get_ticks_msec() >= deadline:
				return _outcome(false, 0, "timeout", 1.0, {})
			http.poll()
			await get_tree().process_frame
		if http.get_status() != HTTPClient.STATUS_CONNECTED:
			return _outcome(false, 0, "offline", 0.0, {})
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"x-goog-api-key: %s" % str(request.get("api_key", "")),
		])
		err = http.request(HTTPClient.METHOD_POST, str(request.get("path", "")), headers, JSON.stringify(request.get("body", {})))
		if err != OK:
			return _outcome(false, 0, "offline", 0.0, {})
		while http.get_status() == HTTPClient.STATUS_REQUESTING:
			if cancelled:
				return _outcome(false, 0, "stopped", 0.0, {})
			if Time.get_ticks_msec() >= deadline:
				return _outcome(false, 0, "timeout", 1.0, {})
			http.poll()
			await get_tree().process_frame
		var status := http.get_response_code()
		var buffer := PackedByteArray()
		while http.get_status() == HTTPClient.STATUS_BODY:
			if cancelled:
				return _outcome(false, 0, "stopped", 0.0, {})
			if Time.get_ticks_msec() >= deadline:
				return _outcome(false, 0, "timeout", 1.0, {})
			http.poll()
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				buffer.append_array(chunk)
			else:
				await get_tree().process_frame
		var raw := buffer.get_string_from_utf8()
		if status != 200:
			return _outcome(false, status, _kind(status), _retry_after(raw), {})
		var usage := {}
		var on_chunk: Variant = request.get("on_chunk", Callable())
		for event in raw.split("\n\n", false):
			var data := _sse_data(event)
			if data == "" or data == "[DONE]":
				continue
			var parsed: Variant = JSON.parse_string(data)
			if parsed is not Dictionary:
				continue
			var root := parsed as Dictionary
			if root.has("usageMetadata") and root["usageMetadata"] is Dictionary:
				usage = root["usageMetadata"]
			for pcm in _audio_chunks(root):
				if on_chunk is Callable:
					(on_chunk as Callable).call(pcm)
		return _outcome(true, status, "", 0.0, usage)

	func _outcome(ok: bool, status: int, error_kind: String, retry_after: float, usage: Dictionary) -> Dictionary:
		return {"ok": ok, "status": status, "error": error_kind, "retry_after": retry_after, "usage": usage}

	func _sse_data(event: String) -> String:
		var lines: PackedStringArray = PackedStringArray()
		for line in event.split("\n"):
			if line.begins_with("data:"):
				lines.append(line.substr(5).strip_edges())
		return "\n".join(lines)

	func _audio_chunks(root: Dictionary) -> Array[PackedByteArray]:
		var found: Array[PackedByteArray] = []
		var candidates: Variant = root.get("candidates", [])
		if candidates is not Array:
			return found
		for candidate in candidates:
			if candidate is not Dictionary:
				continue
			var content: Variant = (candidate as Dictionary).get("content", {})
			if content is not Dictionary:
				continue
			var parts: Variant = (content as Dictionary).get("parts", [])
			if parts is not Array:
				continue
			for part in parts:
				if part is not Dictionary:
					continue
				var inline: Variant = (part as Dictionary).get("inlineData", {})
				if inline is not Dictionary:
					continue
				var encoded := str((inline as Dictionary).get("data", ""))
				if encoded == "":
					continue
				found.append(Marshalls.base64_to_raw(encoded))
		return found

	func _kind(status: int) -> String:
		if status == 429:
			return "rate_limited"
		if status == 503 or status == 502 or status == 504:
			return "overloaded"
		if status == 401 or status == 403:
			return "auth"
		return "bad_response"

	func _retry_after(body: String) -> float:
		var parsed: Variant = JSON.parse_string(body)
		if parsed is not Dictionary:
			return 1.0
		var err: Variant = (parsed as Dictionary).get("error", {})
		if err is not Dictionary:
			return 1.0
		var details: Variant = (err as Dictionary).get("details", [])
		if details is not Array:
			return 1.0
		for item in details:
			if item is not Dictionary:
				continue
			var info := item as Dictionary
			if not str(info.get("@type", "")).contains("RetryInfo"):
				continue
			var raw := str(info.get("retryDelay", "")).strip_edges()
			if raw.ends_with("ms"):
				return float(raw.trim_suffix("ms")) / 1000.0
			if raw.ends_with("s"):
				return float(raw.trim_suffix("s"))
		return 1.0
