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


static func spoken_text(reply: String) -> String:
	return _clean_line(reply)


static func style_prompt(reply: String, emotion: String, remark: String) -> String:
	var line := spoken_text(reply)
	var tags := _style_tags(emotion, remark)
	if line == "":
		return ""
	if tags == "":
		return line
	return "[%s] %s" % [tags, line]


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


static func _style_tags(emotion: String, remark: String) -> String:
	var tags: PackedStringArray = PackedStringArray()
	var mood := _mood(emotion)
	if mood != "":
		tags.append(mood)
	var stage := _condense_remark(remark)
	if stage != "":
		tags.append(stage)
	return ", ".join(tags)


static func _mood(emotion: String) -> String:
	match emotion:
		"calm":
			return "спокойно"
		"nervous":
			return "нервно, сбивчиво"
		"scared":
			return "тихо, испуганно"
		"sad":
			return "тихо, печально"
		"angry":
			return "резко, гневно"
		"controlled":
			return "холодно, сдержанно"
		"contemptuous":
			return "медленно, презрительно"
		_:
			return "ровно"


static func _clean_line(reply: String) -> String:
	var line := reply.strip_edges()
	line = line.replace("[", "").replace("]", "").replace("*", "")
	return line.strip_edges()


static func _condense_remark(remark: String) -> String:
	var text := remark.strip_edges()
	for mark in ["[", "]", "*", "\"", "«", "»", ".", "!", "?", ",", ";", ":"]:
		text = text.replace(mark, " ")
	var words: PackedStringArray = PackedStringArray()
	for word in text.split(" ", false):
		var clean := str(word).strip_edges()
		if clean == "":
			continue
		var lower := clean.to_lower()
		if lower.contains("скаж") or lower.contains("произнес") or lower == "вслух":
			continue
		words.append(clean)
	text = " ".join(words)
	if text.length() > 40:
		text = text.substr(0, 40).strip_edges()
	return text


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
