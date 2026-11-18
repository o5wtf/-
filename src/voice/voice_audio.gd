class_name VoiceAudio
extends RefCounted
## PCM 16-bit и WAV. Распознавание получает моно 16 кГц.


const UPLOAD_RATE := 16000


static func wav_bytes(pcm: PackedByteArray, mix_rate: int) -> PackedByteArray:
	var data_size := pcm.size()
	var out := PackedByteArray()
	out.resize(44 + data_size)
	_ascii(out, 0, "RIFF")
	_u32(out, 4, 36 + data_size)
	_ascii(out, 8, "WAVE")
	_ascii(out, 12, "fmt ")
	_u32(out, 16, 16)
	_u16(out, 20, 1)
	_u16(out, 22, 1)
	_u32(out, 24, mix_rate)
	_u32(out, 28, mix_rate * 2)
	_u16(out, 32, 2)
	_u16(out, 34, 16)
	_ascii(out, 36, "data")
	_u32(out, 40, data_size)
	for index in data_size:
		out[44 + index] = pcm[index]
	return out


static func to_pcm16k(pcm: PackedByteArray, mix_rate: int, stereo: bool) -> PackedByteArray:
	var single := mono(pcm, stereo)
	var rate := mix_rate if mix_rate > 0 else UPLOAD_RATE
	if rate == UPLOAD_RATE:
		return single
	return resample(single, rate, UPLOAD_RATE)


static func resample(pcm: PackedByteArray, from_rate: int, to_rate: int) -> PackedByteArray:
	var frames := pcm.size() / 2
	if frames == 0 or from_rate <= 0 or to_rate <= 0:
		return PackedByteArray()
	if from_rate == to_rate:
		return pcm
	var out_frames := maxi(1, int(round(float(frames) * float(to_rate) / float(from_rate))))
	var out := PackedByteArray()
	out.resize(out_frames * 2)
	for index in out_frames:
		var source := float(index) * float(from_rate) / float(to_rate)
		var left := mini(int(floor(source)), frames - 1)
		var right := mini(left + 1, frames - 1)
		var frac := source - float(left)
		var mixed := int(round(float(sample_at(pcm, left)) + (float(sample_at(pcm, right)) - float(sample_at(pcm, left))) * frac))
		put_sample(out, index, clampi(mixed, -32768, 32767))
	return out


static func mono(pcm: PackedByteArray, stereo: bool) -> PackedByteArray:
	if not stereo:
		return pcm
	var frames := pcm.size() / 4
	var out := PackedByteArray()
	out.resize(frames * 2)
	for frame in frames:
		out[frame * 2] = pcm[frame * 4]
		out[frame * 2 + 1] = pcm[frame * 4 + 1]
	return out


static func from_vectors(frames: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(frames.size() * 2)
	for index in frames.size():
		var frame := frames[index]
		var mixed := (frame.x + frame.y) * 0.5
		put_sample(out, index, clampi(int(round(mixed * 32767.0)), -32768, 32767))
	return out


static func peak(pcm: PackedByteArray) -> int:
	var best := 0
	var frames := pcm.size() / 2
	for index in frames:
		best = maxi(best, absi(sample_at(pcm, index)))
	return best


static func tone(frames: int, amplitude: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(frames * 2)
	for index in frames:
		put_sample(out, index, amplitude)
	return out


static func sample_at(pcm: PackedByteArray, index: int) -> int:
	var at := index * 2
	if at + 1 >= pcm.size():
		return 0
	var value := int(pcm[at]) | (int(pcm[at + 1]) << 8)
	if value >= 32768:
		value -= 65536
	return value


static func put_sample(pcm: PackedByteArray, index: int, value: int) -> void:
	var stored := value
	if stored < 0:
		stored += 65536
	var at := index * 2
	pcm[at] = stored & 255
	pcm[at + 1] = (stored >> 8) & 255


static func _ascii(buffer: PackedByteArray, at: int, text: String) -> void:
	for index in text.length():
		buffer[at + index] = text.unicode_at(index)


static func _u16(buffer: PackedByteArray, at: int, value: int) -> void:
	buffer[at] = value & 255
	buffer[at + 1] = (value >> 8) & 255


static func _u32(buffer: PackedByteArray, at: int, value: int) -> void:
	buffer.encode_u32(at, value)
