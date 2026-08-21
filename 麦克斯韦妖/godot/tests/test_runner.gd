extends SceneTree

var checks := 0
var failures: Array[String] = []
var group_results: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _group(name: String, before_failures: int, before_checks: int) -> void:
	group_results[name] = {
		"ok": failures.size() == before_failures,
		"checks": checks - before_checks,
	}


func _run() -> void:
	print("MAXWELL_TEST_BEGIN")
	_test_neutral_extraction_and_transfer_boundaries()
	_test_contact_reactions()
	_test_full_pair_matrix()
	_test_real_collision_geometry()
	_test_phase_structure_identity()
	_test_light_link_and_sources()
	_test_emergent_material_combinations()
	_test_grab_safety()
	_test_routes_and_threshold()
	await _test_physics_server_gap()
	await _test_physical_routes()
	await _test_scene_integration()
	var report := {
		"ok": failures.is_empty(),
		"checks": checks,
		"failures": failures,
		"groups": group_results,
	}
	print("MAXWELL_TEST_REPORT=" + JSON.stringify(report))
	print("MAXWELL_TEST_END")
	quit(0 if failures.is_empty() else 1)


func _test_neutral_extraction_and_transfer_boundaries() -> void:
	var f := failures.size()
	var c := checks
	for axis in range(5):
		var ordinary_source := PropertyState.new("ordinary", [0, 0, 0, 0, 0])
		var ordinary_target := PropertyState.new("ordinary", [0, 0, 0, 0, 0])
		var positive := PropertyState.transfer(ordinary_source, ordinary_target, axis, 1)
		_check(positive.ok, "axis %d: neutral positive extraction must succeed" % axis)
		_check(ordinary_source.get_axis(axis) == -1, "axis %d: extracted ordinary source must become opposite negative" % axis)
		_check(ordinary_target.get_axis(axis) == 1, "axis %d: target must receive positive unit" % axis)

		var reverse_source := PropertyState.new("ordinary", [0, 0, 0, 0, 0])
		var reverse_target := PropertyState.new("ordinary", [0, 0, 0, 0, 0])
		var negative := PropertyState.transfer(reverse_source, reverse_target, axis, -1)
		_check(negative.ok, "axis %d: neutral negative extraction must succeed" % axis)
		_check(reverse_source.get_axis(axis) == 1, "axis %d: negative extraction source must become positive" % axis)
		_check(reverse_target.get_axis(axis) == -1, "axis %d: target must receive negative unit" % axis)

	for axis in range(5):
		for source_value in [-1, 0, 1]:
			for target_value in [-1, 0, 1]:
				for polarity in [-1, 1]:
					var source_values := [0, 0, 0, 0, 0]
					var target_values := [0, 0, 0, 0, 0]
					source_values[axis] = source_value
					target_values[axis] = target_value
					var source := PropertyState.new("a", source_values)
					var target := PropertyState.new("b", target_values)
					var expected_ok: bool = source_value - polarity >= -1 and source_value - polarity <= 1 and target_value + polarity >= -1 and target_value + polarity <= 1
					var total_before: int = source_value + target_value
					var result := PropertyState.transfer(source, target, axis, polarity)
					_check(result.ok == expected_ok, "transfer boundary mismatch %s" % str([axis, source_value, target_value, polarity]))
					_check(source.get_axis(axis) + target.get_axis(axis) == total_before, "transfer must conserve unit sum")
	_group("neutral_extraction_and_all_transfers", f, c)


