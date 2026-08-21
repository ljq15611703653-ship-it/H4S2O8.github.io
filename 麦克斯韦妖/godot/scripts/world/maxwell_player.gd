class_name MaxwellPlayer
extends CharacterBody2D

var speed := 300.0
var jump_speed := 560.0
var facing := 1.0
var held_item: MaxwellItem
var world: Node
var _sprite: Sprite2D


func configure(game_world: Node) -> MaxwellPlayer:
	world = game_world
	name = "MaxwellDemon"
	collision_layer = 2
	collision_mask = 5
	var collision := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 22.0
	capsule.height = 72.0
	collision.shape = capsule
	collision.position = Vector2(0, 2)
	add_child(collision)
	_sprite = Sprite2D.new()
	_sprite.name = "DemonArt"
	_sprite.texture = load("res://assets/art/maxwell_demon.png")
	_sprite.scale = Vector2(0.078, 0.078)
	_sprite.position = Vector2(0, -5)
	add_child(_sprite)
	return self


func _physics_process(delta: float) -> void:
	if world == null:
		return
	if held_item != null and is_instance_valid(held_item) and not held_item.can_be_grabbed():
		world.set_status("手中物变成了重、冷、烫、燃烧或结冰状态，妖怪被迫松手。")
		drop_item()
	if not is_on_floor():
		velocity.y += 1300.0 * delta
	var direction := Input.get_axis("move_left", "move_right")
	var movement_speed := speed
	if held_item != null and is_instance_valid(held_item) and held_item.state.base_kind == "resin" and not held_item.linked_parts.is_empty():
		movement_speed = 180.0
		var hand_target := global_position + Vector2(42.0 * facing, -10.0)
		var tether_delta := held_item.global_position - hand_target
		# At full extension the demon cannot keep walking away from the physical
		# assembly.  Holding the same direction resumes automatically as the pulled
		# bodies catch up, giving load feedback without teleportation.
		if tether_delta.length() > 270.0 and absf(direction) > 0.01 and signf(direction) != signf(tether_delta.x):
			direction = 0.0
	if absf(direction) > 0.01:
		facing = signf(direction)
		velocity.x = move_toward(velocity.x, direction * movement_speed, 1500.0 * delta)
		if _sprite != null:
			_sprite.flip_h = facing < 0
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1900.0 * delta)
	# Rigid items can form a tiny corner on a slope where the capsule is visibly
	# supported but CharacterBody2D does not report is_on_floor for that frame.
	# A short downward body probe keeps those recoverable contacts jumpable while
	# remaining far too short to permit an air jump.
	var has_jump_support := is_on_floor() or test_move(global_transform, Vector2(0, 8))
	if Input.is_action_just_pressed("jump") and has_jump_support:
		velocity.y = -jump_speed
	if held_item != null and is_instance_valid(held_item) and held_item.state.get_axis(PropertyState.Axis.WEIGHT) == -1:
		velocity.y -= 520.0 * delta
	move_and_slide()
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var body := collision.get_collider()
		if body is MaxwellItem and body.state.get_axis(PropertyState.Axis.DEFORMATION) == 1 and collision.get_normal().y < -0.55:
			velocity.y = -720.0
	if global_position.y > 900:
		world.reset_demo()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("grab"):
		_toggle_grab()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_tool"):
		world.try_use_tool(self)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("codex"):
		world.toggle_codex()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_level"):
		world.reset_demo()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var axis := _axis_for_key(event.physical_keycode)
		if axis >= 0:
			var polarity := -1 if event.ctrl_pressed else 1
			world.try_player_transfer(self, axis, polarity, event.shift_pressed)
			get_viewport().set_input_as_handled()


func _axis_for_key(keycode: int) -> int:
	match keycode:
		KEY_1: return PropertyState.Axis.TEMPERATURE
		KEY_2: return PropertyState.Axis.COMBUSTIBILITY
		KEY_3: return PropertyState.Axis.FREEZABILITY
		KEY_4: return PropertyState.Axis.WEIGHT
		KEY_5: return PropertyState.Axis.DEFORMATION
	return -1


func _toggle_grab() -> void:
	if held_item != null and is_instance_valid(held_item):
		drop_item()
		world.set_status("放下了物品")
		return
	var candidate: MaxwellItem = world.nearest_item(global_position, 86.0)
	if candidate == null:
		world.set_status("手边没有物品")
		return
	if not candidate.can_be_grabbed():
		world.set_status("这件东西现在拿不动或不能直接碰")
		return
	candidate.release_rack_latch()
	var horizontal_offset := candidate.global_position.x - global_position.x
	if absf(horizontal_offset) > 1.0:
		facing = signf(horizontal_offset)
		if _sprite != null:
			_sprite.flip_h = facing < 0
	held_item = candidate
	held_item.grabbed_by = self
	held_item.add_collision_exception_with(self)
	add_collision_exception_with(held_item)
	for linked_part in held_item.linked_parts:
		if is_instance_valid(linked_part):
			linked_part.add_collision_exception_with(self)
			add_collision_exception_with(linked_part)
	world.set_status("抓住：%s。物品仍有碰撞和重量" % held_item.display_name)


func drop_item() -> void:
	if held_item != null and is_instance_valid(held_item):
		for linked_part in held_item.linked_parts:
			if is_instance_valid(linked_part):
				linked_part.remove_collision_exception_with(self)
				remove_collision_exception_with(linked_part)
		held_item.remove_collision_exception_with(self)
		remove_collision_exception_with(held_item)
		held_item.grabbed_by = null
		held_item.apply_state(false, false)
		held_item = null


func force_drop(reason: String) -> void:
	drop_item()
	if world != null:
		world.set_status(reason)
