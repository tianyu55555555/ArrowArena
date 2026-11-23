class_name Lobby
extends Control
## 备战大厅：Live2D 互动立绘 + 32x32 像素预览 + 6角色/6武器 + 双模式 + 4难度(含极限无尽与背景设定) + 局外算力天赋树 + 双标签科普图鉴馆

signal start_battle(char_id: String, weapon_id: String, mode: String, diff_id: String, pvp_var: String)

var selected_char := "claude"
var selected_weapon := "grimoire"
var selected_mode := "pvp"
var selected_pvp_var := "ffa"  # "ffa" | "2v2v2v2"
var selected_diff := "normal"
var open_talents_on_ready := false
var open_codex_on_ready := false
var open_lan_on_ready := false

var _bg: Control
var _live2d: Live2dView
var _name_label: Label
var _pixel_preview: TextureRect
var _pixel_weapon_preview: TextureRect
var _passive_label: Label
var _active_label: Label
var _weapon_desc_label: Label
var _diff_box: VBoxContainer
var _diff_lore_label: Label
var _pvp_box: VBoxContainer
var _pvp_ffa_btn: Button
var _pvp_team_btn: Button
var _pvp_note_label: Label
var _start_btn: Button
var _mute_btn: Button
var _bgm_btn: Button
var _talent_top_btn: Button
var _lan_top_btn: Button
var _mode_pvp_btn: Button
var _mode_surv_btn: Button
var _char_buttons: Dictionary = {}
var _weapon_buttons: Dictionary = {}
var _diff_buttons: Dictionary = {}

# 局域网联机弹窗
var _lan_modal: PanelContainer
var _lan_entry_box: VBoxContainer
var _lan_room_box: VBoxContainer
var _lan_status_lbl: Label
var _lan_nick_edit: LineEdit
var _lan_ip_edit: LineEdit
var _lan_disc_box: VBoxContainer
var _lan_room_header: Label
var _lan_mode_btns: Dictionary = {}
var _lan_bots_btn: Button
var _lan_roster_box: VBoxContainer
var _lan_start_btn: Button
var _lan_leave_btn: Button

# 算力天赋树弹窗
var _talent_modal: PanelContainer
var _talent_cp_label: Label
var _talent_stats_label: Label
var _talent_cards: Dictionary = {}
var _codex_unlock_btn: Button

# 三标签科普图鉴馆弹窗（AI 模型档案 / AI 公益科普 / 怪物概念档案）
var _tips_modal: PanelContainer
var _codex_tab := "models"  # "models" | "tips" | "monsters"
var _model_index := 0
var _tips_index := 0
var _monster_index := 0
var _tab_models_btn: Button
var _tab_tips_btn: Button
var _tab_mon_btn: Button
var _tips_tag: Label
var _tips_title: Label
var _tips_body: Label
var _tips_page: Label
var _monster_icon: TextureRect

