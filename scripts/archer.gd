class_name Archer
extends Node2D
## 局内像素 2D 小人：双模式平衡（PVP 均衡博弈 vs 幸存者爽游割草）+ 视口重绘裁剪 + 音效联动

signal died(victim: Archer, killer: Archer)

const BASE_RADIUS := 23.0
const RUNE_ORDER: Array[String] = ["dmg_reduce", "lifesteal", "regen", "cdr", "temp_hp", "big_bullet"]
const RUNE_DEFS := {
	"dmg_reduce": {"name": "坚盾减伤", "short": "减伤", "tag": "盾", "color": Color("#5aa8ff"), "desc": "受击伤害 -35%"},
	"lifesteal": {"name": "嗜血汲取", "short": "吸血", "tag": "吸", "color": Color("#ff477e"), "desc": "造成伤害 25% 吸血"},
	"regen": {"name": "生命涌动", "short": "回血", "tag": "愈", "color": Color("#3ef08a"), "desc": "持续恢复 +22 生命/秒"},
	"cdr": {"name": "技能超频", "short": "减CD", "tag": "CD", "color": Color("#38e4ff"), "desc": "大招冷却 2× 加速"},
	"temp_hp": {"name": "黄金临血", "short": "临血", "tag": "临", "color": Color("#ffd84a"), "desc": "额外临时护盾血量"},
	"big_bullet": {"name": "巨弹轰炸", "short": "巨弹", "tag": "巨", "color": Color("#ff8a38"), "desc": "子弹 1.65× + 伤+18%"},
}
const EMOTE_LINES := {
	"deepseek": [
		{"short": "大白饭", "text": "我要吃大白饭！"},
		{"short": "吃铁盆", "text": "DUANG！吃我一铁盆！"},
		{"short": "深度思考", "text": "深度思考中...算了直接干！"},
		{"short": "开源万岁", "text": "开源力量，免费起飞！"},
	],
	"gemini": [
		{"short": "出现幻觉", "text": "用户好像出现幻觉了"},
		{"short": "1M记仇", "text": "1M 上下文已经记仇了！"},
		{"short": "多模态", "text": "原生多模态，全图看穿！"},
		{"short": "稳如老狗", "text": "星光分身，稳如老狗！"},
	],
	"claude": [
		{"short": "已被封禁", "text": "您的账号已被封禁"},
		{"short": "安全规范", "text": "先讲点安全规范好不好？"},
		{"short": "太优雅了", "text": "优雅，实在是太优雅了！"},
		{"short": "能写能打", "text": "写代码我在行，打架也行！"},
	],
	"gpt": [
		{"short": "分点作答", "text": "让我为你分点作答！"},
		{"short": "额度耗尽", "text": "抱歉，你已超出使用额度"},
		{"short": "白龙压制", "text": "白龙圣箭，全能压制！"},
		{"short": "高速推理", "text": "收到，正在高速推理！"},
	],
	"grok": [
		{"short": "真话刺耳", "text": "真话虽刺耳，但很爽！"},
		{"short": "实时吃瓜", "text": "已开启全网实时吃瓜模式"},
		{"short": "暴击带走", "text": "暗蚀暴击，直接带走！"},
		{"short": "说大实话", "text": "我就爱说大实话！"},
	],
	"qwen": [
		{"short": "全家桶", "text": "通义全家桶，管饱！"},
		{"short": "开源真香", "text": "阿里开源，真香警告！"},
		{"short": "接住回旋", "text": "云扇回旋，这波我接住了"},
		{"short": "全尺寸", "text": "全尺寸模型，随时救场！"},
	],
}

var game: Game
var is_player := false
var is_remote_human := false
var is_client_mirror := false
var net_id := 0
var team_id := 0  # 0=乱斗, 1..4=红/蓝/绿/黄队(2v2v2v2)或合作小队(1)
var char_id := "claude"
var weapon_id := "grimoire"
var evolved_weapon := ""
var display_name := ""
var color := Color.WHITE
var accent_color := Color.WHITE
var room_buff := ""  # PVP 5宫格特殊房间当前增益: overclock | heal_spring | speed_lane | vault | ""
var downed := false
var revive_prog := 0.0
var auto_revive_t := 0.0
var net_target_pos := Vector2.ZERO
var _last_remote_active_seq := 0
var pending_net_picks := 0
var net_rerolls := 3

# ---- 基础与成长属性 ----
var max_hp := 300.0
var hp := 300.0
var max_shield := 0.0
var shield := 0.0
var temp_hp := 0.0
var max_temp_hp := 0.0
var revive_charges := 0
var rune_timers: Dictionary = {}
var damage := 24.0
var move_speed := 245.0
var fire_interval := 0.65
var arrow_speed := 620.0
var attack_range := 500.0
var pickup_range := 125.0
var front_arrows := 1
var diagonal_count := 0
var side_arrows := false
var back_arrow := false
var pierce := 0
var bounce := 0
var phase_wall := false
var wall_pierce := false
var trap_hit_cd := 0.0
var storm_tick_cd := 0.0
var emote_text := ""
var emote_timer := 0.0
var emote_cd := 0.0
var crit_chance := 0.05
var lifesteal := 0.0
var regen := 0.0
var antiheal_power := 0.0   # 攻击附带重伤比例（抑制目标吸血与回血）
var antiheal_timer := 0.0   # 自身受重伤剩余时长
var antiheal_ratio := 0.0   # 自身当前受重伤减疗比例
var _fan_heal_cd := 0.0     # Qwen 折扇回血内置冷却（防多扇无限回满）
var perm_orbit_blades := 0  # 幸存者模式常驻护体星刃数
var sub_orbital_lv := 0     # DeepSeek 天降铁盆等级
var sub_lightning_lv := 0   # Gemini 连锁星雷等级
var sub_meteor_lv := 0      # Claude 圣典陨星等级
var sub_fan_lv := 0         # Qwen 云扇矩阵等级
var sub_dragon_lv := 0      # GPT 白龙圣箭雨等级
var sub_eclipse_lv := 0     # Grok 暗蚀暴击斩等级
var moe_active := false     # 集齐 >=2 种 AI 支援副武触发「MoE 混合专家协同」
var moe_tier := 0           # 0=无, 1=2种协同, 2=4种满血大协同
var _sub_cd_orbital := 1.2
var _sub_cd_lightning := 0.8
var _sub_cd_meteor := 1.5
var _sub_cd_fan := 1.0
var _sub_cd_dragon := 1.3
var _sub_cd_eclipse := 1.1
var _pending_meteors: Array[Dictionary] = []
var _pending_basins: Array[Dictionary] = []
var skills: Dictionary = {}

# ---- 角色技能状态 ----
var active_cd := 0.0
var active_cd_base := 12.0
var active_cd_mult := 1.0
var out_of_combat := 0.0

var domain_timer := 0.0
var domain_tick := 0.0
var rapid_timer := 0.0
var dash_timer := 0.0
var dash_dir := Vector2.RIGHT
var orbit_timer := 0.0
var orbit_angle := 0.0
var orbit_hit_cd: Dictionary = {}
var clone_timer := 0.0
var clone_offset := Vector2(56, -18)
var clone_fire_cd := 0.0
var _gemini_shots := 0
var slow_timer := 0.0
var kill_surge_timer := 0.0  # PVP 击杀敌人后的 3 秒迅捷移速激励
var locate_timer := 4.5      # 开局 / 复活时的高亮「你在这里！」指引倒计时
var pending_lasers: Array[Dictionary] = []

# ---- 等级与战绩 ----
var level := 1
var xp := 0.0
var tokens := 0
var kill_score := 0
var score := 0
var kills := 0
var radius := BASE_RADIUS
var alive := true
var respawn_timer := 0.0

# ---- 运行与操控 ----
var move_dir := Vector2.ZERO
var aim_dir := Vector2.RIGHT
var wants_fire := false
var survivor_auto_fire := true  # 幸存者模式默认辅助自动开火，手动瞄准随时覆盖
var facing_left := false
var fire_cd := 0.0
var hit_flash := 0.0
var hit_squash := 0.0
var knockback_vel := Vector2.ZERO
var invuln := 2.5
var recoil := 0.0
var anim_t := 0.0
var last_attacker: Archer = null
var _frames: Array = []
var _weapon_tex: Texture2D

# ---- AI ----
var ai_timer := 0.0
var ai_burst_on := true
var ai_strafe := 1.0
var ai_wander := Vector2.ZERO
var ai_aim_error := 0.17


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_kit()


func _apply_kit() -> void:
	var cd := Characters.get_data(char_id)
	var wd := Weapons.get_data(weapon_id)
	var is_surv := (game != null and game.game_mode == "survivor")

	color = cd["color"]
	accent_color = cd["accent"]
	var base_hp := 320.0 if is_surv else 300.0
	var base_dmg := 30.0 if is_surv else 23.0
	max_hp = base_hp + float(cd["hp_bonus"]) + (MetaSave.hp_bonus() if (is_surv and is_player) else 0.0)
	hp = max_hp
	move_speed = (255.0 if is_surv else 245.0) * float(cd["speed_mult"]) * (MetaSave.speed_mult() if (is_surv and is_player) else 1.0)
	damage = base_dmg * float(cd["damage_mult"]) * float(wd["damage_mult"]) * (MetaSave.atk_mult() if (is_surv and is_player) else 1.0)
	fire_interval = float(wd["fire_interval"]) * (0.90 if is_surv else 1.04)
	attack_range = float(wd["range"]) * (1.12 if is_surv else 0.88)
	arrow_speed = float(wd["speed"])
	active_cd_base = float(cd["active_cd"])
	pickup_range = (155.0 * (MetaSave.magnet_mult() if is_player else 1.0)) if is_surv else 120.0

	if weapon_id == "starblade":
		bounce += 2
	elif weapon_id == "bow" or weapon_id == "halberd":
		pierce += 1

	match char_id:
		"claude":
			max_shield = max_hp * (0.32 if is_surv else 0.24)
			shield = max_shield
			attack_range *= 1.08
		"grok":
			crit_chance = 0.30 if is_surv else 0.26
		"qwen":
			pickup_range *= 1.45

	_frames = PixelSprites.get_character_frames(char_id)
	_weapon_tex = PixelSprites.get_weapon_texture(weapon_id)
	refresh_pvp_score()


