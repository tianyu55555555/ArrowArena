class_name SwarmManager
extends Node2D
## 高性能吸血鬼幸存者模式（「算力潮汐」）批量怪物引擎：
## - 5 种 AI 主题怪（乱码史莱姆、幻觉幽灵、垃圾邮件傀儡、Prompt 注入自爆炸弹、过拟合魔王）
## - 3 个突发阵型事件（0:48 合围圈、1:35 幽灵冲锋群、2:12 注入炸弹潮）
## - 精英必掉黄金 Token 宝箱、重装怪概率掉全图磁铁；空间哈希 O(N) + 单次合批绘制满帧 60-165 FPS！

const MAX_MONSTERS := 120
const CELL_SIZE := 64.0
const WAVE_NAMES := [
	"第 1 潮 · 乱码渗入",
	"第 2 潮 · 幻觉扩散",
	"第 3 潮 · 算力过载",
	"终极潮 · 过拟合魔王降临！",
]

var game: Game
var monsters: Array[Dictionary] = []
var enemy_bullets: Array[Dictionary] = []

var elapsed := 0.0
var wave_idx := 0
var spawn_accum := 0.0
var boss_spawned := [false, false, false, false]
var event_fired := [false, false, false]
var monster_kills := 0
var _next_id := 1
var _touch_cd := 0.0
var _magnet_timer := 32.0
var _endless_next_event := 40.0
var _endless_event_seq := 0
var _endless_next_boss := 50.0
var _endless_boss_tier := 0
var _diff: Dictionary = {}
var _tex: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_diff = Difficulties.get_data(game.difficulty_id)
	for k: String in ["glitch", "hallucination", "spam_tank", "prompt_bomb", "boss"]:
		_tex[k] = PixelSprites.get_monster_texture(k)


func wave_title() -> String:
	if bool(_diff.get("endless", false)):
		return "极限无尽 · 第 %d 轮风暴" % (int(elapsed / 45.0) + 1)
	return WAVE_NAMES[clampi(wave_idx, 0, WAVE_NAMES.size() - 1)]


func active_boss() -> Dictionary:
	for m in monsters:
		if bool(m["is_boss"]):
			return m
	return {}


func _alive_players() -> Array[Archer]:
	var out: Array[Archer] = []
	for a in game.archers:
		if a.alive and not a.downed and a.is_human():
			out.append(a)
	return out


func _nearest_player(from: Vector2) -> Archer:
	var best: Archer = null
	var bd := INF
	for a in game.archers:
		if not a.alive or a.downed or not a.is_human():
			continue
		var d2 := from.distance_squared_to(a.position)
		if d2 < bd:
			bd = d2
			best = a
	return best


func serialize_snapshot() -> Dictionary:
	var m_arr: Array = []
	for m in monsters:
		m_arr.append([
			int(m["id"]), str(m["kind"]), m["pos"],
			float(m["hp"]) / maxf(float(m["max_hp"]), 1.0),
			float(m["radius"]), bool(m["is_boss"]),
			float(m["flash"]) > 0.01, float(m["fuse"]),
		])
	var b_arr: Array = []
	for b in enemy_bullets:
		b_arr.append([b["pos"], b["col"]])
	return {"m": m_arr, "b": b_arr, "k": monster_kills, "w": wave_idx}


func apply_net_snapshot(sd: Dictionary) -> void:
	monster_kills = int(sd.get("k", monster_kills))
	wave_idx = int(sd.get("w", wave_idx))
	var m_arr: Array = sd.get("m", [])
	monsters.clear()
	for row in m_arr:
		var r: Array = row
		var hpr := float(r[3])
		monsters.append({
			"id": int(r[0]), "kind": str(r[1]), "pos": r[2],
			"hp": hpr * 100.0, "max_hp": 100.0, "radius": float(r[4]),
			"is_boss": bool(r[5]), "flash": 0.1 if bool(r[6]) else 0.0,
			"squash": 0.0, "slow": 0.0, "fuse": float(r[7]), "phase": float(int(r[0]) % 17),
		})
	var b_arr: Array = sd.get("b", [])
	enemy_bullets.clear()
	for brow in b_arr:
		var br: Array = brow
		enemy_bullets.append({"pos": br[0], "col": br[1]})
	queue_redraw()


