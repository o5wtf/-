extends TestCase
## Цепочка озвучки идёт вниз от выбранной модели. Автовыключение оставляет только её.


func test_chain_order_is_the_model_list() -> void:
	var ids := TtsQuota.chain()
	assert_eq(ids.size(), TtsQuota.MODELS.size())
	assert_eq(ids[0], "gemini-3.8-flash-lite-tts")
	assert_eq(ids[1], "gemini-3.8-flash-tts")
	assert_eq(TtsQuota.label_for(ids[0]), "3.8 Flash Lite TTS")
	assert_eq(TtsQuota.label_for(ids[1]), "3.8 Flash TTS")
	_begin()
	assert_eq(TtsQuota.next_open(ids[1], TtsQuota.now_unix()), "")
	assert_eq(TtsQuota.next_open(ids[0], TtsQuota.now_unix()), ids[1])
	_end()


func test_daily_quota_walks_down_from_the_selected_model() -> void:
	_begin()
	var pair := _backend([_quota(), _audio()])
	var backend: GeminiTtsBackend = pair[0]
	var transport: _Script = pair[1]
	TurnTiming.begin("gemini")
	var started := backend._clock_s
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(transport.calls.size(), 2)
	assert_true(_path(transport, 0).contains(TtsQuota.chain()[0]))
	assert_true(_path(transport, 1).contains(TtsQuota.chain()[1]))
	assert_false(_path(transport, 1).contains(TtsQuota.chain()[0]))
	assert_true(TtsQuota.is_exhausted(TtsQuota.chain()[0], TtsQuota.now_unix()))
	assert_false(TtsQuota.is_exhausted(TtsQuota.chain()[1], TtsQuota.now_unix()))
	assert_true(backend._clock_s - started < 1.0)
	assert_true(_voice_has("tts model=%s reason=quota_daily" % TtsQuota.chain()[1]))
	assert_true(TurnTiming.format_row(TurnTiming.turns.back()).contains("tts_reason=quota_daily"))
	var flash := SpendMeter.cost_usd(TtsQuota.chain()[1], 1000, 0, 2000)
	var lite := SpendMeter.cost_usd(TtsQuota.chain()[0], 1000, 0, 2000)
	assert_true(is_equal_approx(flash / lite, 0.014 / 0.009))
	_release(backend)


func test_selected_flash_never_walks_up_to_lite() -> void:
	_begin()
	TtsQuota.selected_override = TtsQuota.chain()[1]
	var pair := _backend([_quota()])
	var backend: GeminiTtsBackend = pair[0]
	var transport: _Script = pair[1]
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(transport.calls.size(), 1)
	assert_true(_path(transport, 0).contains(TtsQuota.chain()[1]))
	assert_false(_path(transport, 0).contains(TtsQuota.chain()[0]))
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("quota_daily"))
	_release(backend)


func test_auto_off_uses_only_the_selected_model() -> void:
	_begin()
	TtsQuota.fallback_override = false
	var pair := _backend([_quota()])
	var backend: GeminiTtsBackend = pair[0]
	var transport: _Script = pair[1]
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(transport.calls.size(), 1)
	assert_true(_path(transport, 0).contains(TtsQuota.chain()[0]))
	assert_true(errors[0].contains("quota_daily"))
	assert_false(TtsQuota.is_exhausted(TtsQuota.chain()[0], TtsQuota.now_unix()))
	_release(backend)


