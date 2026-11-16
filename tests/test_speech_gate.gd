extends TestCase


func test_each_sentence_once_and_not_the_whole_line_again() -> void:
	var gate := SpeechGate.new()
	var line_id := gate.open()
	assert_true(gate.accept(line_id, "Первое."))
	assert_true(gate.accept(line_id, "Второе."))
	assert_false(gate.accept(line_id, "Первое."))
	assert_false(gate.accept(line_id, "Первое. Второе."))
	assert_eq(SpeechGate.unsaid("Первое. Второе.", "Первое."), "Второе.")
	assert_eq(SpeechGate.unsaid("Первое. Второе.", "Первое. Второе."), "")
	assert_eq(SpeechGate.unsaid("Первое.", "Другое"), "")


func test_fallback_and_route_play_only_one_engine() -> void:
	var live_only := SpeechGate.engines_played(VoiceRoute.LIVE, true, true)
	assert_eq(live_only.size(), 1)
	assert_eq(live_only[0], VoiceRoute.LIVE)
	var live_failed := SpeechGate.engines_played(VoiceRoute.LIVE, true, false)
	assert_eq(live_failed.size(), 1)
	assert_eq(live_failed[0], VoiceRoute.READER)
	var reader := SpeechGate.engines_played(VoiceRoute.READER, true, true)
	assert_eq(reader.size(), 1)
	assert_eq(reader[0], VoiceRoute.READER)
	var reader_failed := SpeechGate.engines_played(VoiceRoute.READER, false, true)
	assert_eq(reader_failed.size(), 1)
	assert_eq(reader_failed[0], VoiceRoute.LIVE)


func test_confirmed_guess_is_spoken_once_and_dropped_guess_is_not() -> void:
	var gate := SpeechGate.new()
	var dropped := gate.open()
	assert_false(gate.accept(dropped, ""))
	var confirmed := gate.open()
	assert_false(gate.accept(dropped, "Реплика."))
	assert_true(gate.accept(confirmed, "Реплика."))
	assert_false(gate.accept(confirmed, "Реплика."))


func test_log_and_signal_happen_once() -> void:
	var gate := SpeechGate.new()
	assert_eq(gate.log_once(7, "live"), "озвучка начата id=7 движок=live")
	assert_eq(gate.log_once(7, "reader"), "")
	var timer := Timer.new()
	var hits := [0]
	var callback := func() -> void:
		hits[0] += 1
	SpeechGate.connect_once(timer.timeout, callback)
	SpeechGate.connect_once(timer.timeout, callback)
	assert_eq(timer.timeout.get_connections().size(), 1)
	timer.free()
