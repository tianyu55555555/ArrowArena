class_name PixelSprites
extends RefCounted
## 高精 32x32 复古二次元像素精灵工坊：
## - 6 位 AI 娘 32x32 精绘 Q 版小人（3x3 萌系大眼、高光发带、分层礼服/龙翼/猫耳/鲸尾/女仆头饰、4 帧动画）
## - 像素 Token 晶片（蓝/金/紫）、全图磁铁、黄金宝箱、回血爱心、6 种武器、5 种 AI 主题怪物

static var _char_cache: Dictionary = {}
static var _weapon_cache: Dictionary = {}
static var _orb_cache: Dictionary = {}
static var _monster_cache: Dictionary = {}
static var _heart_tex: ImageTexture = null
static var _magnet_tex: ImageTexture = null
static var _chest_tex: ImageTexture = null
static var _grass_tile: ImageTexture = null
static var _obstacle_cache: Dictionary = {}
static var _prop_cache: Dictionary = {}
static var _ui_font: Font = null


static func ui_font() -> Font:
	if _ui_font == null:
		if ResourceLoader.exists("res://assets/fonts/zpix.ttf"):
			_ui_font = load("res://assets/fonts/zpix.ttf") as Font
		if _ui_font == null:
			_ui_font = ThemeDB.fallback_font
	return _ui_font


static func get_character_frames(char_id: String) -> Array:
	if _char_cache.has(char_id):
		return _char_cache[char_id]
	var frames: Array = []
	for f in 4:
		frames.append(ImageTexture.create_from_image(_build_chibi_32(char_id, f)))
	_char_cache[char_id] = frames
	return frames


static func get_weapon_texture(weapon_id: String) -> ImageTexture:
	if _weapon_cache.has(weapon_id):
		return _weapon_cache[weapon_id]
	var tex := ImageTexture.create_from_image(_build_weapon(weapon_id))
	_weapon_cache[weapon_id] = tex
	return tex


static func get_orb_texture(tier: int) -> ImageTexture:
	if _orb_cache.has(tier):
		return _orb_cache[tier]
	var tex := ImageTexture.create_from_image(_build_token_chip(tier))
	_orb_cache[tier] = tex
	return tex


static func get_monster_texture(kind: String) -> ImageTexture:
	if _monster_cache.has(kind):
		return _monster_cache[kind]
	var tex := ImageTexture.create_from_image(_build_monster(kind))
	_monster_cache[kind] = tex
	return tex


