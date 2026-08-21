class_name MaxwellItem
extends RigidBody2D

signal geometry_rebuilt(item: MaxwellItem)
signal state_changed(item: MaxwellItem)

var state := PropertyState.new()
var display_name := "物品"
var base_color := Color("#93a6b8")
var base_size := Vector2(58, 58)
var base_shape := "box"
var indestructible := false
var break_threshold := 650.0
var source_axis := -1
var source_value := 0
var source_period := 0.8
var source_clock := 0.0
var is_functional := false
var trap_eligible := false
var rack_latched := false
var linked_light: MaxwellItem
var linked_parts: Array[MaxwellItem] = []
var merged_volume := 1.0
var fluid_particle := false
var liquid_group_id := -1
var deformable_liquid := false
var liquid_cell_size := 10.0
var liquid_cells: Dictionary = {}
var grabbed_by: Node2D
var _visual_size := Vector2.ZERO
var _last_geometry_signature := ""
var _label: Label
var _show_label := true
var _liquid_step_clock := 0.0
var _liquid_step_parity := false
var _liquid_local_bounds := Rect2()


func configure(config: Dictionary) -> MaxwellItem:
	display_name = config.get("name", "物品")
	state = PropertyState.new(config.get("kind", "generic"), config.get("axes", [0, 0, 0, 0, 0]))
	state.base_can_be_liquid = config.get("can_be_liquid", false)
	state.phase = config.get("phase", "liquid" if state.base_can_be_liquid else "solid")
	state.structure = config.get("structure", "intact")
	base_color = config.get("color", Color("#93a6b8"))
	base_size = config.get("size", Vector2(58, 58))
	base_shape = config.get("shape", "box")
	indestructible = config.get("indestructible", false)
	break_threshold = config.get("break_threshold", 650.0)
	is_functional = config.get("functional", false)
	trap_eligible = config.get("trap_eligible", false)
	rack_latched = config.get("latched", false)
	source_axis = config.get("source_axis", -1)
	source_value = config.get("source_value", 0)
	source_period = config.get("source_period", 0.8)
	merged_volume = config.get("volume", 1.0)
	fluid_particle = config.get("fluid_particle", false)
	liquid_group_id = config.get("liquid_group_id", -1)
	deformable_liquid = config.get("deformable_liquid", false)
	liquid_cell_size = config.get("liquid_cell_size", 10.0)
	_show_label = config.get("show_label", true)
	freeze = config.get("static", false) or rack_latched
	if deformable_liquid:
		freeze = true
	lock_rotation = config.get("lock_rotation", false)
	contact_monitor = true
	max_contacts_reported = 12
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var contact_only := bool(config.get("contact_only", false))
	collision_layer = 8 if contact_only else 4
	# Sensor-like process objects participate through directly_touches()/bounds,
	# but must never add an invisible physical lip to the terrain or block cargo.
	collision_mask = 0 if contact_only else 7
	add_to_group("maxwell_items")
	_ensure_label()
	apply_state(true)
	return self


func _ready() -> void:
	_ensure_label()
	apply_state(true)


