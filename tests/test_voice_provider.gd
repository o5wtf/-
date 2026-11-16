extends TestCase
## Голос: фейковый транспорт Gemini и фейковый микрофон. Сюжет дел не используется.

const SECRET := "unit-test-key"

var _finished: int = 0
var _heard: String = ""
var _heard_final: bool = false
var _heard_n: int = 0


func test_profile_follows_gender_age_and_name() -> void:
	var young := VoiceProfiles.for_person("a", "Анна", "", 22)
	assert_eq(young.gender, "female")
	assert_eq(young.age_band, "young")
	assert_true(young.voice_name == "Leda" or young.voice_name == "Zephyr")
	var older := VoiceProfiles.for_person("b", "Иван", "", 70)
	assert_eq(older.gender, "male")
	assert_eq(older.age_band, "older")
	assert_true(older.voice_name == "Enceladus" or older.voice_name == "Schedar")
	var forced := VoiceProfiles.for_person("a", "Анна", "male", 40)
	assert_eq(forced.gender, "male")
	assert_eq(forced.age_band, "adult")
	assert_eq(VoiceProfiles.for_person("a", "Анна", "", 22).voice_name, young.voice_name)
	var agent := CaseData.Agent.new()
	agent.id = "p"
	agent.name = "Мария"
	agent.gender = "female"
	agent.age = 60
	var from_case := VoiceProfiles.for_agent(agent)
	assert_eq(from_case.gender, "female")
	assert_eq(from_case.age_band, "older")


func test_style_prompt_is_only_the_spoken_line() -> void:
	assert_eq(VoiceProfiles.DEFAULT_STYLE_MODE, VoiceProfiles.STYLE_PLAIN)
	assert_eq(VoiceProfiles.style_prompt("Только это.", "angry", "отводит взгляд"), "Только это.")
	var emotions := ["calm", "neutral", "nervous", "scared", "sad", "angry", "controlled", "contemptuous"]
	for emotion in emotions:
		for mode in [VoiceProfiles.STYLE_ENGLISH_PREFIX, VoiceProfiles.STYLE_ENGLISH_TAGS]:
			var prompt := VoiceProfiles.style_prompt("Только это.", emotion, "отводит взгляд", mode)
			var russian := prompt.substr(prompt.rfind("\n") + 1)
			assert_eq(russian, "Только это.")
			assert_false(russian.contains("["), mode)
			assert_false(russian.contains("]"), mode)
			for word in VoiceProfiles.MOOD_WORDS:
				assert_false(prompt.to_lower().contains(word), "%s/%s" % [emotion, word])
			for phrase in ["скажи", "произнеси", "вслух", "отводит"]:
				assert_false(prompt.to_lower().contains(phrase), phrase)
		assert_eq(VoiceProfiles.style_prompt("Только это.", emotion, "отводит взгляд", VoiceProfiles.STYLE_PLAIN), "Только это.")
	var cold := VoiceProfiles.style_prompt("Хватит.", "controlled", "молчит", VoiceProfiles.STYLE_ENGLISH_PREFIX)
	assert_true(cold.begins_with("Read the following Russian line in a cold, restrained tone."))
	assert_true(cold.ends_with("\nХватит."))
	var tags := VoiceProfiles.style_prompt("Хватит.", "nervous", "молчит", VoiceProfiles.STYLE_ENGLISH_TAGS)
	assert_true(tags.begins_with("[nervous] [hesitant]\n"))
	assert_eq(VoiceProfiles.spoken_text("Холодно, сдержанно: Я уже всё рассказал."), "Я уже всё рассказал.")
	assert_eq(VoiceProfiles.spoken_text("(нервно) Я не знаю."), "Я не знаю.")
	assert_eq(VoiceProfiles.spoken_text("*вздыхает* Оставьте меня."), "Оставьте меня.")
	assert_eq(VoiceProfiles.spoken_text("— тихо — Я был дома."), "Я был дома.")
	assert_eq(VoiceProfiles.spoken_text("[холодно, сдержанно] Хватит."), "Хватит.")
	assert_eq(VoiceProfiles.style_prompt("[холодно, сдержанно] Хватит.", "controlled", "молчит", VoiceProfiles.STYLE_PLAIN), "Хватит.")


