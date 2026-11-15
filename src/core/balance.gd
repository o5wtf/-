class_name Balance
extends RefCounted
## Числа давления из раздела 11 диздока. Полосы — для ремарок UI (UI§2.3).

const EVIDENCE_KEY := 10
const EVIDENCE_NORMAL := 5
const CONTRADICTION_LIE := 10
const CONTRADICTION_PLAIN := 5

const EMOTIONS: PackedStringArray = [
	"calm", "neutral", "nervous", "scared", "sad", "angry", "controlled", "contemptuous",
]


static func clamp_pressure(value: int) -> int:
	return clampi(value, 0, 100)


static func band(pressure_value: int) -> String:
	var value := clamp_pressure(pressure_value)
	if value >= 75:
		return "breaking"
	if value >= 50:
		return "nervous"
	if value >= 25:
		return "tense"
	return "calm"


static func emotion_allowed(emotion: String) -> bool:
	return EMOTIONS.has(emotion)
