class_name Hud
extends CanvasLayer
## 게임 화면 UI 전부. 모양은 hud.tscn 에 있고, 여기선 내용만 채운다.

const SLOT := preload("res://scenes/ui/slot.tscn")
const RECIPE_ROW := preload("res://scenes/ui/recipe_row.tscn")
const NEED_ROW := preload("res://scenes/ui/need_row.tscn")
const TOAST := preload("res://scenes/ui/toast.tscn")

var player: Player
var map_dirty := true
var _open := ""
var _station := ""
var _chest_id := -1
var _ship_id := -1
var _cursor := {}
var _sel_recipe := -1
var _hot_slots: Array = []
var _inv_slots := {}      # inv index -> Slot (가방 창)
var _chest_slots: Array = []
var _chestbag_slots: Array = []
var _slow_t := 0.0
var _pickup_rows := {}
var _chat_open := false

@onready var clock_label: Label = %Clock
@onready var hp_bar: ProgressBar = %HpBar
@onready var food_bar: ProgressBar = %FoodBar
@onready var water_bar: ProgressBar = %WaterBar
@onready var hotbar: HBoxContainer = %Hotbar
@onready var held_name: Label = %HeldName
@onready var prompt: Label = %Prompt
@onready var progress_box: VBoxContainer = %ProgressBox
@onready var progress_label: Label = %ProgressLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var toasts: VBoxContainer = %Toasts
@onready var pickups_box: VBoxContainer = %Pickups
@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var player_list: RichTextLabel = %PlayerList
@onready var tracker: RichTextLabel = %Tracker
@onready var fish_alert_label: Label = %FishAlert
@onready var downed_label: Label = %DownedLabel
@onready var sleep_overlay: ColorRect = %SleepOverlay
@onready var boss_box: VBoxContainer = %BossBox
@onready var boss_bar: ProgressBar = %BossBar
@onready var underwater: ColorRect = %Underwater
@onready var hurt_rect: ColorRect = %HurtRect
@onready var fps_label: Label = %FPS
@onready var cursor_slot: Slot = %CursorSlot
@onready var tooltip: PanelContainer = %Tooltip
@onready var tooltip_text: RichTextLabel = %TooltipText
@onready var game_ui: Control = %GameUI
# 창들
@onready var inv_panel: PanelContainer = %InvPanel
@onready var bag_grid: GridContainer = %BagGrid
@onready var hot_grid: GridContainer = %HotGrid
@onready var craft_title: Label = %CraftTitle
@onready var show_all: CheckButton = %ShowAll
@onready var recipe_list: VBoxContainer = %RecipeList
@onready var recipe_detail: RichTextLabel = %RecipeDetail
@onready var craft_btn: Button = %CraftBtn
@onready var craft5_btn: Button = %Craft5Btn
@onready var chest_panel: PanelContainer = %ChestPanel
@onready var chest_grid: GridContainer = %ChestGrid
@onready var chest_bag_grid: GridContainer = %ChestBagGrid
@onready var ship_panel: PanelContainer = %ShipPanel
@onready var ship_parts: VBoxContainer = %ShipParts
@onready var depart_btn: Button = %DepartBtn
@onready var journal: PanelContainer = %Journal
@onready var routes_text: RichTextLabel = get_node("%루트")
@onready var note_list: ItemList = %NoteList
@onready var note_text: RichTextLabel = %NoteText
@onready var stats_text: RichTextLabel = get_node("%기록")
@onready var map_panel: PanelContainer = %MapPanel
@onready var map_view: Control = %MapView
@onready var note_panel: PanelContainer = %NotePanel
@onready var note_title: Label = %NoteTitle
@onready var note_body: RichTextLabel = %NoteBody
@onready var pause_panel: PanelContainer = %PausePanel
@onready var invite_text: RichTextLabel = %InviteText
@onready var settings: Control = %Settings
@onready var loading: ColorRect = %Loading
@onready var loading_label: Label = %LoadingLabel
@onready var fatal_rect: ColorRect = %Fatal
@onready var fatal_label: Label = %FatalLabel
@onready var ending: ColorRect = %Ending
@onready var end_title: Label = %EndTitle
@onready var end_body: RichTextLabel = %EndBody


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 9:
		var s: Slot = SLOT.instantiate()
		hotbar.add_child(s)
		s.index = i
		s.set_key(str(i + 1))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hot_slots.append(s)
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		_inv_slots[i] = _new_slot(bag_grid, i, _on_inv_slot)
	for i in Inventory.HOTBAR:
		_inv_slots[i] = _new_slot(hot_grid, i, _on_inv_slot)
		_inv_slots[i].set_key(str(i + 1))
	for i in Structs.CHEST_SLOTS:
		_chest_slots.append(_new_slot(chest_grid, i, _on_chest_slot))
	for i in Inventory.SIZE:
		_chestbag_slots.append(_new_slot(chest_bag_grid, i, _on_chestbag_slot))
	cursor_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in cursor_slot.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	craft_btn.pressed.connect(_craft.bind(1))
	craft5_btn.pressed.connect(_craft.bind(5))
	show_all.toggled.connect(func(_on): _rebuild_recipes())
	depart_btn.pressed.connect(_on_depart)
	note_list.item_selected.connect(_on_note_selected)
	%NoteClose.pressed.connect(func(): _set_open(""))
	%ResumeBtn.pressed.connect(func(): _set_open(""))
	%SettingsBtn.pressed.connect(func(): _set_open("settings"))
	%SaveQuitBtn.pressed.connect(func(): Game.I.leave_to_title())
	%FatalBtn.pressed.connect(func(): Game.I.leave_to_title())
	%EndContinue.pressed.connect(_on_end_continue)
	%EndTitleBtn.pressed.connect(func(): Game.I.leave_to_title())
	settings.closed.connect(func(): _set_open("pause"))
	chat_input.text_submitted.connect(_on_chat_submit)
	(get_node("%조작법") as RichTextLabel).text = _help_text()
	_set_open("")
	loading.visible = true
	fatal_rect.visible = false
	ending.visible = false
	sleep_overlay.visible = false
	downed_label.visible = false
	fish_alert_label.visible = false
	progress_box.visible = false
	boss_box.visible = false
	underwater.visible = false
	hurt_rect.color.a = 0.0
	tooltip.visible = false
	cursor_slot.visible = false
	chat_input.visible = false


