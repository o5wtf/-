class_name MicInput
extends Node
## Тёплый микрофон. В Godot 4.7 основной путь — AudioServer.get_input_frames.
## Если устройство не открылось, остаётся AudioStreamMicrophone и AudioEffectCapture.


const API_INPUT_FRAMES := "AudioServer.get_input_frames"
const API_BUS := "AudioStreamMicrophone+AudioEffectCapture"
const BUS_NAME := "MicCapture"

var api_name: String = ""
var last_error: String = ""
var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _bus := -1


static func preferred_api() -> String:
	return API_INPUT_FRAMES


func warm() -> bool:
	last_error = ""
	if _server_input():
		api_name = API_INPUT_FRAMES
		return true
	if _bus_input():
		api_name = API_BUS
		return true
	api_name = ""
	if last_error == "":
		last_error = "no_device"
	return false


func stop() -> void:
	if api_name == API_INPUT_FRAMES:
		AudioServer.set_input_device_active(false)
	if _player != null and is_instance_valid(_player):
		_player.stop()
	api_name = ""


func read_pcm() -> PackedByteArray:
	if api_name == API_INPUT_FRAMES:
		var available := AudioServer.get_input_frames_available()
		if available <= 0:
			return PackedByteArray()
		var frames: PackedVector2Array = AudioServer.get_input_frames(available)
		var pcm := VoiceAudio.from_vectors(frames)
		return VoiceAudio.to_pcm16k(pcm, AudioServer.get_input_mix_rate(), false)
	if _capture == null:
		return PackedByteArray()
	var chunk := _capture.get_buffer(_capture.get_frames_available())
	if chunk.is_empty():
		return PackedByteArray()
	var stereo := AudioServer.get_mix_rate()
	var pcm := PackedByteArray()
	pcm.resize(chunk.size() * 2)
	for index in chunk.size():
		VoiceAudio.put_sample(pcm, index, clampi(int(round(chunk[index].x * 32767.0)), -32768, 32767))
	return VoiceAudio.to_pcm16k(pcm, int(stereo), false)


func _server_input() -> bool:
	var err := AudioServer.set_input_device_active(true)
	if err != OK:
		last_error = "input_inactive"
		return false
	return true


func _bus_input() -> bool:
	if _player != null and is_instance_valid(_player) and _capture != null:
		if not _player.playing:
			_player.play()
		return true
	_bus = AudioServer.get_bus_index(BUS_NAME)
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS_NAME)
		AudioServer.set_bus_mute(_bus, true)
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_bus, _capture)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	_player.volume_db = -80.0
	add_child(_player)
	_player.play()
	return true
