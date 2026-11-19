class_name PhraseVad
extends RefCounted
## Конец фразы — пауза тишины. Шум калибруется по тихим кадрам, без записи звука в журнал.


const RATE := 16000
const FRAME_MS := 20
const FRAME_BYTES := 640
const MIN_SPEECH_MS := 400
const DEFAULT_PAUSE_MS := 700
const MIN_PAUSE_MS := 400
const MAX_PAUSE_MS := 2000

var pause_ms: int = DEFAULT_PAUSE_MS
var blocked: bool = false
var last_pcm: PackedByteArray = PackedByteArray()
var events: PackedStringArray = PackedStringArray()

var _carry: PackedByteArray = PackedByteArray()
var _phrase: PackedByteArray = PackedByteArray()
var _preroll: PackedByteArray = PackedByteArray()
var _in_speech: bool = false
var _speech_ms: int = 0
var _silence_ms: int = 0
var _noise: float = 80.0


func set_pause_ms(ms: int) -> void:
	pause_ms = clampi(ms, MIN_PAUSE_MS, MAX_PAUSE_MS)


func set_blocked(active: bool) -> void:
	if active == blocked:
		return
	blocked = active
	if active and _in_speech:
		_reset_utterance()
		_log("vad echo")
	elif active:
		_log("vad echo")
	else:
		_log("vad resume")


func reset_utterance() -> void:
	_reset_utterance()


func push(pcm: PackedByteArray) -> void:
	if blocked:
		if _in_speech:
			_reset_utterance()
			_log("vad echo")
		return
	if pcm.is_empty():
		return
	_carry.append_array(pcm)
	while _carry.size() >= FRAME_BYTES:
		var frame := _carry.slice(0, FRAME_BYTES)
		_carry = _carry.slice(FRAME_BYTES)
		_take_frame(frame)


func _take_frame(frame: PackedByteArray) -> void:
	var energy := _energy(frame)
	var gate := maxf(_noise * 2.5, _noise + 180.0)
	var voiced := energy >= gate
	if not _in_speech:
		if not voiced:
			_noise = _noise * 0.9 + energy * 0.1
			_remember_preroll(frame)
			return
		_in_speech = true
		_speech_ms = FRAME_MS
		_silence_ms = 0
		_phrase = PackedByteArray()
		_phrase.append_array(_preroll)
		_phrase.append_array(frame)
		_preroll = PackedByteArray()
		_log("vad start")
		return
	_phrase.append_array(frame)
	if voiced:
		_speech_ms += FRAME_MS
		_silence_ms = 0
		return
	_silence_ms += FRAME_MS
	if _silence_ms < pause_ms:
		return
	var speech := _speech_ms
	var captured := _phrase
	_reset_utterance()
	if speech < MIN_SPEECH_MS:
		_log("vad drop speech_ms=%d" % speech)
		return
	last_pcm = captured
	_log("vad end speech_ms=%d pause_ms=%d" % [speech, pause_ms])


func _remember_preroll(frame: PackedByteArray) -> void:
	_preroll.append_array(frame)
	var limit := int(RATE * 200 / 1000.0) * 2
	if _preroll.size() > limit:
		_preroll = _preroll.slice(_preroll.size() - limit)


func _reset_utterance() -> void:
	_in_speech = false
	_speech_ms = 0
	_silence_ms = 0
	_phrase = PackedByteArray()


func _energy(frame: PackedByteArray) -> float:
	var count := frame.size() / 2
	if count <= 0:
		return 0.0
	var sum := 0
	for index in count:
		var sample := int(frame[index * 2]) | (int(frame[index * 2 + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		sum += absi(sample)
	return float(sum) / float(count)


func _log(line: String) -> void:
	events.append(line)
	if is_instance_valid(Speaker):
		Speaker.note_line(line)
