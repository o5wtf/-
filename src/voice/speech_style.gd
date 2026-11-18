class_name SpeechStyle
extends RefCounted
## Стиль синтеза: манера персонажа, интонация реплики и темп.
## Пустой результат значит, что speechMetadata не отправляется.
## Русские слова тона оставлены: сравнение с английскими на платном ключе здесь не запускалось.


const PACE_SLOW := "медленно"
const PACE_FAST := "быстро"


static func compose(voice_style: String, tone: String, pace: String, enabled: bool) -> String:
	if not enabled:
		return ""
	var parts := PackedStringArray()
	var manner := voice_style.strip_edges()
	if manner != "":
		parts.append(manner)
	var spoken := VoiceTone.for_speech(tone, true)
	if spoken != "" and spoken != "нейтрально":
		parts.append(spoken)
	var speed := pace_phrase(pace)
	if speed != "":
		parts.append(speed)
	return ", ".join(parts)


static func pace_phrase(raw: String) -> String:
	match raw.strip_edges().to_lower():
		"slow":
			return PACE_SLOW
		"fast":
			return PACE_FAST
		_:
			return ""


static func normalize_pace(raw: String) -> String:
	var value := raw.strip_edges().to_lower()
	if value == "slow" or value == "normal" or value == "fast":
		return value
	return ""