func _new_slot(parent: Control, idx: int, cb: Callable) -> Slot:
	var s: Slot = SLOT.instantiate()
	parent.add_child(s)
	s.index = idx
	s.slot_clicked.connect(cb)
	s.slot_hovered.connect(_on_slot_hover.bind(s))
	return s


func bind_player(p: Player) -> void:
	player = p
	refresh_inventory()
	# 첫날 아침에만 조작 안내를 띄운다 (가방을 열거나 1분 지나면 사라짐)
	var keys: Control = %Keys
	keys.visible = Game.I.clock.day == 1 and Game.I.clock.hour < 9.0
	if keys.visible:
		get_tree().create_timer(60.0).timeout.connect(func(): keys.visible = false)


func blocks_game_input() -> bool:
	return _open != "" or _chat_open or loading.visible or fatal_rect.visible


# ═════════ 입력 ═════════

func _unhandled_input(event: InputEvent) -> void:
	if player == null or fatal_rect.visible or loading.visible:
		return
	if Game.I.ending_playing and _open == "":
		return   # 오프닝/엔딩 연출 중
	# 마우스가 풀려 있으면(웹에서 Esc, 창 전환 등) 화면을 한 번 클릭해 다시 잡는다
	if event is InputEventMouseButton and event.pressed and _open == "" and not _chat_open \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if _chat_open:
		if event.is_action_pressed("pause"):
			_close_chat()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if Game.I.ending_playing and _open == "":
			return
		_set_open("" if _open != "" else "pause")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		_set_open("" if _open in ["inv", "chest", "ship"] else "inv")
		if _open == "inv":
			_station = _nearest_station()
			_rebuild_recipes()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal") and _open in ["", "journal"]:
		_set_open("" if _open == "journal" else "journal")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and _open in ["", "map"]:
		_set_open("" if _open == "map" else "map")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and _open == "" and Net.is_online():
		_chat_open = true
		chat_input.visible = true
		chat_input.text = ""
		chat_input.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()


func _set_open(what: String) -> void:
	if _open == "chest" and what != "chest" and _chest_id >= 0:
		Game.I.structs.req_chest.rpc_id(1, _chest_id, "close", null)
		_chest_id = -1
		Audio.play("chest_close", -6.0)
	if _open in ["inv"] and what != "inv":
		_return_cursor()
	_open = what
	# 혼자 할 때만 메뉴에서 시간이 멈춘다
	if not Net.is_online():
		get_tree().paused = what in ["pause", "settings", "note", "journal", "map"]
	inv_panel.visible = what == "inv"
	chest_panel.visible = what == "chest"
	ship_panel.visible = what == "ship"
	journal.visible = what == "journal"
	map_panel.visible = what == "map"
	note_panel.visible = what == "note"
	pause_panel.visible = what == "pause"
	settings.visible = what == "settings"
	tooltip.visible = false
	if what == "":
		if player and not Game.I.ending_playing:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Audio.play("open", -8.0)
	match what:
		"journal": _refresh_journal()
		"map": map_view.rebuild_if_dirty()
		"pause": _refresh_invite()
		"inv":
			refresh_inventory()
			(%Keys as Control).visible = false


