class_name Hud
extends CanvasLayer
## The interface, built for a touch tablet. Sizes scale with the screen height (designed on a 1840 px tall tablet)
## and with the player's "interface size" setting.
##
## Top: resources, population, clock and raid timer. Bottom, left to right: minimap, selection card, command cards,
## quick selection and (when relevant) the deconstruct button. Notifications stack under the top bar, coloured and
## with an icon by importance. Menus are full-screen dialogs that pause the game.

var map: GameMap
var ctl: Controller

var s := 1.0
var ui_scale := 1.0

# widgets rebuilt together by build()
var root: Control
var top: PanelContainer
var bottom: PanelContainer
var place_bar: PanelContainer
var minimap: Minimap
var cmd_box: HBoxContainer          # the cards on the current page
var cmd_holder: Control             # clips them; the page size follows its width
var tab_row: HBoxContainer
var tabs_box: HBoxContainer
var pager: HBoxContainer
var page_prev: Button
var page_next: Button
var page_label: Label
var _cmd_items: Array = []          # every card for the selection, across all pages
var _page := 0
var _page_key := ""
var decon_btn: Button
var card_icon: Control
var card_icon_holder: Control
var card_title: Label
var card_hp: ProgressBar
var card_hp_text: Label
var card_prog: ProgressBar
var card_prog_text: Label
var card_body: Label
var clock_label: Label
var raid_label: Label
var raid_pill: PanelContainer
var raid_glyph: Glyph
var speed_label: Label
var idle_badge: PanelContainer
var idle_badge_label: Label
var place_label: Label
var turn_btn: Button
var lasso: LassoOverlay
var toast_box: VBoxContainer
var pop_label: Label
var age_label: Label
var pop_chip: HBoxContainer

var build_tab := 0
var _res_labels: Dictionary = {}
var _cost_labels: Array = []       # [Label, resource, amount]
var _modals: Dictionary = {}       # name -> {"root": Control, "box": VBoxContainer}
var _open_modal := ""
var _confirm_yes: Callable
var _confirm_back := ""
var _decon_target: Building
var _toasts: Array = []            # [{node, t, text}]
var _cmd_sig := ""
var _sync_t := 0.0
var _last_attack_toast := -100.0
var _pulse := 0.0
var _sel_sig := ""

# widgets inside the modals that need refreshing
var _load_btn: Button
var _auto_btn: Button
var _diff_seg: HBoxContainer
var _speed_seg: HBoxContainer
var _attacks_btn: Button
var _chatter_seg: HBoxContainer
var _tomb_seg: HBoxContainer
var _scale_seg: HBoxContainer
var _over_stats: Label
var _opp_seg: HBoxContainer
var _win_stats: Label
var _over_auto: Button

const INK := Color(0.96, 0.91, 0.76)
const DIM := Color(0.72, 0.66, 0.5)
const PANEL := Color(0.09, 0.07, 0.05, 0.95)
const PANEL_IN := Color(0.15, 0.115, 0.08, 1.0)
const GOLD := Color(0.95, 0.8, 0.4)
const EDGE := Color(0.62, 0.48, 0.24)
const GOOD := Color(0.4, 0.85, 0.4)
const WARN := Color(1.0, 0.65, 0.2)
const DANGER := Color(0.95, 0.3, 0.25)

var BUILD_TABS := [
	["Economy", ["house", "farm", "lumber_camp", "mining_camp", "mill", "dock", "market", "tc"]],
	["Military", ["barracks", "archery_range", "stable", "siege_workshop", "monastery", "blacksmith"]],
	["Defense", ["tower", "wall", "gate", "castle", "university"]],
]


func build(m: GameMap, c: Controller) -> void:
	if not AppRuntime.mods.buildings.is_empty():
		BUILD_TABS.append(["Mods", AppRuntime.mods.buildings.map(func(b: Dictionary) -> String: return b.key)])
	map = m
	ctl = c
	ui_scale = Defs.load_ui_scale()
	_build_all()
	map.message.connect(show_toast)
	map.message.connect(func(t: String) -> void: GameLog.event("message: " + t))
	map.game_over.connect(_on_game_over)
	map.victory.connect(_on_victory)
	map.attacked.connect(_on_attacked)
	ctl.selection_changed.connect(_on_selection_changed)
	ctl.placing_changed.connect(_on_placing_changed)


func _build_all() -> void:
	s = clampf(get_viewport().get_visible_rect().size.y / 1840.0, 0.55, 1.6) * ui_scale
	if root:
		root.queue_free()
	_res_labels.clear()
	_cost_labels.clear()
	_modals.clear()
	_toasts.clear()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_bottom()
	_build_place_bar()
	toast_box = VBoxContainer.new()
	toast_box.add_theme_constant_override("separation", int(10 * s))
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_box.offset_top = 100 * s
	root.add_child(toast_box)
	_build_pause()
	_build_settings()
	_build_debug()
	_build_logs()
	_build_barter()
	_build_civ()
	_build_confirm()
	_build_over()
	_build_victory()
	minimap.setup(map, ctl.cam)
	minimap.jump_to.connect(ctl.cam.look_at_world)
	_open_modal = ""
	refresh_commands()
	_sync(true)


# ------------------------------------------------------------------ styling
func _box(col: Color, radius := 14.0, border := Color(0, 0, 0, 0), bw := 0.0, mx := 14.0, my := 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius * s))
	sb.border_color = border
	sb.set_border_width_all(int(bw * s))
	sb.content_margin_left = mx * s
	sb.content_margin_right = mx * s
	sb.content_margin_top = my * s
	sb.content_margin_bottom = my * s
	return sb


func _label(text: String, size_px: int, col := INK, outline := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size_px * s))
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", int(6 * s))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(b: Button, fill: Color, edge: Color, radius := 12.0) -> void:
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.42))
	b.add_theme_stylebox_override("normal", _box(fill, radius, edge, 2))
	b.add_theme_stylebox_override("hover", _box(fill.lightened(0.1), radius, edge.lightened(0.2), 2))
	b.add_theme_stylebox_override("pressed", _box(fill.lightened(0.25), radius, edge.lightened(0.4), 3))
	b.add_theme_stylebox_override("disabled", _box(fill.darkened(0.35), radius, edge.darkened(0.4), 2))
	# a bright frame for keyboard / controller focus
	var f := _box(Color(0, 0, 0, 0), radius, Color(1, 1, 1, 0.95), 4)
	b.add_theme_stylebox_override("focus", f)


func _button(text: String, cb: Callable, w := 170.0, h := 120.0, size_px := 28, fill := Color(0.34, 0.25, 0.14), edge := EDGE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w * s, h * s)
	b.add_theme_font_size_override("font_size", int(size_px * s))
	_style(b, fill, edge)
	b.pressed.connect(cb)
	return b


func _primary(text: String, cb: Callable, w := 300.0, h := 110.0, size_px := 34) -> Button:
	return _button(text, cb, w, h, size_px, Color(0.2, 0.42, 0.2), Color(0.5, 0.85, 0.4))


func _danger(text: String, cb: Callable, w := 300.0, h := 110.0, size_px := 30) -> Button:
	return _button(text, cb, w, h, size_px, Color(0.45, 0.14, 0.1), Color(0.9, 0.4, 0.3))


func _panel(col := PANEL, radius := 0.0, border := EDGE, bw := 3.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(col, radius, border, bw, 18, 12))
	return p


