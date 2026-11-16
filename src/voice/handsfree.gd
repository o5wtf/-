class_name Handsfree
extends RefCounted
## Постоянное прослушивание: пауза, куски звука и отсев пустых фраз.

const DEFAULT_PAUSE_MS := 700
const MIN_PAUSE_MS := 400
const MAX_PAUSE_MS := 1500
const CHUNK_MS := 30
const RING_MS := 300
const ECHO_TAIL_MS := 250
const MIN_CHARS := 2


static func clamp_pause(ms: int) -> int:
	return clampi(ms, MIN_PAUSE_MS, MAX_PAUSE_MS)


static func accept_phrase(text: String) -> bool:
	var clean := text.strip_edges()
	if clean.length() < MIN_CHARS or _clock(clean):
		return false
	return _normalize(clean).length() >= MIN_CHARS


static func commit(text: String, previous: String, elapsed_ms: int) -> Dictionary:
	if not accept_phrase(text):
		return {"send": false, "previous": previous}
	if text.strip_edges() == previous.strip_edges() and elapsed_ms < 1000:
		return {"send": false, "previous": previous}
	return {"send": true, "previous": text.strip_edges()}


static func echo_blocked(output_active: bool, since_output_ms: int) -> bool:
	if output_active:
		return true
	return since_output_ms >= 0 and since_output_ms < ECHO_TAIL_MS


static func should_forward(text: String, blocked: bool) -> bool:
	return accept_phrase(text) and not blocked


static func should_reconnect(listening: bool, closed: bool, auth_failed: bool) -> bool:
	return listening and closed and not auth_failed


static func route(is_final: bool) -> String:
	return "submit" if is_final else "partial"


static func chunk_bytes(rate: int) -> int:
	var safe := rate if rate > 0 else 16000
	return maxi(2, int(float(safe) * float(CHUNK_MS) / 1000.0) * 2)


static func slice_pcm(pcm: PackedByteArray, rate: int) -> Array:
	var pieces: Array = []
	var size := chunk_bytes(rate)
	var offset := 0
	while offset < pcm.size():
		var count := mini(size, pcm.size() - offset)
		if count >= 2:
			pieces.append(pcm.slice(offset, offset + count))
		offset += count
	return pieces


static func push_ring(buf: PackedByteArray, pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var merged := buf.duplicate()
	merged.append_array(pcm)
	var limit := maxi(2, int(float(rate if rate > 0 else 16000) * float(RING_MS) / 1000.0) * 2)
	if merged.size() <= limit:
		return merged
	return merged.slice(merged.size() - limit)


static func _clock(text: String) -> bool:
	var folded := text.strip_edges()
	if folded == "" or not folded.contains(":"):
		return false
	for index in folded.length():
		var ch := folded.substr(index, 1)
		var ok := (ch >= "0" and ch <= "9") or ch == ":" or ch == "." or ch == "," or ch == " " or ch == "-" or ch == ">" or ch == "[" or ch == "]" or ch == "(" or ch == ")"
		if not ok:
			return false
	return true


static func _normalize(text: String) -> String:
	var folded := text.to_lower().replace("ё", "е")
	var kept := ""
	for index in folded.length():
		var ch := folded.substr(index, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or (ch >= "а" and ch <= "я"):
			kept += ch
	return kept