func _physics_process(delta: float) -> void:
	if game.game_over:
		return
	elapsed += delta
	if game.net_role == "client":
		queue_redraw()
		return
	var ap := _alive_players()
	if ap.is_empty():
		return
	_touch_cd = maxf(_touch_cd - delta, 0.0)
	_magnet_timer -= delta
	if _magnet_timer <= 0.0:
		_magnet_timer = 44.0
		game.pickups.spawn_magnet(game.random_free_point(160.0, false))

	var is_endless := bool(_diff.get("endless", false))
	var dur := maxf(float(_diff.get("duration", 150.0)), 60.0)
	var rate_mult := float(_diff.get("rate_mult", 1.0))

	if is_endless:
		var new_w := int(elapsed / 45.0)
		if new_w != wave_idx:
			wave_idx = new_w
			game.hud.show_banner("⚡ 进入 %s！怪物强度再度飙升！" % wave_title(), Color(0.90, 0.45, 1.0))
			Sfx.play("boss_warn", 0.02, 400, -7.0)
		if elapsed >= _endless_next_event:
			_endless_next_event += 42.0
			var ev := _endless_event_seq % 3
			_endless_event_seq += 1
			if ev == 0: _event_encircle_ring()
			elif ev == 1: _event_phantom_stampede()
			else: _event_bomb_rush()
		if elapsed >= _endless_next_boss:
			_endless_next_boss += 55.0
			_endless_boss_tier += 1
			_spawn_boss(false, _endless_boss_tier)
	else:
		# 按当前难度总坚守时长动态分配 4 波次、3 突发事件与 4 次 Boss！
		var seg := dur * 0.25
		var new_wave := mini(3, int(elapsed / seg))
		if new_wave != wave_idx:
			wave_idx = new_wave
			game.hud.show_banner("进入 %s！" % wave_title(), Color(1.0, 0.72, 0.30))
			Sfx.play("boss_warn", 0.02, 400, -7.0)

		if not event_fired[0] and elapsed >= dur * 0.28:
			event_fired[0] = true
			_event_encircle_ring()
		if not event_fired[1] and elapsed >= dur * 0.55:
			event_fired[1] = true
			_event_phantom_stampede()
		if not event_fired[2] and elapsed >= dur * 0.76:
			event_fired[2] = true
			_event_bomb_rush()

		var boss_fracs := [0.22, 0.48, 0.72, 0.87]
		for bi in boss_fracs.size():
			if not boss_spawned[bi] and elapsed >= dur * float(boss_fracs[bi]):
				boss_spawned[bi] = true
				_spawn_boss(bi == 3, bi)

	var cap := 140 if is_endless else MAX_MONSTERS
	var rate := (1.9 + elapsed * 0.036) * rate_mult
	if is_endless:
		rate += (elapsed / 90.0) * 1.4
	spawn_accum += rate * delta
	while spawn_accum >= 1.0 and monsters.size() < cap:
		spawn_accum -= 1.0
		_spawn_wave_monster()

	_update_monsters(delta)
	_update_bullets(delta)
	queue_redraw()


# ================= 突发阵型事件 =================
func _event_encircle_ring() -> void:
	var p := game.player.position
	var count := 20
	for i in count:
		if monsters.size() >= MAX_MONSTERS:
			break
		var ang := i * TAU / float(count)
		var pos := (p + Vector2.from_angle(ang) * 410.0).clamp(
			Vector2(-Game.ARENA_HALF + 60, -Game.ARENA_HALF + 60),
			Vector2(Game.ARENA_HALF - 60, Game.ARENA_HALF - 60)
		)
		_add_monster("glitch", pos, 0.85)
	game.hud.show_banner("⚠ 突发事件：乱码合围圈！撕开缺口突围！", Color(0.42, 1.0, 0.56))
	Sfx.play("boss_warn", 0.04, 250, -7.0)