func test_live_messages_carry_transcript_and_audio() -> void:
	var pcm := PackedByteArray([1, 0, 2, 0])
	var audio := {
		"serverContent": {
			"modelTurn": {"parts": [{
				"inlineData": {"mimeType": "audio/pcm;rate=24000", "data": Marshalls.raw_to_base64(pcm)},
			}]},
			"turnComplete": true,
		},
	}
	var events := GeminiLive.parse_server(JSON.stringify(audio))
	assert_eq(events.size(), 2)
	assert_eq(events[0]["kind"], "audio")
	assert_eq(events[0]["pcm"], pcm)
	assert_eq(events[0]["mix_rate"], 24000)
	assert_eq(events[1]["kind"], "turn_complete")
	var heard := {
		"serverContent": {
			"interimInputTranscription": {"text": "во сколь"},
			"inputTranscription": {"text": "Во сколько"},
		},
	}
	var text_events := GeminiLive.parse_server(JSON.stringify(heard))
	assert_eq(text_events[0]["kind"], "interim")
	assert_eq(text_events[0]["text"], "во сколь")
	assert_eq(text_events[1]["kind"], "transcript")
	assert_eq(text_events[1]["text"], "Во сколько")
	var setup := GeminiLive.setup_message("gemini-3.8-live", "Kore", false)
	assert_eq(setup["setup"]["model"], "models/gemini-3.8-live")
	assert_false(JSON.stringify(setup).contains("systemInstruction") == false)
	var line := GeminiLive.line_message("Хватит.")
	assert_eq(line["clientContent"]["turns"][0]["parts"][0]["text"], "Хватит.")
	assert_false(str(line["clientContent"]["turns"][0]["parts"][0]["text"]).contains("["))


func test_live_instruction_carries_tone_outside_the_line() -> void:
	var line := "Хватит."
	var expected := {
		"calm": "calm",
		"neutral": "calm",
		"nervous": "hesitant",
		"scared": "quiet",
		"sad": "sad",
		"angry": "sharp",
		"controlled": "restrained",
		"contemptuous": "contemptuous",
	}
	for emotion in expected:
		var setup: Dictionary = GeminiLive.setup_message("gemini-3.8-live", "Kore", false, emotion, "отводит взгляд")
		var instruction := str(setup["setup"]["systemInstruction"]["parts"][0]["text"])
		assert_true(instruction.contains("Тон:"), emotion)
		assert_true(instruction.contains(str(expected[emotion])), emotion)
		assert_true(instruction.contains("отводит взгляд"), emotion)
		var sent: Dictionary = GeminiLive.line_message(VoiceProfiles.spoken_text(line))
		var spoken := str(sent["clientContent"]["turns"][0]["parts"][0]["text"])
		assert_eq(spoken, line)
		assert_false(spoken.contains(str(expected[emotion])))
		assert_false(spoken.contains("отводит"))
		assert_false(spoken.contains("Тон"))


func test_live_vad_verbatim_and_resumption() -> void:
	var listen: Dictionary = GeminiLive.setup_message("gemini-3.5-transcribe-live", "", true)
	var activity: Dictionary = listen["setup"]["realtimeInputConfig"]["automaticActivityDetection"]
	assert_eq(activity, GeminiLive.ACTIVITY)
	assert_eq(activity["silenceDurationMs"], 500)
	assert_eq(activity["endOfSpeechSensitivity"], "END_SENSITIVITY_HIGH")
	assert_eq(activity["startOfSpeechSensitivity"], "START_SENSITIVITY_HIGH")
	var speak: Dictionary = GeminiLive.setup_message("gemini-3.8-live", "Kore", false, "controlled", "молчит", "handle-1")
	assert_true(speak["setup"].has("outputAudioTranscription"))
	assert_eq(speak["setup"]["sessionResumption"]["handle"], "handle-1")
	assert_true(speak["setup"]["contextWindowCompression"].has("slidingWindow"))
	assert_true(str(speak["setup"]["systemInstruction"]["parts"][0]["text"]).contains("cold, restrained"))
	var sent: Dictionary = GeminiLive.line_message("Хватит.")
	assert_eq(sent["clientContent"]["turns"][0]["parts"][0]["text"], "Хватит.")
	assert_true(GeminiLive.verbatim_ok("Хватит!", "хватит"))
	assert_true(GeminiLive.verbatim_ok("Всё сказал.", "все сказал"))
	assert_false(GeminiLive.verbatim_ok("Хватит.", "Совершенно другая фраза"))
	assert_true(GeminiLive.should_fallback(false, true, "", "Хватит."))
	assert_true(GeminiLive.should_fallback(true, false, "", "Хватит."))
	assert_true(GeminiLive.should_fallback(true, true, "другая фраза", "Хватит."))
	assert_false(GeminiLive.should_fallback(true, true, "Хватит!", "Хватит."))
	assert_false(GeminiLive.should_fallback(true, true, "", "Хватит."))
	var events := GeminiLive.parse_server("{\"sessionResumptionUpdate\":{\"newHandle\":\"abc\",\"resumable\":true},\"goAway\":{\"timeLeft\":\"10s\"}}")
	var handle := ""
	var leaving := false
	for event in events:
		if str(event.get("kind", "")) == "resume":
			handle = str(event.get("handle", ""))
		if str(event.get("kind", "")) == "go_away":
			leaving = true
	assert_eq(handle, "abc")
	assert_true(leaving)
	var same := GeminiLive.session_key("gemini-3.8-live", "Kore", false, "calm", "")
	assert_true(GeminiLive.can_resume(same, same, handle))
	var other := GeminiLive.session_key("gemini-3.8-live", "Kore", false, "angry", "")
	assert_false(GeminiLive.can_resume(same, other, handle))


