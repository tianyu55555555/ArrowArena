class_name Arena
extends Node2D
## 双地图像素战场渲染器：
## - PVE（算力潮汐/双人合作）：无缝 128x128 有机像素草地 + 中央 AI 检查点圣所 + 4 种 32x32 精绘障碍物
## - PVP（五宫格决斗场）：中央最大决斗场 + 像素石砌高墙与拱门 + 四边特殊房间（超频室/回春泉/极速风道/Token宝库）

var game: Game
var _grass: Texture2D
var _obs_tex: Dictionary = {}
var _prop_tex: Dictionary = {}
var _creep_tex: Dictionary = {}
var _mid_boss_tex: Texture2D = null
var _props: Array[Dictionary] = []
var _t := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_grass = PixelSprites.get_grass_tile()
	for k in ["moss_rock", "server_pillar", "pine_cluster", "data_crystal"]:
		_obs_tex[k] = PixelSprites.get_obstacle_texture(k)
	for pk in ["flower_bed", "flagstone", "circuit_pad", "clover_tuft"]:
		_prop_tex[pk] = PixelSprites.get_prop_texture(pk)
	for ck in ["glitch", "hallucination", "spam_tank"]:
		_creep_tex[ck] = PixelSprites.get_monster_texture(ck)
	_mid_boss_tex = PixelSprites.get_monster_texture("boss")
	if game == null or game.game_mode != "pvp":
		_build_ground_props()


func _build_ground_props() -> void:
	_props.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var kinds := ["flower_bed", "clover_tuft", "flagstone", "flower_bed", "clover_tuft", "circuit_pad"]
	var h := Game.ARENA_HALF - 110.0
	for _i in 64:
		var p := Vector2(rng.randf_range(-h, h), rng.randf_range(-h, h))
		if p.length() < 240.0:
			continue
		if game != null and (game.point_in_rock(p, 28.0) or game.point_in_wall(p, 24.0)):
			continue
		var k: String = kinds[rng.randi() % kinds.size()]
		var sc := rng.randf_range(2.6, 3.6)
		_props.append({"pos": p, "kind": k, "sc": sc})


func _process(delta: float) -> void:
	_t += delta
	# PVP 含移动锯刃陷阱与野生数据怪，每帧顺滑刷新；PVE 低频脉冲零开销
	if (game != null and game.game_mode == "pvp") or int(_t * 15.0) != int((_t - delta) * 15.0):
		queue_redraw()


func _draw() -> void:
	var h := Game.ARENA_HALF
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	var vr := game.visible_world_rect(140.0) if game != null else Rect2(-h, -h, h * 2, h * 2)

	if game != null and game.game_mode == "pvp":
		_draw_pvp_5grid(h, pulse, vr)
	else:
		_draw_survivor_meadow(h, pulse, vr)

	# 绘制 32x32 精绘像素障碍物（两模式共用）
	if game == null:
		return
	for i in game.rocks.size():
		var r := game.rocks[i]
		var c := Vector2(r.x, r.y)
		var rad := r.z
		if not vr.grow(rad + 40.0).has_point(c):
			continue
		var kind := game.rock_kinds[i] if i < game.rock_kinds.size() else "moss_rock"
		var tex: Texture2D = _obs_tex.get(kind, _obs_tex["moss_rock"])

		draw_set_transform(c + Vector2(4.0, rad * 0.58), 0.0, Vector2(1.0, 0.44))
		draw_circle(Vector2.ZERO, rad * 1.06, Color(0.04, 0.08, 0.06, 0.34))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		if kind == "server_pillar" or kind == "data_crystal":
			var gcol := Color(0.24, 0.86, 1.0, 0.12 + pulse * 0.08) if kind == "server_pillar" else Color(0.38, 0.72, 1.0, 0.14 + pulse * 0.10)
			draw_circle(c + Vector2(0, rad * 0.15), rad * 1.18, gcol)

		var draw_sz := rad * 2.38
		var dst := Rect2(c.x - draw_sz * 0.5, c.y - draw_sz * 0.58, draw_sz, draw_sz)
		draw_texture_rect(tex, dst, false)


