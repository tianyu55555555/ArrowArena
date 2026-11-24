class_name Hud
extends CanvasLayer
## 战斗界面：支持 PVP 平衡竞技 + 算力潮汐（幸存者）双模式 HUD、Boss 血条、自动开火开关、静音按钮、双摇杆与增益动画

const JOY_R := 72.0

var game: Game
var move_joy_vec := Vector2.ZERO
var aim_joy_vec := Vector2.ZERO
var aim_joy_active := false
var mouse_fire_held := false
var is_touch_ui := false

var overlay: Control
var fx_overlay: Control
var skill_dim: ColorRect
var skill_panel: PanelContainer
var skill_title: Label
var reroll_btn: Button
var skill_cards: Array[Button] = []
var skill_card_slots: Array[Control] = []
var skill_ids: Array[String] = []
var _picking_locked := false
var _hovered_card := -1

var chest_panel: PanelContainer
var chest_items_box: VBoxContainer
var chest_sub: Label

var over_panel: PanelContainer
var over_title: Label
var over_stats: Label
var pause_panel: PanelContainer
var pause_title_lbl: Label
var pause_summary_lbl: Label
var pause_build_grid: GridContainer
var pause_restart_btn: Button
var pause_bgm_btn: Button
var pause_sfx_btn: Button
var active_btn: Button
var active_btn_title: Label
var active_btn_sub: Label
var mute_btn: Button
var bgm_btn: Button
var pause_btn: Button
var auto_btn: Button = null
var emote_bar: HBoxContainer = null

var feed: Array[Dictionary] = []
var hud_sparks: Array[Dictionary] = []
var banner_text := ""
var banner_col := Color.WHITE
var banner_t := 0.0
var _dmg_flash := 0.0
var hint_time := 9.0
var _avatar_tex: Texture2D

var _move_joy_idx := -1
var _move_joy_center := Vector2.ZERO
var _move_joy_knob := Vector2.ZERO
var _aim_joy_idx := -1
var _aim_joy_center := Vector2.ZERO
var _aim_joy_knob := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_touch_ui = OS.get_name() == "Android" or OS.get_name() == "iOS" or DisplayServer.is_touchscreen_available() or (game != null and game.demo_touch)
	var cd := Characters.get_data(game.player_char_id)
	_avatar_tex = load(str(cd["avatar"])) as Texture2D

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = PixelSprites.ui_font()
	th.default_font_size = 18
	root.theme = th
	add_child(root)

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	root.add_child(overlay)

	_build_corner_controls(root)
	_build_skill_panel(root)
	_build_chest_panel(root)
	_build_pause_panel(root)
	_build_over_panel(root)

	fx_overlay = Control.new()
	fx_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_overlay.draw.connect(_draw_fx_overlay)
	root.add_child(fx_overlay)


func _build_corner_controls(root: Control) -> void:
	var cd := Characters.get_data(game.player_char_id)
	active_btn = Button.new()
	active_btn.anchor_left = 1.0
	active_btn.anchor_right = 1.0
	active_btn.anchor_top = 1.0
	active_btn.anchor_bottom = 1.0
	if is_touch_ui:
		# 触屏布局：把右下角完整留给独立右瞄准摇杆（不挡视野！），大招放在右摇杆左上侧一键拇指直达
		active_btn.offset_left = -336
		active_btn.offset_right = -224
		active_btn.offset_top = -176
		active_btn.offset_bottom = -96
	else:
		active_btn.offset_left = -216
		active_btn.offset_right = -24
		active_btn.offset_top = -104
		active_btn.offset_bottom = -24
	active_btn.focus_mode = Control.FOCUS_NONE
	active_btn.pressed.connect(func() -> void:
		if not get_tree().paused and game.player != null and game.player.alive and not game.player.downed:
			game._trigger_local_active()
	)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.20, 0.88)
	sb.set_corner_radius_all(16)
	sb.border_color = cd["accent"]
	sb.set_border_width_all(3)
	active_btn.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = (cd["color"] as Color).darkened(0.25)
	active_btn.add_theme_stylebox_override("hover", sbh)
	root.add_child(active_btn)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	active_btn.add_child(vb)

	active_btn_title = Label.new()
	active_btn_title.text = "[Space/右键] %s" % cd["active_name"]
	active_btn_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	active_btn_title.add_theme_font_size_override("font_size", 15)
	active_btn_title.add_theme_color_override("font_color", Color.WHITE)
	active_btn_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(active_btn_title)

	active_btn_sub = Label.new()
	active_btn_sub.text = "已就绪！"
	active_btn_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	active_btn_sub.add_theme_font_size_override("font_size", 14)
	active_btn_sub.add_theme_color_override("font_color", cd["accent"])
	active_btn_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(active_btn_sub)

	# 右下小工具栏（主动大招上方：暂停 / 音乐 / 音效 / 自动火）
	mute_btn = Button.new()
	mute_btn.anchor_left = 1.0; mute_btn.anchor_right = 1.0; mute_btn.anchor_top = 1.0; mute_btn.anchor_bottom = 1.0
	mute_btn.offset_left = -114; mute_btn.offset_right = -24; mute_btn.offset_top = -140; mute_btn.offset_bottom = -112
	mute_btn.add_theme_font_size_override("font_size", 12)
	mute_btn.focus_mode = Control.FOCUS_NONE
	mute_btn.text = "音效:关" if Sfx.muted else "音效:开"
	mute_btn.pressed.connect(func() -> void:
		var m := Sfx.toggle_mute()
		mute_btn.text = "音效:关" if m else "音效:开"
		if pause_sfx_btn != null: pause_sfx_btn.text = mute_btn.text
		if not m: Sfx.play("ui_click")
	)
	root.add_child(mute_btn)

	bgm_btn = Button.new()
	bgm_btn.anchor_left = 1.0; bgm_btn.anchor_right = 1.0; bgm_btn.anchor_top = 1.0; bgm_btn.anchor_bottom = 1.0
	bgm_btn.offset_left = -216; bgm_btn.offset_right = -122; bgm_btn.offset_top = -140; bgm_btn.offset_bottom = -112
	bgm_btn.add_theme_font_size_override("font_size", 12)
	bgm_btn.focus_mode = Control.FOCUS_NONE
	bgm_btn.text = "音乐:关" if Sfx.bgm_muted else "音乐:开"
	bgm_btn.pressed.connect(func() -> void:
		var m := Sfx.toggle_bgm_mute()
		bgm_btn.text = "音乐:关" if m else "音乐:开"
		if pause_bgm_btn != null: pause_bgm_btn.text = bgm_btn.text
		Sfx.play("ui_click")
	)
	root.add_child(bgm_btn)

	pause_btn = Button.new()
	pause_btn.anchor_left = 1.0; pause_btn.anchor_right = 1.0; pause_btn.anchor_top = 1.0; pause_btn.anchor_bottom = 1.0
	pause_btn.offset_left = -114; pause_btn.offset_right = -24; pause_btn.offset_top = -174; pause_btn.offset_bottom = -146
	pause_btn.add_theme_font_size_override("font_size", 12)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.text = "⏸ 暂停"
	pause_btn.pressed.connect(toggle_pause_menu)
	root.add_child(pause_btn)

	# 幸存者模式：自动开火快捷开关
	if game.game_mode == "survivor":
		auto_btn = Button.new()
		auto_btn.anchor_left = 1.0; auto_btn.anchor_right = 1.0; auto_btn.anchor_top = 1.0; auto_btn.anchor_bottom = 1.0
		auto_btn.offset_left = -216; auto_btn.offset_right = -122; auto_btn.offset_top = -174; auto_btn.offset_bottom = -146
		auto_btn.add_theme_font_size_override("font_size", 12)
		auto_btn.focus_mode = Control.FOCUS_NONE
		auto_btn.text = "自动火:开"
		auto_btn.pressed.connect(func() -> void:
			if game.player != null:
				game.player.survivor_auto_fire = not game.player.survivor_auto_fire
				auto_btn.text = "自动火:开" if game.player.survivor_auto_fire else "自动火:关"
				Sfx.play("ui_click")
		)
		root.add_child(auto_btn)

	# 左下角（触屏移至底部居中，避开左右双摇杆）：战内快捷热梗表情 / 语音气泡条
	emote_bar = HBoxContainer.new()
	if is_touch_ui:
		emote_bar.anchor_left = 0.5; emote_bar.anchor_right = 0.5
		emote_bar.anchor_top = 1.0; emote_bar.anchor_bottom = 1.0
		emote_bar.offset_left = -196; emote_bar.offset_right = 196
		emote_bar.offset_top = -62; emote_bar.offset_bottom = -32
	else:
		emote_bar.anchor_left = 0.0; emote_bar.anchor_right = 0.0
		emote_bar.anchor_top = 1.0; emote_bar.anchor_bottom = 1.0
		emote_bar.offset_left = 16; emote_bar.offset_right = 450
		emote_bar.offset_top = -68; emote_bar.offset_bottom = -38
	emote_bar.add_theme_constant_override("separation", 6)
	var ems := Archer.get_emotes_for(game.player_char_id)
	var acc_col: Color = cd["accent"]
	for ei in ems.size():
		var eb := Button.new()
		eb.text = "[%d]%s" % [ei + 1, str(ems[ei]["short"])]
		eb.custom_minimum_size = Vector2(92, 28)
		eb.add_theme_font_size_override("font_size", 12)
		eb.focus_mode = Control.FOCUS_NONE
		var esb := StyleBoxFlat.new()
		esb.bg_color = Color(0.06, 0.09, 0.16, 0.80)
		esb.set_corner_radius_all(8)
		esb.border_color = Color(acc_col.r, acc_col.g, acc_col.b, 0.65)
		esb.set_border_width_all(1)
		eb.add_theme_stylebox_override("normal", esb)
		var esbh := esb.duplicate() as StyleBoxFlat
		esbh.bg_color = Color(acc_col.r, acc_col.g, acc_col.b, 0.28)
		eb.add_theme_stylebox_override("hover", esbh)
		eb.pressed.connect(func() -> void:
			if not get_tree().paused:
				game.send_local_emote(ei)
		)
		emote_bar.add_child(eb)
	root.add_child(emote_bar)
	if is_touch_ui:
		_apply_touch_layout()