var _bg_top := Color(0.16, 0.11, 0.12)
var _bg_bot := Color(0.28, 0.16, 0.14)
var _target_top := Color(0.16, 0.11, 0.12)
var _target_bot := Color(0.28, 0.16, 0.14)
var _anim_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MetaSave.ensure_loaded()
	var th := Theme.new()
	th.default_font = PixelSprites.ui_font()
	th.default_font_size = 15
	theme = th

	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(_draw_bg)
	add_child(_bg)

	var main_vb := VBoxContainer.new()
	main_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vb.offset_left = 22
	main_vb.offset_right = -22
	main_vb.offset_top = 8
	main_vb.offset_bottom = -6
	main_vb.add_theme_constant_override("separation", 5)
	add_child(main_vb)

	# --- 顶部栏（精简清爽：去掉标题后冗长介绍）---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	main_vb.add_child(top_bar)

	var brand := Label.new()
	brand.text = "AI 娘像素大乱斗"
	brand.add_theme_font_size_override("font_size", 26)
	brand.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72))
	top_bar.add_child(brand)

	var top_sp := Control.new()
	top_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_sp)

	_lan_top_btn = Button.new()
	_lan_top_btn.text = "🌐 局域网联机"
	_lan_top_btn.custom_minimum_size = Vector2(142, 36)
	_lan_top_btn.focus_mode = Control.FOCUS_NONE
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.10, 0.24, 0.36, 0.94)
	lsb.set_corner_radius_all(10)
	lsb.border_color = Color(0.36, 0.88, 1.0)
	lsb.set_border_width_all(2)
	_lan_top_btn.add_theme_stylebox_override("normal", lsb)
	var lsbh := lsb.duplicate() as StyleBoxFlat
	lsbh.bg_color = Color(0.16, 0.34, 0.50, 0.98)
	_lan_top_btn.add_theme_stylebox_override("hover", lsbh)
	_lan_top_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_open_lan_modal()
	)
	_lan_top_btn.visible = not OS.has_feature("web")
	top_bar.add_child(_lan_top_btn)

	_talent_top_btn = Button.new()
	_talent_top_btn.custom_minimum_size = Vector2(168, 36)
	_talent_top_btn.focus_mode = Control.FOCUS_NONE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.32, 0.22, 0.08, 0.92)
	tsb.set_corner_radius_all(10)
	tsb.border_color = Color(1.0, 0.84, 0.34)
	tsb.set_border_width_all(2)
	_talent_top_btn.add_theme_stylebox_override("normal", tsb)
	var tsbh := tsb.duplicate() as StyleBoxFlat
	tsbh.bg_color = Color(0.45, 0.32, 0.12, 0.96)
	_talent_top_btn.add_theme_stylebox_override("hover", tsbh)
	_talent_top_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_open_talent_modal()
	)
	top_bar.add_child(_talent_top_btn)

	var wiki_btn := Button.new()
	wiki_btn.text = "科普图鉴馆"
	wiki_btn.custom_minimum_size = Vector2(108, 36)
	wiki_btn.focus_mode = Control.FOCUS_NONE
	wiki_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_open_tips_modal()
	)
	top_bar.add_child(wiki_btn)

	_bgm_btn = Button.new()
	_bgm_btn.text = "音乐: 关" if Sfx.bgm_muted else "音乐: 开"
	_bgm_btn.custom_minimum_size = Vector2(82, 36)
	_bgm_btn.focus_mode = Control.FOCUS_NONE
	_bgm_btn.pressed.connect(func() -> void:
		var m := Sfx.toggle_bgm_mute()
		_bgm_btn.text = "音乐: 关" if m else "音乐: 开"
		Sfx.play("ui_click")
	)
	top_bar.add_child(_bgm_btn)

	_mute_btn = Button.new()
	_mute_btn.text = "音效: 关" if Sfx.muted else "音效: 开"
	_mute_btn.custom_minimum_size = Vector2(82, 36)
	_mute_btn.focus_mode = Control.FOCUS_NONE
	_mute_btn.pressed.connect(func() -> void:
		var m := Sfx.toggle_mute()
		_mute_btn.text = "音效: 关" if m else "音效: 开"
		if not m:
			Sfx.play("ui_click")
	)
	top_bar.add_child(_mute_btn)

	# --- 主体左右分栏 ---
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	main_vb.add_child(body)

	var footer_note := Label.new()
	footer_note.text = ("网页单人试玩版（支持 iOS / 安卓 / 电脑） · 手机请横屏游玩 · 非官方免费公益同人二创，严禁商用"
		if OS.has_feature("web")
		else "非官方免费公益同人二创 · 仅限学习交流与亲友局域网联机，严禁任何商业用途 · 纯本地存档无联网上报")
	footer_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_note.add_theme_font_size_override("font_size", 11)
	footer_note.add_theme_color_override("font_color", Color(0.62, 0.70, 0.82, 0.72))
	main_vb.add_child(footer_note)

	# 左侧 Live2D 展示区
	var left_stage := Control.new()
	left_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_stage.size_flags_stretch_ratio = 0.92
	body.add_child(left_stage)

	_live2d = Live2dView.new()
	_live2d.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_stage.add_child(_live2d)

	var plate := PanelContainer.new()
	plate.anchor_top = 1.0
	plate.anchor_bottom = 1.0
	plate.anchor_left = 0.0
	plate.anchor_right = 1.0
	plate.offset_top = -98
	plate.offset_bottom = -6
	plate.offset_left = 8
	plate.offset_right = -8
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.08, 0.14, 0.85)
	psb.set_corner_radius_all(14)
	psb.set_content_margin_all(11)
	psb.border_color = Color(1, 1, 1, 0.22)
	psb.set_border_width_all(1)
	plate.add_theme_stylebox_override("panel", psb)
	left_stage.add_child(plate)

	var plate_hb := HBoxContainer.new()
	plate_hb.add_theme_constant_override("separation", 12)
	plate.add_child(plate_hb)

	var name_vb := VBoxContainer.new()
	name_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	name_vb.add_theme_constant_override("separation", 4)
	plate_hb.add_child(name_vb)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	name_vb.add_child(_name_label)

	var l2d_hint := Label.new()
	l2d_hint.text = "点击立绘互动对话 · 移动鼠标视线跟随"
	l2d_hint.add_theme_font_size_override("font_size", 12)
	l2d_hint.add_theme_color_override("font_color", Color(0.68, 0.76, 0.88, 0.85))
	name_vb.add_child(l2d_hint)

	var px_box := VBoxContainer.new()
	px_box.alignment = BoxContainer.ALIGNMENT_CENTER
	plate_hb.add_child(px_box)

	var px_tag := Label.new()
	px_tag.text = "32px 像素形态"
	px_tag.add_theme_font_size_override("font_size", 11)
	px_tag.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	px_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	px_box.add_child(px_tag)

	var px_row := HBoxContainer.new()
	px_row.alignment = BoxContainer.ALIGNMENT_CENTER
	px_row.add_theme_constant_override("separation", 6)
	px_box.add_child(px_row)

	_pixel_preview = TextureRect.new()
	_pixel_preview.custom_minimum_size = Vector2(56, 56)
	_pixel_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pixel_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	px_row.add_child(_pixel_preview)

	_pixel_weapon_preview = TextureRect.new()
	_pixel_weapon_preview.custom_minimum_size = Vector2(44, 38)
	_pixel_weapon_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pixel_weapon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pixel_weapon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	px_row.add_child(_pixel_weapon_preview)

	# --- 右侧配置面板 ---
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.18
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.07, 0.09, 0.15, 0.88)
	rsb.set_corner_radius_all(18)
	rsb.set_content_margin_all(11)
	rsb.border_color = Color(1, 1, 1, 0.16)
	rsb.set_border_width_all(2)
	right_panel.add_theme_stylebox_override("panel", rsb)
	body.add_child(right_panel)

	var rvb := VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 5)
	right_panel.add_child(rvb)

	# 1. 选角色
	rvb.add_child(_section_header("1. 选择出战 AI 少女（6 位专属技能角色）"))
	var char_grid := GridContainer.new()
	char_grid.columns = 3
	char_grid.add_theme_constant_override("h_separation", 8)
	char_grid.add_theme_constant_override("v_separation", 6)
	rvb.add_child(char_grid)

	for cid in Characters.ORDER:
		var cd := Characters.get_data(cid)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 64)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_contents = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_select_char.bind(cid, true))
		char_grid.add_child(btn)

		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 7; hb.offset_right = -7; hb.offset_top = 5; hb.offset_bottom = -5
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(hb)

		var av := TextureRect.new()
		av.texture = load(str(cd["avatar"])) as Texture2D
		av.custom_minimum_size = Vector2(52, 52)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(av)

		var ivb := VBoxContainer.new()
		ivb.alignment = BoxContainer.ALIGNMENT_CENTER
		ivb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ivb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ivb)

		var nl := Label.new()
		nl.text = str(cd["name"])
		nl.add_theme_font_size_override("font_size", 16)
		nl.add_theme_color_override("font_color", Color.WHITE)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ivb.add_child(nl)

		var wl := Label.new()
		wl.text = str(Weapons.get_data(str(cd["weapon"]))["name"])
		wl.add_theme_font_size_override("font_size", 11)
		wl.add_theme_color_override("font_color", cd["accent"])
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ivb.add_child(wl)
		_char_buttons[cid] = btn

	# 技能简介框
	var skill_box := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.11, 0.14, 0.22, 0.90)
	ssb.set_corner_radius_all(10)
	ssb.set_content_margin_all(9)
	skill_box.add_theme_stylebox_override("panel", ssb)
	rvb.add_child(skill_box)

	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 3)
	skill_box.add_child(svb)

	_passive_label = Label.new()
	_passive_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passive_label.add_theme_font_size_override("font_size", 13)
	_passive_label.add_theme_color_override("font_color", Color(0.84, 0.96, 1.0))
	svb.add_child(_passive_label)

	_active_label = Label.new()
	_active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_active_label.add_theme_font_size_override("font_size", 13)
	_active_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.62))
	svb.add_child(_active_label)

	# 2. 武器选择
	rvb.add_child(_section_header("2. 武装选择（默认本命武器，可自由跨界搭配）"))
	var w_grid := GridContainer.new()
	w_grid.columns = 3
	w_grid.add_theme_constant_override("h_separation", 7)
	w_grid.add_theme_constant_override("v_separation", 6)
	rvb.add_child(w_grid)

	for wid in Weapons.ORDER:
		var wd := Weapons.get_data(wid)
		var wb := Button.new()
		wb.custom_minimum_size = Vector2(0, 42)
		wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wb.focus_mode = Control.FOCUS_NONE
		wb.pressed.connect(_select_weapon.bind(wid))
		w_grid.add_child(wb)

		var whb := HBoxContainer.new()
		whb.set_anchors_preset(Control.PRESET_FULL_RECT)
		whb.offset_left = 7; whb.offset_right = -7; whb.offset_top = 3; whb.offset_bottom = -3
		whb.add_theme_constant_override("separation", 6)
		whb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wb.add_child(whb)

		var wic := TextureRect.new()
		wic.texture = PixelSprites.get_weapon_texture(wid)
		wic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wic.custom_minimum_size = Vector2(32, 26)
		wic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		whb.add_child(wic)

		var wvb := VBoxContainer.new()
		wvb.alignment = BoxContainer.ALIGNMENT_CENTER
		wvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		whb.add_child(wvb)

		var wnl := Label.new()
		wnl.text = str(wd["name"])
		wnl.add_theme_font_size_override("font_size", 13)
		wnl.add_theme_color_override("font_color", Color.WHITE)
		wnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wvb.add_child(wnl)

		var wsl := Label.new()
		wsl.text = str(wd["short"])
		wsl.add_theme_font_size_override("font_size", 10)
		wsl.add_theme_color_override("font_color", wd["color"])
		wsl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wvb.add_child(wsl)
		_weapon_buttons[wid] = wb

	_weapon_desc_label = Label.new()
	_weapon_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon_desc_label.add_theme_font_size_override("font_size", 12)
	_weapon_desc_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.96))
	rvb.add_child(_weapon_desc_label)

	# 3. 双玩法模式 + 幸存者四档难度与背景任务简报
	rvb.add_child(_section_header("3. 模式与难度（算力潮汐可赚高倍率算力点升级永久天赋）"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	rvb.add_child(mode_row)

	_mode_pvp_btn = Button.new()
	_mode_pvp_btn.text = "竞技乱斗（平衡 PVP）· 纯公平拉扯"
	_mode_pvp_btn.custom_minimum_size = Vector2(0, 38)
	_mode_pvp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_pvp_btn.add_theme_font_size_override("font_size", 14)
	_mode_pvp_btn.focus_mode = Control.FOCUS_NONE
	_mode_pvp_btn.pressed.connect(_select_mode.bind("pvp"))
	mode_row.add_child(_mode_pvp_btn)

	_mode_surv_btn = Button.new()
	_mode_surv_btn.text = "算力潮汐（吸血鬼幸存者）· 怪潮割草"
	_mode_surv_btn.custom_minimum_size = Vector2(0, 38)
	_mode_surv_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_surv_btn.add_theme_font_size_override("font_size", 14)
	_mode_surv_btn.focus_mode = Control.FOCUS_NONE
	_mode_surv_btn.pressed.connect(_select_mode.bind("survivor"))
	mode_row.add_child(_mode_surv_btn)

	# 幸存者专属 4 档难度行 + 世界观坚守背景
	_diff_box = VBoxContainer.new()
	_diff_box.add_theme_constant_override("separation", 5)
	rvb.add_child(_diff_box)

	var d_row := HBoxContainer.new()
	d_row.add_theme_constant_override("separation", 6)
	_diff_box.add_child(d_row)

	for did in Difficulties.ORDER:
		var dd := Difficulties.get_data(did)
		var db := Button.new()
		db.custom_minimum_size = Vector2(0, 44)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.add_theme_font_size_override("font_size", 12)
		db.focus_mode = Control.FOCUS_NONE
		db.pressed.connect(_select_diff.bind(did))
		d_row.add_child(db)
		_diff_buttons[did] = db

	_diff_lore_label = Label.new()
	_diff_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_lore_label.add_theme_font_size_override("font_size", 12)
	_diff_lore_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
	_diff_box.add_child(_diff_lore_label)

	_pvp_box = VBoxContainer.new()
	_pvp_box.add_theme_constant_override("separation", 5)
	rvb.add_child(_pvp_box)

	var pvp_sub_row := HBoxContainer.new()
	pvp_sub_row.add_theme_constant_override("separation", 8)
	_pvp_box.add_child(pvp_sub_row)

	_pvp_ffa_btn = Button.new()
	_pvp_ffa_btn.text = "五宫格自由乱斗 (FFA)"
	_pvp_ffa_btn.custom_minimum_size = Vector2(0, 36)
	_pvp_ffa_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pvp_ffa_btn.add_theme_font_size_override("font_size", 13)
	_pvp_ffa_btn.focus_mode = Control.FOCUS_NONE
	_pvp_ffa_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		selected_pvp_var = "ffa"
		_refresh_button_styles()
	)
	pvp_sub_row.add_child(_pvp_ffa_btn)

	_pvp_team_btn = Button.new()
	_pvp_team_btn.text = "五宫格四阵营组队 (2v2v2v2)"
	_pvp_team_btn.custom_minimum_size = Vector2(0, 36)
	_pvp_team_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pvp_team_btn.add_theme_font_size_override("font_size", 13)
	_pvp_team_btn.focus_mode = Control.FOCUS_NONE
	_pvp_team_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		selected_pvp_var = "2v2v2v2"
		_refresh_button_styles()
	)
	pvp_sub_row.add_child(_pvp_team_btn)

	_pvp_note_label = Label.new()
	_pvp_note_label.text = "五宫格决斗场：死亡3s复活掉半级，最终按击杀分+等级分结算！区域厚墙单口，量子穿墙/穿墙弹仅穿室内薄墙！"
	_pvp_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pvp_note_label.add_theme_font_size_override("font_size", 12)
	_pvp_note_label.add_theme_color_override("font_color", Color(0.72, 0.88, 0.98))
	_pvp_box.add_child(_pvp_note_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rvb.add_child(spacer)

	_start_btn = Button.new()
	_start_btn.custom_minimum_size = Vector2(0, 46)
	_start_btn.add_theme_font_size_override("font_size", 21)
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.pressed.connect(func() -> void:
		Sfx.play("card_pick", 0.02, 80, -8.0)
		start_battle.emit(selected_char, selected_weapon, selected_mode, selected_diff, selected_pvp_var)
	)
	rvb.add_child(_start_btn)

	_build_talent_modal()
	_build_tips_modal()
	_build_lan_modal()
	_select_char(selected_char, false)
	_refresh_meta_ui()
	if NetManager.inst != null:
		NetManager.inst.room_updated.connect(_refresh_lan_modal)
		NetManager.inst.discovery_updated.connect(_refresh_lan_discovery)
		NetManager.inst.connection_status.connect(_on_lan_status)
	if open_talents_on_ready:
		_open_talent_modal()
	elif open_codex_on_ready:
		_open_tips_modal()
	elif open_lan_on_ready or NetManager.is_online():
		_open_lan_modal()


func _section_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.62))
	return l