func _test_contact_reactions() -> void:
	var f := failures.size()
	var c := checks
	var hot := PropertyState.new("stone", [1, 0, 0, 0, 0])
	var fuel := PropertyState.new("wood", [0, 1, 0, 0, 0])
	ContactRules.resolve_pair(hot, fuel)
	_check(fuel.burning, "hot + flammable must ignite immediately")

	var ordinary := PropertyState.new("stone", [0, 0, 0, 0, 0])
	ContactRules.resolve_pair(hot.duplicate_state(), ordinary)
	_check(not ordinary.burning, "hot + ordinary must not burn")

	var extinguisher := PropertyState.new("stone", [0, -1, 0, 0, 0])
	ContactRules.resolve_pair(fuel, extinguisher)
	_check(not fuel.burning, "extinguishing item must stop burning")

	var cold := PropertyState.new("stone", [-1, 0, 0, 0, 0])
	var water := PropertyState.new("water", [0, 0, 1, 0, 0])
	water.base_can_be_liquid = true
	water.phase = "liquid"
	ContactRules.resolve_pair(cold, water)
	_check(water.frozen and water.phase == "solid", "cold + freezable liquid must freeze into solid")

	var anti_freeze := PropertyState.new("stone", [0, 0, -1, 0, 0])
	ContactRules.resolve_pair(anti_freeze, water)
	_check(not water.frozen and water.phase == "liquid", "anti-freeze must thaw frozen liquid while touching")
	ContactRules.resolve_intrinsic(water)
	_check(not water.frozen, "water frozen by a removed external cold source must not refreeze when its own temperature is neutral")

	var intrinsically_cold_water := PropertyState.new("water", [-1, 0, 1, 0, 0])
	intrinsically_cold_water.base_can_be_liquid = true
	intrinsically_cold_water.phase = "liquid"
	ContactRules.resolve_intrinsic(intrinsically_cold_water)
	ContactRules.resolve_pair(anti_freeze, intrinsically_cold_water)
	_check(not intrinsically_cold_water.frozen, "anti-freeze contact must temporarily suppress intrinsically cold water ice")
	ContactRules.resolve_intrinsic(intrinsically_cold_water)
	_check(intrinsically_cold_water.frozen and intrinsically_cold_water.phase == "solid", "separated cold + freezable object must immediately refreeze")

	var intrinsically_hot_fuel := PropertyState.new("wood", [1, 1, 0, 0, 0])
	ContactRules.resolve_intrinsic(intrinsically_hot_fuel)
	ContactRules.resolve_pair(extinguisher, intrinsically_hot_fuel)
	_check(not intrinsically_hot_fuel.burning, "extinguisher contact must temporarily suppress intrinsically hot fuel fire")
	ContactRules.resolve_intrinsic(intrinsically_hot_fuel)
	_check(intrinsically_hot_fuel.burning, "separated hot + flammable object must immediately reignite")

	var hot_again := PropertyState.new("hot", [1, 0, 0, 0, 0])
	var cold_again := PropertyState.new("cold", [-1, 0, 0, 0, 0])
	ContactRules.resolve_pair(hot_again, cold_again)
	_check(hot_again.get_axis(0) == 0 and cold_again.get_axis(0) == 0, "opposite temperatures must neutralize")
	_group("contact_reactions", f, c)


func _all_axis_vectors() -> Array:
	var vectors: Array = []
	for encoded in range(243):
		var value := encoded
		var vector := [0, 0, 0, 0, 0]
		for axis in range(5):
			vector[axis] = value % 3 - 1
			value /= 3
		vectors.append(vector)
	return vectors


func _test_full_pair_matrix() -> void:
	var f := failures.size()
	var c := checks
	var vectors := _all_axis_vectors()
	for left_values in vectors:
		for right_values in vectors:
			var ab_left := PropertyState.new("a", left_values)
			var ab_right := PropertyState.new("b", right_values)
			var ba_left := PropertyState.new("a", left_values)
			var ba_right := PropertyState.new("b", right_values)
			ContactRules.resolve_pair(ab_left, ab_right)
			ContactRules.resolve_pair(ba_right, ba_left)
			_check(ab_left.signature() == ba_left.signature() and ab_right.signature() == ba_right.signature(), "pair order dependence: %s × %s" % [str(left_values), str(right_values)])
	for left_kind in ["furnace", "cold_source", "water", "wood_wall", "glass_gate", "hammer", "resin", "light_shell", "door_blocker"]:
		for right_kind in ["furnace", "cold_source", "water", "wood_wall", "glass_gate", "hammer", "resin", "light_shell", "door_blocker"]:
			var left := PropertyState.new(left_kind)
			var right := PropertyState.new(right_kind)
			ContactRules.resolve_pair(left, right)
			_check(left.values.size() == 5 and right.values.size() == 5, "functional kind matrix failed")
	_group("59049_state_pairs_and_function_pairs", f, c)


