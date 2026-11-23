class_name Skills
extends RefCounted
## 双模式增益池：
## - PVP 竞技模式：精炼克制、讲究走位博弈
## - 算力潮汐（幸存者/双人合作模式）：全 6 位 AI 支援副武 + MoE 混合专家协同 + 6 把主武器「超武进化」！

const PVP_LIST: Array[Dictionary] = [
	{"id": "pvp_multishot", "name": "双重齐射", "desc": "正前方弹道 +1\n(单发伤 -26%，射程微缩)", "max": 1, "rarity": "epic", "icon": ">>"},
	{"id": "pvp_diagonal", "name": "斜翼补箭", "desc": "两侧 38° 额外齐射\n(单发伤 -14%，射程微缩)", "max": 1, "rarity": "epic", "icon": "<^>"},
	{"id": "pvp_phase_wall", "name": "量子穿墙", "desc": "角色化作量子幽影\n可直接穿过所有墙壁与障碍！", "max": 1, "rarity": "epic", "icon": "PHZ"},
	{"id": "pvp_wall_pierce", "name": "穿墙弹道", "desc": "子弹无视墙壁与障碍穿墙打击\n(穿墙伤 85%，穿透敌人 +1)", "max": 1, "rarity": "epic", "icon": "W->"},
	{"id": "pvp_pierce", "name": "穿透瞄准", "desc": "投射物穿透敌人 +1", "max": 1, "rarity": "rare", "icon": "==>"},
	{"id": "pvp_bounce", "name": "精准弹射", "desc": "命中后弹向附近敌人 +1", "max": 1, "rarity": "rare", "icon": "Z->"},
	{"id": "pvp_crit", "name": "会心一击", "desc": "暴击率 +10%（1.4倍伤）", "max": 2, "rarity": "rare", "icon": "*!*"},
	{"id": "pvp_atk", "name": "精准强化", "desc": "攻击力 +10%", "max": 3, "rarity": "common", "icon": "ATK"},
	{"id": "pvp_aspd", "name": "快速装填", "desc": "攻击速度 +10%\n(高射速小幅收束射程)", "max": 3, "rarity": "common", "icon": "SPD"},
	{"id": "pvp_cdr", "name": "技能冷却", "desc": "主动大招冷却 -12%", "max": 2, "rarity": "rare", "icon": "CD-"},
	{"id": "pvp_speed", "name": "轻盈步法", "desc": "移动速度 +8%", "max": 2, "rarity": "common", "icon": "RUN"},
	{"id": "pvp_hp", "name": "稳健体魄", "desc": "生命上限 +45 并回复", "max": 3, "rarity": "common", "icon": "+HP"},
	{"id": "pvp_heal", "name": "战术回复", "desc": "立即回复 40% 生命与护盾", "max": 99, "rarity": "common", "icon": "FIX"},
	{"id": "pvp_lifesteal", "name": "续航汲取", "desc": "造成伤害的 8% 转为生命", "max": 2, "rarity": "rare", "icon": "DRN"},
	{"id": "pvp_regen", "name": "缓慢再生", "desc": "每秒回复 1.4% 生命", "max": 2, "rarity": "common", "icon": "REG"},
	{"id": "pvp_range", "name": "远距视界", "desc": "射程 +14%，弹速 +8%", "max": 2, "rarity": "common", "icon": "RNG"},
]

