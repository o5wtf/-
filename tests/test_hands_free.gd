extends TestCase


func test_pause_ends_a_phrase_and_short_noise_is_dropped() -> void:
	var vad := PhraseVad.new()
	vad.set_pause_ms(700)
	vad.push(_tone(500, 4000))
	vad.push(_tone(680, 0))
	assert_false(_has(vad, "vad end"))
	vad.push(_tone(40, 0))
	assert_true(_has(vad, "vad end speech_ms=500 pause_ms=700"))
	assert_false(_has(vad, "vad drop"))
	var dropped := PhraseVad.new()
	dropped.set_pause_ms(700)
	dropped.push(_tone(200, 4000))
	dropped.push(_tone(700, 0))
	assert_true(_has(dropped, "vad drop speech_ms=200"))
	assert_false(_has(dropped, "vad end"))
	assert_eq(dropped.last_pcm.size(), 0)


func test_echo_guard_does_not_capture_during_playback() -> void:
	var vad := PhraseVad.new()
	vad.set_pause_ms(700)
	vad.set_blocked(true)
	vad.push(_tone(800, 5000))
	vad.push(_tone(800, 0))
	assert_false(_has(vad, "vad end"))
	assert_true(_has(vad, "vad echo"))
	vad.set_blocked(false)
	vad.push(_tone(500, 4000))
	vad.push(_tone(700, 0))
	assert_true(_has(vad, "vad end speech_ms=500"))
	assert_true(vad.last_pcm.size() <= PhraseVad.RATE * 2 * 13 / 10)


func test_pause_toggle_stops_and_resumes_listening() -> void:
	var listen := HandsFreeListen.new()
	listen.enabled = true
	listen.screen_active = true
	listen.set_pause_ms(700)
	(Engine.get_main_loop() as SceneTree).root.add_child(listen)
	listen.push_pcm(_tone(200, 4000))
	listen.toggle_pause()
	assert_eq(listen.state_name, HandsFreeListen.STATE_PAUSED)
	assert_eq(listen.label(), "Пауза")
	listen.push_pcm(_tone(800, 4000))
	listen.push_pcm(_tone(800, 0))
	assert_false(_has(listen.vad, "vad end"))
	listen.toggle_pause()
	assert_eq(listen.label(), "Слушаю")
	listen.push_pcm(_tone(500, 4000))
	listen.push_pcm(_tone(700, 0))
	assert_true(_has(listen.vad, "vad end speech_ms=500"))
	listen.free()


func test_hands_free_pause_is_saved() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	SettingsStore.save_values("mock", "", "gemini-3.5-flash-lite", 1.0, null, null, null, null, true, "hands_free", null, null, null, null, null, 900)
	var loaded := SettingsStore.load_current()
	assert_eq(loaded.mic_mode, "hands_free")
	assert_eq(loaded.mic_pause_ms, 900)
	assert_true(loaded.mic_enabled)
	var screen := (load("res://ui/screens/settings.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var mode := screen.find_child("MicMode", true, false) as OptionButton
	var slider := screen.find_child("PauseSlider", true, false) as HSlider
	assert_false(mode.is_item_disabled(1))
	assert_eq(mode.selected, 1)
	assert_eq(int(slider.value), 900)
	screen.free()
	if previous == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()


func _tone(ms: int, amp: int) -> PackedByteArray:
	var samples := int(PhraseVad.RATE * ms / 1000.0)
	var out := PackedByteArray()
	out.resize(samples * 2)
	for index in samples:
		var value := amp
		if value < 0:
			value += 65536
		out[index * 2] = value & 255
		out[index * 2 + 1] = (value >> 8) & 255
	return out


func _has(vad: PhraseVad, fragment: String) -> bool:
	for line in vad.events:
		if str(line).contains(fragment):
			return true
	return false
