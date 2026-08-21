class_name DemoWorld
extends Node2D

const WORLD_SIZE := Vector2(2440, 720)
const DOOR_ZONE := Rect2(2010, 108, 168, 160)
# Includes the real contact envelope of a 58 px receiver against the 96 px
# blocker. The receiver is then ejected left into the visible shelf; elsewhere
# in the door zone the same heavy conversion still triggers the sink trap.
const SIDE_POCKET := Rect2(1860, 165, 170, 125)
const ICE_SUPPORT_ZONE := Rect2(1800, 190, 150, 130)

var player: MaxwellPlayer
var hud: DemoHud
var items: Array[MaxwellItem] = []
var blocker: MaxwellItem
var receiver: MaxwellItem
var wood_support: MaxwellItem
var glass_gate: MaxwellItem
var hinge_floor: TerrainPiece
var door_barrier: TerrainPiece
var light_cage_exit: TerrainPiece
var _burn_time := 0.0
var _floor_tilted := false
var _door_open := false
var _won := false
var _pair_clock := 0.0
var _merge_clock := 0.0
var _next_liquid_group_id := 1
var _resin_payload: Dictionary = {}
var _joints: Array[Joint2D] = []
# A manual transfer is Maxwell's separating gate: the two participants do not
# immediately undo the operation while they are still in the same contact.
# Normal contact reactions resume after they physically separate once.
var _insulated_transfer_pairs: Dictionary = {}


func _ready() -> void:
	_build_level()
	hud = DemoHud.new().configure()
	add_child(hud)
	set_status("目标：清空高处门前的重物，再让妖怪进入门内。没有固定路线。")
	queue_redraw()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_pair_clock += delta
	_merge_clock += delta
	if _pair_clock >= 0.08:
		_pair_clock = 0.0
		_resolve_all_contacts()
	if _merge_clock >= 0.22:
		_merge_clock = 0.0
		_merge_identical_liquids()
		_split_disconnected_liquids()
	_update_process_geometry(delta)
	_update_trap()
	_update_door()
	var touching := contact_target_for(player.held_item) if player.held_item != null else nearest_item(player.global_position, 82.0)
	hud.set_context(player, touching)
	if _door_open and not _won and player.global_position.x > 2195.0 and player.global_position.y < 285.0:
		_won = true
		player.drop_item()
		hud.show_win()
		set_status("实验完成：最终状态满足，出口接受了这条路线。")
		if OS.has_feature("web"):
			JavaScriptBridge.eval("document.title='麦克斯韦妖的燃烧水 — 实验完成';")


