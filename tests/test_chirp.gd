extends TestCase

var _holder: Node = null


func test_jwt_is_signed_and_token_is_cached() -> void:
	var pair := _rsa()
	var pem := str(pair["private"])
	var issued := 1_700_000_000
	var built := ChirpAuth.build_jwt("demo@example.gserviceaccount.com", pem, issued)
	assert_true(built.get("ok", false))
	var token := str(built.get("token", ""))
	var parts := token.split(".")
	assert_eq(parts.size(), 3)
	var header: Variant = JSON.parse_string(_b64url_decode(parts[0]).get_string_from_utf8())
	var payload: Variant = JSON.parse_string(_b64url_decode(parts[1]).get_string_from_utf8())
	assert_eq(str((header as Dictionary).get("alg", "")), "RS256")
	assert_eq(str((payload as Dictionary).get("iss", "")), "demo@example.gserviceaccount.com")
	assert_eq(str((payload as Dictionary).get("scope", "")), ChirpAuth.SCOPE)
	assert_eq(str((payload as Dictionary).get("aud", "")), ChirpAuth.AUD)
	assert_eq(int((payload as Dictionary).get("exp", 0)), issued + ChirpAuth.TTL_S)
	var pub := CryptoKey.new()
	assert_eq(pub.load_from_string(str(pair["public"]), true), OK)
	assert_true(Crypto.new().verify(HashingContext.HASH_SHA256, built.get("digest", PackedByteArray()), _b64url_decode(parts[2]), pub))
	var pkcs8 := _pkcs8_pem(pem)
	var wrapped := ChirpAuth.build_jwt("demo@example.gserviceaccount.com", pkcs8, issued)
	assert_true(wrapped.get("ok", false), "PKCS#8")
	var wrapped_parts := str(wrapped.get("token", "")).split(".")
	assert_true(Crypto.new().verify(HashingContext.HASH_SHA256, wrapped.get("digest", PackedByteArray()), _b64url_decode(wrapped_parts[2]), pub))
	var http := _Http.new()
	http.token = "ya29.SECRETTOKEN"
	ChirpAuth.reset()
	ChirpAuth.transport = http
	ChirpAuth.now_override = issued
	ChirpAuth.key_override = _account(pem)
	var first: Dictionary = await ChirpAuth.access_token(_host())
	assert_true(first.get("ok", false))
	assert_true(bool(first.get("refreshed", false)))
	var second: Dictionary = await ChirpAuth.access_token(_host())
	assert_false(bool(second.get("refreshed", false)))
	assert_eq(http.token_posts, 1)
	ChirpAuth.now_override = issued + ChirpAuth.TTL_S - ChirpAuth.SKEW_S
	var third: Dictionary = await ChirpAuth.access_token(_host())
	assert_true(bool(third.get("refreshed", false)))
	assert_eq(http.token_posts, 2)
	assert_false(_log_has("ya29.SECRETTOKEN"))
	assert_false(_log_has("PRIVATE KEY"))
	assert_true(_log_has("chirp token refresh"))
	_cleanup()


func test_bad_json_is_a_clear_error_and_chirp_is_skipped_without_a_key() -> void:
	assert_eq(str(ChirpAuth.parse("не json").get("error", "")), "bad_json")
	assert_true(str(ChirpAuth.parse("не json").get("message", "")).contains("не JSON"))
	assert_eq(str(ChirpAuth.parse('{"client_email":"a@b.c"}').get("error", "")), "bad_json")
	assert_true(ChirpAuth.message_for("chirp_auth", 401, "").contains("отклонён"))
	assert_true(ChirpAuth.message_for("chirp_api", 403, "SERVICE_DISABLED").contains("выключен"))
	ChirpAuth.key_override = ""
	ChirpAuth.transport = _Http.new()
	assert_false(TtsQuota.chirp_ready())
	assert_eq(TtsQuota.chain()[2], ChirpVoices.MODEL_ID)
	TtsQuota.store_path = "user://tts-quota-chirp.cfg"
	TtsQuota.now_override = 1_800_000_000
	TtsQuota.fallback_override = true
	TtsQuota.selected_override = TtsQuota.chain()[0]
	TtsQuota.reset()
	assert_eq(TtsQuota.next_open(TtsQuota.chain()[1], TtsQuota.now_unix()), "")
	var backend := _backend([_quota(), _quota()])
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(backend.transport.calls.size(), 2)
	assert_eq(_http().synth_posts, 0)
	assert_true(errors[0].contains("quota_daily"))
	backend.free()
	_cleanup()


