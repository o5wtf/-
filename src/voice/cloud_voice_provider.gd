class_name CloudVoiceProvider
extends VoiceProvider
## Gemini TTS и расшифровка речи тем же ключом. Запросы синтеза идут по одному.

var speech: GeminiSpeech
var live: GeminiLive
var mic: Object = null
var speaker: PcmSpeaker
var _live_input: bool = false
var _live_streaming: bool = false
var _live_pitch: float = 1.0
var _live_volume: float = 1.0
var _listen_language: String = "ru-RU"
var _mic_released_ms: int = 0
var _speak_started_ms: int = 0
var _logged_audio: bool = false
var _audio_engine: String = VoiceRoute.LIVE
var _measure_audio: bool = false
var _route := VoiceRoute.new()
var _listen_pump: Variant = null
var _queue: Array = []
var _draining: bool = false
var _pending_wav: PackedByteArray = PackedByteArray()
var _next_id: int = 1
var _listening: bool = false


func _ready() -> void:
	if speech == null:
		speech = GeminiSpeech.new()
		var config := LLMConfig.load_settings()
		speech.api_key = config.api_key
		speech.dialogue_model = config.dialogue_model
		speech.tts_model = _tts_model()
	if speech.get_parent() == null:
		add_child(speech)
	if live == null:
		live = GeminiLive.new()
	if live.get_parent() == null:
		add_child(live)
	if not live.partial_text.is_connected(_on_partial):
		live.partial_text.connect(_on_partial)
	if not live.playback_reset.is_connected(_on_playback_reset):
		live.playback_reset.connect(_on_playback_reset)
	if speaker == null:
		speaker = PcmSpeaker.new()
	if speaker.get_parent() == null:
		add_child(speaker)
	if mic == null:
		mic = MicRecorder.new()
	if mic is Node and (mic as Node).get_parent() == null:
		add_child(mic)


func is_tts_available() -> bool:
	return true


func is_stt_available() -> bool:
	return true


func is_listening() -> bool:
	return _listening


func speak(text: String, profile: VoiceProfiles.Profile, emotion: String, remark: String = "") -> int:
	var line := VoiceProfiles.spoken_text(text)
	if line == "":
		return -1
	var utterance_id := _next_id
	_next_id += 1
	_queue.append({
		"id": utterance_id,
		"text": line,
		"profile": profile,
		"emotion": emotion,
		"remark": remark,
	})
	if not _draining:
		_draining = true
		Callable(self, "_drain").call_deferred()
	_speak_started_ms = Time.get_ticks_msec()
	_logged_audio = false
	_measure_audio = false
	return utterance_id


func stop_speaking() -> void:
	_queue.clear()
	if speaker != null:
		speaker.stop()


func prepare_connection() -> void:
	if speech == null or live == null:
		return
	live.prepare_socket(speech.api_key)


func start_listening(language: String = "ru-RU") -> void:
	if _listening:
		return
	if not _mic_allowed():
		voice_error.emit("permission", "Нет доступа к микрофону. Вопрос можно набрать текстом.")
		return
	var started: Dictionary = mic.call("start")
	if not started.get("ok", false):
		voice_error.emit("permission", str(started.get("message", "Не удалось включить микрофон.")))
		return
	_listening = true
	_listen_language = language if language != "" else "ru-RU"
	Callable(self, "_open_live_input").call_deferred()


func stop_listening() -> void:
	if not _listening:
		return
	_listening = false
	_mic_released_ms = Time.get_ticks_msec()
	if _live_input:
		Callable(self, "_finish_live_input").call_deferred()
		return
	_finish_recorded_input()


func _open_live_input() -> void:
	if not _listening:
		return
	if not GeminiLive.network_enabled or speech.api_key.strip_edges() == "":
		return
	var opened: Dictionary = await live.listen_open(speech.api_key, _listen_language, _vocabulary())
	if not _listening:
		live._close()
		return
	_live_input = opened.get("ok", false)
	if _live_input:
		await _pump_live_input()