func test_l16_and_wav_roundtrip() -> void:
	var pcm := PackedByteArray([1, 2, 3, 4, 5, 6])
	var parsed := VoiceAudio.pcm_from_mime("audio/L16;codec=pcm;rate=24000", Marshalls.raw_to_base64(pcm))
	assert_true(parsed.get("ok", false))
	assert_eq(parsed["mix_rate"], 24000)
	assert_eq(parsed["pcm"], pcm)
	var stream := VoiceAudio.stream_from_pcm(parsed["pcm"], parsed["mix_rate"])
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(stream.mix_rate, 24000)
	assert_false(stream.stereo)
	var wav := VoiceAudio.wav_bytes(pcm, 16000)
	var back := VoiceAudio.pcm_from_mime("audio/wav", Marshalls.raw_to_base64(wav))
	assert_eq(back["mix_rate"], 16000)
	assert_eq(back["pcm"], pcm)


func test_overload_falls_back_and_cache_replays_without_request() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var speaker: CloudVoiceProvider.PcmSpeaker = fixture["speaker"]
	var provider: CloudVoiceProvider = fixture["provider"]
	_arm(provider)
	transport.push(_status(503, "{\"error\":{\"status\":\"UNAVAILABLE\",\"message\":\"high demand\"}}"))
	transport.push(_audio(PackedByteArray([8, 0, 9, 0])))
	var profile := VoiceProfiles.for_person("a", "Анна", "female", 40)
	provider.speak("Добрый день.", profile, "calm", "кивает")
	await _until(provider, 1)
	assert_eq(speaker.played.size(), 1)
	assert_eq(speaker.played[0]["mix_rate"], 24000)
	assert_eq(transport.seen.size(), 2)
	assert_true(str(transport.seen[1]["url"]).contains("gemini-3.8-flash-tts"))
	assert_false(str(transport.seen[0]["body"]).contains(SECRET))
	var cache_path := VoiceCache.path_for(VoiceCache.key_for(profile.voice_name, "calm", "Добрый день.", VoiceProfiles.DEFAULT_STYLE_MODE, "кивает"))
	assert_true(FileAccess.file_exists(cache_path))
	assert_false(FileAccess.get_file_as_string(cache_path).contains(SECRET))
	provider.speak("Добрый день.", profile, "calm", "кивает")
	await _until(provider, 2)
	assert_eq(transport.seen.size(), 2)
	assert_eq(speaker.played.size(), 2)
	_free(fixture)


func test_rate_limit_skips_audio_and_does_not_keep_asking() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var provider: CloudVoiceProvider = fixture["provider"]
	_arm(provider)
	_notice = ""
	provider.voice_error.connect(_on_notice)
	for _index in 4:
		transport.push(_status(429, "{\"error\":{\"status\":\"RESOURCE_EXHAUSTED\",\"message\":\"quota\"}}"))
	var profile := VoiceProfiles.for_person("a", "Анна", "", 40)
	provider.speak("Первая.", profile, "neutral", "")
	provider.speak("Вторая.", profile, "neutral", "")
	await _until(provider, 1)
	assert_eq(_notice, "rate_limited")
	assert_eq(fixture["speaker"].played.size(), 0)
	assert_eq(transport.seen.size(), 4)
	assert_true(str(transport.seen[0]["body"]).contains("Первая."))
	assert_false(str(transport.seen[0]["body"]).contains("Вторая."))
	_free(fixture)