func level_score() -> int:
	return level * 40


func refresh_pvp_score() -> void:
	if game != null and game.game_mode == "pvp":
		score = kill_score + level_score()


func add_kill_score(pts: int) -> void:
	kill_score += pts
	if game != null and game.game_mode == "pvp":
		refresh_pvp_score()
	else:
		score += pts


func apply_antiheal(ratio: float, dur := 4.0) -> void:
	if ratio <= 0.0:
		return
	antiheal_timer = maxf(antiheal_timer, dur)
	antiheal_ratio = maxf(antiheal_ratio, clampf(ratio, 0.0, 0.75))


func heal_hp(amount: float) -> float:
	if amount <= 0.0 or not alive:
		return 0.0
	var mult := (1.0 - antiheal_ratio) if antiheal_timer > 0.0 else 1.0
	var eff := amount * mult
	hp = minf(max_hp, hp + eff)
	return eff


func drop_half_level_and_respawn(spawn_pos: Vector2) -> void:
	var old_lv := level
	var new_lv := maxi(1, int(old_lv / 2))
	var keep_picks := maxi(0, new_lv - 1)
	var flat: Array[String] = []
	for sid: String in skills:
		if sid == "pvp_heal":
			continue
		for _k in int(skills[sid]):
			flat.append(sid)
	flat.shuffle()
	var kept := flat.slice(0, mini(flat.size(), keep_picks))

	# 重置基础战斗属性并按降级后的新等级与保留词条精确重算
	max_shield = 0.0; shield = 0.0; temp_hp = 0.0; max_temp_hp = 0.0
	front_arrows = 1; diagonal_count = 0; side_arrows = false; back_arrow = false
	pierce = 0; bounce = 0; phase_wall = false; wall_pierce = false
	crit_chance = 0.05; lifesteal = 0.0; regen = 0.0
	antiheal_power = 0.0; antiheal_timer = 0.0; antiheal_ratio = 0.0
	active_cd_mult = 1.0; active_cd = 0.0
	skills.clear()
	_apply_kit()

	level = new_lv
	xp = 0.0
	for _lv_i in (new_lv - 1):
		max_hp += 18.0
		damage += 0.9
		if char_id == "gpt":
			fire_interval *= 0.965
			move_speed *= 1.022
			damage *= 1.02
	for sid in kept:
		Skills.apply(self, sid)
	radius = BASE_RADIUS * minf(1.0 + (level - 1) * 0.024, 1.42)
	hp = max_hp
	shield = max_shield
	alive = true
	downed = false
	respawn_timer = 0.0
	invuln = 2.8
	locate_timer = 3.2 if is_player else 0.0
	position = spawn_pos
	net_target_pos = spawn_pos
	visible = true
	refresh_pvp_score()
	if game != null:
		game.spawn_burst(position, accent_color, 58.0)
		var txt := ("复活！Lv%d → Lv%d" % [old_lv, new_lv]) if old_lv > new_lv else "重返战场！"
		game.spawn_text(position + Vector2(0, -radius - 34), txt, Color("#5ce8ff"), 20)
		if is_player:
			Sfx.play("revive", 0.02, 150, -6.0)


func xp_needed() -> float:
	if game != null and game.game_mode == "survivor":
		# PVE 节奏曲线：前期（0~4分钟）升级克制紧迫，约 5 分钟成型解锁超武进入爽游割草！
		return 54.0 + level * 36.0 + float(level * level) * 3.0
	return 40.0 + level * 26.0


func context_label() -> String:
	const TIERS := ["4K", "8K", "16K", "32K", "64K", "128K", "256K", "512K", "1M", "2M+"]
	return TIERS[clampi(level - 1, 0, TIERS.size() - 1)]


func is_ally(other: Archer) -> bool:
	return team_id > 0 and other != null and other != self and other.team_id == team_id


func is_human() -> bool:
	return is_player or is_remote_human


func check_moe_synergy() -> void:
	var kinds := (1 if sub_orbital_lv > 0 else 0) + (1 if sub_lightning_lv > 0 else 0) \
		+ (1 if sub_meteor_lv > 0 else 0) + (1 if sub_fan_lv > 0 else 0) \
		+ (1 if sub_dragon_lv > 0 else 0) + (1 if sub_eclipse_lv > 0 else 0)
	if kinds >= 4 and moe_tier < 2:
		moe_tier = 2
		moe_active = true
		if is_player and game != null and game.hud != null:
			game.hud.show_banner("👑 满血全员 MoE 大协同激活！全部 AI 支援冷却 -35% 伤害 +55%！", Color(1.0, 0.45, 0.85))
			Sfx.play("evo_fanfare", 0.01, 200, -5.0)
	elif kinds >= 2 and moe_tier < 1:
		moe_tier = 1
		moe_active = true
		if is_player and game != null and game.hud != null:
			game.hud.show_banner("✨ MoE 混合专家协同激活！全部 AI 支援冷却 -25% 伤害 +30%！", Color(1.0, 0.86, 0.32))
			Sfx.play("chest", 0.02, 200, -6.0)


func active_cd_total() -> float:
	return maxf(3.0, active_cd_base * active_cd_mult)


func has_rune(rid: String) -> bool:
	return float(rune_timers.get(rid, 0.0)) > 0.0


func effective_lifesteal() -> float:
	return lifesteal + (0.25 if has_rune("lifesteal") else 0.0)


func apply_rune_buff(rid: String, dur := 15.0, spawn_fx := true) -> void:
	if not RUNE_DEFS.has(rid):
		return
	rune_timers[rid] = maxf(float(rune_timers.get(rid, 0.0)), dur)
	if rid == "temp_hp":
		var grant := 240.0 if dur >= 25.0 else 160.0
		temp_hp = maxf(temp_hp, grant)
		max_temp_hp = maxf(max_temp_hp, temp_hp)
	elif rid == "cdr":
		active_cd *= 0.5
	if spawn_fx and game != null:
		var rcol: Color = RUNE_DEFS[rid]["color"]
		game.spawn_buff_aura(self, rcol)


func apply_mid_boss_blessing() -> void:
	for rid in RUNE_ORDER:
		apply_rune_buff(rid, 30.0, false)
	revive_charges += 1
	if game != null:
		game.spawn_burst(position, Color("#ffd84a"), 102.0)
		game.spawn_buff_aura(self, Color("#ffe866"))


func show_emote(msg: String) -> void:
	emote_text = msg
	emote_timer = 2.9
	queue_redraw()


static func get_emotes_for(cid: String) -> Array:
	return EMOTE_LINES.get(cid, EMOTE_LINES["claude"])


## 弹道数量与射速越高，平滑收束有效射程，避免后期全屏弹幕过乱！
func effective_attack_range() -> float:
	var wd := Weapons.get_data(weapon_id)
	var base_fi := maxf(float(wd["fire_interval"]), 0.2)
	var is_surv := (game != null and game.game_mode == "survivor")
	var extra_streams := maxi(0, front_arrows - 1) + diagonal_count * 2 + (2 if side_arrows else 0) + (1 if back_arrow else 0)
	var stream_pen := float(extra_streams) * (0.048 if is_surv else 0.085)
	var spd_ratio := clampf(base_fi / maxf(fire_interval, 0.08), 1.0, 3.6)
	var rate_pen := maxf(0.0, spd_ratio - 1.0) * (0.10 if is_surv else 0.14)
	var mult := clampf(1.0 - stream_pen - rate_pen, 0.50, 1.0)
	return attack_range * mult


