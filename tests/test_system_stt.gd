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
	assert_eq(SystemStt.code_from_android(2), "network")
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
	var workflow := FileAccess.get_file_as_string("res://.github/workflows/build.yml")
	assert_true(workflow.contains("stage_system_speech.sh"))
	assert_false(workflow.contains("Windows Desktop"))


func _attach(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


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

	func isAvailable() -> bool:
		return available

	func startListening(prefer: bool) -> void:
		started += 1
		offline = prefer
		call_deferred("emit_signal", "partial", partial_line)

	func stopListening() -> void:
		stopped += 1
		if fail != "":
			call_deferred("emit_signal", "failed", fail)
		else:
			call_deferred("emit_signal", "finished", text)

	func partialText() -> String:
		return partial_line

	func recover() -> Dictionary:
		fail = ""
		return {"ok": true, "text": text, "error": "", "message": "", "usage": {}}
