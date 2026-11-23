class_name MetaSave
extends RefCounted
## 轻量本地存档与局外「算力天赋树」管理器（持久化至 user://save.json）
## 说明：天赋强化仅作用于「算力潮汐」幸存者模式，PVP 竞技保持零局外属性碾压的绝对公平！

const SAVE_PATH := "user://save.json"

const TALENTS: Array[Dictionary] = [
	{"id": "xp", "name": "Token 加速", "desc": "幸存者 Token/经验获取 +10%/级", "max": 5, "base_cost": 40, "step_cost": 35, "icon": "T+"},
	{"id": "speed", "name": "神经提速", "desc": "幸存者移动速度 +5%/级", "max": 5, "base_cost": 45, "step_cost": 40, "icon": "RUN"},
	{"id": "reroll", "name": "上下文缓存", "desc": "开局免费词条刷新 +1 次/级", "max": 3, "base_cost": 65, "step_cost": 65, "icon": "R+"},
	{"id": "hp", "name": "架构加固", "desc": "幸存者基础生命 +30/级", "max": 5, "base_cost": 40, "step_cost": 35, "icon": "+HP"},
	{"id": "atk", "name": "参数微调", "desc": "幸存者基础攻击 +7%/级", "max": 5, "base_cost": 55, "step_cost": 45, "icon": "ATK"},
	{"id": "magnet", "name": "数据磁力场", "desc": "Token 拾取范围 +15%/级", "max": 4, "base_cost": 40, "step_cost": 35, "icon": "MAG"},
]

const CODEX_UNLOCK_COST := 120

static var _loaded := false
static var data: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_merge_dict(data, parsed as Dictionary)


static func _default_data() -> Dictionary:
	return {
		"compute_points": 0,
		"total_cp_earned": 0,
		"total_kills": 0,
		"matches_played": 0,
		"talents": {"xp": 0, "speed": 0, "reroll": 0, "hp": 0, "atk": 0, "magnet": 0},
		"codex_full_unlocked": false,
		"seen_monsters": [],
		"cleared_diffs": [],
		"best_endless_sec": 0.0,
		"best_endless_kills": 0,
	}


static func _merge_dict(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if dst.has(k) and dst[k] is Dictionary and src[k] is Dictionary:
			_merge_dict(dst[k], src[k])
		elif dst.has(k):
			dst[k] = src[k]


static func save_to_disk() -> void:
	ensure_loaded()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


static func compute_points() -> int:
	ensure_loaded()
	return int(data["compute_points"])


static func talent_level(id: String) -> int:
	ensure_loaded()
	var t: Dictionary = data["talents"]
	return int(t.get(id, 0))


static func talent_info(id: String) -> Dictionary:
	for t in TALENTS:
		if t["id"] == id:
			return t
	return {}


static func talent_cost(id: String) -> int:
	var info := talent_info(id)
	if info.is_empty():
		return 999999
	var lv := talent_level(id)
	if lv >= int(info["max"]):
		return -1
	return int(info["base_cost"]) + lv * int(info["step_cost"])


static func buy_talent(id: String) -> bool:
	ensure_loaded()
	var cost := talent_cost(id)
	if cost < 0 or compute_points() < cost:
		return false
	data["compute_points"] = compute_points() - cost
	var t: Dictionary = data["talents"]
	t[id] = int(t.get(id, 0)) + 1
	save_to_disk()
	return true


static func reset_talents() -> int:
	ensure_loaded()
	var refund := 0
	var t: Dictionary = data["talents"]
	for info in TALENTS:
		var id: String = info["id"]
		var lv := int(t.get(id, 0))
		for i in lv:
			refund += int(info["base_cost"]) + i * int(info["step_cost"])
		t[id] = 0
	if refund > 0:
		data["compute_points"] = compute_points() + refund
		save_to_disk()
	return refund


static func is_codex_full_unlocked() -> bool:
	ensure_loaded()
	return bool(data["codex_full_unlocked"])


static func unlock_full_codex() -> bool:
	ensure_loaded()
	if is_codex_full_unlocked() or compute_points() < CODEX_UNLOCK_COST:
		return false
	data["compute_points"] = compute_points() - CODEX_UNLOCK_COST
	data["codex_full_unlocked"] = true
	save_to_disk()
	return true


static func mark_monster_seen(kind: String) -> void:
	ensure_loaded()
	var arr: Array = data["seen_monsters"]
	if not arr.has(kind):
		arr.append(kind)
		save_to_disk()


static func is_monster_unlocked(kind: String) -> bool:
	ensure_loaded()
	return is_codex_full_unlocked() or (data["seen_monsters"] as Array).has(kind)


static func is_tip_unlocked(index: int) -> bool:
	ensure_loaded()
	# 前 10 条公益小知识默认免费开放；后 8 条进阶百科可通过解全图鉴解锁（或按局数逐步解锁）
	if index < 10 or is_codex_full_unlocked():
		return true
	var played := int(data["matches_played"])
	return index < 10 + played * 2


static func is_diff_cleared(diff_id: String) -> bool:
	ensure_loaded()
	return (data["cleared_diffs"] as Array).has(diff_id)


# ================= 天赋加成查询 =================
static func xp_mult() -> float:
	return 1.0 + talent_level("xp") * 0.10


static func speed_mult() -> float:
	return 1.0 + talent_level("speed") * 0.05


static func extra_rerolls() -> int:
	return talent_level("reroll")


static func hp_bonus() -> float:
	return talent_level("hp") * 30.0


static func atk_mult() -> float:
	return 1.0 + talent_level("atk") * 0.07


static func magnet_mult() -> float:
	return 1.0 + talent_level("magnet") * 0.15


# ================= 对局结算折算算力点 =================
static func record_match_result(mode: String, diff_id: String, kills: int, tokens: int, survived_sec: float, victory: bool, persist := true) -> Dictionary:
	ensure_loaded()
	var mult := 1.0
	var base_cp := 0
	var new_record := false

	if mode == "survivor":
		var dd := Difficulties.get_data(diff_id)
		mult = float(dd["cp_mult"])
		base_cp = int(round(kills * 0.65 + survived_sec * 0.25 + tokens * 0.06))
		if victory:
			base_cp += 45
		if diff_id == "endless" and survived_sec > float(data["best_endless_sec"]):
			new_record = true
	else:
		base_cp = int(round(kills * 18.0 + tokens * 0.15 + survived_sec * 0.18))

	if is_codex_full_unlocked():
		mult *= 1.10

	var earned := maxi(10, int(round(base_cp * mult)))
	if persist:
		data["matches_played"] = int(data["matches_played"]) + 1
		data["total_kills"] = int(data["total_kills"]) + kills
		if mode == "survivor":
			if victory:
				var cleared: Array = data["cleared_diffs"]
				if not cleared.has(diff_id):
					cleared.append(diff_id)
			if diff_id == "endless":
				if survived_sec > float(data["best_endless_sec"]):
					data["best_endless_sec"] = survived_sec
				if kills > int(data["best_endless_kills"]):
					data["best_endless_kills"] = kills
		data["compute_points"] = compute_points() + earned
		data["total_cp_earned"] = int(data["total_cp_earned"]) + earned
		save_to_disk()

	return {
		"earned": earned,
		"total_cp": compute_points(),
		"mult": mult,
		"new_record": new_record,
	}
