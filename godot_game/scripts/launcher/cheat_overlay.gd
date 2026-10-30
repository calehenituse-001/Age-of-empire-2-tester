class_name CheatOverlay
extends CanvasLayer
var main: Main
var floating: Button
var panel: PanelContainer
var diagnostics_label: Label
var moved := false
var dragging := false
var drag_start := Vector2.ZERO
var button_start := Vector2.ZERO
var touch_index := -1
var elapsed := 0.0
const LABELS := {"food": "Unlimited Food", "wood": "Unlimited Wood", "gold": "Unlimited Gold", "stone": "Unlimited Stone", "resource_multiplier": "Resource Income Multiplier", "instant_build": "Instant Construction", "build_multiplier": "Construction Multiplier", "free_build": "Ignore Construction Costs", "instant_train": "Instant Training", "train_multiplier": "Training Multiplier", "instant_upgrade": "Instant Unit Upgrades", "instant_research": "Instant Research", "research_multiplier": "Research Multiplier", "free_research": "Ignore Research Costs", "population_override": "Population Override"}

func setup(owner_main: Main) -> void:
	main = owner_main
	layer = 1024
	AppRuntime.overlay = self
	floating = _button("SAFE MODE" if AppRuntime.safe_mode else "CHEATS")
	floating.position = Vector2(20, 110)
	floating.size = Vector2(160, 60)
	add_child(floating)
	floating.gui_input.connect(_drag)
	floating.pressed.connect(func() -> void:
		if not moved:
			panel.visible = not panel.visible)
	panel = PanelContainer.new()
	panel.position = Vector2(16, 16)
	var available := main.get_viewport().get_visible_rect().size
	panel.size = Vector2(minf(700, available.x - 32), available.y - 32)
	panel.visible = false
	add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	var heading := Label.new()
	heading.text = "CHEATS · human player only · offline\nCompleted work remains when disabled."
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	var close := _button("CLOSE")
	close.pressed.connect(func() -> void: panel.hide())
	column.add_child(close)
	for key: String in CheatPolicy.FLAGS:
		var b := _button("")
		b.toggle_mode = true
		b.button_pressed = bool(AppRuntime.cheats.values[key])
		b.disabled = not AppRuntime.cheats.eligible()
		b.text = LABELS[key] + (" · ON" if b.button_pressed else " · OFF")
		b.toggled.connect(func(on: bool) -> void:
			AppRuntime.cheats.values[key] = on
			b.text = LABELS[key] + (" · ON" if on else " · OFF")
			if not AppRuntime.save_cheats():
				main.hud.toast("Could not save cheat configuration")
			main.map.recalc_pop())
		column.add_child(b)
	for kind in ["resource", "build", "train", "research"]:
		var choices := OptionButton.new()
		choices.add_theme_font_size_override("font_size", 26)
		choices.custom_minimum_size.y = 58
		choices.disabled = not AppRuntime.cheats.eligible()
		for n: int in CheatPolicy.FACTORS:
			choices.add_item(kind.capitalize() + " ×" + str(n))
		choices.select(CheatPolicy.FACTORS.find(int(AppRuntime.cheats.values[kind + "_factor"])))
		choices.item_selected.connect(func(index: int) -> void:
			AppRuntime.cheats.values[kind + "_factor"] = CheatPolicy.FACTORS[index]
			AppRuntime.save_cheats())
		column.add_child(choices)
	var pop := SpinBox.new()
	pop.min_value = 1
	pop.max_value = 1000
	pop.value = int(AppRuntime.cheats.values.population_limit)
	pop.prefix = "Population"
	pop.custom_minimum_size.y = 58
	pop.get_line_edit().add_theme_font_size_override("font_size", 26)
	pop.editable = AppRuntime.cheats.eligible()
	pop.value_changed.connect(func(value: float) -> void:
		AppRuntime.cheats.values.population_limit = int(value)
		AppRuntime.save_cheats()
		main.map.recalc_pop())
	column.add_child(pop)
	var leave := _button("SAVE AND RETURN TO LAUNCHER")
	leave.pressed.connect(func() -> void:
		if SaveGame.write(SaveGame.AUTO, main):
			get_tree().quit()
		else:
			main.hud.toast("Save failed; game remains open"))
	column.add_child(leave)
	diagnostics_label = Label.new()
	diagnostics_label.position = Vector2(195, 110)
	diagnostics_label.add_theme_font_size_override("font_size", 22)
	diagnostics_label.visible = AppRuntime.config.get("diagnostics", false)
	add_child(diagnostics_label)

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 58
	b.add_theme_font_size_override("font_size", 26)
	return b

func _drag(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index < 0:
			touch_index = event.index
			drag_start = event.position
			button_start = floating.position
			moved = false
		elif event.index == touch_index:
			touch_index = -1
	elif event is InputEventScreenDrag and event.index == touch_index:
		_move(floating.position + event.relative - button_start)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			drag_start = floating.get_global_mouse_position()
			button_start = floating.position
			moved = false
	elif event is InputEventMouseMotion and dragging:
		_move(floating.get_global_mouse_position() - drag_start)

func _move(offset: Vector2) -> void:
	if offset.length() > 8 or moved:
		moved = true
		floating.position = (button_start + offset).clamp(Vector2.ZERO, main.get_viewport().get_visible_rect().size - floating.size)
		floating.accept_event()

func blocks(point: Vector2) -> bool:
	return (panel.visible and panel.get_global_rect().has_point(point)) or floating.get_global_rect().has_point(point)

func _process(dt: float) -> void:
	elapsed += dt
	if elapsed >= 1.0:
		elapsed = 0.0
		if diagnostics_label and diagnostics_label.visible:
			diagnostics_label.text = AppRuntime.diagnostics()