func _nearest_station() -> String:
	for st in ["workbench", "campfire", "furnace"]:
		if player.station_near(st):
			return st
	return ""


# ═════════ 매 프레임 ═════════

func _process(delta: float) -> void:
	if player == null or Game.I == null:
		return
	hp_bar.value = player.hp
	food_bar.value = player.hunger
	water_bar.value = player.thirst
	clock_label.text = Game.I.clock.time_text() + ("  비" if Game.I.clock.raining else "")
	if hurt_rect.color.a > 0.0:
		hurt_rect.color.a = maxf(0.0, hurt_rect.color.a - delta * 1.5)
	# 체력이 낮으면 화면 가장자리가 두근두근
	if player.hp < 25.0 and not player.downed:
		hurt_rect.color.a = maxf(hurt_rect.color.a, 0.12 + 0.1 * sin(Time.get_ticks_msec() / 180.0))
	_warn(player.hunger < 20.0, "hunger", "배가 너무 고프다... 뭐라도 먹자")
	_warn(player.thirst < 20.0, "thirst", "목이 탄다... 코코넛이나 깨끗한 물!")
	food_bar.modulate = Color(1, 1, 1, 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 250.0))) if player.hunger < 20.0 else Color.WHITE
	water_bar.modulate = Color(1, 1, 1, 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 250.0))) if player.thirst < 20.0 else Color.WHITE
	if cursor_slot.visible:
		cursor_slot.position = get_viewport().get_mouse_position() - cursor_slot.size * 0.5
	if tooltip.visible:
		var mp := get_viewport().get_mouse_position() + Vector2(18, 18)
		var vs := get_viewport().get_visible_rect().size
		tooltip.position = Vector2(minf(mp.x, vs.x - tooltip.size.x - 8), minf(mp.y, vs.y - tooltip.size.y - 8))
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 0.4
		_refresh_tracker()
		_refresh_boss()
		on_players_changed()
		fps_label.visible = Settings.show_fps
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()
		if _open == "ship":
			_refresh_ship()
		if _open == "chest" and not Game.I.structs.list.has(_chest_id):
			_set_open("")
			toast("상자가 부서졌다!")
		if _open == "inv":
			var st := _nearest_station()
			if st != _station:
				_station = st
				_rebuild_recipes()
		if _open == "map":
			map_view.queue_redraw()


# ═════════ 알림 ═════════

var _warned := {}


func _warn(cond: bool, key: String, text: String) -> void:
	## 조건이 처음 참이 될 때 한 번만 알린다
	if cond and not _warned.get(key, false):
		toast(text, Color("ffb07a"))
		Audio.play("error", -6.0)
	_warned[key] = cond


func toast(text: String, col: Color = Color(1, 0.97, 0.9)) -> void:
	var t := TOAST.instantiate()
	toasts.add_child(t)
	t.show_text(text, col)
	while toasts.get_child_count() > 5:
		toasts.get_child(0).queue_free()
		toasts.remove_child(toasts.get_child(0))


func pickup_note(id: String, n: int) -> void:
	var row: Dictionary = _pickup_rows.get(id, {})
	if not row.is_empty() and is_instance_valid(row.node) and Time.get_ticks_msec() - row.t < 2500:
		row.n += n
		row.t = Time.get_ticks_msec()
		row.node.label.text = "+%d %s" % [row.n, Items.name_of(id)]
		return
	var t := TOAST.instantiate()
	pickups_box.add_child(t)
	t.show_text("+%d %s" % [n, Items.name_of(id)], Color("c8f7c5"), 2.0)
	_pickup_rows[id] = {"node": t, "n": n, "t": Time.get_ticks_msec()}
	while pickups_box.get_child_count() > 6:
		var c := pickups_box.get_child(0)
		pickups_box.remove_child(c)
		c.queue_free()


func set_prompt(text: String) -> void:
	if prompt.text != text:
		prompt.text = text


func set_progress(text: String, frac: float) -> void:
	progress_box.visible = frac >= 0.0
	progress_label.text = text
	progress_bar.value = clampf(frac, 0, 1) * 100.0


