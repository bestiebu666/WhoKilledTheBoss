extends Node
## 布置俯视图：不是游戏的一部分，只是把整间设计部从正上方拍一张、标上名字。
## 跑法（不要加 --headless，需要真实渲染）：
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/topview.tscn
##
## 图的朝向固定：**上方 = 北（-z），右方 = 东（+x）**，和 room.json 的注释一致。
## 每个东西底下一个小圆点、名字挂在上方（垫白底方便在图上圈改）；
## 同名重叠的自动往上错开一行。背景铺 2 米网格 + 房间外沿坐标刻度 + 米制标尺。

const OUT_DIR := "res://shots/"
const OUT_NAME := "布置俯视图"
const WIN := Vector2i(1920, 1200)      # 出图分辨率（跟着窗口走）
const GRID_M := 2.0                    # 网格间距（米）

## ---------------------------------------------------------------- 全局字号总开关
## 2026-10-13：作者要求「整个游戏的字体稍微改大一点」。
## 本文件（设计部布置俯视图）的每一处文字都要经过 `_settings()` 这一个口子，
## 所以在那里乘系数即可。和 frontend.gd / hud.gd 是同一个开关、同一个数值 ——
## ⚠ **三份要一起改**，只改一个会让这张图上的字和游戏里的字大小不一致。
## 1.0 = 原样；1.15 = 放大 15%。取值理由见 frontend.gd 里那段注释。
const FONT_SCALE := 1.15