func _select_char(cid: String, animate := true) -> void:
	if animate:
		Sfx.play("ui_click")
	selected_char = cid
	var d := Characters.get_data(cid)
	_target_top = d["bg_top"]
	_target_bot = d["bg_bot"]
	if not animate:
		_bg_top = _target_top
		_bg_bot = _target_bot

	_live2d.set_character(cid, animate)
	_name_label.text = str(d["name"])
	_passive_label.text = "【被动 · %s】%s" % [d["passive_name"], d["passive_desc"]]
	_active_label.text = "【主动 Space · %s】(CD %ds) %s" % [d["active_name"], int(round(float(d["active_cd"]))), d["active_desc"]]
	selected_weapon = str(d["weapon"])
	_refresh_button_styles()
	_refresh_weapon_info()
	if NetManager.is_online() and NetManager.inst != null:
		NetManager.inst.update_my_profile(selected_char, selected_weapon)


func _select_weapon(wid: String) -> void:
	Sfx.play("ui_click")
	selected_weapon = wid
	_refresh_button_styles()
	_refresh_weapon_info()
	if NetManager.is_online() and NetManager.inst != null:
		NetManager.inst.update_my_profile(selected_char, selected_weapon)


func _select_mode(m: String) -> void:
	Sfx.play("ui_click")
	selected_mode = m
	_refresh_button_styles()


func _select_diff(d: String) -> void:
	Sfx.play("ui_click")
	selected_diff = d
	_refresh_button_styles()


func _refresh_weapon_info() -> void:
	var wd := Weapons.get_data(selected_weapon)
	var cd := Characters.get_data(selected_char)
	var tag := "【本命推荐】" if selected_weapon == str(cd["weapon"]) else "【跨界武装】"
	_weapon_desc_label.text = "%s %s：%s" % [tag, wd["name"], wd["desc"]]
	_pixel_weapon_preview.texture = PixelSprites.get_weapon_texture(selected_weapon)


