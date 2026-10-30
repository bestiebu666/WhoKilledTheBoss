extends Node
## 头顶台词核对图：**3 轮 × 4 人 = 12 张**，一次拍全。
##
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_idleshot.tscn
##
## 每张 = 玩家站到那个小人正前方 1.4 米、低头看他头顶那个框 —— 就是玩家长按走近会看到的东西。
## ⚠ 中文最容易翻车的一条：Label3D 的默认字体没有汉字，会「文本非空、框也弹出来了，
##   但屏幕上一个字都没有」。所以这张图**必须真的看一眼**，不能只看自检。
##
## 产物 shots/头顶台词_R{轮}_{人}.png，再用 tools/idle_shot_sheet.py 拼成一张对照表。

const OUT_DIR := "res://shots/"
## 拍图顺序：和 objects.json 的 npcs 顺序一致
const ORDER := ["feng", "intern1", "boss", "director"]
const HINT := {"feng": "凤凰男", "intern1": "实习1号", "boss": "老板", "director": "总监"}
const STAND_DIST := 1.4      # 站到小人正前方多少米（思考框的弹出范围是 2.6 米）

var main: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(40)
	if main.hud != null:
		(main.hud as CanvasLayer).visible = false

	for ri in range(ContentDB.round_count()):
		main.round_idx = ri
		main._apply_idle_lines()
		for nid in ORDER:
			await _shoot_one(ri, nid)

	print("[idleshot] 完成：%d 轮 × %d 人" % [ContentDB.round_count(), ORDER.size()])
	get_tree().quit(0)


func _shoot_one(ri: int, nid: String) -> void:
	var npc := _npc_by_id(nid)
	var p := ContentDB.vec3(npc.get("pos"), Vector3.ZERO)
	var k := float(npc.get("scale", 1.0))
	var height := ContentDB.vec3(npc.get("size"), Vector3(0.6, 1.3, 0.6)).y * k
	var stand := Vector3(p.x, 0.0, p.z + STAND_DIST)
	main.player.global_position = stand
	# 走位之后等思考框「啵」出来（_tick_npcs 每帧喂距离给它）
	await _settle(26)

	# 抬头看那个框：相机在 3 米高，目标取框中心（头顶再往上大半个框高）
	var target_y := height + 0.62
	var pitch := -rad_to_deg(atan2(main.eye_height - target_y, STAND_DIST))
	await _pose(stand, 0.0, pitch)
	var bb: Variant = main._npc_bubbles.get(nid, null)
	print("    R%d %-9s 框里「%s」（弹出进度 %.2f）"
		% [ri + 1, HINT.get(nid, nid), "" if bb == null else str(bb.text_of()),
		   -1.0 if bb == null else float(bb.progress())])
	await _shot("头顶台词_R%d_%s" % [ri + 1, HINT.get(nid, nid)])


func _npc_by_id(id: String) -> Dictionary:
	for n in ContentDB.npcs:
		if str(n.get("id", "")) == id:
			return n
	return {}


func _pose(pos: Vector3, yaw: float, pitch: float) -> void:
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
	print("[idleshot] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