func _spacer(expand := true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


# ------------------------------------------------------------------ top bar
func _build_top() -> void:
	top = _panel(PANEL, 0.0)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_stylebox_override("panel", _box(PANEL, 0, EDGE, 3, 40, 8))
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(30 * s))
	top.add_child(row)
	for r: String in Defs.RES_NAMES:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", int(10 * s))
		chip.add_child(Glyph.make(r, 56 * s))
		var l := _label("0", 38, INK, true)
		l.custom_minimum_size = Vector2(96 * s, 0)
		chip.add_child(l)
		_res_labels[r] = l
		row.add_child(chip)
	pop_chip = HBoxContainer.new()
	pop_chip.add_theme_constant_override("separation", int(10 * s))
	pop_chip.add_child(Glyph.make("pop", 56 * s))
	pop_label = _label("0/0", 38, INK, true)
	pop_chip.add_child(pop_label)
	row.add_child(pop_chip)
	age_label = _label("Dark Age", 30, GOLD, true)
	row.add_child(age_label)
	row.add_child(_spacer())
	var clock := HBoxContainer.new()
	clock.add_theme_constant_override("separation", int(8 * s))
	clock.add_child(Glyph.make("clock", 34 * s))
	clock_label = _label("0:00", 32, INK, true)
	clock.add_child(clock_label)
	row.add_child(clock)
	raid_pill = PanelContainer.new()
	raid_pill.add_theme_stylebox_override("panel", _box(Color(0.2, 0.15, 0.1), 20, EDGE, 2, 16, 4))
	var rp := HBoxContainer.new()
	rp.add_theme_constant_override("separation", int(10 * s))
	raid_glyph = Glyph.make("warn", 34 * s, WARN)
	rp.add_child(raid_glyph)
	raid_label = _label("", 30)
	rp.add_child(raid_label)
	raid_pill.add_child(rp)
	row.add_child(raid_pill)
	speed_label = _label("", 30, GOLD, true)
	row.add_child(speed_label)
	row.add_child(_button("Debug", func() -> void: _open("debug"), 140, 72, 26))
	row.add_child(_button("Menu", func() -> void: _open("pause"), 150, 72, 30, Color(0.4, 0.3, 0.16), GOLD))


# ------------------------------------------------------------------ bottom bar
func _build_bottom() -> void:
	bottom = _panel(PANEL, 0.0)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_stylebox_override("panel", _box(PANEL, 0, EDGE, 3, 30, 14))
	root.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(22 * s))
	bottom.add_child(row)
	# minimap
	var mm_frame := PanelContainer.new()
	mm_frame.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.03), 8, GOLD, 3, 4, 4))
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(260 * s, 260 * s)
	mm_frame.add_child(minimap)
	row.add_child(mm_frame)
	# selection card
	row.add_child(_build_card())
	# commands
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", int(8 * s))
	row.add_child(mid)
	tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", int(10 * s))
	mid.add_child(tab_row)
	tabs_box = HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", int(10 * s))
	tab_row.add_child(tabs_box)
	tab_row.add_child(_spacer())
	# page buttons: big touch targets; the cards never run under the quick buttons or off the screen
	pager = HBoxContainer.new()
	pager.add_theme_constant_override("separation", int(10 * s))
	page_prev = _button("<", _flip.bind(-1), 96, 64, 34)
	page_label = _label("1/1", 28, DIM)
	page_label.custom_minimum_size = Vector2(90 * s, 0)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_next = _button(">", _flip.bind(1), 96, 64, 34)
	pager.add_child(page_prev)
	pager.add_child(page_label)
	pager.add_child(page_next)
	pager.visible = false
	tab_row.add_child(pager)
	cmd_holder = Control.new()
	cmd_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cmd_holder.clip_contents = true
	cmd_holder.resized.connect(_show_page)
	mid.add_child(cmd_holder)
	cmd_box = HBoxContainer.new()
	cmd_box.add_theme_constant_override("separation", int(10 * s))
	cmd_holder.add_child(cmd_box)
	# quick selection
	var qs := GridContainer.new()
	qs.columns = 2
	qs.add_theme_constant_override("h_separation", int(8 * s))
	qs.add_theme_constant_override("v_separation", int(8 * s))
	row.add_child(qs)
	var idle := _quick("villager", "Idle", ctl.select_idle_villager, Color(1.0, 0.75, 0.3))
	idle_badge = PanelContainer.new()
	idle_badge.add_theme_stylebox_override("panel", _box(DANGER, 30, Color(1, 1, 1, 0.9), 2, 10, 0))
	idle_badge_label = _label("0", 26, Color.WHITE)
	idle_badge.add_child(idle_badge_label)
	idle_badge.visible = false
	idle_badge.position = Vector2(100 * s, -4 * s)
	idle.add_child(idle_badge)
	qs.add_child(idle)
	qs.add_child(_quick("villagers", "All", ctl.select_all_villagers, Color(0.55, 0.8, 1.0)))
	qs.add_child(_quick("shield", "Army", ctl.select_army, Color(0.45, 0.65, 1.0)))
	qs.add_child(_quick("clear", "Clear", ctl.clear_selection, Color(0.9, 0.85, 0.7)))
	# deconstruct, far right
	decon_btn = _danger("", _ask_deconstruct, 150, 250, 24)
	var dv := VBoxContainer.new()
	dv.set_anchors_preset(Control.PRESET_FULL_RECT)
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dg := Glyph.make("cross", 60 * s, Color(1, 0.7, 0.6))
	dg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dv.add_child(dg)
	var dl := _label("Deconstruct", 24, INK)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(dl)
	decon_btn.add_child(dv)
	decon_btn.visible = false
	row.add_child(decon_btn)


func _quick(glyph: String, text: String, cb: Callable, col: Color) -> Button:
	var b := _button("", cb, 160, 118, 26)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", int(2 * s))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Glyph.make(glyph, 46 * s, col)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(g)
	var l := _label(text, 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	return b


func _build_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(PANEL_IN, 12, EDGE, 2, 16, 10))
	card.custom_minimum_size = Vector2(640 * s, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(6 * s))
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(14 * s))
	v.add_child(head)
	card_icon_holder = Control.new()
	card_icon_holder.custom_minimum_size = Vector2(110 * s, 84 * s)
	card_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(card_icon_holder)
	card_title = _label("", 36, GOLD)
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_title.clip_text = true
	head.add_child(card_title)
	card_hp = ProgressBar.new()
	card_hp.show_percentage = false
	card_hp.custom_minimum_size = Vector2(0, 26 * s)
	card_hp.max_value = 1.0
	card_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_hp.add_theme_stylebox_override("background", _box(Color(0.05, 0.04, 0.03), 8, Color(0, 0, 0), 2, 0, 0))
	v.add_child(card_hp)
	card_hp_text = _label("", 24, DIM)
	card_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card_hp_text.position = Vector2.ZERO
	card_hp.add_child(card_hp_text)
	card_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_hp_text.add_theme_font_size_override("font_size", int(22 * s))
	card_hp_text.add_theme_color_override("font_color", Color.WHITE)
	card_hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	card_hp_text.add_theme_constant_override("outline_size", int(6 * s))
	card_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_prog = ProgressBar.new()
	card_prog.show_percentage = false
	card_prog.custom_minimum_size = Vector2(0, 22 * s)
	card_prog.max_value = 1.0
	card_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_prog.add_theme_stylebox_override("background", _box(Color(0.05, 0.04, 0.03), 8, Color(0, 0, 0), 2, 0, 0))
	card_prog.add_theme_stylebox_override("fill", _box(Color(0.35, 0.65, 1.0), 8, Color(0, 0, 0, 0), 0, 0, 0))
	card_prog.visible = false
	v.add_child(card_prog)
	card_prog_text = _label("", 22, Color.WHITE, true)
	card_prog_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_prog_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_prog_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_prog.add_child(card_prog_text)
	card_body = _label("", 26, INK)
	card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(card_body)
	return card