func _apply_touch_layout() -> void:
	var cd := Characters.get_data(game.player_char_id)
	# 大招放在右瞄准摇杆左上方，绝不遮挡右摇杆且拇指易点
	active_btn.offset_left = -362; active_btn.offset_right = -218
	active_btn.offset_top = -170; active_btn.offset_bottom = -94
	if active_btn_title != null:
		active_btn_title.text = "[大招] %s" % cd["active_name"]
		active_btn_title.add_theme_font_size_override("font_size", 14)
	# 工具小按钮移至右上小地图正左侧，彻底腾空右下独立瞄准区！
	pause_btn.anchor_top = 0.0; pause_btn.anchor_bottom = 0.0
	pause_btn.offset_left = -264; pause_btn.offset_right = -174; pause_btn.offset_top = 202; pause_btn.offset_bottom = 230
	bgm_btn.anchor_top = 0.0; bgm_btn.anchor_bottom = 0.0
	bgm_btn.offset_left = -264; bgm_btn.offset_right = -174; bgm_btn.offset_top = 238; bgm_btn.offset_bottom = 266
	mute_btn.anchor_top = 0.0; mute_btn.anchor_bottom = 0.0
	mute_btn.offset_left = -264; mute_btn.offset_right = -174; mute_btn.offset_top = 274; mute_btn.offset_bottom = 302
	if auto_btn != null:
		auto_btn.anchor_top = 0.0; auto_btn.anchor_bottom = 0.0
		auto_btn.offset_left = -264; auto_btn.offset_right = -174; auto_btn.offset_top = 310; auto_btn.offset_bottom = 338
	if emote_bar != null:
		emote_bar.anchor_left = 0.5; emote_bar.anchor_right = 0.5
		emote_bar.anchor_top = 1.0; emote_bar.anchor_bottom = 1.0
		emote_bar.offset_left = -196; emote_bar.offset_right = 196
		emote_bar.offset_top = -62; emote_bar.offset_bottom = -32


func _panel_style(border_col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.16, 0.94)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(26)
	sb.border_color = border_col
	sb.set_border_width_all(3)
	return sb


func _build_skill_panel(root: Control) -> void:
	skill_dim = ColorRect.new()
	skill_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	skill_dim.color = Color(0.02, 0.03, 0.07, 0.62)
	skill_dim.visible = false
	root.add_child(skill_dim)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)

	skill_panel = PanelContainer.new()
	skill_panel.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.85, 0.38, 0.9)))
	skill_panel.visible = false
	cc.add_child(skill_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	skill_panel.add_child(vb)

	skill_title = Label.new()
	skill_title.text = "LEVEL UP!  选择一项增益  (按 1 / 2 / 3 或点击卡片)"
	skill_title.add_theme_font_size_override("font_size", 26)
	skill_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42))
	skill_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(skill_title)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)

	for i in 3:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(246, 224)
		hb.add_child(slot)
		skill_card_slots.append(slot)

		var b := Button.new()
		b.size = Vector2(246, 224)
		b.pivot_offset = Vector2(123, 112)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_skill_button.bind(i))
		b.mouse_entered.connect(_on_card_hover.bind(i, true))
		b.mouse_exited.connect(_on_card_hover.bind(i, false))
		slot.add_child(b)
		skill_cards.append(b)

	# 刷新词条（Reroll）按钮：免费 3 次，之后消耗 50 Token 刷新！
	reroll_btn = Button.new()
	reroll_btn.custom_minimum_size = Vector2(300, 44)
	reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reroll_btn.add_theme_font_size_override("font_size", 17)
	reroll_btn.focus_mode = Control.FOCUS_NONE
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.14, 0.22, 0.36, 0.95)
	rsb.set_corner_radius_all(12)
	rsb.border_color = Color(0.42, 0.88, 1.0, 0.85)
	rsb.set_border_width_all(2)
	reroll_btn.add_theme_stylebox_override("normal", rsb)
	var rsbh := rsb.duplicate() as StyleBoxFlat
	rsbh.bg_color = Color(0.20, 0.32, 0.50, 0.98)
	reroll_btn.add_theme_stylebox_override("hover", rsbh)
	reroll_btn.pressed.connect(func() -> void:
		if not _picking_locked:
			game.reroll_skill_choices()
	)
	vb.add_child(reroll_btn)