var main: Node3D
var cam: Camera3D
var _layer: CanvasLayer
var _labels: Array = []                # {pos, text, color, screen}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	get_window().size = WIN
	await _settle(3)

	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(30)

	# HUD（进度条 / 信息卡）在图上只会碍事
	if main.hud != null:
		(main.hud as CanvasLayer).visible = false

	# 天花板和 6 盏吊灯正好扣在头顶，不摘掉就什么都看不见。
	# 灯本体留着（地板上的光斑是它打的，有点层次反而好看），只摘灯罩。
	for ch in main.get_children():
		var n := String(ch.name)
		if n == "SM_B_Ceiling" or n.begins_with("SM_B_Lamp"):
			(ch as Node3D).visible = false
	# 点击落点圈跟着玩家跑，俯视图上是个没意义的圈
	for ch in main.get_children():
		if String(ch.name) == "SM_FX_Marker":
			(ch as Node3D).visible = false
	# 头顶的思考框是「人身上的界面」，从正上方看就是四朵白云糊在名字上 —— 摘掉。
	for nid in main._npc_bubbles:
		var bb: Node3D = main._npc_bubbles[nid]
		if bb != null:
			bb.visible = false

	var rs: Vector3 = main.room_size
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	cam = Camera3D.new()
	cam.name = "TopCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# 正交视野按「房间 + 边距」反算。上下多留 5.6 米 —— 不是浪费，
	# 是给北墙那一排标签留地方：不然「人台」「雕塑」这些会被顶到房间外面去。
	cam.size = maxf(rs.z + 5.6, (rs.x + 3.0) / aspect)
	cam.position = Vector3(0.0, 30.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # 镜头朝下：上=北，右=东
	add_child(cam)
	cam.make_current()
	main.camera_locked = true                         # 别让 main 的 _sync_camera 把相机抢回去

	await _settle(6)
	await _build_overlay()
	await _settle(6)

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + OUT_NAME + ".png"
	var err := img.save_png(path)
	print("[topview] %s  %d×%d  -> %s"
		% [path, img.get_width(), img.get_height(), "ok" if err == OK else "ERR %d" % err])
	Audio.shutdown()   # 放掉 BGM 资源，退出日志才干净
	get_tree().quit(0 if err == OK else 1)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


# ---------------------------------------------------------------- 图层

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "TopOverlay"
	_layer.layer = 30
	add_child(_layer)

	_collect()

	var vh := get_viewport().get_visible_rect().size.y
	var px_per_m := vh / cam.size
	for it in _labels:
		# anchor = 物件真实位置（圆点钉在这儿，永远不动）
		# 名字的位置另算。两者分开，否则错开一多，圆点也跟着飘，
		# 图上标的就不是真实位置了。
		var p := cam.unproject_position(Vector3(it["pos"].x, 0.0, it["pos"].z))
		it["anchor"] = p

	_add_grid()

	# --- 先把名字都建出来，等一帧量出真实宽高，再做避让 ---
	# 白底必须先建、且紧挨在字前面 —— 不然后加的底会盖在字上面，字就看不见了。
	var nodes: Array = []
	for it in _labels:
		var bg := ColorRect.new()
		bg.color = Color(1, 1, 1, 0.90)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.visible = false
		_layer.add_child(bg)
		var lab := Label.new()
		lab.text = it["text"]
		lab.label_settings = _settings(it["color"])
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(lab)
		nodes.append({"it": it, "lab": lab, "bg": bg})
	await _settle(2)

	# --- 矩形避让：撞上了就整块错开一行，挪到不撞为止 ---
	# 默认一律往上排（画面上方留了 2.8 米白边，就是给北墙那排标签用的）；
	# 只有真的顶出画面了，才改往下排。
	var boxes: Array = []
	for n in nodes:
		var lab: Label = n["lab"]
		var it: Dictionary = n["it"]
		var a: Vector2 = it["anchor"]
		var txt: Vector2 = lab.get_minimum_size()
		var w := txt.x + 12.0
		var h := txt.y + 4.0
		var x := a.x - w * 0.5
		var rect := _pack(x, w, h, a.y - 13.0 - h, -1.0, boxes)
		if rect.position.y < 6.0:
			rect = _pack(x, w, h, a.y + 13.0, 1.0, boxes)
		boxes.append(rect)
		n["rect"] = rect

	# --- 落笔 ---
	for n in nodes:
		var it: Dictionary = n["it"]
		var lab: Label = n["lab"]
		var a: Vector2 = it["anchor"]
		var rect: Rect2 = n["rect"]
		var col: Color = it["color"]

		var bg: ColorRect = n["bg"]
		bg.visible = true
		bg.position = rect.position
		bg.size = rect.size

		lab.size = rect.size
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.position = rect.position

		# 名字被错开之后，用一条细线把它和圆点连起来，免得不知道指的是谁
		var top: float = rect.position.y
		var bot: float = rect.position.y + rect.size.y
		var gap_a := a.y - bot          # 名字在上方
		var gap_b := top - a.y          # 名字在下方
		if gap_a > 3.0:
			_stem(a, bot, col)
		elif gap_b > 3.0:
			_stem(a, top, col)

		var dot := ColorRect.new()
		dot.color = col
		dot.size = Vector2(9, 9)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.position = a - Vector2(4.5, 4.5)
		_layer.add_child(dot)

	_add_frame(px_per_m)


func _collect() -> void:
	var props: Variant = ContentDB.room.get("props", [])
	if typeof(props) == TYPE_ARRAY:
		for p in props:
			var pn := str((p as Dictionary).get("name", ""))
			var slot := Models.slot_of("prop:" + pn)
			var cn := Models.cn_name(slot) if slot != "" else pn
			_labels.append({"pos": ContentDB.vec3((p as Dictionary).get("pos"), Vector3.ZERO),
				"text": _short(cn), "color": Color("#4B4A47")})
	for s in ContentDB.spots:
		_labels.append({"pos": ContentDB.vec3(s.get("pos"), Vector3.ZERO),
			"text": _short(str(s.get("name", ""))), "color": Color("#C2703F")})
	for n in ContentDB.npcs:
		_labels.append({"pos": ContentDB.vec3(n.get("pos"), Vector3.ZERO),
			"text": _short(str(n.get("name", ""))), "color": Color("#3F6EA8")})


## 「整组工位桌 1（岛北排，3 个座位，椅子朝北）」→「整组工位桌 1」
func _short(s: String) -> String:
	var i := s.find("（")
	var t := s.substr(0, i) if i >= 0 else s
	i = t.find("(")
	if i >= 0:
		t = t.substr(0, i)
	return t.strip_edges().substr(0, 14)


## 从 y0 开始、朝 dir 方向一行一行试，直到和已有方块都不相交。返回定好的矩形。
func _pack(x: float, w: float, h: float, y0: float, dir: float, boxes: Array) -> Rect2:
	var y := y0
	var step := (h + 3.0) * dir
	var guard := 0
	while guard < 24:
		guard += 1
		var hit := false
		var cx := x + w * 0.5
		var cy := y + h * 0.5
		for b in boxes:
			var r := b as Rect2
			var dx := absf(cx - (r.position.x + r.size.x * 0.5))
			var dy := absf(cy - (r.position.y + r.size.y * 0.5))
			if dx < (w + r.size.x) * 0.5 + 4.0 and dy < (h + r.size.y) * 0.5 + 3.0:
				hit = true
				break
		if not hit:
			break
		y += step
	return Rect2(x, y, w, h)


## 把「设计字号」换算成**实际字号** —— 本文件所有文字都必须过这里，见 FONT_SCALE。
func _fs(base: int) -> int:
	return maxi(1, int(round(float(base) * FONT_SCALE)))


func _settings(col: Color, size: int = 15) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = _fs(size)
	ls.font_color = col
	# 白底已经垫好了，就不再描边 —— 描边会把细笔画糊掉
	ls.outline_size = 0
	return ls


## 圆点到名字之间那条细连线
func _stem(a: Vector2, edge_y: float, col: Color) -> void:
	var stem := ColorRect.new()
	stem.color = Color(col.r, col.g, col.b, 0.5)
	stem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stem.size = Vector2(1.5, absf(a.y - edge_y))
	stem.position = Vector2(a.x - 0.75, minf(a.y, edge_y))
	_layer.add_child(stem)


# ---------------------------------------------------------------- 网格 / 标尺

func _add_grid() -> void:
	var rs: Vector3 = main.room_size
	var hx := rs.x * 0.5
	var hz := rs.z * 0.5
	var gcol := Color(0.25, 0.22, 0.18, 0.10)
	var x := -floorf(hx / GRID_M) * GRID_M
	while x <= hx + 0.01:
		var a := cam.unproject_position(Vector3(x, 0.0, -hz))
		var b := cam.unproject_position(Vector3(x, 0.0, hz))
		var ln := ColorRect.new()
		ln.color = gcol
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ln.size = Vector2(1.0, b.y - a.y)
		ln.position = a
		_layer.add_child(ln)
		x += GRID_M
	var z := -floorf(hz / GRID_M) * GRID_M
	while z <= hz + 0.01:
		var a := cam.unproject_position(Vector3(-hx, 0.0, z))
		var b := cam.unproject_position(Vector3(hx, 0.0, z))
		var ln2 := ColorRect.new()
		ln2.color = gcol
		ln2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ln2.size = Vector2(b.x - a.x, 1.0)
		ln2.position = a
		_layer.add_child(ln2)
		z += GRID_M

	# 房间外沿
	var tl := cam.unproject_position(Vector3(-hx, 0.0, -hz))
	var br := cam.unproject_position(Vector3(hx, 0.0, hz))
	var border := ColorRect.new()
	border.color = Color(0.25, 0.22, 0.18, 0.0)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.position = tl
	border.size = br - tl
	_layer.add_child(border)
	for seg in [[Vector2(tl.x, tl.y), Vector2(br.x - tl.x, 2.0)],
			[Vector2(tl.x, br.y - 2.0), Vector2(br.x - tl.x, 2.0)],
			[Vector2(tl.x, tl.y), Vector2(2.0, br.y - tl.y)],
			[Vector2(br.x - 2.0, tl.y), Vector2(2.0, br.y - tl.y)]]:
		var e := ColorRect.new()
		e.color = Color(0.25, 0.22, 0.18, 0.35)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.position = seg[0]
		e.size = seg[1]
		_layer.add_child(e)


func _add_frame(px_per_m: float) -> void:
	var vp := get_viewport().get_visible_rect().size

	var title := Label.new()
	title.text = "设计部 · 布置俯视图　｜　上 = 北 (-z)　右 = 东 (+x)　｜　小圆点 = 物件所在位置　｜　浅线 = 2 米网格"
	title.label_settings = _settings(Color("#2E2D2B"), 21)
	title.position = Vector2(28, 20)
	_layer.add_child(title)

	var note := Label.new()
	note.text = "在图上直接圈 / 写字标出要改的地方就行　·　右下角是米制标尺　·　房间外沿每 2 米一个坐标刻度"
	note.label_settings = _settings(Color("#6E675E"), 16)
	note.position = Vector2(28, 52)
	_layer.add_child(note)

	var bar_len := 2.0 * px_per_m
	var bar := ColorRect.new()
	bar.color = Color("#2E2D2B")
	bar.size = Vector2(bar_len, 4)
	bar.position = Vector2(vp.x - bar_len - 48, vp.y - 50)
	_layer.add_child(bar)
	for i in 3:
		var cap := ColorRect.new()
		cap.color = Color("#2E2D2B")
		cap.size = Vector2(2, 10)
		cap.position = Vector2(vp.x - bar_len - 48 + bar_len * i * 0.5 - 1, vp.y - 53)
		_layer.add_child(cap)
	var tick := Label.new()
	tick.text = "2 米"
	tick.label_settings = _settings(Color("#2E2D2B"), 16)
	tick.position = Vector2(vp.x - bar_len - 48, vp.y - 76)
	_layer.add_child(tick)

	var rs: Vector3 = main.room_size
	var x := -8
	while x <= 8:
		_tick(Vector3(float(x), 0.0, rs.z * 0.5 + 0.55), str(x))
		x += 2
	var z := -6
	while z <= 6:
		_tick(Vector3(-rs.x * 0.5 - 0.75, 0.0, float(z)), str(z))
		z += 2


func _tick(world: Vector3, txt: String) -> void:
	var p := cam.unproject_position(world)
	var lab := Label.new()
	lab.text = txt
	var ls := _settings(Color("#7C7468"), 14)
	ls.outline_size = 0
	lab.label_settings = ls
	lab.size = Vector2(44, 16)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.position = p + Vector2(-22, -8)
	_layer.add_child(lab)
