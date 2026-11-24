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
const BOSS_ROTATION: Array[String] = ["cage_charger", "bullet_hell", "gravity_bomber"]
const BOSS_ARCHETYPES: Dictionary = {
	"cage_charger": {
		"name": "囚笼冲撞兽 · 算力壁垒",
		"short": "结界冲撞",
		"color": Color("#ff3d68"),
		"speed": 108.0,
		"radius": 38.0,
		"hp_mult": 1.08,
		"warn": "⚠ Boss「囚笼冲撞兽」降临！小心被结界框住躲避三连冲撞！",
	},
	"bullet_hell": {
		"name": "发散弹幕魔 · 梯度风暴",
		"short": "发散弹幕",
		"color": Color("#b85cff"),
		"speed": 100.0,
		"radius": 36.0,
		"hp_mult": 1.00,
		"warn": "⚠ Boss「发散弹幕魔」降临！小心高密度发散弹波与螺旋弹幕！",
	},
	"gravity_bomber": {
		"name": "坍缩重炮王 · 幻觉核心",
		"short": "重炮轰炸",
		"color": Color("#ff8a2b"),
		"speed": 96.0,
		"radius": 39.0,
		"hp_mult": 1.12,
		"warn": "⚠ Boss「坍缩重炮王」降临！小心封路延时红圈爆破！",
	},
	"overfit_king": {
		"name": "终极过拟合魔王",
		"short": "全能魔王",
		"color": Color("#ff2468"),
		"speed": 118.0,
		"radius": 46.0,
		"hp_mult": 1.35,
		"warn": "⚠ 终极「过拟合魔王」降临！结界冲撞 + 发散弹幕全技能压境！",
	},
}

var game: Game
var monsters: Array[Dictionary] = []
var enemy_bullets: Array[Dictionary] = []
var boss_cage: Dictionary = {}            # {"active": bool, "owner_id": int, "center": Vector2, "radius": float, "timer": float, "max_timer": float}
var charge_lanes: Array[Dictionary] = []  # 冲撞红区预警走廊
var bomb_zones: Array[Dictionary] = []    # 延时坍缩轰炸红圈

var elapsed := 0.0
var wave_idx := 0
var spawn_accum := 0.0
var boss_spawned := [false, false, false, false]
var event_fired := [false, false, false]
var monster_kills := 0
var _next_id := 1
var _touch_cd := 0.0
var _magnet_timer := 34.0
var _endless_next_event := 42.0
var _endless_event_seq := 0
var _endless_next_boss := 55.0
var _endless_boss_tier := 0
var _demo_boss_spawned := false
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


func clamp_to_boss_cage(a: Archer) -> void:
	if boss_cage.is_empty() or not bool(boss_cage.get("active", false)):
		return
	var c: Vector2 = boss_cage["center"]
	var max_r := float(boss_cage["radius"]) - a.radius - 4.0
	if max_r <= 24.0:
		return
	var off := a.position - c
	var d2 := off.length_squared()
	if d2 > max_r * max_r:
		a.position = c + (off / sqrt(d2)) * max_r


func _clear_boss_skills_for(owner_id: int) -> void:
	if not boss_cage.is_empty() and int(boss_cage.get("owner_id", -1)) == owner_id:
		var cc: Vector2 = boss_cage["center"]
		var cr := float(boss_cage["radius"])
		boss_cage = {}
		game.spawn_burst(cc, Color("#ff6890"), minf(cr * 0.45, 130.0))
	charge_lanes.assign(charge_lanes.filter(func(l: Dictionary) -> bool: return int(l.get("owner_id", -1)) != owner_id))