func test_timeout_and_missing_model_try_the_next() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var provider: CloudVoiceProvider = fixture["provider"]
	_arm(provider)
	transport.push({"ok": false, "status": 0, "body": "", "headers": {}, "error": "timeout"})
	transport.push(_status(404, "{\"error\":{\"status\":\"NOT_FOUND\",\"message\":\"no longer available\"}}"))
	transport.push(_audio(PackedByteArray([1, 0])))
	provider.speak("Алло.", VoiceProfiles.for_person("a", "Анна", "", 40), "neutral", "")
	await _until(provider, 1)
	assert_eq(fixture["speaker"].played.size(), 1)
	assert_eq(transport.seen.size(), 3)
	assert_true(str(transport.seen[2]["url"]).contains("gemini-3.1-flash-tts-preview"))
	_free(fixture)


func test_auth_error_names_the_reason_without_the_key() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var provider: CloudVoiceProvider = fixture["provider"]
	_arm(provider)
	_notice = ""
	_notice_text = ""
	provider.voice_error.connect(_on_notice_text)
	transport.push(_status(400, "{\"error\":{\"status\":\"INVALID_ARGUMENT\",\"message\":\"API key not valid. %s\"}}" % SECRET))
	provider.speak("Алло.", VoiceProfiles.for_person("a", "Анна", "", 40), "neutral", "")
	await _until(provider, 1)
	assert_eq(_notice, "auth")
	assert_false(_notice_text.contains(SECRET))
	assert_true(_notice_text.contains("Ключ API отклонён"))
	assert_eq(transport.seen.size(), 1)
	_free(fixture)


func test_rate_limit_falls_through_to_the_next_tts_model() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var provider: CloudVoiceProvider = fixture["provider"]
	_arm(provider)
	transport.push(_status(429, "{\"error\":{\"status\":\"RESOURCE_EXHAUSTED\",\"message\":\"quota\"}}"))
	transport.push(_audio(PackedByteArray([4, 0])))
	provider.speak("Ещё раз.", VoiceProfiles.for_person("a", "Анна", "", 40), "neutral", "")
	await _until(provider, 1)
	assert_eq(fixture["speaker"].played.size(), 1)
	assert_eq(transport.seen.size(), 2)
	assert_true(str(transport.seen[1]["url"]).contains("gemini-3.8-flash-tts"))
	provider.speak("Ещё раз.", VoiceProfiles.for_person("a", "Анна", "", 40), "neutral", "")
	await _until(provider, 2)
	assert_eq(transport.seen.size(), 2)
	_free(fixture)


func test_developer_instruction_is_a_request_bug() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var provider: CloudVoiceProvider = fixture["provider"]
	_arm(provider)
	_notice = ""
	_notice_text = ""
	provider.voice_error.connect(_on_notice_text)
	transport.push(_status(400, "{\"error\":{\"status\":\"INVALID_ARGUMENT\",\"message\":\"Developer instruction is not enabled for this model\"}}"))
	provider.speak("Алло.", VoiceProfiles.for_person("a", "Анна", "", 40), "neutral", "")
	await _until(provider, 1)
	assert_eq(_notice, "rejected")
	assert_false(_notice_text.to_lower().contains("недоступ"))
	assert_false(_notice_text.contains("Ключ"))
	assert_eq(transport.seen.size(), 1)
	_free(fixture)


func test_mic_audio_uses_the_fast_transcription_chain() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var mic: FakeMic = fixture["mic"]
	var provider: CloudVoiceProvider = fixture["provider"]
	transport.push(_plain("Во сколько это было?"))
	_heard = ""
	_heard_final = false
	_heard_n = 0
	provider.transcript_ready.connect(_on_transcript)
	provider.start_listening()
	provider.stop_listening()
	while _heard_n < 1:
		await provider.transcript_ready
	assert_eq(_heard, "Во сколько это было?")
	assert_true(_heard_final)
	assert_eq(transport.seen.size(), 1)
	var first := str(transport.seen[0]["body"])
	assert_true(str(transport.seen[0]["url"]).contains("gemini-3.5-flash-lite"))
	assert_eq(transport.seen[0]["timeout"], GeminiSpeech.TRANSCRIBE_TIMEOUT_S)
	assert_true(first.contains("inlineData"))
	assert_true(first.contains(GeminiSpeech.TRANSCRIBE_PROMPT))
	assert_true(first.contains("MINIMAL"))
	assert_false(first.contains("systemInstruction"))
	assert_false(first.contains("responseJsonSchema"))
	assert_false(first.contains(SECRET))
	assert_true(mic.started_count >= 1)
	_free(fixture)


