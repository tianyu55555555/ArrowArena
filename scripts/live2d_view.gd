class_name Live2dView
extends Control
## 局外伪 Live2D 立绘展示组件：呼吸、发丝微动、2.5D 鼠标视线跟随、点击互动弹跳与语音气泡

signal interacted(quote: String)

var _shader_mat: ShaderMaterial
var _portrait: TextureRect
var _backdrop: Control
var _bubble: PanelContainer
var _bubble_label: Label
var _char_id := "claude"
var _time := 0.0
var _look := Vector2.ZERO
var _bounce := 0.0
var _flash := 0.0
var _quote_idx := 0
var _bubble_timer := 0.0
var _accent := Color(1.0, 0.78, 0.52)
var _theme_col := Color(0.85, 0.47, 0.34)
var _particles: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _slide_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	_backdrop = Control.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.draw.connect(_draw_backdrop)
	add_child(_backdrop)

	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_top = 4
	_portrait.offset_bottom = -42
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sh := load("res://shaders/live2d_portrait.gdshader") as Shader
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = sh
	_portrait.material = _shader_mat
	add_child(_portrait)

	# 互动对话条：放在左下名牌正上方，绝不遮挡角色头部、猫耳、龙角与表情！
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.anchor_left = 0.0
	_bubble.anchor_right = 1.0
	_bubble.anchor_top = 1.0
	_bubble.anchor_bottom = 1.0
	_bubble.offset_left = 14
	_bubble.offset_right = -14
	_bubble.offset_top = -170
	_bubble.offset_bottom = -102
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.15, 0.88)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 1, 1, 0.45)
	sb.set_border_width_all(2)
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.visible = false
	add_child(_bubble)

	_bubble_label = Label.new()
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_label.add_theme_font_size_override("font_size", 14)
	_bubble_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	_bubble.add_child(_bubble_label)

	# 初始化柔和光斑粒子
	for i in 22:
		_particles.append({
			"x": randf(),
			"y": randf(),
			"r": randf_range(2.0, 5.5),
			"spd": randf_range(0.03, 0.08),
			"phase": randf() * TAU,
		})


func set_character(char_id: String, animate := true) -> void:
	_char_id = char_id
	_quote_idx = 0
	var d := Characters.get_data(char_id)
	_theme_col = d["color"]
	_accent = d["accent"]
	var tex := load(str(d["portrait"])) as Texture2D
	_portrait.texture = tex
	_shader_mat.set_shader_parameter("glow_color", _accent)

	var sb := _bubble.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = _accent

	if animate:
		_flash = 0.9
		_bounce = 0.5
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		_portrait.modulate.a = 0.0
		_portrait.offset_left = -36
		_portrait.offset_right = -36
		_slide_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_slide_tween.tween_property(_portrait, "modulate:a", 1.0, 0.28)
		_slide_tween.tween_property(_portrait, "offset_left", 0.0, 0.30)
		_slide_tween.tween_property(_portrait, "offset_right", 0.0, 0.30)
	_show_quote(d["quotes"][0])


func trigger_interact(click_pos: Vector2) -> void:
	Sfx.play("card_hover", 0.08, 120, -10.0)
	var d := Characters.get_data(_char_id)
	var quotes: Array = d["quotes"]
	_quote_idx = (_quote_idx + 1) % quotes.size()
	_bounce = 1.0
	_flash = 1.0
	_show_quote(str(quotes[_quote_idx]))
	interacted.emit(str(quotes[_quote_idx]))
	for i in 12:
		var ang := randf() * TAU
		var spd := randf_range(60.0, 170.0)
		_sparks.append({
			"pos": click_pos,
			"vel": Vector2.from_angle(ang) * spd,
			"t": 0.0,
			"life": randf_range(0.4, 0.75),
			"r": randf_range(3.0, 6.5),
		})