func test_per_minute_and_network_stay_on_the_same_model() -> void:
	_begin()
	var limited := _backend([
		{"ok": false, "status": 429, "error": "rate_limited", "retry_after": 30.0, "usage": {}},
		_audio(),
	])
	var backend: GeminiTtsBackend = limited[0]
	var transport: _Script = limited[1]
	var started := backend._clock_s
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(transport.calls.size(), 2)
	assert_true(_path(transport, 0).contains(TtsQuota.chain()[0]))
	assert_true(_path(transport, 1).contains(TtsQuota.chain()[0]))
	assert_true(backend._clock_s - started <= GeminiTtsBackend.SHORT_RETRY_CAP_S)
	assert_true(backend._clock_s - started > 0.0)
	_release(backend)
	var broken := _backend([{"ok": false, "status": 0, "error": "network", "usage": {}}])
	var network: GeminiTtsBackend = broken[0]
	var calls: _Script = broken[1]
	await network.speak("line", "Привет.", "Kore")
	assert_eq(calls.calls.size(), 1)
	assert_true(_path(calls, 0).contains(TtsQuota.chain()[0]))
	_release(network)
	var busy := _backend([
		{"ok": false, "status": 503, "error": "overloaded", "usage": {}},
		{"ok": false, "status": 503, "error": "overloaded", "usage": {}},
		{"ok": false, "status": 503, "error": "overloaded", "usage": {}},
	])
	var retry: GeminiTtsBackend = busy[0]
	var again: _Script = busy[1]
	await retry.speak("line", "Привет.", "Kore")
	assert_eq(again.calls.size(), GeminiTtsBackend.MAX_ATTEMPTS)
	for index in again.calls.size():
		assert_true(_path(again, index).contains(TtsQuota.chain()[0]))
	_release(retry)


func test_known_exhaustion_skips_until_the_hourly_probe() -> void:
	_begin()
	TtsQuota.selected_override = TtsQuota.chain()[1]
	var now := TtsQuota.now_unix()
	TtsQuota.mark_exhausted(TtsQuota.chain()[1], now)
	TtsQuota.mark_probe(now)
	var held := TtsQuota.choose(now + 10)
	assert_true(bool(held.get("skip", false)))
	assert_eq(str(held.get("model", "")), TtsQuota.chain()[1])
	var pair := _backend([])
	var backend: GeminiTtsBackend = pair[0]
	var transport: _Script = pair[1]
	await backend.speak("line", "Привет.", "Kore")
	assert_eq(transport.calls.size(), 0)
	backend.free()
	TtsQuota.now_override = now + TtsQuota.PROBE_INTERVAL_S
	var probe := TtsQuota.choose(TtsQuota.now_unix())
	assert_eq(str(probe.get("model", "")), TtsQuota.chain()[1])
	assert_eq(str(probe.get("reason", "")), "hourly_probe")
	var opened := _backend([_audio()])
	var again: GeminiTtsBackend = opened[0]
	var calls: _Script = opened[1]
	await again.speak("line", "Снова.", "Kore")
	assert_eq(calls.calls.size(), 1)
	assert_true(_path(calls, 0).contains(TtsQuota.chain()[1]))
	assert_false(_path(calls, 0).contains(TtsQuota.chain()[0]))
	assert_false(TtsQuota.is_exhausted(TtsQuota.chain()[1], TtsQuota.now_unix()))
	_release(again)