func serialize_snapshot() -> Dictionary:
	var m_arr: Array = []
	for m in monsters:
		m_arr.append([
			int(m["id"]), str(m["kind"]), m["pos"],
			float(m["hp"]) / maxf(float(m["max_hp"]), 1.0),
			float(m["radius"]), bool(m["is_boss"]),
			float(m["flash"]) > 0.01, float(m["fuse"]),
			str(m.get("boss_type", "")), str(m.get("boss_name", "")),
			m.get("boss_col", Color("#d93258")), str(m.get("charge_state", "")),
		])
	var b_arr: Array = []
	for b in enemy_bullets:
		b_arr.append([b["pos"], b["col"]])
	var cl_arr: Array = []
	for cl in charge_lanes:
		cl_arr.append([cl["start"], cl["dir"], float(cl["len"]), float(cl["width"]), float(cl["t"]), float(cl["max_t"]), cl["col"]])
	var bz_arr: Array = []
	for bz in bomb_zones:
		bz_arr.append([bz["pos"], float(bz["r"]), float(bz["t"]), float(bz["max_t"]), bz["col"]])
	var out := {"m": m_arr, "b": b_arr, "k": monster_kills, "w": wave_idx, "cl": cl_arr, "bz": bz_arr}
	if not boss_cage.is_empty() and bool(boss_cage.get("active", false)):
		out["cg"] = [boss_cage["center"], float(boss_cage["radius"]), float(boss_cage["timer"]), float(boss_cage["max_timer"])]
	return out


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
			"is_boss": bool(r[5]), "is_final": (r.size() > 8 and str(r[8]) == "overfit_king"),
			"flash": 0.1 if bool(r[6]) else 0.0,
			"squash": 0.0, "slow": 0.0, "fuse": float(r[7]), "phase": float(int(r[0]) % 17),
			"boss_type": str(r[8]) if r.size() > 8 else "",
			"boss_name": str(r[9]) if r.size() > 9 else "",
			"boss_col": r[10] if r.size() > 10 else Color("#d93258"),
			"charge_state": str(r[11]) if r.size() > 11 else "",
		})
	var b_arr: Array = sd.get("b", [])
	enemy_bullets.clear()
	for brow in b_arr:
		var br: Array = brow
		enemy_bullets.append({"pos": br[0], "col": br[1]})
	charge_lanes.clear()
	for crow in sd.get("cl", []):
		var cr: Array = crow
		charge_lanes.append({"start": cr[0], "dir": cr[1], "len": float(cr[2]), "width": float(cr[3]), "t": float(cr[4]), "max_t": float(cr[5]), "col": cr[6]})
	bomb_zones.clear()
	for zrow in sd.get("bz", []):
		var zr: Array = zrow
		bomb_zones.append({"pos": zr[0], "r": float(zr[1]), "t": float(zr[2]), "max_t": float(zr[3]), "col": zr[4]})
	if sd.has("cg"):
		var cg: Array = sd["cg"]
		boss_cage = {"active": true, "owner_id": -1, "center": cg[0], "radius": float(cg[1]), "timer": float(cg[2]), "max_timer": float(cg[3])}
	else:
		boss_cage = {}
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
			_endless_boss_tier += 1
			_endless_next_boss += maxf(50.0, 66.0 - float(_endless_boss_tier) * 1.8)
			_spawn_boss(_endless_boss_tier % 4 == 0, _endless_boss_tier)
	else:
		# 按当前难度总坚守时长动态分配 4 波次、3 突发事件与 4 次不同技能 Boss！
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

	# 演示验收钩子：开局立刻召唤指定机制 Boss 便于视觉与行为验收
	if game.demo_pve_boss != "" and not _demo_boss_spawned:
		_demo_boss_spawned = true
		_spawn_boss(game.demo_pve_boss == "overfit_king", 1, game.demo_pve_boss)

	var cap := 140 if is_endless else MAX_MONSTERS
	var rate := (2.05 + elapsed * 0.038) * rate_mult
	if is_endless:
		rate += (elapsed / 82.0) * 1.55
	spawn_accum += rate * delta
	while spawn_accum >= 1.0 and monsters.size() < cap:
		spawn_accum -= 1.0
		_spawn_wave_monster()

	_update_boss_hazards(delta)
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
	# 前 0~4.5 分钟血量曲线更紧迫，熬到约 5 分钟超武 + MoE 成型迎来爽感质变！
	var time_scale := (1.0 + elapsed / 35.0 + pow(elapsed / 92.0, 1.85)) if is_endless else (1.0 + elapsed / 48.0 + pow(elapsed / 120.0, 1.45))
	var scale_hp := time_scale * hp_mult * d_hp
	var hp := 52.0 * scale_hp
	var spd := (130.0 + elapsed * 0.24) * (1.10 if is_endless else 1.0)
	var rad := 18.0
	var dmg := 20.0 * d_dmg
	var xp := 5
	var resist := 1.0

	match kind:
		"hallucination":
			hp = 38.0 * scale_hp
			spd = (186.0 + elapsed * 0.28) * (1.10 if is_endless else 1.0)
			rad = 17.0
			dmg = 22.0 * d_dmg
			xp = 7
		"spam_tank":
			hp = 178.0 * scale_hp
			spd = 96.0 + elapsed * 0.16
			rad = 25.0
			dmg = 30.0 * d_dmg
			xp = 14
			resist = 0.45
		"prompt_bomb":
			hp = 46.0 * scale_hp
			spd = 156.0 + elapsed * 0.20
			rad = 19.0
			dmg = 36.0 * d_dmg
			xp = 9
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