func _build_chest_panel(root: Control) -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)

	chest_panel = PanelContainer.new()
	chest_panel.custom_minimum_size = Vector2(520, 0)
	chest_panel.add_theme_stylebox_override("panel", _panel_style(Color(1.0, 0.85, 0.28, 0.96)))
	chest_panel.visible = false
	cc.add_child(chest_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	chest_panel.add_child(vb)

	var title := Label.new()
	title.text = "🎁 黄金 Token 宝箱开启！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.36))
	vb.add_child(title)

	chest_sub = Label.new()
	chest_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest_sub.add_theme_font_size_override("font_size", 16)
	chest_sub.add_theme_color_override("font_color", Color(0.48, 0.95, 1.0))
	vb.add_child(chest_sub)

	chest_items_box = VBoxContainer.new()
	chest_items_box.add_theme_constant_override("separation", 10)
	vb.add_child(chest_items_box)

	var ok_btn := Button.new()
	ok_btn.text = "全部收入囊中！(Space)"
	ok_btn.custom_minimum_size = Vector2(240, 48)
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_btn.add_theme_font_size_override("font_size", 20)
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.pressed.connect(_close_chest)
	vb.add_child(ok_btn)


func _build_pause_panel(root: Control) -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)

	pause_panel = PanelContainer.new()
	pause_panel.custom_minimum_size = Vector2(740, 440)
	pause_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.42, 0.86, 1.0, 0.92)))
	pause_panel.visible = false
	cc.add_child(pause_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pause_panel.add_child(vb)

	pause_title_lbl = Label.new()
	pause_title_lbl.text = "⏸ 游戏暂停 · 实时 Build 构筑一览"
	pause_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title_lbl.add_theme_font_size_override("font_size", 26)
	pause_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.48))
	vb.add_child(pause_title_lbl)

	pause_summary_lbl = Label.new()
	pause_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_summary_lbl.add_theme_font_size_override("font_size", 15)
	pause_summary_lbl.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
	vb.add_child(pause_summary_lbl)

	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 196)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)

	pause_build_grid = GridContainer.new()
	pause_build_grid.columns = 3
	pause_build_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_build_grid.add_theme_constant_override("h_separation", 10)
	pause_build_grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(pause_build_grid)

	var audio_row := HBoxContainer.new()
	audio_row.alignment = BoxContainer.ALIGNMENT_CENTER
	audio_row.add_theme_constant_override("separation", 14)
	vb.add_child(audio_row)

	pause_bgm_btn = Button.new()
	pause_bgm_btn.custom_minimum_size = Vector2(150, 36)
	pause_bgm_btn.focus_mode = Control.FOCUS_NONE
	pause_bgm_btn.text = "音乐:关" if Sfx.bgm_muted else "音乐:开"
	pause_bgm_btn.pressed.connect(func() -> void:
		var m := Sfx.toggle_bgm_mute()
		pause_bgm_btn.text = "音乐:关" if m else "音乐:开"
		bgm_btn.text = pause_bgm_btn.text
		Sfx.play("ui_click")
	)
	audio_row.add_child(pause_bgm_btn)

	pause_sfx_btn = Button.new()
	pause_sfx_btn.custom_minimum_size = Vector2(150, 36)
	pause_sfx_btn.focus_mode = Control.FOCUS_NONE
	pause_sfx_btn.text = "音效:关" if Sfx.muted else "音效:开"
	pause_sfx_btn.pressed.connect(func() -> void:
		var m := Sfx.toggle_mute()
		pause_sfx_btn.text = "音效:关" if m else "音效:开"
		mute_btn.text = pause_sfx_btn.text
		if not m: Sfx.play("ui_click")
	)
	audio_row.add_child(pause_sfx_btn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vb.add_child(btn_row)

	var resume_btn := Button.new()
	resume_btn.text = "继续战斗 (ESC)"
	resume_btn.custom_minimum_size = Vector2(175, 46)
	resume_btn.add_theme_font_size_override("font_size", 18)
	resume_btn.focus_mode = Control.FOCUS_NONE
	resume_btn.pressed.connect(toggle_pause_menu)
	btn_row.add_child(resume_btn)

	pause_restart_btn = Button.new()
	pause_restart_btn.text = "重新开局"
	pause_restart_btn.custom_minimum_size = Vector2(145, 46)
	pause_restart_btn.add_theme_font_size_override("font_size", 18)
	pause_restart_btn.focus_mode = Control.FOCUS_NONE
	pause_restart_btn.pressed.connect(func() -> void:
		get_tree().paused = false
		game.request_rematch.emit()
	)
	btn_row.add_child(pause_restart_btn)

	var lobby_btn := Button.new()
	lobby_btn.text = "返回大厅" if game.net_role == "offline" else "退出房间返回大厅"
	lobby_btn.custom_minimum_size = Vector2(180, 46)
	lobby_btn.add_theme_font_size_override("font_size", 18)
	lobby_btn.focus_mode = Control.FOCUS_NONE
	lobby_btn.pressed.connect(func() -> void:
		get_tree().paused = false
		if NetManager.is_online() and NetManager.inst != null:
			NetManager.inst.leave_room()
		game.request_lobby.emit()
	)
	btn_row.add_child(lobby_btn)


func toggle_pause_menu() -> void:
	if over_panel.visible or skill_panel.visible or chest_panel.visible:
		return
	Sfx.play("ui_click")
	var opening := not pause_panel.visible
	pause_panel.visible = opening
	skill_dim.visible = opening and game.net_role == "offline"
	if game.net_role == "offline":
		get_tree().paused = opening
	if opening:
		mouse_fire_held = false
		_release_joysticks()
		_refresh_pause_build()


func _refresh_pause_build() -> void:
	pause_title_lbl.text = "⏸ 游戏暂停 · 实时 Build 构筑一览" if game.net_role == "offline" else "⚙ 战中菜单与构筑（联机实时进行中）"
	pause_restart_btn.visible = (game.net_role == "offline")
	var p := game.player
	if p == null:
		return
	var cd := Characters.get_data(p.char_id)
	var wd := Weapons.get_data(p.weapon_id)
	var w_label := str(wd["name"])
	if p.evolved_weapon != "":
		w_label = str(Skills.info(p.evolved_weapon)["name"])
	var moe_str := "未激活（集齐2种AI支援激活）"
	if p.moe_tier >= 2:
		moe_str = "👑 满血全员 MoE 大协同（CD-35% 伤+55%）"
	elif p.moe_tier >= 1:
		moe_str = "✨ MoE 混合专家协同（CD-25% 伤+30%）"
	pause_summary_lbl.text = "%s · 武器：%s · Lv%d (%s)\n攻击 %.0f · 暴击 %d%% · 移速 %.0f · 有效射程 %.0f · 生命 %d/%d\nMoE 状态：%s" % [
		cd["name"], w_label, p.level, p.context_label(),
		p.damage, int(round(p.crit_chance * 100.0)), p.move_speed, p.effective_attack_range(), int(p.hp), int(p.max_hp), moe_str
	]
	for ch in pause_build_grid.get_children():
		ch.queue_free()
	if p.skills.is_empty():
		var empty_l := Label.new()
		empty_l.text = "尚未获取任何局内增益，快拾取 Token 升级吧！"
		empty_l.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		pause_build_grid.add_child(empty_l)
		return
	for sid: String in p.skills:
		var info := Skills.info(sid)
		if info.is_empty():
			continue
		var cnt := int(p.skills[sid])
		var mx := int(info.get("max", 1))
		var col := Skills.rarity_color(sid)
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(col.r, col.g, col.b, 0.16).lerp(Color(0.10, 0.13, 0.22, 0.95), 0.68)
		csb.set_corner_radius_all(10)
		csb.set_content_margin_all(8)
		csb.border_color = col
		csb.set_border_width_all(2)
		chip.add_theme_stylebox_override("panel", csb)
		var lb := Label.new()
		lb.text = "[%s] %s\nLv %d / %d" % [info["icon"], info["name"], cnt, mx]
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", Color.WHITE)
		chip.add_child(lb)
		pause_build_grid.add_child(chip)


func _build_over_panel(root: Control) -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)

	over_panel = PanelContainer.new()
	over_panel.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.85, 0.4, 0.85)))
	over_panel.visible = false
	cc.add_child(over_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	over_panel.add_child(vb)

	over_title = Label.new()
	over_title.add_theme_font_size_override("font_size", 30)
	over_title.add_theme_color_override("font_color", Color(1, 0.88, 0.4))
	over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(over_title)

	over_stats = Label.new()
	over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_stats.add_theme_font_size_override("font_size", 20)
	vb.add_child(over_stats)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)

	var b_again := Button.new()
	b_again.text = "再来一局"
	b_again.custom_minimum_size = Vector2(180, 54)
	b_again.add_theme_font_size_override("font_size", 22)
	b_again.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		get_tree().paused = false
		game.request_rematch.emit()
	)
	row.add_child(b_again)

	var b_lobby := Button.new()
	b_lobby.text = "返回联机房间" if game.net_role != "offline" else "去点算力天赋 / 返回大厅"
	b_lobby.custom_minimum_size = Vector2(250, 54)
	b_lobby.add_theme_font_size_override("font_size", 19)
	b_lobby.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		get_tree().paused = false
		if game.net_role == "host" and NetManager.inst != null:
			NetManager.inst.host_return_to_room()
		elif game.net_role == "client" and NetManager.inst != null:
			NetManager.inst.leave_room()
			game.request_lobby.emit()
		else:
			game.request_lobby.emit()
	)
	row.add_child(b_lobby)


func show_banner(text: String, col: Color) -> void:
	banner_text = text
	banner_col = col
	banner_t = 2.4


func trigger_damage_vignette(strength := 0.65) -> void:
	_dmg_flash = maxf(_dmg_flash, clampf(strength, 0.0, 1.0))


# ================= 增益三选一动画 =================
func _populate_card(b: Button, idx: int, sid: String) -> void:
	for c in b.get_children():
		c.queue_free()
	var s := Skills.info(sid)
	var rcol := Skills.rarity_color(sid)
	var rlbl := Skills.rarity_label(sid)
	var lv := int(game.player.skills.get(sid, 0))

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.14, 0.23, 0.96)
	sb.set_corner_radius_all(14)
	sb.border_color = rcol
	sb.set_border_width_all(3)
	sb.shadow_color = Color(rcol.r, rcol.g, rcol.b, 0.25)
	sb.shadow_size = 8
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = Color(0.16, 0.20, 0.34, 0.98)
	sbh.border_color = rcol.lightened(0.28)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbh)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14; vb.offset_right = -14; vb.offset_top = 12; vb.offset_bottom = -12
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	var rl := Label.new()
	rl.text = rlbl
	rl.add_theme_font_size_override("font_size", 13)
	rl.add_theme_color_override("font_color", rcol)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(rl)
	var kl := Label.new()
	kl.text = "[%d]" % [idx + 1]
	kl.add_theme_font_size_override("font_size", 14)
	kl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.8))
	kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(kl)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(74, 48)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(rcol.r, rcol.g, rcol.b, 0.22)
	bsb.set_corner_radius_all(12)
	bsb.border_color = rcol
	bsb.set_border_width_all(2)
	badge.add_theme_stylebox_override("panel", bsb)
	vb.add_child(badge)

	var ic := Label.new()
	ic.text = str(s["icon"])
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.add_theme_font_size_override("font_size", 22)
	ic.add_theme_color_override("font_color", rcol.lightened(0.35))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(ic)

	var nl := Label.new()
	nl.text = str(s["name"]) + ("" if lv == 0 else " Lv%d" % (lv + 1))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.add_theme_font_size_override("font_size", 21)
	nl.add_theme_color_override("font_color", Color.WHITE)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nl)

	var dl := Label.new()
	dl.text = str(s["desc"])
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dl.add_theme_font_size_override("font_size", 15)
	dl.add_theme_color_override("font_color", Color(0.84, 0.90, 0.98))
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(dl)


