extends Control

const BUILTIN_CASE := "res://cases/rain_over_shadow.json"

var _screen: Control = null


func _ready() -> void:
	UiWidgets.fill(self)
	if OS.get_name() == "Windows":
		DisplayServer.window_set_min_size(Vector2i(1024, 640))
	_apply_theme()
	show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()


func show_menu() -> void:
	var screen := preload("res://ui/screens/main_menu.tscn").instantiate()
	_swap(screen)
	screen.new_case_pressed.connect(_on_new_case)
	screen.settings_pressed.connect(func() -> void: show_settings(false))


func show_settings(explain_key: bool) -> void:
	var screen := preload("res://ui/screens/settings.tscn").instantiate()
	screen.explain_key = explain_key
	screen.back_pressed.connect(show_menu)
	screen.saved.connect(_apply_theme)
	_swap(screen)


func show_briefing() -> void:
	var screen := preload("res://ui/screens/briefing.tscn").instantiate()
	screen.start_pressed.connect(show_investigation)
	_swap(screen)


func show_investigation() -> void:
	var screen := preload("res://ui/screens/investigation.tscn").instantiate()
	screen.menu_pressed.connect(show_menu)
	screen.accuse_pressed.connect(show_accusation)
	_swap(screen)


func show_accusation() -> void:
	var screen := preload("res://ui/screens/accusation.tscn").instantiate()
	screen.menu_pressed.connect(show_menu)
	_swap(screen)


func show_damaged(errors: Array) -> void:
	var screen := preload("res://ui/screens/damaged_case.tscn").instantiate()
	screen.errors = errors
	screen.back_pressed.connect(show_menu)
	_swap(screen)


func _on_new_case() -> void:
	if not SettingsStore.has_playable_key():
		show_settings(true)
		return
	var loaded := Game.open_case(BUILTIN_CASE)
	if not loaded.ok:
		show_damaged(loaded.errors)
		return
	show_briefing()


func _apply_theme() -> void:
	theme = NoirTheme.make(SettingsStore.load_current().text_scale)


func _swap(screen: Control) -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = screen
	UiWidgets.fill(screen)
	add_child(screen)
