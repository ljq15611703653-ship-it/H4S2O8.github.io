class_name TerrainPiece
extends AnimatableBody2D

var piece_size := Vector2(100, 20)
var piece_color := Color("#33485b")
var piece_label := ""
var _label: Label


func configure(size: Vector2, color: Color, label := "", one_way := false) -> TerrainPiece:
	piece_size = size
	piece_color = color
	piece_label = label
	collision_layer = 1
	collision_mask = 6
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape_node.shape = rectangle
	shape_node.one_way_collision = one_way
	shape_node.one_way_collision_margin = 10.0
	add_child(shape_node)
	if not label.is_empty():
		_label = Label.new()
		_label.text = label
		_label.position = Vector2(-size.x * 0.5, -size.y * 0.5 - 24)
		_label.size = Vector2(size.x, 22)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 13)
		_label.add_theme_color_override("font_color", Color("#b9ced8"))
		add_child(_label)
	queue_redraw()
	return self


func _draw() -> void:
	var rect := Rect2(-piece_size * 0.5, piece_size)
	draw_rect(rect, piece_color, true)
	draw_rect(rect, piece_color.lightened(0.2), false, 2.0)
