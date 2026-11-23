class_name Sfx
extends Node
## 程序化复古二次元音效引擎：纯代码合成 16-bit PCM 音效，无需外部音频文件；带声道池与节流防爆音

const MIX_RATE := 22050
const POOL_SIZE := 14

static var muted := false
static var bgm_muted := false
static var _inst: Sfx = null

var _streams: Dictionary = {}
var _bgm_streams: Dictionary = {}
var _bgm_player: AudioStreamPlayer = null
var _bgm_track := ""
var _players: Array[AudioStreamPlayer] = []
var _cursor := 0
var _last_play_ms: Dictionary = {}
var _orb_combo := 0
var _orb_combo_ms := 0


static func ensure(parent: Node) -> Sfx:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var s := Sfx.new()
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(s)
	_inst = s
	return s


static func play(id: String, pitch_jitter := 0.06, min_gap_ms := 40, vol_db := -8.0) -> void:
	if muted or _inst == null or not is_instance_valid(_inst):
		return
	_inst._play_internal(id, pitch_jitter, min_gap_ms, vol_db)


static func toggle_mute() -> bool:
	muted = not muted
	return muted


static func play_bgm(track: String) -> void:
	if _inst == null or not is_instance_valid(_inst):
		return
	_inst._play_bgm_internal(track)


static func toggle_bgm_mute() -> bool:
	bgm_muted = not bgm_muted
	if _inst != null and is_instance_valid(_inst) and _inst._bgm_player != null:
		if bgm_muted:
			_inst._bgm_player.stop()
		elif _inst._bgm_track != "":
			_inst._play_bgm_internal(_inst._bgm_track, true)
	return bgm_muted


func _exit_tree() -> void:
	_streams.clear()
	_bgm_streams.clear()
	if _inst == self:
		_inst = null


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)
	_build_all_sounds()


func _play_bgm_internal(track: String, force := false) -> void:
	if not force and _bgm_track == track and _bgm_player.playing:
		return
	_bgm_track = track
	if bgm_muted or DisplayServer.get_name() == "headless":
		return
	if not _bgm_streams.has(track):
		_bgm_streams[track] = _synth_bgm(track)
	_bgm_player.stream = _bgm_streams[track]
	_bgm_player.volume_db = -14.5 if track == "lobby" else -15.5
	_bgm_player.play()


func _play_internal(id: String, pitch_jitter: float, min_gap_ms: int, vol_db: float) -> void:
	if not _streams.has(id):
		return
	var now := Time.get_ticks_msec()
	var prev := int(_last_play_ms.get(id, 0))
	if now - prev < min_gap_ms:
		return
	_last_play_ms[id] = now

	var pitch := 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	if id == "orb":
		if now - _orb_combo_ms < 360:
			_orb_combo = mini(_orb_combo + 1, 10)
		else:
			_orb_combo = 0
		_orb_combo_ms = now
		pitch = 1.0 + _orb_combo * 0.045

	var p := _players[_cursor]
	_cursor = (_cursor + 1) % POOL_SIZE
	p.stream = _streams[id]
	p.volume_db = vol_db
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()


func _build_all_sounds() -> void:
	# 6 种武器发射音效
	_streams["shoot_bow"] = _synth_sweep(0.09, 680.0, 260.0, "tri", 0.35, 0.15)
	_streams["shoot_grimoire"] = _synth_chord([587.3, 880.0], 0.13, "sine", 0.30, 1.15)
	_streams["shoot_halberd"] = _synth_sweep(0.11, 240.0, 85.0, "saw", 0.35, 0.35)
	_streams["shoot_laser"] = _synth_sweep(0.16, 1320.0, 320.0, "saw", 0.28, 0.08)
	_streams["shoot_basin"] = _synth_sweep(0.11, 340.0, 150.0, "tri", 0.36, 0.24)
	_streams["basin_clang"] = _synth_metallic_clang()
	_streams["shoot_fan"] = _synth_sweep(0.11, 440.0, 740.0, "tri", 0.28, 0.22)
	_streams["shoot_starblade"] = _synth_sweep(0.075, 1180.0, 720.0, "sine", 0.32, 0.05)

	# 命中 / 暴击 / 击杀 / 拾取
	_streams["hit"] = _synth_sweep(0.055, 220.0, 95.0, "tri", 0.30, 0.25)
	_streams["crit"] = _synth_chord([880.0, 1318.5], 0.11, "tri", 0.34, 1.05)
	_streams["kill"] = _synth_sweep(0.16, 480.0, 120.0, "saw", 0.30, 0.28)
	_streams["orb"] = _synth_sweep(0.065, 760.0, 1080.0, "sine", 0.24, 0.0)
	_streams["heart"] = _synth_arpeggio([523.25, 659.25, 783.99], 0.065, "sine", 0.32)

	# 技能 / 升级 / 界面
	_streams["skill"] = _synth_arpeggio([440.0, 659.25, 880.0, 1174.6], 0.055, "tri", 0.34)
	_streams["levelup"] = _synth_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.075, "tri", 0.38)
	_streams["card_hover"] = _synth_sweep(0.035, 620.0, 760.0, "sine", 0.16, 0.0)
	_streams["card_pick"] = _synth_arpeggio([659.25, 987.77, 1318.5], 0.055, "sine", 0.36)
	_streams["ui_click"] = _synth_sweep(0.04, 540.0, 660.0, "sine", 0.20, 0.0)
	_streams["boss_warn"] = _synth_arpeggio([220.0, 185.0, 220.0, 165.0], 0.11, "saw", 0.32)
	_streams["magnet"] = _synth_sweep(0.32, 320.0, 1480.0, "sine", 0.34, 0.04)
	_streams["chest"] = _synth_arpeggio([523.25, 659.25, 783.99, 987.77, 1046.5, 1318.5], 0.06, "tri", 0.40)
	_streams["lightning"] = _synth_sweep(0.14, 1680.0, 260.0, "saw", 0.28, 0.42)
	_streams["orbital"] = _synth_sweep(0.24, 520.0, 75.0, "saw", 0.34, 0.30)
	_streams["reroll"] = _synth_arpeggio([480.0, 640.0, 820.0], 0.035, "sine", 0.26)
	_streams["evo_fanfare"] = _synth_arpeggio([523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98], 0.065, "tri", 0.42)
	_streams["revive"] = _synth_arpeggio([440.0, 554.37, 659.25, 880.0], 0.06, "sine", 0.36)


