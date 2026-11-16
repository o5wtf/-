class_name UiLayout
extends RefCounted
## Широкая раскладка — планшет лёжа и окно Windows. Средняя — планшет стоя.
## Узкий телефон не делается.
## При stretch/expand логическая ширина не падает ниже базы 1280, поэтому
## портрет определяется по размеру окна, а не по ширине вьюпорта.


static func mode_for_size(size: Vector2) -> String:
	if size.x < 1000.0 or size.y > size.x:
		return "medium"
	return "wide"