# ================= PVP 五宫格决斗场绘制 =================
func _draw_pvp_5grid(h: float, pulse: float, vr: Rect2) -> void:
	var font := PixelSprites.ui_font()
	# 1. 场外深渊石底
	draw_rect(Rect2(-h - 1600, -h - 1600, (h + 1600) * 2, (h + 1600) * 2), Color("#101420"))

	# 2. 整体暗青石板基底（含四角包抄侧廊）
	draw_rect(Rect2(-h, -h, h * 2.0, h * 2.0), Color("#252d3d"))
	# 柔和像素石砖大网格（128px 间距，清晰不刺眼）
	var gcol := Color(1.0, 1.0, 1.0, 0.045)
	var x0: float = floorf(maxf(-h, vr.position.x) / 128.0) * 128.0
	var x1: float = minf(h, vr.end.x)
	var y0: float = floorf(maxf(-h, vr.position.y) / 128.0) * 128.0
	var y1: float = minf(h, vr.end.y)
	var gx: float = x0
	while gx <= x1:
		draw_line(Vector2(gx, maxf(-h, vr.position.y)), Vector2(gx, y1), gcol, 2.0)
		gx += 128.0
	var gy: float = y0
	while gy <= y1:
		draw_line(Vector2(maxf(-h, vr.position.x), gy), Vector2(x1, gy), gcol, 2.0)
		gy += 128.0

	# 3. 四边特殊房间主题地砖 + 发光阵纹 + 地面铭牌
	for rm in game.special_rooms:
		var rc: Rect2 = rm["rect"]
		if not vr.intersects(rc):
			continue
		var bg: Color = rm["bg"]
		var acc: Color = rm["color"]
		draw_rect(rc, bg)
		draw_rect(rc.grow(-10.0), Color(acc.r, acc.g, acc.b, 0.24 + pulse * 0.14), false, 4.0)
		var c := rc.get_center()
		# 房间专属图案
		match str(rm["id"]):
			"overclock":
				# 北·算力超频室：炽热熔岩能量方阵
				draw_circle(c, 150.0, Color(acc.r, acc.g, acc.b, 0.10 + pulse * 0.07))
				draw_arc(c, 145.0, 0.0, TAU, 32, Color(acc.r, acc.g, acc.b, 0.45 + pulse * 0.2), 3.0)
				for dx in [-260.0, 260.0]:
					draw_rect(Rect2(c + Vector2(dx - 24, -24), Vector2(48, 48)), Color(acc.r, acc.g, acc.b, 0.16))
					draw_rect(Rect2(c + Vector2(dx - 24, -24), Vector2(48, 48)), Color(acc.r, acc.g, acc.b, 0.55), false, 2.5)
			"heal_spring":
				# 南·数据回春泉：翠绿涟漪泉眼
				draw_circle(c, 170.0, Color(0.20, 0.85, 0.56, 0.14 + pulse * 0.08))
				draw_arc(c, 155.0, 0.0, TAU, 36, Color(0.35, 1.0, 0.68, 0.50 + pulse * 0.22), 3.5)
				draw_arc(c, 92.0 + pulse * 14.0, 0.0, TAU, 28, Color(0.65, 1.0, 0.82, 0.42), 2.5)
				# 像素绿色十字泉心
				draw_rect(Rect2(c + Vector2(-12, -36), Vector2(24, 72)), Color(0.45, 1.0, 0.72, 0.45))
				draw_rect(Rect2(c + Vector2(-36, -12), Vector2(72, 24)), Color(0.45, 1.0, 0.72, 0.45))
			"speed_lane":
				# 西·极速风道：青蓝高速滑轨与箭头
				for ay in range(-480, 481, 160):
					var p := Vector2(c.x, c.y + ay)
					var shift := sin(_t * 4.0 + ay * 0.01) * 10.0
					var pts := PackedVector2Array([
						p + Vector2(-46, -24 + shift), p + Vector2(0, -52 + shift), p + Vector2(46, -24 + shift),
					])
					draw_polyline(pts, Color(acc.r, acc.g, acc.b, 0.45 + pulse * 0.25), 5.0)
			"creep_den":
				# 东·脏数据野区：紫红乱码警戒圈与野怪巢穴铭文
				for ay in [-280.0, 0.0, 280.0]:
					var p := Vector2(c.x, c.y + ay)
					draw_circle(p, 56.0, Color(acc.r, acc.g, acc.b, 0.10 + pulse * 0.06))
					draw_arc(p, 52.0, 0.0, TAU, 24, Color(acc.r, acc.g, acc.b, 0.45 + pulse * 0.2), 2.5)
					draw_rect(Rect2(p - Vector2(10, 10), Vector2(20, 20)), Color(1.0, 0.45, 0.72, 0.35))

		# 房间名称与增益地板铭文
		var title_txt := str(rm["name"])
		var sub_txt := str(rm["desc"])
		draw_string_outline(font, c + Vector2(-180, -10), title_txt, HORIZONTAL_ALIGNMENT_CENTER, 360, 28, 5, Color(0, 0, 0, 0.55))
		draw_string(font, c + Vector2(-180, -10), title_txt, HORIZONTAL_ALIGNMENT_CENTER, 360, 28, Color(acc.r, acc.g, acc.b, 0.75))
		draw_string_outline(font, c + Vector2(-180, 20), sub_txt, HORIZONTAL_ALIGNMENT_CENTER, 360, 16, 4, Color(0, 0, 0, 0.55))
		draw_string(font, c + Vector2(-180, 20), sub_txt, HORIZONTAL_ALIGNMENT_CENTER, 360, 16, Color(0.95, 0.98, 1.0, 0.65))

	# 4. 中央最大房间：Grand Colosseum「中央决斗场」(-740..+740)
	var center_rc := Rect2(-740.0, -740.0, 1480.0, 1480.0)
	if vr.intersects(center_rc):
		draw_rect(center_rc, Color("#333d52"))
		draw_rect(center_rc.grow(-18.0), Color(1.0, 0.84, 0.42, 0.22 + pulse * 0.10), false, 4.0)
		# 中央决斗沙盘八角徽记
		_draw_central_sanctuary(pulse)
		draw_arc(Vector2.ZERO, 480.0, 0.0, TAU, 48, Color(1.0, 0.85, 0.44, 0.24 + pulse * 0.12), 4.0)
		draw_string_outline(font, Vector2(-180, -225), "⚔ 中央决斗场", HORIZONTAL_ALIGNMENT_CENTER, 360, 28, 5, Color(0, 0, 0, 0.55))
		draw_string(font, Vector2(-180, -225), "⚔ 中央决斗场", HORIZONTAL_ALIGNMENT_CENTER, 360, 28, Color(1.0, 0.88, 0.52, 0.72))
		if game.mid_boss.is_empty():
			var cd_s := int(ceil(game.mid_boss_cd))
			var warn := cd_s <= 10
			var cd_col := Color(1.0, 0.36, 0.48, 0.82 + pulse * 0.18) if warn else Color(1.0, 0.88, 0.48, 0.68)
			var cd_txt := "★ Mid Boss 降临倒计时 %d:%02d（击杀 30s 全增益 + 复活）" % [cd_s / 60, cd_s % 60]
			draw_string_outline(font, Vector2(-260, 232), cd_txt, HORIZONTAL_ALIGNMENT_CENTER, 520, 16, 4, Color(0, 0, 0, 0.65))
			draw_string(font, Vector2(-260, 232), cd_txt, HORIZONTAL_ALIGNMENT_CENTER, 520, 16, cd_col)

	# 4.5 四角增益符文祭坛（6 种随机：减伤 / 吸血 / 回血 / 减CD / 临时血量 / 子弹变大，持续 15s，60s 刷新）
	for shrine in game.pvp_runes:
		var sp: Vector2 = shrine["pos"]
		if not vr.grow(150.0).has_point(sp):
			continue
		var kind := str(shrine["kind"])
		var ph := float(shrine.get("phase", 0.0))
		# 祭坛八角底座
		draw_circle(sp, 78.0, Color(0.08, 0.12, 0.20, 0.62))
		var oct_pts := PackedVector2Array()
		for oi in 8:
			oct_pts.append(sp + Vector2.from_angle(oi * TAU / 8.0 + PI / 8.0) * 66.0)
		draw_colored_polygon(oct_pts, Color("#202a3c"))
		var oct_in := PackedVector2Array()
		for oi in 8:
			oct_in.append(sp + Vector2.from_angle(oi * TAU / 8.0 + PI / 8.0) * 52.0)
		draw_colored_polygon(oct_in, Color("#2c3952"))
		draw_string_outline(font, sp + Vector2(-120, -76), "✦ 四角增益符文祭坛 ✦", HORIZONTAL_ALIGNMENT_CENTER, 240, 14, 4, Color(0, 0, 0, 0.72))
		draw_string(font, sp + Vector2(-120, -76), "✦ 四角增益符文祭坛 ✦", HORIZONTAL_ALIGNMENT_CENTER, 240, 14, Color(0.84, 0.92, 1.0, 0.85))
		if kind != "" and Archer.RUNE_DEFS.has(kind):
			var rdef: Dictionary = Archer.RUNE_DEFS[kind]
			var rcol: Color = rdef["color"]
			var bob := sin(_t * 3.8 + ph) * 6.0
			var orb_p := sp + Vector2(0.0, -4.0 + bob)
			draw_circle(sp, 64.0, Color(rcol.r, rcol.g, rcol.b, 0.14 + pulse * 0.10))
			draw_arc(sp, 62.0, 0.0, TAU, 32, Color(rcol.r, rcol.g, rcol.b, 0.72 + pulse * 0.24), 3.2)
			draw_arc(sp, 44.0, _t * 1.6 + ph, _t * 1.6 + ph + PI * 1.35, 24, Color(1.0, 1.0, 1.0, 0.55), 2.2)
			# 悬浮发光六角符文水晶
			draw_circle(orb_p, 29.0, Color(rcol.r, rcol.g, rcol.b, 0.28 + pulse * 0.12))
			var gem := PackedVector2Array()
			for gi in 6:
				gem.append(orb_p + Vector2.from_angle(gi * TAU / 6.0 - PI * 0.5) * 23.0)
			draw_colored_polygon(gem, rcol.darkened(0.18))
			var gem_in := PackedVector2Array()
			for gi in 6:
				gem_in.append(orb_p + Vector2.from_angle(gi * TAU / 6.0 - PI * 0.5) * 16.5)
			draw_colored_polygon(gem_in, rcol.lightened(0.22))
			var tag := str(rdef["tag"])
			draw_string_outline(font, orb_p + Vector2(-24, 7), tag, HORIZONTAL_ALIGNMENT_CENTER, 48, 18, 4, Color(0, 0, 0, 0.90))
			draw_string(font, orb_p + Vector2(-24, 7), tag, HORIZONTAL_ALIGNMENT_CENTER, 48, 18, Color.WHITE)
			# 名称与效果铭牌
			draw_string_outline(font, sp + Vector2(-120, 44), "【%s】" % rdef["name"], HORIZONTAL_ALIGNMENT_CENTER, 240, 17, 4, Color(0, 0, 0, 0.85))
			draw_string(font, sp + Vector2(-120, 44), "【%s】" % rdef["name"], HORIZONTAL_ALIGNMENT_CENTER, 240, 17, rcol.lightened(0.2))
			draw_string_outline(font, sp + Vector2(-130, 64), "持续 15s · %s" % rdef["desc"], HORIZONTAL_ALIGNMENT_CENTER, 260, 13, 4, Color(0, 0, 0, 0.85))
			draw_string(font, sp + Vector2(-130, 64), "持续 15s · %s" % rdef["desc"], HORIZONTAL_ALIGNMENT_CENTER, 260, 13, Color(0.95, 0.98, 1.0))
		else:
			var cd := float(shrine.get("cd", 0.0))
			var prog := clampf(1.0 - cd / Game.RUNE_RESPAWN, 0.0, 1.0)
			draw_arc(sp, 58.0, 0.0, TAU, 28, Color(0.42, 0.52, 0.68, 0.35), 3.0)
			draw_arc(sp, 58.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 28, Color(0.38, 0.88, 1.0, 0.82), 4.0)
			var wait_txt := "符文充能中 %ds" % int(ceil(cd))
			draw_string_outline(font, sp + Vector2(-110, 6), wait_txt, HORIZONTAL_ALIGNMENT_CENTER, 220, 16, 4, Color(0, 0, 0, 0.80))
			draw_string(font, sp + Vector2(-110, 6), wait_txt, HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color(0.70, 0.82, 0.96))

	# 5. 2.5D 像素石砌主城厚墙 & 室内金属战术薄墙
	for w in game.walls:
		if not vr.grow(40.0).intersects(w):
			continue
		var is_thin := minf(w.size.x, w.size.y) < 36.0
		if is_thin:
			# 战术薄墙：清晰金属蓝钢骨架 + 青金脉冲能量筋条（一眼识别掩体与可穿墙目标！）
			draw_rect(Rect2(w.position + Vector2(4, 6), w.size), Color(0.02, 0.04, 0.08, 0.38))
			draw_rect(w.grow(2.0), Color("#121724"))
			draw_rect(w, Color("#3a4b68"))
			draw_rect(Rect2(w.position + Vector2(2, 2), w.size - Vector2(4, 4)), Color("#587096"))
			var rib := Color(0.38, 0.90, 1.0, 0.55 + pulse * 0.25)
			if w.size.x >= w.size.y:
				draw_line(Vector2(w.position.x + 8, w.position.y + w.size.y * 0.5), Vector2(w.end.x - 8, w.position.y + w.size.y * 0.5), rib, 3.0)
			else:
				draw_line(Vector2(w.position.x + w.size.x * 0.5, w.position.y + 8), Vector2(w.position.x + w.size.x * 0.5, w.end.y - 8), rib, 3.0)
			continue
		# 接地投影
		draw_rect(Rect2(w.position + Vector2(8, 12), w.size), Color(0.02, 0.04, 0.08, 0.46))
		# 深色外描边
		draw_rect(w.grow(3.0), Color("#141824"))
		# 墙体正立面（下缘暗石砖带）
		draw_rect(w, Color("#404b63"))
		# 墙顶高光石面
		var top_h := maxf(w.size.y - 12.0, w.size.y * 0.62)
		draw_rect(Rect2(w.position, Vector2(w.size.x, top_h)), Color("#647491"))
		draw_rect(Rect2(w.position, Vector2(w.size.x, 5.0)), Color("#96a8c7"))
		# 像素石块拼接缝
		if w.size.x >= w.size.y:
			var bx := w.position.x + 48.0
			while bx < w.end.x - 16.0:
				draw_line(Vector2(bx, w.position.y + 3.0), Vector2(bx, w.end.y - 3.0), Color("#2e374a"), 2.0)
				bx += 48.0
		else:
			var by := w.position.y + 48.0
			while by < w.end.y - 16.0:
				draw_line(Vector2(w.position.x + 3.0, by), Vector2(w.end.x - 3.0, by), Color("#2e374a"), 2.0)
				by += 48.0
		# 两端青蓝能量门柱灯
		var cap_col := Color(0.32, 0.88, 1.0, 0.68 + pulse * 0.28)
		for ep: Vector2 in [w.position + Vector2(10, 10), w.end - Vector2(10, 10)]:
			draw_rect(Rect2(ep - Vector2(5, 5), Vector2(10, 10)), cap_col)

	# 5.5 西·极速风道：巡航电锯移动陷阱（地面导轨 + 高速旋转红热锯齿轮！）
	for tr in game.pvp_traps:
		var base_p: Vector2 = tr["base"]
		var axis: Vector2 = tr["axis"]
		var p_a := base_p - axis
		var p_b := base_p + axis
		if vr.grow(120.0).intersects(Rect2(Vector2(minf(p_a.x, p_b.x), minf(p_a.y, p_b.y)), (p_b - p_a).abs() + Vector2(60, 60))):
			draw_line(p_a, p_b, Color(0.08, 0.12, 0.18, 0.85), 10.0)
			draw_line(p_a, p_b, Color(1.0, 0.34, 0.34, 0.36), 3.0)
			draw_circle(p_a, 7.0, Color("#4a556e"))
			draw_circle(p_b, 7.0, Color("#4a556e"))
		var tp := game.pvp_trap_pos(tr)
		if not vr.grow(50.0).has_point(tp):
			continue
		var tr_r := float(tr["r"])
		draw_circle(tp + Vector2(3, 5), tr_r * 1.02, Color(0, 0, 0, 0.35))
		draw_circle(tp, tr_r + 6.0, Color(1.0, 0.22, 0.28, 0.18 + pulse * 0.12))
		# 8 齿高速旋转锯刃
		var spin := _t * 9.0 + float(tr["phase"])
		for ti in 8:
			var ang := spin + ti * TAU / 8.0
			var tip := tp + Vector2.from_angle(ang) * (tr_r + 4.0)
			var lpt := tp + Vector2.from_angle(ang - 0.24) * (tr_r * 0.62)
			var rpt := tp + Vector2.from_angle(ang + 0.24) * (tr_r * 0.62)
			draw_colored_polygon(PackedVector2Array([tip, lpt, rpt]), Color("#ff505c"))
		draw_circle(tp, tr_r * 0.68, Color("#241b28"))
		draw_arc(tp, tr_r * 0.68, 0.0, TAU, 18, Color("#ffd870"), 2.5)
		draw_circle(tp, tr_r * 0.28, Color("#ff3b4e"))

	# 5.8 东·脏数据野区：野生数据怪绘制（击杀爆高阶 Token 与血药！）
	for c in game.pvp_creeps:
		var cp: Vector2 = c["pos"]
		if not vr.grow(70.0).has_point(cp):
			continue
		var r := float(c["radius"])
		var sz := r * 2.55
		var bob := absf(sin(_t * 6.5 + float(c.get("phase", 0.0)))) * 4.0
		var tint := Color(2.2, 1.4, 1.4, 1.0) if float(c["flash"]) > 0.0 else Color.WHITE
		draw_circle(cp + Vector2(0, r * 0.72), r * 0.78, Color(0, 0, 0, 0.28))
		var tex: Texture2D = _creep_tex.get(str(c["kind"]), _creep_tex["glitch"])
		draw_texture_rect(tex, Rect2(cp.x - sz * 0.5, cp.y - sz * 0.55 - bob, sz, sz), false, tint)
		var w_bar := r * 2.2
		var top_y := cp.y - sz * 0.58 - 7.0
		draw_rect(Rect2(cp.x - w_bar * 0.5, top_y, w_bar, 5.0), Color(0, 0, 0, 0.68))
		draw_rect(Rect2(cp.x - w_bar * 0.5, top_y, w_bar * clampf(float(c["hp"]) / maxf(float(c["max_hp"]), 1.0), 0.0, 1.0), 5.0), Color("#c978ff"))

	# 5.9 中央决斗场 Mid Boss（核心算力霸主）及其紫金能量弹幕！
	if not game.mid_boss.is_empty():
		var mbp: Vector2 = game.mid_boss["pos"]
		if vr.grow(160.0).has_point(mbp):
			var mbr := float(game.mid_boss["radius"])
			var sz := mbr * 2.75
			var bob := absf(sin(_t * 4.5)) * 7.0
			var tint := Color(2.3, 1.4, 1.4, 1.0) if float(game.mid_boss.get("flash", 0.0)) > 0.0 else Color.WHITE
			draw_circle(mbp, mbr + 24.0, Color(1.0, 0.76, 0.24, 0.14 + pulse * 0.09))
			draw_arc(mbp, mbr + 18.0, _t * 1.4, _t * 1.4 + TAU * 0.75, 36, Color(1.0, 0.84, 0.30, 0.78), 3.6)
			draw_arc(mbp, mbr + 10.0, -_t * 2.2, -_t * 2.2 + TAU * 0.65, 32, Color(0.84, 0.38, 1.0, 0.75), 3.0)
			draw_circle(mbp + Vector2(0, mbr * 0.72), mbr * 0.86, Color(0, 0, 0, 0.38))
			if _mid_boss_tex != null:
				draw_texture_rect(_mid_boss_tex, Rect2(mbp.x - sz * 0.5, mbp.y - sz * 0.56 - bob, sz, sz), false, tint)
			var w_bar := 136.0
			var top_y := mbp.y - sz * 0.58 - 18.0
			draw_rect(Rect2(mbp.x - w_bar * 0.5 - 2.0, top_y - 2.0, w_bar + 4.0, 12.0), Color(0, 0, 0, 0.80))
			var hp_r := clampf(float(game.mid_boss["hp"]) / maxf(float(game.mid_boss["max_hp"]), 1.0), 0.0, 1.0)
			draw_rect(Rect2(mbp.x - w_bar * 0.5, top_y, w_bar * hp_r, 8.0), Color("#ff3b6b").lerp(Color("#ffd84a"), hp_r * 0.45))
			draw_string_outline(font, Vector2(mbp.x - 140, top_y - 8.0), "★ MID BOSS · 算力霸主 ★", HORIZONTAL_ALIGNMENT_CENTER, 280, 16, 4, Color(0, 0, 0, 0.90))
			draw_string(font, Vector2(mbp.x - 140, top_y - 8.0), "★ MID BOSS · 算力霸主 ★", HORIZONTAL_ALIGNMENT_CENTER, 280, 16, Color("#ffe058"))

	for mb in game.mid_boss_bullets:
		var bp: Vector2 = mb["pos"]
		if not vr.grow(30.0).has_point(bp):
			continue
		draw_circle(bp, 13.0, Color(0.82, 0.34, 1.0, 0.30))
		draw_circle(bp, 8.5, Color("#d466ff"))
		draw_circle(bp, 4.2, Color("#fff2b2"))

	# 6. 最后 60 秒：过拟合「算力坍缩缩圈」视觉层（安全区外红紫毒雾 + 高亮收缩警戒环！）
	if game.storm_active:
		var sr := game.storm_radius
		var outer_r := Game.ARENA_HALF * 1.55
		var segs := 64
		var veil_col := Color(0.68, 0.06, 0.30, 0.28 + pulse * 0.08)
		for si in segs:
			var a0 := float(si) * TAU / float(segs)
			var a1 := float(si + 1) * TAU / float(segs)
			var d0 := Vector2.from_angle(a0)
			var d1 := Vector2.from_angle(a1)
			draw_colored_polygon(PackedVector2Array([d0 * sr, d0 * outer_r, d1 * outer_r, d1 * sr]), veil_col)
		draw_arc(Vector2.ZERO, sr + 10.0, 0.0, TAU, 72, Color(1.0, 0.22, 0.48, 0.35 + pulse * 0.15), 14.0)
		draw_arc(Vector2.ZERO, sr, 0.0, TAU, 72, Color(1.0, 0.34, 0.56, 0.92), 5.5)
		draw_arc(Vector2.ZERO, maxf(sr - 14.0, 40.0), _t * 0.7, _t * 0.7 + TAU * 0.85, 64, Color(1.0, 0.85, 0.92, 0.42), 2.0)

	# 7. 边界围墙
	_draw_perimeter(h, pulse)


