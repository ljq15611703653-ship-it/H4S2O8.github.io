class_name ContactRules
extends RefCounted


static func resolve_pair(left: PropertyState, right: PropertyState) -> Array[String]:
	# 所有判断先读取同一个快照，再一次性提交，避免左右调用顺序影响结果。
	var events: Array[String] = []
	var lv := left.values.duplicate()
	var rv := right.values.duplicate()
	var left_was_burning := left.burning
	var right_was_burning := right.burning
	var left_was_frozen := left.frozen
	var right_was_frozen := right.frozen

	var ignite_left: bool = (lv[PropertyState.Axis.COMBUSTIBILITY] == 1
		and lv[PropertyState.Axis.TEMPERATURE] != -1
		and (rv[PropertyState.Axis.TEMPERATURE] == 1 or right_was_burning))
	var ignite_right: bool = (rv[PropertyState.Axis.COMBUSTIBILITY] == 1
		and rv[PropertyState.Axis.TEMPERATURE] != -1
		and (lv[PropertyState.Axis.TEMPERATURE] == 1 or left_was_burning))
	var right_is_nonburning_liquid_water: bool = right.base_kind == "water" and right.phase == "liquid" and not right_was_burning
	var left_is_nonburning_liquid_water: bool = left.base_kind == "water" and left.phase == "liquid" and not left_was_burning
	var water_suppresses_left: bool = left_was_burning and right_is_nonburning_liquid_water and not ignite_right
	var water_suppresses_right: bool = right_was_burning and left_is_nonburning_liquid_water and not ignite_left
	var extinguish_left: bool = left_was_burning and (rv[PropertyState.Axis.COMBUSTIBILITY] == -1 or water_suppresses_left)
	var extinguish_right: bool = right_was_burning and (lv[PropertyState.Axis.COMBUSTIBILITY] == -1 or water_suppresses_right)

	var freeze_left: bool = (lv[PropertyState.Axis.FREEZABILITY] == 1
		and lv[PropertyState.Axis.TEMPERATURE] != 1
		and rv[PropertyState.Axis.TEMPERATURE] == -1)
	var freeze_right: bool = (rv[PropertyState.Axis.FREEZABILITY] == 1
		and rv[PropertyState.Axis.TEMPERATURE] != 1
		and lv[PropertyState.Axis.TEMPERATURE] == -1)
	var thaw_left: bool = left_was_frozen and rv[PropertyState.Axis.FREEZABILITY] == -1
	var thaw_right: bool = right_was_frozen and lv[PropertyState.Axis.FREEZABILITY] == -1
	var heat_left: bool = right_was_burning and (not extinguish_right or water_suppresses_right) and lv[PropertyState.Axis.TEMPERATURE] < 1
	var heat_right: bool = left_was_burning and (not extinguish_left or water_suppresses_left) and rv[PropertyState.Axis.TEMPERATURE] < 1
	var cold_water_cools_left: bool = water_suppresses_left and rv[PropertyState.Axis.TEMPERATURE] == -1
	var cold_water_cools_right: bool = water_suppresses_right and lv[PropertyState.Axis.TEMPERATURE] == -1

	if ignite_left and not extinguish_left:
		left.burning = true
		events.append("ignite_left")
	if ignite_right and not extinguish_right:
		right.burning = true
		events.append("ignite_right")
	if extinguish_left:
		left.burning = false
		events.append("extinguish_left")
	if extinguish_right:
		right.burning = false
		events.append("extinguish_right")

	# 燃烧是持续热源，不是一次性属性转移：源不失去烫，接触物每步向烫移动一级。
	if cold_water_cools_left:
		left.values[PropertyState.Axis.TEMPERATURE] = 0
		right.values[PropertyState.Axis.TEMPERATURE] = 0
		events.append("cold_water_cools_left")
	elif heat_left:
		left.values[PropertyState.Axis.TEMPERATURE] = mini(1, lv[PropertyState.Axis.TEMPERATURE] + 1)
		events.append("heat_left")
	if cold_water_cools_right:
		right.values[PropertyState.Axis.TEMPERATURE] = 0
		left.values[PropertyState.Axis.TEMPERATURE] = 0
		events.append("cold_water_cools_right")
	elif heat_right:
		right.values[PropertyState.Axis.TEMPERATURE] = mini(1, rv[PropertyState.Axis.TEMPERATURE] + 1)
		events.append("heat_right")

	if freeze_left and not thaw_left:
		left.frozen = true
		left.phase = "solid"
		events.append("freeze_left")
	if freeze_right and not thaw_right:
		right.frozen = true
		right.phase = "solid"
		events.append("freeze_right")
	if thaw_left:
		left.frozen = false
		if left.base_can_be_liquid:
			left.phase = "liquid"
		events.append("thaw_left")
	if thaw_right:
		right.frozen = false
		if right.base_can_be_liquid:
			right.phase = "liquid"
		events.append("thaw_right")

	# 冷与烫是同一维度的相反单位，直接接触后双方归中。
	if not heat_left and not heat_right and lv[PropertyState.Axis.TEMPERATURE] == -rv[PropertyState.Axis.TEMPERATURE] and lv[PropertyState.Axis.TEMPERATURE] != 0:
		left.values[PropertyState.Axis.TEMPERATURE] = 0
		right.values[PropertyState.Axis.TEMPERATURE] = 0
		events.append("temperature_neutralized")

	left.reconcile_processes()
	right.reconcile_processes()
	return events


static func resolve_intrinsic(state: PropertyState) -> Array[String]:
	var events: Array[String] = []
	if state.get_axis(PropertyState.Axis.TEMPERATURE) == 1 and state.get_axis(PropertyState.Axis.COMBUSTIBILITY) == 1:
		if not state.burning:
			events.append("self_ignite")
		state.burning = true
	if state.get_axis(PropertyState.Axis.TEMPERATURE) == -1 and state.get_axis(PropertyState.Axis.FREEZABILITY) == 1:
		if not state.frozen:
			events.append("self_freeze")
		state.frozen = true
		state.phase = "solid"
	state.reconcile_processes()
	return events
