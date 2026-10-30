extends Node
## 截图工具：不是游戏的一部分，只是用来核对画面。
## 跑法（不要加 --headless，需要真实渲染）：
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/shot.tscn
##
## 跑的都是玩家的真实第一人称视角 —— 把玩家挪到某处、转个方向，再截。
## 这样截出来的图，就是玩家点开游戏会看到的东西。

const OUT_DIR := "res://shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# ---- 00 进入页 / 前情提要 / 选幕页（和地图无关，先单独截完再卸掉）----
	var app_packed: PackedScene = load("res://scenes/app.tscn")
	var app: Node = app_packed.instantiate()
	add_child(app)
	await _settle(8)
	await _shot(app, "00a_进入页_标题")

	var app_entry: Frontend = app.get("entry")
	if app_entry != null:
		app_entry.show_recap()
		await _settle(4)
		await _shot(app, "00b_前情提要")

		app_entry.advance_recap()
		await _settle(4)
		await _shot(app, "00c_引导剧情")

		app_entry.show_acts()
		await _settle(4)
		await _shot(app, "00d_选幕页")

		# 点一下锁着的第二幕 —— 锁定态唯一的反馈就是下面那句提示，得截下来看
		var locked_btn := app_entry.act_button(1)
		if locked_btn != null:
			locked_btn.pressed.emit()
		await _settle(12)
		await _shot(app, "00e_点锁定幕的提示")

	app.queue_free()
	await _settle(8)

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)

	await _settle(40)

	# 01 出生点：门内侧，朝东北看整片工位区（门心 2026-10-06 加宽后北移到 -1.9，出生点没动）
	await _pose(main, Vector3(-6.8, 0, -1.5), -50.0, -30.0)
	await _shot(main, "01_出生点望向设计部")

	# 02 从岛东南侧斜看工位岛（能同时看到南排的椅子和北墙窗）
	await _pose(main, Vector3(-0.4, 0, -1.9), 48.0, -28.0)
	await _shot(main, "02_工位岛全景")

	# 02b 站在岛南侧看南排正面（椅子、显示器、隔板都朝这边）—— 验证两组朝向相反
	await _pose(main, Vector3(-4.0, 0, -0.8), 0.0, -16.0)
	await _shot(main, "02b_工位正面与椅子")

	# 02c 站到岛东端、贴着中缝往西看 —— 专门核对两组「背靠背」有没有贴合、中间有没有缝
	await _pose(main, Vector3(0.8, 0, -3.84), 90.0, -14.0)
	await _shot(main, "02c_两组背靠背的贴合处")

	# 03 把视角拖到头（pitch 上限）—— 抬头就是天花板，不是天空、也不是边界
	await _pose(main, Vector3(0.0, 0, 0.0), 0.0, main.pitch_max)
	await _shot(main, "03_抬头看天花板")

	# 04 吧台与东南角（会议桌和 6 把椅子 2026-10-06 已被作者删掉，那块空地换成吧台；
	#    东墙那两扇灰盒窗也删了，所以这张不再叫「吧台与东墙窗」）
	await _pose(main, Vector3(0.6, 0, 1.6), -90.0, -30.0)
	await _shot(main, "04_吧台与东南角")

	# 05 从东南角回望全屋
	await _pose(main, Vector3(6.0, 0, 3.6), 59.0, -26.0)
	await _shot(main, "05_从东南角回望全屋")

	# 06 站在凤凰男工位前，弹信息卡
	await _pose(main, Vector3(-6.3, 0, -1.0), -12.0, -34.0)
	main._open_spot("feng_desk")
	await _settle(6)
	await _shot(main, "06_信息卡")

	main.hud._dismiss()

	# 07 点**小人**（不是家具）= 弹他自己的线索卡 —— 2026-10-06 作者：「小人也是可探索点」
	main._open_npc("feng")
	await _settle(6)
	await _shot(main, "07_点小人的线索卡")
	main.hud.close_modal()

	# 08 把本轮全部可探索点看完（⚠ 数量**别写死** —— 每轮的点位是 act1.json 里现读的，
	#    2026-10-06 夜补了南排两张桌之后第 1 轮是 14 个：4 个小人 + 10 个家具/桌面点）
	#    → 右侧「已记下的东西」记满结论
	for s in ContentDB.round_spot_ids(0):
		main._open_spot(str(s))
		main.hud.close_modal()
	await _settle(6)
	await _shot(main, "08_右栏记下的结论")

	# 08b 站到 NPC 面前 —— 主角在高处俯视，不是和 NPC 面对面
	await _pose(main, Vector3(-5.29, 0, -0.35), 0.0, -52.0)
	await _shot(main, "08b_站在NPC面前是俯视")

	# 09 关掉最后一张卡 → **自动**弹出判断题（⛔ 不再需要「找小人说话」）
	# ⚠ 上面的循环用的是 `close_modal()`（不 fire），所以链条还没启动；
	#   这里随便再点开一处再用真出口关掉，就等于「看完最后一个位置」。
	main._open_spot(str(ContentDB.round_spot_ids(0)[0]))
	await _settle(2)
	main.hud._dismiss()
	await _settle(6)
	await _shot(main, "09_看完自动出判断题")

	main._on_option_chosen("q1_feng_rich", _wrong_index(0, "q1_feng_rich"))
	await _settle(6)
	await _shot(main, "10_答错了")

	# 11 反馈关掉 → 自动接第二道题（不用再找人）
	main.hud._continue()
	await _settle(4)
	main._on_option_chosen("q1_intern1_entry", _correct_index(0, "q1_intern1_entry"))
	await _settle(6)
	await _shot(main, "11_答对了")

	# 12 第一轮收尾：三道题答完 → 轮末过场（点「继续搜证」才进第 2 轮、线索刷新）
	main.hud._continue()
	await _settle(4)
	main._on_option_chosen("q1_empty_seats", _correct_index(0, "q1_empty_seats"))
	main.hud._continue()
	await _settle(6)
	await _shot(main, "12_第一轮结束")

	print("[shot] 截图完成，见 " + OUT_DIR)
	Audio.shutdown()   # 放掉 BGM 资源，退出日志才干净
	get_tree().quit(0)


## 某道题**正确选项**的下标（0 起）。选项顺序是作者填的、随时会改，
## 所以截图脚本里别手写下标 —— 写死了会「以为在答对、其实在答错」。
func _correct_index(round_i: int, qid: String) -> int:
	var opts: Variant = ContentDB.round_question(round_i, qid).get("options", [])
	if typeof(opts) == TYPE_ARRAY:
		for i in range((opts as Array).size()):
			if bool(((opts as Array)[i] as Dictionary).get("correct", false)):
				return i
	return 0


## 某道题**错误选项**的下标（0 起）。只有两个选项时 = 另一个。
func _wrong_index(round_i: int, qid: String) -> int:
	var opts: Variant = ContentDB.round_question(round_i, qid).get("options", [])
	var n := (opts as Array).size() if typeof(opts) == TYPE_ARRAY else 0
	var ci := _correct_index(round_i, qid)
	return (ci + 1) % n if n > 1 else ci


## 把玩家挪到某处、转向某个方向，再等相机同步几帧。
func _pose(main: Node3D, pos: Vector3, yaw: float, pitch: float) -> void:
	main.player.global_position = pos
	main.yaw = yaw
	main.pitch = pitch
	main._sync_camera()
	await _settle(4)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


## main 参数只用来对齐调用点，实际截图走的是当前视口 —— 所以前台页面也能用它。
func _shot(_node: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print("[shot] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