func _refresh_meta_ui() -> void:
	_talent_top_btn.text = "⚡ 算力天赋 (%d点)" % MetaSave.compute_points()
	for did in Difficulties.ORDER:
		var dd := Difficulties.get_data(did)
		var b := _diff_buttons[did] as Button
		var extra := ""
		if did == "endless":
			var best := int(MetaSave.data["best_endless_sec"])
			extra = "最佳 %d:%02d" % [best / 60, best % 60] if best > 0 else "×3.0算力"
		else:
			extra = "★已通关" if MetaSave.is_diff_cleared(did) else "×%.1f算力" % float(dd["cp_mult"])
		b.text = "%s (%s)\n%s" % [dd["name"], dd["short"].split("·")[0].strip_edges(), extra]


func _refresh_button_styles() -> void:
	var cd := Characters.get_data(selected_char)
	var theme_col: Color = cd["color"]
	var accent_col: Color = cd["accent"]

	for cid: String in _char_buttons:
		var b := _char_buttons[cid] as Button
		var d := Characters.get_data(cid)
		var sel := (cid == selected_char)
		b.add_theme_stylebox_override("normal", _card_sb(sel, d["color"], d["accent"]))
		b.add_theme_stylebox_override("hover", _card_sb(sel, d["color"], d["accent"], true))
		b.add_theme_stylebox_override("pressed", _card_sb(true, d["color"], d["accent"]))

	for wid: String in _weapon_buttons:
		var wb := _weapon_buttons[wid] as Button
		var wd := Weapons.get_data(wid)
		var sel := (wid == selected_weapon)
		wb.add_theme_stylebox_override("normal", _card_sb(sel, wd["color"], wd["color"]))
		wb.add_theme_stylebox_override("hover", _card_sb(sel, wd["color"], wd["color"], true))
		wb.add_theme_stylebox_override("pressed", _card_sb(true, wd["color"], wd["color"]))

	var pvp_sel := (selected_mode == "pvp")
	_mode_pvp_btn.add_theme_stylebox_override("normal", _card_sb(pvp_sel, Color(0.28, 0.72, 1.0), Color(0.55, 0.90, 1.0)))
	_mode_pvp_btn.add_theme_stylebox_override("hover", _card_sb(pvp_sel, Color(0.28, 0.72, 1.0), Color(0.55, 0.90, 1.0), true))
	_mode_surv_btn.add_theme_stylebox_override("normal", _card_sb(not pvp_sel, Color(0.95, 0.38, 0.56), Color(1.0, 0.78, 0.42)))
	_mode_surv_btn.add_theme_stylebox_override("hover", _card_sb(not pvp_sel, Color(0.95, 0.38, 0.56), Color(1.0, 0.78, 0.42), true))

	_diff_box.visible = not pvp_sel
	_pvp_box.visible = pvp_sel

	var is_ffa := (selected_pvp_var == "ffa")
	_pvp_ffa_btn.add_theme_stylebox_override("normal", _card_sb(is_ffa, Color(0.28, 0.78, 1.0), Color(0.55, 0.92, 1.0)))
	_pvp_ffa_btn.add_theme_stylebox_override("hover", _card_sb(is_ffa, Color(0.28, 0.78, 1.0), Color(0.55, 0.92, 1.0), true))
	_pvp_team_btn.add_theme_stylebox_override("normal", _card_sb(not is_ffa, Color(0.95, 0.65, 0.28), Color(1.0, 0.86, 0.45)))
	_pvp_team_btn.add_theme_stylebox_override("hover", _card_sb(not is_ffa, Color(0.95, 0.65, 0.28), Color(1.0, 0.86, 0.45), true))

	for did in Difficulties.ORDER:
		var dd := Difficulties.get_data(did)
		var db := _diff_buttons[did] as Button
		var dsel := (did == selected_diff)
		db.add_theme_stylebox_override("normal", _card_sb(dsel, dd["color"], dd["color"]))
		db.add_theme_stylebox_override("hover", _card_sb(dsel, dd["color"], dd["color"], true))

	var cur_dd := Difficulties.get_data(selected_diff)
	_diff_lore_label.text = "【%s】(怪血×%.2f · 算力×%.1f) %s" % [
		cur_dd["mission_title"], float(cur_dd["hp_mult"]), float(cur_dd["cp_mult"]), cur_dd["lore"]]
	_start_btn.text = ("进入五宫格 2v2v2v2 组队战！" if not is_ffa else "进入五宫格 PVP 乱斗！") if pvp_sel else "出击！[%s] %s" % [cur_dd["name"], cur_dd["mission_title"]]

	var sbtn_n := StyleBoxFlat.new()
	sbtn_n.bg_color = theme_col if pvp_sel else (cur_dd["color"] as Color).darkened(0.12)
	sbtn_n.set_corner_radius_all(12)
	sbtn_n.border_color = accent_col if pvp_sel else (cur_dd["color"] as Color).lightened(0.3)
	sbtn_n.set_border_width_all(2)
	var sbtn_h := sbtn_n.duplicate() as StyleBoxFlat
	sbtn_h.bg_color = sbtn_n.bg_color.lightened(0.14)
	_start_btn.add_theme_stylebox_override("normal", sbtn_n)
	_start_btn.add_theme_stylebox_override("hover", sbtn_h)
	_start_btn.add_theme_stylebox_override("pressed", sbtn_n)


func _card_sb(selected: bool, col: Color, border: Color, hovered := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.34 if selected else (0.18 if hovered else 0.10))
	if not selected:
		sb.bg_color = sb.bg_color.lerp(Color(0.11, 0.14, 0.21, 0.92), 0.72)
	sb.set_corner_radius_all(10)
	sb.border_color = border if selected else Color(1, 1, 1, 0.32 if hovered else 0.14)
	sb.set_border_width_all(3 if selected else 1)
	return sb


# ================= 局外「算力天赋树」弹窗（user://save.json）=================
func _build_talent_modal() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)

	_talent_modal = PanelContainer.new()
	_talent_modal.custom_minimum_size = Vector2(820, 500)
	_talent_modal.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.97)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(24)
	sb.border_color = Color(1.0, 0.84, 0.35, 0.92)
	sb.set_border_width_all(3)
	_talent_modal.add_theme_stylebox_override("panel", sb)
	cc.add_child(_talent_modal)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_talent_modal.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := Label.new()
	title.text = "⚡ 局外算力天赋树（自动保存至本地）"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.44))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	_talent_cp_label = Label.new()
	_talent_cp_label.add_theme_font_size_override("font_size", 20)
	_talent_cp_label.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
	top.add_child(_talent_cp_label)

	var note := Label.new()
	note.text = "每局消灭怪潮与战绩会自动折算成「算力点」。天赋永久生效于「算力潮汐」幸存者模式，PVP 保持纯公平竞技！"
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.75, 0.84, 0.96))
	vb.add_child(note)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)

	for info in MetaSave.TALENTS:
		var tid: String = info["id"]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(246, 108)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_buy_talent.bind(tid))
		grid.add_child(btn)
		_talent_cards[tid] = btn

	_codex_unlock_btn = Button.new()
	_codex_unlock_btn.custom_minimum_size = Vector2(0, 50)
	_codex_unlock_btn.add_theme_font_size_override("font_size", 16)
	_codex_unlock_btn.focus_mode = Control.FOCUS_NONE
	_codex_unlock_btn.pressed.connect(_on_unlock_codex)
	vb.add_child(_codex_unlock_btn)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	vb.add_child(foot)

	_talent_stats_label = Label.new()
	_talent_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talent_stats_label.add_theme_font_size_override("font_size", 13)
	_talent_stats_label.add_theme_color_override("font_color", Color(0.78, 0.85, 0.94))
	foot.add_child(_talent_stats_label)

	var reset_btn := Button.new()
	reset_btn.text = "重置天赋（全额返还）"
	reset_btn.custom_minimum_size = Vector2(170, 40)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(func() -> void:
		if MetaSave.reset_talents() > 0:
			Sfx.play("reroll")
			_refresh_talent_modal()
			_refresh_meta_ui()
	)
	foot.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_talent_modal.visible = false
	)
	foot.add_child(close_btn)