func test_daily_quota_walks_down_to_chirp_and_direct_selection_uses_it() -> void:
	var pem := str(_rsa()["private"])
	_arm(pem)
	var http := _http()
	var walked := _backend([_quota(), _quota()])
	await walked.speak("line", "Привет.", "Kore")
	assert_eq(walked.transport.calls.size(), 2)
	assert_true(str(walked.transport.calls[0].get("path", "")).contains(TtsQuota.chain()[0]))
	assert_true(str(walked.transport.calls[1].get("path", "")).contains(TtsQuota.chain()[1]))
	assert_eq(http.synth_posts, 1)
	assert_true(_log_has("tts model=%s" % ChirpVoices.MODEL_ID))
	assert_true(_log_has("chars="))
	walked.free()
	http.synth_posts = 0
	http.token_posts = 0
	TtsQuota.selected_override = ChirpVoices.MODEL_ID
	var direct := _backend([])
	await direct.speak("line", "Только Chirp.", "Charon")
	assert_eq(direct.transport.calls.size(), 0)
	assert_true(http.synth_posts >= 1)
	var body := str(http.synth_bodies[http.synth_bodies.size() - 1])
	assert_true(body.contains("ru-RU-Chirp3-HD-Charon"))
	assert_true(body.contains("LINEAR16"))
	assert_false(body.contains("<sigh>"))
	direct.free()
	_cleanup()


func test_chirp_strips_marks_maps_tempo_and_splits_long_lines() -> void:
	assert_eq(ChirpVoices.for_gemini("Kore"), "ru-RU-Chirp3-HD-Kore")
	assert_eq(ChirpVoices.for_gemini("Charon"), "ru-RU-Chirp3-HD-Charon")
	assert_eq(ChirpVoices.for_gemini("НетТакого", "male"), "ru-RU-Chirp3-HD-Charon")
	assert_eq(ChirpVoices.for_gemini("НетТакого", "female"), "ru-RU-Chirp3-HD-Kore")
	assert_eq(ChirpVoices.speaking_rate("нервно, медленно"), 0.9)
	assert_eq(ChirpVoices.speaking_rate("быстро"), 1.1)
	assert_eq(ChirpVoices.speaking_rate("slow"), 0.9)
	assert_eq(ChirpVoices.speaking_rate(""), 1.0)
	var spoken := ChirpVoices.spoken_text("Я был. <sigh> Это правда.")
	assert_false(spoken.contains("<"))
	assert_true(spoken.contains("Я был."))
	assert_true(spoken.contains("Это правда."))
	var short := ChirpVoices.chunks("Раз. Два. Три. Четыре.")
	assert_eq(short[0], "Раз. Два.")
	assert_true(short[0].length() <= ChirpVoices.FIRST_CHARS_MAX)
	assert_true(short.size() >= 2)
	var wordy := ("Слово ".repeat(200)).strip_edges()
	var cut := ChirpVoices.chunks(wordy)
	assert_true(cut[0].length() <= ChirpVoices.FIRST_CHARS_MAX, str(cut[0].length()))
	assert_true(cut[0].length() >= 150, str(cut[0].length()))
	assert_true(cut[1].length() > ChirpVoices.FIRST_CHARS_MAX, str(cut[1].length()))
	var kept := ""
	for piece in cut:
		kept += piece.replace(" ", "")
	assert_eq(kept, wordy.replace(" ", ""))
	var long_sentence := "%s." % "А".repeat(2000)
	var text := "%s %s" % [long_sentence, long_sentence]
	var pieces := ChirpVoices.chunks(text)
	assert_true(pieces.size() >= 2)
	var flat := ""
	for piece in pieces:
		assert_true(piece.to_utf8_buffer().size() <= ChirpVoices.BYTE_LIMIT)
		flat += piece.replace(" ", "")
	assert_eq(flat, text.replace(" ", ""))
	var pem := str(_rsa()["private"])
	_arm(pem)
	TtsQuota.selected_override = ChirpVoices.MODEL_ID
	var http := _http()
	var backend := _backend([])
	await backend.speak("line", "Я дома. <sigh> Правда.", "Kore", "медленно")
	var body := str(http.synth_bodies[0])
	assert_false(body.contains("<sigh>"))
	assert_true(body.contains("0.9"))
	assert_true(body.contains("Я дома."))
	backend.free()
	http.synth_bodies.clear()
	http.seen_pushes.clear()
	http.synth_posts = 0
	var many := _backend([])
	many.sink = _Sink.new()
	http.sink = many.sink
	await many.speak("line", text, "Kore")
	assert_eq(http.synth_posts, pieces.size())
	assert_true(int(http.seen_pushes[1]) >= 1)
	var play0 := many.chirp_events.find("play:0")
	var play1 := many.chirp_events.find("play:1")
	var end0 := many.chirp_events.find("end:0")
	var synth1 := many.chirp_events.find("synth:1")
	assert_true(play0 >= 0 and synth1 > play0 and end0 > play0 and play1 > end0, " ".join(many.chirp_events))
	many.free()
	_cleanup()


