extends TestCase


func test_speculation_keeps_only_a_stable_matching_phrase() -> void:
	assert_true(Speculation.same_input("Где вы были?", "где вы были"))
	assert_false(Speculation.same_input("Где вы были?", "Кто вы"))
	assert_false(Speculation.usable("00:01"))
	assert_false(Speculation.usable("коротко"))
	assert_true(Speculation.usable("Где вы были ночью"))
	assert_false(Speculation.should_launch("Где вы были ночью", false, false, 200))
	assert_false(Speculation.should_launch("Где вы были ночью", true, false, 900))
	assert_false(Speculation.should_launch("Где вы были ночью", false, true, 900))
	assert_true(Speculation.should_launch("Где вы были ночью", false, false, Speculation.DEBOUNCE_MS))


func test_voice_route_starts_on_live_then_uses_the_faster_median() -> void:
	assert_eq(VoiceRoute.choose_samples([], []), VoiceRoute.LIVE)
	assert_eq(VoiceRoute.choose_samples([400], []), VoiceRoute.READER)
	assert_eq(VoiceRoute.choose_samples([400], [900]), VoiceRoute.LIVE)
	assert_eq(VoiceRoute.choose_samples([400, 500], [900]), VoiceRoute.READER)
	assert_eq(VoiceRoute.choose_samples([800, 900], [200, 250]), VoiceRoute.READER)
	assert_eq(VoiceRoute.choose_samples([200, 220], [800, 900]), VoiceRoute.LIVE)
	assert_eq(VoiceRoute.median([10, 40, 20, 30, 100]), 35)
	assert_eq(GeminiSpeech.DEFAULT_TTS_MODEL, "gemini-3.8-flash-lite-tts")
	assert_eq(CloudVoiceProvider.PcmSpeaker.BUFFER_SEC, 0.1)
	var route := VoiceRoute.new()
	route.record(VoiceRoute.LIVE, 300)
	route.record(VoiceRoute.READER, 100)
	route.record(VoiceRoute.LIVE, 280)
	route.record(VoiceRoute.READER, 120)
	assert_eq(route.choose(), VoiceRoute.READER)