func set_downed(on: bool, secs: float) -> void:
	downed_label.visible = on
	if on:
		var alone := Game.I.players.size() <= 1
		downed_label.text = "기절!\n%s" % ("..." if alone else "친구가 살려주길 기다리는 중 (%d초)" % int(ceil(secs)))


func set_sleeping(on: bool) -> void:
	sleep_overlay.visible = on


func set_underwater(on: bool) -> void:
	if underwater.visible != on:
		underwater.visible = on


func hurt_flash() -> void:
	hurt_rect.color.a = 0.45


func fish_alert(on: bool) -> void:
	fish_alert_label.visible = on


func show_loading(text: String) -> void:
	loading.visible = true
	loading_label.text = text


func hide_loading() -> void:
	loading.visible = false
	if _open == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func fatal(text: String) -> void:
	loading.visible = false
	fatal_rect.visible = true
	fatal_label.text = text
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_note(title: String, text: String) -> void:
	note_title.text = title
	note_body.text = text
	_set_open("note")
	Audio.play("book")


# ═════════ 가방 · 제작 ═════════

func refresh_inventory() -> void:
	if player == null:
		return
	var inv := player.inv
	for i in 9:
		_hot_slots[i].set_item(inv.slots[i])
		_hot_slots[i].set_selected(i == player.hotbar_i)
	for i in _inv_slots:
		_inv_slots[i].set_item(inv.slots[i])
	for i in _chestbag_slots.size():
		_chestbag_slots[i].set_item(inv.slots[i])
	held_name.text = Items.name_of(player.held_id) if player.held_id != "" else ""
	if _open == "inv":
		_rebuild_recipes()


func open_inventory(station: String) -> void:
	_set_open("inv")
	_station = station
	_rebuild_recipes()


func _rebuild_recipes() -> void:
	if player == null:
		return
	var st_name: String = Items.STATION_NAMES.get(_station, "")
	craft_title.text = "제작 - 맨손" + ("" if _station == "" else " + " + st_name)
	for c in recipe_list.get_children():
		c.queue_free()
	var rows := []
	for i in Items.RECIPES.size():
		var r: Dictionary = Items.RECIPES[i]
		var station_ok := player.station_near(r.at)
		if not station_ok and not show_all.button_pressed:
			continue
		rows.append([i, r, player.can_craft(r), station_ok])
	# 만들 수 있는 것 먼저
	rows.sort_custom(func(a, b): return int(a[2]) > int(b[2]) if a[2] != b[2] else a[0] < b[0])
	for row in rows:
		var rr := RECIPE_ROW.instantiate()
		recipe_list.add_child(rr)
		rr.setup(row[0], row[1], row[2], row[3])
		rr.button_pressed = row[0] == _sel_recipe
		rr.pressed.connect(_select_recipe.bind(row[0]))
	_show_recipe_detail()


func _select_recipe(idx: int) -> void:
	_sel_recipe = idx
	for c in recipe_list.get_children():
		c.button_pressed = c.recipe_index == idx
	_show_recipe_detail()
	Audio.play("click", -10.0)


func _show_recipe_detail() -> void:
	if _sel_recipe < 0 or player == null:
		recipe_detail.text = "[color=#d8c8a8]왼쪽에서 만들 것을 골라 줘.\n작업대/모닥불/화덕 근처에서는 더 많은 걸 만들 수 있어.[/color]"
		craft_btn.disabled = true
		craft5_btn.disabled = true
		return
	var r: Dictionary = Items.RECIPES[_sel_recipe]
	var t := "[font_size=24][color=#ffe08a]%s[/color][/font_size]%s\n" % [Items.name_of(r.out), "" if r.n <= 1 else " x%d" % r.n]
	t += "[color=#d8c8a8]%s[/color]\n" % Items.item(r.out).get("desc", "")
	for id in r.in:
		var have := player.inv.count(id)
		var col := "#9df59a" if have >= r.in[id] else "#ff8a7a"
		t += "[color=%s]★ %s  %d/%d[/color]\n" % [col, Items.name_of(id), have, r.in[id]]
	if r.at != "":
		var ok := player.station_near(r.at)
		t += "[color=%s]★ %s 근처에서[/color]" % ["#9df59a" if ok else "#ff8a7a", Items.STATION_NAMES[r.at]]
	recipe_detail.text = t
	craft_btn.disabled = not player.can_craft(r)
	craft5_btn.disabled = craft_btn.disabled


func _craft(times: int) -> void:
	if _sel_recipe < 0:
		return
	var r: Dictionary = Items.RECIPES[_sel_recipe]
	if player.craft(r, times) == 0:
		Audio.play("error")
	_rebuild_recipes()


