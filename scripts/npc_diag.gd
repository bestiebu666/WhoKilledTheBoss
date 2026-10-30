extends Node
## NPC 动作诊断 —— 把「一靠近就像气球一样飘起来」量成数字。
##
## 报告每个人在几个距离上的：脚底世界高度、头顶世界高度、pivot 的 y 与 scale.y、
## 转头角度。**只要「脚底高度」不是常数、或者随距离变大，就是真的飘了。**
##
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/npcdiag.tscn

const OUT_DIR := "res://shots/diag/"

var main: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(40)

	print("\n===== NPC 动作诊断 =====")
	var who := "feng"
	var host: Node3D = main._npc_nodes[who]
	var hp := host.global_position
	print("参照人：%s  站位 (%.2f, %.2f)" % [who, hp.x, hp.z])

	for d in [5.0, 3.6, 2.6, 1.6, 0.8]:
		# 站在这个人的正南（+z）侧 d 米处，正对着他。
		main.has_target = false
		main.player.global_position = hp + Vector3(0.0, 0.0, d)
		await _settle(70)
		var r := await _sample(who, 150)
		# Variant：调用 thinking_bubble 自己的方法，静态标成 Node3D 会解析失败。
		var bub: Variant = main._npc_bubbles[who]
		print("  距离 %.1f m │ 脚底 %+.4f~%+.4f m │ 头顶 %.4f~%.4f m │ 起伏 %.1f mm │ 高 %.1f mm │ 转头 %+.1f° │ 思考框 %.2f"
			% [d, r["foot_lo"], r["foot_hi"], r["top_lo"], r["top_hi"],
			   (r["foot_hi"] - r["foot_lo"]) * 1000.0,
			   (r["top_hi"] - r["top_lo"]) * 1000.0,
			   rad_to_deg(r["look"]), bub.progress()])

	# 近景：相机悬在 3 米高（「悬浮记录仪」），所以要按 atan(高度差/水平距离) 给俯角，
	# 不然人整个落在画面下沿之外 —— 上一版就是这么把思考框漏掉的。
	main.player.global_position = hp + Vector3(0.0, 0.0, 2.0)
	main.yaw = 0.0
	main.pitch = -38.0
	main._sync_camera()
	await _settle(90)
	await _shot("diag_near_0")
	# 换个角度再拍一张，确认框是「永远正面朝相机」
	main.player.global_position = hp + Vector3(2.0, 0.0, 1.4)
	main.yaw = -34.0
	main.pitch = -38.0
	main._sync_camera()
	await _settle(60)
	await _shot("diag_near_1")

	# 思考框的「收」也要验：退远，确认它自己缩回去
	main.player.global_position = hp + Vector3(0.0, 0.0, 5.0)
	await _settle(90)
	var far_bub: Variant = main._npc_bubbles[who]
	print("  退到 5.0 m 之后，思考框进度 %.2f（应该是 0）" % far_bub.progress())

	# 四个人的形状各不一样 —— 一人拍一张，确认形状、大小、贴合都正常
	print("  四个人的思考框：")
	if main.hud != null:
		(main.hud as CanvasLayer).visible = false    # 拍照片，别让「已记下的东西」挡着
	for nid in ["feng", "intern1", "boss", "director"]:
		main.has_target = false
		var h2: Node3D = main._npc_nodes[nid]
		var b2: Variant = main._npc_bubbles[nid]
		main.player.global_position = h2.global_position + Vector3(0.0, 0.0, 2.0)
		main.yaw = 0.0
		main.pitch = -38.0
		main._sync_camera()
		await _settle(80)
		print("    %-9s %-11s 形状高 %.2f m  宽 %.2f m"\
			% [nid, b2.style_of(), b2.art_height(), b2.art_width()])
		await _shot("bubble_%s" % nid)

	print("===== 诊断结束 =====\n")
	get_tree().quit(0)


## 采样 frames 帧，回报各项的极值。
func _sample(who: String, frames: int) -> Dictionary:
	var host: Node3D = main._npc_nodes[who]
	var pivot: Node3D = main._npc_pivot[who]
	var foot_lo := INF
	var foot_hi := -INF
	var top_lo := INF
	var top_hi := -INF
	var sy_lo := INF
	var sy_hi := -INF
	for i in range(frames):
		await get_tree().process_frame
		if not is_instance_valid(pivot):
			continue
		var b := _vis_bounds(host)
		foot_lo = minf(foot_lo, b.x)
		foot_hi = maxf(foot_hi, b.x)
		top_lo = minf(top_lo, b.y)
		top_hi = maxf(top_hi, b.y)
		sy_lo = minf(sy_lo, pivot.scale.y)
		sy_hi = maxf(sy_hi, pivot.scale.y)
	var look: float = main._npc_look[who]
	return {
		"foot_lo": foot_lo, "foot_hi": foot_hi,
		"top_lo": top_lo, "top_hi": top_hi,
		"sy_lo": sy_lo, "sy_hi": sy_hi, "look": look,
	}


## 视觉的「脚底高度 / 头顶高度」（世界坐标）。
## ⚠ 取**局部包围盒的底面中心**，不是 8 个角 —— 角点在身体倾斜时会甩出
## 十几毫米的假位移（AABB 是松垮的盒子，并不贴着身体），会把「脚有没有离地」测错。
func _vis_bounds(host: Node3D) -> Vector2:
	var lo := INF
	var hi := -INF
	for mi in _meshes(host):
		if mi.mesh == null:
			continue
		var a: AABB = mi.mesh.get_aabb()
		var c := a.get_center()
		var bot: Vector3 = mi.global_transform * Vector3(c.x, a.position.y, c.z)
		var top: Vector3 = mi.global_transform * Vector3(c.x, a.position.y + a.size.y, c.z)
		lo = minf(lo, bot.y)
		hi = maxf(hi, top.y)
	return Vector2(lo, hi)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var mi := cur as MeshInstance3D
		if mi != null:
			out.append(mi)
	return out


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print("[diag] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
