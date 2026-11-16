class_name VoiceProfiles
extends RefCounted
## Голос персонажа по полу и возрасту из дела. Если полей нет, пол берётся по окончанию имени.
## В промпт синтеза попадает только реплика; эмоция и ремарка задают подачу и не произносятся отдельно.


class Profile:
	extends RefCounted
	var person_id: String = ""
	var voice_name: String = "Kore"
	var gender: String = "female"
	var age_band: String = "adult"
	var pitch: float = 1.0


const FEMALE_VOICES := {
	"young": ["Leda", "Zephyr"],
	"adult": ["Kore", "Aoede"],
	"older": ["Callirrhoe", "Gacrux"],
}
const MALE_VOICES := {
	"young": ["Puck", "Fenrir"],
	"adult": ["Charon", "Orus"],
	"older": ["Enceladus", "Schedar"],
}


static func for_agent(agent: CaseData.Agent) -> Profile:
	if agent == null:
		return for_person("", "", "", 0)
	return for_person(agent.id, agent.name, agent.gender, agent.age)


static func for_person(person_id: String, person_name: String, gender: String, age: int) -> Profile:
	var profile := Profile.new()
	profile.person_id = person_id
	profile.gender = _gender(person_name, gender)
	profile.age_band = _age_band(age)
	var pool: Array = (FEMALE_VOICES if profile.gender == "female" else MALE_VOICES)[profile.age_band]
	profile.voice_name = str(pool[_stable_index(person_id if person_id != "" else person_name, pool.size())])
	profile.pitch = _pitch(profile.gender, profile.age_band)
	return profile


const MOOD_WORDS: PackedStringArray = [
	"спокойно", "ровно", "нервно", "сбивчиво", "тихо", "испуганно", "печально",
	"резко", "гневно", "холодно", "сдержанно", "медленно", "презрительно",
]
const STYLE_PLAIN := "plain"
const STYLE_ENGLISH_PREFIX := "english_prefix"
const STYLE_ENGLISH_TAGS := "english_tags"
## По умолчанию только реплика: текстовая подача на планшете зачитывалась вслух.
## Английские режимы остаются для переключателя «Интонация».
const DEFAULT_STYLE_MODE := STYLE_PLAIN


static func spoken_text(reply: String) -> String:
	var line := reply.strip_edges()
	for _step in 6:
		var next := _strip_leading_direction(line)
		if next == line:
			break
		line = next.strip_edges()
	return line


static func normalize_style(mode: String) -> String:
	var name := mode.strip_edges()
	if name == STYLE_PLAIN or name == STYLE_ENGLISH_PREFIX or name == STYLE_ENGLISH_TAGS:
		return name
	return DEFAULT_STYLE_MODE


static func style_prompt(reply: String, emotion: String, _remark: String, mode: String = DEFAULT_STYLE_MODE) -> String:
	var line := spoken_text(reply)
	if line == "":
		return ""
	var chosen := normalize_style(mode)
	if chosen == STYLE_PLAIN:
		return line
	var tone := _english_tone(emotion)
	if chosen == STYLE_ENGLISH_TAGS:
		return "%s\n%s" % [_english_tags(tone), line]
	return "Read the following Russian line in a %s tone. Speak only the Russian line:\n%s" % [tone, line]


static func live_instruction(emotion: String, remark: String) -> String:
	var text := "Respond in Russian. Output only the words between <<< and >>>. Never answer the line, never add words. Ты озвучиваешь персонажа. Произнеси реплику пользователя дословно, ничего не добавляя и не комментируя. Тон: %s." % live_tone(emotion)
	var stage := remark.strip_edges().replace("\n", " ")
	if stage.length() > 80:
		stage = stage.substr(0, 80).strip_edges()
	if stage != "":
		text += " Ремарка: %s." % stage
	return text


static func live_tone(emotion: String) -> String:
	match emotion:
		"nervous":
			return "нервно, сбивчиво (nervous, hesitant)"
		"scared":
			return "тихо, испуганно (scared, quiet)"
		"sad":
			return "печально (sad)"
		"angry":
			return "резко, гневно (angry, sharp)"
		"controlled":
			return "холодно, сдержанно (cold, restrained)"
		"contemptuous":
			return "медленно, презрительно (slow, contemptuous)"
		_:
			return "спокойно (calm)"


static func marked_line(line: String) -> String:
	return "<<<%s>>>" % spoken_text(line)


static func vocabulary_from_case(case_data: CaseData) -> PackedStringArray:
	var found := PackedStringArray()
	if case_data == null:
		return found
	for agent in case_data.agents:
		_push_term(found, agent.name)
	for item in case_data.evidence:
		_push_term(found, item.title)
	return found


static func _push_term(found: PackedStringArray, text: String) -> void:
	var clean := text.strip_edges()
	if clean == "" or clean.length() > 40 or found.size() >= 100 or found.has(clean):
		return
	found.append(clean)


