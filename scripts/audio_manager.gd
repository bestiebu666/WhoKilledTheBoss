extends Node
## 全局背景音乐（BGM）。autoload 名 = Audio。
##
## 为什么要单独一层：BGM 得跨「进入页 → 前情 → 选幕 → 地图」一路不断。挂在 autoload 上，
## 场景切来切去它都不会停；各个页面只管喊一句 `Audio.play_bgm()`，
## 不需要知道曲子在哪、播到几秒了、要不要循环。
##
## ⭐ 两条铁律（踩过坑，别改回去）：
##   ① 切歌必须【交叉淡化】—— 旧的淡出的同时新的淡入。**绝不能**写成「旧的先淡完 → 新的再淡入」，
##      中间那一拍两边都没声，音乐就断了。
##   ② 淡化补的是【线性增益】而不是 volume_db —— 补 db 的话两首各自的增益会掉到 ~0.0056，
##      合起来比正常音量低约 31 dB，耳朵听到的是一个「空下去」的口子。
##      用 sin/cos 等功率曲线（sin² + cos² = 1 → 合成增益全程恒定）。
##
## 素材：`assets/audio/bgm_main.ogg` —— 由 `tools/build_bgm.py` 从作者的原始 WAV
## 裁掉首尾安静段、做好 40ms 循环接缝再编码出来的。改素材请重跑那个脚本，别手改 ogg。

const TRACKS := {
	"main": "res://assets/audio/bgm_main.ogg",
}
const DEFAULT_TRACK := "main"
const VOLUME_DB := -8.0     # 素材整段 RMS ≈ -16.6 dB，这里再压低一档当背景（不压过将来的音效）
const FADE_TIME := 1.2      # 交叉淡化时长

var _by_id := {}            # track id -> AudioStreamPlayer
var _cur := ""              # 当前曲目 id
var _fade: Tween = null


func _ready() -> void:
	# boot 就起播，不做淡入 —— 否则进游戏先静一拍。
	play_bgm(DEFAULT_TRACK)


## 播一首 BGM。同一首重复点直接 return（页面来回切不该把音乐一次次打回开头）。
func play_bgm(id: String = DEFAULT_TRACK) -> void:
	if not TRACKS.has(id):
		push_error("[Audio] 没有这首 BGM：%s" % id)
		return
	if id == _cur:
		var p: AudioStreamPlayer = _by_id.get(id)
		if p != null and p.playing:
			return
	_switch_to(id, _cur == "")


## 停掉所有 BGM（一般用不上，留给「静音」开关之类的场合）。
func stop_bgm() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for p: AudioStreamPlayer in _by_id.values():
		p.stop()
	_cur = ""


func playing_track() -> String:
	return _cur


## 给校验工具用（scripts/_bgm_check.gd）：跳到当前曲目的某个位置。
func seek_bgm(t: float) -> void:
	var p: AudioStreamPlayer = _by_id.get(_cur)
	if p != null:
		p.seek(t)


## 给校验工具看的只读探针（scripts/_bgm_check.gd 用）。
func debug_state() -> Dictionary:
	var d := {}
	for id: String in _by_id:
		var p: AudioStreamPlayer = _by_id[id]
		var st: AudioStream = p.stream
		var looping := false
		if st is AudioStreamOggVorbis:
			looping = (st as AudioStreamOggVorbis).loop
		d[id] = {
			"playing": p.playing,
			"db": p.volume_db,
			"gain": db_to_linear(p.volume_db),
			"pos": p.get_playback_position(),
			"loop": looping,
			"length": st.get_length(),
		}
	return d


func _switch_to(id: String, immediate: bool) -> void:
	var next: AudioStreamPlayer = _by_id.get(id)
	if next == null:
		next = AudioStreamPlayer.new()
		next.name = "BGM_" + id
		next.stream = load(TRACKS[id])
		add_child(next)
		_by_id[id] = next

	var base_gain := db_to_linear(VOLUME_DB)
	var prev: AudioStreamPlayer = null
	if _cur != "" and _cur != id:
		prev = _by_id.get(_cur)

	if _fade != null and _fade.is_valid():
		_fade.kill()

	if immediate or prev == null:
		# 没有前一首在播：直接满音量起播，不做淡入。
		next.volume_db = _db_of(base_gain)
		if not next.playing:
			next.play()
		if prev != null:
			prev.stop()
		_cur = id
		return

	# 交叉淡化。prev_g0 取它【当前的实际音量】而不是满值 —— 连着切两次时它可能正淡到一半，
	# 硬写满值会让它「先跳大再淡出」，是一下就能听出来的鼓包。
	var prev_g0 := db_to_linear(prev.volume_db)
	if not next.playing:
		next.play()
	next.volume_db = _db_of(0.0)

	_fade = create_tween().set_parallel(true)
	_fade.tween_method(
		func(t: float) -> void: next.volume_db = _db_of(sin(t * PI * 0.5) * base_gain),
		0.0, 1.0, FADE_TIME)
	_fade.tween_method(
		func(t: float) -> void: prev.volume_db = _db_of(prev_g0 * cos(t * PI * 0.5)),
		0.0, 1.0, FADE_TIME)
	_fade.chain().tween_callback(_retire.bind(prev))
	_cur = id


## 淡化跑完再停旧的那一首（停在淡化过程中会听见硬切）。
func _retire(p: AudioStreamPlayer) -> void:
	if p != null and p != _by_id.get(_cur):
		p.stop()


## linear_to_db(0) 是 -inf，必须夹一个下限。
func _db_of(gain: float) -> float:
	return linear_to_db(maxf(gain, 0.0001))


## 主动释放播放资源。**要由调用方在 quit() 之前调**（自检 / 出图脚本都这么做）：
## ⛔ 光靠 `_exit_tree()` 已经太晚 —— 那时 AudioServer 自己在关，playback 释放不掉，
##    Godot 就会打印「resources still in use at exit」（无害，但日志里混 ERROR 容易被误判成出错）。
func shutdown() -> void:
	for p: AudioStreamPlayer in _by_id.values():
		p.stop()
		p.stream = null
	_by_id.clear()
	_cur = ""


func _exit_tree() -> void:
	shutdown()