func _on_inv_slot(idx: int, button: int, shift: bool) -> void:
	var inv := player.inv
	var s = inv.slots[idx]
	if shift and _cursor.is_empty():
		if s == null:
			return
		var taken := inv.take_slot(idx)
		var range_arr: Array = inv.slots.slice(Inventory.HOTBAR) if idx < Inventory.HOTBAR else inv.slots.slice(0, Inventory.HOTBAR)
		var left := Inventory.add_to_slots(range_arr, taken.id, taken.n, taken.get("d", -1))
		var off := Inventory.HOTBAR if idx < Inventory.HOTBAR else 0
		for i in range_arr.size():
			inv.slots[off + i] = range_arr[i]
		if left > 0:
			taken.n = left
			inv.slots[idx] = taken
		inv.changed.emit()
		Audio.play("click", -10.0)
		return
	if button == MOUSE_BUTTON_LEFT:
		if _cursor.is_empty():
			if s != null:
				_cursor = inv.take_slot(idx)
		elif s == null:
			inv.slots[idx] = _cursor
			_cursor = {}
		elif s.id == _cursor.id and Items.max_stack(s.id) > 1:
			var room: int = Items.max_stack(s.id) - s.n
			var put: int = mini(room, _cursor.n)
			s.n += put
			_cursor.n -= put
			if _cursor.n <= 0:
				_cursor = {}
		else:
			inv.slots[idx] = _cursor
			_cursor = s
	elif button == MOUSE_BUTTON_RIGHT:
		if _cursor.is_empty():
			if s != null:
				_cursor = inv.take_slot(idx, int(ceil(s.n / 2.0)))
		elif s == null:
			var one := _cursor.duplicate()
			one.n = 1
			inv.slots[idx] = one
			_cursor.n -= 1
			if _cursor.n <= 0:
				_cursor = {}
		elif s.id == _cursor.id and s.n < Items.max_stack(s.id):
			s.n += 1
			_cursor.n -= 1
			if _cursor.n <= 0:
				_cursor = {}
	inv.changed.emit()
	_update_cursor()
	Audio.play("click", -12.0)


func _update_cursor() -> void:
	cursor_slot.visible = not _cursor.is_empty()
	if cursor_slot.visible:
		cursor_slot.set_item(_cursor)


func _return_cursor() -> void:
	if _cursor.is_empty() or player == null:
		return
	player.receive(_cursor.id, _cursor.n, _cursor.get("d", -1))
	_cursor = {}
	_update_cursor()


func _on_slot_hover(idx: int, inside: bool, s: Slot) -> void:
	if not inside or s.item_id == "":
		tooltip.visible = false
		return
	var d := Items.item(s.item_id)
	var t := "[font_size=22][color=#ffe08a]%s[/color][/font_size]\n[color=#e8dcc8]%s[/color]" % [d.get("name", s.item_id), d.get("desc", "")]
	if d.has("food"):
		var f: Dictionary = d.food
		var parts: Array = []
		if f.get("hunger", 0) != 0: parts.append("배고픔 %+d" % f.hunger)
		if f.get("thirst", 0) != 0: parts.append("목마름 %+d" % f.thirst)
		if f.get("hp", 0) != 0: parts.append("체력 %+d" % f.hp)
		t += "\n[color=#9df59a]우클릭: 먹기 (%s)[/color]" % ", ".join(parts)
	if d.has("block") or d.has("struct"):
		t += "\n[color=#a8e4ff]손에 들고 우클릭: 설치[/color]"
	tooltip_text.text = t
	tooltip.visible = true


# ═════════ 상자 ═════════

func open_chest(id: int) -> void:
	_chest_id = id
	_set_open("chest")
	var items: Array = Game.I.structs.list[id].data.get("items", [])
	on_chest_view(id, items)
	refresh_inventory()
	Game.I.structs.req_chest.rpc_id(1, id, "open", null)


func on_chest_view(id: int, items: Array) -> void:
	if id != _chest_id:
		return
	for i in _chest_slots.size():
		_chest_slots[i].set_item(items[i] if i < items.size() else null)


func _on_chest_slot(idx: int, _button: int, _shift: bool) -> void:
	if _chest_id >= 0:
		Game.I.structs.req_chest.rpc_id(1, _chest_id, "take", idx)
		Audio.play("click", -10.0)


func _on_chestbag_slot(idx: int, _button: int, _shift: bool) -> void:
	if _chest_id < 0:
		return
	var s := player.inv.take_slot(idx)
	if s.is_empty():
		return
	Game.I.structs.req_chest.rpc_id(1, _chest_id, "put", {"id": s.id, "n": s.n, "d": s.get("d", -1)})
	Audio.play("click", -10.0)