# ------------------------------------------------------------------ command cards
func refresh_commands() -> void:
	for c in _cmd_items:
		if c.is_inside_tree():
			c.queue_free()
		else:
			c.free()
	_cmd_items.clear()
	for c in tabs_box.get_children():
		c.queue_free()
	_cost_labels.clear()
	var b := ctl.sel_b
	decon_btn.visible = b != null and b.alive and b.kind != "tc" and ctl.placing == ""
	if ctl.placing != "":
		_show_page()
		return
	var with_build := true
	if b and b.done and b.kind in ["tower", "castle", "barracks", "archery_range", "stable", "siege_workshop", "blacksmith", "university", "monastery", "market", "dock", "house", "lumber_camp", "mining_camp", "mill"]:
		with_build = false       # these show only their own options
	if b and b.done:
		if b.def.has("train"):
			for uk: String in b.train_list():
				var u := map.unit_info(uk)
				_cmd_items.append(_card(_unit_icon(uk), "Train " + String(u.name), u.cost, ctl.train.bind(uk), Color(0.3, 0.26, 0.14)))
		if b.kind == "market":
			_cmd_items.append(_card(Glyph.make("gold", 80 * s), "Trade", {}, _open_barter, Color(0.34, 0.3, 0.1), "buy and sell"))
		for tid: int in map.tech_cards(b):
			_cmd_items.append(_tech_card(b, tid))
		if b.kind == "gate":
			_cmd_items.append(_card(Glyph.make("repair" if not b.locked else "villagers", 80 * s, Color(0.7, 0.85, 1.0)), "Unlock" if b.locked else "Lock", {}, ctl.toggle_gate_lock, Color(0.3, 0.22, 0.12), "shut to everybody" if not b.locked else "open for your units"))
		if not b.garrison.is_empty():
			_cmd_items.append(_card(Glyph.make("villagers", 80 * s, Color(0.55, 0.8, 1.0)), "Unload", {}, ctl.unload_selected, Color(0.2, 0.3, 0.2), "%d inside" % b.garrison.size()))
		if b.hp < b.max_hp - 0.5:
			_cmd_items.append(_card(Glyph.make("repair", 80 * s, Color(0.7, 0.85, 1.0)), "Repair", {}, ctl.repair_selected, Color(0.18, 0.3, 0.4), "%d%% health" % int(b.hp / b.max_hp * 100.0)))
	_cmd_sig = _sig()
	if with_build:
		for i in BUILD_TABS.size():
			var t: Array = BUILD_TABS[i]
			tabs_box.add_child(_button(String(t[0]), _set_tab.bind(i), 220, 64, 28, Color(0.42, 0.31, 0.15) if i == build_tab else Color(0.18, 0.14, 0.1), GOLD if i == build_tab else EDGE))
		var locked: Array = []
		for bk: String in BUILD_TABS[build_tab][1]:
			if b and b.kind == "tc" and bk in ["lumber_camp", "mining_camp", "mill", "barracks", "archery_range", "stable", "siege_workshop", "blacksmith", "university", "monastery", "market", "castle", "dock"]:
				continue    # the Town Center already takes everything in; these stay out of its menu
			var d: Dictionary = Defs.BUILDINGS[bk]
			var lock := Defs.lock_reason(map.tech, bk)
			if lock != "":
				var lc := _card(_building_icon(bk), String(d.name), {}, ctl.start_place.bind(bk), Color(0.2, 0.17, 0.13), lock)
				lc.modulate = Color(1, 1, 1, 0.55)
				locked.append(lc)
			else:
				_cmd_items.append(_card(_building_icon(bk), String(d.name), d.cost, ctl.start_place.bind(bk), Color(0.3, 0.22, 0.12)))
		_cmd_items.append_array(locked)      # what you can build now comes first
	var key := "%d:%d" % [b.get_instance_id() if b else 0, build_tab]
	if key != _page_key:
		_page_key = key
		_page = 0
	_show_page()


## Puts the cards of the current page into the row. A page holds as many cards as fit between the selection card and the
## quick buttons; the arrows above the row turn the pages.
func _show_page() -> void:
	if cmd_box == null:
		return
	for c in cmd_box.get_children():
		cmd_box.remove_child(c)
	var step := (200.0 + 10.0) * s
	var per := maxi(1, int((cmd_holder.size.x + 10.0 * s) / step)) if cmd_holder.size.x > 10.0 else 4
	var pages := maxi(1, ceili(float(_cmd_items.size()) / per))
	_page = clampi(_page, 0, pages - 1)
	for i in range(_page * per, mini(_cmd_items.size(), (_page + 1) * per)):
		cmd_box.add_child(_cmd_items[i])
	pager.visible = pages > 1
	page_label.text = "%d/%d" % [_page + 1, pages]
	page_prev.disabled = _page == 0
	page_next.disabled = _page >= pages - 1


func _flip(d: int) -> void:
	_page += d
	_show_page()


func _set_tab(i: int) -> void:
	build_tab = i
	refresh_commands()


## One command: a big icon, its name, and what it costs. Missing resources are red (and the card is dimmed).
func _card(icon: Control, title: String, cost: Dictionary, cb: Callable, fill: Color, sub := "") -> Button:
	var b := _button("", cb, 200, 196, 24, fill)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 4 * s
	v.offset_right = -4 * s
	v.offset_top = 4 * s
	v.offset_bottom = -4 * s
	v.add_theme_constant_override("separation", int(2 * s))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 92 * s)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(holder)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(icon)
	var name := _label(title, 24)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	v.add_child(name)
	if sub != "":
		var sl := _label(sub, 20, DIM)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.clip_text = true
		v.add_child(sl)
	var costs := HBoxContainer.new()
	costs.alignment = BoxContainer.ALIGNMENT_CENTER
	costs.add_theme_constant_override("separation", int(8 * s))
	costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(costs)
	for r: String in Defs.RES_NAMES:
		if cost.has(r):
			var g := Glyph.make(r, 32 * s)
			costs.add_child(g)
			var l := _label(str(int(cost[r])), 24)
			costs.add_child(l)
			_cost_labels.append([l, r, int(cost[r]), b])
	return b


## A technology the selected building can research: its name, price and how long it takes.
func _tech_card(b: Building, id: int) -> Button:
	var t: Dictionary = Rules.techs[id]
	var ready := map.tech.can_research(id)
	var icon: Control
	if id in Rules.AGE_TECHS:
		var k := Assets.look_key([71, 141, 142][Rules.AGE_TECHS.find(id)], map.style)
		icon = _tex_rect(Assets.tex(Assets.man.buildings[k if k != "" else "tc%s" % ["2", "3", "4"][Rules.AGE_TECHS.find(id)]].file))
	else:
		icon = Glyph.make("up", 1, GOOD)
	var sub := "%d s" % roundi(map.tech.time_of(id) / Rules.GAME_SPEED)
	if not ready:
		sub = Defs.tech_lock_reason(map.tech, id)
	var c := _card(icon, String(t.name), Defs.name_cost(map.tech.cost_of(id)) if ready else {}, ctl.research.bind(id), Color(0.34, 0.3, 0.1) if ready else Color(0.2, 0.17, 0.13), sub)
	if not ready:
		c.modulate = Color(1, 1, 1, 0.55)
	return c


