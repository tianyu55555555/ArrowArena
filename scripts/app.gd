class_name App
extends Node
## 顶层路由：管理 存档(MetaSave) + 音效与8-bit BGM(Sfx) + 局域网联机(NetManager) + 备战大厅 -> 科普加载页 -> 双模式战场

var selected_char := "claude"
var selected_weapon := "grimoire"
var selected_mode := "pvp"
var selected_pvp_var := "ffa"
var selected_diff := "normal"

var _current: Node = null
var _shot_mode := ""
var _shot_path := ""
var _demo_levelup := false
var _demo_pick := false
var _demo_pause := false
var _demo_midboss := false
var _demo_blessing := false
var _demo_storm := false
var _demo_talents := false
var _demo_codex := false
var _demo_lan := false
var _demo_lan_host := false
var _demo_spawn_pos := Vector2.INF
var _demo_skill_capture := -1.0
var _autotest := false
var _lan_host_test := ""
var _lan_join_test := ""
var _override_time := -1.0
var _shot_timer := 0.0
var _shot_done := false


func _ready() -> void:
	randomize()
	MetaSave.ensure_loaded()
	Sfx.ensure(self)
	var nm := NetManager.ensure(self)
	nm.match_started.connect(_on_lan_match_started)
	nm.returned_to_room.connect(_on_lan_returned_to_room)

	var weapon_explicit := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--char="):
			selected_char = arg.substr(7)
		elif arg.begins_with("--weapon="):
			selected_weapon = arg.substr(9)
			weapon_explicit = true
		elif arg.begins_with("--mode="):
			selected_mode = arg.substr(7)
		elif arg.begins_with("--pvp-var="):
			selected_pvp_var = arg.substr(10)
		elif arg.begins_with("--diff="):
			selected_diff = arg.substr(7)
		elif arg.begins_with("--shot-lobby="):
			_shot_mode = "lobby"; _shot_path = arg.substr(13)
		elif arg.begins_with("--shot-talents="):
			_shot_mode = "lobby"; _shot_path = arg.substr(15); _demo_talents = true
		elif arg.begins_with("--shot-codex="):
			_shot_mode = "lobby"; _shot_path = arg.substr(13); _demo_codex = true
		elif arg.begins_with("--shot-lan="):
			_shot_mode = "lobby"; _shot_path = arg.substr(11); _demo_lan = true
		elif arg.begins_with("--shot-lan-room="):
			_shot_mode = "lobby"; _shot_path = arg.substr(16); _demo_lan = true; _demo_lan_host = true
		elif arg.begins_with("--shot-loading="):
			_shot_mode = "loading"; _shot_path = arg.substr(15)
		elif arg.begins_with("--shot-play="):
			_shot_mode = "play"; _shot_path = arg.substr(12)
		elif arg.begins_with("--shot-pause="):
			_shot_mode = "play"; _shot_path = arg.substr(13); _demo_pause = true
		elif arg.begins_with("--shot-levelup="):
			_shot_mode = "levelup"; _shot_path = arg.substr(15); _demo_levelup = true
		elif arg.begins_with("--shot-pick="):
			_shot_mode = "pick"; _shot_path = arg.substr(12); _demo_levelup = true; _demo_pick = true
		elif arg.begins_with("--demo-skill="):
			_demo_skill_capture = float(arg.substr(13))
		elif arg == "--demo-midboss":
			_demo_midboss = true
		elif arg == "--demo-blessing":
			_demo_blessing = true
		elif arg == "--demo-storm":
			_demo_storm = true
		elif arg.begins_with("--demo-pos="):
			var parts := arg.substr(11).split(",")
			if parts.size() == 2:
				_demo_spawn_pos = Vector2(float(parts[0]), float(parts[1]))
		elif arg.begins_with("--lan-host-test="):
			_lan_host_test = arg.substr(16)
		elif arg.begins_with("--lan-join-test="):
			_lan_join_test = arg.substr(16)
		elif arg == "--autotest":
			_autotest = true
		elif arg.begins_with("--time="):
			_override_time = float(arg.substr(7))

	if not weapon_explicit:
		selected_weapon = str(Characters.get_data(selected_char)["weapon"])

	# 双进程局域网联机自动验收钩子（房主 / 客户端）
	if _lan_host_test != "":
		nm.host_room("房主DeepSeek", selected_char, selected_weapon)
		nm.host_set_mode(_lan_host_test)
		_open_lobby(true)
		nm.room_updated.connect(func() -> void:
			if nm.players.size() >= 2 and not nm.in_battle:
				print("LAN HOST: 2 players ready! Starting match mode=", _lan_host_test)
				nm.host_start_match()
		)
		return
	if _lan_join_test != "":
		nm.join_room(_lan_join_test, "队友Gemini", selected_char, selected_weapon)
		_open_lobby(true)
		return

	if _demo_lan_host:
		nm.host_room("房主DeepSeek", selected_char, selected_weapon)
		nm.host_set_mode("pvp_2v2v2v2")

	if _autotest or _shot_mode == "play" or _shot_mode == "levelup" or _shot_mode == "pick":
		_open_battle()
	elif _shot_mode == "loading":
		_open_loading()
	else:
		_open_lobby(_demo_lan)