static func _english_tone(emotion: String) -> String:
	match emotion:
		"nervous":
			return "nervous, hesitant"
		"scared":
			return "scared, quiet"
		"sad":
			return "sad"
		"angry":
			return "angry, sharp"
		"controlled":
			return "cold, restrained"
		"contemptuous":
			return "slow, contemptuous"
		_:
			return "calm"


static func _english_tags(tone: String) -> String:
	var tags: PackedStringArray = PackedStringArray()
	for word in tone.split(","):
		var clean := str(word).strip_edges()
		if clean != "":
			tags.append("[%s]" % clean)
	return " ".join(tags)


static func playback_rate(emotion: String, user_rate: float) -> float:
	return clampf(user_rate * _emotion_rate(emotion), 0.5, 1.6)


static func playback_volume(emotion: String, user_volume: float) -> float:
	return clampf(user_volume * _emotion_volume(emotion), 0.0, 1.0)


static func _gender(person_name: String, explicit: String) -> String:
	var given := explicit.strip_edges().to_lower()
	if given in ["female", "f", "ж", "жен", "женский"]:
		return "female"
	if given in ["male", "m", "м", "муж", "мужской"]:
		return "male"
	var trimmed := person_name.strip_edges()
	if trimmed == "":
		return "male"
	var last := trimmed.substr(trimmed.length() - 1, 1).to_lower()
	if last in ["а", "я", "a"]:
		return "female"
	return "male"


static func _age_band(age: int) -> String:
	if age <= 0:
		return "adult"
	if age < 30:
		return "young"
	if age < 55:
		return "adult"
	return "older"


static func _pitch(gender: String, band: String) -> float:
	var pitch := 1.04 if gender == "female" else 0.94
	if band == "young":
		pitch += 0.04
	elif band == "older":
		pitch -= 0.04
	return clampf(pitch, 0.85, 1.15)


static func _strip_leading_direction(line: String) -> String:
	if line == "":
		return ""
	var wrapped := _unwrap_mark(line, "[", "]")
	if wrapped != line:
		return wrapped
	wrapped = _unwrap_mark(line, "(", ")")
	if wrapped != line:
		return wrapped
	wrapped = _unwrap_mark(line, "*", "*")
	if wrapped != line:
		return wrapped
	for dash in ["—", "–", "-"]:
		wrapped = _unwrap_mark(line, dash, dash)
		if wrapped != line:
			return wrapped
	var mood := _mood_prefix(line)
	if int(mood["count"]) <= 0:
		return line
	var rest := str(mood["rest"])
	var marked := int(mood["count"]) >= 2 or bool(mood["separator"])
	if marked and rest != "":
		return rest
	return line


static func _unwrap_mark(line: String, opener: String, closer: String) -> String:
	if not line.begins_with(opener):
		return line
	var end := line.find(closer, opener.length())
	if end <= opener.length() or end > 64:
		return line
	var inner := line.substr(opener.length(), end - opener.length()).strip_edges()
	var rest := line.substr(end + closer.length()).strip_edges()
	if rest == "":
		if _is_direction(inner):
			return ""
		return line
	if _is_direction(inner):
		return rest
	return line


static func _is_direction(inner: String) -> bool:
	var text := inner.strip_edges()
	if text == "" or text.length() > 48:
		return false
	if text.contains(".") or text.contains("!") or text.contains("?"):
		return false
	return true


static func _mood_prefix(line: String) -> Dictionary:
	var index := 0
	var count := 0
	while index < line.length():
		while index < line.length() and (line.substr(index, 1) == " " or line.substr(index, 1) == ","):
			index += 1
		var word_end := index
		while word_end < line.length():
			var ch := line.substr(word_end, 1)
			if ch == " " or ch == "," or ch == ":" or ch == "." or ch == "—" or ch == "–" or ch == "-":
				break
			word_end += 1
		if word_end == index:
			break
		var word := line.substr(index, word_end - index).to_lower()
		if not MOOD_WORDS.has(word):
			break
		count += 1
		index = word_end
		if index < line.length() and line.substr(index, 1) == ",":
			continue
		break
	var rest := line.substr(index).strip_edges()
	var separator := false
	if rest.begins_with(":") or rest.begins_with(".") or rest.begins_with("—") or rest.begins_with("–") or rest.begins_with("-"):
		separator = true
		rest = rest.substr(1).strip_edges()
	return {"count": count, "rest": rest, "separator": separator}


static func _emotion_rate(emotion: String) -> float:
	match emotion:
		"nervous", "scared":
			return 1.08
		"sad", "controlled":
			return 0.92
		"calm":
			return 0.97
		_:
			return 1.0


static func _emotion_volume(emotion: String) -> float:
	match emotion:
		"scared", "sad":
			return 0.8
		"angry":
			return 1.0
		"calm", "controlled":
			return 0.92
		_:
			return 1.0


static func _stable_index(seed: String, size: int) -> int:
	if size <= 1:
		return 0
	var sum := 0
	for index in seed.length():
		sum += seed.unicode_at(index)
	return sum % size
