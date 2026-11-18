class_name SpeechJunk
extends RefCounted
## Пустое, только знаки или явный не-речевой ответ не отправляются персонажу.


const MARKERS: PackedStringArray = [
	"[music]",
	"[silence]",
	"[noise]",
	"unintelligible",
	"неразборчиво",
	"(тишина)",
	"no speech",
]


static func is_junk(raw: String) -> bool:
	var text := raw.strip_edges().to_lower()
	if text == "":
		return true
	for marker in MARKERS:
		if text == marker:
			return true
	for index in text.length():
		var code := text.unicode_at(index)
		if _is_word(code):
			return false
	return true


static func _is_word(code: int) -> bool:
	if code >= 48 and code <= 57:
		return true
	if code >= 65 and code <= 90:
		return true
	if code >= 97 and code <= 122:
		return true
	if code >= 0x0400 and code <= 0x04FF:
		return true
	return false
