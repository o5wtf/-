extends TestCase


func test_project_enables_audio_input() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	assert_true(text.contains("driver/enable_input=true"))
	assert_false(text.contains("Ввод с микрофона не включается"))


func test_failed_primary_uses_fallback_without_attenuating() -> void:
	var input := _input(_FailServer.new(), true)
	assert_true(input.warm())
	assert_eq(input.api_name, MicInput.API_BUS)
	assert_eq(input.last_error, "")
	assert_eq(input.primary_error, "input_inactive")
	assert_eq(input._player.volume_db, 0.0)
	var bus := AudioServer.get_bus_index(MicInput.BUS_NAME)
	assert_true(bus >= 0)
	assert_true(AudioServer.is_bus_mute(bus))
	assert_eq(MicInput.hint_for("input_inactive"), UiStrings.MIC_NOT_STARTED)
	assert_false(MicInput.hint_for("input_inactive") == UiStrings.MIC_NO_PERMISSION)
	assert_false(MicInput.hint_for("input_inactive") == UiStrings.MIC_FAILED)
	input.free()


func test_both_paths_down_keep_an_honest_error() -> void:
	var input := _input(_FailServer.new(), false)
	assert_false(input.warm())
	assert_eq(input.api_name, "")
	assert_eq(input.last_error, "input_inactive")
	assert_eq(MicInput.hint_for(input.last_error), UiStrings.MIC_NOT_STARTED)
	input.free()


func test_zero_frames_while_holding_switch_to_fallback() -> void:
	var input := _input(_OkServer.new(), true)
	assert_true(input.warm())
	assert_eq(input.api_name, MicInput.API_INPUT_FRAMES)
	input.begin_hold()
	input.observe_hold(PackedByteArray(), 250.0)
	assert_eq(input.api_name, MicInput.API_INPUT_FRAMES)
	input.observe_hold(PackedByteArray(), 200.0)
	assert_eq(input.api_name, MicInput.API_BUS)
	assert_eq(input.primary_error, "zero_frames")
	assert_eq(input._player.volume_db, 0.0)
	input.free()


func test_hint_maps_permission_failure_and_quiet_frames() -> void:
	assert_eq(MicInput.hint_for("denied"), UiStrings.MIC_NO_PERMISSION)
	assert_eq(MicInput.hint_for("quiet", 3200), UiStrings.MIC_TOO_QUIET)
	assert_eq(MicInput.hint_for("quiet", 0), UiStrings.MIC_NOT_STARTED)
	assert_eq(MicInput.hint_for("driver"), UiStrings.MIC_NOT_STARTED)


func test_permission_gates_start_and_restarts_after_grant() -> void:
	var host := Node.new()
	_attach(host)
	var access := MicAccess.new()
	var fake := _FakePermit.new()
	access.provider = fake
	host.add_child(access)
	host.add_child(fake)
	var input := _input(_FailServer.new(), false)
	host.add_child(input)
	assert_false(access.allowed())
	assert_false(MicAccess.start_if_allowed(access, input))
	assert_eq(input.api_name, "")
	assert_false(input.warm())
	assert_eq(input.primary_error, "input_inactive")
	fake.grant_on_request = true
	var ok: bool = await access.ensure()
	assert_true(ok)
	assert_eq(fake.requests, 1)
	assert_true(access.just_granted)
	input.server = _OkServer.new()
	input.fallback_enabled = true
	input.needs_restart = true
	assert_true(MicAccess.start_if_allowed(access, input))
	assert_eq(input.api_name, MicInput.API_INPUT_FRAMES)
	assert_false(access.just_granted)
	assert_false(input.needs_restart)
	host.free()


func test_permission_denial_does_not_start_capture() -> void:
	var host := Node.new()
	_attach(host)
	var access := MicAccess.new()
	var fake := _FakePermit.new()
	fake.grant_on_request = false
	access.provider = fake
	host.add_child(access)
	host.add_child(fake)
	var input := _input(_OkServer.new(), true)
	host.add_child(input)
	var ok: bool = await access.ensure()
	assert_false(ok)
	assert_false(MicAccess.start_if_allowed(access, input))
	assert_eq(input.api_name, "")
	host.free()


func test_status_lines_and_voice_log_cover_the_mic() -> void:
	var input := _input(_OkServer.new(), true)
	assert_true(input.warm())
	input.begin_hold()
	input.observe_hold(VoiceAudio.tone(160, 2000), 40.0)
	input.log_hold()
	var text := "\n".join(MicInput.status_lines())
	for key in ["enable_input=", "driver=", "devices=", "device=", "mix_rate=", "activate=", "api=", "error=", "record_audio=", "hold_frames=", "peak=", "hold_ms="]:
		assert_true(text.contains(key), key)
	var log_text := "\n".join(Speaker.voice_log)
	assert_true(log_text.contains("enable_input="))
	assert_true(log_text.contains("hold_frames="))
	assert_true(log_text.contains("record_audio="))
	input.free()


func test_saved_android_backend_becomes_gemini() -> void:
	var path := "user://config.cfg"
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var file := ConfigFile.new()
	file.parse(previous)
	file.set_value("llm", "settings_version", 7)
	file.set_value("llm", "dialogue_model", "gemini-3.5-flash-lite")
	file.set_value("mic", "stt", "system")
	file.save(path)
	var loaded := SettingsStore.load_current()
	assert_eq(loaded.stt_backend, "gemini")
	var check := ConfigFile.new()
	assert_eq(check.load(path), OK)
	assert_eq(str(check.get_value("mic", "stt", "")), "gemini")
	assert_eq(int(check.get_value("llm", "settings_version", 0)), LLMConfig.SETTINGS_VERSION)
	if previous == "":
		DirAccess.remove_absolute(path)
	else:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		restore.store_string(previous)
		restore.close()


func test_settings_version_and_mic_defaults_stay() -> void:
	assert_eq(LLMConfig.SETTINGS_VERSION, 9)
	var store := SettingsStore.new()
	assert_false(store.mic_enabled)
	assert_eq(store.mic_mode, "push_to_talk")
	assert_eq(store.stt_backend, "gemini")


func test_ci_builds_android_only() -> void:
	var yml := FileAccess.get_file_as_string("res://.github/workflows/build.yml")
	assert_true(yml.contains("name: Сборка Android\n"))
	assert_false(yml.contains("Windows Desktop"))
	assert_false(yml.contains("Detective-windows.zip"))
	assert_true(yml.contains("builds/Detective.apk"))
	assert_false(yml.contains("stage_system_speech"))
	assert_false(yml.contains("check_system_speech"))
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_true(preset.contains("Windows Desktop"))


func _input(server: Object, fallback: bool) -> MicInput:
	var input := MicInput.new()
	input.server = server
	input.fallback_enabled = fallback
	_attach(input)
	return input


func _attach(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


class _OkServer:
	extends RefCounted

	func activate() -> int:
		return OK


class _FailServer:
	extends RefCounted

	func activate() -> int:
		return FAILED


class _FakePermit:
	extends Node

	var granted: bool = false
	var requests: int = 0
	var grant_on_request: bool = true

	func is_granted() -> bool:
		return granted

	func request(access: MicAccess) -> void:
		requests += 1
		call_deferred("_emit", access)

	func _emit(access: MicAccess) -> void:
		granted = grant_on_request
		access.grant_finished.emit(granted)
