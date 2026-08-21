class_name PropertyState
extends RefCounted

enum Axis {
	TEMPERATURE,
	COMBUSTIBILITY,
	FREEZABILITY,
	WEIGHT,
	DEFORMATION,
}

const AXIS_NAMES := ["温度", "燃烧性", "冻结性", "重量", "形变"]
const VALUE_NAMES := [
	["冷", "常温", "烫"],
	["灭火", "普通", "可燃"],
	["阻止结冰", "不可冻结", "可冻结"],
	["轻", "正常", "重"],
	["黏塑", "普通", "弹性"],
]

var values: Array = [0, 0, 0, 0, 0]
var burning := false
var frozen := false
var phase := "solid"
var structure := "intact"
var function_enabled := true
var base_kind := "generic"
var base_can_be_liquid := false


func _init(kind := "generic", initial_values: Array = [0, 0, 0, 0, 0]) -> void:
	base_kind = kind
	if initial_values.size() != 5:
		push_error("物性数组必须恰好包含五条轴")
		initial_values = [0, 0, 0, 0, 0]
	values = initial_values.duplicate()
	for value in values:
		assert(value >= -1 and value <= 1)


func get_axis(axis: int) -> int:
	return values[axis]


func set_axis(axis: int, value: int) -> bool:
	if axis < 0 or axis >= values.size() or value < -1 or value > 1:
		return false
	values[axis] = value
	reconcile_processes()
	return true


func duplicate_state() -> PropertyState:
	var copy := PropertyState.new(base_kind, values)
	copy.burning = burning
	copy.frozen = frozen
	copy.phase = phase
	copy.structure = structure
	copy.function_enabled = function_enabled
	copy.base_can_be_liquid = base_can_be_liquid
	return copy


func reconcile_processes() -> void:
	if values[Axis.COMBUSTIBILITY] != 1:
		burning = false
	if values[Axis.FREEZABILITY] != 1:
		frozen = false
	if frozen:
		phase = "solid"
	elif base_can_be_liquid:
		phase = "liquid"


func signature() -> String:
	return "%s|%s|%s|%s|%s|%s" % [
		str(values), str(burning), str(frozen), phase, structure, str(function_enabled)
	]


func liquid_merge_signature() -> String:
	return "%s|%s|%s|%s|%s" % [
		base_kind, str(values), str(burning), str(frozen), structure
	]


func describe_axis(axis: int) -> String:
	return "%s：%s" % [AXIS_NAMES[axis], VALUE_NAMES[axis][values[axis] + 1]]


static func transfer(source: PropertyState, target: PropertyState, axis: int, polarity: int) -> Dictionary:
	if source == target:
		return {"ok": false, "reason": "源和目标不能相同"}
	if axis < 0 or axis >= 5 or (polarity != -1 and polarity != 1):
		return {"ok": false, "reason": "转移参数无效"}
	var next_source := source.get_axis(axis) - polarity
	var next_target := target.get_axis(axis) + polarity
	if next_source < -1 or next_source > 1 or next_target < -1 or next_target > 1:
		return {"ok": false, "reason": "这一方向已经没有可转移的单位"}
	var total_before := source.get_axis(axis) + target.get_axis(axis)
	source.values[axis] = next_source
	target.values[axis] = next_target
	source.reconcile_processes()
	target.reconcile_processes()
	assert(source.get_axis(axis) + target.get_axis(axis) == total_before)
	return {"ok": true, "reason": "转移成功"}
