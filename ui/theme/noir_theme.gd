class_name NoirTheme
extends RefCounted

const REGULAR := "res://ui/theme/fonts/PTSans-Regular.ttf"
const ITALIC := "res://ui/theme/fonts/PTSans-Italic.ttf"

const INK := Color("14120f")
const PANEL := Color("221e19")
const BUTTON := Color("2c2822")
const BUTTON_HOVER := Color("3a342c")
const LINE := Color("4a4338")
const PAPER := Color("e7dfd0")
const MUTED := Color("a89880")
const GOLD := Color("c4a574")
const GOOD := Color("8eae86")


static func make(scale: float) -> Theme:
	var theme := Theme.new()
	var font: Font = load(REGULAR)
	theme.default_font = font
	var base := 18.0 if OS.get_name() == "Android" else 16.0
	theme.default_font_size = int(round(base * clampf(scale, 0.85, 1.4)))
	_set_color(theme, "font_color", "Button", PAPER)
	_set_color(theme, "font_hover_color", "Button", PAPER)
	_set_color(theme, "font_pressed_color", "Button", GOLD)
	_set_color(theme, "font_color", "Label", PAPER)
	_set_color(theme, "font_color", "CheckBox", PAPER)
	_set_color(theme, "font_color", "LineEdit", PAPER)
	_set_color(theme, "font_placeholder_color", "LineEdit", MUTED)
	_set_color(theme, "font_color", "TextEdit", PAPER)
	_set_color(theme, "font_placeholder_color", "TextEdit", MUTED)
	_set_color(theme, "font_color", "OptionButton", PAPER)
	_set_color(theme, "font_color", "TabContainer", PAPER)
	_set_color(theme, "font_selected_color", "TabContainer", GOLD)
	_set_color(theme, "font_unselected_color", "TabContainer", MUTED)
	theme.set_stylebox("normal", "Button", _box(BUTTON, LINE))
	theme.set_stylebox("hover", "Button", _box(BUTTON_HOVER, GOLD))
	theme.set_stylebox("pressed", "Button", _box(BUTTON_HOVER, GOLD))
	theme.set_stylebox("focus", "Button", _box(BUTTON, GOLD))
	theme.set_stylebox("disabled", "Button", _box(Color("1a1814"), LINE))
	theme.set_stylebox("normal", "LineEdit", _box(Color("1a1814"), LINE))
	theme.set_stylebox("focus", "LineEdit", _box(Color("1a1814"), GOLD))
	theme.set_stylebox("normal", "TextEdit", _box(Color("1a1814"), LINE))
	theme.set_stylebox("focus", "TextEdit", _box(Color("1a1814"), GOLD))
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, LINE))
	theme.set_stylebox("panel", "TabContainer", _box(PANEL, LINE))
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	return theme


static func italic() -> Font:
	return load(ITALIC)


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_top = 8
	box.content_margin_right = 12
	box.content_margin_bottom = 8
	return box


static func _set_color(theme: Theme, name: String, type_name: String, color: Color) -> void:
	theme.set_color(name, type_name, color)