func _swap(node: Node, in_ui_layer := false) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	if in_ui_layer:
		var layer := CanvasLayer.new()
		layer.add_child(node)
		_current = layer
		add_child(layer)
	else:
		_current = node
		add_child(node)


func _open_lobby(open_lan := false) -> void:
	get_tree().paused = false
	Sfx.play_bgm("lobby")
	var lb := Lobby.new()
	lb.selected_char = selected_char
	lb.selected_weapon = selected_weapon
	lb.selected_mode = selected_mode
	lb.selected_pvp_var = selected_pvp_var
	lb.selected_diff = selected_diff
	lb.open_talents_on_ready = _demo_talents
	lb.open_codex_on_ready = _demo_codex
	lb.open_lan_on_ready = open_lan
	lb.start_battle.connect(_on_start_battle)
	_swap(lb, true)


func _on_start_battle(cid: String, wid: String, mode: String, diff_id: String, pvp_var: String) -> void:
	selected_char = cid
	selected_weapon = wid
	selected_mode = mode
	selected_diff = diff_id
	selected_pvp_var = pvp_var
	_open_loading()


func _open_loading() -> void:
	get_tree().paused = false
	var ls := LoadingScreen.new()
	ls.char_id = selected_char
	ls.weapon_id = selected_weapon
	ls.game_mode = selected_mode
	ls.difficulty_id = selected_diff
	ls.auto_advance = _autotest
	ls.finished.connect(_open_battle)
	_swap(ls, true)


func _open_battle() -> void:
	get_tree().paused = false
	var g := Game.new()
	g.game_mode = selected_mode
	g.pvp_variant = selected_pvp_var
	g.difficulty_id = selected_diff
	g.player_char_id = selected_char
	g.player_weapon_id = selected_weapon
	g.autotest = _autotest
	g.net_role = "offline"
	g.demo_midboss = _demo_midboss
	g.demo_blessing = _demo_blessing
	g.demo_storm = _demo_storm
	if _override_time > 0.0:
		g.override_time = _override_time
	if _shot_mode == "play" or _shot_mode == "levelup" or _shot_mode == "pick":
		g.shot_path = _shot_path
		g.demo_levelup = _demo_levelup
		g.demo_pick = _demo_pick
		g.demo_pause = _demo_pause
		g.demo_spawn_pos = _demo_spawn_pos
		g.demo_skill_capture = _demo_skill_capture
	g.request_rematch.connect(_open_loading)
	g.request_lobby.connect(_open_lobby)
	_swap(g)


func _on_lan_match_started(seed_val: int, cfg: Dictionary, roster: Dictionary) -> void:
	get_tree().paused = false
	var nm := NetManager.inst
	var m := str(cfg.get("mode", "pve_coop"))
	var g := Game.new()
	g.net_role = nm.role
	g.map_seed = seed_val
	g.lan_roster = roster
	g.fill_bots = bool(cfg.get("fill_bots", true))
	if m == "pve_coop":
		g.game_mode = "survivor"
		g.is_coop = true
		g.difficulty_id = "endless"
	else:
		g.game_mode = "pvp"
		g.is_coop = false
		g.pvp_variant = "2v2v2v2" if m == "pvp_2v2v2v2" else "ffa"
	var my_info: Dictionary = roster.get(nm.my_id, {})
	g.player_char_id = str(my_info.get("char", selected_char))
	g.player_weapon_id = str(my_info.get("weapon", selected_weapon))
	g.autotest = _autotest or _lan_host_test != "" or _lan_join_test != ""
	if _override_time > 0.0:
		g.override_time = _override_time
	g.request_rematch.connect(_open_lobby.bind(true))
	g.request_lobby.connect(_open_lobby.bind(true))
	_swap(g)


func _on_lan_returned_to_room() -> void:
	_open_lobby(NetManager.is_online())


func _process(delta: float) -> void:
	if _shot_done or (_shot_mode != "lobby" and _shot_mode != "loading"):
		return
	_shot_timer += delta
	if _shot_timer > 1.2:
		_shot_done = true
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("screenshot saved: ", _shot_path)
		get_tree().quit()