func test_transcribe_model_reads_audio_transcription() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var provider: CloudVoiceProvider = fixture["provider"]
	transport.push(_plain(""))
	transport.push(_audio_transcription("После семи."))
	_heard = ""
	_heard_n = 0
	provider.transcript_ready.connect(_on_transcript)
	provider.start_listening()
	provider.stop_listening()
	while _heard_n < 1:
		await provider.transcript_ready
	assert_eq(_heard, "После семи.")
	assert_eq(transport.seen.size(), 2)
	assert_true(str(transport.seen[1]["url"]).contains("gemini-3.5-transcribe"))
	var second: Dictionary = JSON.parse_string(str(transport.seen[1]["body"]))
	assert_false(second["generationConfig"].has("thinkingConfig"))
	_free(fixture)


func test_upload_audio_is_16k_mono_without_edge_silence() -> void:
	var loud := PackedByteArray([0, 0, 0, 16])
	var silence := PackedByteArray([0, 0])
	var pcm := silence + silence + loud + silence + silence
	var prepared := VoiceAudio.prepare_for_upload(pcm, 48000, false)
	assert_true(prepared.size() < pcm.size())
	assert_true(prepared.size() >= 2)
	var wav := VoiceAudio.wav_bytes(prepared, VoiceAudio.UPLOAD_RATE)
	var back := VoiceAudio.pcm_from_mime("audio/wav", Marshalls.raw_to_base64(wav))
	assert_eq(back["mix_rate"], 16000)
	assert_eq(back["pcm"], prepared)


func test_requests_are_one_at_a_time() -> void:
	var fixture := await _cloud()
	var transport: FakeTransport = fixture["transport"]
	var provider: CloudVoiceProvider = fixture["provider"]
	_arm(provider)
	transport.push(_audio(PackedByteArray([1, 0])))
	transport.push(_audio(PackedByteArray([2, 0])))
	var profile := VoiceProfiles.for_person("a", "Анна", "", 40)
	provider.speak("Раз.", profile, "neutral", "")
	provider.speak("Два.", profile, "angry", "")
	await _until(provider, 2)
	assert_eq(transport.max_depth, 1)
	assert_eq(fixture["speaker"].played.size(), 2)
	_free(fixture)


func test_builtin_has_no_stt_and_speaks_the_reply() -> void:
	var host := FakeTts.new()
	var provider := BuiltinVoiceProvider.new()
	provider.host = host
	(Engine.get_main_loop() as SceneTree).root.add_child(provider)
	_arm(provider)
	assert_true(provider.is_tts_available())
	assert_false(provider.is_stt_available())
	_notice = ""
	provider.voice_error.connect(_on_notice)
	provider.start_listening()
	assert_eq(_notice, "unsupported")
	var profile := VoiceProfiles.for_person("m", "Иван", "male", 40)
	provider.speak("Сама реплика.", profile, "angry", "сжимает кулаки")
	await _until(provider, 1)
	assert_eq(host.spoken.size(), 1)
	assert_eq(host.spoken[0]["text"], "Сама реплика.")
	assert_false(str(host.spoken[0]["text"]).contains("сжимает"))
	assert_eq(host.spoken[0]["voice"], "ru-male")
	provider.queue_free()


func test_voice_settings_roundtrip_without_restart_fields() -> void:
	SettingsStore.save_values("mock", "", "gemini-3.5-flash", 1.0, {
		"enabled": false,
		"provider": "builtin",
		"stt_mode": "gemini_audio",
		"volume": 0.4,
		"rate": 1.2,
		"tts_model": "gemini-3.8-flash-lite-tts",
	})
	var store := SettingsStore.load_current()
	assert_false(store.voice_enabled)
	assert_eq(store.voice_provider, "builtin")
	assert_eq(store.stt_mode, "gemini_audio")
	assert_true(absf(store.voice_volume - 0.4) < 0.001)
	assert_true(absf(store.voice_rate - 1.2) < 0.001)


var _notice: String = ""
var _notice_text: String = ""


func _on_notice(kind: String, _message: String) -> void:
	_notice = kind


func _on_notice_text(kind: String, text: String) -> void:
	_notice = kind
	_notice_text = text


func _on_transcript(text: String, is_final: bool) -> void:
	_heard = text
	_heard_final = is_final
	_heard_n += 1


