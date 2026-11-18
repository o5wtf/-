class_name ChirpVoices
extends RefCounted
## Имена Chirp 3 HD и нарезка текста. Стиль и метки в этот синтез не уходят.


const MODEL_ID := "chirp-3-hd"
const BYTE_LIMIT := 4800
## Куски растут, чтобы следующий успел синтезироваться, пока играет текущий.
const CHUNK_CHAR_TARGETS: Array[int] = [150, 300, 600, 1200]
const PREFETCH_AHEAD := 2
const FEMALE_FALLBACK := "Kore"
const MALE_FALLBACK := "Charon"

## Имя как у Gemini, если оно есть в списке. Иначе запасной голос того же пола.
const VOICES: Array[Dictionary] = [
	{"name": "Achernar", "gender": "female"},
	{"name": "Achird", "gender": "male"},
	{"name": "Algenib", "gender": "male"},
	{"name": "Algieba", "gender": "male"},
	{"name": "Alnilam", "gender": "male"},
	{"name": "Aoede", "gender": "female"},
	{"name": "Autonoe", "gender": "female"},
	{"name": "Callirrhoe", "gender": "female"},
	{"name": "Charon", "gender": "male"},
	{"name": "Despina", "gender": "female"},
	{"name": "Enceladus", "gender": "male"},
	{"name": "Erinome", "gender": "female"},
	{"name": "Fenrir", "gender": "male"},
	{"name": "Gacrux", "gender": "female"},
	{"name": "Iapetus", "gender": "male"},
	{"name": "Kore", "gender": "female"},
	{"name": "Laomedeia", "gender": "female"},
	{"name": "Leda", "gender": "female"},
	{"name": "Orus", "gender": "male"},
	{"name": "Puck", "gender": "male"},
	{"name": "Pulcherrima", "gender": "female"},
	{"name": "Rasalgethi", "gender": "male"},
	{"name": "Sadachbia", "gender": "male"},
	{"name": "Sadaltager", "gender": "male"},
	{"name": "Schedar", "gender": "male"},
	{"name": "Sulafat", "gender": "female"},
	{"name": "Umbriel", "gender": "male"},
	{"name": "Vindemiatrix", "gender": "female"},
	{"name": "Zephyr", "gender": "female"},
	{"name": "Zubenelgenubi", "gender": "male"},
]


static func for_gemini(gemini_name: String, gender: String = "") -> String:
	var wanted := gemini_name.strip_edges()
	for item in VOICES:
		if str(item.get("name", "")) == wanted:
			return "ru-RU-Chirp3-HD-%s" % wanted
	var fallback := FEMALE_FALLBACK
	if gender.strip_edges() == "male":
		fallback = MALE_FALLBACK
	return "ru-RU-Chirp3-HD-%s" % fallback


static func speaking_rate(style: String) -> float:
	var low := style.to_lower()
	if low.contains("медленно") or low.contains("slow"):
		return 0.9
	if low.contains("быстро") or low.contains("fast"):
		return 1.1
	return 1.0


static func spoken_text(text: String) -> String:
	return VocalTags.visible(text)


static func chunks(text: String, limit: int = BYTE_LIMIT) -> PackedStringArray:
	var sentences := _sentences(text.strip_edges())
	if sentences.is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	var index := 0
	var step := 0
	while index < sentences.size():
		var target := 1000000
		if step < CHUNK_CHAR_TARGETS.size():
			target = CHUNK_CHAR_TARGETS[step]
		var current := ""
		var progressed := false
		while index < sentences.size():
			var sentence := str(sentences[index])
			if sentence.to_utf8_buffer().size() > limit:
				if current != "":
					break
				for part in _split_long(sentence, limit):
					out.append(part)
				index += 1
				progressed = true
				current = ""
				break
			var candidate := sentence if current == "" else "%s %s" % [current, sentence]
			var over_target := current != "" and candidate.length() > target
			var over_limit := candidate.to_utf8_buffer().size() > limit
			if over_target or over_limit:
				break
			current = candidate
			index += 1
			progressed = true
			if sentence.length() > target:
				break
		if current != "":
			out.append(current)
		elif not progressed:
			break
		step += 1
	return out


static func _sentences(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var start := 0
	var index := 0
	while index < text.length():
		var mark := text.substr(index, 1)
		if mark == "." or mark == "!" or mark == "?" or mark == "…" or mark == "\n":
			var sentence := text.substr(start, index + 1 - start).strip_edges()
			if sentence != "":
				out.append(sentence)
			start = index + 1
			while start < text.length() and (text.substr(start, 1) == " " or text.substr(start, 1) == "\n"):
				start += 1
			index = start
			continue
		index += 1
	if start < text.length():
		var tail := text.substr(start).strip_edges()
		if tail != "":
			out.append(tail)
	return out


static func _split_long(text: String, limit: int) -> PackedStringArray:
	var words := text.split(" ", false)
	if words.size() <= 1:
		return _split_bytes(text, limit)
	var out := PackedStringArray()
	var current := ""
	for word in words:
		var piece := str(word)
		if piece.to_utf8_buffer().size() > limit:
			if current != "":
				out.append(current)
				current = ""
			for part in _split_bytes(piece, limit):
				out.append(part)
			continue
		var candidate := piece if current == "" else "%s %s" % [current, piece]
		if candidate.to_utf8_buffer().size() > limit:
			out.append(current)
			current = piece
		else:
			current = candidate
	if current != "":
		out.append(current)
	return out


static func _split_bytes(text: String, limit: int) -> PackedStringArray:
	var out := PackedStringArray()
	var raw := text.to_utf8_buffer()
	var index := 0
	while index < raw.size():
		var end := mini(index + limit, raw.size())
		while end > index and end < raw.size() and (raw[end] & 0xC0) == 0x80:
			end -= 1
		if end <= index:
			end = mini(index + 1, raw.size())
		out.append(raw.slice(index, end).get_string_from_utf8())
		index = end
	return out
