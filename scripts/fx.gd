class_name Fx
extends Node2D
## 战场特效：飘字(text)、爆炸波纹(burst)、受击火花(hit_impact)、激光(laser)、增益光环(buff_aura)、
## 天降轨道激光(orbital_strike)、连锁星雷(lightning)、圣典陨星(meteor)

var kind := "text"
var text := ""
var color := Color.WHITE
var life := 0.8
var t := 0.0
var ring_radius := 30.0
var beam_end := Vector2.ZERO
var beam_width := 10.0
var hit_dir := Vector2.RIGHT
var is_crit := false
var is_shield := false
var points: PackedVector2Array = PackedVector2Array()
var follow_target: Node2D = null
var font_size := 22
var basin_scale := 1.65
var fall_dur := 0.28
var show_duang := true

var _sparks: Array[Dictionary] = []
var _basin_tex: Texture2D = null


func _ready() -> void:
	if kind == "basin_drop":
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_basin_tex = PixelSprites.get_weapon_texture("basin")
		for i in 12:
			var ang := i * TAU / 12.0 + randf_range(-0.18, 0.18)
			_sparks.append({
				"dir": Vector2.from_angle(ang),
				"dist": randf_range(0.55, 1.12),
				"sz": randf_range(4.0, 7.5),
				"alt": (i % 2 == 0),
			})
	elif kind == "hit_impact":
		var base_ang := hit_dir.angle()
		var count := 10 if is_crit else 6
		for i in count:
			var spread := randf_range(-0.95, 0.95) if i < count - 2 else randf_range(-PI, PI)
			_sparks.append({
				"dir": Vector2.from_angle(base_ang + spread),
				"dist": randf_range(26.0, 62.0) * (1.35 if is_crit else 1.0),
				"sz": randf_range(3.5, 6.5) * (1.25 if is_crit else 1.0),
				"alt": (i % 2 == 1),
			})