func _pump_live_input() -> void:
	while _listening and _live_input:
		if mic.has_method("pull_new"):
			var fresh: Dictionary = mic.call("pull_new")
			var chunk: PackedByteArray = fresh.get("pcm", PackedByteArray())
			var ready := VoiceAudio.to_pcm16k(chunk, int(fresh.get("mix_rate", 16000)), bool(fresh.get("stereo", false)))
			if ready.size() >= 2:
				live.listen_audio(ready)
		await get_tree().create_timer(0.08).timeout


func _finish_live_input() -> void:
	if mic.has_method("pull_new"):
		var fresh: Dictionary = mic.call("pull_new")
		var ready := VoiceAudio.to_pcm16k(fresh.get("pcm", PackedByteArray()), int(fresh.get("mix_rate", 16000)), bool(fresh.get("stereo", false)))
		if ready.size() >= 2:
			live.listen_audio(ready)
	var heard: String = await live.listen_finish()
	_live_input = false
	if _mic_released_ms > 0:
		TurnTiming.span("mic_to_text", _mic_released_ms)
	if heard.strip_edges() != "":
		if mic.has_method("stop"):
			mic.call("stop")
		transcript_ready.emit(heard, true)
		return
	_finish_recorded_input()


func _finish_recorded_input() -> void:
	var clip: Dictionary = mic.call("stop")
	if not clip.get("ok", false):
		voice_error.emit("unsupported", "Не удалось записать звук.")
		return
	var pcm: PackedByteArray = clip.get("pcm", PackedByteArray())
	var prepared := VoiceAudio.prepare_for_upload(pcm, int(clip.get("mix_rate", 16000)), bool(clip.get("stereo", false)))
	if prepared.size() < 2:
		voice_error.emit("unsupported", "Запись слишком короткая.")
		return
	_pending_wav = VoiceAudio.wav_bytes(prepared, VoiceAudio.UPLOAD_RATE, false)
	Callable(self, "_publish_transcript").call_deferred()


func _publish_transcript() -> void:
	var result: Dictionary = await speech.transcribe_wav(_pending_wav)
	if not result.get("ok", false):
		voice_error.emit(str(result.get("error", "unsupported")), str(result.get("message", "")))
		return
	transcript_ready.emit(str(result.get("transcript", "")), true)


func _drain() -> void:
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var outcome := await _speak_one(job)
		speech_finished.emit(int(job["id"]))
		if outcome == "rate_limited" or outcome == "auth":
			_queue.clear()
			break
	_draining = false
	if not _queue.is_empty():
		_draining = true
		Callable(self, "_drain").call_deferred()


func _speak_one(job: Dictionary) -> String:
	var profile: VoiceProfiles.Profile = job["profile"]
	var emotion := str(job["emotion"])
	var remark := str(job["remark"])
	var line := str(job["text"])
	var cache_key := VoiceCache.key_for(profile.voice_name, emotion, line, style_mode, remark)
	var cached := VoiceCache.load(cache_key)
	var pcm: PackedByteArray = PackedByteArray()
	var mix_rate := 24000
	if cached.get("ok", false):
		pcm = cached["pcm"]
		mix_rate = int(cached["mix_rate"])
	else:
		var pitch_now := profile.pitch * VoiceProfiles.playback_rate(emotion, user_rate)
		var volume_now := VoiceProfiles.playback_volume(emotion, user_volume)
		var outcome := await _speak_routed(line, profile.voice_name, pitch_now, volume_now, emotion, remark)
		if str(outcome.get("stop", "")) != "":
			return str(outcome.get("stop", ""))
		if not outcome.get("ready", false):
			return str(outcome.get("stop", "unsupported"))
		pcm = outcome["pcm"]
		mix_rate = int(outcome.get("mix_rate", 24000))
		VoiceCache.store(cache_key, pcm, mix_rate)
		if bool(outcome.get("played", false)):
			return ""
	if pcm.is_empty():
		voice_error.emit("unsupported", "Не удалось озвучить реплику.")
		return "unsupported"
	_note_audio()
	var pitch := profile.pitch * VoiceProfiles.playback_rate(emotion, user_rate)
	var volume := VoiceProfiles.playback_volume(emotion, user_volume)
	await speaker.play(pcm, mix_rate, pitch, volume)
	return ""


