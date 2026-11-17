class_name VoiceTone
extends RefCounted
## Короткая интонация реплики для синтеза. В текст и на экран не попадает.


const CHOICES: PackedStringArray = [
	"нейтрально",
	"нервно",
	"устало",
	"раздражённо",
	"испуганно",
	"грустно",
	"уверенно",
	"уклончиво",
	"саркастично",
]


static func normalize(raw: String) -> String:
	var value := raw.strip_edges().to_lower()
	if value == "" or value == "none" or value == "нет":
		return ""
	var folded := value.replace("ё", "е")
	for choice in CHOICES:
		if choice == value or choice.replace("ё", "е") == folded:
			return choice
	return ""


static func for_speech(raw: String, enabled: bool) -> String:
	if not enabled:
		return ""
	return normalize(raw)