func test_quota_survives_reload_until_los_angeles_midnight() -> void:
	_begin()
	var spring := PacificTime._utc(2026, 3, 8, 9, 0, 0)
	assert_eq(PacificTime._nth_sunday(2026, 3, 2), 8)
	assert_eq(PacificTime._nth_sunday(2026, 11, 1), 1)
	assert_eq(PacificTime.offset_seconds(spring), PacificTime.PST)
	assert_eq(PacificTime.next_midnight_utc(spring), PacificTime._utc(2026, 3, 9, 7, 0, 0))
	assert_eq(PacificTime.offset_seconds(PacificTime._utc(2026, 3, 8, 10, 0, 0)), PacificTime.PDT)
	var autumn := PacificTime._utc(2026, 11, 1, 8, 30, 0)
	assert_eq(PacificTime.offset_seconds(autumn), PacificTime.PDT)
	assert_eq(PacificTime.next_midnight_utc(autumn), PacificTime._utc(2026, 11, 2, 8, 0, 0))
	assert_eq(PacificTime.offset_seconds(PacificTime._utc(2026, 11, 1, 9, 0, 0)), PacificTime.PST)
	assert_eq(PacificTime.next_midnight_utc(PacificTime._utc(2026, 7, 15, 20, 0, 0)), PacificTime._utc(2026, 7, 16, 7, 0, 0))
	assert_eq(PacificTime.next_midnight_utc(PacificTime._utc(2026, 1, 15, 10, 0, 0)), PacificTime._utc(2026, 1, 16, 8, 0, 0))
	TtsQuota.now_override = spring
	TtsQuota.mark_exhausted(TtsQuota.chain()[0], spring)
	TtsQuota.mark_probe(spring)
	var until := TtsQuota.exhausted_until(TtsQuota.chain()[0])
	var file := ConfigFile.new()
	assert_eq(file.load(TtsQuota.store_path), OK)
	assert_eq(int(file.get_value("tts_quota", "until_gemini-3_8-flash-lite-tts", 0)), until)
	assert_eq(until, PacificTime._utc(2026, 3, 9, 7, 0, 0))
	TtsQuota.now_override = spring + 10
	assert_true(TtsQuota.is_exhausted(TtsQuota.chain()[0], TtsQuota.now_unix()))
	var note := TtsQuota.status_line(TtsQuota.now_unix())
	assert_true(note.contains("3.8 Flash TTS"), note)
	assert_true(note.contains("Выбранный недоступен до"), note)
	TtsQuota.now_override = until
	assert_false(TtsQuota.is_exhausted(TtsQuota.chain()[0], TtsQuota.now_unix()))
	var home := TtsQuota.choose(until)
	assert_eq(str(home.get("model", "")), TtsQuota.chain()[0])
	assert_eq(str(home.get("reason", "")), "primary")
	_end()


func test_cache_hit_does_not_clear_exhaustion_or_spend_the_probe() -> void:
	_begin()
	var previous := TtsCache.root_path
	TtsCache.root_path = "user://tts-cache-fallback-test"
	TtsCache.erase_all()
	var lite := TtsQuota.chain()[0]
	var flash := TtsQuota.chain()[1]
	var same := "Привет."
	assert_false(TtsCache.key_for(lite, "Kore", "", same) == TtsCache.key_for(flash, "Kore", "", same))
	TtsQuota.mark_exhausted(lite, TtsQuota.now_unix())
	TtsCache.write(TtsCache.key_for(lite, "Kore", "", same), PackedByteArray([0, 64, 0, 64]))
	var pair := _backend([])
	var backend: GeminiTtsBackend = pair[0]
	backend.use_cache = true
	var transport: _Script = pair[1]
	await backend.speak("line", same, "Kore")
	assert_eq(transport.calls.size(), 0)
	assert_true(TtsQuota.is_exhausted(lite, TtsQuota.now_unix()))
	assert_true(TtsQuota.probe_due(TtsQuota.now_unix()))
	TtsCache.erase_all()
	TtsCache.root_path = previous
	_release(backend)


func test_greeting_prefetch_uses_the_same_chain() -> void:
	_begin()
	var pair := _backend([_quota(), _audio()])
	var backend: GeminiTtsBackend = pair[0]
	var transport: _Script = pair[1]
	var outcome := await backend.prefetch("Здравствуйте.", "Kore", "")
	assert_eq(outcome, "stored")
	assert_eq(transport.calls.size(), 2)
	assert_true(_path(transport, 0).contains(TtsQuota.chain()[0]))
	assert_true(_path(transport, 1).contains(TtsQuota.chain()[1]))
	_release(backend)


func test_gemini_settings_migrate_to_google_lite_and_auto() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var file := ConfigFile.new()
	file.parse(previous)
	file.set_value("llm", "settings_version", 8)
	file.set_value("voice", "engine", "gemini")
	if file.has_section_key("voice", "tts_model"):
		file.erase_section_key("voice", "tts_model")
	if file.has_section_key("voice", "tts_auto"):
		file.erase_section_key("voice", "tts_auto")
	file.save(path)
	var gemini := SettingsStore.load_current()
	assert_eq(gemini.voice_engine, "gemini")
	assert_eq(gemini.tts_model, TtsQuota.chain()[0])
	assert_true(gemini.tts_auto)
	file.set_value("llm", "settings_version", 8)
	file.set_value("voice", "engine", "system")
	if file.has_section_key("voice", "tts_model"):
		file.erase_section_key("voice", "tts_model")
	if file.has_section_key("voice", "tts_auto"):
		file.erase_section_key("voice", "tts_auto")
	file.save(path)
	var system := SettingsStore.load_current()
	assert_eq(system.voice_engine, "system")
	assert_eq(system.tts_model, TtsQuota.chain()[0])
	assert_true(system.tts_auto)
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()


