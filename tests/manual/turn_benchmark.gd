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
	var env_key := OS.get_environment("GEMINI_API_KEY")
	if not LLMConfig.live_smoke_enabled(env_key):
		print("SKIP turn_benchmark")
		quit(0)
		return
	var code := await _run(env_key.strip_edges())
	quit(code)


func _run(api_key: String) -> int:
	var model := OS.get_environment("TURN_BENCH_MODEL").strip_edges()
	if model == "":
		model = "gemini-3.5-flash-lite"
	if model == "gemini-3.5-flash":
		print("SKIP turn_benchmark refuses gemini-3.5-flash")
		return 0
	var turns := int(OS.get_environment("TURN_BENCH_N"))
	if turns <= 0:
		turns = QUESTIONS.size()
	turns = mini(turns, QUESTIONS.size())
	var config := LLMConfig.load_settings()
	config.api_key = api_key
	config.provider = "gemini"
	config.dialogue_model = model
	if LLM.client != null and is_instance_valid(LLM.client):
		LLM.client.queue_free()
	var client := GeminiClient.new()
	client.apply_config(config)
	LLM.client = client
	root.add_child(client)
	var opened: Object = Game.open_case(CASE_PATH)
	if not opened.ok:
		print("FAIL turn_benchmark case")
		return 1
	var agent_id := str(Game.case_data.starting_agent_id)
	if agent_id == "":
		print("FAIL turn_benchmark agent")
		return 1
	print("BENCH model=%s turns=%d" % [model, turns])
	var times: Array = []
	var counts: Array = []
	for index in turns:
		await Game.ask(agent_id, QUESTIONS[index])
		var stats: Dictionary = Game.last_turn_stats
		var used := str(stats.get("model", ""))
		if used == "gemini-3.5-flash":
			print("STOP turn_benchmark flash fallback")
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
