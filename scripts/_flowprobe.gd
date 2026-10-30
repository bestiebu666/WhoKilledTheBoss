extends Node
## 流程探针（**只在排查时跑，不是游戏的一部分**）。
##
## 目的：把「一轮搜证 → 判断题 → 轮末过场 → 下一轮」这条链**真的走一遍**，并把每一步
##   的角色状态打成日志 + 存图。因为肉眼在游戏里点很容易看错「到底停在哪一步」。
##
## 跑法（不加 --headless）：
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_flowprobe.tscn

const OUT := "res://shots/"

var main: Node3D
var hud: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(45)
	hud = main.hud

	_print_round_icons("开局（第 1 轮）")

	# ---- 1) 第 1 轮：把本轮所有点位看完 ----
	# ⛔ `main` 是 Node3D，调它的方法是动态调用 → 返回 Variant，`var x := ...` 会 Parse Error。
	var ids: Array = main._round_ids()
	print("[flow] 第 1 轮点位 %d 个：%s" % [ids.size(), str(ids)])
	for sid in ids:
		main._open_spot(str(sid))
		hud.close_modal()          # 不 fire，只在最后一步用真出口
	print("[flow] 看完之后 scanned=%d" % main.scanned.size())

	# 真出口关掉最后一张 → 链条启动
	main._open_spot(str(ids[0]))
	await _settle(2)
	hud._dismiss()
	await _settle(8)
	await _shot("_flow_01_第一题")
	print("[flow] 出题后 modal_visible=%s  标题=%s" % [hud.modal_visible, hud._title.text])

	# ---- 2) 逐题作答 ----
	var guard := 0
	while not main._round_q_done() and guard < 20:
		guard += 1
		var q: Dictionary = main._next_round_question()
		if q.is_empty():
			break
		var qid := str(q.get("id", ""))
		var idx := _correct_index(main, qid)
		print("[flow] 答第 %d 题 %s -> 选 %d" % [guard, qid, idx])
		main._on_option_chosen(qid, idx)
		await _settle(6)
		hud._continue()            # 反馈卡的真出口
		await _settle(6)

	print("[flow] 题答完：answered=%d  round_q_done=%s" % [main.answered.size(), str(main._round_q_done())])
	await _shot("_flow_02_轮末过场")
	print("[flow] 轮末卡：modal_visible=%s  closable=%s  fire=%s  标题=%s" %
		[hud.modal_visible, hud._modal_closable, hud._modal_fire, hud._title.text])
	_dump_buttons()

	# ---- 3) 点轮末卡的按钮，看会发生什么 ----
	print("[flow] round_idx(前)=%d" % main.round_idx)
	_press_first_button()
	await _settle(10)
	print("[flow] 点了按钮之后：round_idx=%d  modal_visible=%s  标题=%s" %
		[main.round_idx, hud.modal_visible, hud._title.text])
	_print_round_icons("点完轮末按钮")
	await _shot("_flow_03_点了轮末按钮之后")

	# 再点两下，看会不会一路滑到收幕
	for i in range(2):
		_press_first_button()
		await _settle(10)
		print("[flow] 又点一次：round_idx=%d  modal_visible=%s  标题=%s" %
			[main.round_idx, hud.modal_visible, hud._title.text])
	await _shot("_flow_04_连点之后")

	# ---- 4) 东南角沙发：boss（部长／老板）的感叹号在不在、是不是被沙发挡死 ----
	print("[flow] --- 东南角沙发（boss = 部长 = 老板）---")
	for nid0 in ["boss", "director", "feng", "intern1"]:
		var sp0: Sprite3D = main._clue_icons.get(nid0)
		if sp0 != null:
			print("[flow]   %-9s 圆心=%s  visible=%s" % [nid0, str(sp0.position), str(sp0.visible)])

	hud.close_modal()                       # 先把轮末卡收掉，别挡视线
	await _settle(4)
	# 从房间中部朝东南看整个沙发角（宽景）
	main.player.global_position = Vector3(1.6, 0, -0.2)
	main.yaw = -140.0
	main.pitch = -18.0
	main._sync_camera()
	await _settle(10)
	await _shot("_flow_05_沙发角_宽景")
	# 贴近看 boss 本人（眼高 3.0、图标 y≈1.0，水平距 2.6 米 → 俯角 ≈ 38°）
	main.player.global_position = Vector3(4.4, 0, 2.0)
	main.yaw = -132.0
	main.pitch = -34.0
	main._sync_camera()
	await _settle(10)
	await _shot("_flow_06_沙发角_boss近景")

	print("[flow] 结束")
	Audio.shutdown()
	get_tree().quit(0)


## 本轮应该显示几个感叹号、分别在哪。
func _print_round_icons(tag: String) -> void:
	var vis: Array[String] = []
	for id in main._clue_icons:
		var sp: Sprite3D = main._clue_icons[id]
		if sp != null and sp.visible:
			vis.append("%s@%s" % [id, str(sp.position.round())])
	print("[flow] %s：可见感叹号 %d 个 —— %s" % [tag, vis.size(), ", ".join(vis)])


func _dump_buttons() -> void:
	var btns := _find_buttons(hud._modal_layer)
	var names: Array[String] = []
	for b in btns:
		names.append("「%s」" % (b as Button).text)
	print("[flow] 卡片上的按钮：%s" % (", ".join(names) if not names.is_empty() else "（一个都没有！）"))


func _press_first_button() -> void:
	var btns := _find_buttons(hud._modal_layer)
	if btns.is_empty():
		print("[flow] ⛔ 没有按钮可按")
		return
	print("[flow] 按下按钮「%s」" % (btns[0] as Button).text)
	(btns[0] as Button).pressed.emit()


## ⛔ 用 `is_visible_in_tree()` 而不是节点自身的 `visible` ——
##    `close_modal()` 只把 `_modal_layer` 设成不可见，按钮自己的 `visible` 还是 true，
##    拿它当判据会以为「关掉的卡还能按」。
func _find_buttons(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for ch in root.get_children():
		if ch is Button and (ch as Button).is_visible_in_tree():
			out.append(ch)
		out.append_array(_find_buttons(ch))
	return out


func _correct_index(m: Node, qid: String) -> int:
	var q: Dictionary = ContentDB.round_question(m.round_idx, qid)
	var opts: Variant = q.get("options", [])
	if typeof(opts) == TYPE_ARRAY:
		for i in range((opts as Array).size()):
			if bool((opts as Array)[i].get("correct", false)):
				return i
	return 0


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT + name + ".png")
	print("[flow] %s -> %s" % [name, "ok" if err == OK else "ERR %d" % err])