func _build_level() -> void:
	# 低层实验室与渐进的人通道。
	_add_terrain(Vector2(600, 690), Vector2(1200, 60), Color("#253646"), "低层实验室")
	_add_terrain(Vector2(1770, 690), Vector2(1140, 60), Color("#253646"), "")
	_add_terrain(Vector2(470, 560), Vector2(210, 24), Color("#30495a"), "弹跳实验台", true)
	_add_terrain(Vector2(730, 470), Vector2(230, 24), Color("#30495a"), "人通道", true)
	# A forgiving intermediate step keeps the resin route about material handling,
	# rather than asking the player to balance on the bathtub's narrow rim.
	_add_terrain(Vector2(900, 425), Vector2(180, 24), Color("#30495a"), "登高踏板", true)
	_add_terrain(Vector2(1010, 385), Vector2(230, 24), Color("#30495a"), "", true)
	# 下方开口的捕轻笼：不改变“轻会向上飘”，只用真实地形防止关键物飞出关卡。
	_add_terrain(Vector2(1000, 205), Vector2(220, 22), Color("#5d7180"), "捕轻笼")
	# Short physical latches keep a loose shell from being knocked sideways.  The
	# right latch opens only after resin has fixed the shell to a controllable
	# object; no body is teleported and the linked pair must still be dragged out.
	_add_terrain(Vector2(900, 225), Vector2(20, 40), Color("#5d7180"), "")
	light_cage_exit = _add_terrain(Vector2(1100, 225), Vector2(20, 40), Color("#5d7180"), "笼闩")
	_add_terrain(Vector2(1280, 330), Vector2(260, 24), Color("#30495a"), "", true)
	_add_terrain(Vector2(1555, 300), Vector2(310, 24), Color("#30495a"), "货物汇合处", true)
	# A raised side rack isolates the ordinary receiver from the resin/light cargo
	# chain below. The demon can jump up and lift it, while dragged assemblies pass
	# underneath without sweeping it into the final gate.
	_add_terrain(Vector2(1500, 225), Vector2(180, 22), Color("#425361"), "接收块架", true)
	# The membrane is held by its own rack latch; a second one-way collider here
	# would create an underside seam that catches cargo travelling below.
	_add_world_label(Vector2(1692, 82), "水膜挂架", Color("#6f8796"))
	# Loose experiment materials live on a shelf adjoining the spring landing.
	# Reaching it still requires the elastic pad, but no cargo chain can sweep the
	# materials into the gate puzzle and the route is not pixel-perfect platforming.
	_add_terrain(Vector2(680, 560), Vector2(210, 24), Color("#425361"), "材料台", true)
	# Transfer samples have their own one-way shelf on the far left. They remain
	# freely movable, but no longer turn the upper carrying route into a random
	# pile of colliders.
	_add_terrain(Vector2(300, 490), Vector2(300, 24), Color("#425361"), "物性样品台", true)
	# A continuous one-way handoff lets a multi-body resin chain leave the catch
	# platform without requiring every linked body to reproduce a character jump.
	# The underside remains open for the lower-route traversal.
	var catch_handoff := _add_terrain(Vector2(1135, 348), Vector2(180, 22), Color("#425361"), "", true)
	catch_handoff.rotation = -0.32
	# The primary upper cargo route is one continuous physical surface.  Linked
	# rigid bodies can therefore be transported without reproducing a sequence of
	# character-only jumps, while the open underside preserves the lower routes.
	var upper_cargo_route := _add_terrain(Vector2(1500, 335), Vector2(820, 22), Color("#425361"), "上层货道", true)
	upper_cargo_route.rotation = -0.12

	# 货物通道是连续斜坡，玩家能跳过去，但被携带物必须真的沿地形移动。
	# The first ramp is sunk into the floor beneath the bath.  This keeps a real
	# 106 px passage below the bath wall so a 72 px player carrying a tool can
	# reach the outside of the drain plug without clipping through geometry.
	var ramp_a := _add_terrain(Vector2(860, 670), Vector2(360, 24), Color("#425361"), "货物通道")
	ramp_a.rotation = -0.15
	# The drain ramp must be reachable from the lower floor; otherwise the water
	# can flow correctly while no carried object can ever touch it.
	var ramp_b := _add_terrain(Vector2(1210, 620), Vector2(380, 24), Color("#425361"), "")
	ramp_b.rotation = -0.15
	# Physical relay between the two cargo ramps. Without it the 150 px rise is
	# beyond both the demon's jump and any ordinary carried object's trajectory.
	_add_terrain(Vector2(1390, 515), Vector2(150, 22), Color("#425361"), "", true)
	var ramp_c := _add_terrain(Vector2(1550, 415), Vector2(360, 24), Color("#425361"), "")
	ramp_c.rotation = -0.15
	# One-way from below prevents the player capsule from being pinched between
	# the lower ramp and this rising cargo surface.  Bodies approaching from above
	# still receive the same physical support and slide along the same slope.
	var ramp_d := _add_terrain(Vector2(1770, 342), Vector2(300, 24), Color("#425361"), "货运末段", true)
	ramp_d.rotation = -0.27

	# 浴缸：真实底板与左壁；右侧玻璃闸门被打碎后，流体粒子受重力泄入货运斜坡。
	_add_terrain(Vector2(940, 545), Vector2(270, 18), Color("#63808d"), "浴缸")
	_add_terrain(Vector2(810, 490), Vector2(18, 128), Color("#63808d"), "")

	# 高层出口由铰接地板承担重物；下面留有侧坑和支撑区。
	_add_terrain(Vector2(1795, 282), Vector2(250, 24), Color("#344b5a"), "侧槽", true)
	hinge_floor = _add_terrain(Vector2(2045, 267), Vector2(290, 24), Color("#53606a"), "称重门槛")
	_add_terrain(Vector2(2290, 267), Vector2(220, 24), Color("#344b5a"), "出口")
	_add_terrain(Vector2(2320, 152), Vector2(24, 220), Color("#8c785b"), "")
	_add_terrain(Vector2(2300, 52), Vector2(250, 24), Color("#8c785b"), "不可破坏门框")
	door_barrier = _add_terrain(Vector2(2202, 174), Vector2(22, 170), Color("#b5554e"), "状态门")

	player = MaxwellPlayer.new().configure(self)
	# Start in the open handling lane.  The permanent furnace/cold cabinet stay
	# immediately to the left, while the first carried tool can move right
	# without being trapped behind an immovable tutorial prop.
	player.position = Vector2(590, 620)
	add_child(player)
	var camera := Camera2D.new()
	camera.position = Vector2(150, -40)
	camera.limit_left = 0
	camera.limit_right = int(WORLD_SIZE.x)
	camera.limit_top = 0
	camera.limit_bottom = int(WORLD_SIZE.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	player.add_child(camera)

	_spawn_items()


func _spawn_items() -> void:
	_spawn({"name": "熔炉（持续产烫）", "kind": "furnace", "axes": [1, 0, 0, 1, 0], "color": Color("#bd4d32"), "size": Vector2(84, 92), "static": true, "functional": true, "source_axis": PropertyState.Axis.TEMPERATURE, "source_value": 1}, Vector2(250, 614))
	_spawn({"name": "冷柜（持续产冷）", "kind": "cold_source", "axes": [-1, 0, 0, 1, 0], "color": Color("#4b94b8"), "size": Vector2(84, 92), "static": true, "functional": true, "source_axis": PropertyState.Axis.TEMPERATURE, "source_value": -1}, Vector2(365, 614))
	_spawn({"name": "弹性垫", "kind": "elastic_pad", "axes": [0, 0, 0, 0, 1], "color": Color("#bbd94c"), "size": Vector2(88, 34), "static": true}, Vector2(500, 642))
	# Keep the ground tools far enough apart for the player to walk between them.
	# The hammer must sit beyond the spring platform's right edge (x = 575), or
	# the player is forced into a bounce loop before the bath can be opened.
	_spawn({"name": "锤子", "kind": "hammer", "axes": [0, 0, 0, 0, 0], "color": Color("#9ba5ab"), "size": Vector2(54, 28)}, Vector2(650, 630))
	# Keep later experiment materials on separate reachable shelves.  If these
	# start on the sloped floor they settle into one solid pile that blocks the
	# bath-tool tutorial before the player has made any choice.
	_spawn({"name": "引火木块", "kind": "torch", "axes": [0, 1, 0, 0, 0], "color": Color("#a76c3b"), "size": Vector2(48, 44)}, Vector2(220, 450))
	_spawn({"name": "灭火石", "kind": "extinguisher", "axes": [0, -1, 0, 0, 0], "color": Color("#d3e3dd"), "size": Vector2(52, 48)}, Vector2(300, 450))
	# The anti-freeze sample belongs to the later contact laboratory. Keeping it
	# away from the spring landing prevents a single grab radius from containing
	# several unrelated materials.
	_spawn({"name": "阻冻石", "kind": "anti_freeze", "axes": [0, 0, -1, 0, 0], "color": Color("#d8cba1"), "size": Vector2(52, 48)}, Vector2(380, 450))
	glass_gate = _spawn({"name": "浴缸玻璃塞", "kind": "glass_gate", "axes": [0, 0, 0, 0, 0], "color": Color(0.55, 0.88, 0.95, 0.75), "size": Vector2(22, 200), "static": true, "functional": true, "break_threshold": 150.0}, Vector2(1070, 520))
	_spawn_liquid_sheet({"name": "浴缸水", "kind": "water", "axes": [0, 0, 1, 0, 0], "color": Color("#3da9d4"), "can_be_liquid": true, "phase": "liquid"}, Vector2(935, 500), 24, 4)
	# An ordinary part of the drain, not a puzzle hint: burning liquid that reaches
	# it must ignite it through the same generic contact rule as every other item.
	_spawn({"name": "排水木楔", "kind": "drain_wedge", "axes": [0, 1, 0, 0, 0], "color": Color("#8e623d"), "size": Vector2(34, 26), "static": true, "contact_only": true}, Vector2(1095, 575))
	_spawn({"name": "轻壳", "kind": "light_shell", "axes": [0, 0, 0, -1, 0], "color": Color("#a7e6e8"), "size": Vector2(62, 62), "shape": "circle", "latched": true}, Vector2(1000, 330))
	# Start close to, but not touching, the caught shell.  The player must still
	# grab it and close the final horizontal gap before the manual R operation.
	_spawn({"name": "黏塑树脂", "kind": "resin", "axes": [0, 0, 0, 0, -1], "color": Color("#a94fc2"), "size": Vector2(64, 48)}, Vector2(1090, 340))
	# The ordinary receiver waits on the raised convergence shelf. The demon first
	# has to traverse the spring/cargo terrain, then begins the actual carry puzzle;
	# the receiver does not have to bulldoze through the unrelated resin setup.
	receiver = _spawn({"name": "普通接收块", "kind": "receiver", "axes": [0, 0, 0, 0, 0], "color": Color("#c8b78b"), "size": Vector2(58, 58), "trap_eligible": true, "latched": true}, Vector2(1500, 185))
	# Hang the membrane above the receiver lane. It still needs a jump to grab and
	# must be carried down to the nozzle, but no longer acts as an accidental wall
	# for every other piece of cargo travelling toward the side pocket.
	_spawn({"name": "水膜囊", "kind": "water", "axes": [0, 0, 1, 0, 0], "color": Color("#3da9d4"), "size": Vector2(54, 36), "can_be_liquid": true, "phase": "liquid", "latched": true}, Vector2(1735, 128))
	# The exposed cooling nozzle is a persistent environmental source. A freezable
	# liquid that directly touches it freezes and drops into the support zone.
	_spawn({"name": "制冷喷口", "kind": "cold_nozzle", "axes": [-1, 0, 0, 0, 0], "color": Color("#67bddd"), "size": Vector2(36, 64), "static": true, "functional": true, "source_axis": PropertyState.Axis.TEMPERATURE, "source_value": -1, "contact_only": true}, Vector2(1840, 225))
	# This is a load-bearing process object, not an extra lip above the threshold.
	# Its bounds still receive heat/fire contacts and visibly breach, while the
	# actual walkable collision is the hinge floor it supports.
	wood_support = _spawn({"name": "可燃木支撑", "kind": "wood_wall", "axes": [0, 1, 0, 0, 0], "color": Color("#8c5b35"), "size": Vector2(54, 170), "static": true, "contact_only": true}, Vector2(1930, 335))
	blocker = _spawn({"name": "门前重铁块", "kind": "door_blocker", "axes": [0, 0, 0, 1, 0], "color": Color("#5c6872"), "size": Vector2(96, 86), "indestructible": true}, Vector2(2050, 205))


func _spawn(config: Dictionary, at: Vector2) -> MaxwellItem:
	var item := MaxwellItem.new().configure(config)
	item.position = at
	add_child(item)
	items.append(item)
	return item


func _spawn_liquid_puddle(config: Dictionary, at: Vector2, unit_count: int) -> Array[MaxwellItem]:
	var result: Array[MaxwellItem] = []
	var group_id := _next_liquid_group_id
	_next_liquid_group_id += 1
	var shared_state: PropertyState
	var columns := 16
	for index in range(unit_count):
		var particle_config := config.duplicate(true)
		particle_config["size"] = Vector2(14, 14)
		particle_config["fluid_particle"] = true
		particle_config["liquid_group_id"] = group_id
		particle_config["show_label"] = false
		var column := index % columns
		var row := index / columns
		var offset := Vector2((column - (columns - 1) * 0.5) * 14.2, -float(row) * 14.2)
		var particle := _spawn(particle_config, at + offset)
		if shared_state == null:
			shared_state = particle.state
		else:
			particle.state = shared_state
			particle.apply_state(true, false)
		result.append(particle)
	_add_world_label(at + Vector2(-45, -86), config.get("name", "液体"), Color("#8ddcf2"))
	return result


func _spawn_liquid_sheet(config: Dictionary, at: Vector2, columns: int, rows: int) -> MaxwellItem:
	var liquid_config := config.duplicate(true)
	liquid_config["liquid_group_id"] = _next_liquid_group_id
	_next_liquid_group_id += 1
	liquid_config["deformable_liquid"] = true
	liquid_config["liquid_cell_size"] = 10.0
	liquid_config["static"] = true
	liquid_config["show_label"] = false
	var liquid := _spawn(liquid_config, at)
	liquid.seed_liquid_rect(columns, rows)
	_add_world_label(at + Vector2(-45, -86), config.get("name", "液体"), Color("#8ddcf2"))
	return liquid


func _add_terrain(at: Vector2, size: Vector2, color: Color, label := "", one_way := false) -> TerrainPiece:
	var piece := TerrainPiece.new().configure(size, color, label, one_way)
	piece.position = at
	add_child(piece)
	return piece


func _add_world_label(at: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	add_child(label)


func nearest_item(at: Vector2, radius: float, exclude: MaxwellItem = null) -> MaxwellItem:
	var best: MaxwellItem
	var best_distance := radius
	for item in items:
		if not is_instance_valid(item) or item == exclude:
			continue
		var distance := at.distance_to(item.global_position)
		if distance < best_distance:
			best = item
			best_distance = distance
	return best


func contact_target_for(source: MaxwellItem) -> MaxwellItem:
	if source == null or not is_instance_valid(source):
		return null
	var best: MaxwellItem
	var best_score := INF
	for item in items:
		if not is_instance_valid(item) or item == source:
			continue
		if source.directly_touches(item, 8.0):
			var score := source.global_position.distance_squared_to(item.global_position)
			# A visible liquid sheet is the most useful target when a tool overlaps
			# both the liquid and debris at an outlet. Broken debris remains a valid
			# target, but only wins when there is no intact/material target present.
			if item.deformable_liquid:
				score -= 1000000.0
			elif item.state.structure == "broken":
				score += 1000000.0
			if score < best_score:
				best = item
				best_score = score
	return best


func try_player_transfer(actor: MaxwellPlayer, axis: int, polarity: int, reverse: bool) -> void:
	if actor.held_item == null or not is_instance_valid(actor.held_item):
		set_status("先用 E 抓住一个物品；手中物必须直接碰到另一个物品。")
		return
	var held := actor.held_item
	var contact := contact_target_for(held)
	if contact == null:
		set_status("没有发生转移：两个碰撞体没有直接接触。")
		return
	var source := contact if reverse else held
	var target := held if reverse else contact
	var source_before := source.state.get_axis(axis)
	var target_before := target.state.get_axis(axis)
	var result := PropertyState.transfer(source.state, target.state, axis, polarity)
	if not result.ok:
		set_status("转移失败：" + result.reason)
		return
	_mark_insulated_transfer(source, target)
	source.apply_state(true)
	target.apply_state(true)
	_refresh_liquid_group(source)
	_refresh_liquid_group(target)
	_apply_threshold_trap(target)
	var forced_drop := actor.held_item != null and not actor.held_item.can_be_grabbed()
	if forced_drop:
		var released := actor.held_item
		var other := target if released == source else source
		var separation_direction := (released.global_position - other.global_position).normalized()
		if separation_direction.length_squared() < 0.01:
			separation_direction = Vector2(-actor.facing, -0.25).normalized()
		actor.drop_item()
		# The demon's gate completes a transfer by physically separating the
		# products.  If the released inverse object is deliberately brought back,
		# ordinary contact reactions still apply.
		var separation_impulse := 230.0
		# A receiver deliberately presented from the left-side pocket must clear
		# the door envelope after it becomes heavy.  This remains a physical eject
		# (and the same operation from the wrong side is frozen by the sink trap).
		if axis == PropertyState.Axis.WEIGHT and released.trap_eligible and SIDE_POCKET.intersects(released.world_bounds()):
			separation_impulse = 760.0
		released.apply_impulse(separation_direction * separation_impulse + Vector2(0, -90.0))
	set_status("%s → %s，转移%s单位；%s %d→%d，%s %d→%d%s" % [
		source.display_name, target.display_name, "+" if polarity == 1 else "−",
		source.display_name, source_before, source.state.get_axis(axis),
		target.display_name, target_before, target.state.get_axis(axis),
		"；手中物变为不可徒手拿取状态，立即脱手" if forced_drop else "",
	])


func try_use_tool(actor: MaxwellPlayer) -> void:
	if actor.held_item == null or not is_instance_valid(actor.held_item):
		set_status("R 只处理正在直接接触的工具组合；先抓住锤子或树脂。")
		return
	var tool := actor.held_item
	var contact := contact_target_for(tool)
	# Transfer targeting favors a liquid sheet so the player can reliably change
	# flowing water at a crowded drain. A hammer has the opposite intent: when it
	# touches both liquid and a breakable solid, the solid must receive the blow.
	if tool.state.base_kind == "hammer":
		var best_solid_distance := INF
		for candidate in items:
			if not is_instance_valid(candidate) or candidate == tool or candidate.deformable_liquid:
				continue
			if candidate.indestructible or candidate.state.structure != "intact":
				continue
			if not tool.directly_touches(candidate, 8.0):
				continue
			var candidate_distance := tool.global_position.distance_squared_to(candidate.global_position)
			if candidate == glass_gate:
				candidate_distance -= 1000000.0
			if candidate_distance < best_solid_distance:
				contact = candidate
				best_solid_distance = candidate_distance
	# Resin has a semantic first target, not merely a nearest target.  In the
	# crowded catch cage it must bind a directly touching light object instead
	# of a nearby ordinary block.  After that, the same rule selects a touching
	# heavy object for the second link.
	if tool.state.base_kind == "resin":
		var wanted_weight := 1 if _resin_payload.has(tool) else -1
		var best_resin_distance := INF
		for candidate in items:
			if not is_instance_valid(candidate) or candidate == tool:
				continue
			if candidate.state.get_axis(PropertyState.Axis.WEIGHT) != wanted_weight:
				continue
			if not tool.directly_touches(candidate, 8.0):
				continue
			var candidate_distance := tool.global_position.distance_squared_to(candidate.global_position)
			if candidate_distance < best_resin_distance:
				contact = candidate
				best_resin_distance = candidate_distance
	if contact == null:
		set_status("工具没有直接碰到目标。")
		return
	if tool.state.base_kind == "hammer":
		if contact.break_item():
			set_status("%s 被打碎：基底和物性保留，功能失效，碰撞体缩成碎片。" % contact.display_name)
			if contact == glass_gate:
				glass_gate.freeze = false
				# The broken pane remains a physical shard, but recoils into the bath
				# instead of becoming a perfect plug in the passage it just opened.
				glass_gate.apply_impulse(Vector2(-280, -150))
		else:
			set_status("这件物品绝对不可破坏，或已经破碎。")
		return
	if tool.state.base_kind == "resin":
		if not _resin_payload.has(tool):
			if contact.state.get_axis(PropertyState.Axis.WEIGHT) != -1:
				set_status("树脂第一步必须先黏住轻物。")
				return
			contact.release_rack_latch()
			_resin_payload[tool] = contact
			_create_joint(tool, contact)
			if not tool.linked_parts.has(contact):
				tool.linked_parts.append(contact)
			contact.add_collision_exception_with(actor)
			actor.add_collision_exception_with(contact)
			if light_cage_exit != null and is_instance_valid(light_cage_exit):
				light_cage_exit.queue_free()
				light_cage_exit = null
			set_status("树脂已黏住轻物，捕轻笼出口闩被拉开；继续把这条真实碰撞链拖去碰重物。")
		elif contact.state.get_axis(PropertyState.Axis.WEIGHT) == 1:
			var light: MaxwellItem = _resin_payload[tool]
			contact.linked_light = light
			contact.apply_state()
			_create_joint(tool, contact)
			if not tool.linked_parts.has(contact):
				tool.linked_parts.append(contact)
			contact.add_collision_exception_with(actor)
			actor.add_collision_exception_with(contact)
			set_status("轻物—树脂—重物链建立：重物的有效重量暂时变为普通。")
		else:
			set_status("树脂已经带着轻物；现在需要直接碰到重物。")
		return
	set_status("这对物品没有专用工具反应；普通物性仍可用数字键转移。")


func _create_joint(a: MaxwellItem, b: MaxwellItem) -> void:
	var joint := PinJoint2D.new()
	joint.global_position = (a.global_position + b.global_position) * 0.5
	add_child(joint)
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()
	joint.softness = 0.35
	_joints.append(joint)
	queue_redraw()


func _resolve_all_contacts() -> void:
	var live_items: Array[MaxwellItem] = []
	for item in items:
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			live_items.append(item)
	items = live_items
	# 每个接触步都先兑现内禀规则。阻冻/灭火只在直接接触的这一帧压过过程；
	# 分开后若仍是“冷+可冻结”或“烫+可燃”，会立刻重新进入过程。
	for item in items:
		var intrinsic_before := item.state.signature()
		ContactRules.resolve_intrinsic(item.state)
		if item.state.signature() != intrinsic_before:
			item.apply_state(true, false)
	for index in range(items.size()):
		var left := items[index]
		if left.state.burning and left.state.get_axis(PropertyState.Axis.TEMPERATURE) != 1:
			left.state.values[PropertyState.Axis.TEMPERATURE] = 1
			left.apply_state()
		for right_index in range(index + 1, items.size()):
			var right := items[right_index]
			if left.liquid_group_id >= 0 and left.liquid_group_id == right.liquid_group_id:
				continue
			var touching := left.directly_touches(right, 4.0)
			if touching and _insulated_transfer_pairs.has(_contact_pair_key(left, right)):
				continue
			if not touching:
				continue
			var before_left := left.state.signature()
			var before_right := right.state.signature()
			var events := ContactRules.resolve_pair(left.state, right.state)
			if left.state.signature() != before_left:
				left.apply_state(true, false)
				_refresh_liquid_group(left)
			if right.state.signature() != before_right:
				right.apply_state(true, false)
				_refresh_liquid_group(right)
			if not events.is_empty():
				set_status(_describe_events(left, right, events))
	_prune_insulated_transfers()


func _contact_pair_key(left: MaxwellItem, right: MaxwellItem) -> String:
	var left_scope := _contact_scope(left)
	var right_scope := _contact_scope(right)
	return "%s|%s" % [left_scope, right_scope] if left_scope < right_scope else "%s|%s" % [right_scope, left_scope]


func _contact_scope(item: MaxwellItem) -> String:
	if item.liquid_group_id >= 0:
		return "group:%d" % item.liquid_group_id
	return "item:%d" % item.get_instance_id()


func _mark_insulated_transfer(left: MaxwellItem, right: MaxwellItem) -> void:
	var left_scope := _contact_scope(left)
	var right_scope := _contact_scope(right)
	_insulated_transfer_pairs[_contact_pair_key(left, right)] = [left_scope, right_scope]


func _prune_insulated_transfers() -> void:
	for pair_key: String in _insulated_transfer_pairs.keys():
		var scopes: Array = _insulated_transfer_pairs[pair_key]
		var still_touching := false
		for left in items:
			if not is_instance_valid(left) or _contact_scope(left) != scopes[0]:
				continue
			for right in items:
				if not is_instance_valid(right) or _contact_scope(right) != scopes[1]:
					continue
				# Contact targeting itself allows an 8 px tolerance.  Requiring a
				# visibly larger gap prevents solver jitter from counting as a full
				# separation and immediately undoing the player's transfer.
				if left.directly_touches(right, 12.0):
					still_touching = true
					break
			if still_touching:
				break
		if not still_touching:
			_insulated_transfer_pairs.erase(pair_key)


func _describe_events(left: MaxwellItem, right: MaxwellItem, events: Array[String]) -> String:
	if events.any(func(event): return event.begins_with("ignite")):
		return "%s 与 %s 接触：烫 + 可燃，立即燃烧。" % [left.display_name, right.display_name]
	if events.any(func(event): return event.begins_with("freeze")):
		return "%s 与 %s 接触：冷 + 可冻结，立即结冰并更换固体碰撞体。" % [left.display_name, right.display_name]
	if events.any(func(event): return event.begins_with("extinguish")):
		return "灭火物直接接触燃烧物：火焰停止。"
	if events.any(func(event): return event.begins_with("thaw")):
		return "阻止结冰物直接接触冰体：解冻。"
	if events.has("temperature_neutralized"):
		return "冷与烫直接接触：两个温度单位归中。"
	return "发生了接触反应。"


func _merge_identical_liquids() -> void:
	for index in range(items.size()):
		if index >= items.size():
			break
		var left := items[index]
		if not is_instance_valid(left) or left.state.phase != "liquid" or left.state.frozen:
			continue
		for right_index in range(index + 1, items.size()):
			if right_index >= items.size():
				break
			var right := items[right_index]
			if not is_instance_valid(right) or right.state.phase != "liquid" or right.state.frozen:
				continue
			if left.state.liquid_merge_signature() != right.state.liquid_merge_signature():
				continue
			if left.liquid_group_id >= 0 and left.liquid_group_id == right.liquid_group_id:
				continue
			if not left.directly_touches(right, 5.0):
				continue
			if left.deformable_liquid and right.deformable_liquid:
				left.absorb_liquid_sheet(right)
				if player.held_item == right:
					player.drop_item()
				items.erase(right)
				right.queue_free()
				set_status("状态完全相同的液体重新接触并合并了。")
				return
			if left.fluid_particle or right.fluid_particle:
				_join_liquid_groups(left, right)
				set_status("状态完全相同的液体粒子团汇合了；固体不会自动合并。")
				return
			var total := left.merged_volume + right.merged_volume
			left.global_position = (left.global_position * left.merged_volume + right.global_position * right.merged_volume) / total
			left.merged_volume = total
			left.display_name = "%s（合并 %.0f 份）" % [left.state.base_kind, total]
			left.apply_state(true)
			if player.held_item == right:
				player.drop_item()
			items.erase(right)
			right.queue_free()
			set_status("只有状态完全相同的同种液体合并了；固体永不自动合并。")
			return


func _join_liquid_groups(left: MaxwellItem, right: MaxwellItem) -> void:
	var target_group := left.liquid_group_id
	if target_group < 0:
		target_group = _next_liquid_group_id
		_next_liquid_group_id += 1
		left.liquid_group_id = target_group
	var source_group := right.liquid_group_id
	for item in items:
		if not is_instance_valid(item):
			continue
		if item == right or (source_group >= 0 and item.liquid_group_id == source_group):
			item.liquid_group_id = target_group
			item.state = left.state
			item.apply_state(true, false)


func _refresh_liquid_group(changed: MaxwellItem) -> void:
	if changed == null or changed.liquid_group_id < 0:
		return
	for item in items:
		if is_instance_valid(item) and item.liquid_group_id == changed.liquid_group_id and item != changed:
			item.state = changed.state
			item.apply_state(true, false)


func _update_liquid_cohesion() -> void:
	var groups: Dictionary = {}
	for item in items:
		if not is_instance_valid(item) or not item.fluid_particle or item.state.phase != "liquid" or item.state.frozen:
			continue
		if not groups.has(item.liquid_group_id):
			groups[item.liquid_group_id] = []
		groups[item.liquid_group_id].append(item)
	for group_items: Array in groups.values():
		if group_items.size() < 2:
			continue
		var center := Vector2.ZERO
		for item: MaxwellItem in group_items:
			center += item.global_position
		center /= float(group_items.size())
		var free_radius := 42.0 + sqrt(float(group_items.size())) * 7.0
		for item: MaxwellItem in group_items:
			var toward_center := center - item.global_position
			var excess := toward_center.length() - free_radius
			if excess > 0.0:
				item.apply_central_force(toward_center.normalized() * minf(220.0, excess * 3.2))


func _split_disconnected_liquids() -> void:
	var new_liquids: Array[MaxwellItem] = []
	for liquid in items.duplicate():
		if not is_instance_valid(liquid) or not liquid.deformable_liquid or liquid.state.phase != "liquid" or liquid.state.frozen:
			continue
		var components: Array = liquid.liquid_components()
		if components.size() <= 1:
			continue
		components.sort_custom(func(a: Array, b: Array): return a.size() > b.size())
		liquid.set_liquid_cells(components[0])
		for index in range(1, components.size()):
			var split_config := {
				"name": liquid.display_name,
				"kind": liquid.state.base_kind,
				"axes": liquid.state.values.duplicate(),
				"color": liquid.base_color,
				"can_be_liquid": true,
				"phase": "liquid",
				"structure": liquid.state.structure,
				"deformable_liquid": true,
				"liquid_cell_size": liquid.liquid_cell_size,
				"liquid_group_id": liquid.liquid_group_id,
				"static": true,
				"show_label": false,
			}
			var split := MaxwellItem.new().configure(split_config)
			split.state.burning = liquid.state.burning
			split.state.frozen = false
			split.position = liquid.position
			add_child(split)
			split.set_liquid_cells(components[index])
			new_liquids.append(split)
	items.append_array(new_liquids)


func _update_process_geometry(delta: float) -> void:
	if wood_support != null and is_instance_valid(wood_support) and wood_support.state.burning and wood_support.state.structure != "breached":
		_burn_time += delta
		if _burn_time >= 1.7:
			wood_support.breach()
			_tilt_exit_floor("木支撑持续燃烧并烧穿，真实碰撞体出现缺口；门槛失去支撑。")
	for item in items:
		if not is_instance_valid(item):
			continue
		if item.state.frozen and ICE_SUPPORT_ZONE.intersects(item.world_bounds()):
			_tilt_exit_floor("液体在支撑区结冰成固体楔子，顶起门槛。")


func _tilt_exit_floor(reason: String) -> void:
	if _floor_tilted:
		return
	_floor_tilted = true
	hinge_floor.rotation = -0.22
	if blocker != null and is_instance_valid(blocker):
		blocker.apply_impulse(Vector2(-520, -30))
	set_status(reason + " 重物开始依靠重力滑向侧坑。")


func _apply_threshold_trap(changed: MaxwellItem) -> void:
	if changed.trap_eligible and changed.effective_weight() == 1 and DOOR_ZONE.intersects(changed.world_bounds()) and not SIDE_POCKET.intersects(changed.world_bounds()):
		changed.freeze = true
		changed.global_position.y = 232
		set_status("门槛下沉卡槽触发：你在门前制造了另一个重物，它仍然挡门。")


func _update_trap() -> void:
	for item in items:
		if is_instance_valid(item):
			_apply_threshold_trap(item)


func _update_door() -> void:
	var blocked := false
	for item in items:
		if is_instance_valid(item) and item.effective_weight() == 1 and DOOR_ZONE.intersects(item.world_bounds()):
			blocked = true
			break
	var should_open := not blocked
	if should_open == _door_open:
		return
	_door_open = should_open
	var collision := door_barrier.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		for child in door_barrier.get_children():
			if child is CollisionShape2D:
				collision = child
				break
	if collision != null:
		collision.set_deferred("disabled", _door_open)
	door_barrier.piece_color = Color("#4fbb86") if _door_open else Color("#b5554e")
	door_barrier.queue_redraw()
	set_status("门前已没有重物：状态门开启。" if _door_open else "门前检测到重物：状态门关闭。")


func set_status(message: String) -> void:
	if hud != null:
		hud.set_status(message)


func toggle_codex() -> void:
	if hud != null:
		hud.toggle_codex()


func reset_demo() -> void:
	get_tree().reload_current_scene()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("#0b1722"), true)
	for i in range(14):
		var color := Color(0.14, 0.31, 0.38, 0.07 + i * 0.005)
		draw_circle(Vector2(120 + i * 185, 90 + (i % 4) * 105), 115 + (i % 3) * 35, color)
	for joint in _joints:
		if is_instance_valid(joint) and not joint.node_a.is_empty() and not joint.node_b.is_empty():
			var a := get_node_or_null(joint.node_a) as Node2D
			var b := get_node_or_null(joint.node_b) as Node2D
			if a != null and b != null:
				draw_line(to_local(a.global_position), to_local(b.global_position), Color("#d16de3"), 7.0)
