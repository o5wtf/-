class_name UiLayout
extends RefCounted
## Широкая раскладка — планшет лёжа и окно Windows. Портрет — чат на всю ширину.
## Узкий телефон не делается.
## База проекта 1280×800. В альбоме stretch/expand не трогаем.
## В портрете множитель возвращает масштаб к 1, чтобы текст и кнопки
## остались того же физического размера, что и лёжа.

const BASE_SIZE := Vector2(1280, 800)


static func mode_for_size(size: Vector2) -> String:
	if size.x < 1000.0 or size.y > size.x:
		return "medium"
	return "wide"


static func content_scale_factor_for(window_size: Vector2) -> float:
	if window_size.x < 2.0 or window_size.y < 2.0:
		return 1.0
	if window_size.y <= window_size.x:
		return 1.0
	var fit := minf(window_size.x / BASE_SIZE.x, window_size.y / BASE_SIZE.y)
	if fit <= 0.001:
		return 1.0
	return 1.0 / fit
