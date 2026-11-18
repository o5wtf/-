class_name TtsQuota
extends RefCounted
## Суточная квота озвучки по модели. Цепочка — список: сюда можно добавить третий голос.


const MODELS: Array[Dictionary] = [
	{"id": "gemini-3.8-flash-lite-tts", "label": "3.8 Flash Lite TTS"},
	{"id": "gemini-3.8-flash-tts", "label": "3.8 Flash TTS"},
]
const PROBE_INTERVAL_S := 3600

static var store_path: String = "user://config.cfg"
static var now_override: int = -1
static var fallback_override = null
static var selected_override = null


static func chain() -> PackedStringArray:
	var ids := PackedStringArray()
	for item in MODELS:
		ids.append(str(item.get("id", "")))
	return ids


static func label_for(model: String) -> String:
	for item in MODELS:
		if str(item.get("id", "")) == model:
			return str(item.get("label", model))
	return model


static func selected() -> String:
	if selected_override != null:
		var forced := str(selected_override)
		if chain().has(forced):
			return forced
	var want := SettingsStore.load_current().tts_model
	if chain().has(want):
		return want
	return chain()[0]


static func primary() -> String:
	return selected()


static func now_unix() -> int:
	if now_override >= 0:
		return now_override
	return int(Time.get_unix_time_from_system())


static func fallback_enabled() -> bool:
	if fallback_override != null:
		return bool(fallback_override)
	return SettingsStore.load_current().tts_auto


static func reset() -> void:
	var file := ConfigFile.new()
	if file.load(store_path) == OK and file.has_section("tts_quota"):
		file.erase_section("tts_quota")
		file.save(store_path)


static func exhausted_until(model: String) -> int:
	var file := ConfigFile.new()
	if file.load(store_path) != OK:
		return 0
	return int(file.get_value("tts_quota", _until_key(model), 0))


static func is_exhausted(model: String, now_unix: int) -> bool:
	return exhausted_until(model) > now_unix


static func mark_exhausted(model: String, now_unix: int) -> void:
	var file := _file()
	file.set_value("tts_quota", _until_key(model), PacificTime.next_midnight_utc(now_unix))
	file.save(store_path)


static func clear(model: String) -> void:
	var file := _file()
	if file.has_section_key("tts_quota", _until_key(model)):
		file.erase_section_key("tts_quota", _until_key(model))
		file.save(store_path)


static func mark_probe(now_unix: int) -> void:
	var file := _file()
	file.set_value("tts_quota", "probe_%s" % selected(), now_unix)
	file.save(store_path)


static func probe_due(now_unix: int) -> bool:
	var file := ConfigFile.new()
	if file.load(store_path) != OK:
		return true
	var last := int(file.get_value("tts_quota", "probe_%s" % selected(), 0))
	return now_unix - last >= PROBE_INTERVAL_S


static func choose(now_unix: int) -> Dictionary:
	var home := selected()
	if not fallback_enabled() or not is_exhausted(home, now_unix):
		return {"model": home, "reason": "primary", "probe": false}
	if probe_due(now_unix):
		return {"model": home, "reason": "hourly_probe", "probe": true}
	var nxt := next_open(home, now_unix)
	if nxt == "":
		return {"model": home, "reason": "quota_daily", "probe": false, "skip": true}
	return {"model": nxt, "reason": "quota_daily", "probe": false}


static func next_open(model: String, now_unix: int) -> String:
	var passed := false
	for item in chain():
		if not passed:
			if item == model:
				passed = true
			continue
		if not is_exhausted(item, now_unix):
			return item
	return ""


static func status_line(now_unix: int) -> String:
	var choice := choose(now_unix)
	var model := str(choice.get("model", selected()))
	var until := exhausted_until(selected())
	if until > now_unix:
		return "Сейчас голос: %s. Выбранный недоступен до %s." % [label_for(model), PacificTime.format_local(until)]
	return "Сейчас голос: %s." % label_for(model)


static func _until_key(model: String) -> String:
	return "until_%s" % model.replace(".", "_")


static func _file() -> ConfigFile:
	var file := ConfigFile.new()
	file.load(store_path)
	return file
