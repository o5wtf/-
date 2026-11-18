class_name Summarizer
extends RefCounted
## Резюме старой части истории. Запрос к модели и запасной текст без неё.

const SYSTEM_PROMPT := "Ты ведёшь протокол допроса. Сожми разговор в краткое резюме от третьего лица, по-русски, до 600 символов.\nПиши только то, что было сказано: кто что утверждал, на чём настаивал, что признал, какие улики показали.\nНе добавляй выводов, догадок и сведений, которых не было в разговоре."


static func build_request(agent_name: String, old_summary: String, messages: Array) -> Dictionary:
	var previous := old_summary if old_summary != "" else "—"
	var lines: PackedStringArray = PackedStringArray()
	for message in messages:
		if message is not Dictionary:
			continue
		lines.append(_format_line(agent_name, message as Dictionary))
	var user := "ПРЕДЫДУЩЕЕ РЕЗЮМЕ: %s\nНОВЫЕ РЕПЛИКИ:\n%s" % [previous, "\n".join(lines)]
	return {
		"system": SYSTEM_PROMPT,
		"user": user,
		"schema": {
			"type": "object",
			"properties": {"summary": {"type": "string"}},
			"required": ["summary"],
		},
		"model_role": "summary",
		"temperature": 0.2,
		"max_output_tokens": 8192,
	}


## Старое резюме плюс «Имя сказал(а): …» по журналу услышанного за эти ходы.
static func fallback_summary(agent_name: String, old_summary: String, folded_messages: Array, heard: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if old_summary != "":
		lines.append(old_summary)
	var turns := {}
	for message in folded_messages:
		if message is Dictionary:
			turns[int((message as Dictionary).get("turn", -1))] = true
	for entry in heard:
		if entry is not Dictionary:
			continue
		var body := entry as Dictionary
		if not turns.has(int(body.get("turn", -999))):
			continue
		var spoken := str(body.get("text", "")).strip_edges()
		if spoken == "":
			continue
		lines.append("%s сказал(а): %s" % [agent_name, spoken])
	return "\n".join(lines)


static func apply_fallback(dialogue: DialogueState, agent_name: String, heard: Array) -> void:
	if not dialogue.needs_summary():
		return
	var fold_until := dialogue.messages.size() - 6
	var folded: Array = dialogue.messages.slice(dialogue.summarized_count, fold_until)
	dialogue.summary = fallback_summary(agent_name, dialogue.summary, folded, heard)
	dialogue.summarized_count = fold_until


static func _format_line(agent_name: String, message: Dictionary) -> String:
	var text := str(message.get("text", ""))
	if str(message.get("role", "")) != "player":
		text = VocalTags.visible(text)
	if str(message.get("role", "")) == "player":
		return "Следователь: %s" % text
	return "%s: %s" % [agent_name, text]
