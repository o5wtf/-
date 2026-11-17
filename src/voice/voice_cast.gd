class_name VoiceCast
extends RefCounted
## Голос персонажа для Gemini TTS. Поле дела важнее пола.


const MALE := "Charon"
const FEMALE := "Kore"
const EMOTIONS: PackedStringArray = [
	"angry", "calm", "contemptuous", "controlled", "nervous", "sad", "scared",
]


static func voice_for(agent: CaseData.Agent) -> String:
	if agent == null:
		return FEMALE
	var named := agent.tts_voice.strip_edges()
	if _name_ok(named):
		return named
	if agent.gender == "male":
		return MALE
	return FEMALE


static func style_for(emotion: String) -> String:
	var value := emotion.strip_edges().to_lower()
	if EMOTIONS.has(value):
		return value
	return ""


static func _name_ok(value: String) -> bool:
	if value.length() < 2 or value.length() > 32:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z][A-Za-z0-9]+$")
	return pattern.search(value) != null
