extends Node
## 感叹号落点核对探针（**只在核对时跑，不是游戏的一部分**）。
##
## 作者 2026-10-06 夜：「办公室一共有 6 张桌子……4 是外聘设计总监的，6 是部长的」
##   → 南排补了 `leader_desk` / `boss_desk` 两个桌面探索点。
##
## 普通的第一人称截图**看不准**：两排桌子只差 0.97 米深，南排的感叹号（更近、更低）
##   和北排的（更远、更高）在画面上叠在一起，靠肉眼数不清谁是谁。
##
## 所以这里做一件事：**把感叹号临时平放**（Sprite3D 关掉 billboard、绕 X 转 −90°，
##   让它朝天花板），再挂一个正交俯视相机 —— 这一下就成了「平面图 + 5 个感叹号」，
##   哪根压在桌上、哪根掉在地上，一眼看出。
##
## 跑法（不加 --headless）：
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_iconprobe.tscn

const OUT := "res://shots/_iconprobe_工位岛.png"

var main: Node3D


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(45)

	# ---- ① 先把世界坐标算出来打印，跟画面互相印证 ----
	print("---- 探索点感叹号圆心（世界坐标）----")
	for sid in ["feng_desk", "empty_seat", "intern1_desk", "leader_desk", "boss_desk"]:
		var s: Dictionary = {}
		for it in ContentDB.spots:
			if str(it.get("id", "")) == sid:
				s = it
				break
		if s.is_empty():
			print("  ", sid, " 找不到")
			continue
		var pos := ContentDB.vec3(s.get("pos"), Vector3.ZERO)
		var size := ContentDB.vec3(s.get("size"), Vector3.ZERO)
		# ⛔ `main` 是 Node3D，调它的方法是**动态**调用 → 返回值是 Variant，
		#    `var at := ...` 会 Parse Error（"Cannot infer the type"）。必须显式写类型。
		var at: Vector3 = main._clue_icon_at(pos, size, pos.y)
		var row := "北排" if pos.z < -3.8 else "南排"
		print("  %-13s pos=%s  size=%s  ->  圆心=%s   [%s]" % [sid, pos, size, at, row])

	# ---- ② 把影响俯视的东西摘掉 ----
	for ch in main.get_children():
		var n := String(ch.name)
		if n == "SM_B_Ceiling" or n.begins_with("SM_B_Lamp"):
			(ch as Node3D).visible = false
	if main.hud != null:
		(main.hud as CanvasLayer).visible = false

	# ---- ③ 感叹号平放（朝上），这样俯视才看得见 ----
	var flat := 0
	for id in main._clue_icons:
		var sp: Sprite3D = main._clue_icons[id]
		if sp == null:
			continue
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		flat += 1
	print("平放的感叹号：", flat, " 个")

	# ---- ④ 正交俯视工位岛 ----
	# ⚠ 取景要**连带作者标注图上的名字标签**（它们在世界 z ≈ −7 那一带），否则拼「作者标注 vs
	#    我的落位」时那半边没有标签、没法核对。所以：
	#    · 视口改成 1300×1040（比例 1.25，比 16:9 高）—— 否则 16:9 里装不下 4.9 米的纵深；
	#    · 相机心 z 从 −3.82 挪到 **−4.5**，KEEP_WIDTH / size 6.125
	#      → 覆盖 x ∈ [−7.06, −0.94]、z ∈ [−6.95, −2.05]。
	var vp := get_window()
	vp.size = Vector2i(1300, 1040)
	await _settle(3)

	var pc := get_viewport().get_camera_3d() as Camera3D
	if pc != null:
		pc.current = false
	var c := Camera3D.new()
	c.name = "IconProbeCam"
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.keep_aspect = Camera3D.KEEP_WIDTH          # size = 画面**宽**多少米
	c.size = 6.125
	c.position = Vector3(-4.0, 12.0, -4.5)
	c.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	main.add_child(c)
	c.current = true
	await _settle(10)

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT)
	print("[iconprobe] %s -> %s" % [OUT, "ok" if err == OK else "ERR %d" % err])
	Audio.shutdown()
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
