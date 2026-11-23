class_name PickupManager
extends Node2D
## 高性能合批拾取物管理器：
## 管理全图「像素 Token 晶片（蓝/金/紫）」「回血粉心」「全图 Token 磁铁」「黄金 Token 宝箱」！

const MAX_ORBS := 180
const MAX_HEARTS := 18
const MAX_MAGNETS := 4
const MAX_CHESTS := 6

var game: Game
var orbs: Array[Dictionary] = []
var hearts: Array[Dictionary] = []
var magnets: Array[Dictionary] = []
var chests: Array[Dictionary] = []

var magnet_pull_timer := 0.0  # >0 时全图所有 Token 晶片高速吸向玩家！

var _orb_tex: Array[Texture2D] = []
var _heart_tex: Texture2D
var _magnet_tex: Texture2D
var _chest_tex: Texture2D
var _orb_cols: Array[Color] = [Color(0.32, 0.92, 1.0), Color(1.0, 0.84, 0.28), Color(0.85, 0.45, 1.0)]
var _t := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for tier in 3:
		_orb_tex.append(PixelSprites.get_orb_texture(tier))
	_heart_tex = PixelSprites.get_heart_texture()
	_magnet_tex = PixelSprites.get_magnet_texture()
	_chest_tex = PixelSprites.get_chest_texture()


func spawn_orb(pos: Vector2, value: int) -> void:
	if orbs.size() >= MAX_ORBS:
		var merge_idx := randi() % orbs.size()
		orbs[merge_idx]["value"] = int(orbs[merge_idx]["value"]) + value
		orbs[merge_idx]["tier"] = _tier_of(int(orbs[merge_idx]["value"]))
		return
	orbs.append({
		"pos": pos,
		"value": value,
		"tier": _tier_of(value),
		"phase": randf() * TAU,
	})


func spawn_heart(pos: Vector2) -> void:
	if hearts.size() >= MAX_HEARTS:
		return
	hearts.append({"pos": pos, "phase": randf() * TAU})


func spawn_magnet(pos: Vector2) -> void:
	if magnets.size() >= MAX_MAGNETS:
		return
	magnets.append({"pos": pos, "phase": randf() * TAU})


func spawn_chest(pos: Vector2, is_big := false) -> void:
	if chests.size() >= MAX_CHESTS:
		return
	chests.append({"pos": pos, "phase": randf() * TAU, "big": is_big})


func _tier_of(v: int) -> int:
	if v >= 15:
		return 2
	if v >= 10:
		return 1
	return 0


func find_nearest_orb_pos(p: Vector2, max_range: float) -> Vector2:
	var best := Vector2.INF
	var bd := max_range * max_range
	for o in orbs:
		var op: Vector2 = o["pos"]
		var d := p.distance_squared_to(op)
		if d < bd:
			bd = d
			best = op
	return best


func find_nearest_heart_pos(p: Vector2, max_range: float) -> Vector2:
	var best := Vector2.INF
	var bd := max_range * max_range
	for h in hearts:
		var hp: Vector2 = h["pos"]
		var d := p.distance_squared_to(hp)
		if d < bd:
			bd = d
			best = hp
	return best


func serialize_snapshot() -> Dictionary:
	var oa: Array = []
	for o in orbs:
		oa.append([o["pos"], int(o["tier"])])
	var ha: Array = []
	for h in hearts:
		ha.append(h["pos"])
	var ma: Array = []
	for mg in magnets:
		ma.append(mg["pos"])
	var ca: Array = []
	for ch in chests:
		ca.append([ch["pos"], bool(ch["big"])])
	return {"o": oa, "h": ha, "m": ma, "c": ca, "pull": magnet_pull_timer > 0.0}


