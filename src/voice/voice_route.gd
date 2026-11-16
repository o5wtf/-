class_name VoiceRoute
extends RefCounted
## Какой движок озвучки быстрее в этой сессии. Пока замеров нет, остаётся Live.

const LIVE := "live"
const READER := "reader"
const WINDOW := 4

var _live: Array[int] = []
var _reader: Array[int] = []


func choose() -> String:
	return choose_samples(_live, _reader)


func record(engine: String, elapsed_ms: int) -> void:
	if elapsed_ms < 0:
		return
	var bucket: Array[int] = _live if engine == LIVE else _reader
	bucket.append(elapsed_ms)
	while bucket.size() > WINDOW:
		bucket.remove_at(0)


static func choose_samples(live: Array, reader: Array) -> String:
	if reader.is_empty():
		return LIVE if live.is_empty() else READER
	if live.is_empty():
		return LIVE
	if live.size() < 2 or reader.size() < 2:
		return LIVE if live.size() <= reader.size() else READER
	return LIVE if median(live) <= median(reader) else READER


static func median(values: Array) -> int:
	if values.is_empty():
		return 0
	var copy: Array = values.slice(maxi(0, values.size() - WINDOW), values.size())
	copy.sort()
	var mid := int(copy.size() / 2)
	if copy.size() % 2 == 1:
		return int(copy[mid])
	return int((int(copy[mid - 1]) + int(copy[mid])) / 2.0)