# ================= PVE 像素草地圣所绘制 =================
func _draw_survivor_meadow(h: float, pulse: float, vr: Rect2) -> void:
	draw_rect(Rect2(-h - 1600, -h - 1600, (h + 1600) * 2, (h + 1600) * 2), Color("#131f1b"))
	var src_size := (h * 2.0) / 3.0
	draw_texture_rect_region(
		_grass,
		Rect2(-h, -h, h * 2.0, h * 2.0),
		Rect2(0.0, 0.0, src_size, src_size)
	)
	_draw_walkways(h, pulse)
	_draw_central_sanctuary(pulse)
	for pr in _props:
		var pp: Vector2 = pr["pos"]
		if not vr.has_point(pp):
			continue
		var tex: Texture2D = _prop_tex[pr["kind"]]
		var sz := 16.0 * float(pr["sc"])
		draw_texture_rect(tex, Rect2(pp.x - sz * 0.5, pp.y - sz * 0.5, sz, sz), false)
	_draw_perimeter(h, pulse)


func _draw_central_sanctuary(pulse: float) -> void:
	draw_circle(Vector2.ZERO, 212.0, Color(0.18, 0.34, 0.24, 0.36))
	var oct := _regular_poly(8, 196.0, PI / 8.0)
	draw_colored_polygon(oct, Color("#566376"))
	var oct_in := _regular_poly(8, 182.0, PI / 8.0)
	draw_colored_polygon(oct_in, Color("#6b7a8f"))
	var oct_core := _regular_poly(8, 118.0, PI / 8.0)
	draw_colored_polygon(oct_core, Color("#526075"))

	for i in 8:
		var a := i * TAU / 8.0 + PI / 8.0
		var dir := Vector2.from_angle(a)
		draw_line(dir * 52.0, dir * 182.0, Color("#3e4859"), 3.0)

	var glow := Color(0.28, 0.88, 1.0, 0.48 + pulse * 0.28)
	var gold := Color(1.0, 0.84, 0.38, 0.42 + pulse * 0.22)
	draw_arc(Vector2.ZERO, 152.0, 0.0, TAU, 32, glow, 3.0)
	draw_arc(Vector2.ZERO, 96.0, 0.0, TAU, 32, gold, 2.5)
	draw_arc(Vector2.ZERO, 48.0, 0.0, TAU, 24, glow, 3.5)

	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(dir * 52.0, dir * 194.0, glow, 4.0)
		var node_p := dir * 152.0
		draw_rect(Rect2(node_p - Vector2(7, 7), Vector2(14, 14)), Color("#2b364a"))
		draw_rect(Rect2(node_p - Vector2(4, 4), Vector2(8, 8)), glow)

	draw_circle(Vector2.ZERO, 30.0, Color(0.20, 0.78, 1.0, 0.16 + pulse * 0.12))
	var diamond := PackedVector2Array([Vector2(0, -24), Vector2(24, 0), Vector2(0, 24), Vector2(-24, 0)])
	draw_colored_polygon(diamond, Color(0.32, 0.90, 1.0, 0.35 + pulse * 0.20))
	var inner_d := PackedVector2Array([Vector2(0, -12), Vector2(12, 0), Vector2(0, 12), Vector2(-12, 0)])
	draw_colored_polygon(inner_d, Color(0.85, 0.98, 1.0, 0.65 + pulse * 0.25))


