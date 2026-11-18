extends TestCase


func test_desktop_without_plugin_does_not_crash() -> void:
	assert_false(SystemStt.plugin_available())
	assert_true(SystemStt.system_option_disabled(false, false))
	assert_false(SystemStt.system_option_disabled(false, true))
	assert_false(SystemStt.system_option_disabled(true, false))
	var stt := SystemStt.new()
	_attach(stt)
	stt.start_listen()
	var result: Dictionary = await stt.finish_listen()
	assert_false(bool(result.get("ok", true)))
	assert_eq(str(result.get("error", "")), "unavailable")
	assert_eq(str(result.get("message", "")), SystemStt.hint_for_code("unavailable"))
	stt.free()


func test_error_codes_are_honest() -> void:
	assert_eq(SystemStt.hint_for_code("no_match"), "Не расслышал, повторите")
	assert_eq(SystemStt.hint_for_code("network"), "Нет сети для распознавания")
	assert_eq(SystemStt.hint_for_code("busy"), "Распознавание занято")
	assert_eq(SystemStt.hint_for_code("permissions"), "Нет разрешения на микрофон")
	assert_eq(SystemStt.code_from_android(7), "no_match")
	assert_eq(SystemStt.code_from_android(9), "permissions")
	assert_eq(SystemStt.code_from_android(1), "network_timeout")
	assert_eq(SystemStt.code_from_android(2), "network")
	assert_eq(SystemStt.code_from_android(3), "audio")
	assert_eq(SystemStt.code_from_android(4), "server")
	assert_eq(SystemStt.code_from_android(5), "client")
	assert_eq(SystemStt.code_from_android(6), "speech_timeout")
	assert_eq(SystemStt.code_from_android(10), "server_disconnected")
	assert_eq(SystemStt.code_from_android(11), "language_not_supported")
	assert_eq(SystemStt.code_from_android(12), "language_unavailable")
	assert_eq(SystemStt.code_from_android(13), "cannot_check")
	assert_eq(SystemStt.code_from_android(14), "too_many_requests")
	assert_eq(SystemStt.hint_for_code("server_disconnected"), "Сервер распознавания отключился")
	assert_eq(SystemStt.hint_for_code("language_not_supported"), "Язык распознавания не поддерживается")
	assert_eq(SystemStt.hint_for_code("language_unavailable"), "Язык распознавания недоступен")
	assert_eq(SystemStt.hint_for_code("cannot_check"), "Не удалось проверить распознавание")
	assert_eq(SystemStt.hint_for_code("audio"), "Не слышно микрофон. Говорите ближе")
	assert_eq(SystemStt.hint_for_code("client"), "Сбой распознавания на устройстве")
	assert_eq(SystemStt.hint_for_code("server"), "Сервер распознавания не ответил")
	assert_eq(SystemStt.hint_for_code("network_timeout"), "Истекло время сети распознавания")
	assert_eq(SystemStt.hint_for_code("language_unavailable"), "Язык распознавания недоступен")
	assert_eq(SystemStt.hint_for_code("too_many_requests"), "Слишком много запросов к распознаванию")
	assert_eq(SystemStt.hint_for_code("timeout"), "Повторить распознавание")
	assert_eq(GeminiStt.MODEL, "gemini-3.5-flash-lite")


func test_fake_plugin_hold_sends_and_does_not_spend() -> void:
	var host := Node.new()
	_attach(host)
	var fake := _FakeSpeech.new()
	var stt := SystemStt.new()
	stt.bridge = fake
	stt.prefer_offline = true
	var talk := PushToTalk.new()
	talk.stt = stt
	talk.enabled = true
	talk.screen_active = true
	host.add_child(stt)
	host.add_child(fake)
	host.add_child(talk)
	var sent: Array[String] = []
	var partials: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	talk.partial_changed.connect(func(text: String) -> void:
		partials.append(text)
	)
	var before := SpendMeter.session_stt_usd
	assert_true(talk.press())
	assert_eq(fake.started, 1)
	assert_true(fake.offline)
	await (Engine.get_main_loop() as SceneTree).process_frame
	talk.push_pcm(VoiceAudio.tone(VoiceAudio.UPLOAD_RATE, 3000))
	assert_false(partials.is_empty())
	await talk.release(false)
	assert_eq(fake.stopped, 1)
	assert_eq(sent, ["Где вы были?"])
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	assert_eq(SpendMeter.session_stt_usd, before)
	var line := TurnTiming.format_row(TurnTiming.turns.back())
	assert_true(line.contains("backend=system"))
	assert_true(line.contains("stt_done="))
	assert_true(line.contains("reused=no"))
	host.free()