func _physics_process(delta: float) -> void:
	if deformable_liquid and state.phase == "liquid" and not state.frozen and not liquid_cells.is_empty():
		_liquid_step_clock += delta
		var step_period := 0.12 if state.get_axis(PropertyState.Axis.DEFORMATION) == -1 else 0.045
		if _liquid_step_clock >= step_period:
			_liquid_step_clock = 0.0
			_step_deformable_liquid()
	if source_axis >= 0 and state.function_enabled:
		source_clock += delta
		if source_clock >= source_period:
			source_clock = 0.0
			if state.get_axis(source_axis) != source_value:
				state.values[source_axis] = source_value
				apply_state()
	if grabbed_by != null and is_instance_valid(grabbed_by):
		var hand_target := grabbed_by.global_position + Vector2(42.0 * grabbed_by.get("facing"), -10.0)
		var delta_to_hand := hand_target - global_position
		# A resin tool may be towing a second rigid body through a real pin joint, so
		# it needs visible tether slack.  Ordinary single objects keep the stricter
		# anti-clipping limit; neither case bypasses collisions or teleports.
		var towing_chain := state.base_kind == "resin"
		# A held resin tool is lifted and actively pulled by the demon; its surface
		# remains a collider but should not behave as if it were pressed flat and
		# abandoned on the floor. Dropping it reapplies the full sticky material.
		if towing_chain and physics_material_override != null:
			physics_material_override.friction = 0.08
		var carry_slack := 340.0 if towing_chain else 110.0
		if delta_to_hand.length() > carry_slack:
			if grabbed_by.has_method("force_drop"):
				grabbed_by.call("force_drop", "物品被地形卡住，妖怪松手了。")
			return
		var holder_velocity: Vector2 = grabbed_by.get("velocity")
		var follow_gain := 22.0 if towing_chain else 14.0
		var follow_speed := 1200.0 if towing_chain else 900.0
		var follow_acceleration := 9000.0 if towing_chain else 4800.0
		var desired_velocity := (holder_velocity + delta_to_hand * follow_gain).limit_length(follow_speed)
		linear_velocity = linear_velocity.move_toward(desired_velocity, follow_acceleration * delta)
		angular_velocity = move_toward(angular_velocity, 0.0, (30.0 if towing_chain else 18.0) * delta)


func _ensure_label() -> void:
	if _label != null and is_instance_valid(_label):
		return
	_label = Label.new()
	_label.name = "ItemLabel"
	_label.text = display_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("#e9f2f4"))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.visible = _show_label
	add_child(_label)


func apply_state(force_geometry := false, run_intrinsic := true) -> void:
	if run_intrinsic:
		ContactRules.resolve_intrinsic(state)
	var geometry_signature := "%s|%s|%s|%s|%.2f" % [
		state.phase,
		state.structure,
		str(state.frozen),
		str(state.get_axis(PropertyState.Axis.DEFORMATION)),
		merged_volume + (0.01 if fluid_particle else 0.0),
	]
	if force_geometry or geometry_signature != _last_geometry_signature:
		_rebuild_geometry()
		_last_geometry_signature = geometry_signature
	_apply_physics_material()
	if _label != null:
		_label.text = display_name
		_label.position = Vector2(-65, -_visual_size.y * 0.5 - 24)
		_label.size = Vector2(130, 22)
	queue_redraw()
	state_changed.emit(self)


func _rebuild_geometry() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			remove_child(child)
			child.free()
	if deformable_liquid and not liquid_cells.is_empty():
		_rebuild_liquid_sheet_geometry()
		geometry_rebuilt.emit(self)
		return

	_visual_size = base_size * sqrt(merged_volume)
	if state.phase == "liquid" and not state.frozen:
		if fluid_particle:
			_visual_size = base_size
		else:
			_visual_size = Vector2(base_size.x * 1.5 * sqrt(merged_volume), maxf(24.0, base_size.y * 0.58))
	elif state.structure == "broken":
		_visual_size *= Vector2(0.67, 0.56)
	elif state.get_axis(PropertyState.Axis.DEFORMATION) == -1:
		_visual_size *= Vector2(1.42, 0.58)
	elif state.get_axis(PropertyState.Axis.DEFORMATION) == 1:
		_visual_size *= Vector2(0.92, 1.18)

	if state.structure == "breached" and state.base_kind == "wood_wall":
		var segment_height := maxf(22.0, (_visual_size.y - 82.0) * 0.5)
		_add_box_shape(Vector2(_visual_size.x, segment_height), Vector2(0, -(_visual_size.y - segment_height) * 0.5))
		_add_box_shape(Vector2(_visual_size.x, segment_height), Vector2(0, (_visual_size.y - segment_height) * 0.5))
	else:
		var collision := CollisionShape2D.new()
		collision.name = "PhysicalShape"
		if state.phase == "liquid" and not state.frozen:
			if fluid_particle:
				var liquid_circle := CircleShape2D.new()
				liquid_circle.radius = minf(_visual_size.x, _visual_size.y) * 0.5
				collision.shape = liquid_circle
			else:
				var capsule := CapsuleShape2D.new()
				capsule.radius = _visual_size.y * 0.5
				capsule.height = _visual_size.x
				collision.shape = capsule
				collision.rotation = PI * 0.5
		elif (state.get_axis(PropertyState.Axis.DEFORMATION) == 1 and state.base_kind != "elastic_pad") or base_shape == "circle":
			var circle := CircleShape2D.new()
			circle.radius = minf(_visual_size.x, _visual_size.y) * 0.5
			collision.shape = circle
		else:
			var rectangle := RectangleShape2D.new()
			rectangle.size = _visual_size
			collision.shape = rectangle
		add_child(collision)
	geometry_rebuilt.emit(self)


