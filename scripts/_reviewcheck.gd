extends Node
## 「回顾 ▼」功能验证探针（只读，不改任何游戏数据）。
## 跑法：
##   有窗口（出截图）：Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_reviewcheck.tscn
##   headless（只跑断言）：同上 + --headless
##
## 输出：res://shots/_reviewcheck/*.png（headless 不截图）。

const OUT_DIR := "res://shots/_reviewcheck/"

var _fails := 0
var _shots := true


func _ready() -> void:
	_shots = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	await _settle(40)

	# ---------------------------------------------------------- 1) 初始态
	var m: Dictionary = main._review_menu_model()
	var rounds: Array = m["rounds"]
	_check(rounds.size() == 3, "下拉应有 3 轮")
	_check(bool(rounds[0]["reached"]), "第 1 轮应已到达")
	_check(not bool(rounds[1]["reached"]), "第 2 轮应**未**到达")
	_check(not bool(rounds[2]["reached"]), "第 3 轮应**未**到达")
	_check(int(rounds[0]["found"]) == 0, "第 1 轮初始已记 0 条")
	_check(not bool(m["questions"]["reached"]), "判断题初始不可点")

	# ---------------------------------------------------------- 2) 走完第 1 轮探索
	for id in ContentDB.round_spot_ids(0):
		main._open_spot(str(id))
		main.hud.close_modal()
	await _settle(4)
	var m2: Dictionary = main._review_menu_model()
	var found0 := int((m2["rounds"] as Array)[0]["found"])
	_check(found0 > 0, "第 1 轮应有已记条目（得到 %d）" % found0)
	_check(found0 == ContentDB.round_spot_ids(0).size(),
		"第 1 轮条目数应等于该轮探索点数（%d vs %d）"
		% [found0, ContentDB.round_spot_ids(0).size()])
	_check(bool((m2["rounds"] as Array)[1]["reached"]) == false,
		"走完第 1 轮后第 2 轮仍应未到达")

	# ---------------------------------------------------------- 3) 回顾第 1 轮
	main._on_review_requested("round", 0)
	await _settle(8)
	_check(main.hud.modal_visible, "回顾第 1 轮应打开一张纸卡")
	_check(main.hud._review_entries.size() == found0,
		"回顾条目数应等于已记条数（%d vs %d）"
		% [main.hud._review_entries.size(), found0])
	await _shot("01_回顾_第1轮结论")

	# 分页（14 条 → 每页 6 条 → 3 页）
	_check(main.hud._page_count(found0) == 3, "14 条应分 3 页（得到 %d）" % main.hud._page_count(found0))
	main.hud._review_next_page()
	await _settle(8)
	_check(main.hud._review_page == 1, "『下一页』后应停在第 2 页")
	_check(int(main.hud._review_entries.size()) == found0, "翻页不应改动条目总数")
	await _shot("01b_回顾_第1轮_第2页")
	main.hud._review_prev_page()
	await _settle(6)
	_check(main.hud._review_page == 0, "『上一页』后应回到第 1 页")

	main.hud._render_review_clue(0)
	await _settle(8)
	_check(main.hud.modal_visible, "线索详情页应打开")
	await _shot("02_回顾_线索详情")

	# 关键：回顾卡 fire=false —— 关掉它不该把流程推到判断题上。
	main.hud._dismiss()
	await _settle(6)
	_check(not main.hud.modal_visible, "关掉回顾线索卡后应无任何纸卡（回顾不推进流程）")

	# ---------------------------------------------------------- 4) 答一道判断题 → 回顾
	var qs := ContentDB.round_questions(0)
	_check(qs.size() > 0, "第 1 轮应有判断题")
	if qs.size() > 0:
		var qid := str(qs[0]["id"])
		main._on_option_chosen(qid, 0)
		await _settle(4)
		main.hud.close_modal()
		await _settle(2)
		var m3: Dictionary = main._review_menu_model()
		_check(bool(m3["questions"]["reached"]), "答过题后『判断题』应可点")
		_check(int(m3["questions"]["answered"]) == 1, "已答数应为 1")

		main._on_review_requested("questions", 0)
		await _settle(8)
		_check(main.hud._review_qs.size() == 1, "回顾判断题列表应有 1 条")
		await _shot("03_回顾_判断题列表")

		main.hud._render_review_question(0)
		await _settle(8)
		await _shot("04_回顾_判断题结果")
		main.hud.close_modal()
		await _settle(2)

	# ---------------------------------------------------------- 5) 跨轮不串味（核心）
	# 把"当前轮次"挪到第 2 轮，再回顾第 1 轮 —— 正文必须仍是第 1 轮的原文。
	var probe_id := ""
	for id in main.found_by_round.get(0, []):
		if not ContentDB.round_spot(1, str(id)).is_empty():
			probe_id = str(id)
			break
	_check(probe_id != "", "应能找到一个跨轮复用的 id 做对照")
	main.round_idx = 1
	main._review_round(0)
	await _settle(6)
	var ok_all := true
	for e in main.hud._review_entries:
		var d: Dictionary = e
		var want: Variant = ContentDB.round_spot(0, str(d.get("spot", ""))).get("lines", [])
		if str(d.get("lines", [])) != str(want):
			ok_all = false
			printerr("[reviewcheck]   串味：%s 取了 %s" % [str(d.get("spot", "")), str(d.get("lines", []))])
	_check(ok_all, "当前在第 2 轮时，回顾第 1 轮仍取第 1 轮原文（不串轮）")
	main.round_idx = 0
	main.hud.close_modal()
	await _settle(2)

	# ---------------------------------------------------------- 6) 下拉菜单本体
	main.hud._open_review_menu()
	await _settle(6)
	_check(main.hud._review_menu.visible, "下拉应能打开")
	await _shot("05_回顾_下拉菜单")
	main.hud._close_review_menu()
	await _settle(2)
	_check(not main.hud._review_menu.visible, "下拉应能关闭")

	# ---------------------------------------------------------- 7) 悬停提示
	main.hud._show_tip("点击查看线索", main.hud._review_chip_node)
	await _settle(4)
	_check(main.hud._tip.visible, "悬停提示应能显示")
	await _shot("06_回顾_悬停提示")
	main.hud._hide_tip()

	# ---------------------------------------------------------- 8) 下拉的"点外面才收起"
	# ⛔ 这一条是坐标空间一致性的实测：`_input` 里拿 `event.position` 跟
	#    `Control.get_global_rect()` 比。两者若不在同一坐标系，
	#    点菜单行会被误判成"点外面"→ 下拉还没点就先收了，功能等于废掉。
	main.hud._open_review_menu()
	await _settle(6)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = main.hud._review_menu.get_global_rect().get_center()
	main.hud._input(ev)
	await _settle(2)
	_check(main.hud._review_menu.visible, "点在菜单范围内不应收起下拉（坐标空间一致）")

	ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = main.hud._review_chip_node.get_global_rect().get_center()
	main.hud._input(ev)
	await _settle(2)
	_check(main.hud._review_menu.visible, "点在「回顾」按钮上不应收起（留给按钮自己开合）")

	ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(60.0, 640.0)
	main.hud._input(ev)
	await _settle(2)
	_check(not main.hud._review_menu.visible, "点在别处应收起下拉")
	main.hud.close_modal()

	# ---------------------------------------------------------- 汇总
	if _fails == 0:
		print("[reviewcheck] 全部通过 ✅")
	else:
		printerr("[reviewcheck] 有 %d 项失败 ❌" % _fails)
	print("[reviewcheck] 截图见 " + OUT_DIR)
	Audio.shutdown()
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[reviewcheck] PASS · " + what)
	else:
		_fails += 1
		printerr("[reviewcheck] FAIL · " + what)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print("[reviewcheck] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
