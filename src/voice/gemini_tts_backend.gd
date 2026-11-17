class_name GeminiTtsBackend
extends SpeechBackend
## Gemini 3.8 Flash-Lite TTS. PCM 24 кГц начинается с первого целого сэмпла.
## События SSE разбираются по мере чтения тела. При ошибке после повторов
## системный голос не включается: это решает очередь.


const MODEL := "gemini-3.8-flash-lite-tts"
const SAMPLE_RATE := 24000
const BUFFER_SECONDS := 1.0
const PREFILL_SECONDS := 0.15
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
var _download_done: bool = false
var _device_capacity: int = 0
var _pcm_carry: PackedByteArray = PackedByteArray()
var _pending: PackedVector2Array = PackedVector2Array()


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
	_reset_audio()
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
		_reset_audio()
		var result: Dictionary = await _send(spoken, voice, style)
		if token != _generation or str(result.get("error", "")) == "stopped":
			return
		var status := int(result.get("status", 0))
		if result.get("ok", false):
			_note_usage(result.get("usage", {}))
			_download_done = true
			_maybe_open(true)
			if _started_line:
				await _wait_until_heard(token)
			else:
				var shown_status := status if status > 0 else 200
				speech_error.emit(line_id, format_voice_error("no_audio", shown_status, api_key))
			return
		var kind := str(result.get("error", "bad_response"))
		if kind == "":
			kind = "bad_response"
		if kind == "no_audio":
			_note_usage(result.get("usage", {}))
		attempt += 1
		_reset_audio()
		_close_playback()
		if attempt >= MAX_ATTEMPTS or not _retries(kind):
			speech_error.emit(line_id, format_voice_error(kind, status, api_key))
			return
		var pause := float(result.get("retry_after", 1.0))
		if pause < 0.0:
			pause = 1.0
		if _instant:
			_clock_s += pause
		else:
			await get_tree().create_timer(pause).timeout
	speech_error.emit(line_id, format_voice_error("bad_response", 0, api_key))


func stop() -> void:
	_generation += 1
	_reset_audio()
	_close_playback()
	if transport != null and transport.has_method("cancel"):
		transport.call("cancel")


func diagnostics() -> Dictionary:
	return {"has_feature": true, "voices": 0, "russian": 0, "voice_id": "", "error": ""}


static func build_request(text: String, voice_name: String, style: String) -> Dictionary:
	var part := {"text": text}
	var tone := style.strip_edges()
	if tone != "":
		part["speechMetadata"] = {"style": tone}
	return {
		"contents": [{"role": "user", "parts": [part]}],
		"generationConfig": {
			"responseModalities": ["AUDIO"],
			"speechConfig": {
				"voiceConfig": {
					"prebuiltVoiceConfig": {"voiceName": voice_name},
				},
			},
		},
	}


static func format_voice_error(kind: String, status: int, secret: String = "") -> String:
	var clean := kind.strip_edges()
	if clean == "":
		clean = "bad_response"
	var shown := clean
	if status > 0:
		shown = "%s http=%d" % [clean, status]
	var hidden := secret.strip_edges()
	if hidden.length() >= 8 and shown.contains(hidden):
		shown = shown.replace(hidden, "[redacted]")
	return shown


## Чтение тела только пока статус ещё BODY. Иначе движок печатает condition error.
static func body_chunk(status: int, reader: Callable) -> PackedByteArray:
	if status != HTTPClient.STATUS_BODY or not reader.is_valid():
		return PackedByteArray()
	var data: Variant = reader.call()
	if data is PackedByteArray:
		return data
	return PackedByteArray()


## Склеивает PCM16 между кусками. Нечётный хвост остаётся до следующего куска.
static func take_aligned(carry: PackedByteArray, incoming: PackedByteArray) -> Dictionary:
	var joined := PackedByteArray()
	joined.append_array(carry)
	joined.append_array(incoming)
	var even := joined.size() - (joined.size() % 2)
	return {"ready": joined.slice(0, even), "carry": joined.slice(even)}


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


func _process(_delta: float) -> void:
	if _line_id == "":
		return
	_feed()


func _push_pcm(bytes: PackedByteArray) -> void:
	if _line_id == "":
		return
	var aligned := take_aligned(_pcm_carry, bytes)
	_pcm_carry = aligned["carry"] as PackedByteArray
	var ready := aligned["ready"] as PackedByteArray
	if ready.is_empty():
		return
	var frames := pcm16_to_frames(ready)
	if frames.is_empty():
		return
	_pending.append_array(frames)
	_maybe_open(false)
	_feed()