static func get_heart_texture() -> ImageTexture:
	if _heart_tex != null:
		return _heart_tex
	var img := Image.create(12, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rows := [
		"............",
		"..rr....rr..",
		".rwwr..rrrr.",
		".rwrrrrrrrr.",
		".rrrrrrrrrr.",
		"..rrrrrrrr..",
		"...rrrrrr...",
		"....rrrr....",
		".....rr.....",
		"............",
		"............",
	]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "r": img.set_pixel(x, y, Color("#ff4575"))
			elif row[x] == "w": img.set_pixel(x, y, Color("#ffd6e4"))
	_heart_tex = ImageTexture.create_from_image(_add_outline(img, Color("#241220")))
	return _heart_tex


static func get_magnet_texture() -> ImageTexture:
	if _magnet_tex != null:
		return _magnet_tex
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rows := [
		"..............",
		"..sss....sss..",
		"..sss....sss..",
		"..rrr....bbb..",
		"..rrr....bbb..",
		"..rrr....bbb..",
		"..rrr....bbb..",
		"..rrr....bbb..",
		"..rrrr..bbbb..",
		"...rrrrrrrr...",
		"....rrrrrr....",
		"..............",
		"..............",
		"..............",
	]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var c := row[x]
			if c == "r": img.set_pixel(x, y, Color("#ff3b5c"))
			elif c == "b": img.set_pixel(x, y, Color("#369bff"))
			elif c == "s": img.set_pixel(x, y, Color("#eef6ff"))
	_magnet_tex = ImageTexture.create_from_image(_add_outline(img, Color("#151124")))
	return _magnet_tex


static func get_chest_texture() -> ImageTexture:
	if _chest_tex != null:
		return _chest_tex
	var img := Image.create(16, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 紫金像素 Token 宝箱
	_rect(img, 2, 3, 12, 9, Color("#56288a"))
	_rect(img, 3, 2, 10, 4, Color("#7c3ec4"))
	_rect(img, 2, 6, 12, 2, Color("#ffd24c")) # 金色盒扣带
	_rect(img, 2, 3, 2, 9, Color("#e8a832"))
	_rect(img, 12, 3, 2, 9, Color("#e8a832"))
	_rect(img, 3, 2, 10, 1, Color("#ffe885"))
	_rect(img, 3, 11, 10, 1, Color("#d49228"))
	_rect(img, 7, 5, 2, 4, Color("#fff6c2")) # 发光金锁扣
	_px(img, 7, 6, Color("#3cf2ff"))         # Token 晶核
	_px(img, 8, 6, Color("#3cf2ff"))
	_chest_tex = ImageTexture.create_from_image(_add_outline(img, Color("#181026")))
	return _chest_tex


static func get_grass_tile() -> ImageTexture:
	if _grass_tile != null:
		return _grass_tile
	# 无缝 128x128 复古 JRPG 像素草地贴图：柔和有机斑驳草色 + 散落草簇、三叶草、野花与小石子，彻底告别机械格子感
	const SZ := 128
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	var c_base := Color("#4f8f53")
	var c_soft := Color("#589a5a")
	var c_deep := Color("#45814b")
	var c_sun := Color("#65a962")
	var c_blade_dk := Color("#396e40")
	var c_blade_lt := Color("#78be6c")

	# 1. 有机无缝草地斑块（使用周期三角函数确保 128px 四边完美无缝衔接）
	for y in SZ:
		var ay := float(y) / float(SZ) * TAU
		for x in SZ:
			var ax := float(x) / float(SZ) * TAU
			var n := sin(ax * 2.0 + sin(ay * 2.0) * 0.7) * 0.45 \
				+ cos(ay * 3.0 - cos(ax * 2.0) * 0.6) * 0.35 \
				+ sin((ax + ay) * 4.0) * 0.20
			var col := c_base
			if n > 0.34:
				col = c_soft
			elif n < -0.36:
				col = c_deep
			# 细微像素颗粒感（确定性伪随机，不产生网格）
			var h := ((x * 73856093) ^ (y * 19349663)) & 31
			if h == 0 and n > 0.12:
				col = c_sun
			elif h == 1 and n < -0.1:
				col = c_deep
			img.set_pixel(x, y, col)

	# 2. 散落自然像素草簇（32 处 V 型草叶）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261122
	for _i in 34:
		var gx := rng.randi_range(3, SZ - 4)
		var gy := rng.randi_range(3, SZ - 4)
		_px(img, gx, gy, c_blade_dk)
		_px(img, gx + 1, gy, c_blade_dk)
		_px(img, gx - 1, gy - 1, c_blade_lt)
		_px(img, gx + 1, gy - 1, c_blade_lt)
		if rng.randf() < 0.55:
			_px(img, gx, gy - 2, c_sun)

	# 3. 点缀几处小巧像素野花（白雏菊 / 晴空蓝 / 淡鹅黄）
	var flower_cols := [Color("#fff7cc"), Color("#f8fbff"), Color("#9ee4ff"), Color("#ffd0e6")]
	for _i in 9:
		var fx := rng.randi_range(4, SZ - 5)
		var fy := rng.randi_range(4, SZ - 5)
		var fc: Color = flower_cols[rng.randi() % flower_cols.size()]
		_px(img, fx, fy + 1, c_blade_dk)
		_px(img, fx - 1, fy, fc)
		_px(img, fx + 1, fy, fc)
		_px(img, fx, fy - 1, fc)
		_px(img, fx, fy, Color("#ffdb58") if fc != Color("#fff7cc") else Color("#fffdf0"))

	# 4. 少量青苔小卵石
	for _i in 5:
		var sx := rng.randi_range(4, SZ - 5)
		var sy := rng.randi_range(4, SZ - 5)
		_rect(img, sx, sy, 3, 2, Color("#5f736d"))
		_px(img, sx, sy, Color("#8aa198"))

	_grass_tile = ImageTexture.create_from_image(img)
	return _grass_tile


static func get_obstacle_texture(kind: String) -> ImageTexture:
	if _obstacle_cache.has(kind):
		return _obstacle_cache[kind]
	var tex := ImageTexture.create_from_image(_build_obstacle_32(kind))
	_obstacle_cache[kind] = tex
	return tex


static func get_prop_texture(kind: String) -> ImageTexture:
	if _prop_cache.has(kind):
		return _prop_cache[kind]
	var tex := ImageTexture.create_from_image(_build_prop_16(kind))
	_prop_cache[kind] = tex
	return tex


# ================= 4 种 32x32 精绘像素障碍物 =================
static func _build_obstacle_32(kind: String) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"moss_rock":
			# 青苔巨岩：多切面岩石块 + 顶层青苔披挂 + 小野花
			_rect(img, 5, 11, 22, 16, Color("#3a4358"))
			_rect(img, 7, 8, 18, 19, Color("#4c5872"))
			_rect(img, 9, 6, 14, 15, Color("#667594"))
			_rect(img, 4, 15, 24, 10, Color("#4c5872"))
			_rect(img, 6, 23, 20, 4, Color("#323a4d"))
			# 岩石切面高光与暗裂纹
			_rect(img, 8, 9, 9, 5, Color("#8899b8"))
			_rect(img, 9, 8, 5, 2, Color("#aebfd9"))
			_rect(img, 18, 15, 6, 7, Color("#3a4358"))
			_px(img, 16, 14, Color("#2c3345")); _px(img, 17, 15, Color("#2c3345")); _px(img, 17, 16, Color("#2c3345"))
			_px(img, 10, 19, Color("#2c3345")); _px(img, 11, 20, Color("#2c3345"))
			# 青苔披顶
			_rect(img, 8, 6, 15, 4, Color("#3f8545"))
			_rect(img, 10, 5, 11, 3, Color("#5db458"))
			_rect(img, 11, 6, 5, 2, Color("#88d870"))
			_rect(img, 7, 9, 4, 3, Color("#3f8545"))
			_rect(img, 20, 9, 4, 4, Color("#35723c"))
			_px(img, 15, 6, Color("#fff08a")); _px(img, 19, 8, Color("#ffd4ea"))
		"server_pillar":
			# 古代算力晶碑（服务器石柱）：厚重基座 + 发光青蓝 LED 符文条 + 顶部算力晶核
			_rect(img, 5, 22, 22, 7, Color("#363d52"))
			_rect(img, 6, 20, 20, 4, Color("#56627e"))
			_rect(img, 7, 20, 18, 1, Color("#8b99b8"))
			# 柱身
			_rect(img, 8, 8, 16, 14, Color("#46506b"))
			_rect(img, 9, 8, 11, 13, Color("#606e8f"))
			_rect(img, 9, 8, 3, 13, Color("#8191b4"))
			# 金铜镶边
			_rect(img, 8, 8, 16, 2, Color("#cfa24c"))
			_rect(img, 8, 19, 16, 2, Color("#b8883a"))
			# 三排发光青蓝服务器指示灯条
			for row_y in [11, 14, 17]:
				_rect(img, 11, row_y, 10, 2, Color("#182840"))
				_rect(img, 12, row_y, 6, 1, Color("#32e6ff"))
				_px(img, 13, row_y, Color("#d6fcff"))
				_px(img, 19, row_y, Color("#ffce48"))
			# 顶部算力晶核
			_rect(img, 13, 3, 6, 5, Color("#38a8ff"))
			_rect(img, 14, 2, 4, 5, Color("#7ae8ff"))
			_rect(img, 15, 3, 2, 2, Color("#ffffff"))
		"pine_cluster":
			# 像素苍翠树丛：三团交错丰盈像素树冠 + 树干基座 + 红金浆果
			_rect(img, 13, 23, 6, 6, Color("#563626"))
			_rect(img, 14, 23, 2, 6, Color("#754c34"))
			# 底层暗绿树影
			_rect(img, 4, 14, 24, 11, Color("#1f4f32"))
			_rect(img, 6, 10, 20, 14, Color("#245e3a"))
			# 中层翠绿三瓣树冠
			_rect(img, 5, 13, 10, 9, Color("#2f7a44"))
			_rect(img, 17, 13, 10, 9, Color("#2f7a44"))
			_rect(img, 9, 6, 14, 13, Color("#388e4c"))
			# 顶层受光嫩绿叶簇
			_rect(img, 10, 5, 11, 6, Color("#56b058"))
			_rect(img, 11, 6, 6, 3, Color("#84d670"))
			_rect(img, 6, 13, 6, 4, Color("#56b058"))
			_rect(img, 19, 13, 5, 3, Color("#4ca452"))
			# 明亮浆果点缀
			_rect(img, 9, 17, 2, 2, Color("#ff5474")); _px(img, 9, 17, Color("#ffd0dc"))
			_rect(img, 20, 16, 2, 2, Color("#ff5474")); _px(img, 20, 16, Color("#ffd0dc"))
			_rect(img, 15, 11, 2, 2, Color("#ffe064"))
		"data_crystal":
			# 算力水晶簇：深色玄武岩底座 + 三座发光蓝紫晶体尖碑
			_rect(img, 5, 20, 22, 8, Color("#31364c"))
			_rect(img, 7, 18, 18, 8, Color("#474f6e"))
			_rect(img, 9, 18, 10, 3, Color("#687498"))
			# 左斜晶柱
			_rect(img, 6, 12, 6, 10, Color("#3258c8"))
			_rect(img, 7, 10, 4, 10, Color("#56a2ff"))
			_rect(img, 7, 11, 2, 6, Color("#9eeeff"))
			# 右斜晶柱
			_rect(img, 20, 13, 6, 9, Color("#4a3cc8"))
			_rect(img, 21, 11, 4, 9, Color("#7c72ff"))
			_rect(img, 21, 12, 2, 5, Color("#c4ccff"))
			# 中央主晶塔
			_rect(img, 12, 6, 8, 16, Color("#2c68e0"))
			_rect(img, 13, 4, 6, 16, Color("#4cc8ff"))
			_rect(img, 14, 3, 3, 12, Color("#a6f6ff"))
			_rect(img, 15, 4, 1, 7, Color("#ffffff"))
			# 底部荧光余晖
			_rect(img, 11, 21, 10, 2, Color("#4ce8ff"))
	return _add_outline(img, Color("#151424"))


# ================= 4 种 16x16 无碰撞地面装饰物 =================
static func _build_prop_16(kind: String) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"flower_bed":
			_rect(img, 3, 8, 10, 5, Color("#3a7a42"))
			_rect(img, 4, 6, 8, 5, Color("#58a856"))
			_px(img, 5, 6, Color("#fff49c")); _px(img, 6, 5, Color("#fff49c")); _px(img, 5, 5, Color("#ffffff"))
			_px(img, 10, 7, Color("#ff98c8")); _px(img, 11, 7, Color("#ff98c8")); _px(img, 10, 6, Color("#ffe4f0"))
			_px(img, 7, 9, Color("#8ce8ff")); _px(img, 8, 9, Color("#8ce8ff"))
		"flagstone":
			_rect(img, 2, 4, 12, 8, Color("#5c687a"))
			_rect(img, 3, 5, 10, 6, Color("#7d8b9e"))
			_rect(img, 3, 5, 8, 2, Color("#9aa8bc"))
			_px(img, 8, 7, Color("#495364")); _px(img, 9, 8, Color("#495364"))
			_rect(img, 2, 10, 4, 2, Color("#4d944e"))
		"circuit_pad":
			_rect(img, 2, 2, 12, 12, Color("#3d4a5e"))
			_rect(img, 3, 3, 10, 10, Color("#52627a"))
			_rect(img, 5, 5, 6, 6, Color("#38475c"))
			_rect(img, 7, 4, 2, 8, Color("#38d6f0"))
			_rect(img, 4, 7, 8, 2, Color("#38d6f0"))
			_rect(img, 7, 7, 2, 2, Color("#d4fcff"))
		"clover_tuft":
			_rect(img, 4, 7, 8, 6, Color("#2f6e3a"))
			_rect(img, 3, 9, 10, 3, Color("#3f8a48"))
			_rect(img, 5, 6, 6, 4, Color("#62ba5e"))
			_px(img, 6, 6, Color("#98e67e")); _px(img, 10, 8, Color("#98e67e"))
	return img


# ================= 32x32 高精二次元 Q 版像素小人 =================
static func _build_chibi_32(cid: String, frame: int) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# 帧动画：0=呼吸待机, 1=眨眼微蹲, 2=左脚迈步+发丝飘, 3=右脚迈步+发丝飘
	var blink := (frame == 1)
	var hy := (1 if frame == 1 else 0) + (-1 if (frame == 2 or frame == 3) else 0)
	var by := 18 + (-1 if (frame == 2 or frame == 3) else 0)
	var sway := (1 if frame == 2 else (-1 if frame == 3 else 0))

	var skin := Color("#ffe5d0")
	var skin_sh := Color("#f2c2a4")
	var blush := Color("#ff98ac")
	var lash := Color("#23192e")

	# 角色配色板
	var hair := Color("#dc6428")
	var hair_hi := Color("#ff9d56")
	var hair_sh := Color("#993818")
	var eye := Color("#cc6e22")
	var eye_hi := Color("#ffc468")
	var dress1 := Color("#faf3e6")
	var dress2 := Color("#241e28")
	var accent := Color("#e05a26")
	var shoe := Color("#543428")

	match cid:
		"claude":
			hair = Color("#dc6428"); hair_hi = Color("#ffa25a"); hair_sh = Color("#943416")
			eye = Color("#b86420"); eye_hi = Color("#f8c86c")
			dress1 = Color("#faf2e4"); dress2 = Color("#251f29"); accent = Color("#e05824"); shoe = Color("#7a5442")
		"gpt":
			hair = Color("#f0f3fc"); hair_hi = Color("#ffffff"); hair_sh = Color("#c3cae8")
			eye = Color("#9688d8"); eye_hi = Color("#dce4ff")
			dress1 = Color("#fcfdff"); dress2 = Color("#e0e6f8"); accent = Color("#a8b4dc"); shoe = Color("#cfd6ef")
		"grok":
			hair = Color("#f6d27a"); hair_hi = Color("#fff3bf"); hair_sh = Color("#c48e3c")
			eye = Color("#2478ff"); eye_hi = Color("#7cd4ff")
			dress1 = Color("#231e29"); dress2 = Color("#a81a30"); accent = Color("#e8c25a"); shoe = Color("#1e1824")
		"deepseek":
			hair = Color("#4a7ae0"); hair_hi = Color("#8ac2ff"); hair_sh = Color("#2c4a9c")
			eye = Color("#3a7cf0"); eye_hi = Color("#8ee6ff")
			dress1 = Color("#2b3362"); dress2 = Color("#f7f9ff"); accent = Color("#62b8ff"); shoe = Color("#242b52")
		"qwen":
			hair = Color("#8c9ff5"); hair_hi = Color("#c6d2ff"); hair_sh = Color("#5865ba")
			eye = Color("#6e5ce8"); eye_hi = Color("#b8b2ff")
			dress1 = Color("#f5f3ff"); dress2 = Color("#36356e"); accent = Color("#6372e0"); shoe = Color("#333678")
		"gemini":
			hair = Color("#6a9eff"); hair_hi = Color("#b8dcff"); hair_sh = Color("#f57ec8")
			eye = Color("#f03878"); eye_hi = Color("#ff98c4")
			dress1 = Color("#252458"); dress2 = Color("#f5f3ff"); accent = Color("#9668ff"); shoe = Color("#3d3680")

	# ==================== 1. 后景层（披发、双马尾、白龙翼、龙尾/鲸尾/猫尾、广袖）====================
	match cid:
		"claude":
			# 丰盈向外飘展的暖橙长发
			_rect(img, 6, 9 + hy, 20, 14, hair_sh)
			_rect(img, 7, 8 + hy, 18, 12, hair)
			_rect(img, 4 + sway, 15 + hy, 4, 8, hair)
			_rect(img, 24 + sway, 15 + hy, 4, 8, hair)
			_px(img, 3 + sway, 21 + hy, hair_sh)
			_px(img, 28 + sway, 21 + hy, hair_sh)
		"gpt":
			# 对称展翅的圣洁白龙翼 + 银白长发 + 粗壮鳞纹白龙尾
			var wy := 1 if frame == 2 else 0
			_rect(img, 2, 14 + hy + wy, 7, 7, Color("#e6ebfa"))
			_rect(img, 1, 16 + hy + wy, 3, 5, Color("#cfd7f0"))
			_rect(img, 23, 14 + hy + wy, 7, 7, Color("#e6ebfa"))
			_rect(img, 28, 16 + hy + wy, 3, 5, Color("#cfd7f0"))
			_px(img, 2, 21 + wy, Color("#b8c2e2"))
			_px(img, 29, 21 + wy, Color("#b8c2e2"))
			_rect(img, 8, 9 + hy, 16, 15, hair_sh)
			_rect(img, 9, 8 + hy, 14, 13, hair)
			# 白色大龙尾从右下翘起
			_rect(img, 21, 22 + by - 18, 6, 6, Color("#dce2f5"))
			_rect(img, 25, 20 + by - 18, 4, 5, Color("#eef2fc"))
			_px(img, 24, 24 + by - 18, Color("#b8c2e2"))
		"grok":
			# 超长金发大卷双马尾 + 黑丝带蝴蝶结 + 蝙蝠小翼
			var tw := 1 if frame == 2 else 0
			_rect(img, 3, 8 + hy + tw, 6, 15, hair)
			_rect(img, 2, 16 + hy + tw, 5, 7, hair_sh)
			_rect(img, 4, 10 + hy + tw, 2, 10, hair_hi)
			_rect(img, 23, 8 + hy - tw, 6, 15, hair)
			_rect(img, 25, 16 + hy - tw, 5, 7, hair_sh)
			_rect(img, 26, 10 + hy - tw, 2, 10, hair_hi)
			# 双马尾黑色蝴蝶结 + 蝙蝠翅装饰
			_rect(img, 6, 6 + hy, 4, 3, Color("#201a26"))
			_rect(img, 22, 6 + hy, 4, 3, Color("#201a26"))
			_rect(img, 26, 8 + hy, 3, 2, Color("#2c1e30"))
		"deepseek":
			# 飘逸海蓝波浪卷发（内衬浅蓝挑染）+ 背后翘起的深海蓝鲸尾！
			_rect(img, 5 + sway, 10 + hy, 22, 12, hair)
			_rect(img, 4 + sway, 14 + hy, 5, 8, Color("#80c4ff"))
			_rect(img, 23 + sway, 14 + hy, 4, 7, Color("#76b8ff"))
			# 蓝鲸尾从右侧扬起并分叉
			_rect(img, 22, 21 + by - 18, 5, 4, Color("#3a4a7a"))
			_rect(img, 25, 18 + by - 18, 4, 4, Color("#495f96"))
			_rect(img, 24, 16 + by - 18, 2, 3, Color("#495f96"))
			_rect(img, 28, 17 + by - 18, 2, 3, Color("#495f96"))
		"qwen":
			# 蓝紫大波浪长发 + 宽大垂坠靛紫国风广袖披帛
			_rect(img, 6 + sway, 10 + hy, 20, 14, hair_sh)
			_rect(img, 7 + sway, 9 + hy, 18, 11, hair)
			_rect(img, 4, by + 1, 6, 10, dress2)
			_rect(img, 22, by + 1, 6, 10, dress2)
			_rect(img, 4, by + 9, 5, 2, Color("#9ea6e0")) # 广袖金银云纹边
			_rect(img, 23, by + 9, 5, 2, Color("#9ea6e0"))
		"gemini":
			# 蓝->紫->粉三色渐变星空大卷发 + 蓝粉渐变蓬松猫尾！
			_rect(img, 4 + sway, 9 + hy, 24, 6, Color("#68a0ff"))
			_rect(img, 3 + sway, 14 + hy, 26, 5, Color("#9466f5"))
			_rect(img, 3 + sway, 18 + hy, 26, 6, Color("#f682cc"))
			# 蓝粉渐变大猫尾从左下方卷出
			_rect(img, 5, 23 + by - 18, 6, 4, Color("#74b4ff"))
			_rect(img, 3, 21 + by - 18, 4, 4, Color("#f488d0"))

	# ==================== 2. 腿与鞋（迈步交替动画）====================
	var ly_l := 26 + (-1 if frame == 2 else 0)
	var ly_r := 26 + (-1 if frame == 3 else 0)
	var leg_col := Color("#46384d") if cid == "grok" else (Color("#f2f4ff") if cid == "deepseek" else skin_sh)
	_rect(img, 12, ly_l, 3, 4, leg_col)
	_rect(img, 17, ly_r, 3, 4, leg_col)
	if cid == "gemini":
		# 白色堆堆袜 + 蓝紫厚底鞋
		_rect(img, 12, ly_l + 1, 3, 2, Color("#f6f4ff"))
		_rect(img, 17, ly_r + 1, 3, 2, Color("#f6f4ff"))
	_rect(img, 11, ly_l + 3, 4, 2, shoe)
	_rect(img, 17, ly_r + 3, 4, 2, shoe)

	# ==================== 3. 身体与精致分层礼服 ====================
	match cid:
		"claude":
			# 象牙白泡袖上衣 + 黑色束腰马甲 + 暖橙垂带 + 褶皱白金大长裙
			_rect(img, 10, by, 12, 4, dress1)
			_rect(img, 8, by + 1, 3, 4, dress1) # 左泡袖
			_rect(img, 21, by + 1, 3, 4, dress1) # 右泡袖
			_rect(img, 11, by + 2, 10, 3, dress2) # 黑束腰
			_rect(img, 8, by + 5, 16, 5, dress1) # 象牙白大裙摆
			_rect(img, 15, by + 3, 2, 7, accent) # 暖橙中缝飘带
			_rect(img, 8, by + 6, 3, 4, dress2) # 两侧黑橙裙衬
			_rect(img, 21, by + 6, 3, 4, dress2)
			_px(img, 10, by + 7, Color("#ffbe50")) # 金色太阳花徽章
			_px(img, 21, by + 7, Color("#ffbe50"))
		"gpt":
			# 圣洁纯白龙女高衩礼服 + 银蓝六边结腰饰
			_rect(img, 11, by, 10, 5, dress1)
			_rect(img, 9, by + 4, 14, 6, dress1)
			_rect(img, 10, by + 4, 12, 1, dress2)
			_rect(img, 12, by + 6, 3, 4, skin) # 右侧高衩长腿细节
			_rect(img, 16, by + 4, 3, 2, accent) # 六边结腰饰
			_px(img, 17, by + 4, Color.WHITE)
		"grok":
			# 猩红高领衬里 + 黑金哥特蓬蓬裙 + 猩红内衬底边 + 金色腰扣
			_rect(img, 11, by - 1, 10, 2, dress2) # 猩红内领
			_rect(img, 10, by + 1, 12, 4, dress1)
			_rect(img, 8, by + 4, 16, 5, dress1)
			_rect(img, 8, by + 8, 16, 2, dress2) # 猩红蓬裙衬里
			_rect(img, 14, by + 2, 4, 2, accent) # 金色黑洞腰扣
			_px(img, 15, by + 2, dress1)
			_px(img, 10, by + 7, accent); _px(img, 21, by + 7, accent)
		"deepseek":
			# 藏青蕾丝女仆裙 + 纯白荷叶边围裙 + 胸前蝴蝶结 + 小蓝鲸图案！
			_rect(img, 10, by, 12, 4, dress1)
			_rect(img, 13, by, 6, 3, dress2) # 白衬衫胸口
			_rect(img, 14, by, 4, 1, Color("#1e2445")) # 黑蝴蝶结
			_rect(img, 7, by + 4, 18, 6, dress1) # 大蓬女仆裙
			_rect(img, 11, by + 4, 10, 5, dress2) # 白色大围裙
			_rect(img, 15, by + 7, 3, 1, Color("#35508f")) # 围裙小蓝鲸！
			_rect(img, 7, by + 9, 18, 1, dress2) # 白色蕾丝裙底边
		"qwen":
			# 象牙白盘扣国风裙 + 靛紫腰带流苏 + 蓝紫云纹百褶长裙
			_rect(img, 11, by, 10, 4, dress1)
			_px(img, 15, by + 1, accent); _px(img, 15, by + 2, accent) # 盘扣
			_rect(img, 10, by + 3, 12, 2, dress2) # 靛紫腰带
			_rect(img, 8, by + 5, 16, 5, accent) # 蓝紫大长裙
			_rect(img, 13, by + 4, 6, 6, dress1) # 象牙白前片
			_px(img, 15, by + 3, Color.WHITE)    # 腰间徽章
		"gemini":
			# 藏青露腰星空上衣 + 紫星腰带 + 白色荷叶边迷你裙 + 星空外袍
			_rect(img, 11, by, 10, 3, dress1)
			_px(img, 15, by + 1, Color("#90e0ff")) # 胸前四芒星
			_rect(img, 13, by + 3, 6, 1, skin)     # 露腰小蛮腰
			_rect(img, 10, by + 4, 12, 4, dress2)  # 白色荷叶边短裙
			_rect(img, 10, by + 4, 5, 3, dress1)   # 星空斜片
			_rect(img, 8, by + 1, 3, 7, Color("#3a327c")) # 星空大袖袍
			_rect(img, 21, by + 1, 3, 7, Color("#3a327c"))
			_px(img, 9, by + 7, Color("#ffe898")); _px(img, 22, by + 7, Color("#ffe898"))

	# ==================== 4. 精致脸部 + 3x3 萌系动漫大眼 ====================
	_rect(img, 10, 10 + hy, 12, 8, skin)
	_rect(img, 11, 17 + hy, 10, 1, skin_sh)
	# 粉嫩腮红 + 娇小嘴角
	_rect(img, 10, 15 + hy, 2, 1, blush)
	_rect(img, 20, 15 + hy, 2, 1, blush)
	_rect(img, 15, 16 + hy, 2, 1, Color("#e88c8c") if (cid == "grok" or cid == "deepseek") else Color("#d99888"))

	if blink:
		_rect(img, 11, 13 + hy, 3, 1, lash)
		_rect(img, 18, 13 + hy, 3, 1, lash)
	else:
		# 左眼 (11..13, 12..14)
		_rect(img, 11, 12 + hy, 3, 1, lash)
		_rect(img, 11, 13 + hy, 3, 2, eye)
		_px(img, 12, 14 + hy, eye_hi)
		_px(img, 11, 13 + hy, Color.WHITE)
		# 右眼 (18..20, 12..14) —— Gemini 专属粉红 + 金黄异色瞳！
		var r_eye := Color("#f0a820") if cid == "gemini" else eye
		var r_hi := Color("#fff288") if cid == "gemini" else eye_hi
		_rect(img, 18, 12 + hy, 3, 1, lash)
		_rect(img, 18, 13 + hy, 3, 2, r_eye)
		_px(img, 19, 14 + hy, r_hi)
		_px(img, 18, 13 + hy, Color.WHITE)

	# ==================== 5. 层次感前发、高光发带与标志性头饰 ====================
	_rect(img, 9, 5 + hy, 14, 6, hair)
	_rect(img, 11, 4 + hy, 10, 2, hair)
	# 鬓角包脸发丝
	_rect(img, 9, 10 + hy, 2, 7, hair)
	_rect(img, 21, 10 + hy, 2, 7, hair)
	# 刘海参差发尖
	_rect(img, 11, 10 + hy, 2, 2, hair)
	_rect(img, 15, 10 + hy, 2, 3, hair)
	_rect(img, 19, 10 + hy, 2, 2, hair)
	# 动漫分段高光发带
	_rect(img, 11, 7 + hy, 4, 1, hair_hi)
	_rect(img, 17, 7 + hy, 4, 1, hair_hi)
	_px(img, 12, 6 + hy, hair_hi); _px(img, 19, 6 + hy, hair_hi)

	match cid:
		"claude":
			# 标志性暖橙太阳花发饰 + 黑白双丝带
			_rect(img, 20, 5 + hy, 3, 3, Color("#ffae42"))
			_px(img, 21, 6 + hy, Color("#fff2c2"))
			_rect(img, 22, 8 + hy, 2, 4, Color("#241e28"))
			_px(img, 21, 9 + hy, Color("#faf2e4"))
		"gpt":
			# 弯曲白色大龙角 + 左侧银白六边结发饰 + 呆毛
			_rect(img, 9, 2 + hy, 3, 4, Color("#edf1fc"))
			_rect(img, 8, 1 + hy, 2, 2, Color.WHITE)
			_rect(img, 20, 2 + hy, 3, 4, Color("#edf1fc"))
			_rect(img, 22, 1 + hy, 2, 2, Color.WHITE)
			_px(img, 15, 3 + hy, Color.WHITE) # 呆毛
			_rect(img, 21, 7 + hy, 2, 2, Color("#d4dcf4")) # 六边结
		"grok":
			# 金色黑洞小皇冠 + 俏皮呆毛
			_rect(img, 13, 2 + hy, 6, 2, Color("#f2c852"))
			_px(img, 15, 1 + hy, Color("#fff0a8"))
			_px(img, 16, 1 + hy, Color("#241e28"))
			_px(img, 13, 1 + hy, hair) # 呆毛
		"deepseek":
			# 白色荷叶边女仆发箍 + 两侧招牌鲸鳍大耳 + 小蓝蝴蝶结 + 呆毛！
			_rect(img, 10, 3 + hy, 12, 2, Color("#ffffff"))
			_px(img, 9, 4 + hy, Color("#e4ecff"))
			_px(img, 22, 4 + hy, Color("#e4ecff"))
			_px(img, 13, 1 + hy, hair); _px(img, 14, 2 + hy, hair) # 呆毛
			_rect(img, 5, 9 + hy, 4, 3, Color("#3d4f82"))  # 左鲸鳍耳
			_px(img, 4, 11 + hy, Color("#607ab0"))
			_rect(img, 23, 9 + hy, 4, 3, Color("#3d4f82")) # 右鲸鳍耳
			_px(img, 27, 11 + hy, Color("#607ab0"))
			_rect(img, 21, 6 + hy, 3, 2, Color("#6cd8ff")) # 小蓝蝴蝶结
		"qwen":
			# 靛紫白边国风小贝雷帽 + 侧编长麻花辫
			_rect(img, 8, 2 + hy, 8, 3, Color("#353572"))
			_rect(img, 8, 4 + hy, 7, 1, Color("#f4f6ff"))
			_px(img, 11, 3 + hy, Color("#c8d6ff")) # 帽徽
			_rect(img, 19, 13 + hy, 3, 8, Color("#6e7ce6")) # 侧麻花辫
			_px(img, 20, 15 + hy, Color("#c0ccff"))
			_px(img, 20, 18 + hy, Color("#c0ccff"))
		"gemini":
			# 招牌蓝粉大猫耳 + 四芒星发卡 + 双丸子头！
			_rect(img, 8, 1 + hy, 4, 5, Color("#70a4ff"))
			_rect(img, 9, 2 + hy, 2, 3, Color("#ffb4d8")) # 猫耳内粉
			_rect(img, 20, 1 + hy, 4, 5, Color("#70a4ff"))
			_rect(img, 21, 2 + hy, 2, 3, Color("#ffb4d8"))
			_rect(img, 21, 5 + hy, 3, 3, Color("#c8b8ff")) # 星芒发饰
			_px(img, 22, 6 + hy, Color("#fff6c4"))
			_px(img, 15, 2 + hy, Color("#70a4ff"))         # 呆毛

	return _add_outline(img, Color("#191326"))


# ================= 6 种像素武器（向右朝向） =================
static func _build_weapon(wid: String) -> Image:
	var img := Image.create(18, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match wid:
		"grimoire":
			_rect(img, 4, 2, 10, 10, Color("#5c2e1c"))
			_rect(img, 5, 3, 8, 8, Color("#7d3e24"))
			_rect(img, 4, 2, 2, 10, Color("#d4a24a"))
			_rect(img, 13, 3, 1, 8, Color("#f7eedb"))
			_rect(img, 8, 5, 3, 4, Color("#ffaa38"))
			_px(img, 9, 6, Color.WHITE)
		"bow":
			_rect(img, 8, 1, 3, 2, Color("#ffffff"))
			_rect(img, 10, 3, 2, 2, Color("#b8c8f0"))
			_rect(img, 11, 5, 2, 4, Color("#76d6ff"))
			_rect(img, 10, 9, 2, 2, Color("#b8c8f0"))
			_rect(img, 8, 11, 3, 2, Color("#ffffff"))
			for y in range(2, 12):
				_px(img, 8, y, Color("#e8f8ff"))
		"halberd":
			_rect(img, 1, 6, 13, 2, Color("#26222c"))
			_rect(img, 11, 2, 3, 10, Color("#201c26"))
			_rect(img, 13, 3, 3, 3, Color("#d9af52"))
			_rect(img, 13, 8, 3, 3, Color("#d9af52"))
			_rect(img, 14, 6, 3, 2, Color("#e82d44"))
		"basin":
			# 精钢不锈钢大铁盆：卷边亮银盆沿 + 立体深蓝钢内壁 + 镜面竖向金属高光 + DeepSeek 蓝边饰！
			_rect(img, 1, 3, 16, 2, Color("#eef6ff"))  # 宽大亮银卷边盆沿
			_rect(img, 2, 3, 14, 1, Color("#ffffff"))  # 顶部高光沿
			_rect(img, 3, 5, 12, 2, Color("#566c90"))  # 盆口内壁立体阴影
			_rect(img, 5, 5, 7, 1, Color("#7d98bf"))   # 盆内反光
			_rect(img, 2, 6, 14, 4, Color("#b6c9e2"))  # 不锈钢盆身主体
			_rect(img, 3, 10, 12, 2, Color("#8ea5c6")) # 盆底收弧
			_rect(img, 5, 11, 8, 1, Color("#6e84a8"))  # 盆底暗面
			_rect(img, 4, 6, 3, 5, Color("#eef6ff"))   # 镜面银白金属高光带
			_px(img, 5, 7, Color("#ffffff")); _px(img, 5, 8, Color("#ffffff"))
			_rect(img, 12, 7, 2, 3, Color("#748cb0"))  # 右侧金属暗反光
			_rect(img, 8, 8, 3, 1, Color("#3a86ff"))   # DeepSeek 小蓝鲸徽记条
		"fan":
			_rect(img, 3, 6, 4, 2, Color("#d4b468"))
			_rect(img, 6, 4, 4, 6, Color("#565cb8"))
			_rect(img, 9, 2, 4, 10, Color("#f2f0ff"))
			_rect(img, 12, 3, 2, 8, Color("#7c72e6"))
			_px(img, 11, 5, Color("#ffd878"))
			_px(img, 11, 8, Color("#ffd878"))
		"starblade":
			var c1 := Color("#66b4ff")
			var c2 := Color("#ff9cd8")
			_rect(img, 8, 2, 2, 10, c1)
			_rect(img, 4, 6, 10, 2, c2)
			_rect(img, 7, 5, 4, 4, Color("#e8f4ff"))
			_rect(img, 8, 6, 2, 2, Color.WHITE)
	return _add_outline(img, Color("#151220"))


# ================= 像素 Token 晶片（带 T 字徽记与发光引脚！）=================
static func _build_token_chip(tier: int) -> Image:
	var sz := 11 + tier * 2  # 11 / 13 / 15
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color("#1692c4")
	var rim := Color("#4ceeff")
	var core := Color("#e8fcff")
	if tier == 1:
		body = Color("#c87c16"); rim = Color("#ffd447"); core = Color("#fff8cc")
	elif tier >= 2:
		body = Color("#7a28c8"); rim = Color("#df78ff"); core = Color("#fff0ff")

	var pad := 2
	var inner := sz - pad * 2
	# 晶片主体方块（四角微切）
	_rect(img, pad, pad, inner, inner, body)
	_rect(img, pad + 1, pad, inner - 2, 1, rim)
	_rect(img, pad + 1, sz - pad - 1, inner - 2, 1, rim)
	_rect(img, pad, pad + 1, 1, inner - 2, rim)
	_rect(img, sz - pad - 1, pad + 1, 1, inner - 2, rim)
	# 芯片四周金色小引脚
	var mid := sz / 2
	_px(img, mid, 1, rim); _px(img, mid, sz - 2, rim)
	_px(img, 1, mid, rim); _px(img, sz - 2, mid, rim)
	# 中心清晰像素「T」(Token!)
	_rect(img, mid - 2, mid - 2, 5, 1, core)
	_rect(img, mid, mid - 2, 1, 5, core)
	return _add_outline(img, Color("#131020"))


# ================= 5 种 AI 主题像素怪（新增 Prompt 注入自爆炸弹怪）=================
static func _build_monster(kind: String) -> Image:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"glitch":
			_rect(img, 3, 6, 12, 9, Color("#3ce672"))
			_rect(img, 5, 4, 8, 3, Color("#70ff98"))
			_rect(img, 2, 11, 14, 4, Color("#24b856"))
			_rect(img, 12, 6, 3, 2, Color("#ff45b5"))
			_px(img, 4, 13, Color("#40f2ff"))
			_rect(img, 5, 9, 2, 2, Color("#141820"))
			_rect(img, 11, 9, 2, 2, Color("#141820"))
			_px(img, 5, 9, Color.WHITE); _px(img, 11, 9, Color.WHITE)
		"hallucination":
			_rect(img, 4, 3, 10, 10, Color("#a052ff"))
			_rect(img, 6, 2, 6, 2, Color("#d49eff"))
			_rect(img, 3, 12, 3, 4, Color("#7630d6"))
			_rect(img, 8, 12, 2, 4, Color("#7630d6"))
			_rect(img, 12, 12, 3, 4, Color("#7630d6"))
			_rect(img, 5, 7, 3, 2, Color("#ffe866"))
			_rect(img, 10, 7, 3, 2, Color("#ff5ca8"))
		"spam_tank":
			_rect(img, 2, 3, 14, 12, Color("#c9382c"))
			_rect(img, 4, 5, 10, 8, Color("#f26b3a"))
			_rect(img, 4, 2, 10, 2, Color("#404658"))
			_rect(img, 3, 14, 4, 2, Color("#2b2f3c"))
			_rect(img, 11, 14, 4, 2, Color("#2b2f3c"))
			_rect(img, 5, 7, 8, 2, Color("#ffec6e"))
			_px(img, 8, 7, Color("#241820")); _px(img, 9, 7, Color("#241820"))
		"prompt_bomb":
			# Prompt 注入自爆炸弹怪（暗红圆球 + 发光引信 + 惊叹号警告脸！）
			_rect(img, 4, 5, 10, 10, Color("#3a1b26"))
			_rect(img, 5, 6, 8, 8, Color("#d92b45"))
			_rect(img, 6, 4, 6, 2, Color("#5a5e70")) # 炸弹盖
			_rect(img, 8, 2, 2, 2, Color("#ffd858")) # 燃烧引信
			_px(img, 10, 1, Color("#fff8b0"))       # 火花
			_rect(img, 8, 7, 2, 4, Color("#fff5cc")) # 惊叹号 !
			_rect(img, 8, 12, 2, 1, Color("#fff5cc"))
		"boss":
			_rect(img, 2, 4, 14, 11, Color("#3a1b5c"))
			_rect(img, 4, 2, 3, 3, Color("#ffbe3b"))
			_rect(img, 11, 2, 3, 3, Color("#ffbe3b"))
			_rect(img, 4, 6, 10, 7, Color("#5e288f"))
			_rect(img, 5, 7, 3, 3, Color("#ff3058"))
			_rect(img, 10, 7, 3, 3, Color("#ff3058"))
			_px(img, 6, 8, Color.WHITE); _px(img, 11, 8, Color.WHITE)
			_rect(img, 6, 11, 6, 2, Color("#ffbe3b"))
			_rect(img, 3, 14, 12, 2, Color("#241038"))
	return _add_outline(img, Color("#151120"))


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


static func _add_outline(src: Image, outline_col: Color) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := src.duplicate()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.1:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.1:
					out.set_pixel(x, y, outline_col)
					break
	return out