func _add_box_shape(size: Vector2, offset: Vector2) -> void:
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	collision.position = offset
	add_child(collision)


func _apply_physics_material() -> void:
	if deformable_liquid:
		freeze = true
		collision_layer = 8 if state.phase == "liquid" and not state.frozen else 4
		collision_mask = 0 if state.phase == "liquid" and not state.frozen else 7
		return
	var material := PhysicsMaterial.new()
	var raw_weight := state.get_axis(PropertyState.Axis.WEIGHT)
	var effective := effective_weight()
	if effective == -1:
		mass = 0.7
		gravity_scale = -0.34
	elif effective == 1:
		mass = 28.0
		gravity_scale = 1.0
	else:
		mass = 2.4
		gravity_scale = 1.0
	if state.phase == "liquid" and not state.frozen:
		lock_rotation = true
		if effective == 0:
			mass = 0.42 if fluid_particle else maxf(0.8, merged_volume * 1.2)
		material.friction = 0.015
		material.bounce = 0.0
		linear_damp = 1.15
	elif state.get_axis(PropertyState.Axis.DEFORMATION) == -1:
		material.friction = 1.0
		material.bounce = 0.0
		linear_damp = 3.5
	elif state.get_axis(PropertyState.Axis.DEFORMATION) == 1:
		material.friction = 0.3
		material.bounce = 1.12
		linear_damp = 0.2
	else:
		material.friction = 0.62
		material.bounce = 0.06
		linear_damp = 0.6 if raw_weight != -1 else 0.15
	physics_material_override = material


func effective_weight() -> int:
	if state.get_axis(PropertyState.Axis.WEIGHT) == 1 and linked_light != null and is_instance_valid(linked_light):
		if linked_light.state.get_axis(PropertyState.Axis.WEIGHT) == -1:
			return 0
	return state.get_axis(PropertyState.Axis.WEIGHT)


func can_be_grabbed() -> bool:
	return (effective_weight() != 1
		and (not freeze or rack_latched)
		and not state.burning
		and not state.frozen
		and state.get_axis(PropertyState.Axis.TEMPERATURE) == 0)


func release_rack_latch() -> void:
	if not rack_latched:
		return
	rack_latched = false
	freeze = false


func directly_touches(other: MaxwellItem, tolerance := 7.0) -> bool:
	if other == self or not is_instance_valid(other):
		return false
	if deformable_liquid:
		for cell: Vector2i in liquid_cells.keys():
			var center := global_position + Vector2(cell) * liquid_cell_size
			var cell_rect := Rect2(center - Vector2.ONE * liquid_cell_size * 0.5, Vector2.ONE * liquid_cell_size).grow(tolerance)
			if other.deformable_liquid:
				for other_cell: Vector2i in other.liquid_cells.keys():
					var other_center := other.global_position + Vector2(other_cell) * other.liquid_cell_size
					if cell_rect.has_point(other_center):
						return true
			elif cell_rect.intersects(other.world_bounds()):
				return true
		return false
	if other.deformable_liquid:
		return other.directly_touches(self, tolerance)
	for body in get_colliding_bodies():
		if body == other:
			return true
	return world_bounds().grow(tolerance).intersects(other.world_bounds().grow(tolerance))


