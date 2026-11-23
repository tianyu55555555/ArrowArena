class_name NetManager
extends Node
## 局域网联机引擎（Godot ENetMultiplayerPeer + UDP 局域网房间自动发现）：
## - 支持房主权威同步：PVE 双人无尽合作（怪血强化+倒地互救）、PVP 自由乱斗（可选人机）、PVP 2v2v2v2 组队（可选人机）
## - 固定挂载于 /root/NetManager，保证跨大厅/加载页/战场 RPC 路径恒定不失效

const GAME_PORT := 7777
const DISCOVERY_PORT := 7778
const TEAM_NAMES := ["", "红队", "蓝队", "绿队", "黄队"]
const TEAM_COLORS := [
	Color.WHITE,
	Color("#ff4d6d"),
	Color("#3fa9ff"),
	Color("#42e67c"),
	Color("#ffd447"),
]

signal room_updated
signal connection_status(msg: String, is_error: bool)
signal discovery_updated
signal match_started(seed_val: int, cfg: Dictionary, roster: Dictionary)
signal returned_to_room
signal snapshot_received(snap: Dictionary)
signal pickups_received(pk: Dictionary)
signal fx_received(kind: String, pos: Vector2, extra: Dictionary)
signal proj_received(shooter_nid: int, pos: Vector2, dir: Vector2, wid: String, pscale: float, evolved: bool)
signal choices_received(choices: Array)
signal banner_received(text: String, col: Color)
signal feed_received(text: String)
signal emote_received(sender_nid: int, text: String)
signal match_over_received(reason: String, standings: Array, is_victory: bool)

static var inst: NetManager = null

var role := "offline"  # "offline" | "host" | "client"
var in_battle := false
var my_id := 1
var room_cfg: Dictionary = {
	"mode": "pve_coop",  # "pve_coop" | "pvp_ffa" | "pvp_2v2v2v2"
	"fill_bots": true,
	"room_name": "AI 娘联机房",
}
# peer_id (int) -> {"id": int, "name": String, "char": String, "weapon": String, "team": int}
var players: Dictionary = {}
# peer_id (int) -> {"move": Vector2, "aim": Vector2, "fire": bool, "active_seq": int}
var client_inputs: Dictionary = {}
var discovered_rooms: Dictionary = {}  # ip -> Dictionary

var _peer: ENetMultiplayerPeer = null
var _udp_broadcaster: PacketPeerUDP = null
var _udp_listener: PacketPeerUDP = null
var _beacon_t := 0.0
var _pending_profile: Dictionary = {}


static func ensure(root: Node) -> NetManager:
	if inst != null and is_instance_valid(inst):
		return inst
	var existing := root.get_node_or_null("NetManager") as NetManager
	if existing != null:
		inst = existing
		return inst
	var nm := NetManager.new()
	nm.name = "NetManager"
	nm.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(nm)
	inst = nm
	return nm


static func is_online() -> bool:
	return inst != null and inst.role != "offline"


static func is_host() -> bool:
	return inst != null and inst.role == "host"


static func is_client() -> bool:
	return inst != null and inst.role == "client"


static func mode_label(m: String) -> String:
	match m:
		"pve_coop": return "PVE 双人无尽合作"
		"pvp_2v2v2v2": return "PVP 2v2v2v2 组队"
		_: return "PVP 竞技乱斗"


static func max_players_for(m: String) -> int:
	return 2 if m == "pve_coop" else 8


static func get_local_ipv4() -> String:
	var best := "127.0.0.1"
	for addr in IP.get_local_addresses():
		if addr.find(":") != -1:
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
		if addr != "127.0.0.1" and best == "127.0.0.1":
			best = addr
	return best


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	leave_room()
	stop_discovery()
	if inst == self:
		inst = null


# ================= 创建 / 加入 / 退出房间 =================
func host_room(player_name: String, char_id: String, weapon_id: String, port := GAME_PORT) -> int:
	leave_room()
	stop_discovery()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, 8)
	if err != OK:
		connection_status.emit("开房失败（端口 %d 可能被占用）" % port, true)
		return err
	multiplayer.multiplayer_peer = p
	_peer = p
	role = "host"
	my_id = 1
	in_battle = false
	players.clear()
	client_inputs.clear()
	room_cfg["room_name"] = "%s 的房间" % player_name
	players[1] = {
		"id": 1,
		"name": player_name,
		"char": char_id,
		"weapon": weapon_id,
		"team": 1,
	}
	_start_udp_beacon()
	connection_status.emit("已开启局域网房间！本机 IP：%s:%d" % [get_local_ipv4(), port], false)
	room_updated.emit()
	return OK