func _event_phantom_stampede() -> void:
	var p := game.player.position
	var side_dir := Vector2.from_angle(randf() * TAU)
	var perp := side_dir.orthogonal()
	for i in 14:
		if monsters.size() >= MAX_MONSTERS:
			break
		var off := side_dir * 520.0 + perp * ((i - 6.5) * 34.0)
		var pos := (p + off).clamp(
			Vector2(-Game.ARENA_HALF + 60, -Game.ARENA_HALF + 60),
			Vector2(Game.ARENA_HALF - 60, Game.ARENA_HALF - 60)
		)
		_add_monster("hallucination", pos, 1.0)
	game.hud.show_banner("⚠ 突发事件：幻觉幽灵高速冲锋群！", Color(0.84, 0.50, 1.0))
	Sfx.play("boss_warn", 0.06, 250, -7.0)


func _event_bomb_rush() -> void:
	var p := game.player.position
	for i in 8:
		if monsters.size() >= MAX_MONSTERS:
			break
		var ang := i * TAU / 8.0
		var pos := (p + Vector2.from_angle(ang) * 430.0).clamp(
			Vector2(-Game.ARENA_HALF + 60, -Game.ARENA_HALF + 60),
			Vector2(Game.ARENA_HALF - 60, Game.ARENA_HALF - 60)
		)
		_add_monster("prompt_bomb", pos, 1.0)
	game.hud.show_banner("⚠ 突发事件：Prompt 注入炸弹潮！引爆可连锁炸怪！", Color(1.0, 0.42, 0.35))
	Sfx.play("boss_warn", 0.03, 250, -7.0)


func _spawn_wave_monster() -> void:
	var p := game.player.position
	var ang := randf() * TAU
	var dist := randf_range(550.0, 740.0)
	var pos := (p + Vector2.from_angle(ang) * dist).clamp(
		Vector2(-Game.ARENA_HALF + 50, -Game.ARENA_HALF + 50),
		Vector2(Game.ARENA_HALF - 50, Game.ARENA_HALF - 50)
	)
	if game.point_in_rock(pos, 26.0):
		return

	var roll := randf()
	var kind := "glitch"
	if wave_idx >= 1 and roll < 0.14:
		kind = "prompt_bomb"
	elif wave_idx >= 2 and roll < 0.32:
		kind = "spam_tank"
	elif wave_idx >= 1 and roll < 0.58:
		kind = "hallucination"
	_add_monster(kind, pos, 1.0)


func _add_monster(kind: String, pos: Vector2, hp_mult: float) -> void:
	if not game.autotest:
		MetaSave.mark_monster_seen(kind)
	var d_hp := float(_diff.get("hp_mult", 1.0)) * (1.48 if game.is_coop else 1.0)
	var d_dmg := float(_diff.get("dmg_mult", 1.0))
	var is_endless := bool(_diff.get("endless", false))
	var time_scale := (1.0 + elapsed / 42.0 + pow(elapsed / 120.0, 1.75)) if is_endless else (1.0 + elapsed / 62.0)
	var scale_hp := time_scale * hp_mult * d_hp
	var hp := 34.0 * scale_hp
	var spd := (125.0 + elapsed * 0.22) * (1.08 if is_endless else 1.0)
	var rad := 18.0
	var dmg := 18.0 * d_dmg
	var xp := 6
	var resist := 1.0

	match kind:
		"hallucination":
			hp = 25.0 * scale_hp
			spd = (180.0 + elapsed * 0.26) * (1.08 if is_endless else 1.0)
			rad = 17.0
			dmg = 20.0 * d_dmg
			xp = 9
		"spam_tank":
			hp = 112.0 * scale_hp
			spd = 92.0 + elapsed * 0.14
			rad = 25.0
			dmg = 28.0 * d_dmg
			xp = 18
			resist = 0.50
		"prompt_bomb":
			hp = 30.0 * scale_hp
			spd = 152.0 + elapsed * 0.18
			rad = 19.0
			dmg = 34.0 * d_dmg
			xp = 12
			resist = 0.85

	monsters.append({
		"id": _next_id,
		"kind": kind,
		"pos": pos,
		"hp": hp,
		"max_hp": hp,
		"speed": spd,
		"radius": rad,
		"dmg": dmg,
		"xp": xp,
		"flash": 0.0,
		"squash": 0.0,
		"kb_vel": Vector2.ZERO,
		"kb_resist": resist,
		"slow": 0.0,
		"fuse": -1.0,  # prompt_bomb 引信倒计时（>=0 时闪红即将爆炸）
		"shoot_cd": 0.0,
		"is_boss": false,
		"is_final": false,
		"phase": randf() * TAU,
	})
	_next_id += 1