func _spawn_boss(is_final: bool, tier := 0, force_type := "") -> void:
	if not game.autotest:
		MetaSave.mark_monster_seen("boss")
	var d_hp := float(_diff.get("hp_mult", 1.0)) * (1.55 if game.is_coop else 1.0)
	var d_dmg := float(_diff.get("dmg_mult", 1.0))
	var is_endless := bool(_diff.get("endless", false))
	var btype := force_type
	if btype == "" or not BOSS_ARCHETYPES.has(btype):
		btype = "overfit_king" if is_final else BOSS_ROTATION[maxi(0, tier - (1 if is_endless else 0)) % BOSS_ROTATION.size()]
	var bdef: Dictionary = BOSS_ARCHETYPES[btype]
	var p := game.player.position
	var pos: Vector2
	if force_type != "":
		pos = (p + Vector2(215.0, -45.0)).clamp(
			Vector2(-Game.ARENA_HALF + 100, -Game.ARENA_HALF + 100),
			Vector2(Game.ARENA_HALF - 100, Game.ARENA_HALF - 100)
		)
	else:
		pos = (p + Vector2.from_angle(randf() * TAU) * 520.0).clamp(
			Vector2(-Game.ARENA_HALF + 100, -Game.ARENA_HALF + 100),
			Vector2(Game.ARENA_HALF - 100, Game.ARENA_HALF - 100)
		)
	var base_hp := (3200.0 if is_final else (1050.0 + elapsed * 12.0 + tier * 420.0)) * float(bdef["hp_mult"])
	var hp := base_hp * d_hp * (1.0 + tier * 0.42 if is_endless else 1.0)
	var bname := str(bdef["name"])
	if is_endless and tier > 0 and force_type == "":
		bname = "%s Lv%d" % [bname, tier]
	var bcol: Color = bdef["color"]
	monsters.append({
		"id": _next_id,
		"kind": "boss",
		"pos": pos,
		"hp": hp,
		"max_hp": hp,
		"speed": float(bdef["speed"]) * (1.08 if is_endless else 1.0),
		"radius": float(bdef["radius"]) + (4.0 if (is_endless and tier >= 3) else 0.0),
		"dmg": (44.0 if is_final else 34.0) * d_dmg,
		"xp": 110 if is_final else 60,
		"flash": 0.0,
		"squash": 0.0,
		"kb_vel": Vector2.ZERO,
		"kb_resist": 0.12,
		"slow": 0.0,
		"fuse": -1.0,
		"shoot_cd": 1.8,
		"is_boss": true,
		"is_final": is_final,
		"phase": 0.0,
		"boss_type": btype,
		"boss_name": bname,
		"boss_col": bcol,
		"skill_cd": 0.25 if force_type != "" else 1.85,
		"skill_phase": 0,
		"charge_state": "",
		"charge_t": 0.0,
		"charge_dir": Vector2.RIGHT,
		"charges_left": 0,
		"burst_left": 0,
		"burst_t": 0.0,
		"burst_ang": 0.0,
		"burst_mode": "",
	})
	_next_id += 1
	var msg := str(bdef["warn"])
	if is_endless and tier > 0 and force_type == "":
		msg = "⚡ 无尽 Lv%d · %s" % [tier, msg]
	game.hud.show_banner(msg, bcol.lightened(0.18))
	Sfx.play("boss_warn", 0.02, 200, -5.0)