func test_chirp_playback_is_ordered_and_cancel_drops_the_rest() -> void:
	var pem := str(_rsa()["private"])
	_arm(pem)
	TtsQuota.selected_override = ChirpVoices.MODEL_ID
	var http := _http()
	var hold := _Hold.new()
	http.hold = hold
	var backend := _backend([])
	backend.sink = hold
	var text := "Раз. Два. Три. Четыре. Пять. Шесть."
	await backend.speak("line", text, "Kore")
	assert_eq(hold.overlaps, 0)
	assert_true(hold.plays >= 2)
	assert_true(bool(http.saw_playing_during_prefetch))
	var play0 := backend.chirp_events.find("play:0")
	var play1 := backend.chirp_events.find("play:1")
	var end0 := backend.chirp_events.find("end:0")
	assert_true(play1 > end0 and end0 > play0)
	backend.free()
	http.hold = null
	http.synth_posts = 0
	http.cancel_on_second = true
	var again := _backend([])
	again.sink = _Hold.new()
	http.backend = again
	await again.speak("line", text, "Kore")
	assert_false(again.chirp_events.has("play:1"))
	assert_true(again.chirp_events.has("play:0"))
	again.free()
	_cleanup()


func test_exhausted_gemini_falls_through_to_chirp() -> void:
	var pem := str(_rsa()["private"])
	_arm(pem)
	TtsQuota.selected_override = TtsQuota.chain()[0]
	TtsQuota.mark_exhausted(TtsQuota.chain()[0], TtsQuota.now_unix())
	TtsQuota.mark_exhausted(TtsQuota.chain()[1], TtsQuota.now_unix())
	TtsQuota.mark_probe(TtsQuota.now_unix())
	var http := _http()
	var backend := _backend([])
	backend.api_key = ""
	await backend.speak("line", "Дальше Chirp.", "Kore")
	assert_eq(backend.transport.calls.size(), 0)
	assert_eq(http.synth_posts, 1)
	assert_true(backend.chirp_events.has("play:0"))
	backend.free()
	_cleanup()


func test_chirp_rate_limit_retries_and_spend_counts_chars() -> void:
	var pem := str(_rsa()["private"])
	_arm(pem)
	var http := _http()
	http.fail_once = true
	SpendMeter.store_path = "user://chirp-spend-test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SpendMeter.store_path))
	SpendMeter.now_override = 1_767_225_600
	TtsQuota.selected_override = ChirpVoices.MODEL_ID
	var before := SpendMeter.session_usd
	var backend := _backend([])
	var started := backend._clock_s
	await backend.speak("line", "Раз два.", "Kore")
	assert_eq(http.synth_posts, 2)
	assert_true(backend._clock_s - started <= GeminiTtsBackend.SHORT_RETRY_CAP_S)
	assert_true(backend._clock_s - started > 0.0)
	var chars := "Раз два.".length()
	assert_true(is_equal_approx(SpendMeter.session_usd - before, SpendMeter.chirp_cost_usd(chars)))
	assert_eq(SpendMeter.chirp_chars_this_month(), chars)
	SpendMeter.now_override = 1_798_761_600
	assert_eq(SpendMeter.chirp_chars_this_month(), 0)
	backend.free()
	_cleanup()


