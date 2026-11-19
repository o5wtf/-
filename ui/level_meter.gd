class_name LevelMeter
extends RefCounted
## Полоска громкости: быстрый подъём и спад примерно за 0.25 с. На экран — не чаще 15 раз в секунду.

const ATTACK_S := 0.05
const RELEASE_S := 0.25
const FRAME_S := 1.0 / 15.0

var shown: float = 0.0
var target: float = 0.0
var _wait: float = 0.0


func push(level: float) -> void:
	target = clampf(level, 0.0, 1.0)


func advance(delta: float) -> bool:
	var tau := ATTACK_S if target > shown else RELEASE_S
	var blend := 1.0 - exp(-delta / tau)
	shown = lerpf(shown, target, blend)
	if shown < 0.004 and target < 0.004:
		shown = 0.0
	_wait += delta
	if _wait < FRAME_S:
		return false
	_wait = 0.0
	return true