func _test_real_collision_geometry() -> void:
	var f := failures.size()
	var c := checks
	var item := MaxwellItem.new().configure({"name": "shape", "kind": "stone", "size": Vector2(80, 60)})
	var default_signature := item.collision_signature()
	_check(default_signature.contains("RectangleShape2D"), "ordinary solid must have rectangle collision")
	item.state.values[PropertyState.Axis.DEFORMATION] = -1
	item.apply_state(true)
	var plastic_signature := item.collision_signature()
	_check(plastic_signature != default_signature and plastic_signature.contains("RectangleShape2D"), "plastic deformation must rebuild a wider collision")
	item.state.values[PropertyState.Axis.DEFORMATION] = 1
	item.apply_state(true)
	_check(item.collision_signature().contains("CircleShape2D"), "elastic state must switch to a round collision")
	item.free()

	var wall := MaxwellItem.new().configure({"name": "wall", "kind": "wood_wall", "size": Vector2(60, 180), "static": true})
	var wall_before := wall.collision_signature()
	wall.breach()
	_check(wall.collision_signature() != wall_before, "burn-through must change collision signature")
	_check(wall.collision_signature().split(";").size() == 2, "breached wall must have two physical segments")
	_check(not wall.point_is_solid_local(Vector2.ZERO), "breached wall center must be physically passable")
	_check(wall.point_is_solid_local(Vector2(0, -75)), "breached wall remaining segment must stay solid")
	wall.free()

	var glass := MaxwellItem.new().configure({"name": "glass", "kind": "glass_gate", "size": Vector2(24, 150), "functional": true})
	var glass_before := glass.collision_signature()
	_check(glass.break_item(), "breakable glass must break")
	_check(not glass.state.function_enabled and glass.collision_signature() != glass_before, "broken glass loses function and rebuilds collision")
	glass.free()

	var frame := MaxwellItem.new().configure({"name": "frame", "kind": "frame", "indestructible": true})
	_check(not frame.break_item() and frame.state.structure == "intact", "indestructible frame must reject damage")
	frame.free()
	_group("real_collision_geometry", f, c)


func _test_phase_structure_identity() -> void:
	var f := failures.size()
	var c := checks
	var water := MaxwellItem.new().configure({"name": "water", "kind": "water", "axes": [-1, 0, 1, 0, 0], "can_be_liquid": true, "phase": "liquid", "size": Vector2(70, 54)})
	water.apply_state(true)
	_check(water.state.frozen and water.state.phase == "solid", "intrinsic cold/freezable water must freeze")
	water.break_item()
	water.state.values[PropertyState.Axis.TEMPERATURE] = 0
	water.thaw()
	_check(water.state.base_kind == "water" and water.state.phase == "liquid" and water.state.structure == "broken", "broken ice must thaw to broken water identity")
	water.free()

	var stone := MaxwellItem.new().configure({"name": "stone", "kind": "stone", "axes": [-1, 0, 1, 0, 0], "size": Vector2(70, 54)})
	stone.apply_state(true)
	stone.break_item()
	stone.state.values[PropertyState.Axis.TEMPERATURE] = 0
	stone.thaw()
	_check(stone.state.base_kind == "stone" and stone.state.phase == "solid" and stone.state.structure == "broken", "frozen broken stone must remain broken stone after thaw")
	stone.free()

	var liquid_a := PropertyState.new("water", [0, 0, 1, 0, 0])
	liquid_a.base_can_be_liquid = true
	liquid_a.phase = "liquid"
	var liquid_b := liquid_a.duplicate_state()
	var different := liquid_a.duplicate_state()
	different.values[PropertyState.Axis.WEIGHT] = -1
	_check(liquid_a.liquid_merge_signature() == liquid_b.liquid_merge_signature(), "identical liquids must be merge-compatible")
	_check(liquid_a.liquid_merge_signature() != different.liquid_merge_signature(), "different liquid states must not merge")
	_group("phase_structure_and_liquid_identity", f, c)