func test_cache_hit_does_not_call_chirp_or_spend() -> void:
	var pem := str(_rsa()["private"])
	_arm(pem)
	var http := _http()
	var previous := TtsCache.root_path
	TtsCache.root_path = "user://tts-cache-chirp-test"
	TtsCache.erase_all()
	var text := "Из кэша."
	var voice := ChirpVoices.for_gemini("Kore")
	TtsCache.write(TtsCache.key_for(ChirpVoices.MODEL_ID, voice, "1.0", text), PackedByteArray([0, 64, 0, 64]))
	SpendMeter.store_path = "user://chirp-spend-cache.cfg"
	var before := SpendMeter.session_usd
	TtsQuota.selected_override = ChirpVoices.MODEL_ID
	var backend := _backend([])
	backend.use_cache = true
	await backend.speak("line", text, "Kore")
	assert_eq(http.synth_posts, 0)
	assert_eq(http.token_posts, 0)
	assert_true(is_equal_approx(SpendMeter.session_usd, before))
	TtsCache.erase_all()
	TtsCache.root_path = previous
	backend.free()
	_cleanup()


func test_settings_greys_chirp_until_a_key_is_present() -> void:
	ChirpAuth.key_override = ""
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/settings.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var models := screen.find_child("VoiceModel", true, false) as OptionButton
	var index := TtsQuota.chain().find(ChirpVoices.MODEL_ID)
	assert_eq(models.get_item_text(index), "Chirp 3 HD")
	assert_true(models.is_item_disabled(index))
	var hint := screen.find_child("ChirpHint", true, false) as Label
	assert_true(hint.text.contains("без ключа"))
	ChirpAuth.key_override = _account(str(_rsa()["private"]))
	screen.call("_refresh_tts_panel")
	assert_false(models.is_item_disabled(index))
	screen.free()
	_cleanup()


func _arm(pem: String) -> void:
	ChirpAuth.reset()
	ChirpAuth.key_override = _account(pem)
	ChirpAuth.now_override = 1_700_000_000
	ChirpAuth.transport = _Http.new()
	TtsQuota.store_path = "user://tts-quota-chirp.cfg"
	TtsQuota.now_override = 1_800_000_000
	TtsQuota.fallback_override = true
	TtsQuota.selected_override = TtsQuota.chain()[0]
	TtsQuota.reset()


func _cleanup() -> void:
	ChirpAuth.reset()
	ChirpAuth.key_override = null
	ChirpAuth.transport = null
	ChirpAuth.now_override = -1
	TtsQuota.reset()
	TtsQuota.store_path = "user://config.cfg"
	TtsQuota.now_override = -1
	TtsQuota.fallback_override = null
	TtsQuota.selected_override = null
	SpendMeter.store_path = "user://config.cfg"
	SpendMeter.now_override = -1
	if _holder != null and is_instance_valid(_holder):
		_holder.free()
		_holder = null


func _host() -> Node:
	if _holder == null or not is_instance_valid(_holder):
		_holder = Node.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(_holder)
	return _holder


func _http() -> _Http:
	return ChirpAuth.transport as _Http


func _account(pem: String) -> String:
	return JSON.stringify({
		"client_email": "demo@example.gserviceaccount.com",
		"private_key": pem,
	})


func _rsa() -> Dictionary:
	var key: CryptoKey = Crypto.new().generate_rsa(2048)
	return {"private": key.save_to_string(false), "public": key.save_to_string(true)}


func _b64url_decode(text: String) -> PackedByteArray:
	var padded := text.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0:
		padded += "="
	return Marshalls.base64_to_raw(padded)