# ================= Boss 多技能机制（囚笼结界 / 区域冲撞 / 发散弹幕波 / 延时重炮） =================
func _start_boss_cage(m: Dictionary, target_pos: Vector2, rad := 335.0, dur := 8.5) -> void:
	var mp: Vector2 = m["pos"]
	var mid := mp.lerp(target_pos, 0.58)
	var lim := Game.ARENA_HALF - rad - 30.0
	mid = mid.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	boss_cage = {
		"active": true,
		"owner_id": int(m["id"]),
		"center": mid,
		"radius": rad,
		"timer": dur,
		"max_timer": dur,
	}
	# 把 Boss 和当前玩家都平滑收束进结界内，确保公平且立刻生效
	for a in _alive_players():
		clamp_to_boss_cage(a)
	var boff := mp - mid
	var bmax := rad - float(m["radius"]) - 8.0
	if boff.length_squared() > bmax * bmax:
		m["pos"] = mid + boff.normalized() * bmax
	game.hud.show_banner("⚠ 囚笼结界展开！无法逃离区域，准备躲避高速冲撞！", Color("#ff4c78"))
	Sfx.play("boss_warn", 0.02, 180, -5.0)
	game.add_shake(5.5)


func _begin_boss_charge(m: Dictionary, target_pos: Vector2) -> void:
	var mp: Vector2 = m["pos"]
	var d := target_pos - mp
	var cdir := d.normalized() if d.length_squared() > 1.0 else Vector2.RIGHT
	m["charge_state"] = "telegraph"
	m["charge_t"] = 0.88
	m["charge_dir"] = cdir
	var lane_len := 440.0
	if not boss_cage.is_empty() and bool(boss_cage.get("active", false)):
		lane_len = minf(float(boss_cage["radius"]) * 1.65, 520.0)
	var bcol: Color = m.get("boss_col", Color("#ff3d68"))
	charge_lanes.append({
		"owner_id": int(m["id"]),
		"start": mp,
		"dir": cdir,
		"len": lane_len,
		"width": float(m["radius"]) * 2.05,
		"t": 0.88,
		"max_t": 0.88,
		"col": bcol,
	})
	Sfx.play("boss_warn", 0.08, 120, -9.0)


func _fire_radial_wave(mp: Vector2, r: float, count: int, base_ang: float, spd: float, dmg: float, col: Color) -> void:
	for bi in count:
		var bdir := Vector2.from_angle(base_ang + float(bi) * TAU / float(count))
		enemy_bullets.append({
			"pos": mp + bdir * (r * 0.85),
			"vel": bdir * spd,
			"dmg": dmg,
			"life": 3.8,
			"col": col,
		})
	Sfx.play("shoot", 0.06, 70, -10.0)


func _spawn_bomb_zones(target_pos: Vector2, dmg: float, col: Color, count := 5) -> void:
	var lim := Game.ARENA_HALF - 90.0
	var pts: Array[Vector2] = [target_pos]
	var base_a := randf() * TAU
	for i in count - 1:
		var ang := base_a + float(i) * TAU / float(maxi(1, count - 1)) + randf_range(-0.22, 0.22)
		var dist := randf_range(135.0, 215.0)
		pts.append((target_pos + Vector2.from_angle(ang) * dist).clamp(Vector2(-lim, -lim), Vector2(lim, lim)))
	for pt in pts:
		bomb_zones.append({
			"pos": pt,
			"r": 78.0,
			"t": 1.12,
			"max_t": 1.12,
			"dmg": dmg,
			"col": col,
		})
	Sfx.play("boss_warn", 0.05, 160, -8.0)


func _update_boss_hazards(delta: float) -> void:
	# 1. 更新囚笼结界倒计时并持续约束玩家
	if not boss_cage.is_empty() and bool(boss_cage.get("active", false)):
		boss_cage["timer"] = float(boss_cage["timer"]) - delta
		for a in _alive_players():
			clamp_to_boss_cage(a)
		if float(boss_cage["timer"]) <= 0.0:
			var cc: Vector2 = boss_cage["center"]
			boss_cage = {}
			game.spawn_burst(cc, Color("#ff6890"), 90.0)

	# 2. 更新冲撞预警红区走廊
	var ci := charge_lanes.size() - 1
	while ci >= 0:
		charge_lanes[ci]["t"] = float(charge_lanes[ci]["t"]) - delta
		if float(charge_lanes[ci]["t"]) <= 0.0:
			charge_lanes.remove_at(ci)
		ci -= 1

	# 3. 更新延时重炮红圈并在引爆时造成伤害 + 震屏
	var alive_ps := _alive_players()
	var bi := bomb_zones.size() - 1
	while bi >= 0:
		var bz := bomb_zones[bi]
		bz["t"] = float(bz["t"]) - delta
		if float(bz["t"]) <= 0.0:
			var bp: Vector2 = bz["pos"]
			var br := float(bz["r"])
			var bdmg := float(bz["dmg"])
			var bcol: Color = bz["col"]
			bomb_zones.remove_at(bi)
			game.spawn_burst(bp, bcol, br * 1.15)
			Sfx.play("orbital", 0.10, 80, -8.5)
			game.add_shake(4.0)
			for p in alive_ps:
				var dp := bp.distance_to(p.position)
				if dp <= br + p.radius * 0.7:
					var away := (p.position - bp).normalized() if dp > 0.01 else Vector2.RIGHT
					p.take_damage(bdmg, null, false, away * 320.0)
		bi -= 1