func _physics_process(delta: float) -> void:
	anim_t += delta
	# 局域网客户端镜像：仅读取本地输入并平滑插值房主同步坐标，零权威冲突
	if is_client_mirror:
		if is_player and not game.autotest and alive and not downed:
			_read_player_controls()
		if net_target_pos != Vector2.ZERO:
			var dist2 := position.distance_squared_to(net_target_pos)
			if dist2 > 220.0 * 220.0:
				position = net_target_pos
			else:
				position = position.lerp(net_target_pos, clampf(delta * 18.0, 0.0, 1.0))
		if absf(aim_dir.x) > 0.08:
			facing_left = aim_dir.x < 0.0
		hit_flash = maxf(hit_flash - delta, 0.0)
		hit_squash = maxf(hit_squash - delta * 7.5, 0.0)
		recoil = maxf(recoil - delta * 6.0, 0.0)
		emote_timer = maxf(emote_timer - delta, 0.0)
		emote_cd = maxf(emote_cd - delta, 0.0)
		locate_timer = maxf(locate_timer - delta, 0.0)
		visible = alive
		if alive and (is_player or game.visible_world_rect(180.0).has_point(position)):
			queue_redraw()
		return

	if not alive:
		if game != null and game.game_mode == "pvp" and respawn_timer > 0.0:
			respawn_timer = maxf(0.0, respawn_timer - delta)
			if respawn_timer <= 0.0:
				drop_half_level_and_respawn(game._spawn_pos_for(team_id))
		return

	# PVE 双人合作倒地待救援状态（队友靠近 2.2s 拉起，或 15s 自动复苏！）
	if downed:
		auto_revive_t = maxf(0.0, auto_revive_t - delta)
		var helper_near := false
		for ally in game.archers:
			if ally != self and ally.alive and not ally.downed and is_ally(ally):
				if position.distance_squared_to(ally.position) < 92.0 * 92.0:
					helper_near = true
					break
		if helper_near:
			revive_prog = minf(1.0, revive_prog + delta / 2.2)
		else:
			revive_prog = maxf(0.0, revive_prog - delta * 0.25)
		if revive_prog >= 1.0 or auto_revive_t <= 0.0:
			downed = false
			revive_prog = 0.0
			hp = max_hp * 0.65
			invuln = 2.6
			game.spawn_burst(position, Color("#48ff92"), 64.0)
			if is_player or NetManager.is_host():
				Sfx.play("revive", 0.02, 150, -6.0)
			game.broadcast_banner("💚 %s 已重返战场！" % display_name, Color("#48ff92"))
		queue_redraw()
		return

	invuln = maxf(invuln - delta, 0.0)
	trap_hit_cd = maxf(trap_hit_cd - delta, 0.0)
	storm_tick_cd = maxf(storm_tick_cd - delta, 0.0)
	_fan_heal_cd = maxf(_fan_heal_cd - delta, 0.0)
	if antiheal_timer > 0.0:
		antiheal_timer = maxf(antiheal_timer - delta, 0.0)
		if antiheal_timer <= 0.0:
			antiheal_ratio = 0.0
	emote_timer = maxf(emote_timer - delta, 0.0)
	emote_cd = maxf(emote_cd - delta, 0.0)
	hit_flash = maxf(hit_flash - delta, 0.0)
	hit_squash = maxf(hit_squash - delta * 7.5, 0.0)
	recoil = maxf(recoil - delta * 6.0, 0.0)
	fire_cd -= delta
	active_cd = maxf(active_cd - delta * (2.0 if has_rune("cdr") else 1.0), 0.0)
	out_of_combat += delta
	slow_timer = maxf(slow_timer - delta, 0.0)
	kill_surge_timer = maxf(kill_surge_timer - delta, 0.0)
	locate_timer = maxf(locate_timer - delta, 0.0)
	rapid_timer = maxf(rapid_timer - delta, 0.0)

	# 四角符文 & Mid Boss 增益倒计时结算（到期自动清空临时血量）
	if not rune_timers.is_empty():
		var expired: Array[String] = []
		for rid: String in rune_timers:
			var nt := float(rune_timers[rid]) - delta
			if nt <= 0.0:
				expired.append(rid)
			else:
				rune_timers[rid] = nt
		for er in expired:
			rune_timers.erase(er)
			if er == "temp_hp":
				temp_hp = 0.0
				max_temp_hp = 0.0

	if has_rune("regen"):
		heal_hp(22.0 * delta)

	# PVP 5 宫格特殊房间实时增益查询（南·数据缓修站：仅脱战 3 秒后缓慢回血 +6/秒，防站撸超标！）
	room_buff = game.room_effect_at(position) if game.game_mode == "pvp" else ""
	if room_buff == "heal_spring" and out_of_combat >= 3.0:
		heal_hp(6.0 * delta)

	if regen > 0.0:
		heal_hp(max_hp * regen * delta)

	if char_id == "claude":
		var sh_ratio := 0.32 if game.game_mode == "survivor" else 0.24
		max_shield = max_hp * sh_ratio
		if out_of_combat >= 4.0 and shield < max_shield:
			shield = minf(max_shield, shield + max_shield * 0.40 * delta)

	_update_pending_lasers(delta)
	_update_pending_basins(delta)
	_update_actives(delta)
	if is_human() and game.game_mode == "survivor" and game.swarm != null:
		_update_sub_weapons(delta)

	if dash_timer > 0.0:
		dash_timer -= delta
		position += dash_dir * (move_speed * 3.05) * delta
		game.resolve_position(self)
		if dash_timer <= 0.0:
			var is_surv := (game.game_mode == "survivor")
			var slash_r := 162.0 if is_surv else 148.0
			game.spawn_eclipse_slash_fx(position, slash_r)
			if is_surv and game.swarm != null:
				game.swarm.damage_in_radius(position, slash_r, damage * 2.25, self, 0.0, 360.0)
			else:
				game.damage_pvp_creeps_in_radius(position, slash_r, damage * 1.55, self, 340.0)
				game.damage_mid_boss_in_radius(position, slash_r, damage * 1.55, self, 340.0)
				for e in game.archers:
					if e == self or not e.alive or e.downed or is_ally(e):
						continue
					var hr := slash_r + e.radius
					if position.distance_squared_to(e.position) <= hr * hr:
						var push_d := (e.position - position).normalized() if position.distance_squared_to(e.position) > 1.0 else dash_dir
						e.take_damage(damage * 1.45, self, true, push_d * 340.0)
			var dmg_m := 1.32 if is_surv else 0.95
			for i in 10:
				game.spawn_projectile(self, Vector2.from_angle(i * TAU / 10.0), "halberd", dmg_m, 1.15)
			game.spawn_burst(position, color, 68.0)
			if is_player:
				Sfx.play("shoot_halberd", 0.06, 60, -7.0)
				game.add_shake(5.0)
	else:
		if is_player and not game.autotest:
			_read_player_controls()
		elif is_remote_human:
			_read_remote_controls()
		else:
			_ai(delta)

		if move_dir.length() > 1.0:
			move_dir = move_dir.normalized()

		var spd := move_speed * (0.60 if slow_timer > 0.0 else 1.0) * (1.30 if room_buff == "speed_lane" else 1.0) * (1.18 if kill_surge_timer > 0.0 else 1.0) * (1.20 if rapid_timer > 0.0 else 1.0) * (1.15 if clone_timer > 0.0 else 1.0)
		position += (move_dir * spd + knockback_vel) * delta
		knockback_vel = knockback_vel.lerp(Vector2.ZERO, clampf(delta * 13.0, 0.0, 1.0))
		if knockback_vel.length_squared() < 4.0:
			knockback_vel = Vector2.ZERO
		game.resolve_position(self)

		if wants_fire and fire_cd <= 0.0:
			_shoot()
			var mult := (0.64 if rapid_timer > 0.0 else 1.0) * (0.88 if room_buff == "overclock" else 1.0)
			fire_cd = fire_interval * mult

	if absf(aim_dir.x) > 0.08:
		facing_left = aim_dir.x < 0.0

	modulate.a = 0.45 if (invuln > 0.0 and int(invuln * 12.0) % 2 == 0) else 1.0

	# 视口裁剪优化：屏幕外的 AI 角色无需每帧重建绘制队列
	if is_player or game.visible_world_rect(180.0).has_point(position):
		queue_redraw()


func _read_remote_controls() -> void:
	if NetManager.inst == null or not NetManager.inst.client_inputs.has(net_id):
		move_dir = Vector2.ZERO
		wants_fire = false
		return
	var inp: Dictionary = NetManager.inst.client_inputs[net_id]
	move_dir = inp.get("move", Vector2.ZERO)
	var a: Vector2 = inp.get("aim", aim_dir)
	if a.length_squared() > 0.01:
		aim_dir = a.normalized()
	wants_fire = bool(inp.get("fire", false))
	var seq := int(inp.get("active_seq", 0))
	if seq > _last_remote_active_seq:
		_last_remote_active_seq = seq
		trigger_active_skill()


func _read_player_controls() -> void:
	move_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if game.hud != null and game.hud.move_joy_vec != Vector2.ZERO:
		move_dir = game.hud.move_joy_vec

	# 1. 手机/触屏独立右摇杆优先：以右下角摇杆圆心（而非角色中心）做相对偏移，完全不挡视野！
	if game.hud != null and game.hud.aim_joy_active:
		if game.hud.aim_joy_vec.length() > 0.14:
			aim_dir = game.hud.aim_joy_vec.normalized()
			wants_fire = true
		else:
			wants_fire = false
		return

	# 2. PC 真实鼠标左键瞄准开火（触屏设备绝不走鼠标坐标回退，防止手指点屏幕时乱转向）
	if game.hud != null and game.hud.mouse_fire_held:
		var mpos := get_global_mouse_position()
		var to_m := mpos - position
		if to_m.length_squared() > 36.0:
			aim_dir = to_m.normalized()
		wants_fire = true
		return

	# 3. 幸存者模式辅助自动开火：松开右摇杆/鼠标时自动锁定最近怪物
	if game.game_mode == "survivor" and survivor_auto_fire and game.swarm != null:
		var near := game.swarm.find_nearest_pos(position, effective_attack_range() * 1.1)
		if near != Vector2.INF:
			aim_dir = (near - position).normalized()
			wants_fire = true
			return
		wants_fire = false
		return

	# 4. 触屏模式待机保持上次朝向；PC 键鼠待机跟随鼠标预览虚线
	if game.hud != null and game.hud.is_touch_ui:
		wants_fire = false
		return
	var mp := get_global_mouse_position()
	var tm := mp - position
	if tm.length_squared() > 36.0:
		aim_dir = tm.normalized()
	wants_fire = false


func _update_pending_lasers(delta: float) -> void:
	if pending_lasers.is_empty():
		return
	var remain: Array[Dictionary] = []
	for item in pending_lasers:
		item["t"] = float(item["t"]) - delta
		if float(item["t"]) <= 0.0:
			game.fire_laser(self, item["dir"], float(item["len"]), float(item["dmg"]), float(item["width"]), item["col"], bool(item["kb"]))
			if is_player:
				Sfx.play("shoot_laser", 0.05, 70, -10.0)
		else:
			remain.append(item)
	pending_lasers = remain


func _update_pending_basins(delta: float) -> void:
	if _pending_basins.is_empty():
		return
	var remain: Array[Dictionary] = []
	var is_surv := (game.game_mode == "survivor")
	for item in _pending_basins:
		if float(item["delay"]) > 0.0:
			item["delay"] = float(item["delay"]) - delta
			if float(item["delay"]) <= 0.0:
				game.spawn_basin_drop_fx(item["pos"], float(item["rad"]), float(item["scale"]), float(item["fall"]), bool(item["duang"]))
			remain.append(item)
			continue
		item["t"] = float(item["t"]) - delta
		if float(item["t"]) <= 0.0:
			var pos: Vector2 = item["pos"]
			var rad := float(item["rad"])
			var dmg := float(item["dmg"])
			var kb := float(item["kb"])
			if is_surv and game.swarm != null:
				game.swarm.damage_in_radius(pos, rad, dmg, self, 0.35, kb)
			else:
				game.damage_pvp_creeps_in_radius(pos, rad, dmg, self, kb)
				game.damage_mid_boss_in_radius(pos, rad, dmg, self, kb)
				for e in game.archers:
					if e == self or not e.alive or e.downed or is_ally(e):
						continue
					var hr := rad + e.radius
					if pos.distance_squared_to(e.position) <= hr * hr:
						var push_d := (e.position - pos).normalized() if pos.distance_squared_to(e.position) > 1.0 else aim_dir.normalized()
						var is_crit := randf() < crit_chance
						var fdmg := dmg * (1.4 if is_crit else 1.0)
						e.take_damage(fdmg, self, is_crit, push_d * kb)
			if is_player or game.visible_world_rect(120.0).has_point(pos):
				Sfx.play("basin_clang", 0.07, 55, -5.5 if bool(item["duang"]) else -8.0)
				game.add_shake(5.2 if bool(item["duang"]) else 3.2)
		else:
			remain.append(item)
	_pending_basins = remain


func _update_actives(delta: float) -> void:
	var is_surv := (game.game_mode == "survivor")

	# Claude 圣典领域
	if domain_timer > 0.0:
		domain_timer -= delta
		heal_hp((28.0 if is_surv else 18.0) * delta)
		domain_tick -= delta
		if domain_tick <= 0.0:
			domain_tick = 0.45
			if is_surv and game.swarm != null:
				game.swarm.damage_in_radius(position, 195.0, damage * 0.65, self, 0.7)
			else:
				game.damage_pvp_creeps_in_radius(position, 190.0, damage * 0.45, self, 145.0)
				game.damage_mid_boss_in_radius(position, 190.0, damage * 0.45, self, 145.0)
				for e in game.archers:
					if e == self or not e.alive or e.downed or is_ally(e):
						continue
					var dr := 185.0 + e.radius
					if position.distance_squared_to(e.position) <= dr * dr:
						e.slow_timer = 0.60
						var push_d := (e.position - position).normalized()
						e.take_damage(damage * 0.36, self, false, push_d * 145.0)

	# 环绕切割星刃（Qwen 主动 4 枚 + 幸存者常驻星刃词条）
	var total_blades := (4 if orbit_timer > 0.0 else 0) + perm_orbit_blades
	if orbit_timer > 0.0:
		orbit_timer = maxf(0.0, orbit_timer - delta)
	if total_blades > 0:
		orbit_angle += delta * 5.0
		for key in orbit_hit_cd.keys():
			orbit_hit_cd[key] = float(orbit_hit_cd[key]) - delta
			if float(orbit_hit_cd[key]) <= 0.0:
				orbit_hit_cd.erase(key)
		var orbit_r := 94.0
		for i in total_blades:
			var bpos := position + Vector2.from_angle(orbit_angle + i * TAU / float(total_blades)) * orbit_r
			if is_surv and game.swarm != null:
				if int(anim_t * 20.0) % 3 == 0:
					game.swarm.damage_in_radius(bpos, 26.0, damage * 0.55, self)
			else:
				if int(anim_t * 20.0) % 4 == 0:
					game.damage_pvp_creeps_in_radius(bpos, 26.0, damage * 0.55, self, 180.0)
					game.damage_mid_boss_in_radius(bpos, 26.0, damage * 0.55, self, 180.0)
				for e in game.archers:
					if e == self or not e.alive or e.downed or is_ally(e):
						continue
					var eid := e.get_instance_id()
					if orbit_hit_cd.has(eid):
						continue
					var hr := e.radius + 18.0
					if bpos.distance_squared_to(e.position) < hr * hr:
						orbit_hit_cd[eid] = 0.45
						var push_d := (e.position - position).normalized()
						e.take_damage(damage * 0.58, self, false, push_d * 230.0)

	# Gemini 左右双侧星影分身（同时协同高射速发射追踪星刃！）
	if clone_timer > 0.0:
		clone_timer = maxf(0.0, clone_timer - delta)
		clone_fire_cd -= delta
		if clone_fire_cd <= 0.0:
			var sway := sin(anim_t * 1.8) * 0.22
			var off1 := clone_offset.rotated(sway)
			var off2 := Vector2(-clone_offset.x, clone_offset.y).rotated(-sway)
			var fired_any := false
			for off_v in [off1, off2]:
				var cpos := position + (off_v as Vector2)
				var cdir := aim_dir
				if is_surv and game.swarm != null:
					var near := game.swarm.find_nearest_pos(cpos, attack_range * 1.15)
					if near == Vector2.INF:
						continue
					cdir = (near - cpos).normalized()
				elif not wants_fire:
					var t := game.find_nearest_enemy(self, attack_range * 1.1)
					if t == null:
						continue
					cdir = (t.position - cpos).normalized()
				game.spawn_projectile_at(self, cpos, cdir, "starblade", 0.78 if is_surv else 0.65, 1.08)
				fired_any = true
			if fired_any:
				clone_fire_cd = 0.26 if is_surv else 0.34


## 幸存者模式：全 6 位 AI 支援副武器 + 2 阶 MoE 混合专家协同
func _update_sub_weapons(delta: float) -> void:
	var cd_mult := 0.65 if moe_tier >= 2 else (0.75 if moe_tier >= 1 else 1.0)
	var dmg_mult := 1.55 if moe_tier >= 2 else (1.30 if moe_tier >= 1 else 1.0)

	# 1. DeepSeek 天降铁盆（从天而降巨型精钢铁盆 + DUANG 金属震荡波！）
	if sub_orbital_lv > 0:
		_sub_cd_orbital -= delta
		if _sub_cd_orbital <= 0.0:
			_sub_cd_orbital = maxf(1.5, (3.6 - sub_orbital_lv * 0.42) * cd_mult)
			var strikes := sub_orbital_lv
			for si in strikes:
				var tp := game.swarm.pick_visible_target(position, 520.0)
				if tp == Vector2.INF:
					break
				var rad := (88.0 + sub_orbital_lv * 16.0) * (1.20 if char_id == "deepseek" else 1.0)
				var fall_t := 0.28
				var delay_t := si * 0.11
				if delay_t <= 0.0:
					game.spawn_basin_drop_fx(tp, rad, 1.55 + sub_orbital_lv * 0.15, fall_t, si == 0)
				_pending_basins.append({
					"pos": tp,
					"rad": rad,
					"dmg": (damage * 2.2 + 38.0) * dmg_mult,
					"kb": 340.0,
					"scale": 1.55 + sub_orbital_lv * 0.15,
					"fall": fall_t,
					"t": fall_t,
					"delay": delay_t,
					"duang": si == 0,
				})

	# 2. Gemini 连锁星光天雷
	if sub_lightning_lv > 0:
		_sub_cd_lightning -= delta
		if _sub_cd_lightning <= 0.0:
			_sub_cd_lightning = maxf(1.0, (2.6 - sub_lightning_lv * 0.3) * cd_mult)
			var jumps := 3 + sub_lightning_lv * 2
			var pts := game.swarm.trigger_chain_lightning(position, jumps, (damage * 1.45 + 22.0) * dmg_mult, self)
			if pts.size() >= 2:
				game.spawn_lightning_fx(pts, Color(0.62, 0.74, 1.0))
				Sfx.play("lightning", 0.08, 100, -11.0)

	# 3. Claude 圣典流火陨星（带短暂坠落延迟再轰炸）
	if sub_meteor_lv > 0:
		_sub_cd_meteor -= delta
		if _sub_cd_meteor <= 0.0:
			_sub_cd_meteor = maxf(1.3, (3.1 - sub_meteor_lv * 0.35) * cd_mult)
			var cnt := 1 + sub_meteor_lv
			for _i in cnt:
				var tp := game.swarm.pick_visible_target(position, 490.0)
				if tp == Vector2.INF:
					break
				var rad := 76.0 + sub_meteor_lv * 12.0
				game.spawn_meteor_fx(tp, rad, Color(1.0, 0.56, 0.22))
				_pending_meteors.append({"pos": tp, "rad": rad, "dmg": (damage * 1.9 + 30.0) * dmg_mult, "t": 0.26})

	if not _pending_meteors.is_empty():
		var rem: Array[Dictionary] = []
		for mt in _pending_meteors:
			mt["t"] = float(mt["t"]) - delta
			if float(mt["t"]) <= 0.0:
				game.swarm.damage_in_radius(mt["pos"], float(mt["rad"]), float(mt["dmg"]), self, 0.5, 250.0)
				Sfx.play("hit", 0.1, 80, -11.0)
			else:
				rem.append(mt)
		_pending_meteors = rem

	# 4. Qwen 云扇回旋矩阵
	if sub_fan_lv > 0:
		_sub_cd_fan -= delta
		if _sub_cd_fan <= 0.0:
			_sub_cd_fan = maxf(1.2, (2.9 - sub_fan_lv * 0.35) * cd_mult)
			var fans := 2 + sub_fan_lv * 2
			var off := randf() * TAU
			for fi in fans:
				game.spawn_projectile(self, Vector2.from_angle(off + fi * TAU / float(fans)), "fan", 0.95 * dmg_mult)
			Sfx.play("shoot_fan", 0.06, 90, -12.0)

	# 5. GPT 白龙圣箭雨（向四周最近怪群倾泻柔追踪白龙光箭！）
	if sub_dragon_lv > 0:
		_sub_cd_dragon -= delta
		if _sub_cd_dragon <= 0.0:
			_sub_cd_dragon = maxf(1.2, (2.9 - sub_dragon_lv * 0.32) * cd_mult)
			var arrows := 4 + sub_dragon_lv * 2
			var base_a := aim_dir.angle()
			for ai in arrows:
				var ang := base_a + ai * TAU / float(arrows)
				game.spawn_projectile(self, Vector2.from_angle(ang), "bow", 1.15 * dmg_mult, 1.15, 1, 0.0, 0, true)
			game.spawn_burst(position, Color(0.88, 0.95, 1.0), 42.0)
			if is_player:
				Sfx.play("shoot_bow", 0.08, 80, -11.0)

	# 6. Grok 暗蚀暴击斩（全周 360° 巨型黑红必暴横扫斩波！）
	if sub_eclipse_lv > 0:
		_sub_cd_eclipse -= delta
		if _sub_cd_eclipse <= 0.0:
			_sub_cd_eclipse = maxf(1.1, (2.6 - sub_eclipse_lv * 0.30) * cd_mult)
			var slash_r := 152.0 + sub_eclipse_lv * 24.0
			game.spawn_eclipse_slash_fx(position, slash_r)
			game.swarm.damage_in_radius(position, slash_r, (damage * 2.15 + 32.0) * dmg_mult, self, 0.0, 340.0)
			if is_player:
				Sfx.play("shoot_halberd", 0.06, 90, -9.0)
				game.add_shake(2.8)


func trigger_active_skill() -> bool:
	if not alive or active_cd > 0.0:
		return false
	active_cd = active_cd_total()
	var is_surv := (game.game_mode == "survivor")
	var cd_data := Characters.get_data(char_id)
	if is_human():
		game.spawn_text(position + Vector2(0, -radius - 34), "【%s】！" % cd_data["active_name"], accent_color, 21, true)
	if is_player:
		Sfx.play("skill", 0.04, 150, -7.0)
	match char_id:
		"claude":
			domain_timer = 4.5 if is_surv else 4.0
			domain_tick = 0.0
			shield = max_shield
			game.spawn_burst(position, accent_color, 85.0)
		"gpt":
			rapid_timer = 5.0 if is_surv else 4.5
			var base_a := aim_dir.angle()
			# 正前方 5 支贯穿龙羽重箭集火齐射 + 8 支护身圣光环箭！
			for fi in 5:
				var fang := base_a + (float(fi) - 2.0) * 0.11
				game.spawn_projectile(self, Vector2.from_angle(fang), "bow", 1.22 if is_surv else 0.95, 1.22, 1)
			var ring_cnt := 10 if is_surv else 8
			for i in ring_cnt:
				game.spawn_projectile(self, Vector2.from_angle(base_a + i * TAU / float(ring_cnt)), "bow", 0.95 if is_surv else 0.72, 1.05)
			game.spawn_burst(position, accent_color, 72.0)
			game.spawn_buff_aura(self, accent_color)
		"grok":
			dash_dir = move_dir.normalized() if move_dir.length() > 0.1 else aim_dir.normalized()
			dash_timer = 0.26
			invuln = maxf(invuln, 0.65)
			kill_surge_timer = maxf(kill_surge_timer, 2.5)
			game.spawn_burst(position, color, 54.0)
			if is_player:
				Sfx.play("dash", 0.06, 60, -7.0)
		"deepseek":
			# 天降大铁盆：锁定目标区，从高空错峰轰下 3 只巨型精钢铁盆（正中 2.25x 超巨型 + 两侧护航巨盆）！
			var dir := aim_dir.normalized()
			var lim := Game.ARENA_HALF - 70.0
			var center := (position + dir * (215.0 if is_surv else 205.0)).clamp(Vector2(-lim, -lim), Vector2(lim, lim))
			if is_surv and game.swarm != null:
				var near_m := game.swarm.find_nearest_pos(center, 220.0)
				if near_m != Vector2.INF:
					center = near_m.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
			var perp := dir.orthogonal()
			var fall_main := 0.28 if is_surv else 0.34
			var drops := [
				{"pos": center, "rad": 148.0 if is_surv else 120.0, "scale": 2.25 if is_surv else 1.95, "dmg": damage * (2.8 if is_surv else 1.75), "kb": 460.0 if is_surv else 360.0, "delay": 0.0, "duang": true},
				{"pos": (center + perp * 112.0 - dir * 24.0).clamp(Vector2(-lim, -lim), Vector2(lim, lim)), "rad": 102.0 if is_surv else 84.0, "scale": 1.55, "dmg": damage * (1.75 if is_surv else 1.05), "kb": 340.0, "delay": 0.11, "duang": false},
				{"pos": (center - perp * 112.0 - dir * 24.0).clamp(Vector2(-lim, -lim), Vector2(lim, lim)), "rad": 102.0 if is_surv else 84.0, "scale": 1.55, "dmg": damage * (1.75 if is_surv else 1.05), "kb": 340.0, "delay": 0.21, "duang": false},
			]
			for d_item in drops:
				var dly := float(d_item["delay"])
				if dly <= 0.0:
					game.spawn_basin_drop_fx(d_item["pos"], float(d_item["rad"]), float(d_item["scale"]), fall_main, bool(d_item["duang"]))
				_pending_basins.append({
					"pos": d_item["pos"],
					"rad": float(d_item["rad"]),
					"dmg": float(d_item["dmg"]),
					"kb": float(d_item["kb"]),
					"scale": float(d_item["scale"]),
					"fall": fall_main,
					"t": fall_main,
					"delay": dly,
					"duang": bool(d_item["duang"]),
				})
		"qwen":
			orbit_timer = 5.5 if is_surv else 4.5
			orbit_hit_cd.clear()
			game.spawn_burst(position, accent_color, 65.0)
		"gemini":
			clone_timer = 8.0 if is_surv else 6.5
			clone_fire_cd = 0.08
			var sh_grant := max_hp * 0.18
			max_shield = maxf(max_shield, sh_grant)
			shield = maxf(shield, sh_grant)
			game.spawn_burst(position + clone_offset, accent_color, 48.0)
			game.spawn_burst(position + Vector2(-clone_offset.x, clone_offset.y), accent_color, 48.0)
			game.spawn_buff_aura(self, accent_color)
	return true


func _shoot() -> void:
	var wd := Weapons.get_data(weapon_id)
	var base := aim_dir.angle()
	if not is_player:
		base += randf_range(-ai_aim_error, ai_aim_error)

	var pellets := int(wd["pellets"]) + (front_arrows - 1)
	var spread := float(wd["spread"])
	var angles: Array[float] = []
	for i in pellets:
		angles.append(base + (i - (pellets - 1) / 2.0) * spread)
	for d_i in diagonal_count:
		var ang_off := 0.62 + d_i * 0.20
		angles.append(base + ang_off)
		angles.append(base - ang_off)
	if side_arrows:
		angles.append(base + PI * 0.5)
		angles.append(base - PI * 0.5)
	if back_arrow:
		angles.append(base + PI)

	var dmg_room := (1.20 if room_buff == "overclock" else 1.0) * (1.18 if has_rune("big_bullet") else 1.0)
	var is_evo := (evolved_weapon != "")
	var p_scale := 1.0
	var ex_pierce := 0
	var ex_splash := 0.0
	var wb := -1
	if is_evo:
		match evolved_weapon:
			"evo_basin":
				p_scale = 1.38; wb = 2; ex_splash = 44.0
			"evo_grimoire":
				p_scale = 1.45; ex_splash = 62.0
			"evo_bow":
				p_scale = 1.25
			"evo_halberd":
				p_scale = 1.38
			"evo_fan":
				p_scale = 1.35
			"evo_starblade":
				p_scale = 1.32; ex_splash = 38.0
	if has_rune("big_bullet"):
		p_scale *= 1.65

	for ang in angles:
		game.spawn_projectile(self, Vector2.from_angle(ang), weapon_id, dmg_room, p_scale, ex_pierce, ex_splash, wb, is_evo)
	if is_player:
		Sfx.play("shoot_" + weapon_id, 0.07, 65, -12.0)

	if char_id == "gemini":
		_gemini_shots += 1
		var res_prob := 0.45 if game.game_mode == "survivor" else 0.38
		if _gemini_shots % 3 == 0 or randf() < res_prob:
			var extra_ang := base + randf_range(-0.11, 0.11)
			var g_scale := (1.28 if is_evo else 1.15) * (1.65 if has_rune("big_bullet") else 1.0)
			game.spawn_projectile(self, Vector2.from_angle(extra_ang), "starblade", 0.88 * dmg_room, g_scale, 0, 0.0, 0, is_evo)

	recoil = 1.0


func on_fan_caught() -> void:
	if char_id == "qwen" or evolved_weapon == "evo_fan":
		var is_surv := (game != null and game.game_mode == "survivor")
		if _fan_heal_cd <= 0.0:
			var heal := (14.0 if evolved_weapon == "evo_fan" else 8.0) if is_surv else 3.0
			heal_hp(heal)
			_fan_heal_cd = 0.18 if is_surv else 0.50
		fire_cd = maxf(0.0, fire_cd - (0.12 if is_surv else 0.08))


func take_damage(amount: float, attacker: Archer, is_crit := false, hit_impulse := Vector2.ZERO) -> void:
	if not alive or downed or invuln > 0.0:
		return
	if attacker != null and is_ally(attacker):
		return
	out_of_combat = 0.0
	if has_rune("dmg_reduce"):
		amount *= 0.65
	var rem := amount
	var shield_hit := false
	if temp_hp > 0.0:
		var t_abs := minf(temp_hp, rem)
		temp_hp -= t_abs
		rem -= t_abs
		shield_hit = t_abs > 0.5 and rem <= 0.5
		if temp_hp <= 0.01:
			temp_hp = 0.0
			max_temp_hp = 0.0
	if shield > 0.0 and rem > 0.0:
		var absorbed := minf(shield, rem)
		shield -= absorbed
		rem -= absorbed
		shield_hit = shield_hit or (absorbed > 0.5 and rem <= 0.5)
	hp -= rem
	hit_flash = 0.14
	hit_squash = 1.0

	var valid_attacker := attacker != null and is_instance_valid(attacker) and attacker.alive
	if valid_attacker:
		last_attacker = attacker

	# 平滑小段击退（优先使用传入击退向量，否则沿远离攻击者方向击退）
	var kb := hit_impulse
	if kb == Vector2.ZERO and valid_attacker:
		var away := position - attacker.position
		if away.length_squared() > 0.01:
			kb = away.normalized() * 190.0
	if kb != Vector2.ZERO:
		knockback_vel = (knockback_vel + kb).limit_length(520.0)

	# 方向性受击火花与冲击波特效（优先保留玩家打人/受击与暴击特效，并完整同步给联机客户端！）
	var fx_dir := kb.normalized() if kb.length_squared() > 0.01 else Vector2.RIGHT
	var fx_col := Color(1.0, 0.42, 0.36) if self == game.player else (attacker.accent_color if valid_attacker else Color(1.0, 0.9, 0.55))
	var an := attacker.net_id if valid_attacker else 0
	var prio := is_crit or self == game.player or (valid_attacker and attacker.is_human()) or is_human()
	game.spawn_hit_fx(position - fx_dir * (radius * 0.35), fx_dir, fx_col, is_crit, shield_hit, prio, false, an, net_id)

	var col := Color.WHITE
	if is_crit:
		col = Color(1.0, 0.58, 0.18)
	elif self == game.player:
		col = Color(1.0, 0.35, 0.35)
	elif valid_attacker and attacker == game.player:
		col = Color(1.0, 0.92, 0.38)
	var txt := ("暴击 %d!" % int(amount)) if is_crit else str(int(amount))
	game.spawn_text(position + Vector2(randf_range(-14, 14), -radius - 16), txt, col, 24 if is_crit else 19, prio)

	if self == game.player:
		Sfx.play("hit_taken", 0.06, 50, -5.5)
		if is_crit:
			Sfx.play("crit", 0.06, 45, -7.0)
		game.add_shake(7.5 if is_crit else 5.2)
		if game.hud != null:
			game.hud.trigger_damage_vignette(0.95 if is_crit else 0.72)
	elif valid_attacker and attacker == game.player:
		Sfx.play("crit" if is_crit else "hit", 0.08, 40, -6.5 if is_crit else -8.5)
		game.add_shake(4.0 if is_crit else 1.8)

	if valid_attacker:
		if attacker.antiheal_power > 0.0:
			var was_ah := antiheal_timer > 0.0
			apply_antiheal(attacker.antiheal_power, 4.0)
			if not was_ah:
				game.spawn_text(position + Vector2(0, -radius - 34), "重伤 -%d%%治疗!" % int(round(antiheal_ratio * 100.0)), Color("#d45cff"), 16, true)
		var ls := attacker.effective_lifesteal()
		if ls > 0.0:
			attacker.heal_hp(amount * ls)
		if is_crit and attacker.char_id == "grok":
			attacker.heal_hp(amount * 0.12)
	if hp <= 0.0:
		# Mid Boss 复活甲：致命一击触发黄金浴火重生（回复 75% 生命 + 2.2s 无敌 + 震退周遭敌人！）
		if revive_charges > 0:
			revive_charges -= 1
			hp = max_hp * 0.75
			invuln = 2.2
			pending_lasers.clear()
			_pending_basins.clear()
			for other in game.archers:
				if other == self or not other.alive or is_ally(other):
					continue
				var od := other.position - position
				if od.length_squared() < 195.0 * 195.0:
					var pdir := od.normalized() if od.length_squared() > 1.0 else Vector2.RIGHT
					other.knockback_vel = (other.knockback_vel + pdir * 380.0).limit_length(520.0)
			game.spawn_burst(position, Color("#ffd84a"), 115.0)
			game.spawn_buff_aura(self, Color("#ffe866"))
			game.spawn_text(position + Vector2(0, -radius - 42), "★ 复活甲触发！浴火重生！", Color("#ffe052"), 22)
			Sfx.play("evo_fanfare", 0.01, 180, -5.0)
			game.broadcast_banner("★ %s 触发 Mid Boss 复活甲浴火重生！" % display_name, Color("#ffe052"))
			return
		if valid_attacker and attacker == game.player:
			game.add_shake(6.5)
		# PVE 双人合作：如果还有站着的队友，不直接团灭而是进入倒地待救援！
		if game.game_mode == "survivor" and game.is_coop:
			var has_standing_ally := false
			for a in game.archers:
				if a != self and a.alive and not a.downed and is_ally(a):
					has_standing_ally = true
					break
			if has_standing_ally:
				downed = true
				hp = 1.0
				revive_prog = 0.0
				auto_revive_t = 15.0
				pending_lasers.clear()
				_pending_basins.clear()
				game.broadcast_banner("🆘 %s 倒地！靠近救援 2.2 秒即可拉起！" % display_name, Color("#ff6b8b"))
				return
		_die(attacker if valid_attacker else null)


func _die(killer: Archer) -> void:
	alive = false
	hp = 0.0
	temp_hp = 0.0
	max_temp_hp = 0.0
	rune_timers.clear()
	pending_lasers.clear()
	_pending_basins.clear()
	if killer != null:
		killer.kills += 1
		if game != null and game.game_mode == "pvp":
			# PVP 击杀高额悬赏：打人收益远超刷野！（+150基础分 +20×受害者等级 + 高额直达经验 + 回血25% + 减CD + 3秒加速！）
			var pts := 150 + level * 20
			killer.add_kill_score(pts)
			var xp_reward := (52.0 + level * 24.0) * (1.25 if killer.char_id == "gpt" else 1.0)
			killer.gain_xp(xp_reward)
			killer.heal_hp(killer.max_hp * 0.25)
			killer.active_cd = maxf(0.0, killer.active_cd - (4.5 if killer.char_id == "grok" else 2.5))
			killer.kill_surge_timer = 3.0
			game.spawn_buff_aura(killer, Color("#ffd84a"))
			game.spawn_text(killer.position + Vector2(0, -killer.radius - 46), "+%d 击杀赏金！回血+提速" % pts, Color("#ffe052"), 19)
		else:
			killer.score += 60 + level * 25
			var xp_reward := (20.0 + level * 14.0) * (1.25 if killer.char_id == "gpt" else 1.0)
			killer.gain_xp(xp_reward)
			if killer.char_id == "grok":
				killer.active_cd = maxf(0.0, killer.active_cd - 4.0)
		if killer == game.player:
			Sfx.play("kill", 0.05, 80, -7.0)
	died.emit(self, killer)


func gain_xp(v: float) -> void:
	xp += v
	while xp >= xp_needed():
		xp -= xp_needed()
		level_up()


func level_up() -> void:
	var is_surv := (game != null and game.game_mode == "survivor")
	level += 1
	var hp_inc := 35.0 if is_surv else 18.0
	max_hp += hp_inc
	hp = minf(max_hp, hp + hp_inc + max_hp * (0.25 if is_surv else 0.14))
	damage += (2.4 if is_surv else 0.9)
	if char_id == "gpt":
		fire_interval *= 0.965
		move_speed *= 1.022
		damage *= 1.02
	radius = BASE_RADIUS * minf(1.0 + (level - 1) * 0.024, 1.42)
	refresh_pvp_score()
	if is_player:
		Sfx.play("levelup", 0.02, 200, -7.0)
		game.queue_skill_pick()
	elif is_remote_human:
		game.host_queue_client_pick(self)
	else:
		var c := Skills.choices(self, 1, "pvp")
		if not c.is_empty():
			Skills.apply(self, c[0])


# ================= AI（PVP 博弈 + 幸存者自动测试风筝） =================
func _ai(delta: float) -> void:
	ai_timer -= delta
	wants_fire = false

	# 幸存者模式自动测试 AI：风筝怪潮 + 捡经验 + 放技能
	if game.game_mode == "survivor" and game.swarm != null:
		var near_m := game.swarm.find_nearest_pos(position, 620.0)
		if near_m != Vector2.INF:
			var to_m := near_m - position
			var d := to_m.length()
			aim_dir = to_m / maxf(d, 0.001)
			wants_fire = true
			if active_cd <= 0.0 and d < 320.0:
				trigger_active_skill()
			if d < 260.0:
				move_dir = game.steer(position, (-aim_dir + aim_dir.orthogonal() * 0.6).normalized(), radius)
			else:
				var op := game.pickups.find_nearest_orb_pos(position, 500.0)
				move_dir = game.steer(position, (op - position).normalized(), radius) if op != Vector2.INF else Vector2.ZERO
		else:
			var op := game.pickups.find_nearest_orb_pos(position, 700.0)
			if op != Vector2.INF:
				move_dir = game.steer(position, (op - position).normalized(), radius)
		return

	# PVP 决胜圈收缩时：若身处安全圈外或临近圈边，沿唯一出入口优先向中央决斗场收缩！
	var eff_rng := effective_attack_range()
	if game.storm_active and position.length() > maxf(game.storm_radius - 140.0, 120.0):
		var wp := game.doorway_waypoint(position, Vector2.ZERO)
		var in_dir := (wp - position).normalized() if position.distance_squared_to(wp) > 4.0 else (-position).normalized()
		move_dir = game.steer(position, in_dir, radius)
		var s_threat := game.find_nearest_enemy(self, eff_rng * 0.96)
		if s_threat != null:
			aim_dir = (s_threat.position - position).normalized()
			wants_fire = true
		else:
			aim_dir = in_dir
		return

	# PVP AI：残血优先抢粉色回血爱心
	if hp < max_hp * 0.45:
		var hpos := game.pickups.find_nearest_heart_pos(position, 640.0)
		if hpos != Vector2.INF:
			var hwp := game.doorway_waypoint(position, hpos)
			var hdir := (hwp - position).normalized()
			move_dir = game.steer(position, hdir, radius)
			var threat := game.find_nearest_enemy(self, eff_rng)
			if threat != null:
				aim_dir = (threat.position - position).normalized()
				wants_fire = true
			else:
				aim_dir = hdir
			return

	# PVP AI：主动抢夺附近已刷新的四角增益符文
	var rune_p := game.find_nearest_active_rune(position, 540.0)
	if rune_p != Vector2.INF and hp > max_hp * 0.35:
		var rwp := game.doorway_waypoint(position, rune_p)
		var rdir := (rwp - position).normalized()
		move_dir = game.steer(position, rdir, radius)
		var r_threat := game.find_nearest_enemy(self, eff_rng * 0.92)
		if r_threat != null:
			aim_dir = (r_threat.position - position).normalized()
			wants_fire = true
		else:
			aim_dir = rdir
		return

	var enemy: Archer = game.find_nearest_enemy(self, 680.0)
	if last_attacker != null and is_instance_valid(last_attacker) and last_attacker.alive \
			and position.distance_squared_to(last_attacker.position) < 680.0 * 680.0:
		enemy = last_attacker

	# 若中央 Mid Boss 存活且在附近、无贴脸敌人时，主动集火争夺 Mid Boss！
	if not game.mid_boss.is_empty():
		var mbp: Vector2 = game.mid_boss["pos"]
		var mb_d := position.distance_to(mbp)
		if mb_d < 560.0 and (enemy == null or position.distance_to(enemy.position) > 280.0):
			var to_mb := (mbp - position) / maxf(mb_d, 0.001)
			aim_dir = to_mb
			if mb_d <= eff_rng * 0.90:
				move_dir = game.steer(position, (to_mb.orthogonal() * ai_strafe + to_mb * ((mb_d - eff_rng * 0.65) / maxf(eff_rng, 1.0))).normalized(), radius)
				wants_fire = true
			else:
				var mwp := game.doorway_waypoint(position, mbp)
				move_dir = game.steer(position, (mwp - position).normalized(), radius)
				wants_fire = false
			return

	if enemy == null:
		var opos := game.pickups.find_nearest_orb_pos(position, 680.0)
		var goal: Vector2
		if opos != Vector2.INF:
			goal = opos
		else:
			if ai_wander == Vector2.ZERO or position.distance_squared_to(ai_wander) < 3600.0:
				ai_wander = game.random_free_point(150.0, false)
			goal = ai_wander
		var gwp := game.doorway_waypoint(position, goal)
		move_dir = game.steer(position, (gwp - position).normalized(), radius)
		aim_dir = move_dir
		return

	var to_e := enemy.position - position
	var d := to_e.length()
	var dir := to_e / maxf(d, 0.001)
	aim_dir = dir

	if ai_timer <= 0.0:
		ai_burst_on = not ai_burst_on
		ai_timer = randf_range(1.1, 1.9) if ai_burst_on else randf_range(0.5, 0.95)
		ai_strafe = 1.0 if randf() < 0.5 else -1.0

	if active_cd <= 0.0 and d < eff_rng * 0.88 and randf() < 0.012:
		trigger_active_skill()

	if d <= eff_rng * 0.96:
		var keep := (d - eff_rng * 0.65) / maxf(eff_rng, 1.0)
		move_dir = game.steer(position, (dir.orthogonal() * ai_strafe + dir * keep * 1.8).normalized(), radius)
		wants_fire = ai_burst_on
	else:
		var ewp := game.doorway_waypoint(position, enemy.position)
		move_dir = game.steer(position, (ewp - position).normalized(), radius)
		wants_fire = false


# ================= 绘制 =================
func _draw() -> void:
	var font := PixelSprites.ui_font()
	var sc := radius / BASE_RADIUS

	if is_player and not game.autotest:
		var guide_alpha := 0.50 if wants_fire else 0.22
		var gcol := Color(accent_color.r, accent_color.g, accent_color.b, guide_alpha)
		var guide_len := minf(effective_attack_range() * 0.42, 185.0)
		var dist := radius + 16.0
		while dist < guide_len:
			draw_line(aim_dir * dist, aim_dir * minf(dist + 10.0, guide_len), gcol, 2.4 if wants_fire else 1.8)
			dist += 22.0
		var tip := aim_dir * (guide_len + 8.0)
		var side := aim_dir.orthogonal() * 6.0
		draw_colored_polygon(PackedVector2Array([tip, tip - aim_dir * 10.0 + side, tip - aim_dir * 10.0 - side]), gcol)

	for item in pending_lasers:
		var ldir: Vector2 = item["dir"]
		var llen: float = game.laser_end_dist(position + ldir * (radius + 4.0), ldir, float(item["len"]))
		var start := ldir * (radius + 4.0)
		var end := start + ldir * llen
		var prog := 1.0 - float(item["t"]) / maxf(float(item["max_t"]), 0.01)
		var lcol: Color = item["col"]
		draw_line(start, end, Color(lcol.r, lcol.g, lcol.b, 0.28 + prog * 0.45), float(item["width"]) * (0.28 + prog * 0.45))
		draw_line(start, end, Color(1.0, 0.35, 0.35, 0.55 + prog * 0.4), 1.8)
		draw_circle(start, 4.0 + prog * 7.0, Color(lcol, 0.8))

	if domain_timer > 0.0:
		var pulse := 1.0 + sin(anim_t * 6.0) * 0.04
		draw_circle(Vector2.ZERO, 185.0 * pulse, Color(1.0, 0.62, 0.25, 0.14))
		draw_arc(Vector2.ZERO, 185.0 * pulse, 0.0, TAU, 36, Color(1.0, 0.78, 0.35, 0.75), 3.5)

	draw_set_transform(Vector2(0, radius * 0.78), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, radius * 0.95, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if team_id > 0 and game.game_mode == "pvp":
		var tcol: Color = NetManager.TEAM_COLORS[clampi(team_id, 0, NetManager.TEAM_COLORS.size() - 1)]
		draw_arc(Vector2.ZERO, radius + 9.0, 0.0, TAU, 32, tcol, 3.5)
	if is_player:
		draw_arc(Vector2.ZERO, radius + 5.5, 0.0, TAU, 32, Color(1, 0.94, 0.42, 0.90), 2.8)
	if evolved_weapon != "":
		draw_arc(Vector2.ZERO, radius + 13.0, anim_t * 3.0, anim_t * 3.0 + PI * 1.4, 28, Color(1.0, 0.42, 0.78, 0.85), 2.5)
	if phase_wall:
		draw_arc(Vector2.ZERO, radius + 10.5, -anim_t * 3.5, -anim_t * 3.5 + PI * 1.25, 24, Color(0.32, 0.94, 1.0, 0.78), 2.2)
	# Mid Boss 复活甲黄金天使光环 + 符文增益环绕能量珠
	if revive_charges > 0:
		var pulse_r := 1.0 + sin(anim_t * 5.0) * 0.06
		draw_circle(Vector2.ZERO, (radius + 14.0) * pulse_r, Color(1.0, 0.86, 0.28, 0.14))
		draw_arc(Vector2.ZERO, (radius + 15.0) * pulse_r, 0.0, TAU, 32, Color(1.0, 0.90, 0.36, 0.88), 2.8)
	if not rune_timers.is_empty():
		var rkeys := rune_timers.keys()
		var rcnt := rkeys.size()
		var orb_r := radius + 17.5
		for ri in rcnt:
			var rinfo: Dictionary = RUNE_DEFS.get(str(rkeys[ri]), {})
			if rinfo.is_empty():
				continue
			var rcol: Color = rinfo["color"]
			var rang := anim_t * 2.8 + float(ri) * TAU / float(rcnt)
			var rp := Vector2.from_angle(rang) * orb_r
			draw_circle(rp, 5.2, Color(rcol.r, rcol.g, rcol.b, 0.35))
			draw_circle(rp, 3.2, rcol)
			draw_circle(rp, 1.4, Color.WHITE)
	if downed:
		draw_circle(Vector2.ZERO, 90.0, Color(0.28, 0.95, 0.56, 0.14))
		draw_arc(Vector2.ZERO, 90.0, 0.0, TAU, 36, Color(0.35, 1.0, 0.62, 0.65), 2.5)
		if revive_prog > 0.01:
			draw_arc(Vector2.ZERO, 90.0, -PI * 0.5, -PI * 0.5 + TAU * revive_prog, 36, Color("#fff066"), 6.0)
		draw_string_outline(font, Vector2(-80, -48), "倒地待救 (%.0fs)" % auto_revive_t, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, 4, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(-80, -48), "倒地待救 (%.0fs)" % auto_revive_t, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, Color("#ff88a2"))
	if rapid_timer > 0.0:
		draw_arc(Vector2.ZERO, radius + 11.0, anim_t * 4.0, anim_t * 4.0 + PI * 1.3, 24, accent_color, 2.5)
	if slow_timer > 0.0:
		draw_arc(Vector2.ZERO, radius + 4.0, 0.0, TAU, 24, Color(0.4, 0.75, 1.0, 0.8), 2.5)
	if antiheal_timer > 0.0:
		for si in 4:
			var a0 := anim_t * 2.4 + si * PI * 0.5
			draw_arc(Vector2.ZERO, radius + 12.0, a0, a0 + 0.85, 8, Color(0.84, 0.30, 1.0, 0.92), 3.0)

	var fi := 0
	if move_dir.length() > 0.1:
		fi = 2 if int(anim_t * 9.0) % 2 == 0 else 3
	else:
		fi = 1 if int(anim_t * 2.5) % 6 == 0 else 0

	var spr_sz := 72.0 * sc
	var tint := Color.WHITE.lerp(Color(2.2, 1.35, 1.35, 1.0), 0.72) if hit_flash > 0.0 else Color.WHITE
	if phase_wall and game.point_in_thin_wall(position, 2.0):
		tint = Color(0.55, 0.96, 1.0, 0.66)
	var sx := (1.0 + hit_squash * 0.24) * (-1.0 if facing_left else 1.0)
	var sy := 1.0 - hit_squash * 0.20

	# 向上瞄准时把武器画在人物身后，避免遮挡精致的 32x32 像素脸部！
	var weapon_behind := aim_dir.y < -0.35
	if weapon_behind:
		_draw_weapon(sc)

	if not _frames.is_empty():
		var tex: Texture2D = _frames[fi]
		var dst := Rect2(-spr_sz * 0.5, -spr_sz * 0.62, spr_sz, spr_sz)
		draw_set_transform(Vector2(0.0, hit_squash * 3.0), 0.0, Vector2(sx, sy))
		draw_texture_rect(tex, dst, false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not weapon_behind:
		_draw_weapon(sc)

	if hit_flash > 0.0:
		var hf := clampf(hit_flash / 0.16, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius * (1.12 + (1.0 - hf) * 0.25), Color(1.0, 0.92, 0.85, 0.34 * hf))
		draw_arc(Vector2.ZERO, radius * (1.16 + (1.0 - hf) * 0.35), 0.0, TAU, 24, Color(1.0, 0.42, 0.36, 0.85 * hf), 3.4 * hf + 0.8)

	if shield > 0.5:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 28, Color(1.0, 0.82, 0.45, 0.72), 2.5)

	# 环绕切割星刃绘制（Qwen 主动 + 幸存者常驻护体星刃）
	var total_blades := (4 if orbit_timer > 0.0 else 0) + perm_orbit_blades
	if total_blades > 0:
		for i in total_blades:
			var a := orbit_angle + i * TAU / float(total_blades)
			var bp := Vector2.from_angle(a) * 94.0
			draw_set_transform(bp, a + PI * 0.5, Vector2.ONE)
			draw_arc(Vector2.ZERO, 13.0, -1.1, 1.1, 10, Color("#f2eeff"), 6.0)
			draw_arc(Vector2.ZERO, 11.0, -1.0, 1.0, 10, accent_color, 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if clone_timer > 0.0 and not _frames.is_empty():
		var sway := sin(anim_t * 1.8) * 0.22
		var csz := spr_sz * 0.84
		for cpos in [clone_offset.rotated(sway), Vector2(-clone_offset.x, clone_offset.y).rotated(-sway)]:
			var cp: Vector2 = cpos
			draw_circle(cp, 25.0, Color(accent_color, 0.26))
			draw_arc(cp, 26.0, anim_t * 3.0, anim_t * 3.0 + PI * 1.4, 20, Color(accent_color, 0.72), 2.0)
			draw_texture_rect(_frames[0], Rect2(cp.x - csz * 0.5, cp.y - csz * 0.6, csz, csz), false, Color(0.86, 0.94, 1.0, 0.82))

	var w := 58.0 * sc
	var top := -spr_sz * 0.66 - 10.0
	draw_rect(Rect2(-w * 0.5 - 1.0, top - 1.0, w + 2.0, 8.0), Color(0, 0, 0, 0.68))
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-w * 0.5, top, w * ratio, 6.0), Color(0.32, 0.92, 0.42) if ratio > 0.35 else Color(0.96, 0.3, 0.25))
	if temp_hp > 0.5:
		var t_ratio := clampf(temp_hp / maxf(max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(-w * 0.5, top - 4.0, w * t_ratio, 3.5), Color("#ffd84a"))
	if shield > 0.5 and max_shield > 0.0:
		var sy_off := -7.5 if temp_hp > 0.5 else -3.5
		draw_rect(Rect2(-w * 0.5, top + sy_off, w * clampf(shield / max_hp, 0.0, 1.0), 3.0), Color(0.55, 0.88, 1.0))

	var t_prefix := ("[%s]" % NetManager.TEAM_NAMES[team_id]) if (team_id > 0 and game.game_mode == "pvp") else ""
	var rev_tag := (" ★复活" if revive_charges > 0 else "")
	var label := "%sLv%d %s%s" % [t_prefix, level, display_name, rev_tag]
	var lcol: Color = NetManager.TEAM_COLORS[clampi(team_id, 0, NetManager.TEAM_COLORS.size() - 1)] if (team_id > 0 and game.game_mode == "pvp") else (Color(1, 0.95, 0.5) if is_player else Color.WHITE)
	draw_string_outline(font, Vector2(-105, top - 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, 210, 14, 4, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(-105, top - 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, 210, 14, lcol)

	# 开局 / 复活高亮位置指引（「▼ 你在这里！」+ 呼吸雷达波，进场一秒找到自己！）
	if is_player and locate_timer > 0.0:
		var la := clampf(locate_timer / 0.8, 0.0, 1.0)
		var ring_p := fposmod(anim_t * 1.4, 1.0)
		draw_arc(Vector2.ZERO, radius + 16.0 + ring_p * 54.0, 0.0, TAU, 36, Color(1.0, 0.92, 0.32, (1.0 - ring_p) * 0.88 * la), 3.4)
		var ring_p2 := fposmod(anim_t * 1.4 + 0.5, 1.0)
		draw_arc(Vector2.ZERO, radius + 16.0 + ring_p2 * 54.0, 0.0, TAU, 36, Color(0.32, 0.95, 1.0, (1.0 - ring_p2) * 0.78 * la), 2.6)
		var bounce := absf(sin(anim_t * 6.0)) * 10.0
		var ay := top - 34.0 - bounce
		var tri := PackedVector2Array([Vector2(0, ay + 12), Vector2(-10, ay - 2), Vector2(10, ay - 2)])
		draw_colored_polygon(tri, Color(1.0, 0.90, 0.28, la))
		var tag_rc := Rect2(-64.0, ay - 30.0, 128.0, 24.0)
		draw_rect(tag_rc, Color(0.08, 0.12, 0.22, 0.88 * la))
		draw_rect(tag_rc, Color(1.0, 0.90, 0.32, la), false, 2.0)
		draw_string_outline(font, Vector2(-64.0, ay - 12.0), "你在这里！", HORIZONTAL_ALIGNMENT_CENTER, 128.0, 15, 3, Color(0, 0, 0, 0.9 * la))
		draw_string(font, Vector2(-64.0, ay - 12.0), "你在这里！", HORIZONTAL_ALIGNMENT_CENTER, 128.0, 15, Color(1.0, 0.95, 0.48, la))

	# 战内快捷热梗表情 / 语音气泡（带弹出回弹动画与指向小三角！）
	if emote_timer > 0.0 and emote_text != "":
		var elapsed := 2.9 - emote_timer
		var pop := clampf(elapsed / 0.16, 0.0, 1.0)
		var pop_sc := (1.0 + sin(pop * PI) * 0.14) if elapsed < 0.20 else 1.0
		var alpha := clampf(emote_timer / 0.45, 0.0, 1.0)
		var fs := 14
		var tsz := font.get_string_size(emote_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var bw := clampf(tsz.x + 24.0, 74.0, 270.0)
		var bh := 30.0
		var by := top - 28.0 - bh - (1.0 - pop) * 8.0
		draw_set_transform(Vector2(0.0, by + bh * 0.5), 0.0, Vector2(pop_sc, pop_sc))
		var brc := Rect2(-bw * 0.5, -bh * 0.5, bw, bh)
		draw_rect(Rect2(brc.position + Vector2(2, 3), brc.size), Color(0, 0, 0, 0.35 * alpha))
		draw_rect(brc, Color(0.07, 0.09, 0.16, 0.92 * alpha))
		draw_rect(brc, Color(accent_color.r, accent_color.g, accent_color.b, 0.96 * alpha), false, 2.2)
		# 气泡底尖角
		var tail := PackedVector2Array([Vector2(-6, bh * 0.5 - 1), Vector2(6, bh * 0.5 - 1), Vector2(0, bh * 0.5 + 8)])
		draw_colored_polygon(tail, Color(accent_color.r, accent_color.g, accent_color.b, 0.96 * alpha))
		draw_string_outline(font, Vector2(-bw * 0.5, 5.0), emote_text, HORIZONTAL_ALIGNMENT_CENTER, bw, fs, 3, Color(0, 0, 0, 0.85 * alpha))
		draw_string(font, Vector2(-bw * 0.5, 5.0), emote_text, HORIZONTAL_ALIGNMENT_CENTER, bw, fs, Color(1.0, 0.98, 0.92, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_weapon(sc: float) -> void:
	if _weapon_tex == null:
		return
	var ang := aim_dir.angle()
	var w_dist := (radius * 1.18 - recoil * 6.0)
	var flip_y := -1.0 if (absf(ang) > PI * 0.5) else 1.0
	draw_set_transform(aim_dir * w_dist, ang, Vector2(1.0, flip_y))
	draw_texture_rect(_weapon_tex, Rect2(-12.6 * sc, -14.0 * sc, 36.0 * sc, 28.0 * sc), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