func _log_has(fragment: String) -> bool:
	for line in Speaker.voice_log:
		if str(line).contains(fragment):
			return true
	return false


func _backend(scripted: Array) -> GeminiTtsBackend:
	var transport := _Gemini.new()
	transport.scripted = scripted
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	backend.sink = _Sink.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(backend)
	return backend


func _pkcs8_pem(pkcs1_pem: String) -> String:
	var der := ChirpAuth._pem_body(pkcs1_pem)
	var algorithm := PackedByteArray([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
	var version := PackedByteArray([0x02, 0x01, 0x00])
	var octet := PackedByteArray([0x04])
	octet.append_array(_der_len(der.size()))
	octet.append_array(der)
	var body := PackedByteArray()
	body.append_array(version)
	body.append_array(algorithm)
	body.append_array(octet)
	var outer := PackedByteArray([0x30])
	outer.append_array(_der_len(body.size()))
	outer.append_array(body)
	return ChirpAuth._pem_armor(outer, "PRIVATE KEY")


func _der_len(value: int) -> PackedByteArray:
	if value < 128:
		return PackedByteArray([value])
	return PackedByteArray([0x82, (value >> 8) & 255, value & 255])


func _quota() -> Dictionary:
	return {"ok": false, "status": 429, "error": "quota_daily", "retry_after": 86399.0, "usage": {}}


class _Gemini:
	extends RefCounted

	var scripted: Array = []
	var calls: Array = []

	func stream(request: Dictionary) -> Dictionary:
		calls.append({"path": request.get("path", "")})
		if scripted.is_empty():
			return {"ok": false, "status": 0, "error": "bad_response", "usage": {}}
		var outcome: Dictionary = scripted.pop_front()
		var on_chunk: Variant = request.get("on_chunk")
		if outcome.get("ok", false) and on_chunk is Callable:
			for chunk in outcome.get("chunks", []):
				if chunk is PackedByteArray:
					(on_chunk as Callable).call(chunk)
		return outcome


class _Http:
	extends RefCounted

	var token: String = "ya29.SECRETTOKEN"
	var token_posts: int = 0
	var synth_posts: int = 0
	var synth_bodies: Array = []
	var seen_pushes: Array = []
	var fail_once: bool = false
	var sink: Object = null
	var hold: Object = null
	var backend: Object = null
	var cancel_on_second: bool = false
	var saw_playing_during_prefetch: bool = false

	func post(url: String, body: String, _headers: PackedStringArray) -> Dictionary:
		if url.contains("text:synthesize"):
			seen_pushes.append(int(sink.pushes) if sink != null else 0)
			synth_posts += 1
			synth_bodies.append(body)
			if cancel_on_second and synth_posts >= 2 and backend != null:
				backend.call("stop")
				return {"status": 200, "body": "{\"audioContent\":\"\"}"}
			if hold != null and synth_posts >= 2 and int(hold.buffered) > 0:
				saw_playing_during_prefetch = true
				hold.call("release")
			if fail_once:
				fail_once = false
				return {"status": 429, "body": "{\"error\":{\"code\":429}}"}
			return {"status": 200, "body": JSON.stringify({"audioContent": Marshalls.raw_to_base64(PackedByteArray([0, 64, 0, 64]))})}
		token_posts += 1
		return {"status": 200, "body": JSON.stringify({"access_token": token, "expires_in": 3600})}


class _Sink:
	extends RefCounted

	var pushes: int = 0

	func start() -> void:
		pass

	func push(_frames: PackedVector2Array) -> void:
		pushes += 1


class _Hold:
	extends RefCounted

	var buffered: int = 0
	var plays: int = 0
	var overlaps: int = 0
	var hold: bool = true

	func start() -> void:
		pass

	func frames_available() -> int:
		return 100000

	func buffered_frames() -> int:
		return buffered if hold else 0

	func push(frames: PackedVector2Array) -> void:
		if buffered > 0:
			overlaps += 1
		buffered += frames.size()
		plays += 1

	func release() -> void:
		hold = false
		buffered = 0