const SURVIVOR_LIST: Array[Dictionary] = [
	# --- 全 6 位 AI 支援副武（集齐 2 种触发 MoE 协同，4 种以上触发满血全员大协同！）---
	{"id": "sub_orbital", "name": "DeepSeek·天降铁盆", "desc": "【AI支援副武】每3.6秒从天而降巨型铁盆 DUANG 震荡清群！\n(2种激活 MoE 协同 / 4种满血大协同)", "max": 3, "rarity": "epic", "icon": "DS"},
	{"id": "sub_lightning", "name": "Gemini·连锁星雷", "desc": "【AI支援副武】每2.4秒释放星雷连锁电击多怪\n(2种激活 MoE 协同 / 4种满血大协同)", "max": 3, "rarity": "epic", "icon": "GM"},
	{"id": "sub_meteor", "name": "Claude·圣典陨星", "desc": "【AI支援副武】每3.0秒坠落暖橙圣典火球轰炸\n(2种激活 MoE 协同 / 4种满血大协同)", "max": 3, "rarity": "epic", "icon": "CL"},
	{"id": "sub_fan_storm", "name": "Qwen·云扇矩阵", "desc": "【AI支援副武】每2.8秒向四周甩出穿透回旋折扇\n(2种激活 MoE 协同 / 4种满血大协同)", "max": 3, "rarity": "epic", "icon": "QW"},
	{"id": "sub_dragon_rain", "name": "GPT·白龙圣箭雨", "desc": "【AI支援副武】每2.9秒向四周倾泻追踪白龙光箭雨！\n(2种激活 MoE 协同 / 4种满血大协同)", "max": 3, "rarity": "epic", "icon": "GP"},
	{"id": "sub_eclipse_slash", "name": "Grok·暗蚀暴击斩", "desc": "【AI支援副武】每2.6秒横扫全周黑红暴击斩波强退怪群！\n(2种激活 MoE 协同 / 4种满血大协同)", "max": 3, "rarity": "epic", "icon": "GK"},

	# --- 爽游构筑词条（带对应武器超武合成提示）---
	{"id": "surv_multishot", "name": "狂暴多重", "desc": "正前方弹道 +1（最多叠4层，射程微缩）\n【龙羽光弓·超武素材】", "max": 4, "rarity": "epic", "icon": ">>>"},
	{"id": "surv_diagonal", "name": "斜向弹幕", "desc": "额外向两侧 42° 喷射火力\n(弹道过多时小幅收束射程)", "max": 2, "rarity": "epic", "icon": "<^>"},
	{"id": "surv_allaround", "name": "全向散射", "desc": "左右 90° + 背后 180° 全开火！\n(弹幕密集小幅收束射程)", "max": 1, "rarity": "epic", "icon": "<+>"},
	{"id": "surv_phase_wall", "name": "量子穿墙", "desc": "角色化作量子幽影\n可直接穿过所有障碍物风筝怪潮！", "max": 1, "rarity": "epic", "icon": "PHZ"},
	{"id": "surv_wall_pierce", "name": "穿墙弹道", "desc": "子弹无视障碍物直接穿墙\n并额外穿透怪物 +1！", "max": 1, "rarity": "rare", "icon": "W->"},
	{"id": "surv_orbit", "name": "护体星刃", "desc": "召唤 2 枚常驻环绕切割星刃！", "max": 3, "rarity": "epic", "icon": "O*O"},
	{"id": "surv_pierce", "name": "无限穿透", "desc": "投射物穿透数量 +2", "max": 3, "rarity": "rare", "icon": "==>"},
	{"id": "surv_bounce", "name": "连锁弹射", "desc": "命中后弹向附近敌人 +2\n【双子星刃·超武素材】", "max": 3, "rarity": "rare", "icon": "Z->"},
	{"id": "surv_crit", "name": "致命过载", "desc": "暴击率 +20%（2.0倍狂暴暴击）\n【暗蚀战戟·超武素材】", "max": 3, "rarity": "rare", "icon": "*!*"},
	{"id": "surv_atk", "name": "超频算力", "desc": "攻击力 +28%\n【奥术典籍·超武素材】", "max": 6, "rarity": "common", "icon": "ATK"},
	{"id": "surv_aspd", "name": "极速推理", "desc": "攻击速度 +24%\n【精钢铁盆·超武素材】", "max": 5, "rarity": "common", "icon": "SPD"},
	{"id": "surv_cdr", "name": "大招无双", "desc": "主动大招冷却 -24%", "max": 3, "rarity": "rare", "icon": "CD-"},
	{"id": "surv_magnet", "name": "Token磁铁", "desc": "Token 晶片拾取范围 +80%！\n【云纹折扇·超武素材】", "max": 3, "rarity": "rare", "icon": "MAG"},
	{"id": "surv_speed", "name": "凌波微步", "desc": "移动速度 +14%", "max": 3, "rarity": "common", "icon": "RUN"},
	{"id": "surv_hp", "name": "巨量扩容", "desc": "生命上限 +90 并回血", "max": 5, "rarity": "common", "icon": "+HP"},
	{"id": "surv_heal", "name": "瞬间满血", "desc": "立即回满全部生命与护盾", "max": 99, "rarity": "common", "icon": "FIX"},
	{"id": "surv_lifesteal", "name": "狂战吸血", "desc": "造成伤害的 14% 转为生命", "max": 3, "rarity": "rare", "icon": "DRN"},
	{"id": "surv_regen", "name": "纳米自愈", "desc": "每秒回复 2.6% 生命", "max": 3, "rarity": "common", "icon": "REG"},
]