func _speak_routed(line: String, voice_name: String, pitch: float, volume_linear: float, emotion: String, remark: String) -> Dictionary:
	var engine := _route.choose()
	if engine == VoiceRoute.READER:
		_begin_audio(VoiceRoute.READER)
		var fast: Dictionary = await speech.synthesize(line, voice_name, emotion, remark, -1.0, VoiceProfiles.STYLE_PLAIN, true)
		if fast.get("ok", false):
			return {"ready": true, "pcm": fast["pcm"], "mix_rate": int(fast.get("mix_rate", 24000)), "played": false, "stop": ""}
		if str(fast.get("error", "")) == "auth":
			voice_error.emit("auth", str(fast.get("message", "")))
			return {"ready": false, "stop": "auth"}
		engine = VoiceRoute.LIVE
	if engine == VoiceRoute.LIVE:
		_begin_audio(VoiceRoute.LIVE)
		var streamed := await _speak_live(line, voice_name, pitch, volume_linear, emotion, remark)
		if streamed.get("ok", false):
			return {"ready": true, "pcm": streamed["pcm"], "mix_rate": int(streamed.get("mix_rate", 24000)), "played": true, "stop": ""}
		if str(streamed.get("error", "")) == "auth":
			voice_error.emit("auth", str(streamed.get("message", "")))
			return {"ready": false, "stop": "auth"}
	_begin_audio(VoiceRoute.READER)
	var result: Dictionary = await speech.synthesize(line, voice_name, emotion, remark, -1.0, VoiceProfiles.STYLE_PLAIN, true)
	if not result.get("ok", false):
		var kind := str(result.get("error", "unsupported"))
		var message := str(result.get("message", "")).strip_edges()
		if message == "":
			message = "Не удалось озвучить реплику."
		voice_error.emit(kind, message)
		return {"ready": false, "stop": kind}
	return {"ready": true, "pcm": result["pcm"], "mix_rate": int(result.get("mix_rate", 24000)), "played": false, "stop": ""}


func _begin_audio(engine: String) -> void:
	_audio_engine = engine
	_speak_started_ms = Time.get_ticks_msec()
	_logged_audio = false
	_measure_audio = true


func _speak_live(line: String, voice_name: String, pitch: float, volume_linear: float, emotion: String, remark: String) -> Dictionary:
	if not GeminiLive.network_enabled or speech.api_key.strip_edges() == "":
		return {"ok": false, "error": "unavailable", "message": "", "pcm": PackedByteArray(), "mix_rate": 0}
	_live_pitch = pitch
	_live_volume = volume_linear
	_live_streaming = false
	if not live.audio_chunk.is_connected(_on_live_chunk):
		live.audio_chunk.connect(_on_live_chunk)
	var result: Dictionary = await live.speak_line(speech.api_key, line, voice_name, emotion, remark)
	if result.get("ok", false):
		if _live_streaming:
			await speaker.end_stream()
		else:
			var spoken: PackedByteArray = result.get("pcm", PackedByteArray())
			if not spoken.is_empty():
				_note_audio()
				await speaker.play(spoken, int(result.get("mix_rate", 24000)), pitch, volume_linear)
		return result
	if _live_streaming:
		speaker.stop()
		_live_streaming = false
	return result


func _on_partial(text: String) -> void:
	if live == null or not live.accepts_input() or GeminiLive.is_clock_label(text):
		return
	transcript_ready.emit(text, false)


