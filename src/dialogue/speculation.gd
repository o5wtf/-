class_name Speculation
extends RefCounted
## Одна догадка ответа, пока игрок ещё держит микрофон.
## Сравнение только по нормализованному тексту вопроса.

const DEBOUNCE_MS := 700
const MIN_CHARS := 12


static func normalize(text: String) -> String:
	var folded := text.to_lower().replace("ё", "е")
	var kept := ""
	for index in folded.length():
		var ch := folded.substr(index, 1)
		if ch == " " or ch == "\n" or ch == "\t":
			kept += " "
		elif _letter(ch):
			kept += ch
	return " ".join(kept.split(" ", false))


static func same_input(left: String, right: String) -> bool:
	var a := normalize(left)
	var b := normalize(right)
	return a != "" and a == b


static func usable(text: String) -> bool:
	var clean := text.strip_edges()
	if clean.length() < MIN_CHARS or GeminiLive.is_clock_label(clean):
		return false
	return normalize(clean) != ""


static func should_launch(text: String, already_started: bool, pending: bool, stable_ms: int) -> bool:
	if already_started or pending or stable_ms < DEBOUNCE_MS:
		return false
	return usable(text)


static func _letter(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or (ch >= "а" and ch <= "я")
