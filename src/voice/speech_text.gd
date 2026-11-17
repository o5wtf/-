class_name SpeechText
extends RefCounted
## Текст, который можно отдать в озвучку. Ремарка, тон, разметка и служебные слова убираются.
## Сам текст реплики в журнал не пишется.


const SERVICE_PHRASES: PackedStringArray = [
	"языковая модель",
	"нейросеть",
	"промпт",
]


static func clean(raw: String) -> String:
	var text := raw.replace("\r\n", "\n").replace("\r", "\n")
	text = _strip_spans(text, "*", "*")
	text = _strip_spans(text, "(", ")")
	text = _strip_spans(text, "（", "）")
	text = _strip_spans(text, "[", "]")
	text = text.replace("**", "").replace("`", "").replace("__", "")
	text = _strip_line_noise(text)
	text = _strip_prefixes(text)
	text = _strip_service_words(text)
	text = text.replace("*", "").replace("#", "").replace("_", "")
	var lines: PackedStringArray = PackedStringArray()
	for line in text.split("\n"):
		var cleaned := _collapse(line)
		if cleaned != "":
			lines.append(cleaned)
	return _collapse(" ".join(lines))


static func _strip_spans(text: String, opener: String, closer: String) -> String:
	var result := ""
	var index := 0
	while index < text.length():
		var start := text.find(opener, index)
		if start < 0:
			result += text.substr(index)
			break
		result += text.substr(index, start - index)
		var end := text.find(closer, start + opener.length())
		if end < 0:
			break
		index = end + closer.length()
	return result


static func _strip_line_noise(text: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var bullet := RegEx.new()
	bullet.compile("^\\s*(?:[-•*]|\\d+[.)])\\s+")
	var label := RegEx.new()
	label.compile("(?i)^\\s*(?:ремарка|тон|эмоция|emotion|player_tone|remark)\\s*[:=].*$")
	for line in text.split("\n"):
		if label.search(line) != null:
			continue
		var match := bullet.search(line)
		if match != null:
			line = line.substr(match.get_end())
		lines.append(line)
	return "\n".join(lines)


static func _strip_prefixes(text: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("(?i)\\b(?:player_tone|emotion|remark|ремарка|тон|эмоция)\\s*[:=]\\s*[-+]?\\w+\\b")
	return pattern.sub(text, " ", true)


static func _strip_service_words(text: String) -> String:
	var result := text
	for phrase in SERVICE_PHRASES:
		var pattern := RegEx.new()
		pattern.compile("(?i)%s" % phrase)
		result = pattern.sub(result, " ", true)
	var kept: PackedStringArray = PackedStringArray()
	for part in result.split(" ", false):
		var word := part.trim_suffix(".").trim_suffix(",").trim_suffix("!").trim_suffix("?").trim_suffix(":").trim_suffix(";")
		if word.to_lower() == "ии":
			continue
		kept.append(part)
	return " ".join(kept)


static func _collapse(text: String) -> String:
	var space := RegEx.new()
	space.compile("[ \\t\\f\\v]+")
	var collapsed := space.sub(text, " ", true)
	var punctuation := RegEx.new()
	punctuation.compile("\\s+([.,!?;:])")
	return punctuation.sub(collapsed, "$1", true).strip_edges()