func test_fake_plugin_error_then_retry() -> void:
	var host := Node.new()
	_attach(host)
	var fake := _FakeSpeech.new()
	fake.fail = "busy"
	var stt := SystemStt.new()
	stt.bridge = fake
	var talk := PushToTalk.new()
	talk.stt = stt
	talk.enabled = true
	talk.screen_active = true
	host.add_child(stt)
	host.add_child(fake)
	host.add_child(talk)
	var hints: Array[String] = []
	var sent: Array[String] = []
	talk.hint_changed.connect(func(text: String) -> void: hints.append(text))
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	await talk.release(false)
	assert_false(talk.locked)
	assert_true(hints[hints.size() - 1] == SystemStt.hint_for_code("busy"))
	await talk.retry()
	assert_eq(sent, ["Где вы были?"])
	assert_false(talk.locked)
	host.free()


func test_early_final_is_ready_on_release() -> void:
	var host := Node.new()
	_attach(host)
	var fake := _FakeSpeech.new()
	fake.finish_immediately = true
	var stt := SystemStt.new()
	stt.bridge = fake
	var talk := PushToTalk.new()
	talk.stt = stt
	talk.enabled = true
	talk.screen_active = true
	host.add_child(stt)
	host.add_child(fake)
	host.add_child(talk)
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	await talk.release(false)
	assert_eq(sent, ["Где вы были?"])
	assert_false(talk.locked)
	host.free()


func test_cancel_ignores_a_late_result() -> void:
	var host := Node.new()
	_attach(host)
	var fake := _FakeSpeech.new()
	fake.hold_result = true
	var stt := SystemStt.new()
	stt.bridge = fake
	var talk := PushToTalk.new()
	talk.stt = stt
	talk.enabled = true
	talk.screen_active = true
	host.add_child(stt)
	host.add_child(fake)
	host.add_child(talk)
	var sent: Array[String] = []
	talk.submit = func(text: String) -> void:
		sent.append(text)
	assert_true(talk.press())
	fake.on_stop = func() -> void:
		talk.cancel()
	await talk.release(false)
	fake.emit_signal("finished", "опоздало")
	assert_eq(sent.size(), 0)
	assert_false(talk.locked)
	assert_eq(talk.state_name, PushToTalk.STATE_IDLE)
	assert_true(fake.cancelled > 0)
	host.free()


func test_listen_timeout_offers_retry() -> void:
	var host := Node.new()
	_attach(host)
	var fake := _FakeSpeech.new()
	fake.hold_result = true
	var stt := SystemStt.new()
	stt.bridge = fake
	stt.listen_timeout_s = 0.05
	host.add_child(stt)
	host.add_child(fake)
	stt.start_listen()
	var result: Dictionary = await stt.finish_listen()
	assert_false(bool(result.get("ok", true)))
	assert_eq(str(result.get("error", "")), "timeout")
	assert_eq(str(result.get("message", "")), "Повторить распознавание")
	host.free()


func test_unavailable_system_selection_resets_to_gemini_once() -> void:
	assert_eq(SettingsStore.choose_stt("system", false), "gemini")
	assert_eq(SettingsStore.choose_stt("system", true), "system")
	assert_eq(SettingsStore.choose_stt("gemini", false), "gemini")
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var file := ConfigFile.new()
	file.parse(previous)
	file.set_value("mic", "stt", "system")
	file.save(path)
	var loaded := SettingsStore.load_current()
	assert_eq(loaded.stt_backend, "gemini")
	var check := ConfigFile.new()
	assert_eq(check.load(path), OK)
	assert_eq(str(check.get_value("mic", "stt", "")), "gemini")
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()


func test_turn_log_survives_other_voice_notes() -> void:
	TurnTiming.reset()
	for _index in 12:
		TurnTiming.begin("gemini")
		TurnTiming.mark("release")
		TurnTiming.publish()
	assert_eq(TurnTiming.lines().size(), 10)
	assert_eq(Speaker.turn_log.size(), 10)
	for index in 25:
		Speaker.note_line("mic noise %d" % index)
	assert_eq(TurnTiming.lines().size(), 10)
	assert_eq(Speaker.turn_log.size(), 10)
	assert_true(Speaker.voice_log.size() <= 20)
	TurnTiming.reset()