func _spawn_boss(is_final: bool, tier := 0) -> void:
	if not game.autotest:
		MetaSave.mark_monster_seen("boss")
	var d_hp := float(_diff.get("hp_mult", 1.0)) * (1.55 if game.is_coop else 1.0)
	var d_dmg := float(_diff.get("dmg_mult", 1.0))
	var is_endless := bool(_diff.get("endless", false))
	var p := game.player.position
	var pos := (p + Vector2.from_angle(randf() * TAU) * 540.0).clamp(
		Vector2(-Game.ARENA_HALF + 80, -Game.ARENA_HALF + 80),
		Vector2(Game.ARENA_HALF - 80, Game.ARENA_HALF - 80)
	)
	var base_hp := (2100.0 if is_final else (620.0 + elapsed * 7.5 + tier * 260.0))
	var hp := base_hp * d_hp * (1.0 + tier * 0.35 if is_endless else 1.0)
	monsters.append({
		"id": _next_id,
		"kind": "boss",
		"pos": pos,
		"hp": hp,
		"max_hp": hp,
		"speed": (118.0 if (is_final or is_endless) else 106.0),
		"radius": 44.0 if (is_final or (is_endless and tier >= 3)) else 35.0,
		"dmg": (40.0 if is_final else 30.0) * d_dmg,
		"xp": 95 if is_final else 50,
		"flash": 0.0,
		"squash": 0.0,
		"kb_vel": Vector2.ZERO,
		"kb_resist": 0.14,
		"slow": 0.0,
		"fuse": -1.0,
		"shoot_cd": 2.3,
		"is_boss": true,
		"is_final": is_final,
		"phase": 0.0,
	})
	_next_id += 1
	var msg := ("警告：终极「过拟合魔王」降临！" if is_final
		else ("极限无尽 · 过拟合魔王 Lv%d 降临！（必掉大宝箱）" % tier if is_endless
			else "精英「过拟合巨像」出现！（击杀必掉黄金 Token 宝箱）"))
	game.hud.show_banner(msg, Color(1.0, 0.35, 0.45))
	Sfx.play("boss_warn", 0.02, 200, -5.0)


func _detonate_bomb(pos: Vector2, dmg_to_player: float) -> void:
	game.spawn_burst(pos, Color(1.0, 0.36, 0.24), 108.0)
	Sfx.play("orbital", 0.12, 80, -10.0)
	game.add_shake(4.5)
	for p in _alive_players():
		var dp := pos.distance_to(p.position)
		if dp <= 112.0 + p.radius:
			var away := (p.position - pos).normalized() if dp > 0.01 else Vector2.RIGHT
			p.take_damage(dmg_to_player, null, false, away * 320.0)
	# 爆炸同时重创周围所有其他怪物，奖励玩家拉怪引爆连锁清屏！
	damage_in_radius(pos, 118.0, 75.0 + elapsed * 0.8, game.player, 0.0, 300.0)


