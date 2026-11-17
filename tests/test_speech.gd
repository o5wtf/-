extends TestCase


func test_cleaner_keeps_the_reply_and_drops_markup() -> void:
	assert_eq(SpeechText.clean("Я был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("Я был дома. *отводит взгляд*"), "Я был дома.")
	assert_eq(SpeechText.clean("Я был дома. (тихо) [angry]"), "Я был дома.")
	assert_eq(SpeechText.clean("**Я** был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("- Я был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("Я нейросеть и всё знаю про промпт."), "Я и всё знаю про.")
	assert_eq(SpeechText.clean("тон: +3\nЯ был дома."), "Я был дома.")
	assert_eq(SpeechText.clean("ремарка: отводит взгляд"), "")
	assert_eq(SpeechText.clean("ИИ сказал привет."), "сказал привет.")
	assert_false(SpeechText.clean("Я был дома.").contains("*"))


func test_queue_speaks_once_and_in_order() -> void:
	var queue := SpeechQueue.new()
	assert_true(queue.enqueue("a", "первая"))
	assert_false(queue.enqueue("a", "первая ещё раз"))
	assert_true(queue.enqueue("b", "вторая"))
	assert_false(queue.enqueue("", "пусто"))
	assert_false(queue.enqueue("c", "   "))
	var first := queue.take_next()
	assert_eq(first["id"], "a")
	assert_true(queue.take_next().is_empty())
	queue.finish("a")
	var second := queue.take_next()
	assert_eq(second["id"], "b")
	queue.finish("b")
	assert_true(queue.take_next().is_empty())


func test_queue_stop_clears_and_reset_allows_the_id_again() -> void:
	var queue := SpeechQueue.new()
	assert_true(queue.enqueue("a", "первая"))
	assert_true(queue.enqueue("b", "вторая"))
	assert_eq(queue.take_next()["id"], "a")
	queue.stop()
	assert_eq(queue.current_id, "")
	assert_true(queue.pending.is_empty())
	assert_true(queue.take_next().is_empty())
	assert_false(queue.enqueue("a", "снова"))
	queue.reset()
	assert_true(queue.enqueue("a", "снова"))


func test_voice_choice_prefers_russian_then_any() -> void:
	var russian := [{"id": "ru-1", "name": "Анна", "language": "ru"}]
	var other := [{"id": "en-1", "name": "Anna", "language": "en"}]
	assert_eq(SystemTtsBackend.choose_voice("", russian, other), "ru-1")
	assert_eq(SystemTtsBackend.choose_voice("en-1", [], other), "en-1")
	assert_eq(SystemTtsBackend.choose_voice("", [], other), "en-1")
	assert_eq(SystemTtsBackend.choose_voice("", [], []), "")
	assert_eq(SystemTtsBackend.choose_voice("Анна", russian, other), "ru-1")


func test_manifest_requests_tts_service() -> void:
	var xml := TtsManifest.queries_xml()
	assert_true(xml.contains("<queries>"))
	assert_true(xml.contains("android.intent.action.TTS_SERVICE"))


func test_empty_voices_are_retried_then_russian_is_used() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(language: String, call_index: int) -> Array:
		if call_index < 5:
			return []
		if language == "ru":
			return [{"id": "ru-1", "name": "Анна", "language": "ru"}]
		return [{"id": "ru-1", "language": "ru"}, {"id": "en-1", "language": "en"}]
	var backend := _backend(driver)
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Проверка.", "")
	assert_true(errors.is_empty())
	assert_eq(driver.spoken, ["ru-1"])
	assert_true(driver.voice_calls > 2)
	assert_eq(backend.last_russian_count, 1)
	backend.free()


func test_missing_russian_uses_any_voice_without_waiting() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(language: String, _call_index: int) -> Array:
		if language == "ru":
			return []
		return [{"id": "en-1", "name": "Anna", "language": "en"}]
	var backend := _backend(driver)
	await backend.speak("line", "Проверка.", "")
	assert_eq(driver.spoken, ["en-1"])
	assert_eq(backend.last_error, "")
	assert_true(driver.voice_calls == 2)
	backend.free()


func test_blank_voice_id_is_still_spoken() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(language: String, _call_index: int) -> Array:
		if language == "ru":
			return []
		return [{"id": "", "name": "Default", "language": "en"}]
	var backend := _backend(driver)
	await backend.speak("line", "Проверка.", "")
	assert_eq(driver.spoken, [""])
	assert_eq(backend.last_error, "")
	backend.free()


func test_no_voice_only_after_the_retry_window() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(_language: String, _call_index: int) -> Array:
		return []
	var backend := _backend(driver)
	var errors: Array[String] = []
	backend.speech_error.connect(func(_id: String, kind: String) -> void: errors.append(kind))
	await backend.speak("line", "Проверка.", "")
	assert_eq(errors, ["no_voice"])
	assert_true(driver.spoken.is_empty())
	assert_true(backend._clock_s >= SystemTtsBackend.RETRY_WINDOW_S)
	assert_eq(backend.diagnostics()["voices"], 0)
	assert_eq(backend.diagnostics()["error"], "no_voice")
	backend.free()


func test_startup_does_not_cache_an_empty_voice_list() -> void:
	var driver := ScriptedTts.new()
	driver.voices_plan = func(_language: String, _call_index: int) -> Array:
		return [{"id": "ru-1", "language": "ru"}]
	var backend := SystemTtsBackend.new()
	backend.driver = driver
	backend._instant = true
	(Engine.get_main_loop() as SceneTree).root.add_child(backend)
	assert_eq(driver.voice_calls, 0)
	await backend.speak("line", "Проверка.", "")
	assert_true(driver.voice_calls >= 2)
	backend.free()


func _backend(driver: ScriptedTts) -> SystemTtsBackend:
	var backend := SystemTtsBackend.new()
	backend.driver = driver
	backend._instant = true
	(Engine.get_main_loop() as SceneTree).root.add_child(backend)
	return backend


func test_speaker_queues_without_interrupting_and_stop_clears() -> void:
	var speaker: Node = load("res://src/voice/speaker.gd").new()
	speaker.set("listen_to_game", false)
	var fake := FakeBackend.new()
	speaker.set("backend", fake)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(speaker)
	speaker.set("enabled", true)
	var states: Array[bool] = []
	speaker.connect("is_speaking", func(active: bool) -> void: states.append(active))
	var first_id := str(speaker.call("line_id_for", "a"))
	speaker.call("speak_reply", "a", "Первая реплика.")
	assert_eq(fake.calls, [first_id])
	assert_true(bool(speaker.get("speaking")))
	speaker.call("speak_reply", "a", "Первая реплика ещё раз.")
	assert_eq(fake.calls.size(), 1)
	var queue: SpeechQueue = speaker.get("queue")
	assert_true(queue.enqueue("next", "вторая"))
	speaker.call("_pump")
	assert_eq(fake.calls.size(), 1)
	fake.finished.emit(first_id)
	assert_eq(fake.calls, [first_id, "next"])
	queue.enqueue("later", "третья")
	speaker.call("stop_and_clear")
	assert_false(bool(speaker.get("speaking")))
	assert_true(queue.pending.is_empty())
	assert_eq(fake.calls[fake.calls.size() - 1], "stop")
	fake.finished.emit("next")
	assert_eq(fake.calls.size(), 3)
	speaker.free()
	assert_true(states[0])
	assert_false(states[states.size() - 1])


class ScriptedTts:
	extends RefCounted

	var voices_plan: Callable
	var voice_calls: int = 0
	var spoken: Array[String] = []

	func voices(language: String) -> Array:
		voice_calls += 1
		var listed: Variant = voices_plan.call(language, voice_calls)
		if listed is Array:
			return listed
		return []

	func speak(_text: String, voice_id: String, _utterance_id: int) -> void:
		spoken.append(voice_id)

	func stop() -> void:
		pass

	func bind(_started: Callable, _finished: Callable, _canceled: Callable) -> void:
		pass

	func has_tts() -> bool:
		return true


class FakeBackend:
	extends SpeechBackend

	var calls: Array[String] = []

	func speak(line_id: String, _text: String, _voice_hint: String = "") -> void:
		calls.append(line_id)
		started.emit(line_id)

	func stop() -> void:
		calls.append("stop")
