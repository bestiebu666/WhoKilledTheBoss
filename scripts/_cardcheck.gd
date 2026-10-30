extends Node
## 换底图后的画面核对：把两张新纸卡（线索框 / 记录框）在真实渲染里截出来。
## 跑法（**不要加 --headless**，需要真实渲染）：
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_cardcheck.tscn
##
## 输出到 res://shots/_cardcheck/ —— 刻意跟 shot.gd 分开，不覆盖作者的正式截图。

const OUT_DIR := "res://shots/_cardcheck/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	await _settle(45)

	# 00 记录框的空态（还没看过任何东西）
	await _shot("00_记录框_空态")

	# 01 线索框：点家具 → 弹信息卡（走 card_clue.png）
	main._open_spot("feng_desk")
	await _settle(8)
	await _shot("01_线索框_信息卡")
	main.hud._dismiss()

	# 02 线索框：点小人 → 弹他自己的线索卡
	main._open_npc("feng")
	await _settle(8)
	await _shot("02_线索框_小人")
	main.hud.close_modal()

	# 03 记录框：把本轮点位都看一遍，右栏攒满条目（走 card_journal.png）
	for s in ContentDB.round_spot_ids(0):
		main._open_spot(str(s))
		main.hud.close_modal()
	await _settle(8)
	await _shot("03_记录框_已有条目")

	# 04 判断题：看完最后一个位置后自动弹出（也是 card_clue.png，看选项放不放得下）
	main._open_spot(str(ContentDB.round_spot_ids(0)[0]))
	await _settle(2)
	main.hud._dismiss()
	await _settle(8)
	await _shot("04_判断题")

	print("[cardcheck] 完成，见 " + OUT_DIR)
	Audio.shutdown()
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print("[cardcheck] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