func _update_monsters(delta: float) -> void:
	var alive_ps := _alive_players()
	if alive_ps.is_empty():
		return

	var grid: Dictionary = {}
	for i in monsters.size():
		var mp: Vector2 = monsters[i]["pos"]
		var key := Vector2i(int(floor(mp.x / CELL_SIZE)), int(floor(mp.y / CELL_SIZE)))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)

	var lim := Game.ARENA_HALF - 30.0
	var exploded_positions: Array[Dictionary] = []

	var i := monsters.size() - 1
	while i >= 0:
		var m := monsters[i]
		m["flash"] = maxf(float(m["flash"]) - delta, 0.0)
		m["squash"] = maxf(float(m["squash"]) - delta * 7.5, 0.0)
		m["slow"] = maxf(float(m["slow"]) - delta, 0.0)
		var kbv: Vector2 = m["kb_vel"]
		kbv = kbv.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
		if kbv.length_squared() < 4.0:
			kbv = Vector2.ZERO
		m["kb_vel"] = kbv

		var mp: Vector2 = m["pos"]
		var p: Archer = alive_ps[0]
		if alive_ps.size() > 1:
			var best_d2 := mp.distance_squared_to(p.position)
			for pi in range(1, alive_ps.size()):
				var d2p := mp.distance_squared_to(alive_ps[pi].position)
				if d2p < best_d2:
					best_d2 = d2p
					p = alive_ps[pi]
		var ppos := p.position
		var to_p := ppos - mp
		var dist := to_p.length()
		var dir := to_p / maxf(dist, 0.001)
		var spd := float(m["speed"]) * (0.52 if float(m["slow"]) > 0.0 else 1.0)

		# Prompt 注入自爆炸弹怪引信逻辑
		if m["kind"] == "prompt_bomb":
			var fuse := float(m["fuse"])
			if fuse < 0.0 and dist < 96.0:
				fuse = 0.72
				m["fuse"] = fuse
			if fuse >= 0.0:
				fuse -= delta
				m["fuse"] = fuse
				spd *= 0.25
				if fuse <= 0.0:
					exploded_positions.append({"pos": mp, "dmg": float(m["dmg"])})
					monsters[i] = monsters[monsters.size() - 1]
					monsters.pop_back()
					i -= 1
					continue

		if m["kind"] == "hallucination":
			dir = (dir + dir.orthogonal() * sin(elapsed * 4.5 + float(m["phase"])) * 0.45).normalized()

		var push := Vector2.ZERO
		var ck := Vector2i(int(floor(mp.x / CELL_SIZE)), int(floor(mp.y / CELL_SIZE)))
		var r := float(m["radius"])
		var cell_arr: Array = grid.get(ck, [])
		var checked := 0
		for oi_v in cell_arr:
			var oi := int(oi_v)
			if oi == i or oi >= monsters.size():
				continue
			var d := mp - (monsters[oi]["pos"] as Vector2)
			var md := r + float(monsters[oi]["radius"])
			var d2 := d.length_squared()
			if d2 < md * md and d2 > 0.01:
				push += d / sqrt(d2) * (md - sqrt(d2)) * 3.0
			checked += 1
			if checked >= 6:
				break

		mp += (dir * spd + push + kbv) * delta
		mp = mp.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		m["pos"] = mp

		var touch_r := r + p.radius - 4.0
		if m["kind"] != "prompt_bomb" and _touch_cd <= 0.0 and mp.distance_squared_to(ppos) < touch_r * touch_r:
			_touch_cd = 0.45
			var away_p := (ppos - mp).normalized() if dist > 0.01 else Vector2.RIGHT
			p.take_damage(float(m["dmg"]), null, false, away_p * 260.0)
			m["kb_vel"] = (kbv - away_p * (240.0 * float(m["kb_resist"]))).limit_length(460.0)

		if bool(m["is_boss"]):
			m["shoot_cd"] = float(m["shoot_cd"]) - delta
			if float(m["shoot_cd"]) <= 0.0 and dist < 680.0:
				m["shoot_cd"] = 2.6 if bool(m["is_final"]) else 3.4
				var cnt := 10 if bool(m["is_final"]) else 7
				var base := dir.angle()
				for bi in cnt:
					var bdir := Vector2.from_angle(base + bi * TAU / float(cnt))
					enemy_bullets.append({
						"pos": mp + bdir * r,
						"vel": bdir * 245.0,
						"dmg": 26.0,
						"life": 3.2,
						"col": Color("#ff5080") if bool(m["is_final"]) else Color("#c068ff"),
					})
		i -= 1

	for ex in exploded_positions:
		_detonate_bomb(ex["pos"], float(ex["dmg"]))


