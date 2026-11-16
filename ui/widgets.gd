class_name UiWidgets
extends RefCounted


static func fill(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL


static func button(text: String, node_name: String) -> Button:
	var control := Button.new()
	control.text = text
	control.name = node_name
	control.custom_minimum_size = Vector2(48, 48)
	return control


static func label(text: String, node_name: String = "") -> Label:
	var control := Label.new()
	control.text = text
	if node_name != "":
		control.name = node_name
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control


static func scrolling(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll
