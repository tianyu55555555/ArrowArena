class_name Game
extends Node2D
## 战场主控：
## - 单人/联机双模式：PVP 五宫格决斗场（自由乱斗 / 2v2v2v2 组队，可选 AI 人机）+ PVE 算力潮汐（单人四档难度 / 局域网双人无尽合作）
## - 完整局域网房主权威同步 + 客户端平滑插值镜像 + 6 把主武器超武进化 + 6 位 AI 支援副武

signal request_rematch
signal request_lobby

const ARENA_HALF := 1600.0
const BOT_COUNT := 7
const MATCH_TIME := 390.0  # 6分30秒：容纳中央 Mid Boss 首次 1:30 降临 + 每 3 分钟刷新争夺
const RUNE_DURATION := 15.0
const RUNE_RESPAWN := 60.0
const MID_BOSS_FIRST_DELAY := 90.0
const MID_BOSS_RESPAWN := 180.0
const STORM_START_TIME := 60.0
const STORM_MAX_R := 2150.0
const STORM_MIN_R := 440.0
const ORB_TARGET := 125
const HEART_TARGET := 14
const MAX_TEXT_FX := 28
const MAX_HIT_FX := 24

var game_mode := "pvp"         # "pvp" | "survivor"
var pvp_variant := "ffa"       # "ffa" | "2v2v2v2"
var fill_bots := true
var is_coop := false
var difficulty_id := "normal"  # "normal" | "hard" | "nightmare" | "endless"
var is_endless := false
var net_role := "offline"      # "offline" | "host" | "client"
var map_seed := 0
var lan_roster: Dictionary = {}

var survived_sec := 0.0
var player_char_id := "claude"
var player_weapon_id := "grimoire"
var autotest := false
var override_time := -1.0
var shot_path := ""
var demo_levelup := false
var demo_pick := false
var demo_pause := false
var demo_midboss := false
var demo_blessing := false
var demo_storm := false
var demo_spawn_pos := Vector2.INF
var demo_skill_capture := -1.0
var _demo_skill_fired := false

var archers: Array[Archer] = []
var rocks: Array[Vector3] = []
var rock_kinds: Array[String] = []
var walls: Array[Rect2] = []
var special_rooms: Array[Dictionary] = []
var pvp_traps: Array[Dictionary] = []   # 西房间移动锯刃陷阱
var pvp_creeps: Array[Dictionary] = []  # 东房间野生数据怪（击杀爆 Token + 血药！）
var pvp_runes: Array[Dictionary] = []   # 四角增益符文祭坛（6 种随机，持续 15s，60s 刷新）
var mid_boss: Dictionary = {}           # 中央决斗场 Mid Boss（每 3 分钟刷新，击杀 30s 全6增益 + 1次复活）
var mid_boss_bullets: Array[Dictionary] = []
var mid_boss_cd := MID_BOSS_FIRST_DELAY
var mid_boss_warned := false
var storm_active := false
var storm_radius := STORM_MAX_R
var _emote_cycle := 0
var _creep_seq := 1
var _creep_respawn_t := 0.0
var team_scores: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}

var player: Archer
var camera: Camera2D
var hud: Hud
var pickups: PickupManager
var swarm: SwarmManager = null
var proj_layer: Node2D
var archer_layer: Node2D
var fx_layer: Node2D

var time_left := MATCH_TIME
var game_over := false
var pending_picks := 0
var rerolls_left := 3
var active_projectiles := 0
var _text_fx_count := 0
var _hit_fx_count := 0
var _shake := 0.0

var _shot_timer := 0.0
var _shot_done := false
var _demo_picked := false
var _bot_seq := 0
var _next_bot_nid := -1
var _net_snap_t := 0.0
var _net_pickup_t := 0.0
var _net_input_t := 0.0
var _local_active_seq := 0
var _last_client_choices: Array[String] = []
var _host_pending_choices: Dictionary = {}  # peer_id -> Array[String]


func _ready() -> void:
	if map_seed != 0:
		seed(map_seed)
	else:
		randomize()
	MetaSave.ensure_loaded()
	Sfx.ensure(get_tree().root)
	Sfx.play_bgm("battle")
	rerolls_left = 3 + (MetaSave.extra_rerolls() if game_mode == "survivor" else 0)

	if is_coop:
		game_mode = "survivor"
		difficulty_id = "endless"
	if game_mode == "survivor":
		var dd := Difficulties.get_data(difficulty_id)
		is_endless = bool(dd["endless"])
		time_left = float(dd["duration"])
	if override_time > 0.0:
		time_left = override_time

	_setup_input()
	if game_mode == "pvp":
		_gen_pvp_5grid()
	else:
		_gen_rocks()

	var arena := Arena.new()
	arena.game = self
	add_child(arena)

	pickups = PickupManager.new()
	pickups.game = self
	add_child(pickups)

	if game_mode == "survivor":
		swarm = SwarmManager.new()
		swarm.game = self
		add_child(swarm)

	proj_layer = _layer()
	archer_layer = _layer()
	fx_layer = _layer()

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)
	camera.make_current()

	_spawn_initial_roster()

	if net_role != "client":
		_spawn_initial_pickups()

	if player != null:
		if demo_spawn_pos != Vector2.INF:
			player.position = demo_spawn_pos
		if demo_blessing:
			player.apply_mid_boss_blessing()
		if demo_storm and game_mode == "pvp":
			storm_active = true
			storm_radius = 620.0
			time_left = minf(time_left, 18.0)
			send_local_emote(0)
			for a in archers:
				if a != player:
					var ems := Archer.get_emotes_for(a.char_id)
					if not ems.is_empty():
						a.show_emote(str(ems[0]["text"]))
		camera.position = player.position
		camera.reset_smoothing()

	hud = Hud.new()
	hud.game = self
	add_child(hud)

	if net_role == "client" and NetManager.inst != null:
		_connect_client_signals()

	if game_mode == "survivor":
		var dd := Difficulties.get_data(difficulty_id)
		var tag := "【双人无尽合作 · 怪血强化】携手死守公益 AI 灯塔！" if is_coop else "【%s · %s】坚守同步开始！" % [dd["name"], dd["mission_title"]]
		hud.show_banner(tag, dd["color"])
	elif pvp_variant == "2v2v2v2":
		hud.show_banner("⚔ 五宫格 2v2v2v2！四角随机 6 种神符 · 中央 Mid Boss 赐 30s 全增益 + 复活！", Color(1.0, 0.84, 0.36))
	else:
		hud.show_banner("⚔ 五宫格决斗场！四角随机 6 种神符 · 中央 Mid Boss 赐 30s 全增益 + 复活！", Color(0.45, 0.90, 1.0))


func _exit_tree() -> void:
	if NetManager.inst != null and net_role == "client":
		if NetManager.inst.snapshot_received.is_connected(_on_net_snapshot):
			NetManager.inst.snapshot_received.disconnect(_on_net_snapshot)
		if NetManager.inst.pickups_received.is_connected(_on_net_pickups):
			NetManager.inst.pickups_received.disconnect(_on_net_pickups)
		if NetManager.inst.fx_received.is_connected(_on_net_fx):
			NetManager.inst.fx_received.disconnect(_on_net_fx)
		if NetManager.inst.proj_received.is_connected(_on_net_proj):
			NetManager.inst.proj_received.disconnect(_on_net_proj)
		if NetManager.inst.choices_received.is_connected(_on_net_choices):
			NetManager.inst.choices_received.disconnect(_on_net_choices)
		if NetManager.inst.banner_received.is_connected(_on_net_banner):
			NetManager.inst.banner_received.disconnect(_on_net_banner)
		if NetManager.inst.feed_received.is_connected(_on_net_feed):
			NetManager.inst.feed_received.disconnect(_on_net_feed)
		if NetManager.inst.emote_received.is_connected(_on_net_emote):
			NetManager.inst.emote_received.disconnect(_on_net_emote)
		if NetManager.inst.match_over_received.is_connected(_on_net_match_over):
			NetManager.inst.match_over_received.disconnect(_on_net_match_over)


func _connect_client_signals() -> void:
	var nm := NetManager.inst
	nm.snapshot_received.connect(_on_net_snapshot)
	nm.pickups_received.connect(_on_net_pickups)
	nm.fx_received.connect(_on_net_fx)
	nm.proj_received.connect(_on_net_proj)
	nm.choices_received.connect(_on_net_choices)
	nm.banner_received.connect(_on_net_banner)
	nm.feed_received.connect(_on_net_feed)
	nm.emote_received.connect(_on_net_emote)
	nm.match_over_received.connect(_on_net_match_over)


func _layer() -> Node2D:
	var n := Node2D.new()
	add_child(n)
	return n


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"active_skill": [KEY_SPACE, KEY_E],
	}
	for action: String in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)


# ================= 地图生成（PVE 像素圣所 vs PVP 五宫格决斗场）=================
func _gen_rocks() -> void:
	walls.clear()
	special_rooms.clear()
	rocks.clear()
	rock_kinds.clear()
	var rock_count := 16
	var kinds := ["moss_rock", "server_pillar", "pine_cluster", "data_crystal"]
	var tries := 0
	while rocks.size() < rock_count and tries < 700:
		tries += 1
		var p := Vector2(randf_range(-ARENA_HALF + 190, ARENA_HALF - 190), randf_range(-ARENA_HALF + 190, ARENA_HALF - 190))
		var r := randf_range(44.0, 74.0)
		if p.length() < 265.0 + r:
			continue
		var ok := true
		for o in rocks:
			var min_d := r + o.z + 195.0
			if p.distance_squared_to(Vector2(o.x, o.y)) < min_d * min_d:
				ok = false
				break
		if ok:
			rocks.append(Vector3(p.x, p.y, r))
			rock_kinds.append(kinds[rocks.size() % kinds.size()])


func _gen_pvp_5grid() -> void:
	rocks.clear()
	rock_kinds.clear()
	walls.clear()
	pvp_traps.clear()
	pvp_creeps.clear()
	special_rooms = [
		{
			"id": "overclock", "name": "🔥 算力超频室", "desc": "攻击 +20% · 攻速 +12%",
			"rect": Rect2(-740.0, -1580.0, 1480.0, 814.0),
			"bg": Color("#382127"), "color": Color("#ff6848"),
		},
		{
			"id": "heal_spring", "name": "💚 数据缓修站", "desc": "脱战 3 秒缓回 +6/秒",
			"rect": Rect2(-740.0, 766.0, 1480.0, 814.0),
			"bg": Color("#1d352e"), "color": Color("#42eb8c"),
		},
		{
			"id": "speed_lane", "name": "⚡ 极速风道", "desc": "移速 +30% · 小心巡航锯刃陷阱！",
			"rect": Rect2(-1580.0, -740.0, 814.0, 1480.0),
			"bg": Color("#1d2e42"), "color": Color("#3ce4ff"),
		},
		{
			"id": "creep_den", "name": "👾 脏数据野区", "desc": "清剿野生数据怪 · 爆高阶 Token 与血药！",
			"rect": Rect2(766.0, -740.0, 814.0, 1480.0),
			"bg": Color("#2d2244"), "color": Color("#c978ff"),
		},
	]
	# 五宫格主结构石墙（厚 48~52px）+ 房间内部大量薄墙掩体（厚 22px，配合穿墙/穿墙子弹超爽！）
	walls = [
		# --- 主城厚墙：中央决斗场四面合围（各留 320px 宽拱门）---
		Rect2(-766.0, -766.0, 606.0, 52.0),
		Rect2(160.0, -766.0, 606.0, 52.0),
		Rect2(-766.0, 714.0, 606.0, 52.0),
		Rect2(160.0, 714.0, 606.0, 52.0),
		Rect2(-766.0, -714.0, 52.0, 554.0),
		Rect2(-766.0, 160.0, 52.0, 554.0),
		Rect2(714.0, -714.0, 52.0, 554.0),
		Rect2(714.0, 160.0, 52.0, 554.0),
		# 四角翼墙（留 374px 宽侧廊包抄道）
		Rect2(-1600.0, -764.0, 460.0, 48.0),
		Rect2(1140.0, -764.0, 460.0, 48.0),
		Rect2(-1600.0, 716.0, 460.0, 48.0),
		Rect2(1140.0, 716.0, 460.0, 48.0),

		# --- 中央决斗场薄墙掩体（4 组对称 L 型薄墙，留足拉扯与卡视野空间）---
		Rect2(-485.0, -295.0, 160.0, 22.0),
		Rect2(-485.0, -295.0, 22.0, 145.0),
		Rect2(325.0, -295.0, 160.0, 22.0),
		Rect2(463.0, -295.0, 22.0, 145.0),
		Rect2(-485.0, 273.0, 160.0, 22.0),
		Rect2(-485.0, 150.0, 22.0, 145.0),
		Rect2(325.0, 273.0, 160.0, 22.0),
		Rect2(463.0, 150.0, 22.0, 145.0),

		# --- 北·算力超频室薄墙掩体 ---
		Rect2(-490.0, -1045.0, 165.0, 22.0),
		Rect2(325.0, -1045.0, 165.0, 22.0),
		Rect2(-95.0, -1350.0, 190.0, 22.0),

		# --- 南·数据缓修站薄墙（方便卡视野脱战 3 秒触发缓回）---
		Rect2(-470.0, 1040.0, 160.0, 22.0),
		Rect2(310.0, 1040.0, 160.0, 22.0),
		Rect2(-90.0, 1340.0, 180.0, 22.0),

		# --- 西·极速风道薄墙导流障 ---
		Rect2(-1190.0, -540.0, 22.0, 175.0),
		Rect2(-1190.0, 365.0, 22.0, 175.0),

		# --- 东·脏数据野区薄墙掩体 ---
		Rect2(1045.0, -510.0, 22.0, 165.0),
		Rect2(1045.0, 345.0, 22.0, 165.0),
		Rect2(1265.0, -11.0, 165.0, 22.0),
	]
	# 精炼战术像素晶碑（保留四角开阔地带作为「四角增益符文祭坛」）
	var pillars := [
		{"p": Vector2(-565, -565), "r": 42.0, "k": "server_pillar"},
		{"p": Vector2(565, -565), "r": 42.0, "k": "server_pillar"},
		{"p": Vector2(-565, 565), "r": 42.0, "k": "data_crystal"},
		{"p": Vector2(565, 565), "r": 42.0, "k": "data_crystal"},
	]
	for item in pillars:
		var pt: Vector2 = item["p"]
		rocks.append(Vector3(pt.x, pt.y, float(item["r"])))
		rock_kinds.append(str(item["k"]))

	# 四角增益符文祭坛（6 种随机符文：减伤/吸血/回血/减CD/临时血量/子弹变大，持续 15s，60s 刷新）
	pvp_runes.clear()
	mid_boss = {}
	mid_boss_bullets.clear()
	mid_boss_cd = MID_BOSS_FIRST_DELAY
	mid_boss_warned = false
	var corner_pts := [
		Vector2(-1240.0, -1240.0),
		Vector2(1240.0, -1240.0),
		Vector2(-1240.0, 1240.0),
		Vector2(1240.0, 1240.0),
	]
	var init_pool: Array[String] = Archer.RUNE_ORDER.duplicate()
	init_pool.shuffle()
	for ci in corner_pts.size():
		var start_kind := init_pool[ci % init_pool.size()] if (demo_midboss and net_role != "client") else ""
		pvp_runes.append({
			"pos": corner_pts[ci],
			"kind": start_kind,
			"cd": 0.0 if start_kind != "" else 6.0,
			"phase": float(ci) * 1.4,
		})
	if demo_midboss and net_role != "client":
		_spawn_mid_boss(true)

	# 西·极速风道：4 座沿轨高速往返巡航的红热电锯陷阱（确定性正弦运动，局域网天然 0 延迟同步！）
	pvp_traps = [
		{"base": Vector2(-1180.0, -235.0), "axis": Vector2(280.0, 0.0), "spd": 1.85, "phase": 0.0, "r": 28.0},
		{"base": Vector2(-1180.0, 235.0), "axis": Vector2(280.0, 0.0), "spd": 2.05, "phase": PI, "r": 28.0},
		{"base": Vector2(-1430.0, 0.0), "axis": Vector2(0.0, 440.0), "spd": 1.50, "phase": 1.1, "r": 28.0},
		{"base": Vector2(-930.0, 0.0), "axis": Vector2(0.0, 410.0), "spd": 1.72, "phase": 3.7, "r": 28.0},
	]
	# 东·脏数据野区：初始生成 6 只野生数据怪（含 1 只高血重装垃圾怪，清剿爆 Token 与血药！）
	if net_role != "client":
		for ci in 6:
			_spawn_pvp_creep("spam_tank" if ci == 0 else ("hallucination" if ci % 2 == 1 else "glitch"))


func pvp_trap_pos(tr: Dictionary) -> Vector2:
	return (tr["base"] as Vector2) + (tr["axis"] as Vector2) * sin(survived_sec * float(tr["spd"]) + float(tr["phase"]))


func _spawn_pvp_creep(kind := "") -> void:
	if kind == "":
		var has_tank := false
		for c in pvp_creeps:
			if str(c["kind"]) == "spam_tank":
				has_tank = true
				break
		kind = "spam_tank" if not has_tank else (["glitch", "hallucination"].pick_random())
	var pos := Vector2(1180.0, 0.0)
	for _i in 30:
		var cand := Vector2(randf_range(830.0, 1510.0), randf_range(-650.0, 650.0))
		if not point_in_wall(cand, 36.0) and not point_in_rock(cand, 36.0):
			pos = cand
			break
	var hp := 215.0 if kind == "spam_tank" else (76.0 if kind == "hallucination" else 96.0)
	var rad := 26.0 if kind == "spam_tank" else 19.0
	var spd := 86.0 if kind == "spam_tank" else (145.0 if kind == "hallucination" else 112.0)
	pvp_creeps.append({
		"id": _creep_seq, "kind": kind, "pos": pos, "home": pos,
		"hp": hp, "max_hp": hp, "radius": rad, "speed": spd,
		"dmg": 22.0 if kind == "spam_tank" else 15.0,
		"flash": 0.0, "kb": Vector2.ZERO, "touch_cd": 0.0, "phase": randf() * TAU,
	})
	_creep_seq += 1


func _update_pvp_room_hazards(delta: float) -> void:
	# 1. 西·极速风道移动电锯陷阱碰撞
	for tr in pvp_traps:
		var tp := pvp_trap_pos(tr)
		var tr_r := float(tr["r"])
		for a in archers:
			if not a.alive or a.trap_hit_cd > 0.0:
				continue
			var hr := tr_r + a.radius - 2.0
			if tp.distance_squared_to(a.position) < hr * hr:
				a.trap_hit_cd = 0.55
				var away := (a.position - tp).normalized() if tp.distance_squared_to(a.position) > 1.0 else Vector2.RIGHT
				a.take_damage(32.0, null, false, away * 330.0)
				spawn_burst(tp, Color("#ff4048"), 34.0)

	# 2. 东·脏数据野区野生数据怪巡逻、反击与定时刷新
	if pvp_creeps.size() < 6:
		_creep_respawn_t += delta
		if _creep_respawn_t >= 5.5:
			_creep_respawn_t = 0.0
			_spawn_pvp_creep()

	var den_rect := Rect2(792.0, -700.0, 760.0, 1400.0)
	for c in pvp_creeps:
		c["flash"] = maxf(float(c["flash"]) - delta, 0.0)
		c["touch_cd"] = maxf(float(c["touch_cd"]) - delta, 0.0)
		var kbv: Vector2 = c["kb"]
		kbv = kbv.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		c["kb"] = kbv
		var cp: Vector2 = c["pos"]
		# 若有玩家进入东野区，则主动追击；否则在野区内巡逻
		var tgt: Archer = null
		var bd := 360.0 * 360.0
		for a in archers:
			if not a.alive or not den_rect.has_point(a.position):
				continue
			var d2 := cp.distance_squared_to(a.position)
			if d2 < bd:
				bd = d2
				tgt = a
		var dir := Vector2.ZERO
		if tgt != null:
			dir = (tgt.position - cp).normalized()
		else:
			var home_v: Vector2 = (c["home"] as Vector2) + Vector2(cos(survived_sec * 0.7 + float(c["phase"])), sin(survived_sec * 0.9 + float(c["phase"]))) * 85.0
			var to_h := home_v - cp
			if to_h.length_squared() > 100.0:
				dir = to_h.normalized() * 0.55
		var np := (cp + (dir * float(c["speed"]) + kbv) * delta).clamp(den_rect.position, den_rect.end)
		if not point_in_wall(np, float(c["radius"]) * 0.85):
			cp = np
		c["pos"] = cp
		if tgt != null and float(c["touch_cd"]) <= 0.0:
			var hr := float(c["radius"]) + tgt.radius - 3.0
			if cp.distance_squared_to(tgt.position) < hr * hr:
				c["touch_cd"] = 0.65
				var away := (tgt.position - cp).normalized() if cp.distance_squared_to(tgt.position) > 1.0 else Vector2.LEFT
				tgt.take_damage(float(c["dmg"]), null, false, away * 220.0)

	# 3. 四角随机增益符文（持续 15s，60s 刷新一次）
	_update_pvp_runes(delta)

	# 4. 中央决斗场 Mid Boss（每 3 分钟刷新一次，击杀享 30s 全6增益 + 1次复活）
	_update_mid_boss(delta)

	# 5. 最后 60 秒：过拟合「算力坍缩缩圈」机制，倒逼全员涌入中央决斗场大决战！
	_update_pvp_storm(delta)


func _update_pvp_storm(delta: float) -> void:
	if not storm_active and (time_left <= STORM_START_TIME or demo_storm):
		storm_active = true
		Sfx.play("boss_warn", 0.02, 400, -5.5)
		broadcast_banner("⚠ 最后 60 秒！算力坍缩毒圈启动，速向中央决斗场集结！", Color("#ff3878"))
		broadcast_feed("⚠ 决胜圈启动！安全区正持续向中央决斗场收缩！")
	if not storm_active:
		return
	var prog := clampf((STORM_START_TIME - time_left) / STORM_START_TIME, 0.0, 1.0)
	var target_r := lerpf(STORM_MAX_R, STORM_MIN_R, prog)
	storm_radius = minf(storm_radius, target_r) if demo_storm else lerpf(storm_radius, target_r, clampf(delta * 2.5, 0.0, 1.0))
	if storm_radius > target_r:
		storm_radius = maxf(target_r, storm_radius - 32.0 * delta)
	var tick_dmg := 14.0 + prog * 18.0
	for a in archers:
		if not a.alive or a.downed:
			continue
		if a.position.length() > storm_radius:
			if a.storm_tick_cd <= 0.0:
				a.storm_tick_cd = 0.50
				var in_dir := (-a.position).normalized() if a.position.length_squared() > 1.0 else Vector2.ZERO
				a.take_damage(tick_dmg, null, false, in_dir * 105.0)
				spawn_burst(a.position, Color("#ff3878"), 28.0)


func _update_pvp_runes(delta: float) -> void:
	for shrine in pvp_runes:
		var kind := str(shrine["kind"])
		if kind == "":
			var ncd := float(shrine["cd"]) - delta
			shrine["cd"] = ncd
			if ncd <= 0.0:
				# 随机刷出 6 种之一，尽量避免当前 4 角全部重复
				var used: Array[String] = []
				for other in pvp_runes:
					var ok := str(other["kind"])
					if ok != "":
						used.append(ok)
				var pool: Array[String] = []
				for rk in Archer.RUNE_ORDER:
					if not used.has(rk):
						pool.append(rk)
				if pool.is_empty():
					pool = Archer.RUNE_ORDER.duplicate()
				var chosen: String = pool.pick_random()
				shrine["kind"] = chosen
				shrine["cd"] = 0.0
				var rcol: Color = Archer.RUNE_DEFS[chosen]["color"]
				spawn_burst(shrine["pos"], rcol, 48.0)
			continue
		var spos: Vector2 = shrine["pos"]
		for a in archers:
			if not a.alive or a.downed:
				continue
			var pr := a.radius + 28.0
			if spos.distance_squared_to(a.position) <= pr * pr:
				a.apply_rune_buff(kind, RUNE_DURATION)
				var rdef: Dictionary = Archer.RUNE_DEFS[kind]
				var rcol: Color = rdef["color"]
				shrine["kind"] = ""
				shrine["cd"] = RUNE_RESPAWN
				a.score += 20
				spawn_burst(spos, rcol, 62.0)
				spawn_text(a.position + Vector2(0, -a.radius - 38), "符文【%s】15s！" % rdef["name"], rcol, 20)
				if a == player:
					Sfx.play("card_pick", 0.03, 90, -6.5)
				broadcast_feed("%s 拾取了四角符文【%s】(15s)" % [a.display_name, rdef["name"]])
				break


func find_nearest_active_rune(pos: Vector2, max_r: float) -> Vector2:
	var best := Vector2.INF
	var bd := max_r * max_r
	for shrine in pvp_runes:
		if str(shrine["kind"]) == "":
			continue
		var sp: Vector2 = shrine["pos"]
		var d2 := pos.distance_squared_to(sp)
		if d2 < bd:
			bd = d2
			best = sp
	return best


func _spawn_mid_boss(silent := false) -> void:
	mid_boss = {
		"pos": Vector2.ZERO,
		"hp": 1150.0,
		"max_hp": 1150.0,
		"radius": 52.0,
		"speed": 84.0,
		"dmg": 28.0,
		"flash": 0.0,
		"kb": Vector2.ZERO,
		"touch_cd": 0.0,
		"shoot_cd": 2.0,
		"volley": 0,
		"phase": 0.0,
	}
	mid_boss_cd = 0.0
	mid_boss_warned = false
	for a in archers:
		if not a.alive:
			continue
		if a.position.length_squared() < 110.0 * 110.0:
			var push_d := a.position.normalized() if a.position.length_squared() > 1.0 else Vector2.RIGHT
			a.position = push_d * 115.0
	if not silent and fx_layer != null:
		spawn_burst(Vector2.ZERO, Color("#ffd84a"), 135.0)
		Sfx.play("boss_warn", 0.02, 200, -5.0)
		broadcast_banner("★ 中央决斗场 Mid Boss 降临！击杀享 30 秒全 6 增益 + 1 次复活！", Color("#ffd84a"))
		broadcast_feed("★ 中央 Mid Boss 已刷新于决斗场核心！")


func _update_mid_boss(delta: float) -> void:
	# 先更新已射出的 Mid Boss 弹幕（即使 Boss 刚被击杀也要自然消散）
	if not mid_boss_bullets.is_empty():
		var rem_b: Array[Dictionary] = []
		for b in mid_boss_bullets:
			b["life"] = float(b["life"]) - delta
			if float(b["life"]) <= 0.0:
				continue
			var bp: Vector2 = (b["pos"] as Vector2) + (b["vel"] as Vector2) * delta
			b["pos"] = bp
			if not in_arena(bp) or point_in_wall(bp, 4.0) or point_in_rock(bp, 4.0):
				continue
			var hit_any := false
			for a in archers:
				if not a.alive or a.downed:
					continue
				var hr := a.radius + 9.0
				if bp.distance_squared_to(a.position) <= hr * hr:
					var push_d := (b["vel"] as Vector2).normalized()
					a.take_damage(float(b["dmg"]), null, false, push_d * 190.0)
					hit_any = true
					break
			if not hit_any:
				rem_b.append(b)
		mid_boss_bullets = rem_b

	if mid_boss.is_empty():
		mid_boss_cd = maxf(0.0, mid_boss_cd - delta)
		if not mid_boss_warned and mid_boss_cd <= 10.0 and mid_boss_cd > 0.0:
			mid_boss_warned = true
			Sfx.play("boss_warn", 0.02, 400, -6.5)
			broadcast_banner("⚠ 中央决斗场 Mid Boss 将在 10 秒后降临！速往中心集结！", Color("#ff5c84"))
		if mid_boss_cd <= 0.0:
			_spawn_mid_boss(false)
		return

	mid_boss["flash"] = maxf(float(mid_boss["flash"]) - delta, 0.0)
	mid_boss["touch_cd"] = maxf(float(mid_boss["touch_cd"]) - delta, 0.0)
	mid_boss["shoot_cd"] = float(mid_boss["shoot_cd"]) - delta
	mid_boss["phase"] = float(mid_boss["phase"]) + delta
	var kbv: Vector2 = mid_boss["kb"]
	kbv = kbv.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
	mid_boss["kb"] = kbv

	var bp: Vector2 = mid_boss["pos"]
	var tgt: Archer = null
	var bd := 680.0 * 680.0
	for a in archers:
		if not a.alive or a.downed or a.position.length_squared() > 710.0 * 710.0:
			continue
		var d2 := bp.distance_squared_to(a.position)
		if d2 < bd:
			bd = d2
			tgt = a

	var move_v := Vector2.ZERO
	if tgt != null:
		var to_t := tgt.position - bp
		if to_t.length_squared() > 140.0 * 140.0:
			move_v = to_t.normalized() * float(mid_boss["speed"])
	elif bp.length_squared() > 25.0:
		move_v = (-bp).normalized() * (float(mid_boss["speed"]) * 0.7)

	var np := bp + (move_v + kbv) * delta
	if np.length() > 410.0:
		np = np.normalized() * 410.0
	if not point_in_wall(np, float(mid_boss["radius"]) * 0.85) and not point_in_rock(np, float(mid_boss["radius"]) * 0.85):
		bp = np
	mid_boss["pos"] = bp

	if tgt != null and float(mid_boss["touch_cd"]) <= 0.0:
		var hr := float(mid_boss["radius"]) + tgt.radius - 4.0
		if bp.distance_squared_to(tgt.position) < hr * hr:
			mid_boss["touch_cd"] = 0.72
			var away := (tgt.position - bp).normalized() if bp.distance_squared_to(tgt.position) > 1.0 else Vector2.RIGHT
			tgt.take_damage(float(mid_boss["dmg"]), null, false, away * 290.0)

	# 8 向旋转紫金能量弹幕（只要中央决斗场有挑战者即定期释放！）
	if float(mid_boss["shoot_cd"]) <= 0.0:
		mid_boss["shoot_cd"] = 2.35
		if tgt != null:
			var v_idx := int(mid_boss["volley"])
			mid_boss["volley"] = v_idx + 1
			var base_ang := (tgt.position - bp).angle() + (0.39 if v_idx % 2 == 1 else 0.0)
			for bi in 8:
				var ang := base_ang + bi * TAU / 8.0
				mid_boss_bullets.append({
					"pos": bp + Vector2.from_angle(ang) * (float(mid_boss["radius"]) + 6.0),
					"vel": Vector2.from_angle(ang) * 265.0,
					"dmg": 22.0,
					"life": 2.4,
				})
			spawn_burst(bp, Color("#d47aff"), 68.0)


func hit_mid_boss(pos: Vector2, pad: float, dmg: float, is_crit: bool, exclude_ids: Array[int], attacker: Archer, kb := Vector2.ZERO, fx_col := Color(1.0, 0.88, 0.36)) -> bool:
	if mid_boss.is_empty() or exclude_ids.has(-999):
		return false
	var r := float(mid_boss["radius"]) + pad
	if pos.distance_squared_to(mid_boss["pos"]) <= r * r:
		_damage_mid_boss(dmg, is_crit, attacker, kb, fx_col)
		return true
	return false


func damage_mid_boss_in_radius(center: Vector2, rad: float, dmg: float, attacker: Archer, kb_force := 190.0) -> void:
	if mid_boss.is_empty():
		return
	var mp: Vector2 = mid_boss["pos"]
	var r := rad + float(mid_boss["radius"])
	if center.distance_squared_to(mp) <= r * r:
		var away := (mp - center).normalized() if center.distance_squared_to(mp) > 1.0 else Vector2.RIGHT
		_damage_mid_boss(dmg, false, attacker, away * kb_force, Color("#ffd84a"))


func _damage_mid_boss(dmg: float, is_crit: bool, attacker: Archer, kb: Vector2, fx_col: Color) -> void:
	if mid_boss.is_empty():
		return
	mid_boss["hp"] = float(mid_boss["hp"]) - dmg
	mid_boss["flash"] = 0.14
	mid_boss["kb"] = ((mid_boss["kb"] as Vector2) + kb * 0.22).limit_length(180.0)
	var mp: Vector2 = mid_boss["pos"]
	spawn_hit_fx(mp, kb.normalized() if kb.length_squared() > 1.0 else Vector2.RIGHT, fx_col, is_crit, false)
	spawn_text(mp + Vector2(randf_range(-16, 16), -54), ("%d!" % int(dmg)) if is_crit else str(int(dmg)), Color(1.0, 0.58, 0.2) if is_crit else Color(1.0, 0.92, 0.42), 22 if is_crit else 17)
	if attacker != null and is_instance_valid(attacker) and attacker.alive:
		var ls := attacker.effective_lifesteal()
		if ls > 0.0:
			attacker.hp = minf(attacker.max_hp, attacker.hp + dmg * ls)
	if attacker == player:
		Sfx.play("crit" if is_crit else "hit", 0.08, 45, -10.0)
	if float(mid_boss["hp"]) <= 0.0:
		mid_boss = {}
		mid_boss_cd = MID_BOSS_RESPAWN
		mid_boss_warned = false
		spawn_burst(mp, Color("#ffd84a"), 155.0)
		Sfx.play("evo_fanfare", 0.01, 180, -4.5)
		add_shake(7.5)
		if attacker != null and is_instance_valid(attacker) and attacker.alive:
			attacker.apply_mid_boss_blessing()
			attacker.score += 250
			if attacker.team_id > 0:
				team_scores[attacker.team_id] = int(team_scores.get(attacker.team_id, 0)) + 250
			broadcast_banner("★ %s 斩杀中央 Mid Boss！获 30 秒全 6 增益 + 1 次复活！" % attacker.display_name, Color("#ffd84a"))
			broadcast_feed("★ %s 斩杀 Mid Boss（30s 全增益 + 复活甲）" % attacker.display_name)
			if not attacker.is_human():
				var ems := Archer.get_emotes_for(attacker.char_id)
				if not ems.is_empty():
					broadcast_emote(attacker.net_id, str(ems[0]["text"]))
		else:
			broadcast_banner("中央 Mid Boss 已被击败，3 分钟后重新降临！", Color("#ffd84a"))


func hit_pvp_creep(pos: Vector2, pad: float, dmg: float, is_crit: bool, exclude_ids: Array[int], attacker: Archer, kb := Vector2.ZERO, fx_col := Color(1.0, 0.92, 0.55)) -> int:
	for i in pvp_creeps.size():
		var c := pvp_creeps[i]
		var cid := int(c["id"])
		if exclude_ids.has(cid):
			continue
		var r := float(c["radius"]) + pad
		if pos.distance_squared_to(c["pos"]) <= r * r:
			_damage_pvp_creep(i, dmg, is_crit, attacker, kb, fx_col)
			return cid
	return -1


func damage_pvp_creeps_in_radius(center: Vector2, rad: float, dmg: float, attacker: Archer, kb_force := 190.0) -> void:
	var i := pvp_creeps.size() - 1
	while i >= 0:
		if i >= pvp_creeps.size():
			i -= 1
			continue
		var c := pvp_creeps[i]
		var r := rad + float(c["radius"])
		if center.distance_squared_to(c["pos"]) <= r * r:
			var away := ((c["pos"] as Vector2) - center).normalized()
			_damage_pvp_creep(i, dmg, false, attacker, away * kb_force, Color(0.88, 0.62, 1.0))
		i -= 1


func _damage_pvp_creep(idx: int, dmg: float, is_crit: bool, attacker: Archer, kb: Vector2, fx_col: Color) -> void:
	if idx < 0 or idx >= pvp_creeps.size():
		return
	var c := pvp_creeps[idx]
	c["hp"] = float(c["hp"]) - dmg
	c["flash"] = 0.14
	c["kb"] = ((c["kb"] as Vector2) + kb * (0.45 if str(c["kind"]) == "spam_tank" else 0.9)).limit_length(380.0)
	var cp: Vector2 = c["pos"]
	spawn_hit_fx(cp, kb.normalized() if kb.length_squared() > 1.0 else Vector2.RIGHT, fx_col, is_crit, false)
	spawn_text(cp + Vector2(randf_range(-10, 10), -26), ("%d!" % int(dmg)) if is_crit else str(int(dmg)), Color(1.0, 0.58, 0.2) if is_crit else Color(1.0, 0.94, 0.55), 20 if is_crit else 16)
	if attacker != null and is_instance_valid(attacker) and attacker.alive:
		var ls := attacker.effective_lifesteal()
		if ls > 0.0:
			attacker.hp = minf(attacker.max_hp, attacker.hp + dmg * ls)
	if attacker == player:
		Sfx.play("crit" if is_crit else "hit", 0.08, 45, -11.0)
	if float(c["hp"]) <= 0.0:
		var is_tank := (str(c["kind"]) == "spam_tank")
		pvp_creeps.remove_at(idx)
		spawn_burst(cp, Color("#c978ff"), 48.0 if is_tank else 34.0)
		if attacker == player:
			Sfx.play("kill", 0.06, 60, -8.0)
		if attacker != null and is_instance_valid(attacker):
			attacker.score += 45 if is_tank else 22
			if attacker.team_id > 0:
				team_scores[attacker.team_id] = int(team_scores.get(attacker.team_id, 0)) + (30 if is_tank else 15)
		# 清剿野怪必爆高阶金/紫 Token + 回血血药！
		var tok_cnt := 5 if is_tank else 3
		for ti in tok_cnt:
			var ang := ti * TAU / float(tok_cnt) + randf() * 0.4
			spawn_orb(cp + Vector2.from_angle(ang) * randf_range(16.0, 44.0), 15 if is_tank else [10, 15].pick_random())
		spawn_heart(cp + Vector2(20, 0))
		if is_tank:
			spawn_heart(cp + Vector2(-20, 0))


func room_effect_at(p: Vector2) -> String:
	for rm in special_rooms:
		if (rm["rect"] as Rect2).has_point(p):
			return str(rm["id"])
	return ""


func room_info(rid: String) -> Dictionary:
	for rm in special_rooms:
		if str(rm["id"]) == rid:
			return rm
	return {}


# ================= 初始参战者与拾取物生成 =================
func _spawn_initial_roster() -> void:
	if net_role == "offline":
		var my_team := 1 if (game_mode == "pvp" and pvp_variant == "2v2v2v2") else (1 if is_coop else 0)
		var p_name := "%s(你)" % Characters.get_data(player_char_id)["name"]
		player = _spawn_archer(true, false, false, 1, my_team, player_char_id, player_weapon_id, p_name, 1)
		if game_mode == "pvp" and fill_bots:
			if pvp_variant == "2v2v2v2":
				# 补满 4 队 × 2 人（共 8 人）
				_spawn_bot(1)
				for t in [2, 3, 4]:
					_spawn_bot(t)
					_spawn_bot(t)
			else:
				for _i in BOT_COUNT:
					_spawn_bot(0)
		return

	# 局域网联机（Host / Client 均按同步名单生成全部真人角色）
	var my_nid := NetManager.inst.my_id if NetManager.inst != null else 1
	var team_counts := {1: 0, 2: 0, 3: 0, 4: 0}
	var pids := lan_roster.keys()
	pids.sort()
	var human_idx := 0
	for raw_pid in pids:
		var pid := int(raw_pid)
		var info: Dictionary = lan_roster[raw_pid]
		var is_me := (pid == my_nid)
		var is_rem := (net_role == "host" and not is_me)
		var is_mir := (net_role == "client")
		var tid := int(info.get("team", 0))
		if is_coop:
			tid = 1
		var pname := str(info.get("name", "玩家")) + ("(你)" if is_me else "")
		var a := _spawn_archer(is_me, is_rem, is_mir, pid, tid, str(info.get("char", "claude")), str(info.get("weapon", "grimoire")), pname, 1, human_idx)
		if is_me:
			player = a
		if team_counts.has(tid):
			team_counts[tid] = int(team_counts[tid]) + 1
		human_idx += 1

	# 房主按房间配置填充 AI 人机（PVP 乱斗或 2v2v2v2）
	if net_role == "host" and game_mode == "pvp" and fill_bots:
		if pvp_variant == "2v2v2v2":
			for t in [1, 2, 3, 4]:
				var need := maxi(0, 2 - int(team_counts[t]))
				for _k in need:
					_spawn_bot(t)
		else:
			var need := maxi(0, 8 - archers.size())
			for _k in need:
				_spawn_bot(0)


func _spawn_initial_pickups() -> void:
	if game_mode == "pvp":
		for _i in ORB_TARGET:
			spawn_orb(random_free_point(50.0, false), [5, 5, 5, 10, 10, 15].pick_random())
		for _i in 10:
			spawn_heart(random_free_point(90.0, false))
	else:
		for _i in 38:
			spawn_orb(random_free_point(80.0, false), 5)
		pickups.spawn_magnet(random_free_point(180.0, false))


func visible_world_rect(pad := 80.0) -> Rect2:
	if camera == null:
		return Rect2(-ARENA_HALF, -ARENA_HALF, ARENA_HALF * 2.0, ARENA_HALF * 2.0)
	var vs := get_viewport_rect().size / camera.zoom
	var half := vs * 0.5 + Vector2(pad, pad)
	return Rect2(camera.position - half, half * 2.0)


# ================= 生成角色与投射物 =================
func _spawn_pos_for(team: int, idx := 0) -> Vector2:
	if game_mode == "survivor":
		return Vector2(-70.0 + idx * 140.0, 0.0) if is_coop else Vector2.ZERO
	if pvp_variant == "2v2v2v2" and team >= 1 and team <= 4:
		var bases := [Vector2.ZERO, Vector2(0, -1160), Vector2(0, 1160), Vector2(-1160, 0), Vector2(1160, 0)]
		var b: Vector2 = bases[team]
		var jitter := Vector2(randf_range(-140.0, 140.0), randf_range(-120.0, 120.0))
		var p := (b + jitter).clamp(Vector2(-ARENA_HALF + 120, -ARENA_HALF + 120), Vector2(ARENA_HALF - 120, ARENA_HALF - 120))
		if not point_in_rock(p, 40.0) and not point_in_wall(p, 40.0):
			return p
	return random_free_point(120.0, true)


func _spawn_archer(is_p: bool, is_rem: bool, is_mir: bool, nid: int, team: int, cid: String, wid: String, n: String, start_level: int, idx := 0) -> Archer:
	var a := Archer.new()
	a.game = self
	a.is_player = is_p
	a.is_remote_human = is_rem
	a.is_client_mirror = is_mir
	a.net_id = nid
	a.team_id = team
	a.char_id = cid
	a.weapon_id = wid
	a.display_name = n
	a.position = _spawn_pos_for(team, idx)
	a.net_target_pos = a.position
	if not is_p and not is_rem:
		a.ai_aim_error = randf_range(0.15, 0.25)
	archer_layer.add_child(a)
	archers.append(a)
	a.died.connect(_on_archer_died)
	if not is_mir:
		for _i in start_level - 1:
			a.level_up()
		a.hp = a.max_hp
	return a


func _spawn_bot(team := 0) -> void:
	if game_over or game_mode != "pvp" or net_role == "client":
		return
	var cid: String = Characters.ORDER[_bot_seq % Characters.ORDER.size()]
	var copy_num := (_bot_seq / Characters.ORDER.size()) + 1
	_bot_seq += 1
	var cd := Characters.get_data(cid)
	var wid: String = str(cd["weapon"])
	var n := str(cd["name"]) if copy_num == 1 else "%s #%d" % [cd["name"], copy_num]
	var lv := 1
	if player != null:
		lv = clampi(player.level - randi_range(0, 1), 1, player.level + 1)
	var b_nid := _next_bot_nid
	_next_bot_nid -= 1
	_spawn_archer(false, false, false, b_nid, team, cid, wid, n, lv)


func spawn_projectile(owner_archer: Archer, dir: Vector2, wid: String, dmg_mult := 1.0, proj_scale := 1.0, extra_pierce := 0, extra_splash := 0.0, custom_wall_bounces := -1, is_evo := false) -> void:
	var pos := owner_archer.position + dir * (owner_archer.radius + 6.0)
	spawn_projectile_at(owner_archer, pos, dir, wid, dmg_mult, proj_scale, extra_pierce, extra_splash, custom_wall_bounces, is_evo)


func spawn_projectile_at(owner_archer: Archer, pos: Vector2, dir: Vector2, wid: String, dmg_mult := 1.0, proj_scale := 1.0, extra_pierce := 0, extra_splash := 0.0, custom_wall_bounces := -1, is_evo := false) -> void:
	var cap := 180 if game_mode == "survivor" else 110
	if active_projectiles >= cap and not owner_archer.is_human():
		return
	if active_projectiles >= cap + 40:
		return
	var wd := Weapons.get_data(wid)
	var p := Projectile.new()
	p.game = self
	p.shooter = owner_archer
	p.weapon_id = wid
	p.position = pos
	p.proj_scale = proj_scale
	p.evolved = is_evo
	var spd := owner_archer.arrow_speed
	p.velocity = dir.normalized() * spd
	p.damage = owner_archer.damage * dmg_mult
	p.pierce = owner_archer.pierce + extra_pierce
	p.bounce = owner_archer.bounce
	p.wall_bounces = custom_wall_bounces if custom_wall_bounces >= 0 else (1 if wid == "basin" else 0)
	p.wall_pierce = owner_archer.wall_pierce
	p.homing = float(wd["homing"]) + (2.4 if (wid == "bow" and is_evo) else 0.0)
	var sp := float(wd["splash"]) + extra_splash
	if owner_archer.char_id == "deepseek" and sp > 0.0:
		sp *= 1.25
	p.splash = sp
	# 弹道数与射速叠高后自动收束有效射程，保持弹幕爽而不乱！
	var eff_range := owner_archer.effective_attack_range()
	p.max_dist = eff_range * 0.92
	p.life = (eff_range * (1.42 if wid == "basin" else 1.18) / maxf(spd, 100.0)) if wid != "fan" else 2.4
	p.color = wd["color"]
	proj_layer.add_child(p)
	if net_role == "host" and NetManager.inst != null:
		NetManager.inst.s2c_spawn_proj.rpc(owner_archer.net_id, pos, dir.normalized(), wid, proj_scale, is_evo)


func spawn_mini_basin(owner_archer: Archer, pos: Vector2, dir: Vector2) -> void:
	if active_projectiles >= 210:
		return
	var p := Projectile.new()
	p.game = self
	p.shooter = owner_archer
	p.weapon_id = "basin"
	p.position = pos
	p.proj_scale = 0.72
	p.evolved = true
	p.is_mini_split = true
	p.velocity = dir.normalized() * 520.0
	p.damage = owner_archer.damage * 0.58
	p.pierce = 0
	p.bounce = 1
	p.wall_bounces = 1
	p.splash = 46.0
	p.life = 0.75
	p.color = Color("#7ae8ff")
	proj_layer.add_child(p)
	if net_role == "host" and NetManager.inst != null:
		NetManager.inst.s2c_spawn_proj.rpc(owner_archer.net_id, pos, dir.normalized(), "basin", 0.72, true)


func laser_end_dist(start: Vector2, dir: Vector2, max_len: float) -> float:
	var step := 16.0
	var d := step
	while d < max_len:
		var pt := start + dir * d
		if not in_arena(pt) or point_in_rock(pt, 0.0) or point_in_wall(pt, 0.0):
			return d
		d += step
	return max_len


func fire_laser(owner_archer: Archer, dir: Vector2, length: float, dmg: float, width: float, col: Color, knockback: bool) -> void:
	var start := owner_archer.position + dir * (owner_archer.radius + 4.0)
	var end_dist := laser_end_dist(start, dir, length)
	var end_pos := start + dir * end_dist

	var beam := Fx.new()
	beam.kind = "laser"
	beam.position = start
	beam.beam_end = end_pos - start
	beam.beam_width = width
	beam.color = col
	beam.life = 0.24 if width > 12.0 else 0.16
	fx_layer.add_child(beam)

	if game_mode == "survivor" and swarm != null:
		swarm.damage_along_beam(start, dir, end_dist, width, dmg, owner_archer, knockback)
		return

	if not mid_boss.is_empty():
		var mrel: Vector2 = (mid_boss["pos"] as Vector2) - start
		var mproj := mrel.dot(dir)
		if mproj >= 0.0 and mproj <= end_dist:
			var mperp := (mrel - dir * mproj).length()
			if mperp <= float(mid_boss["radius"]) + width * 0.85:
				var m_crit := randf() < owner_archer.crit_chance
				_damage_mid_boss(dmg * (1.4 if m_crit else 1.0), m_crit, owner_archer, dir * (420.0 if knockback else 200.0), col)

	for a in archers:
		if a == owner_archer or not a.alive or a.downed or owner_archer.is_ally(a):
			continue
		var rel := a.position - start
		var proj := rel.dot(dir)
		if proj < 0.0 or proj > end_dist:
			continue
		var perp := (rel - dir * proj).length()
		if perp <= a.radius + width * 0.85:
			var final_dmg := dmg
			var is_crit := randf() < owner_archer.crit_chance
			if is_crit:
				final_dmg *= 1.4
			var kb_force := 480.0 if knockback else 235.0
			a.take_damage(final_dmg, owner_archer, is_crit, dir * kb_force)


func spawn_orb(p: Vector2, value: int) -> void:
	pickups.spawn_orb(p, value)


func spawn_heart(p: Vector2) -> void:
	pickups.spawn_heart(p)


# ================= 特效生成与局域网广播 =================
func _broadcast_fx(kind: String, pos: Vector2, extra: Dictionary) -> void:
	if net_role == "host" and NetManager.inst != null:
		NetManager.inst.s2c_fx.rpc(kind, pos, extra)


func broadcast_banner(text: String, col: Color) -> void:
	if hud != null:
		hud.show_banner(text, col)
	if net_role == "host" and NetManager.inst != null:
		NetManager.inst.s2c_banner.rpc(text, col)


func broadcast_feed(text: String) -> void:
	if hud != null:
		hud.add_feed(text)
	if net_role == "host" and NetManager.inst != null:
		NetManager.inst.s2c_feed.rpc(text)


func send_local_emote(idx := -1) -> void:
	if player == null or not player.alive or player.emote_cd > 0.0:
		return
	var ems := Archer.get_emotes_for(player.char_id)
	if ems.is_empty():
		return
	var pick := idx if (idx >= 0 and idx < ems.size()) else (_emote_cycle % ems.size())
	_emote_cycle += 1
	var msg := str(ems[pick]["text"])
	player.emote_cd = 1.25
	if net_role == "client":
		player.show_emote(msg)
		Sfx.play("card_hover", 0.08, 90, -10.0)
		if NetManager.inst != null:
			NetManager.inst.c2s_emote.rpc_id(1, msg)
	else:
		broadcast_emote(player.net_id, msg)


func broadcast_emote(sender_nid: int, text: String) -> void:
	var a := _find_archer_by_nid(sender_nid)
	if a != null and a.alive:
		a.show_emote(text)
		if a == player or visible_world_rect(120.0).has_point(a.position):
			Sfx.play("card_hover", 0.08, 90, -10.0)
	if net_role == "host" and NetManager.inst != null:
		NetManager.inst.s2c_emote.rpc(sender_nid, text)


func _on_net_emote(sender_nid: int, text: String) -> void:
	var a := _find_archer_by_nid(sender_nid)
	if a != null and a.alive:
		a.show_emote(text)
		if a == player or visible_world_rect(120.0).has_point(a.position):
			Sfx.play("card_hover", 0.08, 90, -10.0)


func spawn_text(p: Vector2, text: String, col: Color, fsize := 20) -> void:
	if _text_fx_count >= MAX_TEXT_FX or not visible_world_rect(40.0).has_point(p):
		return
	var f := Fx.new()
	f.kind = "text"
	f.text = text
	f.color = col
	f.font_size = fsize
	f.life = 0.65
	f.position = p
	_text_fx_count += 1
	f.tree_exited.connect(func() -> void: _text_fx_count = maxi(0, _text_fx_count - 1))
	fx_layer.add_child(f)


func spawn_hit_fx(p: Vector2, hit_dir: Vector2, col: Color, is_crit := false, is_shield := false) -> void:
	if _hit_fx_count >= MAX_HIT_FX or not visible_world_rect(70.0).has_point(p):
		return
	var f := Fx.new()
	f.kind = "hit_impact"
	f.position = p
	f.hit_dir = hit_dir.normalized() if hit_dir.length_squared() > 0.001 else Vector2.RIGHT
	f.color = col
	f.is_crit = is_crit
	f.is_shield = is_shield
	f.life = 0.28 if is_crit else 0.21
	_hit_fx_count += 1
	f.tree_exited.connect(func() -> void: _hit_fx_count = maxi(0, _hit_fx_count - 1))
	fx_layer.add_child(f)


func add_shake(amount: float) -> void:
	_shake = minf(12.0, maxf(_shake, amount))


func spawn_burst(p: Vector2, col: Color, r: float, from_net := false) -> void:
	if not from_net:
		_broadcast_fx("burst", p, {"c": col, "r": r})
	if not visible_world_rect(90.0).has_point(p):
		return
	var f := Fx.new()
	f.kind = "burst"
	f.color = col
	f.ring_radius = r
	f.life = 0.45
	f.position = p
	fx_layer.add_child(f)


func spawn_buff_aura(target: Node2D, col: Color) -> void:
	var f := Fx.new()
	f.kind = "buff_aura"
	f.follow_target = target
	f.position = target.position
	f.color = col
	f.ring_radius = 40.0
	f.life = 0.72
	fx_layer.add_child(f)


func spawn_orbital_fx(pos: Vector2, rad: float, col: Color) -> void:
	if not visible_world_rect(140.0).has_point(pos):
		return
	var f := Fx.new()
	f.kind = "orbital_strike"
	f.position = pos
	f.ring_radius = rad
	f.color = col
	f.life = 0.42
	fx_layer.add_child(f)


func spawn_basin_drop_fx(pos: Vector2, rad: float, basin_scale := 1.65, fall_dur := 0.28, show_duang := true, from_net := false) -> void:
	if not from_net:
		_broadcast_fx("basin_drop", pos, {"r": rad, "s": basin_scale, "f": fall_dur, "d": show_duang})
	if not visible_world_rect(220.0).has_point(pos):
		return
	var f := Fx.new()
	f.kind = "basin_drop"
	f.position = pos
	f.ring_radius = rad
	f.basin_scale = basin_scale
	f.fall_dur = fall_dur
	f.show_duang = show_duang
	f.color = Color(0.45, 0.84, 1.0)
	f.life = fall_dur + 0.56
	fx_layer.add_child(f)


func spawn_eclipse_slash_fx(pos: Vector2, rad: float, from_net := false) -> void:
	if not from_net:
		_broadcast_fx("eclipse_slash", pos, {"r": rad})
	if not visible_world_rect(180.0).has_point(pos):
		return
	var f := Fx.new()
	f.kind = "eclipse_slash"
	f.position = pos
	f.ring_radius = rad
	f.color = Color(0.95, 0.22, 0.35)
	f.life = 0.36
	fx_layer.add_child(f)


func spawn_lightning_fx(pts: PackedVector2Array, col: Color, from_net := false) -> void:
	if not from_net:
		_broadcast_fx("lightning", Vector2.ZERO, {"pts": pts, "c": col})
	var f := Fx.new()
	f.kind = "lightning"
	f.points = pts
	f.color = col
	f.life = 0.28
	fx_layer.add_child(f)


func spawn_meteor_fx(pos: Vector2, rad: float, col: Color, from_net := false) -> void:
	if not from_net:
		_broadcast_fx("meteor", pos, {"r": rad, "c": col})
	if not visible_world_rect(140.0).has_point(pos):
		return
	var f := Fx.new()
	f.kind = "meteor"
	f.position = pos
	f.ring_radius = rad
	f.color = col
	f.life = 0.62
	fx_layer.add_child(f)


# ================= 每帧输入与逻辑 =================
func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE and hud != null:
			hud.toggle_pause_menu()
			return
		var modal_open := hud != null and (hud.skill_panel.visible or hud.pause_panel.visible or hud.chest_panel.visible or hud.over_panel.visible)
		if not modal_open and not get_tree().paused and player != null and player.alive:
			if kc >= KEY_1 and kc <= KEY_4:
				send_local_emote(kc - KEY_1)
				return
			elif kc == KEY_T:
				send_local_emote(-1)
				return
	if get_tree().paused or player == null or not player.alive or player.downed:
		return
	if event.is_action_pressed("active_skill"):
		_trigger_local_active()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_trigger_local_active()


func _trigger_local_active() -> void:
	if net_role == "client":
		_local_active_seq += 1
		Sfx.play("skill", 0.04, 150, -8.0)
	else:
		player.trigger_active_skill()


func _physics_process(delta: float) -> void:
	if game_over:
		return
	survived_sec += delta

	if net_role == "client":
		_net_client_tick(delta)
		return

	if is_endless:
		if autotest and override_time > 0.0 and survived_sec >= override_time:
			end_match("极限无尽测试达标！", false)
			return
	else:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			var dd := Difficulties.get_data(difficulty_id)
			var win_msg := "同步完成！[%s] %s 守护成功！" % [dd["name"], dd["mission_title"]] if game_mode == "survivor" else "时间到！"
			end_match(win_msg, game_mode == "survivor")
			return

	if game_mode == "pvp":
		for i in archers.size():
			for j in range(i + 1, archers.size()):
				var a := archers[i]
				var b := archers[j]
				if not a.alive or not b.alive:
					continue
				var d := b.position - a.position
				var min_d := a.radius + b.radius
				var d2 := d.length_squared()
				if d2 < min_d * min_d and d2 > 0.01:
					var dl := sqrt(d2)
					var push := (d / dl) * (min_d - dl) * 0.5
					a.position -= push
					b.position += push
		_update_pvp_room_hazards(delta)
		if pickups.orbs.size() < ORB_TARGET and randf() < 0.22:
			spawn_orb(random_free_point(50.0, false), [5, 5, 10].pick_random())
		if pickups.hearts.size() < 10 and randf() < 0.025:
			spawn_heart(random_free_point(90.0, false))

	if net_role == "host":
		_net_host_tick(delta)


func _process(delta: float) -> void:
	if player != null and player.alive:
		camera.position = player.position
		var z := 1.0 / sqrt(player.radius / Archer.BASE_RADIUS)
		camera.zoom = camera.zoom.lerp(Vector2(z, z), delta * 2.0)
	if _shake > 0.05:
		_shake = maxf(_shake - delta * 28.0, 0.0)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


func debug_shot(delta: float) -> void:
	if shot_path == "" or _shot_done:
		return
	_shot_timer += delta
	if demo_skill_capture >= 0.0 and not _demo_skill_fired and _shot_timer > 2.2:
		_demo_skill_fired = true
		player.trigger_active_skill()
	if demo_storm and not _demo_skill_fired and _shot_timer > 2.0:
		_demo_skill_fired = true
		player.emote_cd = 0.0
		send_local_emote(0)
		for a in archers:
			if a != player and a.alive and a.position.distance_squared_to(player.position) < 620.0 * 620.0:
				var ems := Archer.get_emotes_for(a.char_id)
				if not ems.is_empty():
					a.show_emote(str(ems[0]["text"]))
	if demo_pause and not _demo_picked and _shot_timer > 1.6:
		_demo_picked = true
		# 演示暂停构筑面板：给玩家叠 3 个代表词条 + 1 个超武直观展示 Build 视图
		Skills.apply(player, "sub_orbital")
		Skills.apply(player, "sub_dragon_rain")
		Skills.apply(player, "sub_eclipse_slash")
		Skills.apply(player, "surv_aspd")
		Skills.apply(player, "evo_basin")
		hud.toggle_pause_menu()
	if demo_levelup and _shot_timer > 1.4 and pending_picks == 0 and player.level == 1:
		player.gain_xp(player.xp_needed())
	if demo_pick and not _demo_picked and _shot_timer > 2.3 and hud.skill_panel.visible:
		_demo_picked = true
		hud.pick_skill_for_demo(1)
	var capture_at := (2.2 + demo_skill_capture) if demo_skill_capture >= 0.0 else (2.1 if demo_pause else (2.65 if demo_pick else (2.5 if demo_levelup else 3.2)))
	if _shot_timer > capture_at:
		_shot_done = true
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("screenshot saved: ", shot_path)
		get_tree().quit()


# ================= 局域网同步（Host 快照广播 / Client 镜像与输入上报）=================
func _net_host_tick(delta: float) -> void:
	if NetManager.inst == null:
		return
	_net_snap_t -= delta
	_net_pickup_t -= delta
	if _net_snap_t <= 0.0:
		_net_snap_t = 0.045  # ~22Hz 平滑快照
		var a_arr: Array = []
		for a in archers:
			a_arr.append([
				a.net_id, a.char_id, a.weapon_id, a.display_name, a.team_id,
				a.position, a.aim_dir, a.hp, a.max_hp, a.shield, a.max_shield,
				a.level, a.score, a.kills, a.tokens, a.alive, a.downed,
				a.revive_prog, a.auto_revive_t, a.active_cd, a.evolved_weapon, a.room_buff, a.phase_wall, a.wall_pierce,
				a.temp_hp, a.max_temp_hp, a.revive_charges, a.rune_timers.duplicate(),
			])
		var snap := {
			"tl": time_left, "ss": survived_sec, "a": a_arr, "ts": team_scores.duplicate(),
		}
		if not pvp_creeps.is_empty():
			var pc_arr: Array = []
			for c in pvp_creeps:
				pc_arr.append([int(c["id"]), str(c["kind"]), c["pos"], float(c["hp"]) / maxf(float(c["max_hp"]), 1.0), float(c["radius"]), float(c["flash"]) > 0.01])
			snap["pc"] = pc_arr
		if game_mode == "pvp":
			var pr_arr: Array = []
			for sh in pvp_runes:
				pr_arr.append([str(sh["kind"]), float(sh["cd"])])
			snap["pr"] = pr_arr
			snap["mbc"] = mid_boss_cd
			if not mid_boss.is_empty():
				snap["mb"] = [mid_boss["pos"], float(mid_boss["hp"]), float(mid_boss["max_hp"]), float(mid_boss["radius"]), float(mid_boss["flash"]) > 0.01]
			if not mid_boss_bullets.is_empty():
				var mbb_arr: Array = []
				for b in mid_boss_bullets:
					mbb_arr.append(b["pos"])
				snap["mbb"] = mbb_arr
			if storm_active:
				snap["sa"] = true
				snap["sr"] = storm_radius
		if swarm != null:
			snap["sw"] = swarm.serialize_snapshot()
		NetManager.inst.s2c_snapshot.rpc(snap)
	if _net_pickup_t <= 0.0:
		_net_pickup_t = 0.20
		NetManager.inst.s2c_pickups.rpc(pickups.serialize_snapshot())


func _on_net_pickups(pk: Dictionary) -> void:
	if pickups != null:
		pickups.apply_net_snapshot(pk)


func _net_client_tick(delta: float) -> void:
	if NetManager.inst == null or player == null:
		return
	_net_input_t -= delta
	if _net_input_t <= 0.0:
		_net_input_t = 0.033  # 30Hz 上报输入
		NetManager.inst.c2s_input.rpc_id(1, player.move_dir, player.aim_dir, player.wants_fire, _local_active_seq)


func _on_net_snapshot(snap: Dictionary) -> void:
	time_left = float(snap.get("tl", time_left))
	survived_sec = float(snap.get("ss", survived_sec))
	if snap.has("ts"):
		team_scores = snap["ts"]
	if snap.has("sw") and swarm != null:
		swarm.apply_net_snapshot(snap["sw"])
	if snap.has("pc"):
		pvp_creeps.clear()
		for crow in snap["pc"]:
			var cr: Array = crow
			pvp_creeps.append({
				"id": int(cr[0]), "kind": str(cr[1]), "pos": cr[2],
				"hp": float(cr[3]) * 100.0, "max_hp": 100.0, "radius": float(cr[4]),
				"flash": 0.1 if bool(cr[5]) else 0.0, "phase": float(int(cr[0]) % 13),
			})
	elif game_mode == "pvp":
		pvp_creeps.clear()
	if snap.has("pr"):
		var pr_arr: Array = snap["pr"]
		for ri in mini(pr_arr.size(), pvp_runes.size()):
			var rr: Array = pr_arr[ri]
			pvp_runes[ri]["kind"] = str(rr[0])
			pvp_runes[ri]["cd"] = float(rr[1])
	if snap.has("mbc"):
		mid_boss_cd = float(snap["mbc"])
	if snap.has("mb"):
		var mbr: Array = snap["mb"]
		mid_boss = {
			"pos": mbr[0], "hp": float(mbr[1]), "max_hp": float(mbr[2]),
			"radius": float(mbr[3]), "flash": 0.1 if bool(mbr[4]) else 0.0,
		}
	elif game_mode == "pvp":
		mid_boss = {}
	if snap.has("mbb"):
		mid_boss_bullets.clear()
		for bpos in snap["mbb"]:
			mid_boss_bullets.append({"pos": bpos})
	elif game_mode == "pvp":
		mid_boss_bullets.clear()
	if snap.has("sa"):
		storm_active = bool(snap["sa"])
		storm_radius = float(snap.get("sr", storm_radius))
	if snap.has("pk") and pickups != null:
		pickups.apply_net_snapshot(snap["pk"])

	var my_nid := NetManager.inst.my_id if NetManager.inst != null else 1
	var seen_nids: Dictionary = {}
	for row in snap.get("a", []):
		var r: Array = row
		var nid := int(r[0])
		seen_nids[nid] = true
		var a := _find_archer_by_nid(nid)
		if a == null:
			a = _spawn_archer(nid == my_nid, false, true, nid, int(r[4]), str(r[1]), str(r[2]), str(r[3]), 1)
			if nid == my_nid:
				player = a
		a.net_target_pos = r[5]
		if not a.is_player:
			a.aim_dir = r[6]
		a.hp = float(r[7]); a.max_hp = float(r[8])
		a.shield = float(r[9]); a.max_shield = float(r[10])
		a.level = int(r[11]); a.score = int(r[12]); a.kills = int(r[13]); a.tokens = int(r[14])
		a.alive = bool(r[15]); a.downed = bool(r[16])
		a.revive_prog = float(r[17]); a.auto_revive_t = float(r[18])
		a.active_cd = float(r[19]); a.evolved_weapon = str(r[20]); a.room_buff = str(r[21])
		if r.size() > 23:
			a.phase_wall = bool(r[22]); a.wall_pierce = bool(r[23])
		if r.size() > 27:
			a.temp_hp = float(r[24]); a.max_temp_hp = float(r[25]); a.revive_charges = int(r[26])
			a.rune_timers = (r[27] as Dictionary).duplicate() if (r[27] is Dictionary) else {}
		a.radius = Archer.BASE_RADIUS * minf(1.0 + (a.level - 1) * 0.024, 1.42)

	for i in range(archers.size() - 1, -1, -1):
		if not seen_nids.has(archers[i].net_id) and archers[i] != player:
			archers[i].queue_free()
			archers.remove_at(i)


func _find_archer_by_nid(nid: int) -> Archer:
	for a in archers:
		if a.net_id == nid:
			return a
	return null


func _on_net_proj(shooter_nid: int, pos: Vector2, dir: Vector2, wid: String, pscale: float, evolved: bool) -> void:
	var src := _find_archer_by_nid(shooter_nid)
	var wd := Weapons.get_data(wid)
	var p := Projectile.new()
	p.game = self
	p.shooter = src
	p.weapon_id = wid
	p.position = pos
	p.proj_scale = pscale
	p.evolved = evolved
	p.visual_only = true
	p.wall_bounces = 1 if wid == "basin" else 0
	p.wall_pierce = src != null and src.wall_pierce
	p.velocity = dir.normalized() * float(wd["speed"])
	p.life = 0.85
	p.color = wd["color"]
	proj_layer.add_child(p)
	if src != null and src.is_player:
		Sfx.play("shoot_" + wid, 0.07, 65, -12.0)


func _on_net_fx(kind: String, pos: Vector2, extra: Dictionary) -> void:
	match kind:
		"burst":
			spawn_burst(pos, extra.get("c", Color.WHITE), float(extra.get("r", 40.0)), true)
		"basin_drop":
			spawn_basin_drop_fx(pos, float(extra.get("r", 100.0)), float(extra.get("s", 1.6)), float(extra.get("f", 0.28)), bool(extra.get("d", true)), true)
			Sfx.play("basin_clang", 0.07, 70, -7.0)
		"eclipse_slash":
			spawn_eclipse_slash_fx(pos, float(extra.get("r", 150.0)), true)
		"lightning":
			spawn_lightning_fx(extra.get("pts", PackedVector2Array()), extra.get("c", Color.CYAN), true)
		"meteor":
			spawn_meteor_fx(pos, float(extra.get("r", 80.0)), extra.get("c", Color.ORANGE), true)


func _on_net_choices(choices: Array) -> void:
	_last_client_choices.clear()
	for c in choices:
		_last_client_choices.append(str(c))
	Sfx.play("levelup", 0.02, 200, -7.0)
	hud.show_skill_pick(_last_client_choices)


func _on_net_banner(text: String, col: Color) -> void:
	if hud != null:
		hud.show_banner(text, col)


func _on_net_feed(text: String) -> void:
	if hud != null:
		hud.add_feed(text)


func _on_net_match_over(reason: String, _standings: Array, is_victory: bool) -> void:
	end_match(reason, is_victory, true)


# ================= 对局流程（死亡 / 复活 / 结算 / 选卡）=================
func _on_archer_died(victim: Archer, killer: Archer) -> void:
	spawn_burst(victim.position, victim.color, victim.radius)
	if game_mode == "pvp":
		var drops := 3 + victim.level
		for _i in drops:
			var p := victim.position + Vector2.from_angle(randf() * TAU) * randf_range(10.0, 65.0)
			spawn_orb(p, 10 if randf() < 0.6 else 15)
		spawn_heart(victim.position + Vector2(randf_range(-18, 18), randf_range(-18, 18)))
		if killer != null and killer.team_id > 0:
			team_scores[killer.team_id] = int(team_scores.get(killer.team_id, 0)) + 100

	var killer_name := killer.display_name if killer != null else ("算力怪潮" if game_mode == "survivor" else "算力坍缩圈")
	broadcast_feed("%s 击败了 %s" % [killer_name, victim.display_name])
	if killer != null and not killer.is_human() and killer.alive and randf() < 0.45:
		var kems := Archer.get_emotes_for(killer.char_id)
		if not kems.is_empty():
			broadcast_emote(killer.net_id, str(kems.pick_random()["text"]))

	# 联机 PVP：真人玩家死亡 3 秒后复活继续参战，直至时间结束决胜负！
	if net_role == "host" and game_mode == "pvp" and victim.is_human():
		victim.visible = false
		get_tree().create_timer(3.0, false).timeout.connect(func() -> void:
			if game_over or not is_instance_valid(victim):
				return
			victim.alive = true
			victim.downed = false
			victim.hp = victim.max_hp
			victim.shield = victim.max_shield
			victim.invuln = 2.6
			victim.position = _spawn_pos_for(victim.team_id)
			victim.visible = true
			spawn_burst(victim.position, victim.accent_color, 52.0)
		)
		return

	# PVE 双人合作：只有全队都倒下才团灭！
	if game_mode == "survivor" and is_coop:
		var any_alive := false
		for a in archers:
			if a != victim and a.alive and not a.downed and a.is_human():
				any_alive = true
				break
		if not any_alive:
			end_match("双人防线失守！共坚守 %d:%02d！" % [int(survived_sec) / 60, int(survived_sec) % 60], false)
		return

	archers.erase(victim)
	if victim == player:
		player.visible = false
		end_match("防线失守！被 %s 击败" % killer_name if game_mode == "survivor" else "你被 %s 击败了" % killer_name)
	else:
		var old_team := victim.team_id
		victim.queue_free()
		if fill_bots:
			get_tree().create_timer(3.5, false).timeout.connect(_spawn_bot.bind(old_team))


func end_match(reason: String, victory := false, from_net := false) -> void:
	if game_over:
		return
	game_over = true
	if net_role == "host" and not from_net and NetManager.inst != null:
		NetManager.inst.s2c_match_over.rpc(reason, [], victory)
	var rank := 1
	for a in archers:
		if a != player and a.score > player.score:
			rank += 1
	var total := archers.size() + (0 if (player != null and player.alive) else 1)
	var k_cnt := swarm.monster_kills if (game_mode == "survivor" and swarm != null) else (player.kills if player != null else 0)
	var p_tok := player.tokens if player != null else 0
	var cp_info := MetaSave.record_match_result(game_mode, difficulty_id, k_cnt, p_tok, survived_sec, victory, not autotest)
	hud.show_game_over(reason, rank, total, cp_info)
	if net_role == "offline":
		get_tree().paused = true
	if autotest:
		print("AUTOTEST END [%s/%s/%s/%s]: %s | Lv%d kills %d survived %.1fs | +CP %d (x%.1f) | evo %s | skills %s" % [
			game_mode, difficulty_id, player_char_id, player_weapon_id, reason, player.level, k_cnt, survived_sec, int(cp_info["earned"]), float(cp_info["mult"]), player.evolved_weapon, player.skills])
		get_tree().quit()


func queue_skill_pick() -> void:
	pending_picks += 1
	if pending_picks == 1:
		if net_role == "offline":
			get_tree().paused = true
		hud.show_skill_pick(Skills.choices(player, 3, game_mode))


func host_queue_client_pick(client_archer: Archer) -> void:
	if net_role != "host" or NetManager.inst == null:
		return
	client_archer.pending_net_picks += 1
	if client_archer.pending_net_picks == 1:
		var ch := Skills.choices(client_archer, 3, game_mode)
		_host_pending_choices[client_archer.net_id] = ch
		NetManager.inst.s2c_level_choices.rpc_id(client_archer.net_id, ch)


func host_apply_client_skill(peer_id: int, skill_id: String) -> void:
	var a := _find_archer_by_nid(peer_id)
	if a == null:
		return
	Skills.apply(a, skill_id)
	a.pending_net_picks = maxi(0, a.pending_net_picks - 1)
	if a.pending_net_picks > 0 and NetManager.inst != null:
		var ch := Skills.choices(a, 3, game_mode)
		_host_pending_choices[peer_id] = ch
		NetManager.inst.s2c_level_choices.rpc_id(peer_id, ch)


func host_reroll_client_skill(peer_id: int) -> void:
	var a := _find_archer_by_nid(peer_id)
	if a == null or NetManager.inst == null:
		return
	if a.net_rerolls > 0:
		a.net_rerolls -= 1
	elif a.tokens >= 50:
		a.tokens -= 50
	else:
		return
	var ch := Skills.choices(a, 3, game_mode)
	_host_pending_choices[peer_id] = ch
	NetManager.inst.s2c_level_choices.rpc_id(peer_id, ch)


func reroll_skill_choices() -> bool:
	if net_role == "client":
		if NetManager.inst != null:
			NetManager.inst.c2s_reroll_skill.rpc_id(1)
			Sfx.play("reroll", 0.04, 80, -8.0)
		return true
	if rerolls_left > 0:
		rerolls_left -= 1
	elif player.tokens >= 50:
		player.tokens -= 50
	else:
		return false
	Sfx.play("reroll", 0.04, 80, -8.0)
	hud.show_skill_pick(Skills.choices(player, 3, game_mode))
	return true


func open_token_chest(is_big: bool, opener: Archer = null) -> void:
	var target := opener if opener != null else player
	var reward_cnt := 3 if (is_big or randf() < 0.35) else 2
	var rewards := Skills.choices(target, reward_cnt, game_mode)
	for sid in rewards:
		Skills.apply(target, sid)
	# 双人合作：队友也同步吃满宝箱强化！
	if is_coop:
		for ally in archers:
			if ally != target and ally.alive and ally.is_human():
				var a_rews := Skills.choices(ally, reward_cnt, game_mode)
				for asid in a_rews:
					Skills.apply(ally, asid)
	var bonus_tokens := 120 if is_big else 80
	target.tokens += bonus_tokens
	target.score += bonus_tokens * 2
	Sfx.play("chest", 0.02, 120, -6.0)
	spawn_buff_aura(target, Color(1.0, 0.86, 0.30))
	if autotest or net_role != "offline":
		broadcast_banner("🎁 黄金 Token 宝箱开启！全队直获 %d 项强力增益！" % reward_cnt, Color(1.0, 0.88, 0.34))
		return
	get_tree().paused = true
	hud.show_chest_rewards(rewards, bonus_tokens)


func on_chest_closed() -> void:
	if pending_picks > 0:
		hud.show_skill_pick(Skills.choices(player, 3, game_mode))
	elif not game_over:
		get_tree().paused = false


func on_skill_chosen(id: String) -> void:
	if net_role == "client":
		if NetManager.inst != null:
			NetManager.inst.c2s_pick_skill.rpc_id(1, id)
		player.skills[id] = int(player.skills.get(id, 0)) + 1
		if id.begins_with("evo_"):
			player.evolved_weapon = id
		hud.hide_skill_pick()
		return
	Skills.apply(player, id)
	var s := Skills.info(id)
	var col := Skills.rarity_color(id)
	spawn_buff_aura(player, col)
	spawn_text(player.position + Vector2(0, -player.radius - 42), "获得增益：%s！" % s["name"], col, 22)
	pending_picks -= 1
	if pending_picks > 0:
		hud.show_skill_pick(Skills.choices(player, 3, game_mode))
	else:
		hud.hide_skill_pick()
		if not game_over:
			get_tree().paused = false


func ranking() -> Array[Archer]:
	var arr: Array[Archer] = archers.duplicate()
	if player != null and not player.alive and not arr.has(player):
		arr.append(player)
	arr.sort_custom(func(x: Archer, y: Archer) -> bool: return x.score > y.score)
	return arr


func team_ranking() -> Array[Dictionary]:
	var totals := {1: 0, 2: 0, 3: 0, 4: 0}
	for tid in [1, 2, 3, 4]:
		totals[tid] = int(team_scores.get(tid, 0))
	for a in archers:
		if a.team_id >= 1 and a.team_id <= 4:
			totals[a.team_id] = int(totals[a.team_id]) + a.score
	var out: Array[Dictionary] = []
	for tid in [1, 2, 3, 4]:
		out.append({"team": tid, "name": NetManager.TEAM_NAMES[tid], "score": int(totals[tid]), "color": NetManager.TEAM_COLORS[tid]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["score"]) > int(y["score"]))
	return out


# ================= 查询 / 碰撞 / 寻路工具 =================
func find_nearest_enemy(a: Archer, max_range: float) -> Archer:
	var best: Archer = null
	var bd := max_range * max_range
	for o in archers:
		if o == a or not o.alive or o.downed or a.is_ally(o):
			continue
		var d := a.position.distance_squared_to(o.position)
		if d < bd:
			bd = d
			best = o
	return best


func find_bounce_target(from: Vector2, max_range: float, exclude: Array[Archer], shooter: Archer) -> Archer:
	var best: Archer = null
	var bd := max_range * max_range
	for o in archers:
		if o == shooter or not o.alive or o.downed or exclude.has(o) or (shooter != null and shooter.is_ally(o)):
			continue
		var d := from.distance_squared_to(o.position)
		if d < bd:
			bd = d
			best = o
	return best


func in_arena(p: Vector2) -> bool:
	return absf(p.x) < ARENA_HALF and absf(p.y) < ARENA_HALF


func point_in_rock(p: Vector2, pad: float) -> bool:
	for r in rocks:
		var lim := r.z + pad
		if p.distance_squared_to(Vector2(r.x, r.y)) < lim * lim:
			return true
	return false


func point_in_wall(p: Vector2, pad := 0.0) -> bool:
	for w in walls:
		if w.grow(pad).has_point(p):
			return true
	return false


func bounce_normal_at(p: Vector2) -> Vector2:
	if p.x <= -ARENA_HALF:
		return Vector2.RIGHT
	if p.x >= ARENA_HALF:
		return Vector2.LEFT
	if p.y <= -ARENA_HALF:
		return Vector2.DOWN
	if p.y >= ARENA_HALF:
		return Vector2.UP
	for w in walls:
		if w.grow(10.0).has_point(p):
			var dl := absf(p.x - w.position.x)
			var dr := absf(p.x - w.end.x)
			var dt := absf(p.y - w.position.y)
			var db := absf(p.y - w.end.y)
			var mn := minf(minf(dl, dr), minf(dt, db))
			if mn == dl: return Vector2.LEFT
			if mn == dr: return Vector2.RIGHT
			if mn == dt: return Vector2.UP
			return Vector2.DOWN
	for r in rocks:
		var c := Vector2(r.x, r.y)
		var d := p - c
		if d.length_squared() <= (r.z + 14.0) * (r.z + 14.0):
			return d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT
	return Vector2.ZERO


func resolve_position(a: Archer) -> void:
	var lim := ARENA_HALF - a.radius
	a.position = a.position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	# 「量子穿墙」加成：角色可直接穿过场内所有墙壁与障碍物（依然受限于外圈场地边界）！
	if a.phase_wall:
		return
	# 1. 圆 vs 矩形墙壁平滑滑动碰撞
	for w in walls:
		var cx := clampf(a.position.x, w.position.x, w.end.x)
		var cy := clampf(a.position.y, w.position.y, w.end.y)
		var closest := Vector2(cx, cy)
		var d := a.position - closest
		var d2 := d.length_squared()
		if d2 < a.radius * a.radius:
			if d2 > 0.0001:
				a.position = closest + (d / sqrt(d2)) * a.radius
			else:
				var n := bounce_normal_at(a.position)
				a.position += n * a.radius
	# 2. 圆 vs 圆形像素障碍物碰撞
	for r in rocks:
		var c := Vector2(r.x, r.y)
		var d := a.position - c
		var min_d := r.z + a.radius
		var d2 := d.length_squared()
		if d2 < min_d * min_d:
			a.position = c + ((d / sqrt(d2)) if d2 > 0.0001 else Vector2.RIGHT) * min_d


func steer(p: Vector2, dir: Vector2, radius: float) -> Vector2:
	var out := dir
	for r in rocks:
		var to_c := Vector2(r.x, r.y) - p
		var lim := r.z + radius + 72.0
		if to_c.length_squared() < lim * lim and to_c.dot(dir) > 0.0:
			var side := dir.orthogonal()
			if side.dot(to_c) > 0.0:
				side = -side
			out += side * 1.5
	# 墙壁前探平滑绕门（防 AI 顶墙卡住）
	var probe := p + dir * (radius + 54.0)
	if point_in_wall(probe, radius * 0.7):
		var left_v := dir.rotated(-1.15)
		var right_v := dir.rotated(1.15)
		var lb := point_in_wall(p + left_v * 80.0, radius)
		var rb := point_in_wall(p + right_v * 80.0, radius)
		if not lb and rb:
			out = left_v
		elif not rb and lb:
			out = right_v
		else:
			out = left_v if (p.x + p.y >= 0.0) else right_v
	return out.normalized() if out.length_squared() > 0.001 else dir


func random_free_point(margin: float, avoid_archers: bool) -> Vector2:
	var p := Vector2.ZERO
	for _i in 60:
		p = Vector2(randf_range(-ARENA_HALF + margin, ARENA_HALF - margin), randf_range(-ARENA_HALF + margin, ARENA_HALF - margin))
		if point_in_rock(p, 42.0) or point_in_wall(p, 42.0):
			continue
		if avoid_archers:
			var ok := true
			for a in archers:
				if a.position.distance_squared_to(p) < 520.0 * 520.0:
					ok = false
					break
			if not ok:
				continue
		return p
	return p
