class_name DemoHud
extends CanvasLayer

var status_label: Label
var context_label: Label
var win_panel: PanelContainer
var codex_panel: PanelContainer


func configure() -> DemoHud:
	var title := Label.new()
	title.position = Vector2(22, 16)
	title.text = "麦克斯韦妖的燃烧水  ·  全验证实验室"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#f1d99b"))
	add_child(title)

	var help_panel := PanelContainer.new()
	help_panel.position = Vector2(18, 56)
	help_panel.size = Vector2(398, 154)
	var help := Label.new()
	help.text = "A/D 移动　空格跳跃　E 抓取/放下　R 使用工具/黏合　C 图鉴\n1 温度　2 燃烧性　3 冻结性　4 重量　5 形变\n数字键：手中物 → 接触物；Shift：反向\nCtrl+数字：转移负单位；T 重置\n\n关键：从普通物提取正物性，源物会立刻变成相反物性。"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color("#dbe8eb"))
	help_panel.add_child(help)
	add_child(help_panel)

	status_label = Label.new()
	status_label.position = Vector2(22, 226)
	status_label.size = Vector2(650, 48)
	status_label.text = "目标：想办法清空高处门前的重物，然后让妖怪进门。"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color("#ffdc83"))
	add_child(status_label)

	context_label = Label.new()
	context_label.position = Vector2(850, 18)
	context_label.size = Vector2(410, 190)
	context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	context_label.add_theme_font_size_override("font_size", 14)
	context_label.add_theme_color_override("font_color", Color("#c7f3ef"))
	add_child(context_label)

	win_panel = PanelContainer.new()
	win_panel.position = Vector2(390, 260)
	win_panel.size = Vector2(500, 170)
	win_panel.visible = false
	var win_label := Label.new()
	win_label.text = "实验完成\n\n你没有找到“钥匙”，只是让门前不再存在重物。\n世界只检查最终状态，不关心你走了哪条路线。\n\n按 T 重新实验"
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 19)
	win_label.add_theme_color_override("font_color", Color("#ecf9d2"))
	win_panel.add_child(win_label)
	add_child(win_panel)

	codex_panel = PanelContainer.new()
	codex_panel.position = Vector2(410, 104)
	codex_panel.size = Vector2(520, 510)
	codex_panel.visible = false
	var codex := Label.new()
	codex.text = "实验图鉴　［C 关闭］\n\n麦克斯韦榨取\n普通物给出 +1 后自身成为 −1；给出 −1 后自身成为 +1。物性守恒，不会复制。\n\n流动的火\n液态水 + 可燃 + 烫 → 燃烧液体。基底仍是水，继续使用液体碰撞、流动和同状态合并；灭火物接触或移走可燃性后停止。\n\n黏塑 / 弹性\n普通物给出黏塑后自身变弹性。黏塑目标变扁、高摩擦；弹性目标变圆并反弹。\n\n轻 / 重\n普通物给出轻后自身变重。轻物向上飘；轻物经黏塑连接重物时，只临时把重物有效重量降为普通。\n\n冷冻对称\n冷 + 可冻结 → 结冰；阻冻物仅在直接接触期间解冻。若物体自身仍是冷 + 可冻结，分开后立即重新结冰。\n\n图鉴只记录材料规律，不给出门前重物的固定解法。"
	codex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	codex.add_theme_font_size_override("font_size", 16)
	codex.add_theme_color_override("font_color", Color("#e7f3e7"))
	codex_panel.add_child(codex)
	add_child(codex_panel)
	return self


func set_status(message: String) -> void:
	status_label.text = message


func set_context(player: MaxwellPlayer, touching: MaxwellItem) -> void:
	var lines: Array[String] = []
	if player.held_item != null and is_instance_valid(player.held_item):
		lines.append("手中：" + _describe(player.held_item))
	else:
		lines.append("手中：空")
	if touching != null:
		lines.append("接触：" + _describe(touching))
	else:
		lines.append("接触：无")
	context_label.text = "\n".join(lines)


func _describe(item: MaxwellItem) -> String:
	var state := item.state
	var process := ""
	if state.burning:
		process += " · 燃烧"
	if state.frozen:
		process += " · 结冰"
	return "%s\n%s / %s / %s / %s / %s%s" % [
		item.display_name,
		PropertyState.VALUE_NAMES[0][state.values[0] + 1],
		PropertyState.VALUE_NAMES[1][state.values[1] + 1],
		PropertyState.VALUE_NAMES[2][state.values[2] + 1],
		PropertyState.VALUE_NAMES[3][state.values[3] + 1],
		PropertyState.VALUE_NAMES[4][state.values[4] + 1],
		process,
	]


func show_win() -> void:
	win_panel.visible = true


func toggle_codex() -> void:
	codex_panel.visible = not codex_panel.visible