func _update_bullets(delta: float) -> void:
	var alive_ps := _alive_players()
	var i := enemy_bullets.size() - 1
	while i >= 0:
		var b := enemy_bullets[i]
		b["life"] = float(b["life"]) - delta
		var bp: Vector2 = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
		b["pos"] = bp
		var hit_any := false
		for p in alive_ps:
			var pr := p.radius + 7.0
			if bp.distance_squared_to(p.position) < pr * pr:
				var bdir := (b["vel"] as Vector2).normalized()
				p.take_damage(float(b["dmg"]), null, false, bdir * 240.0)
				hit_any = true
				break
		if hit_any or float(b["life"]) <= 0.0 or not game.in_arena(bp) or game.point_in_rock(bp, 0.0):
			enemy_bullets[i] = enemy_bullets[enemy_bullets.size() - 1]
			enemy_bullets.pop_back()
		i -= 1


# ================= 索敌与 AI 副武器支援接口 =================
func find_nearest_pos(from: Vector2, max_range: float, exclude_ids: Array[int] = []) -> Vector2:
	var best := Vector2.INF
	var bd := max_range * max_range
	for m in monsters:
		if exclude_ids.has(int(m["id"])):
			continue
		var mp: Vector2 = m["pos"]
		var d2 := from.distance_squared_to(mp)
		if d2 < bd:
			bd = d2
			best = mp
	return best


## 找视野内随机怪物点（用于天降轨道激光/陨星轰炸）
func pick_visible_target(from: Vector2, max_range: float) -> Vector2:
	var cands: Array[Vector2] = []
	var r2 := max_range * max_range
	for m in monsters:
		var mp: Vector2 = m["pos"]
		if from.distance_squared_to(mp) <= r2:
			cands.append(mp)
	if cands.is_empty():
		return Vector2.INF
	return cands.pick_random()


## 连锁星雷：从起点连续跳跃电击 count 只不同怪物
func trigger_chain_lightning(origin: Vector2, count: int, dmg: float, attacker: Archer) -> PackedVector2Array:
	var pts := PackedVector2Array([origin])
	var visited: Array[int] = []
	var cur := origin
	for _step in count:
		var best_idx := -1
		var bd := 360.0 * 360.0
		for i in monsters.size():
			var m := monsters[i]
			var mid := int(m["id"])
			if visited.has(mid):
				continue
			var d2 := cur.distance_squared_to(m["pos"])
			if d2 < bd:
				bd = d2
				best_idx = i
		if best_idx == -1:
			break
		var target_pos: Vector2 = monsters[best_idx]["pos"]
		visited.append(int(monsters[best_idx]["id"]))
		pts.append(target_pos)
		var dir := (target_pos - cur).normalized()
		_damage_index(best_idx, dmg, false, attacker, dir * 165.0, Color(0.75, 0.72, 1.0))
		cur = target_pos
	return pts


func hit_at_point(pos: Vector2, pad: float, dmg: float, is_crit: bool, exclude_ids: Array[int], attacker: Archer, kb_vec := Vector2.ZERO, fx_col := Color(1.0, 0.92, 0.55)) -> int:
	for i in monsters.size():
		var m := monsters[i]
		var mid := int(m["id"])
		if exclude_ids.has(mid):
			continue
		var r := float(m["radius"]) + pad
		if pos.distance_squared_to(m["pos"]) <= r * r:
			_damage_index(i, dmg, is_crit, attacker, kb_vec, fx_col)
			return mid
	return -1