func _open_talent_modal() -> void:
	_tips_modal.visible = false
	_lan_modal.visible = false
	_refresh_talent_modal()
	_talent_modal.visible = true


func _refresh_talent_modal() -> void:
	var cp := MetaSave.compute_points()
	_talent_cp_label.text = "可用算力点：%d" % cp
	for info in MetaSave.TALENTS:
		var tid: String = info["id"]
		var lv := MetaSave.talent_level(tid)
		var mx := int(info["max"])
		var cost := MetaSave.talent_cost(tid)
		var b := _talent_cards[tid] as Button
		var cost_txt := "已满级 ★" if cost < 0 else "升级：%d 算力点" % cost
		b.text = "[%s] %s  Lv %d/%d\n%s\n%s" % [info["icon"], info["name"], lv, mx, info["desc"], cost_txt]
		var can_buy := (cost >= 0 and cp >= cost)
		b.add_theme_stylebox_override("normal", _card_sb(can_buy or cost < 0, Color(0.32, 0.85, 1.0) if cost < 0 else Color(1.0, 0.78, 0.28), Color(0.55, 0.95, 1.0) if cost < 0 else (Color(1.0, 0.88, 0.42) if can_buy else Color(0.4, 0.45, 0.55))))
		b.add_theme_stylebox_override("hover", _card_sb(true, Color(1.0, 0.82, 0.35), Color(1.0, 0.92, 0.55), true))

	if MetaSave.is_codex_full_unlocked():
		_codex_unlock_btn.text = "✓ 已解锁全套「AI 公益百科 + 5种怪物概念图鉴」！（永久算力收益 +10% 生效中）"
		_codex_unlock_btn.add_theme_stylebox_override("normal", _card_sb(true, Color(0.30, 0.82, 0.55), Color(0.55, 1.0, 0.72)))
	else:
		_codex_unlock_btn.text = "📖 解锁全部 AI 公益科普 & 怪物概念图鉴（永久算力收益 +10%%！） — 花费 %d 算力点" % MetaSave.CODEX_UNLOCK_COST
		var ok := cp >= MetaSave.CODEX_UNLOCK_COST
		_codex_unlock_btn.add_theme_stylebox_override("normal", _card_sb(ok, Color(0.68, 0.46, 1.0), Color(0.88, 0.74, 1.0)))

	var best_s := int(MetaSave.data["best_endless_sec"])
	_talent_stats_label.text = "累计对局 %d 场 · 累计消灭 %d · 极限无尽最佳 %d:%02d（%d 杀）" % [
		int(MetaSave.data["matches_played"]), int(MetaSave.data["total_kills"]),
		best_s / 60, best_s % 60, int(MetaSave.data["best_endless_kills"])]


func _on_buy_talent(tid: String) -> void:
	if MetaSave.buy_talent(tid):
		Sfx.play("card_pick", 0.04, 60, -8.0)
		_refresh_talent_modal()
		_refresh_meta_ui()
	else:
		Sfx.play("hit", 0.05, 80, -14.0)


func _on_unlock_codex() -> void:
	if MetaSave.unlock_full_codex():
		Sfx.play("chest", 0.02, 120, -7.0)
		_refresh_talent_modal()
		_refresh_meta_ui()
	else:
		Sfx.play("hit", 0.05, 80, -14.0)


# ================= 三标签「AI 模型档案 + 公益科普 + 怪物概念档案」图鉴弹窗 =================
func _build_tips_modal() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)

	_tips_modal = PanelContainer.new()
	_tips_modal.custom_minimum_size = Vector2(790, 430)
	_tips_modal.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.97)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(24)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.85)
	sb.set_border_width_all(3)
	_tips_modal.add_theme_stylebox_override("panel", sb)
	cc.add_child(_tips_modal)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_tips_modal.add_child(vb)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	vb.add_child(tab_row)

	_tab_models_btn = Button.new()
	_tab_models_btn.text = "AI 模型档案 (%d位)" % AiTips.MODEL_CODEX.size()
	_tab_models_btn.custom_minimum_size = Vector2(168, 36)
	_tab_models_btn.focus_mode = Control.FOCUS_NONE
	_tab_models_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_codex_tab = "models"
		_refresh_codex()
	)
	tab_row.add_child(_tab_models_btn)

	_tab_tips_btn = Button.new()
	_tab_tips_btn.text = "AI 公益科普 (%d条)" % AiTips.LIST.size()
	_tab_tips_btn.custom_minimum_size = Vector2(168, 36)
	_tab_tips_btn.focus_mode = Control.FOCUS_NONE
	_tab_tips_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_codex_tab = "tips"
		_refresh_codex()
	)
	tab_row.add_child(_tab_tips_btn)

	_tab_mon_btn = Button.new()
	_tab_mon_btn.text = "怪物概念档案 (%d种)" % AiTips.MONSTER_CODEX.size()
	_tab_mon_btn.custom_minimum_size = Vector2(168, 36)
	_tab_mon_btn.focus_mode = Control.FOCUS_NONE
	_tab_mon_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_codex_tab = "monsters"
		_refresh_codex()
	)
	tab_row.add_child(_tab_mon_btn)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(sp)

	_tips_page = Label.new()
	_tips_page.add_theme_font_size_override("font_size", 14)
	_tips_page.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	tab_row.add_child(_tips_page)

	var content_hb := HBoxContainer.new()
	content_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hb.add_theme_constant_override("separation", 18)
	vb.add_child(content_hb)

	_monster_icon = TextureRect.new()
	_monster_icon.custom_minimum_size = Vector2(150, 220)
	_monster_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_monster_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_monster_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_monster_icon.visible = false
	content_hb.add_child(_monster_icon)

	var text_vb := VBoxContainer.new()
	text_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vb.add_theme_constant_override("separation", 10)
	content_hb.add_child(text_vb)

	_tips_tag = Label.new()
	_tips_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tips_tag.add_theme_font_size_override("font_size", 15)
	_tips_tag.add_theme_color_override("font_color", Color(0.45, 0.92, 1.0))
	text_vb.add_child(_tips_tag)

	_tips_title = Label.new()
	_tips_title.add_theme_font_size_override("font_size", 24)
	_tips_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.56))
	text_vb.add_child(_tips_title)

	_tips_body = Label.new()
	_tips_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tips_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tips_body.add_theme_font_size_override("font_size", 16)
	_tips_body.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	text_vb.add_child(_tips_body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)

	var prev := Button.new()
	prev.text = "上一条"
	prev.custom_minimum_size = Vector2(100, 38)
	prev.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		if _codex_tab == "models": _model_index = posmod(_model_index - 1, AiTips.MODEL_CODEX.size())
		elif _codex_tab == "tips": _tips_index = posmod(_tips_index - 1, AiTips.LIST.size())
		else: _monster_index = posmod(_monster_index - 1, AiTips.MONSTER_CODEX.size())
		_refresh_codex()
	)
	row.add_child(prev)

	var nxt := Button.new()
	nxt.text = "下一条"
	nxt.custom_minimum_size = Vector2(100, 38)
	nxt.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		if _codex_tab == "models": _model_index = posmod(_model_index + 1, AiTips.MODEL_CODEX.size())
		elif _codex_tab == "tips": _tips_index = posmod(_tips_index + 1, AiTips.LIST.size())
		else: _monster_index = posmod(_monster_index + 1, AiTips.MONSTER_CODEX.size())
		_refresh_codex()
	)
	row.add_child(nxt)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(100, 38)
	close.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_tips_modal.visible = false
	)
	row.add_child(close)