func _process(delta: float) -> void:
	t += delta
	if kind == "text":
		position.y -= 58.0 * delta
	elif kind == "buff_aura" and follow_target != null and is_instance_valid(follow_target):
		position = follow_target.position
	if kind == "basin_drop" or kind == "meteor":
		var k := clampf(t / maxf(life, 0.01), 0.0, 1.0)
		modulate.a = 1.0 if k < 0.72 else clampf(1.0 - (k - 0.72) / 0.28, 0.0, 1.0)
	else:
		modulate.a = clampf(1.0 - t / life, 0.0, 1.0)
	if t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(t / life, 0.0, 1.0)
	match kind:
		"text":
			var font := ThemeDB.fallback_font
			draw_string_outline(font, Vector2(-100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, font_size, 5, Color(0, 0, 0, 0.85))
			draw_string(font, Vector2(-100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, font_size, color)
		"hit_impact":
			var ease_out := 1.0 - (1.0 - k) * (1.0 - k)
			var main_col := Color(0.55, 0.88, 1.0) if is_shield else (Color(1.0, 0.72, 0.22) if is_crit else color)
			if k < 0.55:
				var fk := 1.0 - k / 0.55
				var flash_r := (16.0 if is_crit else 11.0) * fk
				draw_circle(Vector2.ZERO, flash_r, Color(1.0, 0.98, 0.9, 0.85 * fk))
				var slash_len := (26.0 if is_crit else 18.0) * (0.6 + ease_out * 0.8)
				var d1 := hit_dir.rotated(0.55)
				var d2 := hit_dir.rotated(-0.55)
				draw_line(-d1 * slash_len, d1 * slash_len, Color(1.0, 0.96, 0.85, fk), 3.2 if is_crit else 2.2)
				draw_line(-d2 * slash_len * 0.75, d2 * slash_len * 0.75, Color(main_col.r, main_col.g, main_col.b, fk), 2.5 if is_crit else 1.8)
			var r := (10.0 + ease_out * (34.0 if is_crit else 24.0))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(main_col.r, main_col.g, main_col.b, (1.0 - k) * 0.85), (3.6 if is_crit else 2.4) * (1.0 - k) + 0.8)
			if is_shield or is_crit:
				var r2 := 6.0 + ease_out * 44.0
				draw_arc(Vector2.ZERO, r2, hit_dir.angle() - 1.1, hit_dir.angle() + 1.1, 16, Color(1.0, 0.95, 0.7, (1.0 - k) * 0.75), 2.2)
			for sp in _sparks:
				var p := (sp["dir"] as Vector2) * (float(sp["dist"]) * ease_out)
				var sz := float(sp["sz"]) * (1.0 - k * 0.75)
				var sc := Color(1.0, 0.97, 0.85) if bool(sp["alt"]) else main_col
				draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), sc)
		"basin_drop":
			# 天降巨型精钢铁盆：前半段高空疾坠 + 地面锁敌预警圈与渐大阴影；落地瞬间 DUANG! 金属震荡波 + 弹性弹跳晃动！
			var bw := 42.0 * basin_scale
			var bh := 33.0 * basin_scale
			if t < fall_dur:
				var fk := clampf(t / maxf(fall_dur, 0.01), 0.0, 1.0)
				# 地面落点预警圈 + 收缩准星
				draw_circle(Vector2.ZERO, ring_radius, Color(0.28, 0.78, 1.0, 0.12 + fk * 0.14))
				draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 36, Color(0.65, 0.94, 1.0, 0.65 + fk * 0.35), 2.8)
				var lock_r := ring_radius * (1.0 - fk * 0.65)
				draw_arc(Vector2.ZERO, lock_r, 0.0, TAU, 28, Color(1.0, 0.95, 0.70, 0.75), 2.0)
				# 随下坠越来越大、越来越浓的接地椭圆阴影
				var sh_sc := 0.25 + fk * 0.78
				draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
				draw_circle(Vector2.ZERO, bw * 0.56 * sh_sc, Color(0.02, 0.05, 0.10, 0.18 + fk * 0.38))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				# 高空重力加速下坠（-390 -> 0，全程在视野内清晰可见疾坠轨迹！）+ 银蓝速度风压线
				var y_pos := -390.0 * pow(1.0 - fk, 1.55)
				var trail := 110.0 + fk * 110.0
				draw_line(Vector2(-bw * 0.32, y_pos), Vector2(-bw * 0.32, y_pos - trail), Color(0.75, 0.95, 1.0, 0.55), 3.0)
				draw_line(Vector2(0, y_pos - 10.0), Vector2(0, y_pos - trail * 1.15), Color(1.0, 1.0, 1.0, 0.75), 4.0)
				draw_line(Vector2(bw * 0.32, y_pos), Vector2(bw * 0.32, y_pos - trail), Color(0.55, 0.88, 1.0, 0.55), 3.0)
				if _basin_tex != null:
					var sc_fall := 0.88 + fk * 0.22
					var tilt := sin(fk * 10.0) * 0.14
					draw_set_transform(Vector2(0.0, y_pos), tilt, Vector2(sc_fall, sc_fall))
					draw_texture_rect(_basin_tex, Rect2(-bw * 0.5, -bh * 0.5, bw, bh), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				var ek := clampf((t - fall_dur) / maxf(life - fall_dur, 0.01), 0.0, 1.0)
				var ease_out := 1.0 - (1.0 - ek) * (1.0 - ek)
				# 落地瞬间刺目金属闪光 + 地面冲击波双环
				if ek < 0.22:
					var fl := 1.0 - ek / 0.22
					draw_circle(Vector2.ZERO, ring_radius * (0.45 + ek * 1.8), Color(0.92, 0.98, 1.0, 0.72 * fl))
				draw_circle(Vector2.ZERO, ring_radius * (0.38 + ease_out * 0.70), Color(0.42, 0.84, 1.0, 0.26 * (1.0 - ek)))
				draw_arc(Vector2.ZERO, ring_radius * (0.35 + ease_out * 0.82), 0.0, TAU, 40, Color(0.92, 0.98, 1.0, (1.0 - ek) * 0.95), 7.0 * (1.0 - ek) + 1.2)
				draw_arc(Vector2.ZERO, ring_radius * (0.20 + ease_out * 0.98), 0.0, TAU, 36, Color(0.32, 0.78, 1.0, (1.0 - ek) * 0.85), 4.5 * (1.0 - ek) + 1.0)
				# 飞溅银蓝金属像素火花
				for sp in _sparks:
					var sp_p := (sp["dir"] as Vector2) * (ring_radius * float(sp["dist"]) * ease_out)
					var ssz := float(sp["sz"]) * (1.0 - ek * 0.72)
					draw_rect(Rect2(sp_p - Vector2(ssz, ssz) * 0.5, Vector2(ssz, ssz)), Color("#eef8ff") if bool(sp["alt"]) else Color("#4cb8ff"))
				# 落地压扁 + 搞笑金属阻尼弹跳晃动（DUANG~）
				draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.44))
				draw_circle(Vector2.ZERO, bw * 0.58, Color(0.02, 0.05, 0.10, 0.42 * (1.0 - ek * 0.5)))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if _basin_tex != null:
					var squash := maxf(0.0, 1.0 - ek * 7.0)
					var hop := -absf(sin(ek * PI * 2.2)) * 22.0 * (1.0 - ek)
					var wobble := sin(ek * 30.0) * 0.26 * (1.0 - ek)
					var sx := 1.0 + squash * 0.34
					var sy := 1.0 - squash * 0.28
					draw_set_transform(Vector2(0.0, hop), wobble, Vector2(sx, sy))
					draw_texture_rect(_basin_tex, Rect2(-bw * 0.5, -bh * 0.62, bw, bh), false)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if show_duang and ek < 0.78:
					var font := ThemeDB.fallback_font
					var dy := -bh * 0.85 - ease_out * 36.0
					var fsz := int(22 + basin_scale * 4)
					draw_string_outline(font, Vector2(-90, dy), "DUANG!", HORIZONTAL_ALIGNMENT_CENTER, 180, fsz, 5, Color(0.06, 0.12, 0.25, 0.92))
					draw_string(font, Vector2(-90, dy), "DUANG!", HORIZONTAL_ALIGNMENT_CENTER, 180, fsz, Color("#dff6ff"))
		"eclipse_slash":
			# Grok 暗蚀暴击斩：双道黑红鎏金 360° 横扫巨镰斩波！
			var ease_e := 1.0 - (1.0 - k) * (1.0 - k)
			var sr := ring_radius * (0.45 + ease_e * 0.65)
			var spin_a := k * 3.4
			draw_circle(Vector2.ZERO, sr, Color(0.88, 0.14, 0.28, 0.16 * (1.0 - k)))
			for side in [0.0, PI]:
				draw_arc(Vector2.ZERO, sr, spin_a + side, spin_a + side + 2.3, 24, Color(0.15, 0.08, 0.16, 0.85 * (1.0 - k)), 18.0 * (1.0 - k) + 3.0)
				draw_arc(Vector2.ZERO, sr, spin_a + side + 0.06, spin_a + side + 2.24, 24, Color(0.96, 0.22, 0.36, 0.95 * (1.0 - k)), 9.5 * (1.0 - k) + 2.0)
				draw_arc(Vector2.ZERO, sr * 1.03, spin_a + side + 0.2, spin_a + side + 2.0, 20, Color(1.0, 0.88, 0.48, 0.95 * (1.0 - k)), 3.2 * (1.0 - k) + 0.8)
		"orbital_strike":
			# 天降深蓝轨道激光柱 + 地面冲击波环
			var w := ring_radius * 0.85 * (1.0 - k * 0.7)
			draw_rect(Rect2(-w, -560.0, w * 2.0, 560.0), Color(color, 0.35 * (1.0 - k)))
			draw_rect(Rect2(-w * 0.5, -560.0, w, 560.0), Color(color, 0.85 * (1.0 - k)))
			draw_rect(Rect2(-w * 0.22, -560.0, w * 0.44, 560.0), Color(1.0, 1.0, 1.0, 0.95 * (1.0 - k)))
			draw_circle(Vector2.ZERO, ring_radius * (0.45 + k * 0.85), Color(color, 0.28 * (1.0 - k)))
			draw_arc(Vector2.ZERO, ring_radius * (0.5 + k * 0.95), 0.0, TAU, 36, Color(0.7, 0.95, 1.0, 1.0 - k), 5.0 * (1.0 - k) + 1.0)
		"lightning":
			# 蓝粉星光锯齿连锁雷电
			if points.size() >= 2:
				for i in points.size() - 1:
					var a := points[i]
					var b := points[i + 1]
					var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * sin(t * 90.0 + i * 3.1) * 14.0
					var seg := PackedVector2Array([a, mid, b])
					draw_polyline(seg, Color(color, 0.45 * (1.0 - k)), 9.0 * (1.0 - k) + 2.0)
					draw_polyline(seg, Color(1.0, 0.92, 1.0, 1.0 - k), 3.2 * (1.0 - k) + 1.0)
					draw_circle(b, 8.0 * (1.0 - k), Color(1.0, 0.95, 0.8, 1.0 - k))
		"meteor":
			# 暖橙圣典流火陨星：前 40% 坠落，后 60% 爆炸冲击
			if k < 0.40:
				var fk := k / 0.40
				draw_arc(Vector2.ZERO, ring_radius * (0.4 + fk * 0.6), 0.0, TAU, 28, Color(color, 0.65), 2.5)
				var pos := Vector2(-140.0, -340.0).lerp(Vector2.ZERO, fk)
				draw_line(pos, pos - Vector2(-35.0, -85.0), Color(color, 0.55), 14.0)
				draw_circle(pos, 18.0, color)
				draw_circle(pos, 9.0, Color(1.0, 0.96, 0.78))
			else:
				var ek := (k - 0.40) / 0.60
				draw_circle(Vector2.ZERO, ring_radius * (0.4 + ek * 0.85), Color(color, 0.34 * (1.0 - ek)))
				draw_arc(Vector2.ZERO, ring_radius * (0.5 + ek * 0.9), 0.0, TAU, 32, Color(1.0, 0.86, 0.45, 1.0 - ek), 6.0 * (1.0 - ek) + 1.0)
		"burst":
			draw_arc(Vector2.ZERO, ring_radius * (0.6 + k * 2.2), 0.0, TAU, 32, color, 5.0 * (1.0 - k) + 1.0)
			for i in 10:
				var dir := Vector2.from_angle(i * TAU / 10.0 + k * 0.4)
				var p := dir * ring_radius * (0.4 + k * 2.5)
				var sz := 6.0 * (1.0 - k)
				draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), color)
		"laser":
			var w := beam_width * (1.0 - k * 0.65)
			draw_line(Vector2.ZERO, beam_end, Color(color, 0.35), w * 2.4)
			draw_line(Vector2.ZERO, beam_end, color, w * 1.25)
			draw_line(Vector2.ZERO, beam_end, Color.WHITE, maxf(w * 0.45, 2.0))
			draw_circle(Vector2.ZERO, w * 1.1, Color.WHITE)
			draw_circle(beam_end, w * 1.3, color)
		"buff_aura":
			var r := ring_radius * (0.7 + k * 2.6)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(color, 1.0 - k), 6.0 * (1.0 - k) + 1.5)
			draw_arc(Vector2.ZERO, r * 0.65, k * TAU, k * TAU + PI * 1.4, 28, Color(1, 0.96, 0.65, 1.0 - k), 3.0)
			for i in 8:
				var ang := i * TAU / 8.0 + k * 2.2
				var p := Vector2.from_angle(ang) * r
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.95, 0.6, 1.0 - k))