func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _osc(phase: float, wave: String) -> float:
	var p := fposmod(phase, TAU)
	match wave:
		"tri":
			return 2.0 * absf(2.0 * (p / TAU) - 1.0) - 1.0
		"saw":
			return (2.0 * (p / TAU) - 1.0) * 0.7
		_:
			return sin(p)


func _synth_sweep(dur: float, f0: float, f1: float, wave: String, gain: float, noise_amt: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / float(n)
		var f := lerpf(f0, f1, k)
		ph += TAU * f / float(MIX_RATE)
		var env := pow(1.0 - k, 1.45) * minf(1.0, k * 30.0)
		var s := _osc(ph, wave)
		if noise_amt > 0.0:
			s = lerpf(s, randf_range(-1.0, 1.0), noise_amt * (1.0 - k))
		buf[i] = s * env * gain
	return _make_wav(buf)


func _synth_chord(freqs: Array, dur: float, wave: String, gain: float, pitch_rise := 1.0) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phases: Array[float] = []
	for _i in freqs.size():
		phases.append(0.0)
	for i in n:
		var k := float(i) / float(n)
		var env := pow(1.0 - k, 1.5) * minf(1.0, k * 35.0)
		var acc := 0.0
		for fi in freqs.size():
			var f := float(freqs[fi]) * lerpf(1.0, pitch_rise, k)
			phases[fi] += TAU * f / float(MIX_RATE)
			acc += _osc(phases[fi], wave)
		buf[i] = (acc / float(freqs.size())) * env * gain
	return _make_wav(buf)


func _synth_arpeggio(notes: Array, step_dur: float, wave: String, gain: float) -> AudioStreamWAV:
	var step_n := int(step_dur * MIX_RATE)
	var total := step_n * notes.size() + int(0.08 * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for ni in notes.size():
		var f := float(notes[ni])
		var start := ni * step_n
		var dur_n := step_n + int(0.07 * MIX_RATE)
		var ph := 0.0
		for j in dur_n:
			if start + j >= total:
				break
			var k := float(j) / float(dur_n)
			ph += TAU * f / float(MIX_RATE)
			var env := pow(1.0 - k, 1.35) * minf(1.0, k * 25.0)
			buf[start + j] += _osc(ph, wave) * env * gain * 0.75
	return _make_wav(buf)


## 程序化合成不锈钢大铁盆「DUANG!」金属共鸣撞击音效（非谐金属泛音叠加）
func _synth_metallic_clang() -> AudioStreamWAV:
	var dur := 0.28
	var n := int(dur * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var partials := [290.0, 468.0, 742.0, 1135.0, 1640.0]
	var weights := [0.40, 0.32, 0.26, 0.18, 0.12]
	var decays := [1.6, 2.0, 2.6, 3.4, 4.4]
	var phases: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for i in n:
		var k := float(i) / float(n)
		var atk := minf(1.0, k * 140.0)
		var acc := 0.0
		for pi in partials.size():
			var f := float(partials[pi]) * (1.0 + 0.06 * exp(-k * 18.0))
			phases[pi] += TAU * f / float(MIX_RATE)
			acc += sin(phases[pi]) * float(weights[pi]) * pow(1.0 - k, float(decays[pi]))
		if k < 0.07:
			acc += randf_range(-1.0, 1.0) * 0.28 * (1.0 - k / 0.07)
		buf[i] = clampf(acc * atk * 0.55, -1.0, 1.0)
	return _make_wav(buf)


## 程序化 8-bit 像素芯片音乐（纯代码合成无缝循环 BGM：lobby 轻松明快 / battle 热血节奏）
func _midi_hz(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)


func _synth_bgm(track: String) -> AudioStreamWAV:
	# 32 个八分音符无缝循环（大厅 112 BPM 柔和萌系；战斗 138 BPM 热血复古）
	var step_sec := 0.268 if track == "lobby" else 0.217
	var melody: Array[int] = []
	var bass: Array[int] = []
	var arp_chords: Array = []

	if track == "lobby":
		# C 大调轻快二次元像素大厅主旋律（0 表示休止）
		melody = [
			72, 0, 76, 79, 81, 0, 79, 76,
			74, 0, 76, 74, 72, 0, 67, 0,
			69, 0, 72, 76, 79, 0, 76, 74,
			72, 74, 76, 79, 76, 0, 0, 0,
		]
		bass = [
			48, 0, 55, 0, 48, 0, 55, 0,
			50, 0, 55, 0, 48, 0, 55, 0,
			45, 0, 52, 0, 41, 0, 48, 0,
			43, 0, 50, 0, 48, 0, 55, 0,
		]
		arp_chords = [[60, 64, 67], [62, 65, 67], [57, 60, 64], [55, 59, 62]]
	else:
		# A 小调热血像素冒险战斗主旋律（类似经典复古肉鸽燃曲）
		melody = [
			69, 72, 76, 0, 79, 76, 74, 72,
			76, 0, 72, 74, 76, 79, 81, 0,
			79, 76, 74, 72, 74, 76, 72, 69,
			71, 74, 76, 79, 76, 0, 72, 71,
		]
		bass = [
			45, 57, 45, 57, 48, 60, 48, 60,
			41, 53, 41, 53, 43, 55, 43, 55,
			45, 57, 45, 57, 41, 53, 41, 53,
			40, 52, 43, 55, 45, 57, 43, 55,
		]
		arp_chords = [[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 56, 59]]

	var steps := melody.size()
	var step_n := int(step_sec * MIX_RATE)
	var total := steps * step_n
	var buf := PackedFloat32Array()
	buf.resize(total)

	var ph_m := 0.0
	var ph_b := 0.0
	var ph_a := 0.0
	var lp := 0.0
	var is_battle := (track == "battle")

	for si in steps:
		var mn := melody[si]
		var bn := bass[si]
		var chord: Array = arp_chords[(si / 8) % arp_chords.size()]
		var an := int(chord[si % chord.size()])
		var fm := _midi_hz(mn) if mn > 0 else 0.0
		var fb := _midi_hz(bn) if bn > 0 else 0.0
		var fa := _midi_hz(an)
		for j in step_n:
			var idx := si * step_n + j
			var k := float(j) / float(step_n)
			var atk := minf(1.0, k * 28.0)
			var sample := 0.0
			if fm > 0.0:
				ph_m += TAU * fm / float(MIX_RATE)
				# 柔和方波 + 三角波混合，保留 8-bit 芯片质感但不刺耳
				var sq := 0.65 if fposmod(ph_m, TAU) < PI * 0.72 else -0.65
				var tr := _osc(ph_m, "tri")
				var env_m := atk * pow(1.0 - k * 0.78, 1.3)
				sample += lerpf(tr, sq, 0.42 if is_battle else 0.25) * env_m * 0.28
			if fb > 0.0:
				ph_b += TAU * fb / float(MIX_RATE)
				var env_b := atk * pow(1.0 - k * 0.65, 1.1)
				sample += _osc(ph_b, "tri") * env_b * (0.30 if is_battle else 0.24)
			ph_a += TAU * fa / float(MIX_RATE)
			var env_a := atk * pow(1.0 - k, 1.6)
			sample += sin(ph_a) * env_a * (0.14 if is_battle else 0.16)
			# 战斗曲加入轻量像素打击节奏（底鼓/轻踩镲）
			if is_battle:
				if si % 2 == 0 and k < 0.22:
					var kk := k / 0.22
					sample += sin(kk * TAU * 3.0) * (1.0 - kk) * 0.18
				elif si % 2 == 1 and k < 0.12:
					sample += randf_range(-1.0, 1.0) * (1.0 - k / 0.12) * 0.09
			# 一阶柔化低通滤波，让芯片音乐更耐听
			lp = lerpf(lp, sample, 0.36)
			buf[idx] = clampf(lp, -0.95, 0.95)

	var wav := _make_wav(buf)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total
	return wav