func show_skill_pick(ids: Array[String]) -> void:
	skill_ids = ids
	_picking_locked = false
	_hovered_card = -1
	mouse_fire_held = false
	_release_joysticks()

	skill_title.text = ("LEVEL UP!  上下文扩容至 %s · 超频三选一 (1/2/3)" % game.player.context_label() if game.game_mode == "survivor"
		else "LEVEL UP!  上下文扩容至 %s · 战术三选一 (1/2/3)" % game.player.context_label())
	_refresh_reroll_btn()

	skill_dim.visible = (game.net_role == "offline")
	skill_dim.modulate.a = 0.0
	skill_panel.visible = true
	skill_panel.modulate.a = 0.0
	skill_panel.pivot_offset = skill_panel.size * 0.5
	skill_panel.scale = Vector2(0.90, 0.90)

	var tw_bg := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tw_bg.tween_property(skill_dim, "modulate:a", 1.0, 0.20)
	tw_bg.tween_property(skill_panel, "modulate:a", 1.0, 0.22)
	tw_bg.tween_property(skill_panel, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	for i in skill_cards.size():
		var b := skill_cards[i]
		if i < ids.size():
			_populate_card(b, i, ids[i])
			b.visible = true
			b.position = Vector2(0, 75)
			b.scale = Vector2(0.06, 0.82)
			b.modulate = Color(1, 1, 1, 0)
			var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tw.tween_interval(0.07 * i)
			tw.set_parallel(true)
			tw.tween_property(b, "modulate:a", 1.0, 0.16)
			tw.tween_property(b, "position:y", 0.0, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(b, "scale:y", 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(b, "scale:x", 1.04, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.chain().tween_property(b, "scale:x", 1.0, 0.10)
		else:
			b.visible = false


func _on_card_hover(idx: int, entered: bool) -> void:
	if _picking_locked or idx >= skill_cards.size():
		return
	if entered:
		Sfx.play("card_hover", 0.04, 40, -14.0)
	_hovered_card = idx if entered else (-1 if _hovered_card == idx else _hovered_card)
	var b := skill_cards[idx]
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2(1.07, 1.07) if entered else Vector2.ONE, 0.14)
	tw.tween_property(b, "position:y", -12.0 if entered else 0.0, 0.14)


func pick_skill_for_demo(i: int) -> void:
	_on_skill_button(i)


func _on_skill_button(i: int) -> void:
	if _picking_locked or i >= skill_ids.size():
		return
	var chosen_id := skill_ids[i]
	if game.autotest:
		game.on_skill_chosen(chosen_id)
		return

	Sfx.play("card_pick", 0.03, 80, -7.0)
	_picking_locked = true
	var chosen_card := skill_cards[i]
	var rcol := Skills.rarity_color(chosen_id)
	var center := chosen_card.global_position + chosen_card.size * 0.5

	for k in 28:
		var ang := randf() * TAU
		var spd := randf_range(120.0, 420.0)
		hud_sparks.append({
			"pos": center,
			"vel": Vector2.from_angle(ang) * spd,
			"t": 0.0,
			"life": randf_range(0.45, 0.85),
			"r": randf_range(4.0, 9.0),
			"col": rcol if (k % 2 == 0) else Color(1.0, 0.96, 0.7),
		})

	var s := Skills.info(chosen_id)
	show_banner("获得增益 · %s！" % s["name"], rcol)

	for j in skill_cards.size():
		if j != i and skill_cards[j].visible:
			var t_other := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
			t_other.tween_property(skill_cards[j], "modulate:a", 0.0, 0.18)
			t_other.tween_property(skill_cards[j], "scale", Vector2(0.75, 0.75), 0.18)

	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(chosen_card, "scale", Vector2(1.18, 1.18), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(chosen_card, "position:y", -20.0, 0.16)
	tw.tween_property(chosen_card, "modulate", Color(1.6, 1.55, 1.35, 1.0), 0.14)
	tw.chain().tween_interval(0.14)
	tw.chain().set_parallel(true)
	tw.tween_property(chosen_card, "scale", Vector2(0.4, 1.35), 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(chosen_card, "modulate:a", 0.0, 0.20)
	tw.tween_property(skill_panel, "modulate:a", 0.0, 0.20)
	tw.tween_property(skill_dim, "modulate:a", 0.0, 0.20)
	tw.chain().tween_callback(func() -> void:
		_picking_locked = false
		game.on_skill_chosen(chosen_id)
	)


func hide_skill_pick() -> void:
	skill_panel.visible = false
	skill_dim.visible = false


func _refresh_reroll_btn() -> void:
	if reroll_btn == null:
		return
	if game.rerolls_left > 0:
		reroll_btn.text = "[R] 刷新词条（免费剩余 %d 次）" % game.rerolls_left
		reroll_btn.disabled = false
	elif game.player.tokens >= 50:
		reroll_btn.text = "[R] 消耗 50 Token 刷新（拥有 %d）" % game.player.tokens
		reroll_btn.disabled = false
	else:
		reroll_btn.text = "刷新次数已用完（需 50 Token，当前 %d）" % game.player.tokens
		reroll_btn.disabled = true


func show_chest_rewards(reward_ids: Array[String], bonus_tokens: int) -> void:
	mouse_fire_held = false
	_release_joysticks()
	for c in chest_items_box.get_children():
		c.queue_free()
	chest_sub.text = "额外获得 +%d Token 晶片，并直接强化以下 %d 项能力！" % [bonus_tokens, reward_ids.size()]

	for sid in reward_ids:
		var s := Skills.info(sid)
		var rcol := Skills.rarity_color(sid)
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.15, 0.24, 0.95)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(10)
		sb.border_color = rcol
		sb.set_border_width_all(2)
		row.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.text = "【%s】 %s — %s" % [s["icon"], s["name"], str(s["desc"]).replace("\n", " ")]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(lbl)
		chest_items_box.add_child(row)

	skill_dim.visible = true
	skill_dim.modulate.a = 1.0
	chest_panel.visible = true
	chest_panel.pivot_offset = Vector2(260, 140)
	chest_panel.scale = Vector2(0.7, 0.7)
	chest_panel.modulate.a = 0.0
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tw.tween_property(chest_panel, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(chest_panel, "modulate:a", 1.0, 0.22)

	var center := fx_overlay.size * 0.5
	for k in 36:
		var ang := randf() * TAU
		var spd := randf_range(140.0, 480.0)
		hud_sparks.append({
			"pos": center,
			"vel": Vector2.from_angle(ang) * spd,
			"t": 0.0,
			"life": randf_range(0.55, 1.0),
			"r": randf_range(4.5, 9.5),
			"col": Color(1.0, 0.86, 0.32) if (k % 2 == 0) else Color(0.45, 0.94, 1.0),
		})


func _close_chest() -> void:
	Sfx.play("card_pick", 0.04, 80, -8.0)
	chest_panel.visible = false
	skill_dim.visible = false
	game.on_chest_closed()


func show_game_over(reason: String, rank: int, total: int, cp_info: Dictionary = {}) -> void:
	hide_skill_pick()
	chest_panel.visible = false
	pause_panel.visible = false
	mouse_fire_held = false
	_release_joysticks()
	var p := game.player
	var cd := Characters.get_data(game.player_char_id)
	var wd := Weapons.get_data(game.player_weapon_id)
	var earned := int(cp_info.get("earned", 0))
	var total_cp := int(cp_info.get("total_cp", MetaSave.compute_points()))
	var mult := float(cp_info.get("mult", 1.0))
	var cp_line := "\n\n⚡ 本局折算算力点：+%d 点 (×%.1f)   ·   累计可用：%d 点" % [earned, mult, total_cp]
	if bool(cp_info.get("new_record", false)):
		cp_line += "\n★ 刷新「极限无尽挑战」最长坚守新纪录！"
	over_title.text = reason
	if game.game_mode == "survivor" and game.swarm != null:
		var dd := Difficulties.get_data(game.difficulty_id)
		var sv := int(game.survived_sec)
		over_stats.text = "【算力潮汐 · %s】 %s · %s\n坚守时长 %d:%02d   ·   抵达：%s\n等级 Lv%d (%s)    消灭怪潮 %d    Token %d%s" % [
			dd["name"], cd["name"], wd["name"], sv / 60, sv % 60, game.swarm.wave_title(), p.level, p.context_label(), game.swarm.monster_kills, p.tokens, cp_line]
	else:
		var lines: Array[String] = []
		if game.pvp_variant == "2v2v2v2":
			var tr := game.team_ranking()
			var win_name := str(tr[0]["name"]) if not tr.is_empty() else ""
			lines.append("【五宫格 2v2v2v2 积分结算】 获胜阵营：%s" % win_name)
			for i in tr.size():
				lines.append("%d. %s — 总分 %d" % [i + 1, tr[i]["name"], int(tr[i]["score"])])
		else:
			lines.append("【五宫格 PVP 积分结算】 %s · %s  ·  第 %d / %d 名" % [cd["name"], wd["name"], rank, total])
		lines.append("你的总分：%d（击杀分 %d [%d杀] + 等级分 %d [Lv%d]）" % [p.score, p.kill_score, p.kills, p.level_score(), p.level])
		var rk := game.ranking()
		var top_parts: Array[String] = []
		for i in mini(4, rk.size()):
			var ra := rk[i]
			top_parts.append("%d.%s %d分(杀%d+级%d)" % [i + 1, ra.display_name, ra.score, ra.kill_score, ra.level_score()])
		if not top_parts.is_empty():
			lines.append("前四名：" + "  |  ".join(top_parts))
		over_stats.text = "\n".join(lines) + cp_line
	over_panel.visible = true


func add_feed(msg: String) -> void:
	feed.push_front({"msg": msg, "t": 4.0})
	if feed.size() > 5:
		feed.pop_back()


func _release_joysticks() -> void:
	_move_joy_idx = -1
	move_joy_vec = Vector2.ZERO
	_aim_joy_idx = -1
	aim_joy_vec = Vector2.ZERO
	aim_joy_active = false


# ================= 输入 =================
func _unhandled_input(event: InputEvent) -> void:
	if skill_panel.visible or over_panel.visible or chest_panel.visible or pause_panel.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 忽略触屏模拟出的鼠标事件，防止手机左手划移动摇杆时误触发开火！
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and not aim_joy_active:
			mouse_fire_held = mb.pressed


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if chest_panel.visible and (k == KEY_SPACE or k == KEY_ENTER):
			_close_chest()
			return
		if skill_panel.visible and not _picking_locked:
			if k >= KEY_1 and k <= KEY_3:
				_on_skill_button(k - KEY_1)
			elif k == KEY_R:
				game.reroll_skill_choices()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			mouse_fire_held = false

	if skill_panel.visible or over_panel.visible or chest_panel.visible or pause_panel.visible:
		return

	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if not is_touch_ui:
			is_touch_ui = true
			_apply_touch_layout()
		var half_x := overlay.size.x * 0.5
		if t.pressed:
			if active_btn.get_global_rect().has_point(t.position) or mute_btn.get_global_rect().has_point(t.position) or bgm_btn.get_global_rect().has_point(t.position) or pause_btn.get_global_rect().has_point(t.position):
				return
			if auto_btn != null and auto_btn.get_global_rect().has_point(t.position):
				return
			if emote_bar != null and emote_bar.get_global_rect().has_point(t.position):
				return
			if t.position.x < half_x and _move_joy_idx == -1:
				_move_joy_idx = t.index
				var rest_l := Vector2(126.0, overlay.size.y - 138.0)
				_move_joy_center = rest_l if t.position.distance_to(rest_l) < 105.0 else t.position
				_move_joy_knob = t.position
			elif t.position.x >= half_x and _aim_joy_idx == -1:
				_aim_joy_idx = t.index
				var rest_r := Vector2(overlay.size.x - 126.0, overlay.size.y - 138.0)
				_aim_joy_center = rest_r if t.position.distance_to(rest_r) < 110.0 else t.position
				var init_off := (t.position - _aim_joy_center).limit_length(JOY_R)
				_aim_joy_knob = _aim_joy_center + init_off
				aim_joy_active = true
				aim_joy_vec = (init_off / JOY_R) if init_off.length() > 10.0 else Vector2.ZERO
		else:
			if t.index == _move_joy_idx:
				_move_joy_idx = -1
				move_joy_vec = Vector2.ZERO
			elif t.index == _aim_joy_idx:
				_aim_joy_idx = -1
				aim_joy_vec = Vector2.ZERO
				aim_joy_active = false
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _move_joy_idx:
			var off := d.position - _move_joy_center
			if off.length() > JOY_R:
				off = off.normalized() * JOY_R
			_move_joy_knob = _move_joy_center + off
			var v := off / JOY_R
			move_joy_vec = v if v.length() > 0.12 else Vector2.ZERO
		elif d.index == _aim_joy_idx:
			var off := d.position - _aim_joy_center
			if off.length() > JOY_R:
				off = off.normalized() * JOY_R
			_aim_joy_knob = _aim_joy_center + off
			aim_joy_vec = off / JOY_R


func _process(delta: float) -> void:
	hint_time -= delta
	banner_t = maxf(banner_t - delta, 0.0)
	_dmg_flash = maxf(_dmg_flash - delta * 3.2, 0.0)
	for f in feed:
		f["t"] = float(f["t"]) - delta
	feed.assign(feed.filter(func(f: Dictionary) -> bool: return float(f["t"]) > 0.0))

	for sp in hud_sparks:
		sp["t"] = float(sp["t"]) + delta
		sp["pos"] = (sp["pos"] as Vector2) + (sp["vel"] as Vector2) * delta
		sp["vel"] = (sp["vel"] as Vector2) * (1.0 - delta * 2.4)
	hud_sparks.assign(hud_sparks.filter(func(s: Dictionary) -> bool: return float(s["t"]) < float(s["life"])))

	if game.player != null and active_btn_sub != null:
		if game.player.active_cd > 0.05:
			active_btn_sub.text = "冷却 %.1fs" % game.player.active_cd
			active_btn.modulate = Color(0.65, 0.68, 0.78, 0.9)
		else:
			active_btn_sub.text = "已就绪！"
			active_btn.modulate = Color.WHITE

	overlay.queue_redraw()
	fx_overlay.queue_redraw()
	game.debug_shot(delta)
	if game.autotest and skill_panel.visible and not _picking_locked:
		_on_skill_button(randi() % skill_ids.size())


# ================= 绘制 =================
func _text(canvas: Control, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := PixelSprites.ui_font()
	canvas.draw_string_outline(font, pos, s, align, width, size, 5, Color(0, 0, 0, 0.8))
	canvas.draw_string(font, pos, s, align, width, size, col)


func _bar(pos: Vector2, sz: Vector2, ratio: float, col: Color, label: String, font_size_override := -1) -> void:
	overlay.draw_rect(Rect2(pos - Vector2(3, 3), sz + Vector2(6, 6)), Color(0, 0, 0, 0.6))
	overlay.draw_rect(Rect2(pos, Vector2(sz.x * clampf(ratio, 0.0, 1.0), sz.y)), col)
	var fs := font_size_override if font_size_override > 0 else (int(sz.y) - 3)
	var y_off := sz.y * 0.5 + fs * 0.35
	_text(overlay, pos + Vector2(0, y_off), label, fs, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_overlay() -> void:
	var p := game.player
	if p == null:
		return
	var vs := overlay.size
	var cd := Characters.get_data(p.char_id)
	var wd := Weapons.get_data(p.weapon_id)

	# 左上：角色头像 + 血盾 + 经验
	overlay.draw_rect(Rect2(16, 14, 68, 68), Color(0.06, 0.08, 0.14, 0.85))
	if _avatar_tex != null:
		overlay.draw_texture_rect(_avatar_tex, Rect2(18, 16, 64, 64), false)
	overlay.draw_rect(Rect2(16, 14, 68, 68), cd["accent"], false, 2.5)

	var hp_txt := "%d / %d" % [int(p.hp), int(p.max_hp)]
	if p.temp_hp > 0.5 and p.shield > 0.5:
		hp_txt = "%d/%d +%d临 +%d盾" % [int(p.hp), int(p.max_hp), int(p.temp_hp), int(p.shield)]
	elif p.temp_hp > 0.5:
		hp_txt += " (+%d临血)" % int(p.temp_hp)
	elif p.shield > 0.5:
		hp_txt += " (+%d盾)" % int(p.shield)
	var hp_fs := 15 if hp_txt.length() > 14 else 19
	_bar(Vector2(96, 18), Vector2(266, 24), p.hp / p.max_hp, Color(0.86, 0.26, 0.32), hp_txt, hp_fs)
	if p.temp_hp > 0.5:
		var tw := 266.0 * clampf(p.temp_hp / maxf(p.max_hp, 1.0), 0.0, 1.0)
		overlay.draw_rect(Rect2(96, 18, tw, 5.0), Color("#ffd84a"))
	_bar(Vector2(96, 52), Vector2(266, 18), p.xp / p.xp_needed(), Color(0.24, 0.74, 1.0), "Lv%d · %s Context  (%d Token)" % [p.level, p.context_label(), p.tokens])

	var owned: Array[String] = []
	if p.evolved_weapon != "":
		owned.append(str(Skills.info(p.evolved_weapon)["name"]))
	if p.moe_tier >= 2:
		owned.append("👑满血MoE")
	elif p.moe_active:
		owned.append("★MoE协同")
	for id: String in p.skills:
		if id.begins_with("evo_"):
			continue
		var n: String = Skills.info(id)["name"]
		var c: int = p.skills[id]
		owned.append(n if c == 1 else "%s×%d" % [n, c])
	var buff_y := 94.0
	if not owned.is_empty():
		_text(overlay, Vector2(18, 108), "  ".join(owned.slice(0, 7)), 14, Color(0.92, 0.96, 1.0))
		buff_y = 118.0

	# 四角符文增益倒计时徽章 + Mid Boss 复活甲 + 重伤减疗状态栏
	if p.revive_charges > 0 or p.antiheal_timer > 0.0 or not p.rune_timers.is_empty():
		var bx := 16.0
		var by := buff_y
		if p.revive_charges > 0:
			var rrect := Rect2(bx, by, 134.0, 24.0)
			overlay.draw_rect(rrect, Color(0.26, 0.20, 0.04, 0.88))
			overlay.draw_rect(rrect, Color("#ffe052"), false, 2.0)
			_text(overlay, Vector2(bx, by + 17.0), "★ 复活甲 ×%d" % p.revive_charges, 13, Color("#ffe86b"), HORIZONTAL_ALIGNMENT_CENTER, 134.0)
			bx += 142.0
		if p.antiheal_timer > 0.0:
			var ahw := 148.0
			if bx + ahw > 376.0:
				bx = 16.0
				by += 28.0
			var ahrect := Rect2(bx, by, ahw, 24.0)
			overlay.draw_rect(ahrect, Color(0.24, 0.06, 0.30, 0.90))
			overlay.draw_rect(ahrect, Color("#d45cff"), false, 1.8)
			_text(overlay, Vector2(bx, by + 17.0), "[重伤] 治疗-%d%% %ds" % [int(round(p.antiheal_ratio * 100.0)), int(ceil(p.antiheal_timer))], 12, Color("#f2b6ff"), HORIZONTAL_ALIGNMENT_CENTER, ahw)
			bx += ahw + 6.0
		for rk in Archer.RUNE_ORDER:
			var rt := float(p.rune_timers.get(rk, 0.0))
			if rt <= 0.0:
				continue
			var rdef: Dictionary = Archer.RUNE_DEFS[rk]
			var rcol: Color = rdef["color"]
			var pw := 102.0
			if bx + pw > 376.0:
				bx = 16.0
				by += 28.0
			var prect := Rect2(bx, by, pw, 24.0)
			overlay.draw_rect(prect, Color(0.06, 0.09, 0.16, 0.85))
			overlay.draw_rect(prect, rcol, false, 1.8)
			_text(overlay, Vector2(bx, by + 17.0), "[%s]%s %ds" % [rdef["tag"], rdef["short"], int(ceil(rt))], 12, rcol.lightened(0.22), HORIZONTAL_ALIGNMENT_CENTER, pw)
			bx += pw + 6.0

	# PVE 双人合作：显示队友状态与救援提示
	if game.is_coop:
		var ally_y := 132.0
		for a in game.archers:
			if a != p and a.is_human():
				var st := "🆘 倒地！靠近救援 (%.0fs)" % a.auto_revive_t if a.downed else "HP %d/%d · Lv%d" % [int(a.hp), int(a.max_hp), a.level]
				var scol := Color("#ff6b8b") if a.downed else Color("#6effa8")
				overlay.draw_rect(Rect2(16, ally_y - 18, 290, 26), Color(0.05, 0.08, 0.14, 0.72))
				_text(overlay, Vector2(24, ally_y), "🤝 队友 %s · %s" % [a.display_name, st], 14, scol)
				ally_y += 30.0

	# 顶部中间（无尽模式正计时 ∞，常规难度倒计时同步检查点）
	if game.game_mode == "survivor" and game.swarm != null:
		var dd := Difficulties.get_data(game.difficulty_id)
		if game.is_endless:
			var sv := int(game.survived_sec)
			var mode_lbl := "双人合作坚守" if game.is_coop else "已坚守"
			_text(overlay, Vector2(0, 38), "%s %d:%02d  ∞" % [mode_lbl, sv / 60, sv % 60], 30, Color(0.92, 0.65, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		else:
			var tl := int(ceil(game.time_left))
			_text(overlay, Vector2(0, 38), "%d:%02d" % [tl / 60, tl % 60], 30, Color.WHITE if tl > 30 else Color(1, 0.4, 0.3), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(overlay, Vector2(0, 68), "[%s] %s   ·   消灭 %d" % ["双人无尽" if game.is_coop else dd["name"], game.swarm.wave_title(), game.swarm.monster_kills], 16, Color(1.0, 0.86, 0.48), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		var boss := game.swarm.active_boss()
		if not boss.is_empty():
			var bname := str(boss.get("boss_name", "终极过拟合魔王" if bool(boss["is_final"]) else "过拟合巨像"))
			var bcol: Color = boss.get("boss_col", Color("#d93258"))
			_bar(Vector2(vs.x * 0.5 - 210, 82), Vector2(420, 22), float(boss["hp"]) / float(boss["max_hp"]), bcol, "★ %s  %d / %d" % [bname, int(boss["hp"]), int(boss["max_hp"])], 14)
	else:
		var tl := int(ceil(game.time_left))
		_text(overlay, Vector2(0, 38), "%d:%02d" % [tl / 60, tl % 60], 30, Color.WHITE if tl > 30 else Color(1, 0.4, 0.3), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		var pvp_tag := "五宫格 2v2v2v2" if game.pvp_variant == "2v2v2v2" else "五宫格乱斗 PVP"
		_text(overlay, Vector2(0, 68), "%s  ·  总分 %d（击杀 %d + 等级 %d）" % [pvp_tag, p.score, p.kill_score, p.level_score()], 16, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		var sub_y := 78.0
		if not game.mid_boss.is_empty():
			var mb_hp := float(game.mid_boss["hp"])
			var mb_max := maxf(float(game.mid_boss["max_hp"]), 1.0)
			_bar(Vector2(vs.x * 0.5 - 210, sub_y), Vector2(420, 22), mb_hp / mb_max, Color("#e03868"), "★ 中央 Mid Boss · 算力霸主   %d / %d" % [int(mb_hp), int(mb_max)])
			sub_y += 28.0
		elif p.room_buff == "":
			var mb_s := int(ceil(game.mid_boss_cd))
			var warn_c := Color("#ff6080") if mb_s <= 10 else Color("#ffd866")
			overlay.draw_rect(Rect2(vs.x * 0.5 - 205, sub_y, 410, 24), Color(0.06, 0.08, 0.15, 0.76))
			overlay.draw_rect(Rect2(vs.x * 0.5 - 205, sub_y, 410, 24), Color(warn_c.r, warn_c.g, warn_c.b, 0.72), false, 1.5)
			_text(overlay, Vector2(0, sub_y + 17.0), "★ 中央 Mid Boss 刷新 %d:%02d（击杀 30s 全增益 + 复活）" % [mb_s / 60, mb_s % 60], 13, warn_c, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
			sub_y += 28.0
		if game.storm_active:
			var out_storm := p.position.length() > game.storm_radius
			var st_col := Color("#ff3864") if out_storm else Color("#ff76a8")
			var st_txt := "⚠ 身处算力坍缩圈外！火速冲进中央决斗场！" if out_storm else "⚠ 最后决胜缩圈中 · 安全半径 %d" % int(game.storm_radius)
			overlay.draw_rect(Rect2(vs.x * 0.5 - 205, sub_y, 410, 24), Color(0.24, 0.04, 0.12, 0.86) if out_storm else Color(0.12, 0.05, 0.14, 0.76))
			overlay.draw_rect(Rect2(vs.x * 0.5 - 205, sub_y, 410, 24), st_col, false, 2.0)
			_text(overlay, Vector2(0, sub_y + 17.0), st_txt, 14, st_col.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
			sub_y += 28.0
		if p.room_buff != "":
			var rinfo := game.room_info(p.room_buff)
			if not rinfo.is_empty():
				var rcol: Color = rinfo["color"]
				var rdesc := str(rinfo["desc"])
				if p.room_buff == "heal_spring":
					rdesc = "脱战缓回中 +6/秒" if p.out_of_combat >= 3.0 else "交战中暂停，%.1fs 后缓回" % (3.0 - p.out_of_combat)
				overlay.draw_rect(Rect2(vs.x * 0.5 - 190, sub_y, 380, 26), Color(0.05, 0.08, 0.14, 0.78))
				overlay.draw_rect(Rect2(vs.x * 0.5 - 190, sub_y, 380, 26), rcol, false, 1.8)
				_text(overlay, Vector2(0, sub_y + 18.0), "当前房间：%s（%s）" % [rinfo["name"], rdesc], 14, rcol, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# 右上：2v2v2v2 团队榜 / PVP 个人榜 / 幸存者战况
	var x0 := vs.x - 256.0
	if game.game_mode == "survivor" and game.swarm != null:
		overlay.draw_rect(Rect2(x0 - 10, 12, 250, 124), Color(0, 0, 0, 0.45))
		_text(overlay, Vector2(x0, 36), "双人合作 · 无尽潮汐" if game.is_coop else "算力潮汐 · 幸存者", 18, Color(1, 0.82, 0.38))
		_text(overlay, Vector2(x0, 64), "当前怪潮数：%d" % game.swarm.monsters.size(), 15, Color(1, 0.65, 0.72))
		_text(overlay, Vector2(x0, 88), "累计消灭：%d" % game.swarm.monster_kills, 15, Color(0.68, 1.0, 0.78))
		_text(overlay, Vector2(x0, 112), "当前 FPS：%d" % Engine.get_frames_per_second(), 14, Color(0.75, 0.88, 1.0))
	elif game.pvp_variant == "2v2v2v2":
		overlay.draw_rect(Rect2(x0 - 10, 12, 250, 144), Color(0, 0, 0, 0.46))
		_text(overlay, Vector2(x0, 36), "四阵营积分榜 (2v2v2v2)", 17, Color(1, 0.85, 0.4))
		var tr := game.team_ranking()
		for i in tr.size():
			var td := tr[i]
			var is_mine := (int(td["team"]) == p.team_id)
			var col: Color = td["color"]
			var tag := "%d. %s%s" % [i + 1, td["name"], " (我队)" if is_mine else ""]
			_text(overlay, Vector2(x0, 64 + i * 24), tag, 15, col)
			_text(overlay, Vector2(x0, 64 + i * 24), str(td["score"]), 15, col, HORIZONTAL_ALIGNMENT_RIGHT, 226)
	else:
		overlay.draw_rect(Rect2(x0 - 10, 12, 250, 178), Color(0, 0, 0, 0.42))
		_text(overlay, Vector2(x0, 36), "排行榜（五宫格 PVP）", 18, Color(1, 0.85, 0.4))
		var rank := game.ranking()
		var my_rank := rank.find(p) + 1
		for i in mini(5, rank.size()):
			var a := rank[i]
			var col := Color(1, 0.95, 0.4) if a == p else Color.WHITE
			_text(overlay, Vector2(x0, 64 + i * 24), "%d. %s" % [i + 1, a.display_name], 15, col)
			_text(overlay, Vector2(x0, 64 + i * 24), str(a.score), 15, col, HORIZONTAL_ALIGNMENT_RIGHT, 226)
		if my_rank > 5:
			_text(overlay, Vector2(x0, 182), "%d. %s" % [my_rank, p.display_name], 15, Color(1, 0.95, 0.4))
			_text(overlay, Vector2(x0, 182), str(p.score), 15, Color(1, 0.95, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 226)

	# 小地图（支持 PVP 五宫格特殊房底色与石墙显示！）
	var mm := Rect2(vs.x - 166, 202, 154, 154)
	overlay.draw_rect(mm, Color(0.10, 0.13, 0.18, 0.72) if game.game_mode == "pvp" else Color(0.08, 0.16, 0.10, 0.65))
	var k := mm.size.x / (Game.ARENA_HALF * 2.0)
	for rm in game.special_rooms:
		var rrc: Rect2 = rm["rect"]
		var mrc := Rect2(mm.position + (rrc.position + Vector2.ONE * Game.ARENA_HALF) * k, rrc.size * k)
		var rc_col: Color = rm["color"]
		overlay.draw_rect(mrc, Color(rc_col.r, rc_col.g, rc_col.b, 0.28))
	for w in game.walls:
		var wrc := Rect2(mm.position + (w.position + Vector2.ONE * Game.ARENA_HALF) * k, Vector2(maxf(w.size.x * k, 2.0), maxf(w.size.y * k, 2.0)))
		overlay.draw_rect(wrc, Color(0.75, 0.84, 0.96, 0.90))
	overlay.draw_rect(mm, Color(1, 1, 1, 0.55), false, 2.0)
	for r in game.rocks:
		overlay.draw_circle(mm.position + (Vector2(r.x, r.y) + Vector2.ONE * Game.ARENA_HALF) * k, maxf(r.z * k, 2.0), Color(0.6, 0.62, 0.68, 0.7))
	for h in game.pickups.hearts:
		var hp_pt := mm.position + ((h["pos"] as Vector2) + Vector2.ONE * Game.ARENA_HALF) * k
		overlay.draw_circle(hp_pt, 2.2, Color(1.0, 0.42, 0.62))
	for mag in game.pickups.magnets:
		var mp_pt := mm.position + ((mag["pos"] as Vector2) + Vector2.ONE * Game.ARENA_HALF) * k
		overlay.draw_circle(mp_pt, 3.2, Color(0.32, 0.95, 1.0))
	for ch in game.pickups.chests:
		var cp_pt := mm.position + ((ch["pos"] as Vector2) + Vector2.ONE * Game.ARENA_HALF) * k
		overlay.draw_circle(cp_pt, 4.2, Color(1.0, 0.88, 0.28))
	for tr in game.pvp_traps:
		var tpt := mm.position + (game.pvp_trap_pos(tr) + Vector2.ONE * Game.ARENA_HALF) * k
		overlay.draw_circle(tpt, 2.4, Color("#ff3848"))
	for cr in game.pvp_creeps:
		var cpt := mm.position + ((cr["pos"] as Vector2) + Vector2.ONE * Game.ARENA_HALF) * k
		overlay.draw_circle(cpt, 2.6, Color("#d482ff"))
	for sh in game.pvp_runes:
		var spt := mm.position + ((sh["pos"] as Vector2) + Vector2.ONE * Game.ARENA_HALF) * k
		var sk := str(sh["kind"])
		if sk != "" and Archer.RUNE_DEFS.has(sk):
			var scol: Color = Archer.RUNE_DEFS[sk]["color"]
			overlay.draw_circle(spt, 4.4, scol)
			overlay.draw_circle(spt, 1.8, Color.WHITE)
		else:
			overlay.draw_arc(spt, 3.4, 0.0, TAU, 12, Color(0.6, 0.75, 0.9, 0.55), 1.2)
	if not game.mid_boss.is_empty():
		var mbpt := mm.position + ((game.mid_boss["pos"] as Vector2) + Vector2.ONE * Game.ARENA_HALF) * k
		overlay.draw_circle(mbpt, 5.8, Color("#ffd84a"))
		overlay.draw_circle(mbpt, 3.6, Color("#ff2e63"))
	if game.storm_active:
		var mm_c := mm.get_center()
		overlay.draw_arc(mm_c, minf(game.storm_radius * k, mm.size.x * 0.71), 0.0, TAU, 36, Color("#ff3878"), 2.0)
	if game.game_mode == "survivor" and game.swarm != null:
		for m in game.swarm.monsters:
			var mpt := mm.position + ((m["pos"] as Vector2) + Vector2.ONE * Game.ARENA_HALF) * k
			overlay.draw_circle(mpt, 4.2 if bool(m["is_boss"]) else 2.0, Color("#ff3864") if bool(m["is_boss"]) else Color("#ff8866", 0.75))
	for a in game.archers:
		if not a.alive:
			continue
		var mp := mm.position + (a.position + Vector2.ONE * Game.ARENA_HALF) * k
		var dcol: Color = Color(1, 0.95, 0.4) if a == p else (NetManager.TEAM_COLORS[clampi(a.team_id, 0, 4)] if (a.team_id > 0 and game.game_mode == "pvp") else a.color)
		overlay.draw_circle(mp, 5.0 if a == p else 3.2, dcol)
		if a == p and p.locate_timer > 0.0:
			var pulse_mm := fposmod(p.anim_t * 2.0, 1.0)
			overlay.draw_arc(mp, 6.0 + pulse_mm * 16.0, 0.0, TAU, 20, Color(1.0, 0.94, 0.32, 1.0 - pulse_mm), 2.2)

	for i in feed.size():
		var f := feed[i]
		var c := Color(1, 1, 1, clampf(float(f["t"]), 0.0, 1.0))
		_text(overlay, Vector2(vs.x - 420, 390 + i * 24), str(f["msg"]), 15, c, HORIZONTAL_ALIGNMENT_RIGHT, 408)

	if game.game_mode == "pvp" and not p.alive and p.respawn_timer > 0.0 and not game.game_over:
		var rbox := Rect2(vs.x * 0.5 - 230, vs.y * 0.42, 460, 74)
		overlay.draw_rect(rbox, Color(0.08, 0.05, 0.14, 0.86))
		overlay.draw_rect(rbox, Color("#ff6b8b"), false, 2.4)
		_text(overlay, Vector2(0, rbox.position.y + 32), "已阵亡 · %.1f 秒后复活重返战场" % p.respawn_timer, 24, Color("#ff8aa2"), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(overlay, Vector2(0, rbox.position.y + 58), "复活等级减半（Lv%d → Lv%d） · 击杀分完整保留！" % [p.level, maxi(1, int(p.level / 2))], 15, Color(0.92, 0.96, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	if hint_time > 0.0:
		var c := Color(1, 1, 1, clampf(hint_time, 0.0, 1.0))
		var htxt := ""
		if is_touch_ui:
			htxt = ("左下摇杆移动 · 右下独立摇杆随时手动瞄准（不挡人物视野！已开自动火） · 大招在右摇杆左上方"
				if game.game_mode == "survivor"
				else "左下摇杆移动 · 右下独立摇杆瞄准开火（完全脱离角色中心，绝不挡视野！） · 大招在右摇杆左上方")
		else:
			htxt = ("WASD/左摇杆走位 · 辅助自动开火（左键/右摇杆可手动） · 空格/右键大招 · [1-4/T] 热梗气泡"
				if game.game_mode == "survivor"
				else "WASD/左摇杆移动 · 左键/右摇杆瞄准开火 · 空格/右键放技能 · [1-4/T] 发战内热梗气泡")
		_text(overlay, Vector2(0, vs.y - 16), htxt, 14, c, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	# 触屏设备：常驻显示半透明「左下移动摇杆」与「右下独立瞄准摇杆」（完全脱离角色中心，绝不挡视野！）
	if is_touch_ui and _move_joy_idx == -1:
		var rl := Vector2(126.0, vs.y - 138.0)
		overlay.draw_circle(rl, JOY_R, Color(0.4, 0.78, 1.0, 0.10))
		overlay.draw_arc(rl, JOY_R, 0.0, TAU, 32, Color(0.48, 0.86, 1.0, 0.36), 2.5)
		overlay.draw_circle(rl, 22.0, Color(0.65, 0.92, 1.0, 0.30))
		_text(overlay, rl + Vector2(-60, JOY_R + 18), "左下·移动", 13, Color(0.75, 0.94, 1.0, 0.72), HORIZONTAL_ALIGNMENT_CENTER, 120)

	if is_touch_ui and _aim_joy_idx == -1:
		var rr := Vector2(vs.x - 126.0, vs.y - 138.0)
		overlay.draw_circle(rr, JOY_R, Color(1.0, 0.66, 0.24, 0.11))
		overlay.draw_arc(rr, JOY_R, 0.0, TAU, 32, Color(1.0, 0.78, 0.36, 0.42), 2.5)
		overlay.draw_circle(rr, 22.0, Color(1.0, 0.82, 0.42, 0.34))
		_text(overlay, rr + Vector2(-72, JOY_R + 18), "右下·拖动瞄准", 13, Color(1.0, 0.90, 0.62, 0.80), HORIZONTAL_ALIGNMENT_CENTER, 144)

	if _move_joy_idx != -1:
		overlay.draw_circle(_move_joy_center, JOY_R, Color(0.4, 0.75, 1.0, 0.16))
		overlay.draw_arc(_move_joy_center, JOY_R, 0.0, TAU, 36, Color(0.5, 0.85, 1.0, 0.60), 3.0)
		overlay.draw_circle(_move_joy_knob, 28.0, Color(0.65, 0.9, 1.0, 0.62))

	if _aim_joy_idx != -1:
		overlay.draw_circle(_aim_joy_center, JOY_R, Color(1.0, 0.65, 0.25, 0.18))
		overlay.draw_arc(_aim_joy_center, JOY_R, 0.0, TAU, 36, Color(1.0, 0.78, 0.35, 0.75), 3.2)
		overlay.draw_circle(_aim_joy_knob, 28.0, Color(1.0, 0.82, 0.4, 0.72))
		if aim_joy_vec.length() > 0.14:
			var adir := aim_joy_vec.normalized()
			overlay.draw_line(_aim_joy_center, _aim_joy_center + adir * (JOY_R + 18.0), Color(1, 0.92, 0.5, 0.92), 3.5)


func _draw_fx_overlay() -> void:
	# 玩家受击四周微红边框闪烁反馈
	if _dmg_flash > 0.01:
		var vs := fx_overlay.size
		var a := _dmg_flash * 0.34
		var edge := 26.0
		var c := Color(1.0, 0.16, 0.22, a)
		fx_overlay.draw_rect(Rect2(0, 0, vs.x, edge), c)
		fx_overlay.draw_rect(Rect2(0, vs.y - edge, vs.x, edge), c)
		fx_overlay.draw_rect(Rect2(0, edge, edge, vs.y - edge * 2.0), c)
		fx_overlay.draw_rect(Rect2(vs.x - edge, edge, edge, vs.y - edge * 2.0), c)
		fx_overlay.draw_rect(Rect2(2, 2, vs.x - 4, vs.y - 4), Color(1.0, 0.25, 0.3, _dmg_flash * 0.65), false, 4.0)

	for sp in hud_sparks:
		var k := 1.0 - float(sp["t"]) / float(sp["life"])
		var pos := sp["pos"] as Vector2
		var r := float(sp["r"]) * k
		var c: Color = sp["col"]
		fx_overlay.draw_circle(pos, r, Color(c.r, c.g, c.b, k))
		fx_overlay.draw_line(pos - Vector2(r * 2.2, 0), pos + Vector2(r * 2.2, 0), Color(1, 1, 1, k), 2.0)
		fx_overlay.draw_line(pos - Vector2(0, r * 2.2), pos + Vector2(0, r * 2.2), Color(1, 1, 1, k), 2.0)

	if banner_t > 0.0 and banner_text != "":
		var a := clampf(banner_t * 1.4, 0.0, 1.0)
		var vs := fx_overlay.size
		var y := 146.0 - (1.0 - a) * 14.0
		var bfs := 18
		var tw := PixelSprites.ui_font().get_string_size(banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x
		var bw := clampf(tw + 48.0, 380.0, vs.x - 140.0)
		fx_overlay.draw_rect(Rect2(vs.x * 0.5 - bw * 0.5, y - 24, bw, 36), Color(0.06, 0.08, 0.15, 0.86 * a))
		fx_overlay.draw_rect(Rect2(vs.x * 0.5 - bw * 0.5, y - 24, bw, 36), Color(banner_col.r, banner_col.g, banner_col.b, 0.92 * a), false, 2.0)
		_text(fx_overlay, Vector2(0, y), banner_text, bfs, Color(banner_col.r, banner_col.g, banner_col.b, a).lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
