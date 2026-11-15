class_name EvidenceMatcher
extends RefCounted
## Ищет название открытой улики в вопросе: без регистра, по первым 5 буквам длинных слов.


static func find_mentioned(question: String, evidence_items: Array) -> Array[String]:
	var question_words := _words(question)
	var found: Array[String] = []
	for item in evidence_items:
		var title := ""
		var evidence_id := ""
		if item is CaseData.EvidenceItem:
			var evidence := item as CaseData.EvidenceItem
			title = evidence.title
			evidence_id = evidence.id
		elif item is Dictionary:
			title = str((item as Dictionary).get("title", ""))
			evidence_id = str((item as Dictionary).get("id", ""))
		if evidence_id == "" or title == "":
			continue
		if _title_mentioned(title, question_words):
			found.append(evidence_id)
	return found


static func _title_mentioned(title: String, question_words: PackedStringArray) -> bool:
	for raw_word in _words(title):
		if raw_word.length() > 4:
			var stem := raw_word.substr(0, 5)
			for question_word in question_words:
				if question_word.length() > 4 and question_word.substr(0, 5) == stem:
					return true
		else:
			for question_word in question_words:
				if question_word == raw_word:
					return true
	return false


static func _words(text: String) -> PackedStringArray:
	var words := PackedStringArray()
	var current := ""
	for index in text.length():
		var ch := text.substr(index, 1).to_lower()
		if _is_letter(ch):
			current += ch
		elif current != "":
			words.append(current)
			current = ""
	if current != "":
		words.append(current)
	return words


static func _is_letter(ch: String) -> bool:
	if ch == "ё":
		return true
	return (ch >= "a" and ch <= "z") or (ch >= "а" and ch <= "я")
