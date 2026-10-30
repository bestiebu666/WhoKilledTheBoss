extends Node
var main: Node3D
func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	for i in range(40): await get_tree().process_frame
	main._open_spot("feng_desk")
	for i in range(15): await get_tree().process_frame
	var h = main.hud
	print("box   size=", h._modal_paper_box.size, " min=", h._modal_paper_box.custom_minimum_size, " glob=", h._modal_paper_box.global_position)
	print("paper size=", h._modal_paper.size, " glob=", h._modal_paper.global_position)
	print("pad   size=", h._modal_pad.size, " glob=", h._modal_pad.global_position, " anchors=", h._modal_pad.anchor_left, h._modal_pad.anchor_top, h._modal_pad.anchor_right, h._modal_pad.anchor_bottom)
	print("pad margins l/t/r/b=", h._modal_pad.get_theme_constant("margin_left"), h._modal_pad.get_theme_constant("margin_top"), h._modal_pad.get_theme_constant("margin_right"), h._modal_pad.get_theme_constant("margin_bottom"))
	print("col   size=", h._modal_col.size, " glob=", h._modal_col.global_position)
	print("title glob=", h._title.global_position, " text=", h._title.text)
	get_tree().quit(0)