func join_room(ip: String, player_name: String, char_id: String, weapon_id: String, port := GAME_PORT) -> int:
	leave_room()
	var clean_ip := ip.strip_edges()
	if clean_ip == "":
		clean_ip = "127.0.0.1"
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(clean_ip, port)
	if err != OK:
		connection_status.emit("连接 %s:%d 失败！" % [clean_ip, port], true)
		return err
	multiplayer.multiplayer_peer = p
	_peer = p
	role = "client"
	in_battle = false
	players.clear()
	_pending_profile = {
		"name": player_name,
		"char": char_id,
		"weapon": weapon_id,
	}
	connection_status.emit("正在连接 %s:%d ..." % [clean_ip, port], false)
	return OK


func leave_room() -> void:
	_stop_udp_beacon()
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	role = "offline"
	in_battle = false
	my_id = 1
	players.clear()
	client_inputs.clear()
	room_updated.emit()


# ================= UDP 局域网房间发现 =================
func _start_udp_beacon() -> void:
	_stop_udp_beacon()
	_udp_broadcaster = PacketPeerUDP.new()
	_udp_broadcaster.set_broadcast_enabled(true)
	_beacon_t = 0.0


func _stop_udp_beacon() -> void:
	if _udp_broadcaster != null:
		_udp_broadcaster.close()
		_udp_broadcaster = null


func start_discovery() -> void:
	stop_discovery()
	discovered_rooms.clear()
	_udp_listener = PacketPeerUDP.new()
	var err := _udp_listener.bind(DISCOVERY_PORT)
	if err != OK:
		# 同机多开时端口 7778 可能已被另一个客户端占用，静默降级为手动输入 IP 即可
		_udp_listener = null


func stop_discovery() -> void:
	if _udp_listener != null:
		_udp_listener.close()
		_udp_listener = null


func _process(delta: float) -> void:
	if role == "host" and _udp_broadcaster != null:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var payload := JSON.stringify({
				"app": "ArrowArena",
				"name": str(room_cfg.get("room_name", "AI 娘房间")),
				"mode": str(room_cfg.get("mode", "pve_coop")),
				"players": players.size(),
				"max": max_players_for(str(room_cfg.get("mode", "pve_coop"))),
				"port": GAME_PORT,
				"in_game": in_battle,
			}).to_utf8_buffer()
			_udp_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			_udp_broadcaster.put_packet(payload)
			_udp_broadcaster.set_dest_address("127.0.0.1", DISCOVERY_PORT)
			_udp_broadcaster.put_packet(payload)

	if _udp_listener != null:
		var changed := false
		while _udp_listener.get_available_packet_count() > 0:
			var pkt := _udp_listener.get_packet()
			var ip := _udp_listener.get_packet_ip()
			var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary and str((parsed as Dictionary).get("app", "")) == "ArrowArena":
				var d := parsed as Dictionary
				d["ip"] = ip
				d["seen"] = Time.get_ticks_msec()
				discovered_rooms[ip] = d
				changed = true
		var now := Time.get_ticks_msec()
		for k in discovered_rooms.keys():
			if now - int((discovered_rooms[k] as Dictionary).get("seen", 0)) > 4000:
				discovered_rooms.erase(k)
				changed = true
		if changed:
			discovery_updated.emit()


# ================= 房主配置 / 角色更新 / 开战 =================
func host_set_mode(new_mode: String) -> void:
	if role != "host":
		return
	room_cfg["mode"] = new_mode
	if new_mode == "pve_coop":
		room_cfg["fill_bots"] = false
		for pid in players:
			players[pid]["team"] = 1
	elif new_mode == "pvp_2v2v2v2":
		_rebalance_teams()
	else:
		for pid in players:
			players[pid]["team"] = 0
	_broadcast_room_state()


func host_set_fill_bots(enabled: bool) -> void:
	if role != "host":
		return
	room_cfg["fill_bots"] = enabled
	_broadcast_room_state()