func test_settings_lists_models_from_the_chain() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var screen := (load("res://ui/screens/settings.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var models := screen.find_child("VoiceModel", true, false) as OptionButton
	var auto := screen.find_child("VoiceAuto", true, false) as CheckBox
	var engine := screen.find_child("VoiceEngine", true, false) as OptionButton
	assert_eq(models.item_count, TtsQuota.chain().size())
	for index in TtsQuota.chain().size():
		assert_eq(models.get_item_text(index), TtsQuota.label_for(TtsQuota.chain()[index]))
	assert_eq(auto.text, "Автопереключение")
	assert_eq(engine.get_item_text(0), "Системный голос")
	assert_eq(engine.get_item_text(1), "Google")
	engine.select(0)
	screen.call("_refresh_tts_panel")
	assert_false(models.visible)
	engine.select(1)
	screen.call("_refresh_tts_panel")
	assert_true(models.visible)
	assert_true(auto.visible)
	var note := screen.find_child("VoiceModelNote", true, false) as Label
	assert_true(note.text.contains("Сейчас голос:"))
	screen.free()


func _begin() -> void:
	TtsQuota.store_path = "user://tts-quota-test.cfg"
	TtsQuota.now_override = 1_800_000_000
	TtsQuota.fallback_override = true
	TtsQuota.selected_override = TtsQuota.chain()[0]
	TtsQuota.reset()
	TurnTiming.reset()


func _end() -> void:
	TtsQuota.reset()
	TtsQuota.store_path = "user://config.cfg"
	TtsQuota.now_override = -1
	TtsQuota.fallback_override = null
	TtsQuota.selected_override = null
	TurnTiming.reset()


func _release(backend: Node) -> void:
	backend.free()
	_end()


func _backend(scripted: Array) -> Array:
	var transport := _Script.new()
	transport.scripted = scripted
	var backend := GeminiTtsBackend.new()
	backend.transport = transport
	backend.api_key = "unit-test-key"
	backend.use_cache = false
	backend._instant = true
	backend.sink = _Sink.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(backend)
	return [backend, transport]


func _path(transport: _Script, index: int) -> String:
	return str(transport.calls[index].get("path", ""))


func _voice_has(fragment: String) -> bool:
	for line in Speaker.voice_log:
		if str(line).contains(fragment):
			return true
	return false


func _quota() -> Dictionary:
	return {"ok": false, "status": 429, "error": "quota_daily", "retry_after": 86399.0, "usage": {}}


func _audio() -> Dictionary:
	return {
		"ok": true,
		"status": 200,
		"error": "",
		"retry_after": 0.0,
		"usage": {"promptTokenCount": 1000, "candidatesTokenCount": 2000},
		"chunks": [PackedByteArray([0, 64, 0, 64])],
	}


class _Script:
	extends RefCounted

	var scripted: Array = []
	var calls: Array = []

	func stream(request: Dictionary) -> Dictionary:
		calls.append({"path": request.get("path", ""), "body": request.get("body", {})})
		var outcome: Dictionary = scripted.pop_front()
		var on_chunk: Variant = request.get("on_chunk")
		if outcome.get("ok", false) and on_chunk is Callable:
			for chunk in outcome.get("chunks", []):
				if chunk is PackedByteArray:
					(on_chunk as Callable).call(chunk)
		return outcome


class _Sink:
	extends RefCounted

	func start() -> void:
		pass

	func push(_frames: PackedVector2Array) -> void:
		pass
