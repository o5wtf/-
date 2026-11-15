class_name Accusation
extends RefCounted
## Проверка обвинения (раздел 4). Галочки только накапливаются.


static func check(
	case_data: CaseData,
	state: GameState,
	killer_id: String,
	motive_id: String,
	method_id: String
) -> Dictionary:
	state.accusation["attempts"] = int(state.accusation["attempts"]) + 1
	var killer_match := killer_id == case_data.killer_id
	var motive_evaluated := false
	var method_evaluated := false
	var motive_match := false
	var method_match := false
	if killer_match:
		state.accusation["killer_ok"] = true
		motive_evaluated = true
		method_evaluated = true
		motive_match = motive_id == case_data.true_motive_id
		method_match = method_id == case_data.true_method_id
		if motive_match:
			state.accusation["motive_ok"] = true
		if method_match:
			state.accusation["method_ok"] = true
	var killer_ok: bool = state.accusation["killer_ok"] == true
	var motive_ok: bool = state.accusation["motive_ok"] == true
	var method_ok: bool = state.accusation["method_ok"] == true
	return {
		"killer_ok": killer_ok,
		"motive_ok": motive_ok,
		"method_ok": method_ok,
		"killer_match": killer_match,
		"motive_match": motive_match,
		"method_match": method_match,
		"motive_evaluated": motive_evaluated,
		"method_evaluated": method_evaluated,
		"solved": killer_ok and motive_ok and method_ok,
		"attempts": int(state.accusation["attempts"]),
	}