func _building_icon(kind: String) -> Control:
	if kind == "farm":
		var t: Dictionary = Assets.man.terrain["farm_grown"]
		var frame := 4
		var at := AtlasTexture.new()
		at.atlas = Assets.tex(t.file)
		at.region = Rect2(float(t.pad) + (frame % 3) * float(t.cw), float(t.pad) + (frame / 3) * float(t.ch), float(t.tw), float(t.th))
		return _tex_rect(at)
	if kind == "wall":
		var w: Dictionary = Assets.man.walls
		var it: Dictionary = w.items[2]
		var at := AtlasTexture.new()
		at.atlas = Assets.tex(w.file)
		at.region = Rect2(it.x, it.y, it.w, it.h)
		return _tex_rect(at)
	var look := Assets.look_key(map.tech.current(int(Defs.BUILDINGS[kind].uid)), map.style) if Defs.BUILDINGS[kind].has("uid") and kind != "tower" else ""
	return _tex_rect(Assets.tex(Assets.man.buildings[look if look != "" else kind].file))


func _unit_icon(ukind: String) -> Control:
	var key := "vm_stand" if ukind == "villager" else "u%d_idle_blue" % int(ukind)
	var a: Dictionary = Assets.anim(key)
	var f: Array = a.frames[0][0]
	var at := AtlasTexture.new()
	at.atlas = a.tex
	at.region = Rect2(float(a.pad), float(a.pad), f[0], f[1])
	return _tex_rect(at)


func _tex_rect(t: Texture2D) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _sig() -> String:
	var b := ctl.sel_b
	return "t%d" % map.tech.generation if b == null else "%d:%d:%s:%s:%d:%d:%d:%d" % [b.get_instance_id(), b.level, b.done, b.hp < b.max_hp - 0.5, b.train_list().size(), map.tech.generation, b.res_tech, b.garrison.size() + (1000 if b.locked else 0)]


## Recolours the cost numbers: red when you cannot pay.
func _update_costs() -> void:
	var dim := {}
	for e: Array in _cost_labels:
		var lacking: bool = int(map.stock[e[1]]) < int(e[2]) and not AppRuntime.cheats.enabled(e[1])
		(e[0] as Label).add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if lacking else INK)
		dim[e[3]] = bool(dim.get(e[3], false)) or lacking
	for btn: Button in dim:
		if is_instance_valid(btn):
			btn.modulate = Color(1, 1, 1, 0.62) if dim[btn] else Color.WHITE


# ------------------------------------------------------------------ placement bar
func _build_place_bar() -> void:
	lasso = LassoOverlay.new()
	lasso.scale_ui = s
	root.add_child(lasso)
	place_bar = _panel(PANEL, 18)
	place_bar.visible = false
	place_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	place_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	place_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	place_bar.offset_bottom = -24 * s
	root.add_child(place_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(26 * s))
	place_bar.add_child(row)
	place_label = _label("", 30)
	place_label.custom_minimum_size = Vector2(760 * s, 0)
	place_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	place_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(place_label)
	turn_btn = _button("Turn", ctl.rotate_gate, 200, 124, 32)
	row.add_child(turn_btn)
	row.add_child(_danger("Cancel", ctl.cancel_pressed, 240, 124, 32))
	row.add_child(_primary("Place", ctl.confirm_place, 300, 124, 36))


func _on_placing_changed() -> void:
	var on := ctl.placing != ""
	place_bar.visible = on
	bottom.visible = not on
	turn_btn.visible = ctl.placing == "gate"
	if on:
		place_label.text = ctl.place_text()
	refresh_commands()


func _on_selection_changed() -> void:
	refresh_commands()
	_sync(true)


