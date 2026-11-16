class_name VoiceAudio
extends RefCounted
## PCM 16-bit и WAV. Синтез Gemini отдаёт audio/L16, микрофон уходит как audio/wav.


static func wav_bytes(pcm: PackedByteArray, mix_rate: int, stereo: bool = false) -> PackedByteArray:
	var channels := 2 if stereo else 1
	var data_size := pcm.size()
	var out := PackedByteArray()
	out.resize(44 + data_size)
	_ascii(out, 0, "RIFF")
	_u32(out, 4, 36 + data_size)
	_ascii(out, 8, "WAVE")
	_ascii(out, 12, "fmt ")
	_u32(out, 16, 16)
	_u16(out, 20, 1)
	_u16(out, 22, channels)
	_u32(out, 24, mix_rate)
	_u32(out, 28, mix_rate * channels * 2)
	_u16(out, 32, channels * 2)
	_u16(out, 34, 16)
	_ascii(out, 36, "data")
	_u32(out, 40, data_size)
	for index in data_size:
		out[44 + index] = pcm[index]
	return out


static func mono(pcm: PackedByteArray, stereo: bool) -> PackedByteArray:
	if not stereo:
		return pcm
	var out := PackedByteArray()
	var frames := pcm.size() / 4
	out.resize(frames * 2)
	for frame in frames:
		out[frame * 2] = pcm[frame * 4]
		out[frame * 2 + 1] = pcm[frame * 4 + 1]
	return out


static func stream_from_pcm(pcm: PackedByteArray, mix_rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = maxi(mix_rate, 1)
	stream.stereo = false
	stream.data = pcm
	return stream


static func pcm_from_mime(mime: String, encoded: String) -> Dictionary:
	var cleaned := encoded.strip_edges().replace("\n", "").replace("\r", "")
	var raw := Marshalls.base64_to_raw(cleaned)
	if raw.is_empty():
		return {"ok": false}
	var lower := mime.to_lower()
	if lower.contains("wav") or (raw.size() > 12 and raw.slice(0, 4).get_string_from_ascii() == "RIFF"):
		return _pcm_from_wav(raw)
	var rate := 24000
	var marker := lower.find("rate=")
	if marker >= 0:
		rate = lower.substr(marker + 5).to_int()
	if rate <= 0:
		rate = 24000
	return {"ok": true, "pcm": raw, "mix_rate": rate}


static func _pcm_from_wav(raw: PackedByteArray) -> Dictionary:
	if raw.size() < 44 or raw.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {"ok": false}
	var rate := 24000
	var data_at := -1
	var cursor := 12
	while cursor + 8 <= raw.size():
		var chunk := raw.slice(cursor, cursor + 4).get_string_from_ascii()
		var size := raw.decode_u32(cursor + 4)
		if chunk == "fmt " and cursor + 16 <= raw.size():
			rate = raw.decode_u32(cursor + 12)
		elif chunk == "data":
			data_at = cursor + 8
			break
		cursor += 8 + size
	if data_at < 0 or data_at >= raw.size():
		return {"ok": false}
	if rate <= 0:
		rate = 24000
	return {"ok": true, "pcm": raw.slice(data_at), "mix_rate": rate}


static func _ascii(buffer: PackedByteArray, at: int, text: String) -> void:
	for index in text.length():
		buffer[at + index] = text.unicode_at(index)


static func _u16(buffer: PackedByteArray, at: int, value: int) -> void:
	buffer[at] = value & 255
	buffer[at + 1] = (value >> 8) & 255


static func _u32(buffer: PackedByteArray, at: int, value: int) -> void:
	buffer.encode_u32(at, value)
