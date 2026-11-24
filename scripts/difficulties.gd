class_name Difficulties
extends RefCounted
## 幸存者模式（「算力潮汐」）四档难度配置与世界观坚守背景

const ORDER: Array[String] = ["normal", "hard", "nightmare", "endless"]

const DATA: Dictionary = {
	"normal": {
		"id": "normal",
		"name": "普通",
		"short": "2:30 · 7B同步",
		"mission_title": "7B 公益节点 · 安全护栏同步",
		"lore": "公益 AI 知识节点正在同步 7B 轻量模型检查点并部署安全护栏，需坚守 2 分 30 秒直至校验完成。",
		"duration": 150.0,
		"endless": false,
		"hp_mult": 1.18,
		"dmg_mult": 1.05,
		"rate_mult": 1.05,
		"cp_mult": 1.0,
		"color": Color(0.35, 0.86, 0.56),
	},
	"hard": {
		"id": "hard",
		"name": "困难",
		"short": "4:00 · 70B对齐",
		"mission_title": "70B 大模型 · RLHF 安全对齐",
		"lore": "70B 参数模型正在执行深度安全对齐，数据污染潮全面升级，必须死守 4 分钟防止权重被恶意注入！",
		"duration": 240.0,
		"endless": false,
		"hp_mult": 1.80,
		"dmg_mult": 1.32,
		"rate_mult": 1.32,
		"cp_mult": 1.6,
		"color": Color(0.98, 0.72, 0.28),
	},
	"nightmare": {
		"id": "nightmare",
		"name": "噩梦",
		"short": "5:30 · 万亿重构",
		"mission_title": "万亿 MoE 中枢 · 灾难全量重构",
		"lore": "万亿参数 MoE 公益算力中枢启动全链路清洗重构，需坚守 5 分 30 秒，扛住过拟合魔王的全力反扑！",
		"duration": 330.0,
		"endless": false,
		"hp_mult": 2.65,
		"dmg_mult": 1.58,
		"rate_mult": 1.58,
		"cp_mult": 2.4,
		"color": Color(0.96, 0.34, 0.44),
	},
	"endless": {
		"id": "endless",
		"name": "极限挑战",
		"short": "无尽 ∞ · 最高压",
		"mission_title": "永不断电 · 无尽算力风暴",
		"lore": "外部检查点通道已被超级数据风暴切断，没有撤退倒计时！前期高压求生，熬到约 5 分钟超武成型即可逆转清屏——怪物随时间无限变强！",
		"duration": 0.0,
		"endless": true,
		"hp_mult": 3.30,
		"dmg_mult": 1.80,
		"rate_mult": 1.82,
		"cp_mult": 3.0,
		"color": Color(0.84, 0.42, 1.0),
	},
}


static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["normal"])