# ------------------------------------------------------------------ modal dialogs
## A full-screen dimmed dialog. Everything behind it is paused and cannot be tapped.
func _modal(id: String, title: String, width := 820.0, title_col := GOLD) -> VBoxContainer:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.62)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.visible = false
	root.add_child(back)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.08, 0.055, 0.99), 22, GOLD, 4, 44, 34))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	back.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width * s, 0)
	v.add_theme_constant_override("separation", int(16 * s))
	panel.add_child(v)
	var t := _label(title, 52, title_col, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_modals[id] = {"root": back, "box": v}
	return v


func _open(id: String) -> void:
	for k: String in _modals:
		_modals[k].root.visible = k == id
	_open_modal = id
	map.paused = id != ""
	if id != "":
		_sync_menus()
		var first := _first_button(_modals[id].root)
		if first:
			first.grab_focus()


func _close_modal() -> void:
	_open("")


func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and not (c as Button).disabled:
			return c
		var r := _first_button(c)
		if r:
			return r
	return null


func _row(a: Control, b: Control = null) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", int(16 * s))
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(a)
	if b:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(b)
	return r


func _section(text: String) -> Label:
	var l := _label(text.to_upper(), 24, DIM)
	return l


## Radio-style buttons: the chosen one is filled gold, the rest dark (never colour alone: the chosen one is also bold-framed).
func _segmented(options: Array, selected: int, cb: Callable) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", int(10 * s))
	for i in options.size():
		var b := _button(String(options[i]), func() -> void: cb.call(i), 160, 84, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(b)
	_mark_segment(r, selected)
	return r


func _mark_segment(r: HBoxContainer, selected: int) -> void:
	for i in r.get_child_count():
		var b := r.get_child(i) as Button
		if i == selected:
			_style(b, Color(0.6, 0.45, 0.15), GOLD)
			b.add_theme_stylebox_override("normal", _box(Color(0.6, 0.45, 0.15), 12, Color(1, 0.95, 0.7), 5))
			b.add_theme_color_override("font_color", Color.WHITE)
		else:
			_style(b, Color(0.2, 0.15, 0.1), EDGE)


func _build_pause() -> void:
	var v := _modal("pause", "Paused", 760)
	v.add_child(_primary("Resume", _close_modal, 300, 130, 42))
	_load_btn = _button("", func() -> void: _load_slot(SaveGame.MANUAL), 300, 120, 28)
	_auto_btn = _button("", func() -> void: _load_slot(SaveGame.AUTO), 300, 120, 28)
	v.add_child(_row(_button("Save game", _save_game, 300, 120, 32), _load_btn))
	v.add_child(_row(_auto_btn, _button("Settings", func() -> void: _open("settings"), 300, 120, 32)))
	v.add_child(_button("Debug logs", _open_logs, 300, 100, 30))
	v.add_child(_danger("New game", func() -> void: _ask("Start a new game?\nUnsaved progress is lost.", "Yes, choose a civilization", _open_civ_chooser, "pause"), 300, 100, 30))


# ------------------------------------------------------------------ the debug logs window
var _log_list: VBoxContainer
var _log_status: Label
var _log_always_seg: HBoxContainer
var _log_text: TextEdit
var _log_view_title: Label
var _log_view_path := ""


func _build_logs() -> void:
	var v := _modal("logs", "Debug logs", 1100)
	_log_status = _label("", 24, DIM)
	_log_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_log_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 620 * s)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_log_list = VBoxContainer.new()
	_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list.add_theme_constant_override("separation", int(12 * s))
	scroll.add_child(_log_list)
	v.add_child(_section("Always log (also while a computer is attached with USB debugging)"))
	_log_always_seg = _segmented(["Off", "On"], 1 if GameLog.always else 0, _set_log_always)
	v.add_child(_log_always_seg)
	v.add_child(_row(_danger("Delete all", func() -> void: _ask("Delete every log?", "Yes, delete all", _delete_all_logs, "logs"), 300, 100, 30),
		_primary("Back", func() -> void: _open("pause"), 300, 100, 34)))
	# one log opened
	var w := _modal("log_view", "Log", 1300)
	_log_view_title = _label("", 24, DIM)
	w.add_child(_log_view_title)
	_log_text = TextEdit.new()
	_log_text.editable = false
	_log_text.custom_minimum_size = Vector2(0, 640 * s)
	_log_text.add_theme_font_size_override("font_size", int(20 * s))
	_log_text.add_theme_color_override("font_readonly_color", INK)
	_log_text.add_theme_stylebox_override("normal", _box(Color(0.04, 0.03, 0.02), 8, EDGE, 2, 14, 10))
	_log_text.add_theme_stylebox_override("read_only", _box(Color(0.04, 0.03, 0.02), 8, EDGE, 2, 14, 10))
	w.add_child(_log_text)
	w.add_child(_row(_button("Save to Downloads", _export_log, 300, 100, 28), _button("Share", func() -> void: _share_log(false), 300, 100, 30)))
	w.add_child(_row(_button("Write a mail", func() -> void: _share_log(true), 300, 100, 30), _danger("Delete", func() -> void: _delete_log(_log_view_path), 300, 100, 30)))
	w.add_child(_primary("Back", _open_logs, 300, 100, 34))


func _open_logs() -> void:
	_refresh_logs()
	_open("logs")


func _refresh_logs() -> void:
	for c in _log_list.get_children():
		c.queue_free()
	_log_status.text = "%s.\n%s" % [("Logging this session to " + GameLog.path.get_file()) if GameLog.enabled else "Not logging this session", GameLog.adb_note]
	var list := GameLog.sessions()
	if list.is_empty():
		_log_list.add_child(_label("No logs yet. Logs are written while the tablet is not attached to a computer.", 26, DIM))
	for item in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(12 * s))
		var t := "%s   %d min   %d KB" % [item.started, maxi(1, int(item.seconds / 60.0)), maxi(1, int(item.size / 1024.0))]
		if int(item.errors) > 0:
			t += "   %d errors" % int(item.errors)
		if item.exit != "":
			t += "\n" + ("PROBLEM: " if item.bad else "") + String(item.exit)
		var l := _label(t, 26, Color(1.0, 0.55, 0.45) if item.bad else INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var p: String = item.path
		row.add_child(_button("Open", func() -> void: _view_log(p), 170, 84, 28))
		row.add_child(_danger("Delete", func() -> void: _delete_log(p), 170, 84, 28))
		_log_list.add_child(row)
	var exits := GameLog.exits_text()
	if exits != "":
		_log_list.add_child(_section("How earlier runs of the app ended (from Android)"))
		var l2 := _label(exits.strip_edges(), 22, DIM)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_log_list.add_child(l2)


func _view_log(p: String) -> void:
	_log_view_path = p
	_log_view_title.text = p.get_file()
	_log_text.text = GameLog.read_tail(p)
	_open("log_view")
	_log_text.scroll_vertical = _log_text.get_line_count()


func _delete_log(p: String) -> void:
	GameLog.delete_session(p)
	_open_logs()


func _delete_all_logs() -> void:
	GameLog.delete_all()
	_open_logs()


func _set_log_always(i: int) -> void:
	GameLog.set_always(i == 1)
	_mark_segment(_log_always_seg, i)


func _export_log() -> void:
	var dst := GameLog.export_file(_log_view_path)
	show_toast("Saved to %s" % dst if dst != "" else "Could not write to Downloads: allow all files access for the app in the Android settings")


func _share_log(mail: bool) -> void:
	var how := GameLog.share_text(_log_view_path, mail)
	if how == "clipboard":
		show_toast("The log text is on the clipboard: paste it into a mail or a message")


func _build_settings() -> void:
	var v := _modal("settings", "Settings", 980)
	v.add_child(_section("Difficulty"))
	var names: Array = []
	for d: String in Defs.DIFFICULTY_ORDER:
		names.append(Defs.DIFFICULTY[d].name)
	_diff_seg = _segmented(names, Defs.DIFFICULTY_ORDER.find(map.difficulty), _set_difficulty)
	v.add_child(_diff_seg)
	v.add_child(_section("Opponent (applies to the next new game)"))
	_opp_seg = _segmented(Defs.OPPONENT_NAMES, Defs.OPPONENTS.find(Defs.load_opponent()), _set_opponent)
	v.add_child(_opp_seg)
	v.add_child(_section("Interface size"))
	_scale_seg = _segmented(["Small", "Normal", "Large"], _scale_index(), _set_scale)
	v.add_child(_scale_seg)
	v.add_child(_section("Snarky comments"))
	_chatter_seg = _segmented(["On", "Off"], 0 if Chatter.enabled else 1, _set_chatter)
	v.add_child(_chatter_seg)
	v.add_child(_section("Tombstones"))
	_tomb_seg = _segmented(["On", "Off"], 0 if Tombstone.enabled else 1, _set_tombs)
	v.add_child(_tomb_seg)
	v.add_child(_section("Sound"))
	for key: String in ["Master", "Music", "Combat", "Work", "Alerts"]:
		v.add_child(_slider_row(key))
	if not GameData.bundled():          # the portable version keeps an imported copy of the game's data
		v.add_child(_section("Game data (imported from your copy of the game)"))
		v.add_child(_danger("Delete it and import again", func() -> void: _ask("Delete the imported game data?\nSaved games stay. You will be asked for the game folder again.", "Yes, delete it", func() -> void:
			Importer.erase()
			get_tree().change_scene_to_file("res://scenes/boot.tscn"), "settings"), 300, 100, 28))
	v.add_child(_primary("Back", func() -> void: _open("pause"), 300, 100, 34))


var _civ_pick := 1
var _civ_buttons: Array = []
var _civ_text: Label


## The new-game window: the 18 civilizations, what the chosen one is good at, and Start.
func _build_civ() -> void:
	var v := _modal("civ", "Choose your civilization", 1500, GOLD)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", int(10 * s))
	grid.add_theme_constant_override("v_separation", int(10 * s))
	_civ_buttons.clear()
	for c in Rules.raw.civ_info:
		var id: int = int(c.id)
		var b := _button(String(c.name), func() -> void: _pick_civ(id), 220, 80, 28)
		grid.add_child(b)
		_civ_buttons.append(b)
	v.add_child(grid)
	_civ_text = _label("", 26, INK)
	_civ_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_civ_text.custom_minimum_size = Vector2(1380 * s, 330 * s)
	v.add_child(_civ_text)
	v.add_child(_row(_primary("Start game", func() -> void:
		Defs.save_civ(_civ_pick)
		get_tree().reload_current_scene(), 380, 110, 40), _button("Back", func() -> void: _open("pause"), 300, 110, 34)))


func _open_civ_chooser() -> void:
	_pick_civ(Defs.load_civ())
	_open("civ")


func _pick_civ(c: int) -> void:
	_civ_pick = c
	for i in _civ_buttons.size():
		var b: Button = _civ_buttons[i]
		b.modulate = Color(1.25, 1.1, 0.8) if i + 1 == c else Color(1, 1, 1, 0.8)
	var t: String = Rules.raw.civ_info[c - 1].text
	var lines := PackedStringArray()
	for ln in t.split("\n"):
		lines.append(ln.strip_edges())
	_civ_text.text = "\n".join(lines).replace("\n\n\n", "\n\n")


func _scale_index() -> int:
	return 0 if ui_scale < 0.9 else (1 if ui_scale < 1.1 else 2)


func _set_difficulty(i: int) -> void:
	map.difficulty = Defs.DIFFICULTY_ORDER[i]
	Defs.save_difficulty(map.difficulty)
	map.director.on_difficulty_changed()
	_mark_segment(_diff_seg, i)


func _set_opponent(i: int) -> void:
	Defs.save_opponent(Defs.OPPONENTS[i])
	_mark_segment(_opp_seg, i)


func _set_chatter(i: int) -> void:
	Chatter.enabled = i == 0
	Defs.save_chatter(Chatter.enabled)
	_mark_segment(_chatter_seg, i)


func _set_tombs(i: int) -> void:
	Tombstone.enabled = i == 0
	Defs.save_tombs(Tombstone.enabled)
	_mark_segment(_tomb_seg, i)


func _set_scale(i: int) -> void:
	ui_scale = [0.85, 1.0, 1.2][i]
	Defs.save_ui_scale(ui_scale)
	_build_all()
	_open("settings")


func _slider_row(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(20 * s))
	var label := _label(String(Sfx.LABELS[key]), 28)
	label.custom_minimum_size = Vector2(340 * s, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var sl := TouchSlider.new()
	sl.setup(Sfx.get_volume(key), 32.0 * s)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var pct := _label("%d%%" % roundi(Sfx.get_volume(key) * 100.0), 28)
	pct.custom_minimum_size = Vector2(100 * s, 0)
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pct)
	sl.value_changed.connect(func(val: float) -> void:
		Sfx.set_volume(key, val)
		pct.text = "%d%%" % roundi(val * 100.0))
	# let go of the slider: play a sample of that kind of sound
	sl.drag_ended.connect(func() -> void:
		Sfx.play({"Combat": "sword", "Work": "chop", "Alerts": "done", "Master": "sword"}.get(key, ""), 0.0))
	return row


func _build_debug() -> void:
	var v := _modal("debug", "Debug", 900, Color(1.0, 0.55, 0.4))
	v.add_child(_row(_button("+500 of every\nresource", func() -> void:
		for r: String in Defs.RES_NAMES:
			map.stock[r] += 500
		show_toast("+500 of every resource"), 300, 120, 28), _button("Raid now", func() -> void:
		_close_modal()
		if map.rival:
			map.rival.attack_now()
		else:
			map.director.raid(), 300, 120, 28)))
	v.add_child(_row(_button("Next age\n(instant)", func() -> void:
		if map.tech.age() >= 3:
			show_toast("Already in the Imperial Age")
			return
		map.finish_research(101 + map.tech.age()), 300, 120, 28)))
	_attacks_btn = _button("", _toggle_attacks, 300, 120, 28)
	v.add_child(_row(_attacks_btn, _button("Spawn wild\nanimals here", func() -> void:
		var c := Iso.to_cell(ctl.cam.position)
		for i in 2:
			map.director.spawn_wild_pack((c + Vector2i(randi_range(-8, 8), randi_range(-8, 8))).clamp(Vector2i(3, 3), Vector2i(map.size - 4, map.size - 4)))
		_close_modal()
		show_toast("Wild animals appeared nearby"), 300, 120, 28)))
	v.add_child(_section("Game speed"))
	_speed_seg = _segmented(["x1", "x2", "x4"], 0, _set_speed)
	v.add_child(_speed_seg)
	v.add_child(_primary("Close", _close_modal, 300, 100, 34))


var _barter_box: VBoxContainer


## The Market's trade window: sell 100 or buy 100 of food, wood and stone against gold, at today's price.
func _build_barter() -> void:
	_barter_box = _modal("barter", "Market", 900, GOLD)


func _open_barter() -> void:
	_fill_barter()
	_open("barter")


func _fill_barter() -> void:
	for c in _barter_box.get_children():
		c.queue_free()
	var fee := roundi(map.barter_fee() * 100.0)
	_barter_box.add_child(_label("You have %d gold. Trading fee %d%%; prices move with every trade." % [map.stock.gold, fee], 26, DIM))
	for r: String in ["food", "wood", "stone"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(14 * s))
		row.add_child(Glyph.make(r, 56 * s))
		var nm := _label(r.capitalize(), 30, INK)
		nm.custom_minimum_size = Vector2(150 * s, 0)
		row.add_child(nm)
		row.add_child(_button("Sell 100\nget %d gold" % map.barter_sell_gain(r), func() -> void: _trade(r, true), 330, 110, 26, Color(0.3, 0.26, 0.14)))
		row.add_child(_button("Buy 100\npay %d gold" % map.barter_buy_cost(r), func() -> void: _trade(r, false), 330, 110, 26, Color(0.3, 0.26, 0.14)))
		_barter_box.add_child(row)
	_barter_box.add_child(_primary("Close", _close_modal, 300, 100, 34))


func _trade(res: String, sell: bool) -> void:
	var err := map.barter(res, sell)
	if err != "":
		show_toast(err)
	Sfx.play("done")
	_fill_barter()


func _set_speed(i: int) -> void:
	map.speed = [1.0, 2.0, 4.0][i]
	_mark_segment(_speed_seg, i)


func _toggle_attacks() -> void:
	map.attacks_paused = not map.attacks_paused
	_sync_menus()
	show_toast("Attacks paused: raids and wild animals leave you alone" if map.attacks_paused else "Attacks resumed")


func _sync_menus() -> void:
	var mi := SaveGame.info(SaveGame.MANUAL)
	_load_btn.text = "Load game\n%s" % mi if mi != "" else "Load game\nno save yet"
	_load_btn.disabled = mi == ""
	var ai := SaveGame.info(SaveGame.AUTO)
	_auto_btn.text = "Load autosave\n%s" % ai if ai != "" else "Load autosave\nnone yet"
	_auto_btn.disabled = ai == ""
	_attacks_btn.text = "Attacks: PAUSED\n(tap to resume)" if map.attacks_paused else "Attacks: ON\n(tap to pause)"
	_mark_segment(_speed_seg, 0 if map.speed < 1.5 else (1 if map.speed < 3.0 else 2))
	_mark_segment(_diff_seg, Defs.DIFFICULTY_ORDER.find(map.difficulty))


func _save_game() -> void:
	if SaveGame.write(SaveGame.MANUAL, get_parent()):
		show_toast("Game saved")
	else:
		show_toast("Could not save the game")
	_sync_menus()


func _load_slot(path: String) -> void:
	var d := SaveGame.read(path)
	if d.is_empty():
		show_toast("No saved game found")
		return
	Main.pending = d
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ confirmations
func _build_confirm() -> void:
	var v := _modal("confirm", "Are you sure?", 760, Color(1.0, 0.7, 0.5))
	var l := _label("", 34)
	l.name = "text"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var yes := _danger("Yes", func() -> void:
		var cb := _confirm_yes
		_close_modal()
		if cb.is_valid():
			cb.call(), 320, 120, 32)
	yes.name = "yes"
	v.add_child(_row(yes, _button("No", func() -> void: _open(_confirm_back), 320, 120, 34)))


func _ask(text: String, yes_label: String, yes: Callable, back := "") -> void:
	var box: VBoxContainer = _modals.confirm.box
	(box.get_node("text") as Label).text = text
	((box.get_child(2) as HBoxContainer).get_node("yes") as Button).text = yes_label
	_confirm_yes = yes
	_confirm_back = back
	_open("confirm")


func _ask_deconstruct() -> void:
	var b := ctl.sel_b
	if b == null or not b.alive or b.kind == "tc":
		return
	_decon_target = b
	var refund := b.refund_cost()
	var text := "Deconstruct the %s?" % b.title()
	text += "\nYou get back %s." % Defs.cost_text(refund) if not refund.is_empty() else "\nNothing is refunded."
	_ask(text, "Yes, deconstruct", _do_deconstruct, "")


func _do_deconstruct() -> void:
	var b := _decon_target
	_decon_target = null
	if b == null or not is_instance_valid(b) or not b.alive:
		return
	var text := map.deconstruct(b)
	ctl.clear_selection()
	show_toast(text)


# ------------------------------------------------------------------ game over
func _build_over() -> void:
	var v := _modal("over", "Defeat", 760, Color(1.0, 0.45, 0.35))
	v.add_child(_label("Your last Town Center has fallen.", 34))
	_over_stats = _label("", 30, DIM)
	v.add_child(_over_stats)
	v.add_child(_primary("New game", _open_civ_chooser, 300, 120, 38))
	_over_auto = _button("Load autosave", func() -> void: _load_slot(SaveGame.AUTO), 300, 100, 30)
	v.add_child(_over_auto)


func _build_victory() -> void:
	var v := _modal("victory", "Victory!", 760, GOLD)
	v.add_child(_label("The rival's base lies in ruins.", 34))
	_win_stats = _label("", 30, DIM)
	v.add_child(_win_stats)
	v.add_child(_primary("Keep playing", _close_modal, 300, 120, 38))
	v.add_child(_button("New game", _open_civ_chooser, 300, 100, 30))


func _on_victory() -> void:
	var t := int(map.game_time)
	_win_stats.text = "You won after %d:%02d, against %d attack waves." % [t / 60, t % 60, map.rival.wave if map.rival else 0]
	_open("victory")


func _on_game_over() -> void:
	var t := int(map.game_time)
	var waves := map.rival.wave if map.rival else map.director.wave
	_over_stats.text = "You lasted %d:%02d and survived %d %s." % [t / 60, t % 60, waves, "attacks" if map.rival else "raids"]
	_over_auto.visible = SaveGame.exists(SaveGame.AUTO)
	_open("over")


# ------------------------------------------------------------------ notifications
func _classify(text: String) -> String:
	var t := text.to_lower()
	if "raid!" in t or "destroyed" in t or "under attack" in t:
		return "danger"
	if "not enough" in t or "limit" in t or "can't" in t or "needs " in t or "need a " in t or "no villager" in t or "could not" in t or "no saved" in t or "no drop" in t or "full" in t:
		return "warn"
	if "ready" in t or "done" in t or "deconstructed" in t or "saved" in t or "found" in t or "finished" in t or "second villager" in t or "upgrad" in t:
		return "good"
	return "info"


func show_toast(text: String, kind := "") -> void:
	if kind == "":
		kind = _classify(text)
	for e: Dictionary in _toasts:
		if e.text == text:
			e.t = 4.0
			return
	var col: Color = {"danger": DANGER, "warn": WARN, "good": GOOD, "info": GOLD}[kind]
	var glyph: String = {"danger": "warn", "warn": "warn", "good": "check", "info": "info"}[kind]
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _box(Color(0.08, 0.06, 0.04, 0.97), 30, col, 5, 30, 18))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(18 * s))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var g := Glyph.make(glyph, 50 * s, col)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(g)
	var l := _label(text, 38)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(900.0 * s, get_viewport().get_visible_rect().size.x * 0.6), 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	toast_box.add_child(p)
	_toasts.append({"node": p, "t": 4.0 if kind != "danger" else 5.5, "text": text})
	while _toasts.size() > 3:
		var old: Dictionary = _toasts.pop_front()
		old.node.queue_free()