func damage_in_radius(center: Vector2, radius: float, dmg: float, attacker: Archer, slow_dur := 0.0, kb_force := 190.0) -> void:
	var i := monsters.size() - 1
	while i >= 0:
		if i >= monsters.size():
			i -= 1
			continue
		var m := monsters[i]
		var r := radius + float(m["radius"])
		if center.distance_squared_to(m["pos"]) <= r * r:
			if slow_dur > 0.0:
				m["slow"] = maxf(float(m["slow"]), slow_dur)
			var away := ((m["pos"] as Vector2) - center).normalized()
			_damage_index(i, dmg, false, attacker, away * kb_force, Color(1.0, 0.82, 0.45))
		i -= 1


func damage_along_beam(start: Vector2, dir: Vector2, end_dist: float, width: float, dmg: float, attacker: Archer, knockback: bool) -> void:
	var i := monsters.size() - 1
	while i >= 0:
		if i >= monsters.size():
			i -= 1
			continue
		var m := monsters[i]
		var rel: Vector2 = (m["pos"] as Vector2) - start
		var proj := rel.dot(dir)
		if proj >= 0.0 and proj <= end_dist:
			var perp := (rel - dir * proj).length()
			if perp <= float(m["radius"]) + width * 0.9:
				var is_crit := randf() < attacker.crit_chance
				var d := dmg * (2.0 if is_crit else 1.0)
				_damage_index(i, d, is_crit, attacker, dir * (480.0 if knockback else 230.0), Color(0.42, 0.82, 1.0))
		i -= 1


func _damage_index(idx: int, dmg: float, is_crit: bool, attacker: Archer, kb: Vector2, fx_col := Color(1.0, 0.92, 0.55)) -> void:
	if idx < 0 or idx >= monsters.size():
		return
	var m := monsters[idx]
	m["hp"] = float(m["hp"]) - dmg
	m["flash"] = 0.12
	m["squash"] = 1.0
	if kb != Vector2.ZERO:
		var resist := float(m["kb_resist"])
		m["kb_vel"] = ((m["kb_vel"] as Vector2) + kb * resist).limit_length(500.0)

	var mp: Vector2 = m["pos"]
	var fx_dir := kb.normalized() if kb.length_squared() > 0.01 else Vector2.RIGHT
	game.spawn_hit_fx(mp - fx_dir * (float(m["radius"]) * 0.3), fx_dir, fx_col, is_crit, false)

	if attacker != null and attacker.lifesteal > 0.0:
		attacker.hp = minf(attacker.max_hp, attacker.hp + dmg * attacker.lifesteal)

	var col := Color(1.0, 0.52, 0.18) if is_crit else Color(1.0, 0.94, 0.55)
	game.spawn_text(mp + Vector2(randf_range(-10, 10), -float(m["radius"]) - 8),
		("%d!" % int(dmg)) if is_crit else str(int(dmg)), col, 21 if is_crit else 16)
	Sfx.play("crit" if is_crit else "hit", 0.08, 45, -13.0)
	if is_crit:
		game.add_shake(2.2)

	if float(m["hp"]) <= 0.0:
		_kill_index(idx, attacker)


