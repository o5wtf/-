class_name TtsCache
extends RefCounted
## Готовый PCM на устройстве. Ключ — хеш модели, голоса, тона и текста.
## Ключ API и сам текст в каталог не пишутся.


const MAX_BYTES_DEFAULT := 50 * 1024 * 1024

static var root_path: String = "user://tts-cache"
static var max_bytes: int = MAX_BYTES_DEFAULT
static var _use_counter: int = 0


static func key_for(model: String, voice: String, tone: String, text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var payload := "%s\n%s\n%s\n%s" % [model, voice, tone, text]
	ctx.update(payload.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func read(key: String) -> PackedByteArray:
	if not _safe_key(key):
		return PackedByteArray()
	var listed := _listed_size(key)
	var path := _pcm_path(key)
	if listed < 0 or not FileAccess.file_exists(path):
		_drop(key)
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty() or bytes.size() != listed:
		_drop(key)
		return PackedByteArray()
	_remember(key, bytes.size())
	return bytes


static func write(key: String, bytes: PackedByteArray) -> void:
	if not _safe_key(key) or bytes.is_empty() or bytes.size() > max_bytes:
		return
	_ensure_dir()
	_evict_for(bytes.size(), key)
	var file := FileAccess.open(_pcm_path(key), FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()
	_remember(key, bytes.size())


static func erase_all() -> void:
	var absolute := ProjectSettings.globalize_path(root_path)
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	var names: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	for entry in names:
		dir.remove(entry)


static func _evict_for(incoming: int, key: String) -> void:
	var index := _index()
	var rows: Array = []
	var total := 0
	if not index.has_section("items"):
		return
	for item in index.get_section_keys("items"):
		var size := _size_of(str(index.get_value("items", item, "")))
		if str(item) == key:
			_remove_file(str(item))
			continue
		if size <= 0:
			continue
		total += size
		rows.append({"key": str(item), "size": size, "used": _used_of(str(index.get_value("items", item, "")))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["used"]) < int(b["used"]))
	var keep: Array = []
	for row in rows:
		if total + incoming > max_bytes:
			total -= int(row["size"])
			_remove_file(str(row["key"]))
			continue
		keep.append(row)
	var fresh := ConfigFile.new()
	for row in keep:
		fresh.set_value("items", str(row["key"]), "%d|%d" % [int(row["size"]), int(row["used"])])
	fresh.save(_index_path())


static func _remember(key: String, size: int) -> void:
	var index := _index()
	_use_counter += 1
	index.set_value("items", key, "%d|%d" % [size, _use_counter])
	index.save(_index_path())


static func _listed_size(key: String) -> int:
	var index := _index()
	if not index.has_section_key("items", key):
		return -1
	return _size_of(str(index.get_value("items", key, "")))


static func _drop(key: String) -> void:
	_remove_file(key)
	var index := _index()
	if index.has_section_key("items", key):
		index.erase_section_key("items", key)
		index.save(_index_path())


static func _remove_file(key: String) -> void:
	var path := _pcm_path(key)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _index() -> ConfigFile:
	var index := ConfigFile.new()
	index.load(_index_path())
	return index


static func _index_path() -> String:
	return "%s/index.cfg" % root_path.trim_suffix("/")


static func _pcm_path(key: String) -> String:
	return "%s/%s.pcm" % [root_path.trim_suffix("/"), key]


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))


static func _size_of(raw: String) -> int:
	var parts := raw.split("|", false, 1)
	if parts.is_empty():
		return 0
	return int(parts[0])


static func _used_of(raw: String) -> int:
	var parts := raw.split("|", false, 1)
	if parts.size() < 2:
		return 0
	return int(parts[1])


static func _safe_key(key: String) -> bool:
	if key.length() < 32 or key.length() > 128:
		return false
	var pattern := RegEx.new()
	if pattern.compile("^[0-9a-f]+$") != OK:
		return false
	return pattern.search(key) != null