## 6 把主武器专属「超武进化」（Lv6+ 且持有对应素材词条即可在升级/宝箱合成！）
const EVO_LIST: Array[Dictionary] = [
	{
		"id": "evo_basin", "weapon": "basin", "req": "surv_aspd",
		"name": "⚡满血R1·终极铁盆", "icon": "★盆", "rarity": "mythic", "max": 1,
		"desc": "【精钢铁盆超武进化】铁盆放大 1.38 倍、弹壁 +2，命中瞬间分裂 3 只弹射小铁盆连环 DUANG！",
	},
	{
		"id": "evo_grimoire", "weapon": "grimoire", "req": "surv_atk",
		"name": "⚡宪法圣典·超新星", "icon": "★典", "rarity": "mythic", "max": 1,
		"desc": "【奥术典籍超武进化】符文弹体积与溅射翻倍、穿透 +2、伤害 +45%，连环烈焰轰炸！",
	},
	{
		"id": "evo_bow", "weapon": "bow", "req": "surv_multishot",
		"name": "⚡白龙炽羽圣弓", "icon": "★弓", "rarity": "mythic", "max": 1,
		"desc": "【龙羽光弓超武进化】攻速 +32%、穿透 +3、弹道 +1，化作贯天金白龙羽光箭！",
	},
	{
		"id": "evo_halberd", "weapon": "halberd", "req": "surv_crit",
		"name": "⚡黑洞裂空战戟", "icon": "★戟", "rarity": "mythic", "max": 1,
		"desc": "【暗蚀战戟超武进化】一次劈出 5 道巨型黑金裂空斩，暴击 +25%、穿透 +2！",
	},
	{
		"id": "evo_fan", "weapon": "fan", "req": "surv_magnet",
		"name": "⚡通义万象仙扇", "icon": "★扇", "rarity": "mythic", "max": 1,
		"desc": "【云纹折扇超武进化】同时掷出双巨型紫金仙扇，伤害 +40%、回旋吸 Token 并大幅回血！",
	},
	{
		"id": "evo_starblade", "weapon": "starblade", "req": "surv_bounce",
		"name": "⚡百万上下文星河", "icon": "★星", "rarity": "mythic", "max": 1,
		"desc": "【双子星刃超武进化】攻速 +25%、连锁弹射 +3、额外星芒爆炸，全屏星刃风暴！",
	},
]

const RARITY_COLOR: Dictionary = {
	"common": Color(0.38, 0.76, 1.0),
	"rare": Color(0.76, 0.45, 1.0),
	"epic": Color(1.0, 0.78, 0.25),
	"mythic": Color(1.0, 0.36, 0.72),
}

const RARITY_LABEL: Dictionary = {
	"common": "普通增益",
	"rare": "稀有增益",
	"epic": "史诗增益",
	"mythic": "⚡ 超武进化",
}


static func info(id: String) -> Dictionary:
	for s: Dictionary in EVO_LIST:
		if s["id"] == id:
			return s
	for s: Dictionary in PVP_LIST:
		if s["id"] == id:
			return s
	for s: Dictionary in SURVIVOR_LIST:
		if s["id"] == id:
			return s
	return {}


static func evo_for_weapon(wid: String) -> Dictionary:
	for s: Dictionary in EVO_LIST:
		if str(s["weapon"]) == wid:
			return s
	return {}


static func rarity_color(id: String) -> Color:
	var s := info(id)
	return RARITY_COLOR.get(s.get("rarity", "common"), Color.WHITE)


static func rarity_label(id: String) -> String:
	var s := info(id)
	return RARITY_LABEL.get(s.get("rarity", "common"), "普通增益")


static func choices(a: Archer, n: int, mode := "pvp") -> Array[String]:
	var out: Array[String] = []
	# 幸存者模式：Lv6+ 且拥有本武器超武素材 -> 必出超武进化神卡！
	if mode == "survivor" and a.evolved_weapon == "" and a.level >= 6:
		var ev := evo_for_weapon(a.weapon_id)
		if not ev.is_empty():
			var req_id: String = str(ev["req"])
			if int(a.skills.get(req_id, 0)) >= 1:
				out.append(str(ev["id"]))

	var src_list: Array[Dictionary] = SURVIVOR_LIST if mode == "survivor" else PVP_LIST
	var pool: Array[String] = []
	for s: Dictionary in src_list:
		var id: String = s["id"]
		var mx: int = s["max"]
		if int(a.skills.get(id, 0)) < mx:
			if (id == "pvp_heal" or id == "surv_heal") and a.hp >= a.max_hp * 0.75:
				continue
			pool.append(id)
	pool.shuffle()
	for id in pool:
		if out.size() >= n:
			break
		out.append(id)
	return out


