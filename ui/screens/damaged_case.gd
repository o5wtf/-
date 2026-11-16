extends Control

signal back_pressed

var errors: Array = []


func _ready() -> void:
	UiWidgets.fill(self)
	var backdrop := ColorRect.new()
	backdrop.color = NoirTheme.INK
	UiWidgets.fill(backdrop)
	add_child(backdrop)
	var box := VBoxContainer.new()
	UiWidgets.fill(box)
	add_child(box)
	box.add_child(UiWidgets.label(UiStrings.DAMAGED, "TitleLabel"))
	var list := UiWidgets.label("", "ErrorList")
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lines: PackedStringArray = PackedStringArray()
	for item in errors:
		if item is Dictionary:
			lines.append(str((item as Dictionary).get("code", "")))
		else:
			lines.append(str(item))
	list.text = "\n".join(lines)
	box.add_child(list)
	var back := UiWidgets.button(UiStrings.BACK, "BackButton")
	back.pressed.connect(func() -> void: back_pressed.emit())
	box.add_child(back)