func _open_tips_modal() -> void:
	_talent_modal.visible = false
	_lan_modal.visible = false
	# 若打开时默认展示当前选中角色的 AI 模型档案，体验更贴心！
	for i in AiTips.MODEL_CODEX.size():
		if str(AiTips.MODEL_CODEX[i]["id"]) == selected_char:
			_model_index = i
			break
	_refresh_codex()
	_tips_modal.visible = true


func _refresh_codex() -> void:
	var is_models := (_codex_tab == "models")
	var is_tips := (_codex_tab == "tips")
	var is_mon := (_codex_tab == "monsters")
	_tab_models_btn.add_theme_stylebox_override("normal", _card_sb(is_models, Color(1.0, 0.78, 0.30), Color(1.0, 0.90, 0.55)))
	_tab_tips_btn.add_theme_stylebox_override("normal", _card_sb(is_tips, Color(0.32, 0.80, 1.0), Color(0.55, 0.92, 1.0)))
	_tab_mon_btn.add_theme_stylebox_override("normal", _card_sb(is_mon, Color(0.95, 0.45, 0.65), Color(1.0, 0.72, 0.82)))

	if is_models:
		var md := AiTips.MODEL_CODEX[_model_index]
		var cd := Characters.get_data(str(md["id"]))
		_monster_icon.visible = true
		_monster_icon.custom_minimum_size = Vector2(164, 240)
		_monster_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_monster_icon.modulate = Color.WHITE
		_monster_icon.texture = load(str(cd["portrait"])) as Texture2D
		_tips_page.text = "%d / %d" % [_model_index + 1, AiTips.MODEL_CODEX.size()]
		_tips_tag.text = "所属公司：%s  ·  %s" % [md["company"], md["founded"]]
		_tips_title.text = str(md["name"])
		_tips_body.text = "【创始人 / 核心团队】\n%s\n\n【开放生态】%s\n\n【技术与代表特色】\n%s" % [
			md["founders"], md["ecosystem"], md["desc"]
		]
	elif is_tips:
		_monster_icon.visible = false
		_tips_page.text = "%d / %d" % [_tips_index + 1, AiTips.LIST.size()]
		var t := AiTips.LIST[_tips_index]
		if MetaSave.is_tip_unlocked(_tips_index):
			_tips_tag.text = "AI 公益科普  ·  【%s】" % t["tag"]
			_tips_title.text = str(t["title"])
			_tips_body.text = str(t["body"])
		else:
			_tips_tag.text = "🔒 进阶 AI 公益百科（未解锁）"
			_tips_title.text = "？？？（继续游玩或在「算力天赋树」解锁全图鉴）"
			_tips_body.text = "多打几局即可逐步解锁进阶百科，或者直接前往大厅顶部「⚡ 算力天赋树」花费 120 算力点一次性解锁全部科普与怪物档案，还可永久获得 +10% 算力点收益！"
	else:
		_monster_icon.visible = true
		_monster_icon.custom_minimum_size = Vector2(128, 128)
		_monster_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tips_page.text = "%d / %d" % [_monster_index + 1, AiTips.MONSTER_CODEX.size()]
		var m := AiTips.MONSTER_CODEX[_monster_index]
		_monster_icon.texture = PixelSprites.get_monster_texture(str(m["kind"]))
		if MetaSave.is_monster_unlocked(str(m["kind"])):
			_monster_icon.modulate = Color.WHITE
			_tips_tag.text = "对应 AI 概念：%s" % m["concept"]
			_tips_title.text = str(m["name"])
			_tips_body.text = str(m["desc"])
		else:
			_monster_icon.modulate = Color(0.08, 0.08, 0.12, 0.9)
			_tips_tag.text = "🔒 未遭遇怪物档案"
			_tips_title.text = "？？？（待解锁）"
			_tips_body.text = "在「算力潮汐」幸存者模式中遭遇该怪物自动解锁，或在「⚡ 算力天赋树」直接解锁全部图鉴！"


# ================= 局域网联机房间弹窗（建房 / 自动扫描 / IP直连 / 模式与人机配置 / 2v2v2v2 选队）=================
func _exit_tree() -> void:
	if NetManager.inst != null:
		NetManager.inst.stop_discovery()
		if NetManager.inst.room_updated.is_connected(_refresh_lan_modal):
			NetManager.inst.room_updated.disconnect(_refresh_lan_modal)
		if NetManager.inst.discovery_updated.is_connected(_refresh_lan_discovery):
			NetManager.inst.discovery_updated.disconnect(_refresh_lan_discovery)
		if NetManager.inst.connection_status.is_connected(_on_lan_status):
			NetManager.inst.connection_status.disconnect(_on_lan_status)