# ═════════ 조선소 ═════════

func open_shipyard(id: int) -> void:
	_ship_id = id
	_set_open("ship")
	_refresh_ship()


func _refresh_ship() -> void:
	if not Game.I.structs.list.has(_ship_id):
		_set_open("")
		return
	var d: Dictionary = Game.I.structs.list[_ship_id].data
	for c in ship_parts.get_children():
		c.queue_free()
	for part in Structs.SHIP_PARTS:
		var def: Dictionary = Structs.SHIP_PARTS[part]
		var title := Label.new()
		title.text = ("★ " if Game.I.structs.part_done(_ship_id, part) else "☆ ") + def.name
		title.add_theme_color_override("font_color", Color("9df59a") if Game.I.structs.part_done(_ship_id, part) else Color("ffe08a"))
		ship_parts.add_child(title)
		for item in def.need:
			var need: int = def.need[item]
			var have_in: int = d.parts[part].get(item, 0)
			var mine := _count_for(item)
			var row := NEED_ROW.instantiate()
			ship_parts.add_child(row)
			var nm := "익힌 음식 (아무거나)" if item == "cooked" else Items.name_of(item)
			row.setup(part, item, "   %s  %d/%d" % [nm, have_in, need], mine, have_in >= need)
			row.give_pressed.connect(_ship_give)
	var ready: bool = Game.I.structs.ship_ready(_ship_id)
	depart_btn.disabled = not ready
	depart_btn.text = "모두 모였다! 출항!" if ready else "아직 배가 완성되지 않았다"


func _count_for(item: String) -> int:
	if item == "cooked":
		var n := 0
		for c in Structs.COOKED:
			n += player.inv.count(c)
		return n
	return player.inv.count(item)


func _ship_give(part: String, item: String) -> void:
	var d: Dictionary = Game.I.structs.list[_ship_id].data
	var need: int = Structs.SHIP_PARTS[part].need[item] - d.parts[part].get(item, 0)
	if need <= 0:
		return
	var ids: Array = Structs.COOKED if item == "cooked" else [item]
	for id in ids:
		var n := mini(player.inv.count(id), need)
		if n <= 0:
			continue
		player.inv.remove(id, n)
		Game.I.structs.req_interact.rpc_id(1, _ship_id, "give", [part, id, n])
		need -= n
		if need <= 0:
			break
	Audio.play("craft")
	get_tree().create_timer(0.25).timeout.connect(_refresh_ship)


func _on_depart() -> void:
	Game.I.structs.req_interact.rpc_id(1, _ship_id, "depart", null)
	_set_open("")


# ═════════ 일지 ═════════

func _refresh_journal() -> void:
	var q := Game.I.quests
	var t := ""
	for key in ["escape", "adapt", "turtle"]:
		var r: Dictionary = Quests.ROUTES[key]
		var revealed := not r.has("reveal") or q.flag(r.reveal)
		var title: String = r.get("real_name", r.name) if revealed and q.count("tablets") > 0 else r.name
		var pr := q.route_progress(key)
		t += "[font_size=26][color=#ffe08a]%s[/color][/font_size]  [color=#d8c8a8]%s  (%d/%d)[/color]\n" % [title, r.sub, pr[0], pr[1]]
		if not revealed:
			t += "   [color=#8a8070]??? 아직 아무것도 모른다[/color]\n\n"
			continue
		var next_shown := false
		var known: bool = key != "escape" or q.flag("escape_known")
		for i in r.steps.size():
			var s: Dictionary = r.steps[i]
			var done := q.step_done(s)
			var cnt := ""
			if s.has("count"):
				cnt = "  %d/%d" % [mini(q.count(s.count), q.need_of(s)), q.need_of(s)]
			if done:
				t += "   [color=#9df59a]★ %s%s[/color]\n" % [s.text, cnt]
			elif not next_shown:
				next_shown = true
				t += "   [color=#ffffff]☆ %s%s[/color]\n      [color=#a8e4ff]-> %s[/color]\n" % [s.text, cnt, s.hint]
			elif known:
				t += "   [color=#8a8070]☆ %s%s[/color]\n" % [s.text, cnt]
			else:
				t += "   [color=#8a8070]☆ ???[/color]\n"
		t += "\n"
	routes_text.text = t
	note_list.clear()
	for id in q.notes:
		note_list.add_item(Quests.NOTES.get(id, {}).get("title", id))
		note_list.set_item_metadata(note_list.item_count - 1, id)
	note_text.text = "[color=#d8c8a8]읽은 쪽지와 석판을 다시 볼 수 있다.[/color]" if note_list.item_count > 0 else "[color=#8a8070]아직 읽은 쪽지가 없다.[/color]"
	var st: Dictionary = Game.I.stats
	stats_text.text = "[font_size=22]%d일째 생존 중[/font_size]\n\n★ 설치한 블록  %d\n★ 부순 블록  %d\n★ 채집  %d\n★ 제작  %d\n★ 잡은 물고기  %d\n★ 물리친 게  %d\n★ 건진 잔해  %d\n★ 기절  %d\n★ 친구 살림  %d" % [
		Game.I.clock.day, q.count("blocks_placed"), st.get("blocks_broken", 0), st.get("gathered", 0), st.get("crafted", 0),
		st.get("fish", 0), st.get("crabs", 0), st.get("flotsam", 0), st.get("downs", 0), st.get("revives", 0)]


