extends TestCase


func test_pause_sends_one_phrase_and_skips_noise() -> void:
	assert_false(Handsfree.accept_phrase("00:01"))
	assert_false(Handsfree.accept_phrase("а"))
	assert_false(Handsfree.accept_phrase("..."))
	assert_true(Handsfree.accept_phrase("Где"))
	var first := Handsfree.commit("Где вы были", "", 0)
	assert_true(first["send"])
	var repeat := Handsfree.commit("Где вы были", str(first["previous"]), 100)
	assert_false(repeat["send"])
	assert_eq(Handsfree.route(true), "submit")
	assert_eq(Handsfree.route(false), "partial")
	assert_eq(Handsfree.clamp_pause(100), 400)
	assert_eq(Handsfree.clamp_pause(2000), 1500)
	assert_eq(int(GeminiLive.activity_for(700)["silenceDurationMs"]), 700)


func test_echo_is_not_forwarded_and_reconnect_respects_the_toggle() -> void:
	assert_true(Handsfree.echo_blocked(true, 0))
	assert_true(Handsfree.echo_blocked(false, 100))
	assert_false(Handsfree.echo_blocked(false, 400))
	assert_false(Handsfree.should_forward("Где вы были", true))
	assert_true(Handsfree.should_forward("Где вы были", false))
	assert_true(Handsfree.should_reconnect(true, true, false))
	assert_false(Handsfree.should_reconnect(false, true, false))
	assert_false(Handsfree.should_reconnect(true, true, true))


func test_audio_chunks_are_short_and_the_ring_keeps_the_start() -> void:
	var rate := 16000
	var bytes := Handsfree.chunk_bytes(rate)
	assert_true(bytes >= rate * 20 / 1000 * 2)
	assert_true(bytes <= rate * 40 / 1000 * 2)
	var pcm := PackedByteArray()
	pcm.resize(bytes * 2 + 4)
	var pieces: Array = Handsfree.slice_pcm(pcm, rate)
	assert_eq(pieces.size(), 3)
	assert_eq((pieces[0] as PackedByteArray).size(), bytes)
	var ring := Handsfree.push_ring(PackedByteArray(), pcm, rate)
	assert_true(ring.size() <= int(float(rate) * 0.3) * 2)