func _build_lan_modal() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)

	_lan_modal = PanelContainer.new()
	_lan_modal.custom_minimum_size = Vector2(820, 520)
	_lan_modal.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.15, 0.97)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(24)
	sb.border_color = Color(0.36, 0.88, 1.0, 0.92)
	sb.set_border_width_all(3)
	_lan_modal.add_theme_stylebox_override("panel", sb)
	cc.add_child(_lan_modal)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 12)
	_lan_modal.add_child(root_vb)

	var top := HBoxContainer.new()
	root_vb.add_child(top)
	var title := Label.new()
	title.text = "🌐 局域网联机大厅（同 Wi-Fi / 局域网免服务器直连）"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.45, 0.94, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	var close_x := Button.new()
	close_x.text = "收起弹窗"
	close_x.custom_minimum_size = Vector2(96, 34)
	close_x.focus_mode = Control.FOCUS_NONE
	close_x.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		_lan_modal.visible = false
		if NetManager.inst != null and not NetManager.is_online():
			NetManager.inst.stop_discovery()
	)
	top.add_child(close_x)

	_lan_status_lbl = Label.new()
	_lan_status_lbl.text = "本机局域网 IP：%s · 端口 %d（开房前可在主大厅任选出战 AI 娘与武器）" % [NetManager.get_local_ipv4(), NetManager.GAME_PORT]
	_lan_status_lbl.add_theme_font_size_override("font_size", 13)
	_lan_status_lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0))
	root_vb.add_child(_lan_status_lbl)

	# --- 视图 A：未进房（建房 / 局域网自动发现 / 手动 IP 直连）---
	_lan_entry_box = VBoxContainer.new()
	_lan_entry_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lan_entry_box.add_theme_constant_override("separation", 12)
	root_vb.add_child(_lan_entry_box)

	var nick_row := HBoxContainer.new()
	nick_row.add_theme_constant_override("separation", 10)
	_lan_entry_box.add_child(nick_row)
	var nl := Label.new()
	nl.text = "我的联机昵称："
	nick_row.add_child(nl)
	_lan_nick_edit = LineEdit.new()
	_lan_nick_edit.text = "玩家%d" % randi_range(100, 999)
	_lan_nick_edit.custom_minimum_size = Vector2(200, 36)
	nick_row.add_child(_lan_nick_edit)

	var host_btn := Button.new()
	host_btn.text = "🏠 创建局域网房间（做房主）"
	host_btn.custom_minimum_size = Vector2(260, 42)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.add_theme_font_size_override("font_size", 17)
	host_btn.focus_mode = Control.FOCUS_NONE
	host_btn.add_theme_stylebox_override("normal", _card_sb(true, Color(0.24, 0.80, 0.52), Color(0.55, 1.0, 0.76)))
	host_btn.pressed.connect(func() -> void:
		Sfx.play("card_pick", 0.02, 80, -8.0)
		var nick := _lan_nick_edit.text.strip_edges()
		if nick == "": nick = "房主"
		NetManager.inst.host_room(nick, selected_char, selected_weapon)
		_refresh_lan_modal()
	)
	nick_row.add_child(host_btn)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 10)
	_lan_entry_box.add_child(ip_row)
	var ipl := Label.new()
	ipl.text = "手动直连房主 IP："
	ip_row.add_child(ipl)
	_lan_ip_edit = LineEdit.new()
	_lan_ip_edit.text = "127.0.0.1"
	_lan_ip_edit.placeholder_text = "例如 192.168.1.8 或 127.0.0.1"
	_lan_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_ip_edit.custom_minimum_size = Vector2(260, 36)
	ip_row.add_child(_lan_ip_edit)

	var join_btn := Button.new()
	join_btn.text = "🚀 连接加入房间"
	join_btn.custom_minimum_size = Vector2(180, 38)
	join_btn.focus_mode = Control.FOCUS_NONE
	join_btn.add_theme_stylebox_override("normal", _card_sb(true, Color(0.26, 0.65, 1.0), Color(0.55, 0.90, 1.0)))
	join_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		var nick := _lan_nick_edit.text.strip_edges()
		if nick == "": nick = "队友"
		NetManager.inst.join_room(_lan_ip_edit.text, nick, selected_char, selected_weapon)
	)
	ip_row.add_child(join_btn)

	var disc_title := Label.new()
	disc_title.text = "📡 局域网自动扫描到的房间（每秒自动刷新）："
	disc_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.52))
	_lan_entry_box.add_child(disc_title)

	var disc_sc := ScrollContainer.new()
	disc_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lan_entry_box.add_child(disc_sc)
	_lan_disc_box = VBoxContainer.new()
	_lan_disc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_disc_box.add_theme_constant_override("separation", 8)
	disc_sc.add_child(_lan_disc_box)

	# --- 视图 B：房间内（模式配置 / 人机开关 / 玩家列表 / 2v2v2v2 换队 / 全员出击）---
	_lan_room_box = VBoxContainer.new()
	_lan_room_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lan_room_box.add_theme_constant_override("separation", 10)
	_lan_room_box.visible = false
	root_vb.add_child(_lan_room_box)

	_lan_room_header = Label.new()
	_lan_room_header.add_theme_font_size_override("font_size", 15)
	_lan_room_header.add_theme_color_override("font_color", Color(1.0, 0.92, 0.56))
	_lan_room_box.add_child(_lan_room_header)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	_lan_room_box.add_child(mode_row)
	var m_defs := [
		{"id": "pve_coop", "txt": "PVE 双人无尽合作\n(2人·怪血强化)"},
		{"id": "pvp_ffa", "txt": "PVP 五宫格乱斗\n(自由混战·最多8人)"},
		{"id": "pvp_2v2v2v2", "txt": "PVP 五宫格 2v2v2v2\n(四阵营组队·最多8人)"},
	]
	for md in m_defs:
		var mid: String = md["id"]
		var mb := Button.new()
		mb.text = md["txt"]
		mb.custom_minimum_size = Vector2(0, 48)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.add_theme_font_size_override("font_size", 13)
		mb.focus_mode = Control.FOCUS_NONE
		mb.pressed.connect(func() -> void:
			if NetManager.is_host():
				Sfx.play("ui_click")
				NetManager.inst.host_set_mode(mid)
		)
		mode_row.add_child(mb)
		_lan_mode_btns[mid] = mb

	var opt_row := HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 12)
	_lan_room_box.add_child(opt_row)

	_lan_bots_btn = Button.new()
	_lan_bots_btn.custom_minimum_size = Vector2(220, 36)
	_lan_bots_btn.focus_mode = Control.FOCUS_NONE
	_lan_bots_btn.pressed.connect(func() -> void:
		if NetManager.is_host():
			Sfx.play("ui_click")
			NetManager.inst.host_set_fill_bots(not bool(NetManager.inst.room_cfg.get("fill_bots", true)))
	)
	opt_row.add_child(_lan_bots_btn)

	var switch_hint := Label.new()
	switch_hint.text = "提示：点击右上「收起弹窗」可回主大厅随时切换自己的 AI 娘和武器（自动实时同步）！"
	switch_hint.add_theme_font_size_override("font_size", 12)
	switch_hint.add_theme_color_override("font_color", Color(0.74, 0.85, 0.96))
	switch_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_row.add_child(switch_hint)

	var roster_sc := ScrollContainer.new()
	roster_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lan_room_box.add_child(roster_sc)
	_lan_roster_box = VBoxContainer.new()
	_lan_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_roster_box.add_theme_constant_override("separation", 6)
	roster_sc.add_child(_lan_roster_box)

	var foot_row := HBoxContainer.new()
	foot_row.add_theme_constant_override("separation", 12)
	_lan_room_box.add_child(foot_row)

	_lan_leave_btn = Button.new()
	_lan_leave_btn.text = "解散 / 离开房间"
	_lan_leave_btn.custom_minimum_size = Vector2(160, 44)
	_lan_leave_btn.focus_mode = Control.FOCUS_NONE
	_lan_leave_btn.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		NetManager.inst.leave_room()
		NetManager.inst.start_discovery()
		_refresh_lan_modal()
	)
	foot_row.add_child(_lan_leave_btn)

	_lan_start_btn = Button.new()
	_lan_start_btn.text = "⚡ 全员出击！开始联机对局"
	_lan_start_btn.custom_minimum_size = Vector2(0, 46)
	_lan_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_start_btn.add_theme_font_size_override("font_size", 19)
	_lan_start_btn.focus_mode = Control.FOCUS_NONE
	_lan_start_btn.add_theme_stylebox_override("normal", _card_sb(true, Color(0.28, 0.84, 0.48), Color(0.60, 1.0, 0.78)))
	_lan_start_btn.pressed.connect(func() -> void:
		if NetManager.is_host():
			Sfx.play("card_pick", 0.02, 80, -7.0)
			NetManager.inst.host_start_match()
	)
	foot_row.add_child(_lan_start_btn)