func _kill_index(idx: int, killer: Archer) -> void:
	var m := monsters[idx]
	var mp: Vector2 = m["pos"]
	var kind: String = m["kind"]
	var xp := int(m["xp"])
	var is_boss := bool(m["is_boss"])
	var is_final := bool(m["is_final"])

	monsters[idx] = monsters[monsters.size() - 1]
	monsters.pop_back()

	monster_kills += 1
	if killer != null:
		killer.kills = monster_kills
		killer.score += xp * 2
		if killer.char_id == "grok" and (is_boss or monster_kills % 5 == 0):
			killer.active_cd = maxf(0.0, killer.active_cd - 2.5)

	# Prompt 注入炸弹被打爆时立刻炸伤周围其他怪物（不伤玩家，纯正爽感奖励！）
	if kind == "prompt_bomb":
		game.spawn_burst(mp, Color(1.0, 0.48, 0.22), 95.0)
		Sfx.play("kill", 0.08, 60, -8.0)
		damage_in_radius(mp, 110.0, 68.0 + elapsed * 0.7, killer, 0.0, 290.0)
		game.spawn_orb(mp, xp)
		return

	if is_boss:
		game.spawn_burst(mp, Color(1.0, 0.80, 0.30), 72.0)
		Sfx.play("kill", 0.05, 60, -6.0)
		for _i in (10 if is_final else 6):
			game.spawn_orb(mp + Vector2.from_angle(randf() * TAU) * randf_range(16, 70), 20)
		# PVE 回血血包仅由精英/魔王 Boss 击败后掉落（每次掉 2 枚珍贵血包！）
		game.spawn_heart(mp + Vector2(30, -14))
		game.spawn_heart(mp + Vector2(-30, 14))
		# 精英怪必掉黄金 Token 宝箱（无尽模式掉落超大三连宝箱 + 磁铁！）
		if not is_final:
			var is_endless := bool(_diff.get("endless", false))
			game.pickups.spawn_chest(mp, is_endless)
			if is_endless:
				game.pickups.spawn_magnet(mp + Vector2(-28, -24))
			game.hud.show_banner("🎁 精英已击败！掉落黄金 Token 宝箱与 2 枚回血血包！", Color(1.0, 0.88, 0.35))
		else:
			game.end_match("大胜利！检查点安全同步完成，过拟合魔王已清除！", true)
	else:
		game.spawn_orb(mp, xp)
		if kind == "spam_tank" and randf() < 0.14:
			game.pickups.spawn_magnet(mp)
		if randf() < 0.35:
			game.spawn_burst(mp, Color(0.55, 0.95, 0.75), 16.0)


# ================= 单次合批绘制 =================
func _draw() -> void:
	var vr := game.visible_world_rect(90.0)
	for m in monsters:
		var mp: Vector2 = m["pos"]
		if not vr.has_point(mp):
			continue
		var r := float(m["radius"])
		var sz := r * 2.55
		var bob := absf(sin(elapsed * 7.0 + float(m["phase"]))) * 4.0
		var sq := float(m["squash"])
		var sw := sz * (1.0 + sq * 0.28)
		var sh := sz * (1.0 - sq * 0.22)
		var fuse := float(m["fuse"])

		# Prompt 炸弹怪引信蓄力红圈预警！
		if fuse >= 0.0:
			var fk := 1.0 - clampf(fuse / 0.72, 0.0, 1.0)
			draw_circle(mp, 110.0 * (0.35 + fk * 0.65), Color(1.0, 0.22, 0.22, 0.20 + fk * 0.16))
			draw_arc(mp, 110.0, 0.0, TAU, 28, Color(1.0, 0.35, 0.28, 0.85), 2.5)

		var tint := Color.WHITE
		if float(m["flash"]) > 0.0 or (fuse >= 0.0 and int(elapsed * 20.0) % 2 == 0):
			tint = Color(2.2, 1.4, 1.4, 1.0)
		elif float(m["slow"]) > 0.0:
			tint = Color(0.65, 0.85, 1.0)

		draw_circle(mp + Vector2(0, r * 0.72), r * 0.75, Color(0, 0, 0, 0.25))
		var tex: Texture2D = _tex[m["kind"]]
		draw_texture_rect(tex, Rect2(mp.x - sw * 0.5, mp.y - sh * 0.55 - bob + sq * 3.0, sw, sh), false, tint)

		var hp := float(m["hp"])
		var mhp := float(m["max_hp"])
		if bool(m["is_boss"]) or (m["kind"] == "spam_tank" and hp < mhp):
			var w := r * 2.2
			var top := mp.y - sz * 0.58 - 8.0
			draw_rect(Rect2(mp.x - w * 0.5, top, w, 5.0), Color(0, 0, 0, 0.65))
			draw_rect(Rect2(mp.x - w * 0.5, top, w * clampf(hp / mhp, 0.0, 1.0), 5.0), Color("#ff4568"))

	for b in enemy_bullets:
		var bp: Vector2 = b["pos"]
		if not vr.has_point(bp):
			continue
		var col: Color = b["col"]
		draw_circle(bp, 10.0, Color(col, 0.32))
		draw_circle(bp, 6.0, col)
		draw_circle(bp, 2.5, Color.WHITE)
