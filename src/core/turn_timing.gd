class_name TurnTiming
extends RefCounted
## Длительности фаз хода. В журнал не попадают ключ, реплики и текст дела.


static func span(phase: String, started_ms: int) -> void:
	_print(phase, started_ms, "")


static func span_engine(phase: String, started_ms: int, engine: String) -> void:
	_print(phase, started_ms, engine)


static func _print(phase: String, started_ms: int, engine: String) -> void:
	var elapsed := Time.get_ticks_msec() - started_ms
	if elapsed < 0:
		elapsed = 0
	if engine == "":
		print("timing phase=%s ms=%d" % [phase, elapsed])
	else:
		print("timing phase=%s engine=%s ms=%d" % [phase, engine, elapsed])