func _update_boss_skills(m: Dictionary, p: Archer, dist: float, dir: Vector2, delta: float) -> void:
	var btype := str(m.get("boss_type", "bullet_hell"))
	var bcol: Color = m.get("boss_col", Color("#c068ff"))
	var mp: Vector2 = m["pos"]
	var r := float(m["radius"])
	var d_dmg := float(_diff.get("dmg_mult", 1.0))

	# 1. 处理连发弹幕波队列（发散双波 / 旋转螺旋弹幕）
	var bl := int(m.get("burst_left", 0))
	if bl > 0:
		m["burst_t"] = float(m["burst_t"]) - delta
		if float(m["burst_t"]) <= 0.0:
			var bmode := str(m.get("burst_mode", "radial"))
			var bang := float(m.get("burst_ang", 0.0))
			if bmode == "radial":
				var cnt := 18 if btype == "overfit_king" else 16
				_fire_radial_wave(mp, r, cnt, bang + PI / float(cnt), 225.0, 24.0 * d_dmg, bcol.lightened(0.22))
				m["burst_left"] = bl - 1
				m["burst_t"] = 0.36
			else:
				var scnt := 12 if btype == "overfit_king" else 10
				_fire_radial_wave(mp, r, scnt, bang, 250.0, 22.0 * d_dmg, bcol)
				m["burst_ang"] = bang + 0.25
				m["burst_left"] = bl - 1
				m["burst_t"] = 0.27

	# 2. 处理囚笼内高速三连冲撞状态机
	var cstate := str(m.get("charge_state", ""))
	if cstate != "":
		m["charge_t"] = float(m["charge_t"]) - delta
		if cstate == "telegraph" and float(m["charge_t"]) <= 0.0:
			m["charge_state"] = "dashing"
			m["charge_t"] = 0.56
			Sfx.play("dash", 0.05, 80, -6.0)
			game.spawn_burst(mp, bcol, r * 1.4)
		elif cstate == "dashing":
			if int(elapsed * 22.0) % 2 == 0 and randf() < 0.35:
				game.spawn_burst(mp, bcol, r * 0.65)
			if float(m["charge_t"]) <= 0.0:
				var left := int(m.get("charges_left", 0)) - 1
				m["charges_left"] = left
				if left > 0:
					m["charge_state"] = "recover"
					m["charge_t"] = 0.34
				else:
					m["charge_state"] = ""
					m["skill_cd"] = 3.2
		elif cstate == "recover" and float(m["charge_t"]) <= 0.0:
			_begin_boss_charge(m, p.position)
		return

	# 3. 冷却完毕触发 Boss 专属招牌技能！
	m["skill_cd"] = float(m.get("skill_cd", 2.0)) - delta
	if float(m["skill_cd"]) > 0.0 or dist > 860.0:
		return

	var sp := int(m.get("skill_phase", 0))
	m["skill_phase"] = sp + 1
	match btype:
		"cage_charger":
			# 框出不可离开的圆形结界，并在结界内发动 3 次高速预警冲撞！
			_start_boss_cage(m, p.position, 335.0, 8.6)
			m["charges_left"] = 3
			_begin_boss_charge(m, p.position)
		"bullet_hell":
			# 交替释放：16路发散双层渐变波 ↔ 3连10路旋转螺旋弹幕花！
			if sp % 2 == 0:
				var base := dir.angle()
				_fire_radial_wave(mp, r, 16, base, 255.0, 24.0 * d_dmg, bcol)
				m["burst_mode"] = "radial"
				m["burst_ang"] = base
				m["burst_left"] = 1
				m["burst_t"] = 0.36
				m["skill_cd"] = 2.05 if game.demo_pve_boss != "" else 2.65
			else:
				m["burst_mode"] = "spiral"
				m["burst_ang"] = dir.angle()
				m["burst_left"] = 3
				m["burst_t"] = 0.02
				m["skill_cd"] = 2.4 if game.demo_pve_boss != "" else 3.05
		"gravity_bomber":
			# 封路 5 连延时红圈轰炸 + 8 路发散扇形重炮弹！
			_spawn_bomb_zones(p.position, 34.0 * d_dmg, bcol, 5)
			var base := dir.angle()
			for bi in 8:
				var spread := (float(bi) - 3.5) * 0.16
				var bdir := Vector2.from_angle(base + spread)
				enemy_bullets.append({
					"pos": mp + bdir * (r * 0.85),
					"vel": bdir * 235.0,
					"dmg": 24.0 * d_dmg,
					"life": 3.4,
					"col": bcol.lightened(0.18),
				})
			m["skill_cd"] = 2.20 if game.demo_pve_boss != "" else 2.95
		_:
			# 终极过拟合魔王：结界双冲撞 → 18路双层发散弹幕 + 4连红圈轰炸！
			if sp % 2 == 0:
				_start_boss_cage(m, p.position, 355.0, 7.6)
				m["charges_left"] = 2
				_begin_boss_charge(m, p.position)
			else:
				var base := dir.angle()
				_fire_radial_wave(mp, r, 18, base, 260.0, 26.0 * d_dmg, bcol)
				m["burst_mode"] = "radial"
				m["burst_ang"] = base
				m["burst_left"] = 1
				m["burst_t"] = 0.34
				_spawn_bomb_zones(p.position, 36.0 * d_dmg, Color("#ff6b4a"), 4)
				m["skill_cd"] = 3.25


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

		var move_vec := dir * spd + push + kbv
		if bool(m["is_boss"]):
			var cs := str(m.get("charge_state", ""))
			var bt := str(m.get("boss_type", ""))
			if cs == "telegraph":
				move_vec = push * 0.15
			elif cs == "dashing":
				var cdir: Vector2 = m.get("charge_dir", dir)
				move_vec = cdir * 660.0
			elif cs == "recover":
				move_vec = dir * (spd * 0.25)
			elif (bt == "bullet_hell" or bt == "gravity_bomber") and dist < 240.0:
				# 弹幕魔与重炮王保持中距离环绕游走压迫，而非贴脸重叠
				var strafe := dir.orthogonal() * (1.0 if int(m["id"]) % 2 == 0 else -1.0)
				var radial := -dir * 0.55 if dist < 175.0 else Vector2.ZERO
				move_vec = (strafe * 0.85 + radial).normalized() * spd + push + kbv

		mp += move_vec * delta
		mp = mp.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		# 拥有囚笼结界的 Boss 同样被约束在结界内冲撞，绝不会冲出屏幕外！
		if bool(m["is_boss"]) and not boss_cage.is_empty() and bool(boss_cage.get("active", false)) and int(boss_cage.get("owner_id", -1)) == int(m["id"]):
			var cc: Vector2 = boss_cage["center"]
			var bmax_r := float(boss_cage["radius"]) - r - 6.0
			var boff := mp - cc
			if boff.length_squared() > bmax_r * bmax_r:
				mp = cc + boff.normalized() * bmax_r
		m["pos"] = mp

		var touch_r := r + p.radius - 4.0
		if m["kind"] != "prompt_bomb" and _touch_cd <= 0.0 and mp.distance_squared_to(ppos) < touch_r * touch_r:
			var dashing := bool(m["is_boss"]) and str(m.get("charge_state", "")) == "dashing"
			_touch_cd = 0.45
			var away_p := (ppos - mp).normalized() if dist > 0.01 else Vector2.RIGHT
			var hit_dmg := float(m["dmg"]) * (1.45 if dashing else 1.0)
			p.take_damage(hit_dmg, null, false, away_p * (380.0 if dashing else 260.0))
			if dashing:
				game.add_shake(5.5)
			m["kb_vel"] = (kbv - away_p * (240.0 * float(m["kb_resist"]))).limit_length(460.0)

		if bool(m["is_boss"]):
			_update_boss_skills(m, p, dist, dir, delta)
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
		_clear_boss_skills_for(int(m["id"]))
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
	var vr := game.visible_world_rect(120.0)
	var font := PixelSprites.ui_font()

	# 1. 绘制 Boss 囚笼结界（猩红力场环 + 旋转能量栅栏 + 8 座结界柱 + 顶部封锁警告）
	if not boss_cage.is_empty() and bool(boss_cage.get("active", false)):
		var cc: Vector2 = boss_cage["center"]
		var cr := float(boss_cage["radius"])
		var ct := float(boss_cage["timer"])
		var pulse := 0.55 + 0.45 * sin(elapsed * 9.0)
		draw_circle(cc, cr, Color(0.95, 0.14, 0.32, 0.06))
		draw_arc(cc, cr + 10.0, 0.0, TAU, 56, Color(1.0, 0.18, 0.38, 0.25 + pulse * 0.20), 14.0)
		draw_arc(cc, cr, 0.0, TAU, 56, Color(1.0, 0.30, 0.48, 0.94), 5.5)
		draw_arc(cc, cr - 8.0, 0.0, TAU, 48, Color(1.0, 0.78, 0.84, 0.50), 2.0)
		for si in 16:
			var sa := elapsed * 1.1 + float(si) * TAU / 16.0
			draw_arc(cc, cr - 3.0, sa, sa + 0.20, 6, Color(1.0, 0.92, 0.55, 0.85), 3.0)
		for pi in 8:
			var pa := float(pi) * TAU / 8.0 + elapsed * 0.35
			var pp := cc + Vector2.from_angle(pa) * cr
			draw_circle(pp, 10.0, Color("#ff2e58"))
			draw_circle(pp, 5.0, Color("#fff2b2"))
		var warn_s := "⚠ 囚笼结界封锁中！不可离开区域 (%.1fs) ⚠" % maxf(ct, 0.0)
		var label_pos := cc + Vector2(-190.0, cr - 18.0)
		draw_string_outline(font, label_pos, warn_s, HORIZONTAL_ALIGNMENT_CENTER, 380.0, 15, 5, Color(0, 0, 0, 0.92))
		draw_string(font, label_pos, warn_s, HORIZONTAL_ALIGNMENT_CENTER, 380.0, 15, Color("#ff9cb2"))

	# 2. 绘制 Boss 高速冲撞预警走廊（渐变充能红道 + 前进箭头）
	for cl in charge_lanes:
		var st: Vector2 = cl["start"]
		var cdir: Vector2 = cl["dir"]
		var clen := float(cl["len"])
		var cw := float(cl["width"])
		var prog := 1.0 - clampf(float(cl["t"]) / maxf(float(cl["max_t"]), 0.01), 0.0, 1.0)
		var ccol: Color = cl["col"]
		draw_set_transform(st, cdir.angle(), Vector2.ONE)
		draw_rect(Rect2(0.0, -cw * 0.5, clen, cw), Color(ccol.r, ccol.g, ccol.b, 0.16 + prog * 0.16))
		draw_rect(Rect2(0.0, -cw * 0.5, clen * prog, cw), Color(ccol.r, ccol.g, ccol.b, 0.30 + prog * 0.24))
		draw_line(Vector2(0.0, -cw * 0.5), Vector2(clen, -cw * 0.5), Color(1.0, 0.55, 0.65, 0.95), 3.0)
		draw_line(Vector2(0.0, cw * 0.5), Vector2(clen, cw * 0.5), Color(1.0, 0.55, 0.65, 0.95), 3.0)
		var chev_x := 42.0
		while chev_x < clen - 28.0:
			var cx := chev_x + fmod(elapsed * 220.0, 56.0) * 0.5
			if cx < clen - 18.0:
				var pts := PackedVector2Array([Vector2(cx - 12.0, -cw * 0.28), Vector2(cx + 8.0, 0.0), Vector2(cx - 12.0, cw * 0.28)])
				draw_polyline(pts, Color(1.0, 0.94, 0.72, 0.90), 3.2)
			chev_x += 64.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3. 绘制延时重炮轰炸红圈（外警戒环 + 充能扩散内核）
	for bz in bomb_zones:
		var bp: Vector2 = bz["pos"]
		if not vr.has_point(bp):
			continue
		var br := float(bz["r"])
		var prog := 1.0 - clampf(float(bz["t"]) / maxf(float(bz["max_t"]), 0.01), 0.0, 1.0)
		var bcol: Color = bz["col"]
		draw_circle(bp, br, Color(bcol.r, bcol.g, bcol.b, 0.14))
		draw_circle(bp, br * prog, Color(bcol.r, bcol.g, bcol.b, 0.28 + prog * 0.22))
		draw_arc(bp, br, 0.0, TAU, 32, Color(bcol.r, bcol.g, bcol.b, 0.95), 3.2)
		draw_line(bp + Vector2(-12, 0), bp + Vector2(12, 0), Color(1.0, 0.95, 0.7, 0.9), 2.0)
		draw_line(bp + Vector2(0, -12), bp + Vector2(0, 12), Color(1.0, 0.95, 0.7, 0.9), 2.0)

	# 4. 绘制怪潮与不同机制 Boss
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
		var is_b := bool(m["is_boss"])

		# Prompt 炸弹怪引信蓄力红圈预警！
		if fuse >= 0.0:
			var fk := 1.0 - clampf(fuse / 0.72, 0.0, 1.0)
			draw_circle(mp, 110.0 * (0.35 + fk * 0.65), Color(1.0, 0.22, 0.22, 0.20 + fk * 0.16))
			draw_arc(mp, 110.0, 0.0, TAU, 28, Color(1.0, 0.35, 0.28, 0.85), 2.5)

		# Boss 专属机制色光环（冲撞态额外燃起猩红烈焰圈！）
		var bcol: Color = m.get("boss_col", Color("#ff4568")) if is_b else Color("#ff4568")
		if is_b:
			var cs := str(m.get("charge_state", ""))
			draw_circle(mp, r * (1.42 if cs == "dashing" else 1.22), Color(bcol.r, bcol.g, bcol.b, 0.34 if cs == "dashing" else 0.18))
			draw_arc(mp, r * 1.32, elapsed * 2.2, elapsed * 2.2 + TAU * 0.75, 24, bcol.lightened(0.18), 3.2)

		var tint := Color.WHITE
		if float(m["flash"]) > 0.0 or (fuse >= 0.0 and int(elapsed * 20.0) % 2 == 0):
			tint = Color(2.2, 1.4, 1.4, 1.0)
		elif is_b and str(m.get("charge_state", "")) == "dashing":
			tint = Color(1.5, 0.85, 0.92, 1.0)
		elif float(m["slow"]) > 0.0:
			tint = Color(0.65, 0.85, 1.0)
		elif is_b:
			tint = Color.WHITE.lerp(bcol.lightened(0.35), 0.30)

		draw_circle(mp + Vector2(0, r * 0.72), r * 0.75, Color(0, 0, 0, 0.25))
		var tex: Texture2D = _tex[m["kind"]]
		draw_texture_rect(tex, Rect2(mp.x - sw * 0.5, mp.y - sh * 0.55 - bob + sq * 3.0, sw, sh), false, tint)

		var hp := float(m["hp"])
		var mhp := float(m["max_hp"])
		if is_b or (m["kind"] == "spam_tank" and hp < mhp):
			var w := r * 2.4
			var top := mp.y - sz * 0.58 - 8.0
			draw_rect(Rect2(mp.x - w * 0.5, top, w, 6.0 if is_b else 5.0), Color(0, 0, 0, 0.72))
			draw_rect(Rect2(mp.x - w * 0.5, top, w * clampf(hp / mhp, 0.0, 1.0), 6.0 if is_b else 5.0), bcol)
			if is_b:
				var bn := str(m.get("boss_name", "过拟合魔王"))
				draw_string_outline(font, Vector2(mp.x - 130.0, top - 6.0), bn, HORIZONTAL_ALIGNMENT_CENTER, 260.0, 13, 4, Color(0, 0, 0, 0.9))
				draw_string(font, Vector2(mp.x - 130.0, top - 6.0), bn, HORIZONTAL_ALIGNMENT_CENTER, 260.0, 13, bcol.lightened(0.28))

	for b in enemy_bullets:
		var bp: Vector2 = b["pos"]
		if not vr.has_point(bp):
			continue
		var col: Color = b["col"]
		draw_circle(bp, 11.5, Color(col.r, col.g, col.b, 0.34))
		draw_circle(bp, 6.8, col)
		draw_circle(bp, 2.8, Color.WHITE)