func _open_lan_modal() -> void:
	_talent_modal.visible = false
	_tips_modal.visible = false
	if NetManager.inst != null and not NetManager.is_online():
		NetManager.inst.start_discovery()
	_refresh_lan_modal()
	_refresh_lan_discovery()
	_lan_modal.visible = true


func _on_lan_status(msg: String, is_err: bool) -> void:
	if _lan_status_lbl != null:
		_lan_status_lbl.text = msg
		_lan_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.48, 0.48) if is_err else Color(0.55, 0.96, 0.78))


func _refresh_lan_discovery() -> void:
	if _lan_disc_box == null or NetManager.inst == null:
		return
	for ch in _lan_disc_box.get_children():
		ch.queue_free()
	var rooms := NetManager.inst.discovered_rooms
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "暂未扫描到局域网房间……可以点上方「创建局域网房间」做房主，或直接输入好友 IP 加入！"
		empty.add_theme_color_override("font_color", Color(0.65, 0.74, 0.86))
		_lan_disc_box.add_child(empty)
		return
	for ip: String in rooms:
		var rd: Dictionary = rooms[ip]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		var status_tag := "【激战中】" if bool(rd.get("in_game", false)) else "【等待中】"
		lbl.text = "%s %s · %s · %d/%d人 (%s)" % [
			status_tag, str(rd.get("name", "房间")), NetManager.mode_label(str(rd.get("mode", "pve_coop"))),
			int(rd.get("players", 1)), int(rd.get("max", 8)), ip]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var jb := Button.new()
		jb.text = "一键加入"
		jb.disabled = bool(rd.get("in_game", false))
		jb.custom_minimum_size = Vector2(100, 32)
		jb.focus_mode = Control.FOCUS_NONE
		jb.pressed.connect(func() -> void:
			Sfx.play("ui_click")
			var nick := _lan_nick_edit.text.strip_edges()
			if nick == "": nick = "队友"
			NetManager.inst.join_room(ip, nick, selected_char, selected_weapon)
		)
		row.add_child(jb)
		_lan_disc_box.add_child(row)


func _refresh_lan_modal() -> void:
	if _lan_modal == null or NetManager.inst == null:
		return
	var online := NetManager.is_online()
	_lan_entry_box.visible = not online
	_lan_room_box.visible = online
	_lan_top_btn.text = "🌐 联机房间 (%d人)" % NetManager.inst.players.size() if online else "🌐 局域网联机"
	if not online:
		return

	var is_h := NetManager.is_host()
	var cfg := NetManager.inst.room_cfg
	var m := str(cfg.get("mode", "pve_coop"))
	var max_p := NetManager.max_players_for(m)
	_lan_room_header.text = "房间：%s  ·  本机 IP：%s:%d  ·  人数 %d / %d  (%s)" % [
		str(cfg.get("room_name", "AI 联机房")), NetManager.get_local_ipv4(), NetManager.GAME_PORT,
		NetManager.inst.players.size(), max_p, "你是房主" if is_h else "已加入房主房间"]

	for mid: String in _lan_mode_btns:
		var b := _lan_mode_btns[mid] as Button
		var sel := (mid == m)
		b.disabled = not is_h
		b.add_theme_stylebox_override("normal", _card_sb(sel, Color(0.36, 0.84, 1.0) if mid != "pve_coop" else Color(0.88, 0.45, 1.0), Color(0.70, 0.96, 1.0)))

	_lan_bots_btn.visible = (m != "pve_coop")
	var fb := bool(cfg.get("fill_bots", true))
	_lan_bots_btn.text = "PVP 填充 AI 人机：开启 ✓" if fb else "PVP 填充 AI 人机：关闭（纯真人）"
	_lan_bots_btn.disabled = not is_h
	_lan_bots_btn.add_theme_stylebox_override("normal", _card_sb(fb, Color(0.34, 0.82, 0.56), Color(0.60, 1.0, 0.78)))

	for ch in _lan_roster_box.get_children():
		ch.queue_free()
	var pids := NetManager.inst.players.keys()
	pids.sort()
	for raw_pid in pids:
		var pid := int(raw_pid)
		var pd: Dictionary = NetManager.inst.players[raw_pid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var cid := str(pd.get("char", "claude"))
		var wid := str(pd.get("weapon", "grimoire"))
		var tid := int(pd.get("team", 0))
		var cname := str(Characters.get_data(cid)["name"])
		var wname := str(Weapons.get_data(wid)["name"])
		var crown := "👑 " if pid == 1 else "🎮 "
		var team_txt := ("[%s] " % NetManager.TEAM_NAMES[tid]) if (m == "pvp_2v2v2v2" and tid >= 1 and tid <= 4) else ""
		var lb := Label.new()
		lb.text = "%s%s%s  —  %s · %s" % [crown, team_txt, str(pd.get("name", "玩家")), cname, wname]
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.add_theme_font_size_override("font_size", 15)
		if m == "pvp_2v2v2v2" and tid >= 1 and tid <= 4:
			lb.add_theme_color_override("font_color", NetManager.TEAM_COLORS[tid])
		row.add_child(lb)

		# 2v2v2v2 模式下，本人可一键点击换队！
		if m == "pvp_2v2v2v2" and pid == NetManager.inst.my_id:
			for t_opt in [1, 2, 3, 4]:
				var tb := Button.new()
				tb.text = NetManager.TEAM_NAMES[t_opt]
				tb.custom_minimum_size = Vector2(54, 30)
				tb.focus_mode = Control.FOCUS_NONE
				tb.add_theme_stylebox_override("normal", _card_sb(tid == t_opt, NetManager.TEAM_COLORS[t_opt], NetManager.TEAM_COLORS[t_opt]))
				tb.pressed.connect(func() -> void:
					Sfx.play("ui_click")
					NetManager.inst.update_my_profile(selected_char, selected_weapon, t_opt)
				)
				row.add_child(tb)
		_lan_roster_box.add_child(row)

	_lan_leave_btn.text = "解散房间" if is_h else "离开房间"
	_lan_start_btn.disabled = not is_h
	_lan_start_btn.text = "⚡ 全员出击！开始联机对局" if is_h else "⏳ 等待房主点击开始对局..."


func _input(event: InputEvent) -> void:
	if OS.has_feature("web") and ((event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)):
		Sfx.unlock_web_audio()


func _process(delta: float) -> void:
	_anim_t += delta
	_bg_top = _bg_top.lerp(_target_top, clampf(delta * 4.5, 0.0, 1.0))
	_bg_bot = _bg_bot.lerp(_target_bot, clampf(delta * 4.5, 0.0, 1.0))
	var frames := PixelSprites.get_character_frames(selected_char)
	var fi: int = [0, 2, 0, 3][int(_anim_t * 5.0) % 4]
	_pixel_preview.texture = frames[fi]
	_bg.queue_redraw()


func _draw_bg() -> void:
	var steps := 16
	var sh := size.y / float(steps)
	for i in steps:
		var c := _bg_top.lerp(_bg_bot, float(i) / float(steps - 1))
		_bg.draw_rect(Rect2(0, i * sh, size.x, sh + 2.0), c)
	var gcol := Color(1, 1, 1, 0.035)
	for x in range(0, int(size.x), 64):
		_bg.draw_line(Vector2(x, 0), Vector2(x, size.y), gcol, 1.0)
	for y in range(0, int(size.y), 64):
		_bg.draw_line(Vector2(0, y), Vector2(size.x, y), gcol, 1.0)
