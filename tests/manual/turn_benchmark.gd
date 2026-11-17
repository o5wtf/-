extends SceneTree
## Десять реальных ходов текущим контуром. Модель диалога только из окружения,
## по умолчанию gemini-3.5-flash-lite. gemini-3.5-flash этот скрипт не запускает.
## Печатает времена, счётчики и токены. Без текста ответа и без ключа.
##
##   GEMINI_API_KEY=... godot --headless --path . -s res://tests/manual/turn_benchmark.gd


const CASE_PATH := "res://cases/rain_over_shadow.json"
const QUESTIONS: PackedStringArray = [
	"Кто вы?",
	"Где вы были?",
	"Что вы видели?",
	"Что вы делали?",
	"Кто ещё там был?",
	"Что случилось?",
	"Вы кого-нибудь видели?",
	"Что вы можете рассказать?",
	"Почему вы так говорите?",
	"Что было дальше?",
]


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	await process_frame
	var env_key := OS.get_environment("GEMINI_API_KEY")
	if not LLMConfig.live_smoke_enabled(env_key):
		print("SKIP turn_benchmark")
		quit(0)
		return
	var code := await _run(env_key.strip_edges())
	quit(code)


func _run(api_key: String) -> int:
	var game := root.get_node_or_null("Game")
	var llm := root.get_node_or_null("LLM")
	if game == null or llm == null:
		print("FAIL turn_benchmark autoload")
		return 1
	var model := OS.get_environment("TURN_BENCH_MODEL").strip_edges()
	if model == "":
		model = LLMConfig.DEFAULT_DIALOGUE_MODEL
	if not LLMConfig.is_dialogue_model(model):
		print("SKIP turn_benchmark model")
		return 0
	var turns := int(OS.get_environment("TURN_BENCH_N"))
	if turns <= 0:
		turns = QUESTIONS.size()
	turns = mini(turns, QUESTIONS.size())
	var config := LLMConfig.load_settings()
	config.api_key = api_key
	config.provider = "gemini"
	config.dialogue_model = model
	var llm_node := llm as Node
	var current: Variant = llm_node.get("client")
	if current != null and is_instance_valid(current):
		(current as Node).queue_free()
	var client := GeminiClient.new()
	client.apply_config(config)
	llm_node.set("client", client)
	root.add_child(client)
	var opened: Variant = (game as Node).call("open_case", CASE_PATH)
	if not bool(opened.ok):
		print("FAIL turn_benchmark case")
		return 1
	var case_data: Object = (game as Node).get("case_data")
	var agent_id := str(case_data.get("starting_agent_id"))
	if agent_id == "":
		var agents: Variant = case_data.get("agents")
		if agents is Array and not (agents as Array).is_empty():
			agent_id = str((agents as Array)[0].get("id"))
	if agent_id == "":
		print("FAIL turn_benchmark agent")
		return 1
	print("BENCH model=%s turns=%d" % [model, turns])
	var times: Array = []
	var counts: Array = []
	for index in turns:
		await (game as Node).call("ask", agent_id, QUESTIONS[index])
		var stats: Dictionary = (game as Node).get("last_turn_stats")
		var used := str(stats.get("model", ""))
		if used != model and used != "":
			print("STOP turn_benchmark model=%s" % used)
			return 1
		var ms := int(stats.get("ask_to_text_ms", 0))
		var requests := int(stats.get("requests", 0))
		times.append(ms)
		counts.append(requests)
		print("BENCH turn=%d ask_to_text_ms=%d requests=%d summary=%d regen=%d reasons=%s model=%s" % [
			index + 1,
			ms,
			requests,
			int(stats.get("summary", 0)),
			int(stats.get("regen", 0)),
			str(stats.get("reasons", "none")),
			used,
		])
	print("BENCH median ask_to_text_ms=%d requests=%d" % [
		LlmTiming.median_int(times),
		LlmTiming.median_int(counts),
	])
	return 0
