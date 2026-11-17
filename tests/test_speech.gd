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


class FakeBackend:
	extends SpeechBackend

	var calls: Array[String] = []

	func speak(line_id: String, _text: String, _voice_hint: String = "") -> void:
		calls.append(line_id)
		started.emit(line_id)

	func stop() -> void:
		calls.append("stop")