func update_my_profile(char_id: String, weapon_id: String, team := -1) -> void:
	if role == "host":
		if players.has(1):
			players[1]["char"] = char_id
			players[1]["weapon"] = weapon_id
			if team >= 0 and str(room_cfg["mode"]) == "pvp_2v2v2v2":
				players[1]["team"] = clampi(team, 1, 4)
			_broadcast_room_state()
	elif role == "client":
		_pending_profile["char"] = char_id
		_pending_profile["weapon"] = weapon_id
		if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			rpc_id(1, "c2s_update_profile", char_id, weapon_id, team)


func host_start_match() -> void:
	if role != "host":
		return
	in_battle = true
	var seed_val := randi()
	s2c_start_match.rpc(seed_val, room_cfg.duplicate(true), players.duplicate(true))
	match_started.emit(seed_val, room_cfg.duplicate(true), players.duplicate(true))


func host_return_to_room() -> void:
	if role != "host":
		return
	in_battle = false
	s2c_return_room.rpc()
	returned_to_room.emit()
	_broadcast_room_state()


func _rebalance_teams() -> void:
	var idx := 0
	for pid in players:
		players[pid]["team"] = (idx / 2) % 4 + 1
		idx += 1


func _pick_open_team() -> int:
	if str(room_cfg["mode"]) == "pve_coop":
		return 1
	if str(room_cfg["mode"]) != "pvp_2v2v2v2":
		return 0
	var counts := {1: 0, 2: 0, 3: 0, 4: 0}
	for pid in players:
		var t := int(players[pid].get("team", 1))
		if counts.has(t):
			counts[t] = int(counts[t]) + 1
	for tid in [1, 2, 3, 4]:
		if int(counts[tid]) < 2:
			return tid
	return 1


func _broadcast_room_state() -> void:
	if role == "host":
		s2c_room_state.rpc(room_cfg.duplicate(true), players.duplicate(true))
	room_updated.emit()


# ================= ENet 连接回调 =================
func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if role == "host":
		if players.has(id):
			var pname := str(players[id].get("name", "玩家"))
			players.erase(id)
			client_inputs.erase(id)
			feed_received.emit("%s 离开了房间" % pname)
			if in_battle:
				s2c_feed.rpc("%s 离开了房间" % pname)
			_broadcast_room_state()


func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	connection_status.emit("已加入房间！正在同步房主配置...", false)
	rpc_id(1, "c2s_register_player",
		str(_pending_profile.get("name", "玩家")),
		str(_pending_profile.get("char", "claude")),
		str(_pending_profile.get("weapon", "grimoire"))
	)


func _on_connection_failed() -> void:
	leave_room()
	connection_status.emit("连接超时或房间不可达，请检查房主局域网 IP！", true)


func _on_server_disconnected() -> void:
	leave_room()
	connection_status.emit("房主已关闭房间或断开连接", true)
	returned_to_room.emit()


# ================= RPC：大厅与战斗同步 =================
@rpc("any_peer", "call_remote", "reliable")
func c2s_register_player(pname: String, char_id: String, weapon_id: String) -> void:
	if role != "host":
		return
	var sid := multiplayer.get_remote_sender_id()
	var m := str(room_cfg.get("mode", "pve_coop"))
	if in_battle:
		s2c_reject.rpc_id(sid, "该房间正在激战中，请稍候加入！")
		return
	if players.size() >= max_players_for(m):
		s2c_reject.rpc_id(sid, "房间已满（%s 最多 %d 人）！" % [mode_label(m), max_players_for(m)])
		return
	players[sid] = {
		"id": sid,
		"name": pname.substr(0, 12),
		"char": char_id,
		"weapon": weapon_id,
		"team": _pick_open_team(),
	}
	client_inputs[sid] = {"move": Vector2.ZERO, "aim": Vector2.RIGHT, "fire": false, "active_seq": 0}
	_broadcast_room_state()


@rpc("any_peer", "call_remote", "reliable")
func c2s_update_profile(char_id: String, weapon_id: String, team: int) -> void:
	if role != "host":
		return
	var sid := multiplayer.get_remote_sender_id()
	if not players.has(sid):
		return
	players[sid]["char"] = char_id
	players[sid]["weapon"] = weapon_id
	if team >= 1 and team <= 4 and str(room_cfg["mode"]) == "pvp_2v2v2v2":
		# 检查目标队是否少于 2 人
		var cnt := 0
		for pid in players:
			if pid != sid and int(players[pid].get("team", 0)) == team:
				cnt += 1
		if cnt < 2:
			players[sid]["team"] = team
	_broadcast_room_state()