func _on_playback_reset() -> void:
	_live_streaming = false
	if speaker != null:
		speaker.stop()


func _vocabulary() -> PackedStringArray:
	if Game.case_data == null:
		return PackedStringArray()
	return VoiceProfiles.vocabulary_from_case(Game.case_data)


func _note_audio() -> void:
	if _logged_audio or _speak_started_ms <= 0:
		return
	_logged_audio = true
	if _measure_audio:
		_route.record(_audio_engine, Time.get_ticks_msec() - _speak_started_ms)
	TurnTiming.span_engine("text_to_audio", _speak_started_ms, _audio_engine)


func _on_live_chunk(chunk: PackedByteArray, rate: int) -> void:
	_note_audio()
	if not _live_streaming:
		_live_streaming = true
		speaker.begin_stream(rate, _live_pitch, _live_volume)
	speaker.push_stream(chunk)


func _tts_model() -> String:
	var file := ConfigFile.new()
	if file.load(SettingsStore.PATH) != OK:
		return GeminiSpeech.DEFAULT_TTS_MODEL
	return str(file.get_value("voice", "tts_model", GeminiSpeech.DEFAULT_TTS_MODEL)).strip_edges()


func _mic_allowed() -> bool:
	if OS.get_name() != "Android":
		return true
	const PERMISSION := "android.permission.RECORD_AUDIO"
	if OS.get_granted_permissions().has(PERMISSION):
		return true
	return OS.request_permission(PERMISSION)


class PcmSpeaker:
	extends Node

	const BUFFER_SEC := 0.1

	signal playback_finished
	var instant: bool = false
	var played: Array = []
	var _player: AudioStreamPlayer
	var _stream_rate: int = 0
	var _stream_frames: int = 0
	var _pending_frames: PackedVector2Array = PackedVector2Array()

	const BUS := "Master"

	func play(pcm: PackedByteArray, mix_rate: int, pitch: float, volume_linear: float) -> void:
		played.append({"bytes": pcm.size(), "mix_rate": mix_rate})
		if instant:
			return
		if _player == null:
			_player = AudioStreamPlayer.new()
			add_child(_player)
			_player.finished.connect(func() -> void: playback_finished.emit())
		_player.bus = BUS
		_player.stop()
		_player.stream = VoiceAudio.stream_from_pcm(pcm, mix_rate)
		_player.pitch_scale = clampf(pitch, 0.5, 1.6)
		_player.volume_db = linear_to_db(maxf(volume_linear, 0.001))
		_player.play()
		await playback_finished

	func begin_stream(mix_rate: int, pitch: float, volume_linear: float) -> void:
		played.append({"stream": true, "mix_rate": mix_rate})
		if instant:
			return
		if _player == null:
			_player = AudioStreamPlayer.new()
			add_child(_player)
		_player.bus = BUS
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = mix_rate
		generator.buffer_length = BUFFER_SEC
		_player.stop()
		_player.stream = generator
		_player.pitch_scale = clampf(pitch, 0.5, 1.6)
		_player.volume_db = linear_to_db(maxf(volume_linear, 0.001))
		_player.play()
		_stream_rate = mix_rate
		_stream_frames = 0
		_pending_frames = PackedVector2Array()

	func push_stream(pcm: PackedByteArray) -> void:
		if instant:
			played.append({"bytes": pcm.size()})
			return
		var frames := _frames_from_pcm(pcm)
		if frames.is_empty():
			return
		var merged := _pending_frames
		merged.append_array(frames)
		_pending_frames = merged
		_flush_stream()

	func _process(_delta: float) -> void:
		if not instant:
			_flush_stream()

	func _flush_stream() -> void:
		if _player == null or _pending_frames.is_empty():
			return
		var playback := _player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null:
			return
		var available := playback.get_frames_available()
		if available <= 0:
			return
		var count := mini(available, _pending_frames.size())
		playback.push_buffer(_pending_frames.slice(0, count))
		_stream_frames += count
		_pending_frames = _pending_frames.slice(count)

	func end_stream() -> void:
		if instant or _stream_rate <= 0:
			return
		var seconds := float(_stream_frames) / float(_stream_rate)
		if seconds > 0.0:
			await get_tree().create_timer(seconds).timeout

	func stop() -> void:
		if _player != null:
			_player.stop()

	func _frames_from_pcm(pcm: PackedByteArray) -> PackedVector2Array:
		var frames := PackedVector2Array()
		var count := pcm.size() / 2
		frames.resize(count)
		for index in count:
			var value := int(pcm[index * 2]) | (int(pcm[index * 2 + 1]) << 8)
			if value >= 32768:
				value -= 65536
			var sample := float(value) / 32768.0
			frames[index] = Vector2(sample, sample)
		return frames


