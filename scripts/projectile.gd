class_name Projectile
extends Node2D
## 优化版统一投射物：移除每帧 queue_redraw()，改用平方距离检测，同时支持 PVP 角色与幸存者怪潮！

var game: Game
var shooter: Archer
var weapon_id := "bow"
var velocity := Vector2.ZERO
var speed := 620.0
var damage := 24.0
var pierce := 0
var bounce := 0
var wall_bounces := 0
var wall_pierce := false
var _passed_wall := false
var proj_scale := 1.0
var evolved := false
var visual_only := false
var is_mini_split := false
var homing := 0.0
var splash := 0.0
var life := 0.85
var max_dist := 450.0
var traveled := 0.0
var returning := false
var spin := 0.0
var color := Color.WHITE
var origin_pos := Vector2.ZERO
var hit_archers: Array[Archer] = []
var hit_monsters: Array[int] = []
var _basin_tex: Texture2D = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	origin_pos = position
	speed = velocity.length()
	rotation = velocity.angle()
	if weapon_id == "basin":
		_basin_tex = PixelSprites.get_weapon_texture("basin")
	if game != null:
		game.active_projectiles += 1


func _exit_tree() -> void:
	if game != null:
		game.active_projectiles = maxi(0, game.active_projectiles - 1)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	var src: Archer = shooter if (shooter != null and is_instance_valid(shooter)) else null
	if src == null:
		shooter = null

	# 柔追踪目标（PVP 追角色，幸存者追怪潮）
	if homing > 0.0:
		var target_pos := Vector2.INF
		if game.game_mode == "survivor" and game.swarm != null:
			target_pos = game.swarm.find_nearest_pos(position, 320.0, hit_monsters)
		else:
			var t := game.find_bounce_target(position, 290.0, hit_archers, src)
			if t != null:
				target_pos = t.position
		if target_pos != Vector2.INF:
			var want := (target_pos - position).normalized()
			var cur := velocity.normalized()
			var step := clampf(cur.angle_to(want), -homing * delta, homing * delta)
			velocity = cur.rotated(step) * speed

	# 云纹折扇回旋
	if weapon_id == "fan":
		spin += delta * 15.0
		if not returning:
			traveled += speed * delta
			if traveled >= max_dist:
				returning = true
				hit_archers.clear()
				hit_monsters.clear()
				life = maxf(life, 1.4)
		else:
			if src == null or not src.alive:
				queue_free()
				return
			var to_s := src.position - position
			var catch_r := src.radius + 20.0
			if to_s.length_squared() < catch_r * catch_r:
				src.on_fan_caught()
				queue_free()
				return
			velocity = to_s.normalized() * (speed * 1.24)
	elif weapon_id == "starblade":
		spin += delta * 19.0
	elif weapon_id == "basin":
		spin += delta * (13.0 if proj_scale > 1.3 else 17.5)

	var prev_pos := position
	position += velocity * delta
	rotation = spin if (weapon_id == "fan" or weapon_id == "starblade" or weapon_id == "basin") else velocity.angle()

	# 障碍物/墙壁/边界碰撞：「穿墙弹道」仅穿透区域内薄墙，区域分割厚墙与像素晶柱始终阻挡/反弹！
	var out_of_bounds := not game.in_arena(position)
	var hit_solid := out_of_bounds or ((not returning) and (game.point_in_rock(position, 0.0) or game.point_in_thick_wall(position, 0.0)))
	var hit_thin := (not returning) and game.point_in_thin_wall(position, 0.0)
	if hit_thin and wall_pierce:
		if not _passed_wall:
			_passed_wall = true
			damage *= 0.85
			if not visual_only:
				game.spawn_burst(position, Color(0.36, 0.95, 1.0), 16.0)
		hit_thin = false

	var hit_wall := hit_solid or hit_thin
	if hit_wall:
		if weapon_id == "fan" and not returning:
			returning = true
			hit_archers.clear()
			hit_monsters.clear()
			life = maxf(life, 1.2)
		elif wall_bounces > 0:
			wall_bounces -= 1
			var n := game.bounce_normal_at(position)
			if n == Vector2.ZERO:
				n = -velocity.normalized()
			position = prev_pos + n * 4.0
			velocity = velocity.bounce(n)
			hit_archers.clear()
			hit_monsters.clear()
			life = maxf(life, 0.72)
			if not visual_only:
				if splash > 0.0:
					_trigger_splash(null)
				if src != null and src.is_player:
					Sfx.play("basin_clang", 0.08, 60, -8.0)
					game.add_shake(2.4 * proj_scale)
		else:
			if not visual_only and splash > 0.0:
				_trigger_splash(null)
			queue_free()
			return

	var base_pad := 13.0 if weapon_id == "basin" else ((11.0 if evolved else 9.0) if (weapon_id == "fan" or weapon_id == "grimoire" or weapon_id == "halberd") else (8.0 if evolved else 6.0))
	var hit_pad := base_pad * proj_scale
	var travel_dir := velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.RIGHT

	# 联机客户端视觉投射物：撞到目标即刻消失并触发零延迟受击火花，避免子弹穿模丢失打击感！
	if visual_only:
		if weapon_id == "fan":
			return
		if game.game_mode == "survivor" and game.swarm != null:
			for m in game.swarm.monsters:
				var r := float(m["radius"]) + hit_pad
				if position.distance_squared_to(m["pos"]) <= r * r:
					game.spawn_hit_fx(position, travel_dir, color, false, false, src != null and src.is_player, true)
					queue_free()
					return
			return
		for a in game.archers:
			if a == src or not a.alive or a.downed or (src != null and src.is_ally(a)):
				continue
			var hr := a.radius + hit_pad
			if position.distance_squared_to(a.position) < hr * hr:
				game.spawn_hit_fx(position, travel_dir, color, false, a.shield > 0.5, src != null and src.is_player, true)
				queue_free()
				return
		return

	var base_kb := _weapon_kb() * proj_scale

	# --- 模式 1：幸存者怪潮命中 ---
	if game.game_mode == "survivor" and game.swarm != null:
		var crit_mult := 2.25 if (src != null and src.char_id == "grok") else 2.0
		var is_crit := src != null and randf() < src.crit_chance
		var dmg := damage * (crit_mult if is_crit else 1.0)
		if src != null and src.char_id == "deepseek":
			var dist := origin_pos.distance_to(position)
			if dist > 200.0:
				dmg *= (1.0 + clampf((dist - 200.0) / 340.0, 0.0, 1.0) * 0.30)
		var kb_vec := travel_dir * (base_kb * (1.35 if is_crit else 1.0))
		var mid := game.swarm.hit_at_point(position, hit_pad, dmg, is_crit, hit_monsters, src, kb_vec, color)
		if mid != -1:
			hit_monsters.append(mid)
			if weapon_id == "basin" and src != null and src.is_player:
				Sfx.play("basin_clang", 0.09, 65, -9.0)
				if proj_scale > 1.3:
					game.add_shake(4.0)
			# 超武「满血R1·终极铁盆」：命中瞬间分裂 3 只弹壁小铁盆连环 DUANG！
			if evolved and weapon_id == "basin" and not is_mini_split and src != null:
				is_mini_split = true
				for si in 3:
					var sdir := travel_dir.rotated((si - 1) * 0.95 + randf_range(-0.2, 0.2))
					game.spawn_mini_basin(src, position + sdir * 12.0, sdir)
			if splash > 0.0:
				game.spawn_burst(position, Color("#d8eeff") if weapon_id == "basin" else color, splash * 0.45)
				game.swarm.damage_in_radius(position, splash, damage * (0.60 if weapon_id == "basin" else 0.50), src, 0.0, 290.0 if weapon_id == "basin" else 220.0)
			if weapon_id == "fan":
				return
			if pierce > 0:
				pierce -= 1
				damage *= 0.88
			elif bounce > 0:
				bounce -= 1
				damage *= 0.86
				var np := game.swarm.find_nearest_pos(position, 440.0, hit_monsters)
				if np == Vector2.INF:
					queue_free()
					return
				velocity = (np - position).normalized() * speed
				life = maxf(life, 0.8)
			else:
				queue_free()
		return

	# --- 模式 2：PVP 角色、中央 Mid Boss 与东房间野生数据怪命中 ---
	var crit_m := 1.65 if (src != null and src.char_id == "grok") else 1.4
	if not game.mid_boss.is_empty():
		var is_mc := src != null and randf() < src.crit_chance
		var mdmg := damage * (crit_m if is_mc else 1.0)
		var mkb := travel_dir * (base_kb * (1.25 if is_mc else 1.0))
		if game.hit_mid_boss(position, hit_pad, mdmg, is_mc, hit_monsters, src, mkb, color):
			hit_monsters.append(-999)
			if weapon_id == "basin" and src == game.player:
				Sfx.play("basin_clang", 0.08, 65, -8.5)
			if splash > 0.0:
				_trigger_splash(null)
			if weapon_id == "fan":
				return
			if pierce > 0:
				pierce -= 1
				damage *= 0.82
			else:
				queue_free()
				return

	if not game.pvp_creeps.is_empty():
		var is_cc := src != null and randf() < src.crit_chance
		var cdmg := damage * (crit_m if is_cc else 1.0)
		var ckb := travel_dir * (base_kb * (1.25 if is_cc else 1.0))
		var cid := game.hit_pvp_creep(position, hit_pad, cdmg, is_cc, hit_monsters, src, ckb, color)
		if cid != -1:
			hit_monsters.append(cid)
			if weapon_id == "basin" and src == game.player:
				Sfx.play("basin_clang", 0.08, 65, -8.5)
			if splash > 0.0:
				_trigger_splash(null)
			if weapon_id == "fan":
				return
			if pierce > 0:
				pierce -= 1
				damage *= 0.80
			else:
				queue_free()
				return

	for a in game.archers:
		if a == src or not a.alive or a.downed or a in hit_archers or (src != null and src.is_ally(a)):
			continue
		var hr := a.radius + hit_pad
		if position.distance_squared_to(a.position) < hr * hr:
			var dmg := _compute_pvp_damage(a, src)
			var is_crit := false
			if src != null and randf() < src.crit_chance:
				dmg *= crit_m
				is_crit = true
			var kb_vec := travel_dir * (base_kb * (1.30 if is_crit else 1.0))
			a.take_damage(dmg, src, is_crit, kb_vec)
			hit_archers.append(a)
			if weapon_id == "basin" and (src == game.player or a == game.player):
				Sfx.play("basin_clang", 0.08, 65, -8.5)
			if splash > 0.0:
				_trigger_splash(a)
			if weapon_id == "fan":
				continue
			if pierce > 0:
				pierce -= 1
				damage *= 0.80
			elif bounce > 0:
				bounce -= 1
				damage *= 0.78
				var nt := game.find_bounce_target(position, 400.0, hit_archers, src)
				if nt == null:
					queue_free()
					return
				velocity = (nt.position - position).normalized() * speed
				life = maxf(life, 0.75)
			else:
				queue_free()
				return
			break