func world_bounds() -> Rect2:
	if deformable_liquid and not liquid_cells.is_empty():
		return Rect2(global_position + _liquid_local_bounds.position, _liquid_local_bounds.size)
	return Rect2(global_position - _visual_size * 0.5, _visual_size)


func break_item() -> bool:
	if indestructible or state.structure == "broken":
		return false
	state.structure = "broken"
	state.function_enabled = false
	# A broken drain plug represents one surviving shard, not a shortened door.
	# It keeps the same material state and collision, but must no longer span the
	# outlet it used to seal.
	if state.base_kind == "glass_gate":
		base_size = Vector2(base_size.x, minf(base_size.y, 40.0))
	apply_state(true)
	return true


func breach() -> bool:
	if indestructible or state.base_kind != "wood_wall":
		return false
	state.structure = "breached"
	state.function_enabled = false
	apply_state(true)
	return true


func thaw() -> void:
	state.frozen = false
	if state.base_can_be_liquid:
		state.phase = "liquid"
	# 若调用者没有先消掉“冷 + 可冻结”，内禀规则会立即重新结冰。
	apply_state(true, true)


func collision_signature() -> String:
	var signatures: Array[String] = []
	for child in get_children():
		if child is CollisionShape2D:
			var shape_info: String = child.shape.get_class()
			if child.shape is RectangleShape2D:
				shape_info += ":" + str((child.shape as RectangleShape2D).size.round())
			elif child.shape is CircleShape2D:
				shape_info += ":" + str(snappedf((child.shape as CircleShape2D).radius, 0.01))
			signatures.append("%s@%s" % [shape_info, str(child.position.round())])
	return ";".join(signatures)


func point_is_solid_local(point: Vector2) -> bool:
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var rect := Rect2(child.position - (child.shape as RectangleShape2D).size * 0.5, (child.shape as RectangleShape2D).size)
			if rect.has_point(point):
				return true
		elif child is CollisionShape2D and child.shape is CircleShape2D:
			if point.distance_to(child.position) <= (child.shape as CircleShape2D).radius:
				return true
	return false


func _draw() -> void:
	var color := _state_color()
	if deformable_liquid:
		_draw_liquid_sheet(color)
	elif state.phase == "liquid" and not state.frozen:
		_draw_liquid(color)
	elif state.structure == "breached" and state.base_kind == "wood_wall":
		var segment_height := maxf(22.0, (_visual_size.y - 82.0) * 0.5)
		draw_rect(Rect2(Vector2(-_visual_size.x * 0.5, -_visual_size.y * 0.5), Vector2(_visual_size.x, segment_height)), color, true)
		draw_rect(Rect2(Vector2(-_visual_size.x * 0.5, _visual_size.y * 0.5 - segment_height), Vector2(_visual_size.x, segment_height)), color, true)
	else:
		var rect := Rect2(-_visual_size * 0.5, _visual_size)
		if (state.get_axis(PropertyState.Axis.DEFORMATION) == 1 and state.base_kind != "elastic_pad") or base_shape == "circle":
			draw_circle(Vector2.ZERO, minf(_visual_size.x, _visual_size.y) * 0.5, color)
		else:
			draw_rect(rect, color, true)
			draw_rect(rect, color.lightened(0.28), false, 2.0)
	if state.burning and not deformable_liquid:
		for i in range(4):
			var x := -_visual_size.x * 0.35 + i * _visual_size.x * 0.23
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 8, -_visual_size.y * 0.5), Vector2(x, -_visual_size.y * 0.5 - 25 - (i % 2) * 8), Vector2(x + 9, -_visual_size.y * 0.5)
			]), Color("#ff7a24"))
	if state.frozen and not deformable_liquid:
		draw_rect(Rect2(-_visual_size * 0.5 - Vector2(3, 3), _visual_size + Vector2(6, 6)), Color(0.52, 0.88, 1.0, 0.34), true)
		draw_line(Vector2(-_visual_size.x * 0.35, 0), Vector2(_visual_size.x * 0.3, -_visual_size.y * 0.3), Color("#d8fbff"), 2)
	if state.get_axis(PropertyState.Axis.WEIGHT) == -1:
		draw_line(Vector2(-10, _visual_size.y * 0.5 + 5), Vector2(-16, _visual_size.y * 0.5 + 16), Color("#c7f6ff"), 2)
		draw_line(Vector2(10, _visual_size.y * 0.5 + 5), Vector2(16, _visual_size.y * 0.5 + 16), Color("#c7f6ff"), 2)


