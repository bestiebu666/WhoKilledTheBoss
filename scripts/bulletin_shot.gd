extends Node
## 公示板核对图 —— 只干一件事：把刚交付的公告栏真模型拍清楚，确认三件事：
##   ① 贴在**西墙**上（x ≈ −7.94），不是飘在屋里；
##   ② 板面**朝屋里**（+x 方向，也就是从东往西看能看到内容），不是背对观众；
##   ③ **宽顺着墙走**（沿 z），没被「厚薄」顶反。
##
## 跑法（⛔ 不要加 --headless，本机 headless 拿不到 GPU）：
##   Godot_v4.7.2-stable_win64.exe --path . res://scenes/bulletin_shot.tscn

const OUT_DIR := "res://shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	await _settle(40)

	# 相机走玩家那套（`_sync_camera` 每帧会把 camera 拽回玩家头顶），
	# 所以正确做法是**挪玩家 + 给 yaw/pitch**，而不是另建一个相机 —— 另建的会被抢 current。
	# 公告栏贴西墙 x=−7.94、中心高 1.35、沿 z 长 1.637（z 从 3.58 到 5.22）。
	# 站在它正东约 3.4 米处（x=−4.53），平视（pitch ≈ 0）看过去。

	# ① 正面平视 —— 退到东边约 4.5 米（x=−3.4），让整块板 1.637 米宽都在画面里。
	await _pose(main, Vector3(-3.40, 0, 4.40), 90.0, -4.0)
	await _shot("L24_公示板_正面")

	# ② 再从更远的地方平视（x=−1.6，约 6.3 米），连西墙南段一起看 —— 确认没穿进隔壁。
	await _pose(main, Vector3(-1.60, 0, 4.60), 92.0, -3.0)
	await _shot("L25_公示板_西墙全景")

	# ③ 从北边斜看 —— 能一眼看出「宽顺着墙（沿 z）」还是「厚顶着墙」。
	await _pose(main, Vector3(-5.90, 0, 0.90), 148.0, -5.0)
	await _shot("L26_公示板_斜视")

	print("[bulletin_shot] 完成，见 " + OUT_DIR)
	Audio.shutdown()   # 放掉 BGM 资源，退出日志才干净
	get_tree().quit(0)


## 挪玩家 + 定朝向，然后等相机同步。和 shot.gd 的 _pose 同一套。
func _pose(main: Node3D, pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.global_position = pos
	main.yaw = yaw
	main.pitch = pitch
	main._sync_camera()
	await _settle(6)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print("[bulletin_shot] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