func _on_attacked(tile: Vector2) -> void:
	minimap.ping(tile)
	if map.game_time - _last_attack_toast > 15.0:
		_last_attack_toast = map.game_time
		show_toast("You are under attack!", "danger")


# ------------------------------------------------------------------ input
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back_pressed()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_back_pressed()
		get_viewport().set_input_as_handled()


## The Android back button / Escape: close what is open, otherwise open the pause menu.
func _back_pressed() -> void:
	if _open_modal == "settings":
		_open("pause")
	elif _open_modal == "confirm":
		_open(_confirm_back)
	elif _open_modal == "over":
		pass
	elif _open_modal != "":
		_close_modal()
	elif ctl.placing != "":
		ctl.cancel_pressed()
	else:
		_open("pause")


func blocks(p: Vector2) -> bool:
	if AppRuntime.blocks(p):
		return true
	if _open_modal != "":
		return true
	for c: Control in [top, bottom, place_bar]:
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return false


# ------------------------------------------------------------------ per-frame
func _process(dt: float) -> void:
	_pulse += dt
	for r: String in Defs.RES_NAMES:
		_res_labels[r].text = "∞" if AppRuntime.cheats.enabled(r) else str(map.stock[r])
	var capped := map.pop >= map.pop_cap
	pop_label.text = "%d/%d" % [map.pop, map.pop_cap]
	pop_label.add_theme_color_override("font_color", (DANGER if int(_pulse * 3.0) % 2 == 0 else INK) if capped else INK)
	age_label.text = "%s · %s" % [Defs.civ_name(map.civ), Rules.AGE_NAMES[map.tech.age()]]
	var t := int(map.game_time)
	clock_label.text = "%d:%02d" % [t / 60, t % 60]
	speed_label.text = "x%d" % int(map.speed) if map.speed > 1.01 else ""
	# toasts fade in their last second
	for i in range(_toasts.size() - 1, -1, -1):
		var e: Dictionary = _toasts[i]
		e.t -= dt
		e.node.modulate.a = clampf(e.t, 0.0, 1.0)
		if e.t <= 0.0:
			e.node.queue_free()
			_toasts.remove_at(i)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = 0.3
		_sync(false)