func _test_light_link_and_sources() -> void:
	var f := failures.size()
	var c := checks
	var heavy := MaxwellItem.new().configure({"name": "heavy", "kind": "iron", "axes": [0, 0, 0, 1, 0]})
	var light := MaxwellItem.new().configure({"name": "light", "kind": "shell", "axes": [0, 0, 0, -1, 0]})
	_check(heavy.effective_weight() == 1, "unlinked heavy must be heavy")
	heavy.linked_light = light
	heavy.apply_state()
	_check(heavy.effective_weight() == 0 and is_equal_approx(heavy.mass, 2.4), "linked light must make effective weight normal")
	heavy.linked_light = null
	heavy.apply_state()
	_check(heavy.effective_weight() == 1 and is_equal_approx(heavy.mass, 28.0), "disconnect must restore raw heavy weight")
	heavy.free()
	light.free()

	var furnace := MaxwellItem.new().configure({"name": "furnace", "kind": "furnace", "axes": [1, 0, 0, 1, 0], "source_axis": PropertyState.Axis.TEMPERATURE, "source_value": 1})
	var receiver := PropertyState.new("receiver")
	var extracted := PropertyState.transfer(furnace.state, receiver, PropertyState.Axis.TEMPERATURE, 1)
	_check(extracted.ok and furnace.state.get_axis(0) == 0 and receiver.get_axis(0) == 1, "continuous source still obeys transfer conservation at extraction moment")
	furnace.source_clock = furnace.source_period
	furnace._physics_process(0.01)
	_check(furnace.state.get_axis(0) == 1, "continuous source must replenish after extraction")
	furnace.free()
	_group("light_link_and_continuous_sources", f, c)


