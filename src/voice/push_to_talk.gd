class_name PushToTalk
extends Node
## Удержание кнопки: запись, расшифровка, один ход. Микрофон сюда не вшит.


signal state_changed(state_name: String)
signal hint_changed(text: String)
signal level_changed(unit: float)
signal retry_visible(show_button: bool)

const STATE_IDLE := "idle"
const STATE_LISTENING := "listening"
const STATE_RECOGNIZING := "recognizing"
const STATE_ANSWERING := "answering"

var stt: SttBackend
var clip: MicClip = MicClip.new()
var enabled: bool = false
var screen_active: bool = false
var character_busy: bool = false
var locked: bool = false
var state_name: String = STATE_IDLE
var last_wav: PackedByteArray = PackedByteArray()
var submit: Callable = Callable()
var _holding: bool = false
var _generation: int = 0


func press() -> bool:
	if not enabled or not screen_active or locked or character_busy or _holding:
		return false
	clip.begin()
	_holding = true
	_set_state(STATE_LISTENING)
	level_changed.emit(0.0)
	return true


func push_pcm(pcm: PackedByteArray, force_limit: bool = false) -> String:
	if not screen_active:
		if _holding:
			cancel()
		return "hidden"
	if not _holding:
		clip.push_preroll(pcm)
		return "preroll"
	var reached := clip.push_hold(pcm) or force_limit
	level_changed.emit(clip.level())
	if reached or clip.hold_ms() >= float(MicClip.MAX_MS):
		hint_changed.emit("Запись длинная, отправляю её.")
		return "limit"
	return "hold"


func release(force_send: bool = false) -> Dictionary:
	if not _holding and not force_send:
		return {"action": "idle"}
	_holding = false
	level_changed.emit(0.0)
	var decision := clip.end(force_send)
	if str(decision.get("action", "")) != "send":
		_set_state(STATE_IDLE)
		var reason := str(decision.get("reason", ""))
		hint_changed.emit("Тишина в записи." if reason == "quiet" else "Слишком коротко, не отправлено.")
		return decision
	last_wav = VoiceAudio.wav_bytes(decision.get("pcm", PackedByteArray()), VoiceAudio.UPLOAD_RATE)
	_save_last(last_wav)
	await _recognize(last_wav)
	decision["wav"] = last_wav
	return decision


func cancel() -> void:
	_generation += 1
	_holding = false
	clip.cancel()
	locked = false
	level_changed.emit(0.0)
	retry_visible.emit(false)
	_set_state(STATE_IDLE)


func retry() -> void:
	if last_wav.is_empty() or locked or not screen_active:
		return
	await _recognize(last_wav)


func _recognize(wav: PackedByteArray) -> void:
	var token := _generation
	locked = true
	_set_state(STATE_RECOGNIZING)
	var result: Dictionary = {"ok": false, "text": "", "error": "offline"}
	if stt != null:
		var pending: Variant = stt.transcribe(wav)
		if pending is Dictionary:
			result = pending
		else:
			result = await pending
	if token != _generation:
		locked = false
		return
	if not result.get("ok", false):
		locked = false
		hint_changed.emit("Не удалось распознать.")
		retry_visible.emit(true)
		_set_state(STATE_IDLE)
		return
	var text := str(result.get("text", "")).strip_edges()
	if SpeechJunk.is_junk(text):
		locked = false
		retry_visible.emit(false)
		hint_changed.emit("Не расслышал, повторите")
		_set_state(STATE_IDLE)
		return
	retry_visible.emit(false)
	_set_state(STATE_ANSWERING)
	if submit.is_valid():
		var sent: Variant = submit.call(text)
		if sent is not Dictionary and sent != null:
			await sent
	if token != _generation:
		locked = false
		return
	locked = false
	_set_state(STATE_IDLE)


func _set_state(next: String) -> void:
	state_name = next
	state_changed.emit(next)


func _save_last(wav: PackedByteArray) -> void:
	if wav.is_empty():
		return
	var file := FileAccess.open("user://mic-last.wav", FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(wav)
	file.close()