func test_gemini_stt_reuses_the_shared_session() -> void:
	var source := FileAccess.get_file_as_string("res://src/voice/gemini_stt.gd")
	assert_false(source.contains("HTTPRequest.new"))
	assert_true(source.contains("HttpSession.exchange"))
	HttpSession.reset()
	var made: Array = []
	HttpSession.maker = func(_host: String) -> ScriptedLink:
		var link := ScriptedLink.new()
		made.append(link)
		return link
	var host := Node.new()
	_attach(host)
	var transport := GeminiStt.GeminiSttTransport.new()
	host.add_child(transport)
	var headers := {"Content-Type": "application/json"}
	var first: Dictionary = await transport.request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", headers, "{}", 5.0)
	var second: Dictionary = await transport.request("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", headers, "{}", 5.0)
	assert_eq(int(first.get("status", 0)), 200)
	assert_eq(int(second.get("status", 0)), 200)
	assert_true(HttpSession.last_reused)
	assert_eq(made.size(), 1)
	HttpSession.reset()
	HttpSession.maker = Callable()
	host.free()


func test_connection_is_reused_until_it_drops() -> void:
	HttpSession.reset()
	var made: Array = []
	HttpSession.maker = func(_host: String) -> FakeLink:
		var link := FakeLink.new()
		made.append(link)
		return link
	var first := HttpSession.checkout("generativelanguage.googleapis.com")
	assert_false(bool(first.get("reused", true)))
	HttpSession.checkin("generativelanguage.googleapis.com", first.get("client"), true)
	var second := HttpSession.checkout("generativelanguage.googleapis.com")
	assert_true(bool(second.get("reused", false)))
	assert_eq(second.get("client"), first.get("client"))
	var link: FakeLink = second.get("client")
	link.status = HTTPClient.STATUS_DISCONNECTED
	HttpSession.checkin("generativelanguage.googleapis.com", link, false)
	assert_true(link.closed)
	var third := HttpSession.checkout("generativelanguage.googleapis.com")
	assert_false(bool(third.get("reused", true)))
	assert_eq(made.size(), 2)
	var parts := HttpSession.split_url("https://generativelanguage.googleapis.com/v1beta/models/x:generateContent")
	assert_eq(str(parts.get("host", "")), "generativelanguage.googleapis.com")
	assert_eq(int(parts.get("port", 0)), 443)
	assert_true(bool(parts.get("tls", false)))
	assert_true(str(parts.get("path", "")).begins_with("/v1beta"))
	HttpSession.reset()
	HttpSession.maker = Callable()


func test_turn_log_keeps_ten_and_names_the_span() -> void:
	TurnTiming.reset()
	TurnTiming.begin("gemini")
	TurnTiming.mark("release")
	TurnTiming.note_reused(true)
	TurnTiming.mark("first_audio")
	var line := TurnTiming.format_row(TurnTiming.turns.back())
	assert_true(line.contains("backend=gemini"))
	assert_true(line.contains("reused=yes"))
	assert_true(line.contains("total="))
	TurnTiming.reset()
	for _index in 12:
		TurnTiming.begin("gemini")
	assert_eq(TurnTiming.turns.size(), TurnTiming.LIMIT)
	var source := FileAccess.get_file_as_string("res://addons/system_speech/src/SystemSpeechPlugin.kt")
	assert_true(source.contains("SpeechRecognizer"))
	assert_true(source.contains("runOnUiThread"))
	assert_true(source.contains("ru-RU"))
	assert_true(source.contains("EXTRA_PARTIAL_RESULTS"))
	assert_true(source.contains("EXTRA_PREFER_OFFLINE"))
	assert_true(source.contains("latestPartial"))
	assert_true(source.contains("onMainDestroy"))
	assert_true(source.contains("ERROR_AUDIO"))
	assert_true(source.contains("ERROR_CLIENT"))
	assert_true(source.contains("isOnDeviceRecognitionAvailable"))
	assert_true(source.contains("createOnDeviceSpeechRecognizer"))
	var manifest := FileAccess.get_file_as_string("res://addons/system_speech/export_plugin.gd")
	assert_true(manifest.contains("android.speech.RecognitionService"))
	var stage := FileAccess.get_file_as_string("res://tools/stage_system_speech.sh")
	assert_true(stage.contains("src/main/kotlin"))
	var lines := SystemStt.status_lines()
	var joined := "\n".join(lines)
	assert_true(joined.contains("plugin=missing"))
	assert_true(joined.contains("recognition_service=unknown"))
	assert_true(joined.contains("on_device=unknown"))
	assert_true(joined.contains("record_audio=n/a"))
	assert_eq(SystemStt.user_hint(), "Системное распознавание не встроено в сборку")
	_assert_apk_checker()
	var workflow := FileAccess.get_file_as_string("res://.github/workflows/build.yml")
	assert_true(workflow.contains("stage_system_speech.sh"))
	assert_false(workflow.contains("Windows Desktop"))