func _maybe_open(download_finished: bool) -> void:
	if _started_line or _line_id == "" or _pending.is_empty():
		return
	var hardware := sink == null
	if hardware and not download_finished and _pending.size() < int(SAMPLE_RATE * PREFILL_SECONDS):
		return
	_started_line = true
	_open_playback()
	started.emit(_line_id)


func _feed() -> void:
	if not _started_line or _pending.is_empty():
		return
	var room := _frames_room()
	if room <= 0:
		return
	var count := mini(room, _pending.size())
	var batch := _pending.slice(0, count)
	_pending = _pending.slice(count)
	_write(batch)


func _frames_room() -> int:
	if sink != null:
		if sink.has_method("frames_available"):
			return maxi(int(sink.call("frames_available")), 0)
		return _pending.size()
	if _playback != null:
		return maxi(_playback.get_frames_available(), 0)
	return 0


func _device_buffered() -> int:
	if sink != null:
		if sink.has_method("buffered_frames"):
			return maxi(int(sink.call("buffered_frames")), 0)
		return 0
	if _playback == null:
		return 0
	var available := maxi(_playback.get_frames_available(), 0)
	if available > _device_capacity:
		_device_capacity = available
	if _device_capacity <= 0:
		return 1
	return maxi(_device_capacity - available, 0)


func _heard() -> bool:
	return _download_done and _pending.is_empty() and _device_buffered() == 0


func _wait_until_heard(token: int) -> void:
	var steps := 0
	while token == _generation:
		_maybe_open(true)
		_feed()
		if _heard():
			break
		steps += 1
		if steps > 100000:
			speech_error.emit(_line_id, "playback")
			return
		if _instant:
			if sink != null and sink.has_method("advance"):
				sink.call("advance")
			else:
				break
		else:
			await get_tree().process_frame
	if token != _generation or not _started_line or not _heard():
		return
	finished.emit(_line_id)


func _write(frames: PackedVector2Array) -> void:
	if frames.is_empty():
		return
	if sink != null and sink.has_method("push"):
		sink.call("push", frames)
		return
	if _playback != null:
		_playback.push_buffer(frames)


func _reset_audio() -> void:
	_started_line = false
	_download_done = false
	_device_capacity = 0
	_pcm_carry = PackedByteArray()
	_pending = PackedVector2Array()


func _open_playback() -> void:
	if sink != null:
		if sink.has_method("start"):
			sink.call("start")
		return
	if _player == null:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = SAMPLE_RATE
		generator.buffer_length = BUFFER_SECONDS
		_player = AudioStreamPlayer.new()
		_player.stream = generator
		add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback != null:
		_device_capacity = _playback.get_frames_available()


func _close_playback() -> void:
	_playback = null
	_device_capacity = 0
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
		var decoder: GeminiSseDecoder = null
		var error_body := PackedByteArray()
		if status == 200:
			decoder = GeminiSseDecoder.new()
		var on_chunk: Variant = request.get("on_chunk", Callable())
		while http.get_status() == HTTPClient.STATUS_BODY:
			if cancelled:
				return _outcome(false, status, "stopped", 0.0, {})
			if Time.get_ticks_msec() >= deadline:
				return _outcome(false, status, "timeout", 1.0, {})
			http.poll()
			var chunk := _take_chunk(http)
			if chunk.is_empty():
				if http.get_status() != HTTPClient.STATUS_BODY:
					break
				await get_tree().process_frame
				continue
			while not chunk.is_empty():
				if decoder == null:
					error_body.append_array(chunk)
				else:
					for pcm in decoder.push(chunk):
						_emit_pcm(on_chunk, pcm)
				chunk = _take_chunk(http)
		if decoder == null:
			var raw := error_body.get_string_from_utf8()
			return _outcome(false, status, _kind(status), _retry_after(raw), {})
		for pcm in decoder.finish():
			_emit_pcm(on_chunk, pcm)
		if decoder.audio_parts == 0:
			return _outcome(false, status, "no_audio", 0.0, decoder.usage)
		return _outcome(true, status, "", 0.0, decoder.usage)

	func _outcome(ok: bool, status: int, error_kind: String, retry_after: float, usage: Dictionary) -> Dictionary:
		return {"ok": ok, "status": status, "error": error_kind, "retry_after": retry_after, "usage": usage}

	func _take_chunk(http: HTTPClient) -> PackedByteArray:
		return GeminiTtsBackend.body_chunk(http.get_status(), Callable(http, "read_response_body_chunk"))

	func _emit_pcm(on_chunk: Variant, pcm: PackedByteArray) -> void:
		if pcm.is_empty() or on_chunk is not Callable:
			return
		(on_chunk as Callable).call(pcm)

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