func _sync(force: bool) -> void:
	ctl.prune()
	if ctl.placing == "" and _sig() != _cmd_sig:
		refresh_commands()
	_update_costs()
	_update_raid()
	_update_idle_badge()
	_update_card()
	if ctl.placing != "":
		place_label.text = ctl.place_text()


func _update_raid() -> void:
	var enemies := 0
	for m in map.mobs:
		if m.team == 1 and m.alive and not m is FoeVillager and not (map.rival and m is Soldier and m.foe_mode == "guard"):
			enemies += 1
	var col := INK
	var glyph_col := WARN
	var text := ""
	var show_glyph := true
	if map.attacks_paused:
		text = "Attacks paused"
		col = DIM
		show_glyph = false
	elif enemies > 0:
		text = "%d %s!" % [enemies, "attackers" if map.rival else "raiders"]
		col = DANGER if int(_pulse * 3.0) % 2 == 0 else INK
		glyph_col = DANGER
	elif map.rival:
		text = "Rival: %s" % Rules.AGE_NAMES[map.rival.age]
		show_glyph = false
	else:
		var n := int(ceil(map.director.next_raid))
		text = "Raid %d in %d:%02d" % [map.director.wave + 1, n / 60, n % 60]
		if n <= 15:
			col = DANGER if int(_pulse * 3.0) % 2 == 0 else INK
			glyph_col = DANGER
		elif n <= 60:
			col = WARN
	raid_label.text = text
	raid_label.add_theme_color_override("font_color", col)
	raid_glyph.tint = glyph_col
	raid_glyph.visible = show_glyph
	raid_glyph.queue_redraw()