func _arm(provider: VoiceProvider) -> void:
	_finished = 0
	if not provider.speech_finished.is_connected(_on_finished):
		provider.speech_finished.connect(_on_finished)


func _on_finished(_utterance_id: int) -> void:
	_finished += 1


func _until(provider: VoiceProvider, need: int) -> void:
	while _finished < need:
		await provider.speech_finished


func _cloud() -> Dictionary:
	GeminiLive.network_enabled = false
	VoiceCache.directory = "user://voice_cache_test"
	_wipe_cache()
	var transport := FakeTransport.new()
	var speech := GeminiSpeech.new()
	speech.api_key = SECRET
	speech.tts_model = GeminiSpeech.DEFAULT_TTS_MODEL
	speech.dialogue_model = LLMConfig.DEFAULT_DIALOGUE_MODEL
	speech.min_interval_s = 0.0
	speech._instant_wait = true
	speech.set_transport(transport)
	var speaker := CloudVoiceProvider.PcmSpeaker.new()
	speaker.instant = true
	var mic := FakeMic.new()
	var provider := CloudVoiceProvider.new()
	provider.speech = speech
	provider.speaker = speaker
	provider.mic = mic
	(Engine.get_main_loop() as SceneTree).root.add_child(provider)
	return {"provider": provider, "transport": transport, "speaker": speaker, "mic": mic}


func _free(fixture: Dictionary) -> void:
	GeminiLive.network_enabled = true
	(fixture["provider"] as Node).queue_free()
	_wipe_cache()


func _wipe_cache() -> void:
	var dir := DirAccess.open(VoiceCache.directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			dir.remove(name)
		name = dir.get_next()


func _audio(pcm: PackedByteArray) -> Dictionary:
	var payload := {
		"candidates": [{
			"content": {"parts": [{
				"inlineData": {"mimeType": "audio/L16;rate=24000", "data": Marshalls.raw_to_base64(pcm)},
			}]},
			"finishReason": "STOP",
		}],
	}
	return _status(200, JSON.stringify(payload))


func _plain(text: String) -> Dictionary:
	var payload := {
		"candidates": [{
			"content": {"parts": [{"text": text}]},
			"finishReason": "STOP",
		}],
	}
	return _status(200, JSON.stringify(payload))


func _audio_transcription(text: String) -> Dictionary:
	var payload := {
		"candidates": [{
			"content": {"parts": [{"audioTranscription": {"text": text}}]},
			"finishReason": "STOP",
		}],
	}
	return _status(200, JSON.stringify(payload))


func _transcript(text: String) -> Dictionary:
	var payload := {
		"candidates": [{
			"content": {"parts": [{"text": JSON.stringify({"transcript": text})}]},
			"finishReason": "STOP",
		}],
	}
	return _status(200, JSON.stringify(payload))


func _status(code: int, body: String) -> Dictionary:
	return {"ok": true, "status": code, "body": body, "headers": {}, "error": ""}


class FakeTransport:
	extends RefCounted

	var scripted: Array = []
	var seen: Array = []
	var depth: int = 0
	var max_depth: int = 0

	func push(outcome: Dictionary) -> void:
		scripted.append(outcome)

	func request(url: String, headers: Dictionary, body: String, timeout_s: float) -> Dictionary:
		depth += 1
		max_depth = maxi(max_depth, depth)
		seen.append({"url": url, "headers": headers, "body": body, "timeout": timeout_s})
		var outcome: Dictionary = scripted.pop_front() if not scripted.is_empty() else {
			"ok": false, "status": 0, "body": "", "headers": {}, "error": "offline",
		}
		depth -= 1
		return outcome


class FakeMic:
	extends Node

	var started_count: int = 0

	func start() -> Dictionary:
		started_count += 1
		return {"ok": true}

	func stop() -> Dictionary:
		return {"ok": true, "pcm": PackedByteArray([0, 16, 0, 16, 0, 16, 0, 16]), "mix_rate": 16000, "stereo": false}


class FakeTts:
	extends RefCounted

	var spoken: Array = []

	func voices(_language: String) -> Array:
		return [{"id": "ru-male", "name": "Russian male"}, {"id": "ru-female", "name": "Russian female"}]

	func speak(text: String, voice: String, volume: int, pitch: float, rate: float, utterance_id: int) -> void:
		spoken.append({"text": text, "voice": voice, "volume": volume, "pitch": pitch, "rate": rate, "id": utterance_id})

	func stop() -> void:
		pass
