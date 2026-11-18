class_name VocalTags
extends RefCounted
## Короткие метки Gemini TTS. На экране и в истории их нет.
## В синтез Gemini уходят только метки из белого списка, не больше двух.


const MAX_TAGS := 2
const CANONICAL: Dictionary = {
	"sigh": "<sigh>",
	"laugh": "<laugh>",
	"gasp": "<gasp>",
	"short pause": "<short pause>",
}


static func limit(raw: String) -> String:
	return _scan(raw, true)


static func visible(raw: String) -> String:
	return _scan(raw, false)


## Накопитель для показа по кускам: незакрытая «<» в конце куска не рисуется.
static func push_visible(previous_raw: String, chunk: String) -> Dictionary:
	var raw := previous_raw + chunk
	return {"raw": raw, "shown": visible(raw)}


static func for_backend(text: String, gemini: bool, intonation: bool) -> String:
	var tagged := limit(text)
	if gemini and intonation:
		return tagged
	return visible(tagged)


static func _scan(raw: String, keep_allowed: bool) -> String:
	var out := ""
	var index := 0
	var kept := 0
	var length := raw.length()
	while index < length:
		var mark := raw.find("<", index)
		if mark < 0:
			out += raw.substr(index)
			break
		out += raw.substr(index, mark - index)
		var end := raw.find(">", mark + 1)
		if end < 0:
			break
		if keep_allowed and kept < MAX_TAGS:
			var inner := raw.substr(mark + 1, end - mark - 1).strip_edges().to_lower()
			var tag := str(CANONICAL.get(inner, ""))
			if tag != "":
				if not out.ends_with(" ") and out != "":
					out += " "
				out += tag
				kept += 1
		index = end + 1
	return _collapse(out)


static func _collapse(text: String) -> String:
	var space := RegEx.new()
	space.compile("[ \\t\\f\\v]+")
	var collapsed := space.sub(text, " ", true)
	var punctuation := RegEx.new()
	punctuation.compile("\\s+([.,!?;:])")
	return punctuation.sub(collapsed, "$1", true).strip_edges()