static func apply(a: Archer, id: String) -> void:
	match id:
		# --- PVP 平衡词条 ---
		"pvp_multishot":
			a.front_arrows += 1
			a.damage *= 0.74
		"pvp_diagonal":
			a.diagonal_count += 1
			a.damage *= 0.86
		"pvp_phase_wall":
			a.phase_wall = true
		"pvp_wall_pierce":
			a.wall_pierce = true
			a.pierce += 1
		"pvp_pierce":
			a.pierce += 1
		"pvp_bounce":
			a.bounce += 1
		"pvp_crit":
			a.crit_chance = minf(0.50, a.crit_chance + 0.10)
		"pvp_atk":
			a.damage *= 1.10
		"pvp_aspd":
			a.fire_interval *= 0.91
		"pvp_cdr":
			a.active_cd_mult *= 0.88
		"pvp_speed":
			a.move_speed *= 1.08
		"pvp_hp":
			a.max_hp += 45.0
			a.hp += 45.0
		"pvp_heal":
			a.hp = minf(a.max_hp, a.hp + a.max_hp * 0.40)
			if a.max_shield > 0.0:
				a.shield = a.max_shield
		"pvp_lifesteal":
			a.lifesteal += 0.08
		"pvp_regen":
			a.regen += 0.014
		"pvp_range":
			a.attack_range *= 1.14
			a.arrow_speed *= 1.08

		# --- 幸存者全 6 位 AI 支援副武器 ---
		"sub_orbital":
			a.sub_orbital_lv += 1
			a.check_moe_synergy()
		"sub_lightning":
			a.sub_lightning_lv += 1
			a.check_moe_synergy()
		"sub_meteor":
			a.sub_meteor_lv += 1
			a.check_moe_synergy()
		"sub_fan_storm":
			a.sub_fan_lv += 1
			a.check_moe_synergy()
		"sub_dragon_rain":
			a.sub_dragon_lv += 1
			a.check_moe_synergy()
		"sub_eclipse_slash":
			a.sub_eclipse_lv += 1
			a.check_moe_synergy()

		# --- 6 把主武器超武进化 ---
		"evo_basin":
			a.evolved_weapon = id
			a.damage *= 1.32
			a.fire_interval *= 0.86
		"evo_grimoire":
			a.evolved_weapon = id
			a.damage *= 1.45
			a.pierce += 2
		"evo_bow":
			a.evolved_weapon = id
			a.fire_interval *= 0.68
			a.pierce += 3
			a.front_arrows += 1
		"evo_halberd":
			a.evolved_weapon = id
			a.front_arrows += 2
			a.pierce += 2
			a.crit_chance = minf(0.95, a.crit_chance + 0.25)
		"evo_fan":
			a.evolved_weapon = id
			a.damage *= 1.40
			a.front_arrows += 1
			a.pickup_range *= 1.45
		"evo_starblade":
			a.evolved_weapon = id
			a.fire_interval *= 0.75
			a.bounce += 3
			a.damage *= 1.25

		# --- 幸存者爽游词条 ---
		"surv_multishot":
			a.front_arrows += 1
			a.damage *= 0.95
		"surv_diagonal":
			a.diagonal_count += 1
		"surv_allaround":
			a.side_arrows = true
			a.back_arrow = true
		"surv_phase_wall":
			a.phase_wall = true
		"surv_wall_pierce":
			a.wall_pierce = true
			a.pierce += 1
		"surv_orbit":
			a.perm_orbit_blades += 2
		"surv_pierce":
			a.pierce += 2
		"surv_bounce":
			a.bounce += 2
		"surv_crit":
			a.crit_chance = minf(0.85, a.crit_chance + 0.20)
		"surv_atk":
			a.damage *= 1.28
		"surv_aspd":
			a.fire_interval *= 0.80
		"surv_cdr":
			a.active_cd_mult *= 0.76
		"surv_magnet":
			a.pickup_range *= 1.80
		"surv_speed":
			a.move_speed *= 1.14
		"surv_hp":
			a.max_hp += 90.0
			a.hp += 90.0
		"surv_heal":
			a.hp = a.max_hp
			if a.max_shield > 0.0:
				a.shield = a.max_shield
		"surv_lifesteal":
			a.lifesteal += 0.14
		"surv_regen":
			a.regen += 0.026
	a.skills[id] = int(a.skills.get(id, 0)) + 1
	if id.begins_with("evo_") and a.is_player and a.game != null and a.game.hud != null:
		a.game.hud.show_banner("⚡ 超武进化完成！【%s】觉醒！" % info(id)["name"], Color(1.0, 0.42, 0.76))
		Sfx.play("evo_fanfare", 0.01, 200, -5.0)