func _test_emergent_material_combinations() -> void:
	var f := failures.size()
	var c := checks
	var sticky_target := MaxwellItem.new().configure({"name": "stone", "kind": "stone", "size": Vector2(70, 50)})
	var sticky_source := PropertyState.new("ordinary")
	var sticky_transfer := PropertyState.transfer(sticky_source, sticky_target.state, PropertyState.Axis.DEFORMATION, -1)
	sticky_target.apply_state(true)
	_check(sticky_transfer.ok and sticky_source.get_axis(PropertyState.Axis.DEFORMATION) == 1 and sticky_target.state.get_axis(PropertyState.Axis.DEFORMATION) == -1, "ordinary source must become elastic when target receives sticky plasticity")
	_check(sticky_target.collision_signature().contains("RectangleShape2D"), "sticky target must own flattened physical collision")
	sticky_target.free()

	var light_target := MaxwellItem.new().configure({"name": "wood", "kind": "wood"})
	var light_source := PropertyState.new("ordinary")
	var light_transfer := PropertyState.transfer(light_source, light_target.state, PropertyState.Axis.WEIGHT, -1)
	light_target.apply_state(true)
	_check(light_transfer.ok and light_source.get_axis(PropertyState.Axis.WEIGHT) == 1 and light_target.gravity_scale < 0.0, "ordinary source must become heavy while target becomes physically rising light")
	light_target.free()

	var water_fire := MaxwellItem.new().configure({"name": "water", "kind": "water", "can_be_liquid": true, "phase": "liquid", "size": Vector2(70, 54)})
	var fuel_source := PropertyState.new("ordinary")
	var heat_source := PropertyState.new("ordinary")
	var give_fuel := PropertyState.transfer(fuel_source, water_fire.state, PropertyState.Axis.COMBUSTIBILITY, 1)
	var give_heat := PropertyState.transfer(heat_source, water_fire.state, PropertyState.Axis.TEMPERATURE, 1)
	water_fire.apply_state(true)
	_check(give_fuel.ok and give_heat.ok and water_fire.state.burning, "flammable + hot liquid water must burn immediately")
	_check(water_fire.state.phase == "liquid" and water_fire.collision_signature().contains("CapsuleShape2D"), "burning water must keep liquid phase and rounded liquid collision")
	_check(fuel_source.get_axis(PropertyState.Axis.COMBUSTIBILITY) == -1 and heat_source.get_axis(PropertyState.Axis.TEMPERATURE) == -1, "flowing fire extraction must leave extinguisher and cold opposites in ordinary sources")
	var nearby_wood := PropertyState.new("wood", [0, 1, 0, 0, 0])
	var nearby_stone := PropertyState.new("stone", [0, 0, 0, 0, 0])
	ContactRules.resolve_pair(water_fire.state, nearby_wood)
	ContactRules.resolve_pair(water_fire.state, nearby_stone)
	_check(nearby_wood.burning, "flowing fire must ignite directly touching flammable wood")
	_check(not nearby_stone.burning, "flowing fire must not ignite ordinary nonflammable stone")
	_check(nearby_stone.get_axis(PropertyState.Axis.TEMPERATURE) == 1, "flowing fire must continuously heat touching ordinary matter")
	var ordinary_water := PropertyState.new("water", [0, 0, 1, 0, 0])
	ordinary_water.base_can_be_liquid = true
	ordinary_water.phase = "liquid"
	var burning_wood_for_water := PropertyState.new("wood", [1, 1, 0, 0, 0])
	ContactRules.resolve_intrinsic(burning_wood_for_water)
	ContactRules.resolve_pair(burning_wood_for_water, ordinary_water)
	_check(ordinary_water.get_axis(PropertyState.Axis.TEMPERATURE) == 1 and not ordinary_water.burning, "ordinary water touching fire must automatically become hot but not burn")
	_check(not burning_wood_for_water.burning and burning_wood_for_water.get_axis(PropertyState.Axis.TEMPERATURE) == 1, "non-burning liquid water must suppress fire without deleting heat")
	ContactRules.resolve_intrinsic(burning_wood_for_water)
	_check(burning_wood_for_water.burning, "hot flammable object must reignite immediately after ordinary water leaves")
	var cold_water_for_fire := PropertyState.new("water", [-1, 0, 1, 0, 0])
	cold_water_for_fire.base_can_be_liquid = true
	cold_water_for_fire.phase = "liquid"
	var another_burning_wood := PropertyState.new("wood", [1, 1, 0, 0, 0])
	ContactRules.resolve_intrinsic(another_burning_wood)
	ContactRules.resolve_pair(another_burning_wood, cold_water_for_fire)
	_check(not another_burning_wood.burning and another_burning_wood.get_axis(PropertyState.Axis.TEMPERATURE) == 0, "cold water must suppress fire and consume the hot unit")
	ContactRules.resolve_intrinsic(another_burning_wood)
	_check(not another_burning_wood.burning, "object cooled by cold water must not reignite after separation")
	var extinguishing_water := PropertyState.new("water", [0, -1, 1, 0, 0])
	extinguishing_water.base_can_be_liquid = true
	extinguishing_water.phase = "liquid"
	var burning_copy := water_fire.state.duplicate_state()
	ContactRules.resolve_pair(burning_copy, extinguishing_water)
	_check(not burning_copy.burning, "extinguishing water must stop touching fire")
	var flammable_water := PropertyState.new("water", [0, 1, 1, 0, 0])
	flammable_water.base_can_be_liquid = true
	flammable_water.phase = "liquid"
	ContactRules.resolve_pair(water_fire.state, flammable_water)
	_check(flammable_water.burning and flammable_water.get_axis(PropertyState.Axis.TEMPERATURE) == 1 and water_fire.state.burning, "flammable water must catch fire without suppressing the original flowing fire")
	var hot_water := PropertyState.new("water", [1, 0, 1, 0, 0])
	var cold_water := PropertyState.new("water", [-1, 0, 1, 0, 0])
	for liquid in [hot_water, cold_water]:
		liquid.base_can_be_liquid = true
		liquid.phase = "liquid"
	ContactRules.resolve_pair(hot_water, cold_water)
	_check(hot_water.get_axis(PropertyState.Axis.TEMPERATURE) == 0 and cold_water.get_axis(PropertyState.Axis.TEMPERATURE) == 0, "hot and cold water must neutralize before merge")
	_check(not hot_water.frozen and not cold_water.frozen, "opposite temperature neutralization must prevent same-step freezing")
	_check(hot_water.liquid_merge_signature() == cold_water.liquid_merge_signature(), "neutralized same-state water must become merge-compatible")
	var cold_fuel := PropertyState.new("fuel", [-1, 1, 0, 0, 0])
	var one_hot_unit := PropertyState.new("hot", [1, 0, 0, 0, 0])
	ContactRules.resolve_pair(cold_fuel, one_hot_unit)
	_check(cold_fuel.get_axis(PropertyState.Axis.TEMPERATURE) == 0 and not cold_fuel.burning, "one hot unit must first neutralize cold fuel without igniting it")
	var same_flowing_fire := water_fire.state.duplicate_state()
	var extinguished_water := water_fire.state.duplicate_state()
	extinguished_water.burning = false
	_check(water_fire.state.liquid_merge_signature() == same_flowing_fire.liquid_merge_signature(), "identical flowing fire liquids must be merge-compatible")
	_check(water_fire.state.liquid_merge_signature() != extinguished_water.liquid_merge_signature(), "burning and non-burning water must not merge")
	water_fire.free()
	_group("sticky_light_and_flowing_fire", f, c)


