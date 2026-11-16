extends SceneTree
## Снимки экранов на учебной фикстуре. Настоящее дело не открывается.

const FIXTURE := "res://tests/fixtures/turn_flow.json"


func _initialize() -> void:
	var portrait := OS.get_environment("SHOT_LAYOUT") == "portrait"
	var size := Vector2i(800, 1280) if portrait else Vector2i(1280, 800)
	var folder := "portrait" if portrait else "landscape"
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	var packed := load("res://src/main.tscn") as PackedScene
	var main := packed.instantiate() as Control
	root.add_child(main)
	await process_frame
	await process_frame
	await _shot(folder, "menu")
	main.show_settings(true)
	await process_frame
	var key := main.find_child("KeyField", true, false) as LineEdit
	if key != null:
		key.text = ""
		key.secret = true
	await _shot(folder, "settings")
	var game := root.get_node(^"Game")
	var loaded: Object = game.call("open_case", FIXTURE)
	if not bool(loaded.get("ok")):
		print("CAPTURE_FAIL open")
		quit(1)
		return
	main.show_briefing()
	await process_frame
	await _shot(folder, "briefing")
	main.show_investigation()
	await process_frame
	await process_frame
	await _shot(folder, "investigation")
	_select_tab(main, "Блокнот")
	await process_frame
	await _shot(folder, "notebook")
	var state: Object = game.get("state")
	var unlocked: Array = state.get("unlocked_evidence")
	if not unlocked.has("ev"):
		unlocked.append("ev")
	var board: Node = main.find_child("EvidenceBoard", true, false)
	if board != null:
		board.refresh()
	_select_tab(main, "Улики")
	await process_frame
	await _shot(folder, "evidence")
	var prompt := main.find_child("PromptField", true, false) as TextEdit
	var chat: Node = main.find_child("Interrogation", true, false)
	if prompt != null and chat != null:
		prompt.text = "Записка"
		chat._refresh_hint_from_text()
	await process_frame
	await _shot(folder, "hint")
	main.show_accusation()
	await process_frame
	await _shot(folder, "accusation")
	var case_data: Object = game.get("case_data")
	case_data.set("truth_timeline", "Учебный итог.")
	var accusation: Node = main.find_child("Accusation", true, false)
	if accusation != null:
		accusation._show_victory()
	await process_frame
	await _shot(folder, "victory")
	main.show_damaged([{"code": "file_not_found", "message": "учебная ошибка"}])
	await process_frame
	await _shot(folder, "damaged")
	print("CAPTURE_OK %s" % folder)
	quit(0)


func _select_tab(main: Node, title: String) -> void:
	var side := main.find_child("SideTabs", true, false) as TabContainer
	if side == null:
		return
	for index in side.get_tab_count():
		if side.get_tab_title(index) == title:
			side.current_tab = index
			return


func _shot(folder: String, shot_name: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	if image == null or image.get_width() < 10:
		print("CAPTURE_EMPTY %s" % shot_name)
		return
	var path := "/opt/cursor/artifacts/ui-%s-%s.png" % [folder, shot_name]
	var error := image.save_png(path)
	if error != OK:
		print("CAPTURE_SAVE %s %s" % [shot_name, error])
