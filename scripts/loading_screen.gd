class_name LoadingScreen
extends Control
## 公益科普加载界面：加载进度条上奔跑的像素小人 + AI 知识/安全/反诈公益小科普卡片

signal finished

var char_id := "claude"
var weapon_id := "grimoire"
var game_mode := "pvp"
var difficulty_id := "normal"
var auto_advance := false

var _canvas: Control
var _tag_label: Label
var _title_label: Label
var _body_label: Label
var _enter_btn: Button
var _next_btn: Button
var _progress := 0.0
var _ready_to_go := false
var _t := 0.0
var _accent := Color(0.45, 0.85, 1.0)
var _bg_top := Color(0.06, 0.09, 0.16)
var _bg_bot := Color(0.11, 0.16, 0.28)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cd := Characters.get_data(char_id)
	_accent = cd["accent"]
	_bg_top = (cd["bg_top"] as Color).darkened(0.25)
	_bg_bot = (cd["bg_bot"] as Color).darkened(0.15)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_scene)
	add_child(_canvas)

	# 中央 AI 公益科普卡片
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.offset_bottom = -130
	add_child(cc)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(780, 320)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.90)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(30)
	sb.border_color = Color(_accent.r, _accent.g, _accent.b, 0.78)
	sb.set_border_width_all(3)
	card.add_theme_stylebox_override("panel", sb)
	cc.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card.add_child(vb)

	var header := HBoxContainer.new()
	vb.add_child(header)

	_tag_label = Label.new()
	_tag_label.add_theme_font_size_override("font_size", 16)
	_tag_label.add_theme_color_override("font_color", _accent)
	_tag_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_tag_label)

	var badge := Label.new()
	var wd := Weapons.get_data(weapon_id)
	var mname := "平衡PVP竞技"
	if game_mode == "survivor":
		var dd := Difficulties.get_data(difficulty_id)
		mname = "算力潮汐·%s(%s)" % [dd["name"], dd["short"]]
	badge.text = "[%s]  %s · %s" % [mname, cd["name"], wd["name"]]
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	header.add_child(badge)

	if game_mode == "survivor":
		var dd := Difficulties.get_data(difficulty_id)
		var lore_lbl := Label.new()
		lore_lbl.text = "任务背景【%s】：%s" % [dd["mission_title"], dd["lore"]]
		lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore_lbl.add_theme_font_size_override("font_size", 14)
		lore_lbl.add_theme_color_override("font_color", dd["color"])
		vb.add_child(lore_lbl)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.58))
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 19)
	_body_label.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_body_label)

	var foot := Label.new()
	foot.text = "公益倡导：善用 AI 提升学习与生活效率，警惕虚假信息与隐私泄露。"
	foot.add_theme_font_size_override("font_size", 14)
	foot.add_theme_color_override("font_color", Color(0.62, 0.78, 0.88, 0.9))
	vb.add_child(foot)

	# 底部操作按钮
	var btn_row := HBoxContainer.new()
	btn_row.anchor_left = 0.5
	btn_row.anchor_right = 0.5
	btn_row.anchor_top = 1.0
	btn_row.anchor_bottom = 1.0
	btn_row.offset_left = -220
	btn_row.offset_right = 220
	btn_row.offset_top = -72
	btn_row.offset_bottom = -20
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 18)
	add_child(btn_row)

	_next_btn = Button.new()
	_next_btn.text = "换一条 AI 小知识"
	_next_btn.custom_minimum_size = Vector2(180, 46)
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.pressed.connect(_pick_tip)
	btn_row.add_child(_next_btn)

	_enter_btn = Button.new()
	_enter_btn.text = "正在加载像素战场..."
	_enter_btn.custom_minimum_size = Vector2(220, 46)
	_enter_btn.disabled = true
	_enter_btn.focus_mode = Control.FOCUS_NONE
	_enter_btn.pressed.connect(_finish)
	btn_row.add_child(_enter_btn)

	_pick_tip()


func _pick_tip() -> void:
	var tip := AiTips.pick_random()
	_tag_label.text = "AI 公益小知识  ·  【%s】" % tip["tag"]
	_title_label.text = str(tip["title"])
	_body_label.text = str(tip["body"])


func _finish() -> void:
	if _ready_to_go:
		finished.emit()


func _input(event: InputEvent) -> void:
	if _ready_to_go and event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_SPACE or k == KEY_ENTER:
			_finish()


func _process(delta: float) -> void:
	_t += delta
	if _progress < 1.0:
		_progress = minf(1.0, _progress + delta * 0.68)
		if _progress >= 1.0:
			_ready_to_go = true
			_enter_btn.disabled = false
			_enter_btn.text = "进入战场！(Space)"
			var sb := StyleBoxFlat.new()
			sb.bg_color = Characters.get_data(char_id)["color"]
			sb.set_corner_radius_all(10)
			sb.border_color = _accent
			sb.set_border_width_all(2)
			_enter_btn.add_theme_stylebox_override("normal", sb)
			if auto_advance:
				finished.emit()
	_canvas.queue_redraw()


func _draw_scene() -> void:
	var steps := 14
	var sh := size.y / float(steps)
	for i in steps:
		_canvas.draw_rect(Rect2(0, i * sh, size.x, sh + 2.0), _bg_top.lerp(_bg_bot, float(i) / float(steps - 1)))

	# 进度条 + 在进度条上奔跑的像素 Q 版小人
	var bw := minf(780.0, size.x - 120.0)
	var bx := (size.x - bw) * 0.5
	var by := size.y - 115.0
	_canvas.draw_rect(Rect2(bx - 3, by - 3, bw + 6, 22), Color(0, 0, 0, 0.55))
	_canvas.draw_rect(Rect2(bx, by, bw, 16), Color(0.14, 0.18, 0.28))
	_canvas.draw_rect(Rect2(bx, by, bw * _progress, 16), _accent)

	var font := PixelSprites.ui_font()
	var pct := "%d%%" % int(round(_progress * 100.0))
	_canvas.draw_string(font, Vector2(bx + bw + 14, by + 14), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	# 像素小人在进度条前端奔跑！
	var frames := PixelSprites.get_character_frames(char_id)
	var fi := 2 if int(_t * 10.0) % 2 == 0 else 3
	if _ready_to_go:
		fi = 0 if int(_t * 3.0) % 2 == 0 else 1
	var runner: Texture2D = frames[fi]
	var rx := bx + bw * _progress - 26.0
	var ry := by - 52.0 + (0.0 if _ready_to_go else -absf(sin(_t * 10.0)) * 5.0)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw_texture_rect(runner, Rect2(rx, ry, 52, 52), false)