func _test_grab_safety() -> void:
	var f := failures.size()
	var c := checks
	var normal := MaxwellItem.new().configure({"name": "normal", "kind": "stone"})
	var hot := MaxwellItem.new().configure({"name": "hot", "kind": "stone", "axes": [1, 0, 0, 0, 0]})
	var cold := MaxwellItem.new().configure({"name": "cold", "kind": "stone", "axes": [-1, 0, 0, 0, 0]})
	var heavy := MaxwellItem.new().configure({"name": "heavy", "kind": "stone", "axes": [0, 0, 0, 1, 0]})
	var frozen := MaxwellItem.new().configure({"name": "ice", "kind": "water", "axes": [-1, 0, 1, 0, 0], "can_be_liquid": true})
	var burning := MaxwellItem.new().configure({"name": "fire", "kind": "wood", "axes": [1, 1, 0, 0, 0]})
	var fixture := MaxwellItem.new().configure({"name": "fixture", "kind": "fixture", "static": true})
	_check(normal.can_be_grabbed(), "neutral normal-weight item must be grabbable")
	_check(not hot.can_be_grabbed(), "hot item must not be directly grabbable")
	_check(not cold.can_be_grabbed(), "cold item must not be directly grabbable")
	_check(not heavy.can_be_grabbed(), "heavy item must not be directly grabbable")
	_check(frozen.state.frozen and not frozen.can_be_grabbed(), "frozen item must not be directly grabbable")
	_check(burning.state.burning and not burning.can_be_grabbed(), "burning item must not be directly grabbable")
	_check(not fixture.can_be_grabbed(), "anchored fixture must not be directly grabbable")
	for item in [normal, hot, cold, heavy, frozen, burning, fixture]:
		item.free()
	_group("grab_temperature_and_process_safety", f, c)


func _test_routes_and_threshold() -> void:
	var f := failures.size()
	var c := checks
	var all_routes := RouteValidator.validate_all()
	_check(all_routes.ok, "all four route state simulations must reach valid door state")
	for route_id in ["weight_transfer", "light_link", "terrain", "ice_support"]:
		_check(all_routes.routes[route_id].ok, "route failed: " + route_id)
	_check(RouteValidator.trap_rejects_naive_receiver(), "naive weight transfer in threshold must remain blocked")
	_group("four_routes_and_threshold_trap", f, c)


func _test_physics_server_gap() -> void:
	var f := failures.size()
	var c := checks
	var wall := MaxwellItem.new().configure({"name": "wall", "kind": "wood_wall", "size": Vector2(60, 180), "static": true})
	wall.position = Vector2(400, 350)
	root.add_child(wall)
	await physics_frame
	wall.breach()
	await physics_frame
	var center_query := PhysicsRayQueryParameters2D.create(Vector2(350, 350), Vector2(450, 350), 4)
	var segment_query := PhysicsRayQueryParameters2D.create(Vector2(350, 285), Vector2(450, 285), 4)
	var center_hit := root.world_2d.direct_space_state.intersect_ray(center_query)
	var segment_hit := root.world_2d.direct_space_state.intersect_ray(segment_query)
	_check(center_hit.is_empty(), "physics server ray must pass through burned center gap")
	_check(not segment_hit.is_empty(), "physics server ray must hit remaining wall segment")
	wall.queue_free()
	await process_frame
	_group("physics_server_passable_gap", f, c)