func _draw_walkways(h: float, pulse: float) -> void:
	var step_col := Color(0.42, 0.49, 0.58, 0.52)
	var step_hi := Color(0.60, 0.68, 0.78, 0.42)
	var rune_col := Color(0.30, 0.88, 1.0, 0.28 + pulse * 0.18)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var perp := dir.orthogonal()
		var dist := 245.0
		var idx := 0
		while dist < h - 140.0:
			var p := dir * dist
			var bw := 58.0 if (idx % 2 == 0) else 44.0
			var bh := 26.0
			var sz := Vector2(bh, bw) if absf(dir.x) > 0.5 else Vector2(bw, bh)
			var off := perp * (8.0 if (idx % 3 == 0) else (-8.0 if (idx % 3 == 1) else 0.0))
			var rc := Rect2(p + off - sz * 0.5, sz)
			draw_rect(rc, step_col)
			draw_rect(Rect2(rc.position + Vector2(3, 3), rc.size - Vector2(6, 10)), step_hi)
			if idx % 4 == 1:
				draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), rune_col)
			dist += 96.0
			idx += 1

	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cp := Vector2(sx * 860.0, sy * 860.0)
			draw_circle(cp, 74.0, Color(0.24, 0.34, 0.42, 0.32))
			draw_arc(cp, 68.0, 0.0, TAU, 24, Color(0.45, 0.60, 0.72, 0.45), 3.0)
			draw_arc(cp, 44.0, 0.0, TAU, 20, rune_col, 2.5)
			draw_rect(Rect2(cp - Vector2(10, 10), Vector2(20, 20)), Color("#344358"))
			draw_rect(Rect2(cp - Vector2(5, 5), Vector2(10, 10)), rune_col)


