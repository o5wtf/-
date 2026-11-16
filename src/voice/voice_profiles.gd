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
	return reply.strip_edges()


static func style_prompt(reply: String, emotion: String, remark: String) -> String:
	var line := spoken_text(reply)
	var direction := _direction(emotion)
	var stage := remark.strip_edges()
	var prompt := "Скажи по-русски, %s." % direction
	if stage != "":
		prompt += " Подача, не произноси это вслух: %s." % stage
	prompt += "\nПроизнеси только реплику:\n%s" % line
	return prompt


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


static func _direction(emotion: String) -> String:
	match emotion:
		"calm":
			return "спокойно и ровно"
		"nervous":
			return "нервно и сбивчиво"
		"scared":
			return "тихо и испуганно"
		"sad":
			return "тихо и печально"
		"angry":
			return "резко и гневно"
		"controlled":
			return "холодно и сдержанно"
		"contemptuous":
			return "медленно и с презрением"
		_:
			return "обычным голосом"


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