@rpc("authority", "call_remote", "reliable")
func s2c_reject(reason: String) -> void:
	leave_room()
	connection_status.emit(reason, true)


@rpc("authority", "call_remote", "reliable")
func s2c_room_state(cfg: Dictionary, roster: Dictionary) -> void:
	room_cfg = cfg
	players = roster
	room_updated.emit()


@rpc("authority", "call_remote", "reliable")
func s2c_start_match(seed_val: int, cfg: Dictionary, roster: Dictionary) -> void:
	room_cfg = cfg
	players = roster
	in_battle = true
	match_started.emit(seed_val, cfg, roster)


@rpc("authority", "call_remote", "reliable")
func s2c_return_room() -> void:
	in_battle = false
	returned_to_room.emit()


# ---- 战中客户端 -> 房主输入与选卡 ----
@rpc("any_peer", "call_remote", "unreliable_ordered")
func c2s_input(move_dir: Vector2, aim_dir: Vector2, wants_fire: bool, active_seq: int) -> void:
	if role != "host":
		return
	var sid := multiplayer.get_remote_sender_id()
	client_inputs[sid] = {
		"move": move_dir.limit_length(1.0),
		"aim": aim_dir.normalized() if aim_dir.length_squared() > 0.001 else Vector2.RIGHT,
		"fire": wants_fire,
		"active_seq": active_seq,
	}


@rpc("any_peer", "call_remote", "reliable")
func c2s_pick_skill(skill_id: String) -> void:
	if role != "host":
		return
	var sid := multiplayer.get_remote_sender_id()
	# 转发给当前战场 Game 处理
	var g := _find_game()
	if g != null:
		g.host_apply_client_skill(sid, skill_id)


@rpc("any_peer", "call_remote", "reliable")
func c2s_reroll_skill() -> void:
	if role != "host":
		return
	var sid := multiplayer.get_remote_sender_id()
	var g := _find_game()
	if g != null:
		g.host_reroll_client_skill(sid)


@rpc("any_peer", "call_remote", "reliable")
func c2s_emote(text: String) -> void:
	if role != "host":
		return
	var sid := multiplayer.get_remote_sender_id()
	var clean := text.strip_edges().substr(0, 28)
	if clean == "":
		return
	var g := _find_game()
	if g != null:
		g.broadcast_emote(sid, clean)


# ---- 战中房主 -> 客户端广播 ----
@rpc("authority", "call_remote", "reliable")
func s2c_snapshot(snap: Dictionary) -> void:
	snapshot_received.emit(snap)


@rpc("authority", "call_remote", "reliable")
func s2c_pickups(pk: Dictionary) -> void:
	pickups_received.emit(pk)


@rpc("authority", "call_remote", "reliable")
func s2c_spawn_proj(shooter_nid: int, pos: Vector2, dir: Vector2, wid: String, pscale: float, evolved: bool) -> void:
	proj_received.emit(shooter_nid, pos, dir, wid, pscale, evolved)


@rpc("authority", "call_remote", "reliable")
func s2c_fx(kind: String, pos: Vector2, extra: Dictionary) -> void:
	fx_received.emit(kind, pos, extra)


@rpc("authority", "call_remote", "reliable")
func s2c_level_choices(choices: Array) -> void:
	choices_received.emit(choices)


@rpc("authority", "call_remote", "reliable")
func s2c_banner(text: String, col: Color) -> void:
	banner_received.emit(text, col)


@rpc("authority", "call_remote", "reliable")
func s2c_feed(text: String) -> void:
	feed_received.emit(text)


@rpc("authority", "call_remote", "reliable")
func s2c_emote(sender_nid: int, text: String) -> void:
	emote_received.emit(sender_nid, text)


@rpc("authority", "call_remote", "reliable")
func s2c_match_over(reason: String, standings: Array, is_victory: bool) -> void:
	in_battle = false
	match_over_received.emit(reason, standings, is_victory)


func _find_game() -> Game:
	var p := get_parent()
	if p != null:
		for ch in p.get_children():
			if ch is Game:
				return ch as Game
	return null