func _compute_pvp_damage(target: Archer, src: Archer) -> float:
	var dmg := damage
	if src != null and src.char_id == "deepseek":
		var dist := origin_pos.distance_to(target.position)
		if dist > 230.0:
			dmg *= (1.0 + clampf((dist - 230.0) / 360.0, 0.0, 1.0) * 0.24)
	return dmg


func _weapon_kb() -> float:
	match weapon_id:
		"basin": return 350.0
		"halberd": return 300.0
		"bow": return 230.0
		"grimoire": return 215.0
		"fan": return 200.0
		"starblade": return 155.0
		_: return 210.0


func _trigger_splash(direct_victim: Archer) -> void:
	var src: Archer = shooter if (shooter != null and is_instance_valid(shooter)) else null
	game.spawn_burst(position, color, splash * 0.42)
	if game.game_mode == "survivor" and game.swarm != null:
		game.swarm.damage_in_radius(position, splash, damage * 0.50, src, 0.0, 220.0)
		return
	game.damage_pvp_creeps_in_radius(position, splash, damage * 0.45, src, 180.0)
	game.damage_mid_boss_in_radius(position, splash, damage * 0.45, src, 180.0)
	for a in game.archers:
		if a == src or a == direct_victim or not a.alive or a.downed or (src != null and src.is_ally(a)):
			continue
		var sr := splash + a.radius
		if position.distance_squared_to(a.position) <= sr * sr:
			var push_d := (a.position - position).normalized()
			a.take_damage(damage * 0.40, src, false, push_d * 170.0)


