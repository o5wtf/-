extends TestCase
## Проверяет, что каркас проекта жив: автозагрузки на месте и раннер ждёт await.


func test_autoload_game_exists() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		fail("нет дерева сцены")
		return
	var node := tree.root.get_node_or_null(^"Game")
	assert_true(node != null, "автозагрузка Game")
	assert_eq(node, Game)


func test_autoload_llm_exists() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		fail("нет дерева сцены")
		return
	var node := tree.root.get_node_or_null(^"LLM")
	assert_true(node != null, "автозагрузка LLM")
	assert_eq(node, LLM)


func test_assert_helpers() -> void:
	assert_eq("a", "a")
	assert_true(true)
	assert_false(false)
	assert_has(["улика", "агент"], "агент")
	assert_has({"k": 1}, "k")
	assert_has("Detective", "tect")


func test_async_await_runs_to_completion() -> void:
	begin_async()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		fail("нет дерева сцены")
		end_async()
		return
	await tree.process_frame
	var node := tree.root.get_node_or_null(^"LLM")
	assert_true(node != null, "после await автозагрузка LLM на месте")
	end_async()
