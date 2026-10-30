extends Node
## 把整个灰盒导成一个 glb，拖进 Blender 就是一套「1:1 的参考模型」：
## 每个方块的名字就是槽位名（SM_...），位置、尺寸、朝向都是真值 —— 照着描、或者直接拿来当比例参照。
## 输出：assets/placeholders/greybox_reference.glb
##
## 跑法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/export_greybox.tscn

const OUT_DIR := "res://assets/placeholders"
const OUT := "res://assets/placeholders/greybox_reference.glb"

## 这些不是「要建模的东西」，别带进 Blender。
const SKIP := ["Camera", "Sun", "WorldEnvironment", "Hud"]


func _ready() -> void:
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 单独装一个干净的根节点，只放几何。
	var root := Node3D.new()
	root.name = "Greybox"
	add_child(root)

	var moved := 0
	for c in main.get_children():
		if not (c is Node3D):
			continue
		if SKIP.has(str(c.name)):
			continue
		main.remove_child(c)
		root.add_child(c)
		moved += 1
	print("[导出灰盒] 收进 %d 个节点" % moved)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		print("[导出灰盒] append_from_scene 失败，错误码 %d" % err)
		get_tree().quit(1)
		return
	err = doc.write_to_filesystem(state, OUT)
	if err != OK:
		print("[导出灰盒] write_to_filesystem 失败，错误码 %d" % err)
		get_tree().quit(1)
		return

	var size := 0
	if FileAccess.file_exists(OUT):
		size = FileAccess.get_file_as_bytes(OUT).size()
	print("[导出灰盒] 完成：%s（%.1f KB）" % [OUT, float(size) / 1024.0])

	# 顺手把槽位清单打出来，方便和对照表互相核对。
	var names := PackedStringArray()
	for c in root.get_children():
		names.append(str(c.name))
	print("[导出灰盒] 槽位节点 %d 个：" % names.size())
	print("  " + ", ".join(names))
	get_tree().quit(0)
