class_name VoiceCache
extends RefCounted
## Кэш озвучки в user://. Ключа API в файлах нет: только частота и отсчёты PCM.

static var directory := "user://voice_cache"


static func key_for(voice_name: String, emotion: String, reply: String, style_mode: String, remark: String = "") -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var payload := "v6|%s|%s|%s|%s|%s" % [style_mode, voice_name, emotion, remark.strip_edges(), reply.strip_edges()]
	ctx.update(payload.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func path_for(cache_key: String) -> String:
	return "%s/%s.pcm" % [directory.trim_suffix("/"), cache_key]


static func store(cache_key: String, pcm: PackedByteArray, mix_rate: int) -> void:
	if cache_key == "" or pcm.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path_for(cache_key), FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(_header(mix_rate))
	file.store_buffer(pcm)
	file.close()


static func load(cache_key: String) -> Dictionary:
	var file := FileAccess.open(path_for(cache_key), FileAccess.READ)
	if file == null:
		return {"ok": false}
	var raw := file.get_buffer(file.get_length())
	file.close()
	if raw.size() < 8 or raw.slice(0, 4).get_string_from_ascii() != "PCM1":
		return {"ok": false}
	var rate := raw.decode_u32(4)
	return {"ok": true, "mix_rate": rate, "pcm": raw.slice(8)}


static func _header(mix_rate: int) -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(8)
	header[0] = 0x50
	header[1] = 0x43
	header[2] = 0x4d
	header[3] = 0x31
	header.encode_u32(4, maxi(mix_rate, 1))
	return header