func _draw_perimeter(h: float, pulse: float) -> void:
	draw_rect(Rect2(-h - 56, -h - 56, (h + 56) * 2.0, (h + 56) * 2.0), Color("#1d3627") if (game == null or game.game_mode != "pvp") else Color("#181e2c"), false, 92.0)
	draw_rect(Rect2(-h - 14, -h - 14, h * 2.0 + 28, h * 2.0 + 28), Color("#191e2b"), false, 28.0)
	draw_rect(Rect2(-h - 6, -h - 6, h * 2.0 + 12, h * 2.0 + 12), Color("#58657d"), false, 14.0)
	draw_rect(Rect2(-h - 2, -h - 2, h * 2.0 + 4, h * 2.0 + 4), Color("#8090ab"), false, 5.0)
	draw_rect(Rect2(-h + 4, -h + 4, h * 2.0 - 8, h * 2.0 - 8), Color(0.28, 0.86, 1.0, 0.42 + pulse * 0.25), false, 3.0)

	var py_col := Color(0.32, 0.90, 1.0, 0.65 + pulse * 0.30)
	var step := 320.0
	var pos := -h
	while pos <= h + 1.0:
		for pt: Vector2 in [Vector2(pos, -h), Vector2(pos, h), Vector2(-h, pos), Vector2(h, pos)]:
			draw_rect(Rect2(pt - Vector2(14, 14), Vector2(28, 28)), Color("#2b3347"))
			draw_rect(Rect2(pt - Vector2(10, 10), Vector2(20, 20)), Color("#62718c"))
			draw_rect(Rect2(pt - Vector2(5, 5), Vector2(10, 10)), py_col)
		pos += step


func _regular_poly(sides: int, rad: float, start_ang: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		pts.append(Vector2.from_angle(start_ang + i * TAU / float(sides)) * rad)
	return pts