func apply_net_snapshot(d: Dictionary) -> void:
	orbs.clear()
	for r in d.get("o", []):
		var row: Array = r
		orbs.append({"pos": row[0], "tier": int(row[1]), "value": 5, "phase": 0.0})
	hearts.clear()
	for hp_p in d.get("h", []):
		hearts.append({"pos": hp_p, "phase": 0.0})
	magnets.clear()
	for mp_p in d.get("m", []):
		magnets.append({"pos": mp_p, "phase": 0.0})
	chests.clear()
	for cr in d.get("c", []):
		var crow: Array = cr
		chests.append({"pos": crow[0], "big": bool(crow[1]), "phase": 0.0})
	magnet_pull_timer = 1.0 if bool(d.get("pull", false)) else 0.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	_t += delta
	if game.net_role == "client":
		queue_redraw()
		return
	var archers := game.archers
	var player := game.player
	var global_pull := magnet_pull_timer > 0.0 and player != null and player.alive
	if magnet_pull_timer > 0.0:
		magnet_pull_timer = maxf(0.0, magnet_pull_timer - delta)

	# 1. 更新像素 Token 晶片
	var i := orbs.size() - 1
	while i >= 0:
		var o := orbs[i]
		var op: Vector2 = o["pos"]
		if global_pull:
			var d2p := op.distance_squared_to(player.position)
			var pick_r := player.radius + 18.0
			if d2p < pick_r * pick_r:
				_collect_token(player, int(o["value"]))
				orbs[i] = orbs[orbs.size() - 1]
				orbs.pop_back()
			else:
				o["pos"] = op.move_toward(player.position, 1080.0 * delta)
			i -= 1
			continue

		for a in archers:
			if not a.alive:
				continue
			var pr := a.pickup_range
			var d2 := op.distance_squared_to(a.position)
			if d2 > pr * pr:
				continue
			var pick_r := a.radius + 13.0
			if d2 < pick_r * pick_r:
				_collect_token(a, int(o["value"]))
				orbs[i] = orbs[orbs.size() - 1]
				orbs.pop_back()
				break
			var d := sqrt(d2)
			o["pos"] = op.move_toward(a.position, (590.0 - d * 1.3) * delta)
			break
		i -= 1

	# 2. 更新粉色回血爱心
	var j := hearts.size() - 1
	while j >= 0:
		var h := hearts[j]
		var hp_pos: Vector2 = h["pos"]
		for a in archers:
			if not a.alive or a.hp >= a.max_hp - 1.0:
				continue
			var pr := a.pickup_range * 0.78
			var d2 := hp_pos.distance_squared_to(a.position)
			if d2 > pr * pr:
				continue
			var pick_r := a.radius + 14.0
			if d2 < pick_r * pick_r:
				var heal := 65.0 if game.game_mode == "pvp" else 95.0
				a.hp = minf(a.max_hp, a.hp + heal)
				game.spawn_text(a.position + Vector2(0, -a.radius - 18), "+%d HP" % int(heal), Color(0.42, 1.0, 0.56), 19)
				if a == player:
					Sfx.play("heart", 0.04, 80, -8.0)
				hearts[j] = hearts[hearts.size() - 1]
				hearts.pop_back()
				break
			h["pos"] = hp_pos.move_toward(a.position, 440.0 * delta)
			break
		j -= 1

	# 3. 更新全图 Token 磁铁 & 4. 黄金 Token 宝箱（所有人类玩家均可拾取，合作模式全队生效！）
	for hp_a in archers:
		if not hp_a.alive or hp_a.downed or not hp_a.is_human():
			continue
		var m := magnets.size() - 1
		while m >= 0:
			var mp: Vector2 = magnets[m]["pos"]
			var d2 := mp.distance_squared_to(hp_a.position)
			if d2 < (hp_a.radius + 22.0) * (hp_a.radius + 22.0):
				magnets[m] = magnets[magnets.size() - 1]
				magnets.pop_back()
				magnet_pull_timer = 3.2
				Sfx.play("magnet", 0.02, 100, -6.0)
				game.spawn_buff_aura(hp_a, Color(0.35, 0.92, 1.0))
				game.broadcast_banner("🧲 全图 Token 磁铁启动！算力狂吸！", Color(0.35, 0.94, 1.0))
			elif d2 < 140.0 * 140.0:
				magnets[m]["pos"] = mp.move_toward(hp_a.position, 360.0 * delta)
			m -= 1

		var c := chests.size() - 1
		while c >= 0:
			var cp: Vector2 = chests[c]["pos"]
			var big := bool(chests[c]["big"])
			if cp.distance_squared_to(hp_a.position) < (hp_a.radius + 26.0) * (hp_a.radius + 26.0):
				chests[c] = chests[chests.size() - 1]
				chests.pop_back()
				game.open_token_chest(big, hp_a)
			c -= 1

	queue_redraw()