func _find_kind(scene: DemoWorld, kind: String) -> MaxwellItem:
	for item in scene.items:
		if is_instance_valid(item) and item.state.base_kind == kind:
			return item
	return null


func _fresh_world() -> DemoWorld:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var scene := packed.instantiate() as DemoWorld
	root.add_child(scene)
	return scene


func _dispose_world(scene: DemoWorld) -> void:
	scene.queue_free()
	await process_frame
	await process_frame


func _test_physical_routes() -> void:
	var f := failures.size()
	var c := checks

	# 1. 接收物先进入侧槽，再与重物直接接触并接走重性。
	var weight_world := _fresh_world()
	await physics_frame
	weight_world.blocker.global_position = Vector2(2030, 205)
	weight_world.receiver.global_position = Vector2(1952, 205)
	weight_world.blocker.linear_velocity = Vector2.ZERO
	weight_world.receiver.linear_velocity = Vector2.ZERO
	await physics_frame
	_check(weight_world.blocker.directly_touches(weight_world.receiver, 8.0), "weight route receiver must physically touch blocker")
	var transfer := PropertyState.transfer(weight_world.blocker.state, weight_world.receiver.state, PropertyState.Axis.WEIGHT, 1)
	weight_world.blocker.apply_state(true)
	weight_world.receiver.apply_state(true)
	weight_world._update_door()
	_check(transfer.ok and weight_world._door_open and DemoWorld.SIDE_POCKET.intersects(weight_world.receiver.world_bounds()), "physical weight-transfer route must open door with new heavy in side pocket")
	await _dispose_world(weight_world)

	# 2. 轻壳—树脂—重物是两次有顺序的两两连接，原始重性不被改写。
	var light_world := _fresh_world()
	await physics_frame
	var light := _find_kind(light_world, "light_shell")
	var resin := _find_kind(light_world, "resin")
	light.global_position = Vector2(1920, 205)
	resin.global_position = Vector2(1960, 205)
	light_world.blocker.global_position = Vector2(2020, 205)
	light_world._create_joint(light, resin)
	light_world._create_joint(resin, light_world.blocker)
	light_world.blocker.linked_light = light
	light_world.blocker.apply_state()
	_check(light_world.blocker.effective_weight() == 0 and light_world.blocker.state.get_axis(PropertyState.Axis.WEIGHT) == 1, "physical light chain must only change effective weight")
	light_world.blocker.global_position = Vector2(1880, 205)
	await physics_frame
	light_world._update_door()
	_check(light_world._door_open, "physical light-link route must open after normal-effective blocker is pushed away")
	await _dispose_world(light_world)

	# 3. 可燃支撑烧穿，铰接地板转动，重物由真实刚体重力/冲量滑出门区。
	var terrain_world := _fresh_world()
	await physics_frame
	terrain_world.wood_support.state.values[PropertyState.Axis.TEMPERATURE] = 1
	terrain_world.wood_support.apply_state()
	terrain_world._burn_time = 2.0
	terrain_world._update_process_geometry(0.0)
	for frame in range(150):
		await physics_frame
	terrain_world._update_door()
	_check(terrain_world.wood_support.state.structure == "breached" and terrain_world._floor_tilted, "terrain route must burn a real gap and rotate floor collider")
	_check(terrain_world._door_open and not DemoWorld.DOOR_ZONE.intersects(terrain_world.blocker.world_bounds()), "physical terrain route must slide blocker outside door zone")
	await _dispose_world(terrain_world)

	# 4. 水在支撑区结冰后更换固体碰撞体并触发地板，重物滑出。
	var ice_world := _fresh_world()
	await physics_frame
	var water := _find_kind(ice_world, "water")
	water.global_position = Vector2(1920, 330)
	water.state.values[PropertyState.Axis.TEMPERATURE] = -1
	water.apply_state(true)
	ice_world._update_process_geometry(0.0)
	for frame in range(150):
		await physics_frame
	ice_world._update_door()
	_check(water.state.frozen and water.state.phase == "solid" and ice_world._floor_tilted, "ice route must create a solid collision wedge in support zone")
	_check(ice_world._door_open and not DemoWorld.DOOR_ZONE.intersects(ice_world.blocker.world_bounds()), "physical ice-support route must slide blocker outside door zone")
	await _dispose_world(ice_world)

	# 反例：在门槛上才制造新重物，它会下沉卡死并继续关门。
	var trap_world := _fresh_world()
	await physics_frame
	trap_world.blocker.global_position = Vector2(2030, 205)
	trap_world.receiver.global_position = Vector2(2088, 205)
	var bad_transfer := PropertyState.transfer(trap_world.blocker.state, trap_world.receiver.state, PropertyState.Axis.WEIGHT, 1)
	trap_world.blocker.apply_state(true)
	trap_world.receiver.apply_state(true)
	trap_world._apply_threshold_trap(trap_world.receiver)
	trap_world._update_door()
	_check(bad_transfer.ok and trap_world.receiver.freeze and not trap_world._door_open, "threshold must physically trap naive new heavy and keep door closed")
	await _dispose_world(trap_world)
	_group("fresh_world_physical_routes", f, c)


