@tool
extends EditorPlugin
## Подключает экспортный плагин. Игровой ход его не вызывает.


var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/tts_query/export_plugin.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	if _export != null:
		remove_export_plugin(_export)
		_export = null