func _draw_liquid(color: Color) -> void:
	var body_color := color
	body_color.a = 0.88
	if fluid_particle:
		draw_circle(Vector2.ZERO, minf(_visual_size.x, _visual_size.y) * 0.5, body_color)
	else:
		var radius := _visual_size.y * 0.5
		draw_rect(Rect2(Vector2(-_visual_size.x * 0.5 + radius, -radius), Vector2(_visual_size.x - radius * 2.0, radius * 2.0)), body_color, true)
		draw_circle(Vector2(-_visual_size.x * 0.5 + radius, 0), radius, body_color)
		draw_circle(Vector2(_visual_size.x * 0.5 - radius, 0), radius, body_color)


func seed_liquid_rect(columns: int, rows: int) -> void:
	liquid_cells.clear()
	for row in range(rows):
		for column in range(columns):
			var x := column - columns / 2
			var y := row - rows / 2
			liquid_cells[Vector2i(x, y)] = true
	_rebuild_liquid_sheet_geometry()
	queue_redraw()


func absorb_liquid_sheet(other: MaxwellItem) -> void:
	if not deformable_liquid or not other.deformable_liquid:
		return
	for other_cell: Vector2i in other.liquid_cells.keys():
		var world_center := other.global_position + Vector2(other_cell) * other.liquid_cell_size
		var local_cell := Vector2i((world_center - global_position) / liquid_cell_size)
		liquid_cells[local_cell] = true
	_rebuild_liquid_sheet_geometry()
	queue_redraw()


func set_liquid_cells(cells: Array) -> void:
	liquid_cells.clear()
	for cell in cells:
		liquid_cells[Vector2i(cell)] = true
	_rebuild_liquid_sheet_geometry()
	queue_redraw()


func liquid_components() -> Array:
	var components: Array = []
	var remaining := liquid_cells.duplicate()
	var neighbors: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
	]
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		var queue: Array[Vector2i] = [start]
		var component: Array[Vector2i] = []
		remaining.erase(start)
		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			component.append(current)
			for offset: Vector2i in neighbors:
				var candidate: Vector2i = current + offset
				if remaining.has(candidate):
					remaining.erase(candidate)
					queue.append(candidate)
		components.append(component)
	return components


func _step_deformable_liquid() -> void:
	if not is_inside_tree():
		return
	var gravity_direction := -1 if state.get_axis(PropertyState.Axis.WEIGHT) == -1 else 1
	var ordered: Array[Vector2i] = []
	for cell: Vector2i in liquid_cells.keys():
		ordered.append(cell)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i): return a.y > b.y if gravity_direction > 0 else a.y < b.y)
	_liquid_step_parity = not _liquid_step_parity
	var moved := false
	for cell in ordered:
		if not liquid_cells.has(cell):
			continue
		var vertical := Vector2i(0, gravity_direction)
		var first_side := -1 if _liquid_step_parity else 1
		var candidates := [
			cell + vertical,
			cell + Vector2i(first_side, gravity_direction),
			cell + Vector2i(-first_side, gravity_direction),
			cell + Vector2i(first_side, 0),
			cell + Vector2i(-first_side, 0),
		]
		for candidate: Vector2i in candidates:
			if _liquid_cell_blocked(candidate):
				continue
			liquid_cells.erase(cell)
			liquid_cells[candidate] = true
			moved = true
			break
	if moved:
		_rebuild_liquid_sheet_geometry()
		queue_redraw()


func _liquid_cell_blocked(cell: Vector2i) -> bool:
	if liquid_cells.has(cell):
		return true
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position + Vector2(cell) * liquid_cell_size
	query.collision_mask = 1 | 4
	query.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_point(query, 8).is_empty()