func _on_note_selected(i: int) -> void:
	var id: String = note_list.get_item_metadata(i)
	var n: Dictionary = Quests.NOTES.get(id, {})
	note_text.text = "[font_size=24][color=#ffe08a]%s[/color][/font_size]\n\n%s" % [n.get("title", ""), n.get("text", "")]


func _tutorial_hint() -> String:
	## 처음 몇 걸음은 "지금 할 일"을 하나씩 알려준다
	var q := Game.I.quests
	var st := Game.I.structs
	if not "note_start" in q.notes:
		return "떠밀려온 상자를 열어 보자 [E]"
	var h: float = Game.I.clock.hour
	if h >= 18.5 and h < 21.0 and st.count_kind("campfire") == 0 and player.inv.count("torch") == 0:
		return "해가 진다! 횃불(막대기1+야자잎1)을 들고 있으면 게가 못 다가온다"
	if st.count_kind("workbench") == 0:
		return "야자수를 때려 통나무 4개 + 돌멩이 2개 -> [Tab] 작업대"
	if st.count_kind("campfire") == 0:
		return "모닥불 만들기 (막대기 4, 돌멩이 3, 야자잎 2)"
	if player.inv.count("stone_pick") == 0 and player.inv.count("iron_pick") == 0 and Game.I.clock.day <= 2:
		return "돌곡괭이(막대기2/돌3/밧줄1)로 바위를 캐면 돌이 잔뜩"
	if player.inv.count("stone_axe") == 0 and player.inv.count("iron_axe") == 0 and Game.I.clock.day <= 2:
		return "돌도끼를 만들면 나무가 훨씬 빨리 베인다"
	if not q.flag("escape_known") and Game.I.clock.day <= 3:
		return "동쪽 얕은 모래길을 건너 숲섬을 탐험하자"
	return ""


func _refresh_tracker() -> void:
	var q := Game.I.quests
	var lines: Array = []
	var tip := _tutorial_hint()
	if tip != "":
		lines.append("[color=#9df59a]지금[/color] " + tip)
	for key in ["escape", "adapt", "turtle"]:
		var r: Dictionary = Quests.ROUTES[key]
		if r.has("reveal") and not q.flag(r.reveal):
			continue
		if key == "escape" and not q.flag("escape_known") and q.notes.size() == 0:
			continue
		for s in r.steps:
			if not q.step_done(s):
				var cnt := ""
				if s.has("count"):
					cnt = " (%d/%d)" % [mini(q.count(s.count), q.need_of(s)), q.need_of(s)]
				lines.append("[color=#ffe08a]%s[/color] %s%s" % [r.name if not r.has("real_name") else "???", s.text, cnt])
				break
	chat_log.visible = Net.is_online() and chat_log.get_parsed_text() != ""
	tracker.text = "[right]" + "\n".join(lines) + "\n[color=#8a8070][J] 일지[/color][/right]"


func _refresh_boss() -> void:
	var ents := Game.I.ents
	for id in ents.enemies:
		var e: Dictionary = ents.enemies[id]
		if e.kind == "king" and is_instance_valid(e.node) and e.node.global_position.distance_to(player.global_position) < 22.0:
			boss_box.visible = true
			boss_bar.max_value = e.max
			boss_bar.value = e.hp
			return
	boss_box.visible = false


