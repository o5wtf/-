class_name VoiceRateLimiter
extends RefCounted
## Не больше 10 запросов Gemini TTS в минуту. Окно скользит по времени вызовов.


const LIMIT := 10
const WINDOW_S := 60.0

var stamps: Array[float] = []


func delay_for(now: float) -> float:
	_trim(now)
	if stamps.size() < LIMIT:
		return 0.0
	return maxf(0.0, stamps[0] + WINDOW_S - now)


func mark(now: float) -> void:
	_trim(now)
	stamps.append(now)


func _trim(now: float) -> void:
	var kept: Array[float] = []
	for stamp in stamps:
		if now - stamp < WINDOW_S:
			kept.append(stamp)
	stamps = kept
