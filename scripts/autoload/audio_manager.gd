# AudioManager.gd - 音频管理单例
# 管理BGM和音效播放
extends Node

var _bgm_player: AudioStreamPlayer
var _sfx_players: Array = []

# 程序化生成的命中/格挡音效(无需外部音频资源)
var _hit_wav: AudioStreamWAV
var _block_wav: AudioStreamWAV

const SFX_POOL_SIZE := 8


func _ready() -> void:
	# 确保 BGM/SFX 总线存在, 否则音量设置无意义
	_ensure_bus("BGM")
	_ensure_bus("SFX")

	# 预生成打击音效样本, 命中时即时播放
	_hit_wav = _make_hit_sample(false)
	_block_wav = _make_hit_sample(true)

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)

	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)


# 若指定名称的总线不存在则创建一个, 供设置界面调节音量
func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, name)


func play_bgm(stream: AudioStream) -> void:
	if _bgm_player.stream == stream and _bgm_player.playing:
		return
	_bgm_player.stream = stream
	_bgm_player.play()


func stop_bgm() -> void:
	_bgm_player.stop()


func play_sfx(stream: AudioStream) -> void:
	for player in _sfx_players:
		if not player.playing:
			player.stream = stream
			player.play()
			return


func fade_bgm(duration: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", -80.0, duration)
	tween.tween_callback(_on_bgm_faded)


# 播放命中音效: power 控制力度(影响音量与音高), blocked 走金属格挡音色
func play_hit(power: float, blocked: bool) -> void:
	var wav := _block_wav if blocked else _hit_wav
	if not wav:
		return
	for player in _sfx_players:
		if not player.playing:
			player.stream = wav
			player.volume_db = linear_to_db(clampf(power, 0.2, 1.0))
			player.pitch_scale = 1.0 + (0.0 if blocked else (power - 0.6) * 0.3)
			player.play()
			return


# 程序化生成一段 16-bit 单声道打击音效(噪声冲击 + 低频闷响 / 金属格挡)
func _make_hit_sample(blocked: bool) -> AudioStreamWAV:
	var mix_rate := 44100
	var dur := 0.18 if not blocked else 0.09
	var frames := int(mix_rate * dur)
	var data := PackedByteArray()
	data.resize(frames * 2)   # 16-bit 单声道, 每帧 2 字节
	for i in range(frames):
		var t := float(i) / mix_rate
		var decay := exp(-t * (60.0 if blocked else 28.0))
		var s := 0.0
		if blocked:
			# 金属感: 高频噪声 + 短促高频正弦
			s = (randf() * 2.0 - 1.0) * 0.5 * decay
			s += sin(t * 1800.0 * TAU) * 0.3 * decay
		else:
			# 低频闷响 + 噪声冲击
			s = (randf() * 2.0 - 1.0) * 0.6 * decay
			s += sin(t * 90.0 * TAU) * 0.5 * decay
		s = clampf(s, -1.0, 1.0)
		var v := int(s * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	return wav


func _on_bgm_faded() -> void:
	_bgm_player.stop()
	_bgm_player.stream = null
	_bgm_player.volume_db = 0.0