func _collect_token(a: Archer, val: int) -> void:
	var eff_val := int(round(val * 1.25)) if a.room_buff == "vault" else val
	a.tokens += eff_val
	a.score += eff_val
	var xp_gain := float(eff_val) * (1.25 if a.char_id == "gpt" else 1.0)
	if a.is_human() and game.game_mode == "survivor":
		xp_gain *= MetaSave.xp_mult()
	a.gain_xp(xp_gain)
	# PVE 双人合作：队友共享 85% 经验，绝不出现抢经验掉队！
	if game.game_mode == "survivor" and game.is_coop and a.is_human():
		for ally in game.archers:
			if ally != a and ally.alive and ally.is_human() and a.is_ally(ally):
				ally.tokens += eff_val
				ally.score += eff_val
				ally.gain_xp(xp_gain * 0.85)
	if a == game.player:
		Sfx.play("orb", 0.03, 35, -13.0)


func _draw() -> void:
	var vr := game.visible_world_rect(72.0)
	var pulling := magnet_pull_timer > 0.0

	for o in orbs:
		var p: Vector2 = o["pos"]
		if not vr.has_point(p):
			continue
		var tier := int(o["tier"])
		var pulse := 1.0 + sin(_t * 4.8 + float(o["phase"])) * 0.12
		var sz := (20.0 + tier * 5.0) * pulse
		draw_circle(p, sz * (0.95 if pulling else 0.72), Color(_orb_cols[tier], 0.30 if pulling else 0.20))
		draw_texture_rect(_orb_tex[tier], Rect2(p.x - sz * 0.5, p.y - sz * 0.5, sz, sz), false)

	for h in hearts:
		var p: Vector2 = h["pos"]
		if not vr.has_point(p):
			continue
		var pulse := 1.0 + sin(_t * 4.8 + float(h["phase"])) * 0.14
		var sz := 26.0 * pulse
		draw_circle(p, sz * 0.68, Color(1.0, 0.34, 0.54, 0.22))
		draw_texture_rect(_heart_tex, Rect2(p.x - sz * 0.5, p.y - sz * 0.46, sz, sz * 0.92), false)

	# 全图 Token 磁铁（双层脉冲吸力光环）
	for mag in magnets:
		var p: Vector2 = mag["pos"]
		if not vr.has_point(p):
			continue
		var pulse := 1.0 + sin(_t * 6.0 + float(mag["phase"])) * 0.16
		draw_arc(p, 24.0 * pulse, 0.0, TAU, 24, Color(0.35, 0.92, 1.0, 0.8), 2.5)
		draw_circle(p, 19.0, Color(0.35, 0.85, 1.0, 0.22))
		var sz := 30.0 * (1.0 + sin(_t * 5.0) * 0.08)
		draw_texture_rect(_magnet_tex, Rect2(p.x - sz * 0.5, p.y - sz * 0.5, sz, sz), false)

	# 黄金 Token 宝箱（高耸金色光柱 + 旋转星环，绝不漏掉！）
	for ch in chests:
		var p: Vector2 = ch["pos"]
		if not vr.has_point(p):
			continue
		var pulse := 1.0 + sin(_t * 5.5 + float(ch["phase"])) * 0.14
		draw_rect(Rect2(p.x - 16.0, p.y - 120.0, 32.0, 120.0), Color(1.0, 0.84, 0.28, 0.14))
		draw_arc(p, 28.0 * pulse, _t * 2.5, _t * 2.5 + PI * 1.4, 24, Color(1.0, 0.88, 0.35, 0.9), 3.0)
		draw_circle(p, 22.0, Color(1.0, 0.82, 0.25, 0.25))
		var sz := 36.0 * (1.0 + sin(_t * 6.0) * 0.07)
		draw_texture_rect(_chest_tex, Rect2(p.x - sz * 0.5, p.y - sz * 0.5, sz, sz * 0.88), false)