func _show_quote(q: String) -> void:
	_bubble_label.text = "「%s」" % q
	_bubble.visible = true
	_bubble_timer = 5.5
	_bubble.pivot_offset = _bubble.size * 0.5
	_bubble.scale = Vector2(0.92, 0.92)
	_bubble.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bubble, "scale", Vector2.ONE, 0.26)
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.18)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			trigger_interact(mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			trigger_interact(st.position)


func _process(delta: float) -> void:
	_time += delta
	_bounce = lerpf(_bounce, 0.0, clampf(delta * 6.5, 0.0, 1.0))
	_flash = maxf(_flash - delta * 2.4, 0.0)

	# 计算鼠标视线跟随向量（无鼠标移动时带自然缓动）
	var mp := get_local_mouse_position()
	var center := size * 0.5
	var target_look := Vector2.ZERO
	if size.x > 1.0 and size.y > 1.0:
		target_look = Vector2(
			clampf((mp.x - center.x) / (size.x * 0.8), -1.0, 1.0),
			clampf((mp.y - center.y) / (size.y * 0.8), -1.0, 1.0)
		)
	target_look += Vector2(sin(_time * 0.8) * 0.12, cos(_time * 0.65) * 0.08)
	_look = _look.lerp(target_look, clampf(delta * 5.0, 0.0, 1.0))

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("time_sec", _time)
		_shader_mat.set_shader_parameter("look_offset", _look)
		_shader_mat.set_shader_parameter("bounce", _bounce)
		_shader_mat.set_shader_parameter("flash", _flash)

	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.4:
			_bubble.modulate.a = clampf(_bubble_timer / 0.4, 0.0, 1.0)
		if _bubble_timer <= 0.0:
			_bubble.visible = false

	for p in _particles:
		p["y"] = fposmod(float(p["y"]) - float(p["spd"]) * delta, 1.0)
	for sp in _sparks:
		sp["t"] = float(sp["t"]) + delta
		sp["pos"] = (sp["pos"] as Vector2) + (sp["vel"] as Vector2) * delta
		sp["vel"] = (sp["vel"] as Vector2) * (1.0 - delta * 2.8)
	_sparks.assign(_sparks.filter(func(s: Dictionary) -> bool: return float(s["t"]) < float(s["life"])))
	_backdrop.queue_redraw()


func _draw_backdrop() -> void:
	var c := size * Vector2(0.5, 0.48)
	var pulse := 1.0 + sin(_time * 1.8) * 0.05
	# 角色主题光晕背景圈
	_backdrop.draw_circle(c, minf(size.x, size.y) * 0.43 * pulse, Color(_theme_col, 0.16), true, -1.0, true)
	_backdrop.draw_circle(c, minf(size.x, size.y) * 0.30 * pulse, Color(_accent, 0.12), true, -1.0, true)
	# 旋转几何魔法装饰环
	var r_ring := minf(size.x, size.y) * 0.39
	_backdrop.draw_arc(c, r_ring, _time * 0.35, _time * 0.35 + TAU * 0.72, 48, Color(_accent, 0.25), 2.0, true)
	_backdrop.draw_arc(c, r_ring * 0.88, -_time * 0.25, -_time * 0.25 + TAU * 0.55, 48, Color(_theme_col, 0.28), 1.5, true)

	# 漂浮星尘光点
	for p in _particles:
		var px := (float(p["x"]) + sin(_time * 0.9 + float(p["phase"])) * 0.02) * size.x
		var py := float(p["y"]) * size.y
		var a := 0.25 + 0.25 * sin(_time * 2.5 + float(p["phase"]))
		_backdrop.draw_circle(Vector2(px, py), float(p["r"]), Color(_accent, a), true, -1.0, true)

	# 互动星光爆发
	for sp in _sparks:
		var k := 1.0 - float(sp["t"]) / float(sp["life"])
		var pos := sp["pos"] as Vector2
		var r := float(sp["r"]) * k
		_backdrop.draw_circle(pos, r, Color(_accent, k), true, -1.0, true)
		_backdrop.draw_line(pos - Vector2(r * 2.2, 0), pos + Vector2(r * 2.2, 0), Color(1, 1, 1, k), 1.5)
		_backdrop.draw_line(pos - Vector2(0, r * 2.2), pos + Vector2(0, r * 2.2), Color(1, 1, 1, k), 1.5)