class MicRecorder:
	extends Node

	const BUS := "VoiceRecord"

	var _effect: AudioEffectCapture
	var _player: AudioStreamPlayer
	var _stored: PackedByteArray = PackedByteArray()
	var _fresh: PackedByteArray = PackedByteArray()
	var _rate: int = 16000
	var _running: bool = false
	var _resample := VoiceAudio.RateState.new()

	func start() -> Dictionary:
		_ensure()
		_stored = PackedByteArray()
		_fresh = PackedByteArray()
		_resample = VoiceAudio.RateState.new()
		_effect.clear_buffer()
		_running = true
		_player.bus = BUS
		_player.play()
		return {"ok": true}

	func _process(_delta: float) -> void:
		if _running:
			_drain_to_store()

	func pull_new() -> Dictionary:
		_drain_to_store()
		var chunk := _fresh
		_fresh = PackedByteArray()
		if chunk.is_empty():
			return {"ok": true, "pcm": PackedByteArray(), "mix_rate": 16000, "stereo": false}
		return {"ok": true, "pcm": VoiceAudio.feed_16k(_resample, chunk, _rate), "mix_rate": 16000, "stereo": false}

	func stop() -> Dictionary:
		_running = false
		if _effect == null:
			return {"ok": false, "message": "Микрофон не был включён."}
		_drain_to_store()
		if _player != null:
			_player.stop()
		if _stored.is_empty():
			return {"ok": false, "message": "Микрофон ничего не записал."}
		return {"ok": true, "pcm": _stored, "mix_rate": _rate, "stereo": false}

	func _drain_to_store() -> void:
		var native := _take_native()
		if native.pcm.is_empty():
			return
		_stored.append_array(native.pcm)
		_fresh.append_array(native.pcm)
		_rate = int(native.mix_rate)

	func _take_native() -> Dictionary:
		var rate := int(AudioServer.get_mix_rate())
		if _effect == null:
			return {"pcm": PackedByteArray(), "mix_rate": rate}
		var count := _effect.get_frames_available()
		if count <= 0:
			return {"pcm": PackedByteArray(), "mix_rate": rate}
		var frames := _effect.get_buffer(count)
		var pcm := PackedByteArray()
		pcm.resize(frames.size() * 2)
		for index in frames.size():
			var sample := int(round(clampf((frames[index].x + frames[index].y) * 0.5, -1.0, 1.0) * 32767.0))
			var stored := sample if sample >= 0 else sample + 65536
			pcm[index * 2] = stored & 255
			pcm[index * 2 + 1] = (stored >> 8) & 255
		return {"pcm": pcm, "mix_rate": rate}

	func _ensure() -> void:
		if _effect != null:
			return
		var index := AudioServer.get_bus_index(BUS)
		if index <= 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_mute(index, true)
		AudioServer.set_bus_send(index, PcmSpeaker.BUS)
		_effect = AudioEffectCapture.new()
		_effect.buffer_length = 12.0
		AudioServer.add_bus_effect(index, _effect)
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS
		add_child(_player)
