class_name TurnTiming
extends RefCounted
## Длительности фаз хода. В журнал не попадают ключ, реплики и текст дела.


static func span(phase: String, started_ms: int) -> void:
	var elapsed := Time.get_ticks_msec() - started_ms
	if elapsed < 0:
		elapsed = 0
	print("timing phase=%s ms=%d" % [phase, elapsed])
