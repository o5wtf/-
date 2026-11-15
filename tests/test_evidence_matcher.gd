extends TestCase


func test_finds_title_across_cases() -> void:
	var evidence: Array[Dictionary] = [
		{"id": "note", "title": "Записка"},
		{"id": "report", "title": "Финансовый отчёт"},
		{"id": "knife", "title": "Нож"},
		{"id": "log", "title": "Журнал охраны"},
	]
	assert_eq(EvidenceMatcher.find_mentioned("Где записка?", evidence), ["note"])
	assert_eq(EvidenceMatcher.find_mentioned("Покажите записку следователю", evidence), ["note"])
	assert_eq(EvidenceMatcher.find_mentioned("В записке ничего нет", evidence), ["note"])
	assert_eq(EvidenceMatcher.find_mentioned("Он клялся финансовым отчётом", evidence), ["report"])
	assert_eq(EvidenceMatcher.find_mentioned("Сверьте с журналом", evidence), ["log"])
	assert_eq(EvidenceMatcher.find_mentioned("Где нож и записки?", evidence), ["note", "knife"])
	assert_eq(EvidenceMatcher.find_mentioned("Про замок на двери", evidence), [])


func test_ignores_closed_evidence_the_caller_did_not_pass() -> void:
	var open_only: Array[Dictionary] = [{"id": "note", "title": "Записка"}]
	assert_eq(EvidenceMatcher.find_mentioned("Покажите финансовый отчёт и записку", open_only), ["note"])