func _draw() -> void:
	if wall_pierce:
		draw_arc(Vector2.ZERO, 13.0 * proj_scale, 0.0, TAU, 14, Color(0.32, 0.96, 1.0, 0.78), 2.2)
	if proj_scale >= 1.55:
		draw_circle(Vector2.ZERO, 15.0 * proj_scale, Color(1.0, 0.56, 0.22, 0.22))
		draw_arc(Vector2.ZERO, 14.5 * proj_scale, 0.0, TAU, 16, Color(1.0, 0.72, 0.26, 0.80), 2.4)
	if evolved:
		draw_circle(Vector2.ZERO, 17.0 * proj_scale, Color(1.0, 0.44, 0.80, 0.24))
		draw_arc(Vector2.ZERO, 15.5 * proj_scale, 0.0, TAU, 16, Color(1.0, 0.90, 0.42, 0.72), 2.0)
	if proj_scale != 1.0 and weapon_id != "basin":
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(proj_scale, proj_scale))
	match weapon_id:
		"basin":
			# 高速旋转的亮银精钢铁盆 + 金属气旋拖尾弧！
			var r_glow := 17.5 * proj_scale
			draw_circle(Vector2.ZERO, r_glow, Color(0.62, 0.88, 1.0, 0.24))
			draw_arc(Vector2.ZERO, r_glow * 0.96, 0.2, 2.3, 12, Color(0.90, 0.97, 1.0, 0.72), 2.8 * proj_scale)
			draw_arc(Vector2.ZERO, r_glow * 0.96, 3.3, 5.4, 12, Color(0.36, 0.74, 1.0, 0.65), 2.4 * proj_scale)
			if _basin_tex != null:
				var bw := 32.0 * proj_scale
				var bh := 25.0 * proj_scale
				draw_texture_rect(_basin_tex, Rect2(-bw * 0.5, -bh * 0.5, bw, bh), false)
		"grimoire":
			draw_circle(Vector2(-8, 0), 5.0, Color(color, 0.32))
			draw_circle(Vector2.ZERO, 10.0, Color(color, 0.34))
			draw_circle(Vector2.ZERO, 6.5, color)
			draw_line(Vector2(-6, 0), Vector2(6, 0), Color(1, 0.95, 0.78), 2.0)
			draw_line(Vector2(0, -6), Vector2(0, 6), Color(1, 0.95, 0.78), 2.0)
		"halberd":
			draw_arc(Vector2(-6, 0), 14.0, -1.05, 1.05, 12, Color(color, 0.38), 10.0)
			draw_arc(Vector2(-6, 0), 14.0, -1.0, 1.0, 12, Color("#1e1824"), 6.0)
			draw_arc(Vector2(-4, 0), 14.0, -0.95, 0.95, 12, color, 3.5)
			draw_arc(Vector2(-3, 0), 14.5, -0.75, 0.75, 10, Color("#ffd878"), 1.8)
		"fan":
			draw_circle(Vector2.ZERO, 13.0, Color(color, 0.25))
			draw_arc(Vector2.ZERO, 12.0, -1.25, 1.25, 12, Color("#f4f2ff"), 8.0)
			draw_arc(Vector2.ZERO, 12.0, -1.20, 1.20, 12, color, 3.5)
			draw_line(Vector2.ZERO, Vector2(12, 0), Color("#ffd878"), 2.0)
			draw_line(Vector2.ZERO, Vector2(8, -9), Color("#ffd878"), 1.6)
			draw_line(Vector2.ZERO, Vector2(8, 9), Color("#ffd878"), 1.6)
		"starblade":
			var pts := PackedVector2Array([
				Vector2(14, 0), Vector2(4, 4), Vector2(0, 14), Vector2(-4, 4),
				Vector2(-14, 0), Vector2(-4, -4), Vector2(0, -14), Vector2(4, -4),
			])
			draw_circle(Vector2.ZERO, 11.0, Color(color, 0.25))
			draw_colored_polygon(pts, color)
			var inner := PackedVector2Array([
				Vector2(8, 0), Vector2(2, 2), Vector2(0, 8), Vector2(-2, 2),
				Vector2(-8, 0), Vector2(-2, -2), Vector2(0, -8), Vector2(2, -2),
			])
			draw_colored_polygon(inner, Color("#ffe8f8"))
		_:
			draw_line(Vector2(-16, 0), Vector2(10, 0), Color(color, 0.45), 5.0)
			draw_line(Vector2(-14, 0), Vector2(10, 0), Color.WHITE, 2.5)
			draw_colored_polygon(PackedVector2Array([Vector2(18, 0), Vector2(8, -5), Vector2(8, 5)]), Color("#e6f6ff"))
			draw_colored_polygon(PackedVector2Array([Vector2(-10, 0), Vector2(-20, -6), Vector2(-15, 0)]), color)
			draw_colored_polygon(PackedVector2Array([Vector2(-10, 0), Vector2(-15, 0), Vector2(-20, 6)]), color)
	if proj_scale != 1.0 and weapon_id != "basin":
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
