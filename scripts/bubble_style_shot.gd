extends Node
## 思考框形状对照图：把**四个人头上那四个形状**按同样的排布摆一遍，方便和参考图对着看。
##
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/bubbleshot.tscn
##
## 用的是每个人**自己那份** bubble 配置（objects.json），所以这张图就是「游戏里会看到的」。
## 框里的字是内容位（cfg.text）—— NPC 现在是空字符串，这里拿名字占着，方便对号。

const OUT_DIR := "res://shots/"

## 摆的顺序 = 参考图第一列从上到下：星芒 / 方框尾巴 / 云朵射线 / 斜格面板
const ORDER := ["feng", "intern1", "boss", "director"]
const HINT := {
	"feng": "星芒",
	"intern1": "方框+尾巴",
	"boss": "云朵+射线",
	"director": "斜格面板",
}

var main: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(40)
	if main.hud != null:
		(main.hud as CanvasLayer).visible = false
	main.camera_locked = true
	# 人身上那四朵别一起凑热闹
	for nid in main._npc_bubbles:
		var bb: Node3D = main._npc_bubbles[nid]
		if bb != null:
			bb.visible = false

	var t0 := Time.get_ticks_msec()
	for i in range(ORDER.size()):
		var nid: String = ORDER[i]
		var npc := _npc_by_id(nid)
		var cfg: Dictionary = main._bubble_cfg(npc.get("bubble"))
		cfg["range"] = 9999.0
		cfg["text"] = str(npc.get("name", nid))   # ← 内容位，先拿名字占着
		cfg["line_h"] = 0.20
		var b: Variant = BubbleScript.new()
		# host_size 传 0 高：形状下沿就落在节点自己的位置上，方便排排坐
		b.configure(cfg, Vector3(1.0, 0.0, 1.0), "sheet%d" % i)
		add_child(b)
		# 2×2，和参考图一样是「一列一列从上往下」的顺序
		var col := float(i % 2)
		var row := float(i / 2)
		b.global_position = Vector3(-0.80 + col * 1.60, 1.66 - row * 1.02, -0.5)
		b.set_distance(0.0)
		print("    %-9s %-11s 形状 %.2f×%.2f m" % [nid, b.style_of(), b.art_width(), b.art_height()])
	print("[bubbleshot] 四张形状贴图现画用了 %d ms" % (Time.get_ticks_msec() - t0))
	await _settle(90)

	# 取景：按相机自己的 fov 反推距离，别凭手感 —— 上一版就是靠估的，把下面一排切了
	var cam: Camera3D = main.camera
	var fov := cam.fov
	var need_h := 2.35          # 2×2 一共占多高（米）
	var need_w := 2.60
	var d_h := (need_h * 0.5 + 0.45) / tan(deg_to_rad(fov * 0.5))
	var aspect := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)) \
		/ float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	var d_w := (need_w * 0.5 + 0.45) / (tan(deg_to_rad(fov * 0.5)) * aspect)
	var dist := maxf(d_h, d_w)
	cam.global_position = Vector3(0.0, 1.14, -0.5 + dist)
	cam.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	await _settle(10)
	await _shot("思考框_四人形状")
	print("[bubbleshot] 完成。左→右、上→下：%s"
		% ", ".join(ORDER.map(func(x: String) -> String: return "%s·%s" % [x, HINT[x]])))
	get_tree().quit(0)


const BubbleScript := preload("res://scripts/thought_bubble.gd")


func _npc_by_id(id: String) -> Dictionary:
	for n in ContentDB.npcs:
		if str(n.get("id", "")) == id:
			return n
	return {}


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print("[bubbleshot] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
