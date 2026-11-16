class_name Notebook
extends RefCounted
## Журнал услышанного для игрока. Данные лежат в GameState и уже сериализуются.

var case_data: CaseData
var state: GameState


func _init(case_data: CaseData, state: GameState) -> void:
	self.case_data = case_data
	self.state = state


func entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for heard in state.heard:
		var fact_id := str(heard.get("fact_id", ""))
		var form := str(heard.get("form", ""))
		var fact: CaseData.Fact = case_data.fact_by_id.get(fact_id) as CaseData.Fact
		rows.append({
			"agent_id": str(heard.get("agent_id", "")),
			"turn": int(heard.get("turn", 0)),
			"fact_id": fact_id,
			"form": form,
			"text": text_for(fact, form),
		})
	return rows


func contradiction_choices() -> Array[Dictionary]:
	return entries()


static func text_for(fact: CaseData.Fact, form: String) -> String:
	if fact == null:
		return ""
	if form == "lie":
		return fact.lie_text
	if form == "full":
		return fact.content_full
	return fact.content_basic


func to_dict() -> Dictionary:
	return {"heard": state.heard.duplicate(true)}
