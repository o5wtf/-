#!/usr/bin/env python3
"""Проверка файла дела по правилам диздока (разделы 2, 7, 8, 13, 14, 15).

Запуск: python3 tools/validate_case.py cases/<дело>.json
Код возврата 0 — дело корректно, 1 — найдены ошибки.
"""
import json
import sys

EMOTIONS = {"calm", "neutral", "nervous", "scared", "sad", "angry", "controlled", "contemptuous"}
LIE_TYPES = {"must_lie", "can_lie", "cannot_lie"}
BREAKS = {"pressure", "evidence", "contradiction", None}
FORMS = {"truth", "lie"}


def validate(case):
    errors = []
    err = errors.append

    for key in ("id", "title", "briefing", "killer_id", "true_motive_id", "true_method_id",
                "motive_options", "method_options", "agents", "evidence"):
        if key not in case:
            err(f"нет обязательного поля дела: {key}")
    agents = case.get("agents", [])
    evidence = case.get("evidence", [])
    contradictions = case.get("contradictions", [])

    def unique_ids(items, what):
        ids = {}
        for it in items:
            i = it.get("id")
            if not i:
                err(f"{what} без id: {it}")
            elif i in ids:
                err(f"повторяющийся id {what}: {i}")
            ids[i] = it
        return ids

    agent_ids = unique_ids(agents, "агента")
    ev_ids = unique_ids(evidence, "улики")
    contr_ids = unique_ids(contradictions, "противоречия")
    facts = {}
    fact_owner = {}
    for a in agents:
        for f in a.get("facts", []):
            fid = f.get("id")
            if not fid:
                err(f"факт без id у агента {a.get('id')}")
                continue
            if fid in facts:
                err(f"повторяющийся id факта: {fid}")
            facts[fid] = f
            fact_owner[fid] = a.get("id")

    # Скрытая правда
    if case.get("killer_id") not in agent_ids:
        err(f"убийца {case.get('killer_id')} не найден среди агентов")
    motive_ids = {m.get("id") for m in case.get("motive_options", [])}
    method_ids = {m.get("id") for m in case.get("method_options", [])}
    if case.get("true_motive_id") not in motive_ids:
        err(f"true_motive_id {case.get('true_motive_id')} нет в motive_options")
    if case.get("true_method_id") not in method_ids:
        err(f"true_method_id {case.get('true_method_id')} нет в method_options")
    if case.get("starting_agent_id") and case["starting_agent_id"] not in agent_ids:
        err(f"starting_agent_id {case['starting_agent_id']} не найден")

    # Агенты
    for a in agents:
        aid = a.get("id")
        for key in ("name", "role", "personality", "background", "facts"):
            if key not in a or a[key] in ("", None):
                err(f"агент {aid}: нет поля {key}")
        emo = a.get("starting_emotion", "neutral")
        if emo not in EMOTIONS:
            err(f"агент {aid}: эмоция '{emo}' не из списка {sorted(EMOTIONS)}")
        for key in ("starting_pressure", "starting_fatigue"):
            v = a.get(key, 0)
            if not isinstance(v, (int, float)) or not 0 <= v <= 100:
                err(f"агент {aid}: {key}={v} вне 0–100")
        for other in (a.get("relationships") or {}):
            if other not in agent_ids or other == aid:
                err(f"агент {aid}: relationships ссылается на неверного агента {other}")

    # Факты
    lie_facts_in_contradictions = set()
    for c in contradictions:
        for side in ("a", "b"):
            if c.get(f"fact_{side}_form") == "lie":
                lie_facts_in_contradictions.add(c.get(f"fact_{side}_id"))
    for fid, f in facts.items():
        p = f"факт {fid}"
        for key in ("content_basic", "content_full"):
            if not f.get(key):
                err(f"{p}: пустое {key}")
        pb, pf = f.get("pressure_for_basic"), f.get("pressure_for_full")
        if not isinstance(pb, (int, float)) or not isinstance(pf, (int, float)):
            err(f"{p}: пороги давления не числа")
        elif pf < pb:
            err(f"{p}: pressure_for_full ({pf}) < pressure_for_basic ({pb})")
        rel = f.get("related_evidence_ids", [])
        for e in rel:
            if e not in ev_ids:
                err(f"{p}: улика {e} не существует")
        if f.get("requires_evidence") and not rel:
            err(f"{p}: requires_evidence=true, но related_evidence_ids пуст")
        lt = f.get("lie_type")
        if lt not in LIE_TYPES:
            err(f"{p}: lie_type '{lt}' не из {sorted(LIE_TYPES)}")
        is_lie = f.get("is_lie")
        br = f.get("breaks_lie_on")
        if br not in BREAKS:
            err(f"{p}: breaks_lie_on '{br}' недопустим")
        if lt in ("must_lie", "can_lie"):
            if is_lie is not True:
                err(f"{p}: lie_type={lt}, но is_lie не true")
            if not f.get("lie_text"):
                err(f"{p}: lie_type={lt}, но lie_text пуст")
        if lt == "cannot_lie":
            if is_lie:
                err(f"{p}: cannot_lie, но is_lie=true")
            if f.get("lie_text"):
                err(f"{p}: cannot_lie, но lie_text заполнен")
        if is_lie and not br:
            err(f"{p}: is_lie=true, но breaks_lie_on не задан")
        if br == "evidence" and not rel:
            err(f"{p}: breaks_lie_on=evidence, но нет related_evidence_ids")
        if br == "contradiction" and fid not in lie_facts_in_contradictions:
            err(f"{p}: breaks_lie_on=contradiction, но нет противоречия с этим фактом в форме lie")

    # Противоречия
    for cid, c in contr_ids.items():
        pair = []
        for side in ("a", "b"):
            fid, form = c.get(f"fact_{side}_id"), c.get(f"fact_{side}_form")
            if fid not in facts:
                err(f"противоречие {cid}: факт {fid} не существует")
            elif form == "lie" and not facts[fid].get("is_lie"):
                err(f"противоречие {cid}: форма lie у факта {fid} без лжи")
            if form not in FORMS:
                err(f"противоречие {cid}: форма '{form}' не из {sorted(FORMS)}")
            pair.append((fid, form))
        if pair[0] == pair[1]:
            err(f"противоречие {cid}: оба утверждения одинаковы")
        if not c.get("description"):
            err(f"противоречие {cid}: нет description")

    # Условия открытия
    def check_cond(cond, where, ev_self):
        if cond is None:
            return
        if not isinstance(cond, dict):
            err(f"{where}: условие не объект: {cond}")
            return
        for op in ("AND", "OR"):
            if op in cond:
                if len(cond) != 1 or not isinstance(cond[op], list) or not cond[op]:
                    err(f"{where}: {op} должен быть единственным ключом с непустым списком")
                    return
                for sub in cond[op]:
                    check_cond(sub, where, ev_self)
                return
        t = cond.get("type")
        if t == "pressure_on_agent":
            if cond.get("agent_id") not in agent_ids:
                err(f"{where}: агент {cond.get('agent_id')} не найден")
            g = cond.get("gte")
            if not isinstance(g, (int, float)) or not 0 <= g <= 100:
                err(f"{where}: gte={g} вне 0–100")
        elif t == "dialogue_with":
            if cond.get("agent_id") not in agent_ids:
                err(f"{where}: агент {cond.get('agent_id')} не найден")
        elif t == "evidence_shown":
            if cond.get("evidence_id") not in ev_ids:
                err(f"{where}: улика {cond.get('evidence_id')} не найдена")
            if cond.get("evidence_id") == ev_self:
                err(f"{where}: улика требует предъявления самой себя")
            if "agent_id" in cond and cond["agent_id"] not in agent_ids:
                err(f"{where}: агент {cond['agent_id']} не найден")
        elif t == "inconsistency_created":
            if "contradiction_id" in cond and cond["contradiction_id"] not in contr_ids:
                err(f"{where}: противоречие {cond['contradiction_id']} не найдено")
        else:
            err(f"{where}: неизвестный тип условия '{t}'")

    # Улики
    for eid, e in ev_ids.items():
        for key in ("title", "short_description", "full_text", "type"):
            if not e.get(key):
                err(f"улика {eid}: нет поля {key}")
        for f in e.get("related_fact_ids", []):
            if f not in facts:
                err(f"улика {eid}: факт {f} не существует")
        for a in e.get("related_agent_ids", []):
            if a not in agent_ids:
                err(f"улика {eid}: агент {a} не существует")
        if e.get("is_key") and not e.get("related_fact_ids") and not e.get("related_agent_ids"):
            err(f"ключевая улика {eid} ни с чем не связана")
        if e.get("is_key") and not e.get("related_fact_ids"):
            err(f"ключевая улика {eid} не связана ни с одним фактом")
        check_cond(e.get("unlock_condition"), f"улика {eid}", eid)

    # Взаимность связей факт <-> улика (предупреждения не блокируют)
    warnings = []
    for eid, e in ev_ids.items():
        for f in e.get("related_fact_ids", []):
            if f in facts and eid not in facts[f].get("related_evidence_ids", []):
                warnings.append(f"улика {eid} ссылается на факт {f}, но факт не ссылается на улику")
    return errors, warnings


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    with open(sys.argv[1], encoding="utf-8") as fh:
        case = json.load(fh)
    errors, warnings = validate(case)
    for w in warnings:
        print("ПРЕДУПРЕЖДЕНИЕ:", w)
    for e in errors:
        print("ОШИБКА:", e)
    if errors:
        print(f"Дело не прошло проверку: ошибок {len(errors)}.")
        return 1
    print(f"Дело корректно. Агентов: {len(case['agents'])}, фактов: "
          f"{sum(len(a['facts']) for a in case['agents'])}, улик: {len(case['evidence'])}, "
          f"противоречий: {len(case.get('contradictions', []))}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