func on_players_changed() -> void:
	if not is_node_ready() or Game.I == null:
		return
	var t := ""
	for id in Net.players:
		var col: Color = Net.player_color(id)
		var st := ""
		var p: Player = Game.I.players.get(id)
		if p:
			if p.downed:
				st = " [color=#ff7a6a]기절! 살려줘[/color]"
			elif p.sleeping:
				st = " [color=#9fb6ff]쿨쿨[/color]"
			else:
				st = " [color=#%s]♥%d[/color]" % ["9df59a" if p.hp > 50 else ("ffcf8a" if p.hp > 25 else "ff7a6a"), int(p.hp)]
		t += "[color=#%s]★ %s[/color]%s%s\n" % [col.to_html(false), Net.players[id].name, " (호스트)" if id == 1 and Net.is_online() else "", st]
	player_list.text = t if Net.is_online() else ""


func _refresh_invite() -> void:
	if not Net.is_online():
		invite_text.text = "[center][color=#d8c8a8]혼자 하는 중[/color][/center]"
		return
	if not multiplayer.is_server():
		invite_text.text = "[center][color=#d8c8a8]친구의 섬에 놀러 와 있다[/color][/center]"
		return
	var ips := Net.local_ips()
	var t := "[center][color=#ffe08a]친구 초대[/color]\n같은 와이파이: [b]%s[/b]\n포트: %d" % [", ".join(ips), Net.host_port]
	if Net.upnp_status != "":
		t += "\n[color=#a8e4ff]%s[/color]" % Net.upnp_status
	t += "\n[color=#8a8070][font_size=15]인터넷으로 하려면: 공유기 포트포워딩(UDP) 또는 Radmin VPN/ZeroTier 같은 가상 랜[/font_size][/color][/center]"
	invite_text.text = t


# ═════════ 채팅 ═════════

func chat_line(pname: String, col: Color, text: String) -> void:
	chat_log.append_text("[color=#%s]%s[/color]: %s\n" % [col.to_html(false), pname, text.replace("[", "(")])
	chat_log.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(chat_log, "modulate:a", 0.35, 1.0)


func _on_chat_submit(text: String) -> void:
	Game.I.send_chat(text)
	_close_chat()


func _close_chat() -> void:
	_chat_open = false
	chat_input.visible = false
	chat_input.release_focus()
	if _open == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func add_map_ping(pos: Vector3, col: Color) -> void:
	map_view.add_ping(pos, col)
	%Compass.add_ping(pos, col)


# ═════════ 엔딩 ═════════

func set_cinematic(on: bool) -> void:
	game_ui.visible = not on
	if on:
		_set_open("")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func show_ending(title: String, body: String) -> void:
	ending.visible = true
	end_title.text = title
	end_body.text = body
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ending.modulate.a = 0.0
	create_tween().tween_property(ending, "modulate:a", 1.0, 1.5)


func _on_end_continue() -> void:
	ending.visible = false
	Game.I.end_cinematic_done()
	set_cinematic(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _help_text() -> String:
	return """[font_size=22][color=#ffe08a]조작법[/color][/font_size]
[b]WASD[/b] 이동   [b]Shift[/b] 달리기   [b]Space[/b] 점프 / 헤엄쳐 오르기
[b]마우스[/b] 둘러보기   [b]V[/b] 1인칭/3인칭
[b]좌클릭[/b] 때리기 / 캐기 / 부수기 (꾹 누르면 계속)
[b]우클릭[/b] 설치 / 먹기 / 병에 바닷물 뜨기
[b]E[/b] 상호작용 / 잔해 건지기 / 뗏목 타기 / 친구 살리기(꾹)
(바닥에 떨어진 물건은 걸어가면 알아서 주워진다)
[b]1~9 / 휠[/b] 단축바   [b]Q[/b] 버리기 (Ctrl+Q 전부)
[b]Tab[/b] 가방 / 제작   [b]J[/b] 일지   [b]M[/b] 지도
[b]F / 휠클릭[/b] 핑 찍기   [b]T[/b] 채팅   [b]G[/b] 손 흔들기   [b]Esc[/b] 메뉴

[font_size=22][color=#ffe08a]생존 요령[/color][/font_size]
★ 야자수는 맨손으로도 팰 수 있다. 가끔 코코넛이 떨어진다.
★ 바닥의 막대기/돌멩이는 걸어가면 주워진다.
★ 배고픔/목마름이 0 이 되면 체력이 줄어든다.
★ 밤에는 게가 사나워진다. 불 근처가 안전하다.
★ 깊은 바다에서 오래 헤엄치면 상어가 온다. 다리를 놓자!
★ 체력이 0 이 되면 기절한다. 친구가 E 를 꾹 눌러 살릴 수 있다.
★ 침대에서 자면 그곳에서 다시 깨어난다."""
