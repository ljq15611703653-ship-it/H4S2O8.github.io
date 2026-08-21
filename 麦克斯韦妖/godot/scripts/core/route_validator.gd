class_name RouteValidator
extends RefCounted


static func validate_route(route_id: String) -> Dictionary:
	match route_id:
		"weight_transfer":
			return _weight_transfer_route()
		"light_link":
			return _light_link_route()
		"terrain":
			return _terrain_route()
		"ice_support":
			return _ice_support_route()
	return {"ok": false, "reason": "unknown route"}


static func validate_all() -> Dictionary:
	var results := {}
	var ok := true
	for route_id in ["weight_transfer", "light_link", "terrain", "ice_support"]:
		var result := validate_route(route_id)
		results[route_id] = result
		ok = ok and result.ok
	return {"ok": ok, "routes": results}


static func _weight_transfer_route() -> Dictionary:
	var blocker := PropertyState.new("iron", [0, 0, 0, 1, 0])
	var receiver := PropertyState.new("stone", [0, 0, 0, 0, 0])
	var receiver_in_side_pocket := true
	var transfer_result := PropertyState.transfer(blocker, receiver, PropertyState.Axis.WEIGHT, 1)
	var door_clear := blocker.get_axis(PropertyState.Axis.WEIGHT) == 0 and receiver.get_axis(PropertyState.Axis.WEIGHT) == 1 and receiver_in_side_pocket
	return {"ok": transfer_result.ok and door_clear, "blocker": blocker.signature(), "receiver": receiver.signature()}


static func _light_link_route() -> Dictionary:
	var heavy := PropertyState.new("iron", [0, 0, 0, 1, 0])
	var light := PropertyState.new("shell", [0, 0, 0, -1, 0])
	var resin := PropertyState.new("resin", [0, 0, 0, 0, -1])
	var connected := light.get_axis(PropertyState.Axis.WEIGHT) == -1 and resin.get_axis(PropertyState.Axis.DEFORMATION) == -1
	var effective_weight := 0 if connected else heavy.get_axis(PropertyState.Axis.WEIGHT)
	var moved_outside := effective_weight == 0
	connected = false
	var restored_weight := heavy.get_axis(PropertyState.Axis.WEIGHT)
	return {"ok": moved_outside and restored_weight == 1 and not connected, "effective": effective_weight, "restored": restored_weight}


static func _terrain_route() -> Dictionary:
	var support := PropertyState.new("wood_wall", [1, 1, 0, 0, 0])
	ContactRules.resolve_intrinsic(support)
	var breached := support.burning
	var floor_tilted := breached
	var blocker_slid_out := floor_tilted
	return {"ok": support.burning and breached and blocker_slid_out, "burning": support.burning}


static func _ice_support_route() -> Dictionary:
	var water := PropertyState.new("water", [0, 0, 1, 0, 0])
	water.base_can_be_liquid = true
	water.phase = "liquid"
	var cold_source := PropertyState.new("cold_source", [-1, 0, 0, 0, 0])
	ContactRules.resolve_pair(water, cold_source)
	var wedge_formed := water.frozen and water.phase == "solid"
	var floor_tilted := wedge_formed
	var blocker_slid_out := floor_tilted
	return {"ok": wedge_formed and blocker_slid_out, "water": water.signature()}


static func trap_rejects_naive_receiver() -> bool:
	var blocker := PropertyState.new("iron", [0, 0, 0, 1, 0])
	var receiver := PropertyState.new("stone", [0, 0, 0, 0, 0])
	var receiver_in_door_threshold := true
	var result := PropertyState.transfer(blocker, receiver, PropertyState.Axis.WEIGHT, 1)
	var threshold_is_blocked := receiver_in_door_threshold and receiver.get_axis(PropertyState.Axis.WEIGHT) == 1
	return result.ok and threshold_is_blocked
