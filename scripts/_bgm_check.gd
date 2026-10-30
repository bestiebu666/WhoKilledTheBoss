extends Node
## 音频自检：BGM 是不是「真的」在循环、播放没断。
##
## 为什么不能只看 `.import` 里的 `loop=true`：那只说明**导入设置**对，不代表**播起来**接得上。
## 万一 loop 没真正生效，音乐播到结尾会彻底哑掉 —— 而且**不会有任何报错**，肉眼看不出来。
## 所以这里真的把播放头挪到结尾前 1.5 秒，盯 3 秒看它有没有绕回开头。
##
## 跑法（和别的 probe 一样用带窗口的 exe，别加 --headless）：
##   Godot_v4.7.2-stable_win64.exe --path . res://scenes/_bgmcheck.tscn
## 期望末尾打印 BGM_CHECK_OK

const TAIL := 1.5     # 跳到「离结尾还有这么久」的位置
const WATCH := 3.0    # 然后盯这么久


func _ready() -> void:
	await _run()
	get_tree().quit()


func _run() -> void:
	Audio.play_bgm()
	await _wait(2.0)                     # 等它真的起播

	var key := Audio.playing_track()
	var st: Dictionary = Audio.debug_state().get(key, {})
	if st.is_empty():
		print("BGM_CHECK_FAIL: 没有在播的曲目")
		return

	var loop_on: bool = st["loop"]
	var length: float = st["length"]
	print("\n[bgm] track=%s  loop=%s  length=%.2f s  db=%.1f"
		% [key, str(loop_on), length, st["db"]])

	# ---- ① 导入设置 ----
	print("① loop 开关：%s"
		% ("OK" if loop_on else "FAIL（.import 里 loop=false！音乐播完就彻底哑，而且不报错）"))
	if not loop_on:
		print("BGM_CHECK_FAIL")
		return

	# ---- ② 真跨一次循环点 ----
	Audio.seek_bgm(maxf(length - TAIL, 0.0))
	await _wait(0.05)
	var prev: float = float(Audio.debug_state()[key]["pos"])
	var wrapped := false                  # 位置有没有明显回退（= 绕回开头）
	var stayed := true                    # 全程 playing 不掉
	var max_pos := prev
	var min_pos := prev
	var frames := 0
	var t := 0.0
	while t < WATCH:
		await get_tree().process_frame
		t += get_process_delta_time()
		frames += 1
		var s: Dictionary = Audio.debug_state()[key]
		var p: float = float(s["pos"])
		if not bool(s["playing"]):
			stayed = false
		if p < prev - 0.5:
			wrapped = true
		max_pos = maxf(max_pos, p)
		min_pos = minf(min_pos, p)
		prev = p

	print("② 跨循环点：不停播=%s  位置回退=%s  观察 %d 帧（pos 最高 %.2f / 最低 %.2f）"
		% ["OK" if stayed else "FAIL（中途停了）",
		   "OK" if wrapped else "FAIL（一直没绕回开头 → loop 没生效）",
		   frames, max_pos, min_pos])

	var ok := loop_on and stayed and wrapped
	print("BGM_CHECK_%s" % ("OK" if ok else "FAIL"))
	Audio.shutdown()      # 放掉音频资源，退出日志才干净


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()