func _rebuild_liquid_sheet_geometry() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			remove_child(child)
			child.free()
	if liquid_cells.is_empty():
		_liquid_local_bounds = Rect2()
		_visual_size = Vector2.ZERO
		return
	var rows: Dictionary = {}
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483648, -2147483648)
	for cell: Vector2i in liquid_cells.keys():
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
		if not rows.has(cell.y):
			rows[cell.y] = []
		rows[cell.y].append(cell.x)
	for y: int in rows.keys():
		var xs: Array = rows[y]
		xs.sort()
		var run_start: int = xs[0]
		var previous: int = xs[0]
		for index in range(1, xs.size() + 1):
			var closes_run := index == xs.size() or int(xs[index]) != previous + 1
			if closes_run:
				var run_end := previous
				var collision := CollisionShape2D.new()
				var rectangle := RectangleShape2D.new()
				rectangle.size = Vector2((run_end - run_start + 1) * liquid_cell_size, liquid_cell_size)
				collision.shape = rectangle
				collision.position = Vector2((run_start + run_end) * 0.5 * liquid_cell_size, y * liquid_cell_size)
				add_child(collision)
				if index < xs.size():
					run_start = int(xs[index])
					previous = int(xs[index])
			else:
				previous = int(xs[index])
	_liquid_local_bounds = Rect2(
		Vector2(min_cell) * liquid_cell_size - Vector2.ONE * liquid_cell_size * 0.5,
		Vector2(max_cell - min_cell + Vector2i.ONE) * liquid_cell_size
	)
	_visual_size = _liquid_local_bounds.size


func _draw_liquid_sheet(color: Color) -> void:
	var body_color := color
	body_color.a = 0.9
	for cell: Vector2i in liquid_cells.keys():
		var center := Vector2(cell) * liquid_cell_size
		draw_rect(Rect2(center - Vector2.ONE * liquid_cell_size * 0.51, Vector2.ONE * liquid_cell_size * 1.02), body_color, true)
		if state.frozen:
			draw_rect(Rect2(center - Vector2.ONE * liquid_cell_size * 0.51, Vector2.ONE * liquid_cell_size * 1.02), Color(0.52, 0.88, 1.0, 0.34), true)
	if state.burning:
		_draw_liquid_fire()


func _draw_liquid_fire() -> void:
	var surface_cells: Array[Vector2i] = []
	for cell: Vector2i in liquid_cells.keys():
		if not liquid_cells.has(cell + Vector2i.UP):
			surface_cells.append(cell)
	surface_cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x)
	for index in range(surface_cells.size()):
		# A flame every few cells reads as one burning liquid surface without
		# turning a large puddle into an opaque orange block.
		if index % 3 != 0 and index != surface_cells.size() - 1:
			continue
		var center := Vector2(surface_cells[index]) * liquid_cell_size
		var edge_y := center.y - liquid_cell_size * 0.5
		var flame_height := 11.0 + float(index % 2) * 4.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(center.x - 4.5, edge_y),
			Vector2(center.x, edge_y - flame_height),
			Vector2(center.x + 4.5, edge_y),
		]), Color("#ff7a24"))


func _state_color() -> Color:
	var color := base_color
	if state.get_axis(PropertyState.Axis.TEMPERATURE) == 1:
		color = color.lerp(Color("#ff783b"), 0.56)
	elif state.get_axis(PropertyState.Axis.TEMPERATURE) == -1:
		color = color.lerp(Color("#58c9ee"), 0.58)
	if state.get_axis(PropertyState.Axis.COMBUSTIBILITY) == -1:
		color = color.lerp(Color("#daf2ed"), 0.3)
	if state.get_axis(PropertyState.Axis.DEFORMATION) == -1:
		color = color.lerp(Color("#c056d8"), 0.35)
	elif state.get_axis(PropertyState.Axis.DEFORMATION) == 1:
		color = color.lerp(Color("#e4f55c"), 0.28)
	return color