func _test_scene_integration() -> void:
	var f := failures.size()
	var c := checks
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene must load")
	if packed != null:
		var scene := packed.instantiate() as DemoWorld
		root.add_child(scene)
		await physics_frame
		await physics_frame
		await physics_frame
		_check(scene.items.size() >= 15, "full demo must instantiate item set")
		_check(scene.blocker != null and scene.blocker.effective_weight() == 1, "door blocker must begin heavy")
		_check(not scene.blocker.freeze, "initial blocker must remain movable for terrain route")
		_check(scene.player != null and scene.hud != null, "player and HUD must instantiate")
		_check(scene.wood_support.collision_signature().contains("RectangleShape2D"), "support must own a real collider")
		var carry_pad := _find_kind(scene, "elastic_pad")
		_check(carry_pad.freeze, "elastic pad must remain an anchored jump fixture in this demo")
		var liquid_sheet := _find_kind(scene, "water")
		_check(liquid_sheet.deformable_liquid and liquid_sheet.liquid_cells.size() == 96, "bathtub must contain one volume-conserving deformable liquid sheet")
		_check(liquid_sheet.collision_signature().contains("RectangleShape2D"), "deformable liquid must rebuild real row collision shapes from its occupied cells")
		_check(liquid_sheet.liquid_components().size() == 1, "initial bathtub liquid must begin as one connected physical volume")
		var carry_item := _find_kind(scene, "hammer")
		scene.player.global_position = carry_item.global_position - Vector2(42, -10)
		carry_item.linear_velocity = Vector2.ZERO
		var carry_start_x := carry_item.global_position.x
		scene.player.held_item = carry_item
		carry_item.grabbed_by = scene.player
		carry_item.add_collision_exception_with(scene.player)
		scene.player.add_collision_exception_with(carry_item)
		scene.player.global_position += Vector2(60, 0)
		for frame in range(20):
			await physics_frame
		var carry_distance := carry_item.global_position.distance_to(scene.player.global_position + Vector2(42, -10))
		_check(scene.player.held_item == carry_item and carry_item.global_position.x > carry_start_x + 5.0 and carry_distance <= 110.0, "held movable item must follow the player's hand in open space")
		scene.player.global_position += Vector2(180, 0)
		await physics_frame
		await physics_frame
		_check(scene.player.held_item == null and carry_item.grabbed_by == null, "held item blocked beyond reach must auto-drop instead of stretching infinitely")
		var captured_light := _find_kind(scene, "light_shell")
		captured_light.global_position = Vector2(1000, 330)
		captured_light.linear_velocity = Vector2(0, -900)
		for frame in range(90):
			await physics_frame
		_check(captured_light.global_position.y >= 220 and captured_light.global_position.x > 900 and captured_light.global_position.x < 1100, "open-bottom light cage must keep fast-rising key item inside playable space")
		scene.queue_free()
		await process_frame
	_group("scene_and_physics_integration", f, c)