func _assert_apk_checker() -> void:
	var good := "user://speech-good.apk"
	var bad := "user://speech-bad.apk"
	_zip(good, true)
	_zip(bad, false)
	var script := ProjectSettings.globalize_path("res://tools/check_system_speech_apk.py")
	assert_eq(_python(script, ProjectSettings.globalize_path(good)), 0)
	assert_false(_python(script, ProjectSettings.globalize_path(bad)) == 0)
	DirAccess.remove_absolute(good)
	DirAccess.remove_absolute(bad)


func _zip(path: String, complete: bool) -> void:
	var zipper := ZIPPacker.new()
	assert_eq(zipper.open(path), OK)
	zipper.start_file("classes.dex")
	var dex := "SystemSpeechPlugin" if complete else "nothing"
	zipper.write_file(dex.to_utf8_buffer())
	zipper.close_file()
	zipper.start_file("AndroidManifest.xml")
	var manifest := "android.speech.RecognitionService org.godotengine.plugin.v2.SystemSpeech SystemSpeechPlugin" if complete else "empty"
	zipper.write_file(manifest.to_utf8_buffer())
	zipper.close_file()
	zipper.close()


func _python(script: String, apk: String) -> int:
	var output: Array = []
	return OS.execute("python3", PackedStringArray([script, apk]), output, true)


func _attach(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


class ScriptedLink:
	extends RefCounted

	var status: int = HTTPClient.STATUS_DISCONNECTED
	var read_once: bool = false

	func get_status() -> int:
		return status

	func connect_to_host(_host: String, _port: int, _tls: TLSOptions = null) -> int:
		status = HTTPClient.STATUS_CONNECTED
		return OK

	func poll() -> void:
		pass

	func request(_method: int, _path: String, _headers: PackedStringArray, _body: String) -> int:
		read_once = false
		status = HTTPClient.STATUS_BODY
		return OK

	func get_response_code() -> int:
		return 200

	func read_response_body_chunk() -> PackedByteArray:
		if read_once:
			status = HTTPClient.STATUS_CONNECTED
			return PackedByteArray()
		read_once = true
		return PackedByteArray([123, 125])

	func close() -> void:
		status = HTTPClient.STATUS_DISCONNECTED


class FakeLink:
	extends RefCounted

	var status: int = HTTPClient.STATUS_CONNECTED
	var closed: bool = false

	func get_status() -> int:
		return status

	func close() -> void:
		closed = true
		status = HTTPClient.STATUS_DISCONNECTED


class _FakeSpeech:
	extends Node

	signal partial(text: String)
	signal finished(text: String)
	signal failed(code: String)

	var available: bool = true
	var offline: bool = false
	var started: int = 0
	var stopped: int = 0
	var text: String = "Где вы были?"
	var fail: String = ""
	var partial_line: String = "Где"
	var finish_immediately: bool = false
	var hold_result: bool = false
	var cancelled: int = 0
	var on_stop: Callable = Callable()

	func isAvailable() -> bool:
		return available

	func startListening(prefer: bool) -> void:
		started += 1
		offline = prefer
		if finish_immediately:
			emit_signal("finished", text)
			return
		call_deferred("emit_signal", "partial", partial_line)

	func stopListening() -> void:
		stopped += 1
		if on_stop.is_valid():
			on_stop.call()
		if hold_result:
			return
		if fail != "":
			call_deferred("emit_signal", "failed", fail)
		else:
			call_deferred("emit_signal", "finished", text)

	func cancelListening() -> void:
		cancelled += 1

	func partialText() -> String:
		return partial_line

	func recover() -> Dictionary:
		fail = ""
		return {"ok": true, "text": text, "error": "", "message": "", "usage": {}}
