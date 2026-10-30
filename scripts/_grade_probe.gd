extends Node
## 一次性探针：**同一个机位**连拍多档「环境滤镜」，用来挑多巴胺配方。
## 挑完就把这个脚本 + 场景删掉（它不进游戏，只在 shots/ 出对比图）。
##
## 跑法（不要 --headless，需要真实渲染）：
##   Godot_v4.7.2-stable_win64.exe --path . res://scenes/_gradeprobe.tscn

const OUT_DIR := "res://shots/_gradework/"

var main: Node3D
var env: Environment

## ⭐ 第三轮：定稿对比 —— 只拍「现状 A」vs「主推 F」，出 before/after 给作者看。
var presets: Array = [
	{"tag": "A_现状_原样",
	 "tonemap": Environment.TONE_MAPPER_LINEAR, "brightness": 1.0, "contrast": 1.0,
	 "saturation": 1.0, "ambient_color": "#FFF4E4", "ambient_energy": 0.45, "glow": false},
	{"tag": "F_主推_多巴胺",
	 "tonemap": Environment.TONE_MAPPER_LINEAR, "brightness": 1.02, "contrast": 1.20,
	 "saturation": 1.60, "ambient_color": "#FFEDE2", "ambient_energy": 0.55, "glow": true},
]

var poses: Array = [
	["工位岛", Vector3(-0.4, 0, -1.9), 48.0, -28.0],
	["全景", Vector3(6.0, 0, 3.6), 59.0, -26.0],
	["人台", Vector3(1.78, 0, 1.6), 0.0, -20.0],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(40)
	# 思考框会挡视线，先摘掉（和 layout_shot 同一套）
	for nid in main._npc_bubbles:
		var bb: Node3D = main._npc_bubbles[nid]
		if bb != null:
			bb.visible = false

	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		push_error("[grade] 找不到 WorldEnvironment")
		get_tree().quit(1)
		return
	env = we.environment

	for p in presets:
		_apply(p)
		await _settle(6)
		for po in poses:
			await _pose(po[1], po[2], po[3])
			await _shot("%s__%s" % [str(p["tag"]), str(po[0])])

	print("[grade] 对比图完成 -> " + OUT_DIR)
	get_tree().quit(0)


func _apply(p: Dictionary) -> void:
	env.tonemap_mode = int(p["tonemap"])
	env.adjustment_enabled = true
	env.adjustment_brightness = float(p["brightness"])
	env.adjustment_contrast = float(p["contrast"])
	env.adjustment_saturation = float(p["saturation"])
	env.ambient_light_color = Color(str(p["ambient_color"]))
	env.ambient_light_energy = float(p["ambient_energy"])
	env.glow_enabled = bool(p["glow"])
	env.glow_intensity = 0.45
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.08


func _pose(pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.global_position = pos
	main.yaw = yaw
	main.pitch = pitch
	main._sync_camera()
	await _settle(5)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print("[grade] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