func _update_idle_badge() -> void:
	var idle := 0
	for m in map.mobs:
		if m is Villager and m.alive and m.team == 0 and m.is_idle():
			idle += 1
	idle_badge.visible = idle > 0
	idle_badge_label.text = str(idle)


# ------------------------------------------------------------------ the selection card
func _update_card() -> void:
	var title := ""
	var icon_key := ""
	var icon_fn := Callable()
	var hp := -1.0
	var hp_max := 1.0
	var prog := -1.0
	var prog_text := ""
	var body := ""
	var us := ctl.sel_units
	var b := ctl.sel_b
	if us.size() == 1:
		var u := us[0]
		title = String(u.def.get("name", u.kind))
		hp = u.hp
		hp_max = u.max_hp
		if u is Villager:
			body = _cap(u.status_text())
			icon_key = "u:villager"
			icon_fn = func() -> Control: return _unit_icon("villager")
		elif u is Ship:
			body = "Fishing ship, %s.\nTap a school of fish to fish it, or open water to sail." % u.status_text()
			icon_key = "u:" + String(u.kind)
			var sk: String = u.kind
			icon_fn = func() -> Control: return _unit_icon(sk)
		else:
			body = "Tap an enemy to attack, or the ground to move."
			if u is Soldier and u.healer:
				body = "Monk, %s.\nHeals the wounded by himself. Tap an enemy to convert it, a relic to carry it, then your Monastery." % u.status_text()
			if u is Soldier and u.team == 0:
				icon_key = "u:" + String(u.kind)
				var k: String = u.kind
				icon_fn = func() -> Control: return _unit_icon(k)
	elif us.size() > 1:
		var soldiers := 0
		for u in us:
			if u is Soldier:
				soldiers += 1
		title = "%d units" % us.size()
		body = "%d villagers, %d soldiers.\nTap the ground to move, a resource or building site to work, an enemy to attack." % [us.size() - soldiers, soldiers]
		icon_key = "g:villager"
		icon_fn = func() -> Control: return Glyph.make("villagers", 1, Color(0.55, 0.8, 1.0))
	elif ctl.sel_res:
		var r := ctl.sel_res
		title = r.label()
		body = "%d %s left.\nSelect a villager, then tap it to gather." % [r.amount, r.kind]
		icon_key = "g:" + String(r.kind)
		var rk: String = r.kind
		icon_fn = func() -> Control: return Glyph.make(rk, 1)
	elif b:
		title = b.title()
		hp = b.hp
		hp_max = b.max_hp
		icon_key = "b:%s:%d:%d" % [b.kind, b.level, map.tech.age()]
		icon_fn = func() -> Control:
			if b.look_key() != "":
				return _tex_rect(Assets.tex(b._img().file))
			return _building_icon(b.kind)
		if not b.done:
			prog = b.work / b.work_needed
			prog_text = "Under construction %d%%" % int(prog * 100.0)
		elif b.res_tech >= 0:
			prog = b.res_t / b.research_time()
			prog_text = "Researching %s %d%%" % [Rules.techs[b.res_tech].name, int(prog * 100.0)]
		elif not b.queue.is_empty():
			var u := map.unit_info(b.queue[0])
			prog = b.qt / float(u.time)
			prog_text = "Training %s %d%%" % [u.name, int(prog * 100.0)] + ("  (+%d queued)" % (b.queue.size() - 1) if b.queue.size() > 1 else "")
		body = _building_text(b) + _garrison_text(b)
	else:
		title = "Your village"
		icon_key = "g:pop"
		icon_fn = func() -> Control: return Glyph.make("pop", 1)
		body = _village_text()
	card_title.text = title
	if icon_key != _sel_sig:
		_sel_sig = icon_key
		for c in card_icon_holder.get_children():
			c.queue_free()
		if icon_fn.is_valid():
			var icon: Control = icon_fn.call()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			card_icon_holder.add_child(icon)
	card_hp.visible = hp >= 0.0
	if hp >= 0.0:
		var f := clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)
		card_hp.value = f
		card_hp.add_theme_stylebox_override("fill", _box(Color(1.0 - f, 0.25 + 0.65 * f, 0.15), 8, Color(0, 0, 0, 0), 0, 0, 0))
		card_hp_text.text = "%d / %d" % [ceili(hp), int(hp_max)]
	card_prog.visible = prog >= 0.0
	if prog >= 0.0:
		card_prog.value = clampf(prog, 0.0, 1.0)
		card_prog_text.text = prog_text
	card_body.text = body


func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t


func _village_text() -> String:
	if map.game_time < 240.0:
		return "Tap a villager, then a tree, bush, mine or the ground.\nDrag to scroll, pinch to zoom. Double-tap and draw a loop round units to select them. Build a Barracks and Towers before the raids."
	var vill := 0
	var soldiers := 0
	for m in map.mobs:
		if m.team == 0 and m.alive:
			if m is Villager:
				vill += 1
			else:
				soldiers += 1
	var bld := 0
	for b in map.buildings:
		if b.done and b.alive:
			bld += 1
	return "%d villagers, %d soldiers, %d buildings." % [vill, soldiers, bld]


func _garrison_text(b: Building) -> String:
	var cap := b.garrison_cap()
	if not b.done or cap <= 0:
		return ""
	var t := "\nGarrison %d / %d" % [b.garrison.size(), cap]
	if b.def.get("shoots", false) and b.garrison_arrows() > 0:
		t += ", +%d arrows" % b.garrison_arrows()
	return t + ". Select soldiers, then tap it to garrison."


func _building_text(b: Building) -> String:
	if not b.done:
		return "Send villagers to build it."
	if b.kind == "gate":
		return "Your units walk through it, enemies must break it down. %s" % ("Locked: shut for everybody." if b.locked else "Lock it to keep your own units in.")
	if b.kind == "farm":
		return "%d food left." % int(b.food)
	if b.kind == "dock":
		return "Trains fishing ships and warships; fishing ships bring their catch here. Research shipbuilding here."
	if b.kind in ["barracks", "archery_range", "stable"]:
		return "Trains soldiers. Research upgrades here."
	if b.kind == "blacksmith":
		return "Attack and armor upgrades for your soldiers."
	if b.kind == "university":
		return "Tower and wall upgrades."
	if b.kind == "house":
		return "Houses %d villagers." % b.pop_value()
	if b.kind == "tc":
		return "%s. Houses %d. Research ages and economy technologies here." % [Rules.AGE_NAMES[map.tech.age()], b.pop_value()]
	if b.kind == "monastery":
		var rel := "" if b.relics.is_empty() else "\nRelics inside: %d, +%.1f gold per second." % [b.relics.size(), b.relics.size() * Relic.GOLD_RATE * Rules.GAME_SPEED]
		return "Trains monks, who heal and convert. Research faith and healing here. A monk can bring a relic: it pays gold while it stays." + rel
	if b.kind == "siege_workshop":
		return "Rams, mangonels and other siege. Research upgrades here."
	if b.kind == "market":
		return "Trade resources for gold and research commerce."
	if b.def.get("shoots", false):
		return "%d arrow%s per volley, range %d." % [b.tower_shots(), "s" if b.tower_shots() > 1 else "", int(b.range_t)]
	if b.def.has("drop"):
		return "Drop-off for %s. Research better tools here." % " and ".join(b.def.drop)
	return ""
