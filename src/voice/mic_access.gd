class_name MicAccess
extends Node
## RECORD_AUDIO. Захват не стартует, пока разрешение не выдано.
## На Android результат ждёт сигнал MainLoop.on_request_permissions_result.


const RECORD := "android.permission.RECORD_AUDIO"

signal grant_finished(ok: bool)

var provider: Object = null
var just_granted: bool = false


func allowed() -> bool:
	var ok := _is_granted()
	MicInput.record_granted = ok
	return ok


func ensure() -> bool:
	if allowed():
		just_granted = false
		return true
	var ok: bool = await _request()
	MicInput.record_granted = ok
	just_granted = ok
	return ok


static func start_if_allowed(access: MicAccess, input: MicInput) -> bool:
	if access == null or input == null or not access.allowed():
		return false
	if access.just_granted or input.needs_restart:
		input.stop()
		input.needs_restart = false
		access.just_granted = false
		input.api_name = ""
	if input.api_name == "":
		return input.warm()
	return true


func _is_granted() -> bool:
	if provider != null:
		return bool(provider.call("is_granted"))
	if OS.get_name() != "Android":
		return true
	return OS.get_granted_permissions().has(RECORD)


func _request() -> bool:
	if provider != null:
		provider.call("request", self)
		var result: Variant = await grant_finished
		if result is Array:
			return bool((result as Array)[0]) if not (result as Array).is_empty() else false
		return bool(result)
	OS.request_permission(RECORD)
	if OS.get_granted_permissions().has(RECORD):
		return true
	var tree := get_tree()
	if tree == null or not tree.has_signal("on_request_permissions_result"):
		return OS.get_granted_permissions().has(RECORD)
	while is_inside_tree():
		var args: Variant = await tree.on_request_permissions_result
		var permission := ""
		var granted := false
		if args is Array and (args as Array).size() >= 2:
			permission = str((args as Array)[0])
			granted = bool((args as Array)[1])
		if permission == RECORD or permission.ends_with("RECORD_AUDIO"):
			return granted
	return false
