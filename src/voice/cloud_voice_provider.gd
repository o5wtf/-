class_name CloudVoiceProvider
extends VoiceProvider
## Gemini TTS и расшифровка речи тем же ключом. Запросы синтеза идут по одному.

var speech: GeminiSpeech
var mic: Object = null
var speaker: PcmSpeaker
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
	return utterance_id


func stop_speaking() -> void:
	_queue.clear()
	if speaker != null:
		speaker.stop()


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


func stop_listening() -> void:
	if not _listening:
		return
	_listening = false
	var clip: Dictionary = mic.call("stop")
	if not clip.get("ok", false):
		voice_error.emit("unsupported", "Не удалось записать звук.")
		return
	var pcm: PackedByteArray = clip.get("pcm", PackedByteArray())
	var mono := VoiceAudio.mono(pcm, bool(clip.get("stereo", false)))
	if mono.size() < 2:
		voice_error.emit("unsupported", "Запись слишком короткая.")
		return
	_pending_wav = VoiceAudio.wav_bytes(mono, int(clip.get("mix_rate", 16000)), false)
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
	var cache_key := VoiceCache.key_for(profile.voice_name, emotion, remark, line)
	var cached := VoiceCache.load(cache_key)
	var pcm: PackedByteArray = PackedByteArray()
	var mix_rate := 24000
	if cached.get("ok", false):
		pcm = cached["pcm"]
		mix_rate = int(cached["mix_rate"])
	else:
		var result: Dictionary = await speech.synthesize(line, profile.voice_name, emotion, remark)
		if not result.get("ok", false):
			var kind := str(result.get("error", "unsupported"))
			voice_error.emit(kind, str(result.get("message", "")))
			return kind
		pcm = result["pcm"]
		mix_rate = int(result.get("mix_rate", 24000))
		VoiceCache.store(cache_key, pcm, mix_rate)
	if pcm.is_empty():
		return ""
	var pitch := profile.pitch * VoiceProfiles.playback_rate(emotion, user_rate)
	var volume := VoiceProfiles.playback_volume(emotion, user_volume)
	await speaker.play(pcm, mix_rate, pitch, volume)
	return ""


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

	signal playback_finished
	var instant: bool = false
	var played: Array = []
	var _player: AudioStreamPlayer

	func play(pcm: PackedByteArray, mix_rate: int, pitch: float, volume_linear: float) -> void:
		played.append({"bytes": pcm.size(), "mix_rate": mix_rate})
		if instant:
			return
		if _player == null:
			_player = AudioStreamPlayer.new()
			add_child(_player)
			_player.finished.connect(func() -> void: playback_finished.emit())
		_player.stop()
		_player.stream = VoiceAudio.stream_from_pcm(pcm, mix_rate)
		_player.pitch_scale = clampf(pitch, 0.5, 1.6)
		_player.volume_db = linear_to_db(maxf(volume_linear, 0.001))
		_player.play()
		await playback_finished

	func stop() -> void:
		if _player != null:
			_player.stop()


class MicRecorder:
	extends Node

	var _effect: AudioEffectRecord
	var _player: AudioStreamPlayer
	var _bus := "VoiceRecord"

	func start() -> Dictionary:
		_ensure()
		_effect.set_recording_active(false)
		_effect.set_recording_active(true)
		_player.play()
		return {"ok": true}

	func stop() -> Dictionary:
		if _effect == null:
			return {"ok": false, "message": "Микрофон не был включён."}
		_effect.set_recording_active(false)
		if _player != null:
			_player.stop()
		var recorded: AudioStreamWAV = _effect.get_recording()
		if recorded == null or recorded.data.is_empty():
			return {"ok": false, "message": "Микрофон ничего не записал."}
		return {
			"ok": true,
			"pcm": recorded.data,
			"mix_rate": recorded.mix_rate,
			"stereo": recorded.stereo,
		}

	func _ensure() -> void:
		if _effect != null:
			return
		var index := AudioServer.get_bus_index(_bus)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, _bus)
			AudioServer.set_bus_mute(index, true)
		_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(index, _effect)
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = _bus
		add_child(_player)
