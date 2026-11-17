class_name GreetingPlan
extends RefCounted
## Короткие приветствия из поля greeting. Сюжета дела здесь нет.


static func jobs(case_data: CaseData, voice_on: bool, gemini: bool) -> Array:
	var planned: Array = []
	if case_data == null or not voice_on or not gemini:
		return planned
	for agent in case_data.agents:
		if agent == null:
			continue
		var text := SpeechText.clean(agent.greeting)
		if text == "":
			continue
		planned.append({
			"text": text,
			"voice": VoiceCast.voice_for(agent),
			"style": "",
		})
	return planned
