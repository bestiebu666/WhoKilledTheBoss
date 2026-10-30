extends Node
## 工程入口：先把「进入页 / 选幕页」挂上，选完幕再实例化那一幕的场景。
##
## 为什么要有这一层：main.tscn 就是第一幕的地图本身，它不该知道自己是被谁打开的。
## 外壳负责「选幕」这件事，地图只管把那一幕演好 —— 两边互不打扰：
##   · 自检 / 截图脚本仍然可以直接 load("res://scenes/main.tscn") 单独跑一遍地图；
##   · 想跳过进入页直接看地图，把 project.godot 的 run/main_scene 改回 main.tscn 即可。
##
## 换场景的中转都走 _load_act()，「重新走一遍」走 restart_act() —— 重开的是本幕，
## 不会把玩家退回标题页。

var entry: Frontend = null        ## 进入页 / 选幕页那一层 UI
var act: Node = null              ## 当前这一幕的场景实例（第一幕 = 办公室地图）

var _act_path := ""


func _ready() -> void:
	show_entry()


## 挂上进入页（重开本幕不会调它，所以不会突然跳回标题）。
func show_entry() -> void:
	# 页面入口显式点一次 BGM（同曲重复点会自己 return，不会重头播）。
	Audio.play_bgm()
	if entry != null:
		return
	entry = Frontend.new()
	entry.name = "Frontend"
	add_child(entry)
	entry.act_chosen.connect(_on_act_chosen)


func _on_act_chosen(scene_path: String) -> void:
	if not _load_act(scene_path):
		return
	# 地图挂上了，进入页就该让位 —— 否则它会盖在游戏上面（layer 20 > Hud 的 10）。
	if entry != null:
		remove_child(entry)
		entry.queue_free()
		entry = null


## 重新走一遍本幕。main.gd 里的「重新走一遍」按钮会调它（用 has_method 探测，
## 所以直接跑 main.tscn 的时候不会出问题）。
func restart_act() -> void:
	if _act_path == "":
		return
	_load_act(_act_path)


func _load_act(scene_path: String) -> bool:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("[App] 打不开这一幕的场景：%s" % scene_path)
		return false

	# 先摘掉旧的再 queue_free —— 不然同一帧里会短暂并存两个同名节点。
	if act != null:
		remove_child(act)
		act.queue_free()
		act = null

	act = packed.instantiate()
	act.name = "Act"
	add_child(act)
	_act_path = scene_path
	# 地图这一层的页面入口也点一次。现在全程同一首曲子，同曲会自己 return；
	# 将来若给地图单独配一首，只要把这里的 id 换掉就行。
	Audio.play_bgm()
	print("[App] 进入 %s" % scene_path)
	return true
