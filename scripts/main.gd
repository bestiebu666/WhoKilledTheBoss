extends Node3D
## 第一幕：设计部灰盒 + 点击探索 + 判断题
##
## 链路：点击地面移动 → 点击物件弹信息卡 → 6 个看完 → 点 NPC 出题
##      → 选中即判定 → 答对解锁新剧情 / 答错出现新线索 → 3 题答完落幕
##
## 视角是「悬浮记录仪」：相机吊在 3.0 米高（远高于门和 NPC）跟着你走，俯视整间 ——
## 主角是「神器」，本来就该高高在上，不是 NPC 的同事。按住左键拖动环顾：
## 可以低头看脚下，也可以抬头看天花板；松开时几乎没动就是点地面走路。
## 房间四面是 4.5 米满高墙 + 一整块天花板，抬头只会看到它们，看不到建模边界。
##
## 主角不做建模：玩家节点只有一个胶囊碰撞体（走路、贴墙、相机跟随靠它），
## 没有任何可见网格 —— 低头也看不到自己。
## 想调相机（高度 / 视场角 / 灵敏度 / 俯仰范围）改 data/room.json 的 camera 段，代码不用动。
## WASD 也能走，纯属方便，不影响点击那套逻辑。
##
## 世界变色（第二、三幕）不在本文件范围。

const WALK_SPEED := 3.8
const ARRIVE_EPS := 0.20
const INTERACT_RANGE := 3.2
## 按下左键后累计位移小于这么多像素才算「点击」，否则算「拖动环顾」。
## 这两个动作共用左键，必须靠阈值分开 —— 否则每次转头都会顺带走一步。
const CLICK_SLOP := 6.0
## 吊灯。室内没有太阳，光的层次全靠这几盏。
## 层高提到 4.5 米之后灯离地更远，所以能量和半径都往上给一点。
const LAMP_ENERGY := 0.95
const LAMP_RANGE := 10.0
## 答错的物件要不要变个颜色（第一幕的「新线索」视觉提示）。不想要就改 false。
const MARK_CONFLICT_SPOT := true

var camera: Camera3D
var player: CharacterBody3D
var marker: MeshInstance3D
var hud: Hud

var room_size := Vector3(16.0, 4.5, 12.0)
## 布景 / 探索点 / NPC 的尺寸统一乘这个系数（门可单独覆盖 —— 它是墙面/尺度的参照）。
## 房间大 + 相机高的情况下，原尺寸家具在画面里又大又堵 —— 缩一点才有居高临下的松弛感。
var prop_scale := 0.8
var target_pos := Vector3.ZERO
var has_target := false
var pending_spot := ""

## ---- 悬浮记录仪相机 ----
## 高度参考：门是 2.2 米。相机远高于门，就自然俯视 NPC 和整间屋子。
var eye_height := 3.0           ## 相机离地高度。想更「神器」就再往上抬，但要留出天花板的位置
var mouse_sens := 0.13          ## 拖动 1 像素转多少度
var pitch_min := -80.0          ## 能低到多低（负数 = 低头看脚下）
var pitch_max := 22.0           ## 能抬到多高（正数 = 抬头看天花板）
var yaw := -90.0                ## 水平朝向（度）。-90 = 朝东
var pitch := -34.0              ## 俯仰（度）。负数低头，正数抬头
## 截图 / 调试用：锁住相机不让它跟玩家走。
var camera_locked := false

var _dragging := false
var _drag_acc := 0.0

var scanned := {}                 # spot_id -> true
var answered := {}                # question_id -> bool(答对没有)
var story: Array[String] = []     # 新剧情
var clues: Array[String] = []     # 新线索

## ---- 回顾用（2026-10-14 新增，只读，不参与任何判定）----
## 每一轮「已经找到」的结论：轮次索引 -> 探索点 id 数组（按找到顺序）。
## ⛔ 必须按轮次分开记：**同一个 id 每轮的 lines / clue 都不同**，回看时要按
##    「当时那一轮」去取原文，否则第 1 轮的结论会在第 3 轮点开时显示第 3 轮的文案。
var found_by_round := {}
## 已答过的判断题：qid -> {round, chosen, correct}。用来回看「第 X 道」。
var answer_log := {}

## 第一幕第几轮（0 起）。三轮都是「看完全部可探索点（家具 + 小人）→ 自动出判断题 →
## 轮末过场」，轮末线索刷新 = 清空 `scanned`、感叹号全部回来、文案换一套（见 data/act1.json）。
## 几何（位置 / 大小）从头到尾只有一份，所以切轮次不用重建场景。
var round_idx := 0
## 这一轮的轮末过场弹过没有。防重入用（见 `_show_round_end`）。
var _round_end_shown := false

var _spot_nodes := {}             # spot_id -> StaticBody3D
var _npc_nodes := {}              # npc_id  -> StaticBody3D
var _clue_icons := {}             # spot_id -> Node3D     头顶的感叹号（有线索才显示）

var _last_dist := INF             # 卡住检测用
var _stuck_time := 0.0


func _ready() -> void:
	room_size = ContentDB.vec3(ContentDB.room.get("size", [16.0, 4.5, 12.0]), room_size)
	prop_scale = float(ContentDB.room.get("prop_scale", 1.0))

	_build_environment()
	_build_shell()
	_build_props()
	_build_spots()
	_build_npcs()
	_build_player()
	_build_marker()
	_build_camera(ContentDB.room.get("camera", {}))

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.option_chosen.connect(_on_option_chosen)
	hud.modal_closed.connect(_on_modal_closed)
	hud.restart_requested.connect(_on_restart)
	hud.advance_requested.connect(_on_advance)
	# 回顾入口（右上角「回顾 ▼」）：hud 只发"要看什么"，内容由这里组装回灌。
	hud.review_requested.connect(_on_review_requested)
	hud.review_menu_model = _review_menu_model

	# ⛔⛔ 2026-10-06 夜作者实测「一轮搜证 14 条，但画面上好多不需要搜证的也标了感叹号」：
	#    根因 = **这里从来没调过 `_refresh_clue_icons()`**。`_build_clue_icon()` 建出来的
	#    Sprite3D 默认 `visible = true`，而第一次「按本轮点位显隐」发生在**切轮次**的时候
	#    （`_on_advance()` 里那一次）—— 于是**第一轮开局 22 个感叹号全亮**，
	#    比 HUD 上写的「0/14」多出 8 个（正好是三轮都没文案的那 8 个点位：
	#    会议桌 / 沙发 / 雕塑 / 发财树 ×2 / 人台 2·3·4）。玩家点它们会弹出空卡或者
	#    弹不出东西，看起来就是「一堆不该有的感叹号」。
	#    ⭐ 建完图标**立刻按本轮点位收一遍**，这是唯一入口，别再等到切轮次才做。
	_refresh_clue_icons()
	_refresh_progress()
	hud.set_journal(story, clues)
	_refresh_hint()

	# 收工播报：哪些槽位换了真模型、哪些还是灰盒、有没有尺寸或面数超标。
	Models.report()


## 鼠标：按住左键拖动 = 环顾；按下后几乎没动就松开 = 点击（走路 / 看东西）。
## 这两件事共用左键，所以必须靠位移阈值分开 —— 否则每次转头都会顺带走一步。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var blocked := hud != null and hud.modal_visible
		if mb.pressed:
			if blocked:
				return
			_dragging = true
			_drag_acc = 0.0
		else:
			var was_click := _dragging and _drag_acc < CLICK_SLOP
			_dragging = false
			if was_click and not blocked:
				_handle_click(mb.position)
		return

	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_acc += absf(mm.relative.x) + absf(mm.relative.y)
		_look(mm.relative.x, mm.relative.y)
		return
	# ESC 关弹窗交给 Hud 自己管（`Hud._input`）—— 那边知道「这张卡能不能关」：
	# 判断题必须选一个，ESC 不该把它跳过去。这里再拦一道会把它变成万能逃生键。


## 拖多少像素转多少度。x 右移 = 视角右转，y 下移 = 低头。
func _look(dx: float, dy: float) -> void:
	yaw = wrapf(yaw - dx * mouse_sens, -180.0, 180.0)
	pitch = clampf(pitch - dy * mouse_sens, pitch_min, pitch_max)
	_sync_camera()


## 键盘走路（可选）：WASD 按当前朝向平移。
func _manual_move() -> Vector3:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		v.y += 1.0
	if Input.is_key_pressed(KEY_S):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		v.x += 1.0
	if v == Vector2.ZERO or camera == null:
		return Vector3.ZERO
	var b := camera.global_transform.basis
	var fwd := -b.z
	var right := b.x
	fwd.y = 0.0
	right.y = 0.0
	var dir := right * v.x + fwd * v.y
	if dir.length() < 0.001:
		return Vector3.ZERO
	return dir.normalized()


## 相机永远悬在玩家头顶 eye_height 米处，朝向由 yaw / pitch 决定。
## 相机不是玩家的子节点 —— 这样移动不会连带扭视角，转头也不会连带挪位置。
func _sync_camera() -> void:
	if camera_locked or camera == null or player == null:
		return
	camera.global_position = Vector3(
		player.global_position.x, eye_height, player.global_position.z)
	camera.rotation_degrees = Vector3(pitch, yaw, 0.0)


# ---------------------------------------------------------------- 场景搭建

func _make_material(c: Color, emission: float = 0.0) -> StandardMaterial3D:
	# 铁律：Metallic 一律 0，Roughness 0.85，只用 Base Color。
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.0
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c * emission
	return m


## 建一个方块。slot 是这个位置的「槽位名」（如 SM_F_Desk_01）——
## 它同时是场景节点名、是建模对照表上的一行、也是找模型的依据。
## 模型文件名未必等于槽位名：model_map.json 里可以让多个槽位共用一个模型
## （6 张工位桌共用一个 SM_F_Desk.glb），所以查文件走的是 Models 那边。
## 有文件就换真模型，没有就保持灰盒 —— 不报错、不阻塞。
##
## collide_h：碰撞体在竖直方向做多高（不填就是跟灰盒一样高）。
##   给「整组工位桌」这类物件用 —— 它上半截是隔板和椅子，灰盒却有整个高度，
##   摆在桌面上的探索点会正好卡在碰撞体内部，射线从相机打下来先撞到灰盒，
##   永远点不到那个探索点。把碰撞只做到桌面高度，桌面上的东西就露在外面了。
## host_yaw：宿主节点之后会绕 Y 转多少度（0/90/180/270 这类整角）。
##   ⛔ **必须在 attach 之前告诉它** —— 尺寸核对（逐轴比 AABB）是在挂模型的那一刻做的，
##   而「转宿主」的代码在这之后才跑。不说的话它拿到的还是没转的姿态，
##   宽在 x 的东西去比「预期宽在 z」就会直接报错（2026-10-05 公告栏就栽在这）。
func _add_box(slot: String, size: Vector3, center: Vector3, color: Color, group: String = "",
		collide_h: float = -1.0, host_yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = slot if slot != "" else "Box"
	body.position = center
	body.set_meta("slot", slot)

	var mi := MeshInstance3D.new()
	mi.name = "Greybox"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _make_material(color)
	body.add_child(mi)

	# collide_h 的三种取值：0 = **不要碰撞体**（地毯这类平铺在地上的装饰 —— 只有 8 厘米厚，
	# 加了碰撞盒玩家就会被劝在边上绕，而它本来就该踩着走）；
	# 正数 = 碰撞只做到这个高度（工位桌压到桌面，好让桌上的探索点露在碰撞外面）；
	# 不写 / 负数 = 整个灰盒高（默认）。
	if not is_zero_approx(collide_h):
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		var bs := BoxShape3D.new()
		var ch := collide_h if collide_h > 0.0 else size.y
		bs.size = Vector3(size.x, ch, size.z)
		cs.shape = bs
		# 碰撞体的底面跟灰盒底面齐平（不是居中）—— 缩的是上半截。
		cs.position = Vector3(0.0, (ch - size.y) * 0.5, 0.0)
		body.add_child(cs)

	add_child(body)
	if group != "":
		body.add_to_group(group)

	# 真模型接管外观；没有文件就保持灰盒。碰撞始终用灰盒尺寸当基准。
	# host_yaw 传进去：模型是在「转之前」的宿主空间里核尺寸的，得让它知道宿主马上要转。
	if slot != "":
		Models.attach(body, slot, size, mi, 1.0e9, host_yaw)
	return body


## 「没看过 = 微微发光」的统一做法：在网格上叠一层自发光 overlay。
## 灰盒和真模型走同一条路 —— 模型自己的颜色不会被改掉。
##
## ⚠ 2026-10-05 晚：**探索点不再用这套了** —— 作者说「不要再使用你那个发光线索定位了，
## 建模太大太丑，线索的提示和搜索都靠这个感叹号」。探索点现在改成头顶挂
## `icon_clue.png` 的感叹号（见 _build_clue_icon / _refresh_clue_icons）。
## 这段发光代码**留着还给 NPC 用**（`_light_npcs`）和别处 —— 别删。
func _set_glow(node: Node3D, on: bool, tint: Color = Color("#D98C6A")) -> void:
	if node == null:
		return
	var mat: StandardMaterial3D = _make_glow_material(tint) if on else null
	for mi in _mesh_list(node):
		mi.material_overlay = mat


func _make_glow_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _mesh_list(n: Node) -> Array[MeshInstance3D]:
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


## 挂上来的真模型还能再调两样，参数都写在 room.json 的 prop 里：
##
##   glow = { color, energy } —— 「微微发光」，给落地窗那种玻璃幕墙用。
##     诀窍是**把模型自己的漫反射贴图当自发光贴图**（MULTIPLY）：贴图里亮的部分
##     （天空、城市）发光多，暗的部分（窗框、铝料）几乎不发光 —— 天然就只让玻璃亮起来，
##     不用拆材质、不用另配一张 emission 贴图。能量要小才是「微微」（0.5），
##     这是给白天补一点透光感，不是做发光特效。
##
##   tint = { color, gain } —— 整体改色 / 提亮（饮水机要「更白一点」）。
##     就是拿颜色乘一遍 Base Color。**gain > 1 是提亮**：白的地方顶到纯白（灰度变小），
##     暗的地方只是等比提亮、相对层次还在，所以不会把面板涂平。
##     gain 超过 ~1.5 就会开始过曝发飘，一般 1.2~1.35 就够。
##
## 两个都是**覆盖材质**，所以必须先 duplicate —— glb 导入的材质是所有实例共享的，
## 直接改会波及别处（同名模型被复用两次时会一起变）。
func _style_model(node: Node3D, glow: Variant, tint: Variant) -> void:
	var has_glow := typeof(glow) == TYPE_DICTIONARY and not (glow as Dictionary).is_empty()
	var has_tint := typeof(tint) == TYPE_DICTIONARY and not (tint as Dictionary).is_empty()
	if not has_glow and not has_tint:
		return
	for mi in _mesh_list(node):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for si in range(mesh.get_surface_count()):
			var src: Material = mi.get_active_material(si)
			if src == null:
				src = mesh.surface_get_material(si)
			if src == null:
				continue
			# 复制一份再改 —— glb 导入的材质是所有实例共享的，直接改会波及别处。
			var m := src.duplicate() as StandardMaterial3D
			if m == null:
				continue
			if has_glow:
				var gd: Dictionary = glow
				m.emission_enabled = true
				m.emission = ContentDB.col(gd.get("color"), Color("#D3E7FA"))
				m.emission_energy_multiplier = float(gd.get("energy", 0.5))
				if m.albedo_texture != null:
					m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					m.emission_texture = m.albedo_texture
			if has_tint:
				var td: Dictionary = tint
				var c := ContentDB.col(td.get("color"), Color.WHITE)
				var g := float(td.get("gain", 1.0))
				# alpha 固定 1 —— 乘 float 会把 alpha 也放大，超过 1 会出怪事。
				m.albedo_color = Color(c.r * g, c.g * g, c.b * g, 1.0)
			mi.set_surface_override_material(si, m)


## 地面瓷砖：把作者给的几张「格子砖」贴图随机铺满地面。
##
## 一张图里是 cols × rows 个格子（实测 4 列 6 行，一格约 320×310 px，接近正方）。
## 作者要求「格子大小大概 50 厘米」—— 所以一张图铺出来就是 cols*cell × rows*cell
## = 2.0 × 3.0 米。它是**一块「铺块」**（一整块 24 格的地砖），不是无限重复的材质，
## 所以不能靠 uv1_scale 平铺，得老老实实按块摆。
##
## 每块随机挑一张图 + 随机水平/垂直翻转（4 种），4 张图 × 4 种 = 16 个组合；
## 地面 8 × 4 = 32 块，重复率很低，看不出是同一张图在复制。
## **随机种子写在 room.json 里** —— 固定种子，每次重开场景铺法一模一样（截图好对比）；
## 想换一种铺法就改那个数。默认 room.json 没配 floor_tiles 时这段整个跳过。
##
## 网格是「先按 50 厘米算出块数，再用房间尺寸反推每块实际多大」——
## 16 / 2.0 = 8、12 / 3.0 = 4，正好整除，所以每块就是标准的 2.0 × 3.0。
## 万一哪天房间不是整数倍，也是块数取整、边长微调，**不会在边上留一条没铺到的缝**。
func _build_floor_tiles() -> void:
	var cfg: Variant = ContentDB.room.get("floor_tiles")
	if typeof(cfg) != TYPE_DICTIONARY:
		return
	var d: Dictionary = cfg
	var files: Array = d.get("files", [])
	if files.is_empty():
		return

	var dir := str(d.get("dir", "res://assets/textures/floor/"))
	var texs: Array[Texture2D] = []
	for f in files:
		var p := dir + str(f)
		if ResourceLoader.exists(p):
			texs.append(load(p) as Texture2D)
		else:
			push_warning("floor_tiles：找不到贴图 %s" % p)
	if texs.is_empty():
		return

	var cell := float(d.get("cell", 0.5))
	var nx := maxi(1, int(round(room_size.x / (cell * float(int(d.get("cols", 4)))))))
	var nz := maxi(1, int(round(room_size.z / (cell * float(int(d.get("rows", 6)))))))
	var bw := room_size.x / float(nx)
	var bd := room_size.z / float(nz)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.get("seed", 20261006))

	var root := Node3D.new()
	root.name = "FloorTiles"
	add_child(root)

	for ix in nx:
		for iz in nz:
			var t: Texture2D = texs[rng.randi_range(0, texs.size() - 1)]
			var fx := rng.randf() < 0.5
			var fy := rng.randf() < 0.5
			var m := StandardMaterial3D.new()
			m.albedo_texture = t
			# UV 是 0..1：翻转 = 乘 -1，再把偏移补回 1，图才不会跑到格子外面去。
			m.uv1_scale = Vector3(-1.0 if fx else 1.0, -1.0 if fy else 1.0, 1.0)
			m.uv1_offset = Vector3(1.0 if fx else 0.0, 1.0 if fy else 0.0, 0.0)
			m.metallic = 0.0
			m.roughness = 0.85
			# 「不要太糊」：格子砖全是直角和斜线，视角一低最容易被拉花 ——
			# 各向异性过滤就是治这个的（默认的线性过滤在这种斜视下会糊成一片）。
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var pm := PlaneMesh.new()
			pm.size = Vector2(bw, bd)
			var mi := MeshInstance3D.new()
			mi.name = "Tile_%d_%d" % [ix, iz]
			mi.mesh = pm
			mi.material_override = m
			mi.position = Vector3(
				-room_size.x * 0.5 + bw * (float(ix) + 0.5), 0.0,
				-room_size.z * 0.5 + bd * (float(iz) + 0.5))
			root.add_child(mi)


## 色调映射模式名 -> 常量。作者在 room.json 的 `grade.tonemap` 里用字符串写。
## ⛔ 常量名拼错会**直接 Parse Error、整个脚本编译不过**（`REINHARDT` 不是 `REINHARD`，
##   已经踩过一次）—— 加新分支前先确认这个名字在当前 Godot 版本的 Environment 里真实存在。
func _tonemap_of(name: String) -> int:
	match name.to_lower():
		"aces":
			return Environment.TONE_MAPPER_ACES
		"filmic":
			return Environment.TONE_MAPPER_FILMIC
		"reinhardt":
			return Environment.TONE_MAPPER_REINHARDT
		_:
			return Environment.TONE_MAPPER_LINEAR


## 环境 + 全屏调色。
## ⭐ 2026-10-06：作者「模型到游戏里变灰了，要**高饱和 / 多巴胺 / 轻松活泼**，
##   **别改模型颜色、改整个环境色**」。落成两件事，参数全住 `room.json` 的 `grade` 段：
##   ① 环境光颜色 / 能量（改「环境色」，不动任何材质）；
##   ② 全屏 `adjustment`（亮度 / 对比 / **饱和度**）+ 色调映射 + 一点点泛光。
## ⛔ 这一整段只改画面观感，**绝不碰** room.json 里墙/地/顶/props 的 color，也不碰任何 glb。
##   ⚠ `adjustment` / `glow` 只在 Forward+ 生效（本项目就是 Forward+，见 project.godot）。
func _build_environment() -> void:
	var colors: Dictionary = ContentDB.room.get("colors", {})
	var grade: Dictionary = ContentDB.room.get("grade", {})

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = ContentDB.col(colors.get("bg"), Color("#E6E0D4"))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# 环境光颜色 / 能量 —— 这是「环境色」的主开关（室内：环境光打底 + 吊灯出层次）。
	env.ambient_light_color = ContentDB.col(grade.get("ambient_color"), Color("#FFF4E4"))
	env.ambient_light_energy = float(grade.get("ambient_energy", 0.45))
	env.tonemap_mode = _tonemap_of(str(grade.get("tonemap", "linear")))

	# ★ 全屏调色（滤镜）—— 「多巴胺」主要靠这里：饱和度拉高 + 对比略提 + 提亮。
	#   它是**逐像素统一处理**，和「改模型材质色」是两回事：随时可关、可调，一行数值的事。
	env.adjustment_enabled = true
	env.adjustment_brightness = float(grade.get("brightness", 1.0))
	env.adjustment_contrast = float(grade.get("contrast", 1.0))
	env.adjustment_saturation = float(grade.get("saturation", 1.0))

	# 轻泛光：让窗 / 灯这些「本来就亮」的地方晕开一点点，观感更活泼。
	# ⚠ 阈值要 >1，否则全画面发糊、窗户直接过曝成白斑。
	var g: Dictionary = grade.get("glow", {})
	env.glow_enabled = bool(g.get("enable", false))
	env.glow_intensity = float(g.get("intensity", 0.5))
	env.glow_bloom = float(g.get("bloom", 0.05))
	env.glow_hdr_threshold = float(g.get("threshold", 1.05))
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	env.ssao_enabled = false
	env.fog_enabled = false
	we.environment = env
	add_child(we)

	# 从北窗方向斜进来的天光。天花板会挡，所以不投影 —— 只给一点方向感。
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#FFF0D8")
	sun.light_energy = 0.22
	sun.shadow_enabled = false
	sun.rotation_degrees = Vector3(-40.0, 172.0, 0.0)
	add_child(sun)


## 外壳：地面 + 四面满高墙 + 天花板。**没有玩具箱底座** ——
## 房间是自己站进去的，不是摆在桌上看的微缩模型。
## 天花板比墙再多出一点（每边 0.6 米），所以贴到墙边把视角抬到头也只看到墙或天花板。
func _build_shell() -> void:
	var colors: Dictionary = ContentDB.room.get("colors", {})
	var wall_col := ContentDB.col(colors.get("wall"), Color("#EFE9DF"))

	# 地面。**这一块灰盒不再渲染了** —— 真正铺在地上的是下面 _build_floor_tiles() 生成的地砖。
	# 灰盒只留下两样东西：碰撞体（玩家踩在它上面）和 "floor" 这个组（射线点地面走路靠它）。
	# 不把它的网格关掉的话，灰盒顶面（y=0）和地砖面（y=0）会 z-fighting 闪成一片。
	var floor_body := _add_box(Models.slot_of("builtin:Floor"),
		Vector3(room_size.x, 0.1, room_size.z),
		Vector3(0.0, -0.05, 0.0),
		ContentDB.col(colors.get("floor"), Color("#DCD1BC")),
		"floor")
	var fmi := floor_body.get_node_or_null("Greybox") as MeshInstance3D
	if fmi != null:
		fmi.layers = 0          # 0 = 任何相机都不渲染；碰撞体和分组不受影响
	_build_floor_tiles()

	# 天花板 —— 相机能抬头，所以这块会被看得很清楚。尺寸比墙再多出一圈，避免和墙之间露缝。
	# 它被单独挪到第 2 层，而吊灯的 light_cull_mask 只开第 1 层 —— 于是天花板上只有环境光，
	# 不会被近在咫尺的灯泡烤成一片惨白（相机只有 3 米高，离顶很近，这个问题特别明显）。
	# 相机默认渲染所有层，所以玩家照样看得见它。
	var ceil_size := Vector3(room_size.x + 1.2, 0.2, room_size.z + 1.2)
	var ceil_col := ContentDB.col(colors.get("ceiling"), Color("#F7F2EA"))
	var ceil_body := _add_box(Models.slot_of("builtin:Ceiling"), ceil_size,
		ContentDB.box_center(Vector3(0.0, room_size.y, 0.0), ceil_size), ceil_col)
	var cmi := ceil_body.get_node_or_null("Greybox") as MeshInstance3D
	if cmi != null:
		cmi.layers = 1 << 1
		# 顶上吃不到直射光，用自发光当「地面反射回来的光」补一档 —— 否则抬头是一片闷灰。
		# 0.55 是量出来的：再低天花板就比墙暗一截（实测 #B6AC9C vs 墙 #E2D3BB），
		# 再高就整块发白、看不出这是个顶。
		cmi.material_override = _make_material(ceil_col, 0.55)

	var walls: Variant = ContentDB.room.get("walls", [])
	if typeof(walls) == TYPE_ARRAY:
		for w in walls:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			var wname := str(w.get("name", "Wall"))
			var size := ContentDB.vec3(w.get("size"), Vector3(1, 1, 1))
			var pos := ContentDB.vec3(w.get("pos"), Vector3.ZERO)
			_add_box(Models.slot_of("wall:" + wname), size,
				ContentDB.box_center(pos, size),
				ContentDB.col(w.get("color"), wall_col))

	_build_windows(colors)
	_build_ceiling_lights(colors)


## 窗：贴在墙内侧的自发光浅蓝板。**没有真的外面** ——
## 这样既有「白天」的光感，玩家又永远不会透过窗看到建模边界。
func _build_windows(colors: Dictionary) -> void:
	# ⚠ 2026-10-06 晚：东墙那两扇灰盒窗（E1/E2）按作者要求删掉之后，room.json 的
	#   `windows` 数组是**空的**，这个函数现在什么都不生成 —— 留着是给「以后想加
	#   自发光窗板」用。⛔ 要摆正的窗/门一律写成 `props` 里的 `prop:`（这段代码只
	#   造一块浅蓝板，读不了 rot、也不做模型归一化）。
	var wins: Variant = ContentDB.room.get("windows", [])
	if typeof(wins) != TYPE_ARRAY:
		return
	var c := ContentDB.col(colors.get("window"), Color("#C6D8E8"))
	for w in wins:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wname := str(w.get("name", "W"))
		var size := ContentDB.vec3(w.get("size"), Vector3(2.6, 1.2, 0.08))
		var pos := ContentDB.vec3(w.get("pos"), Vector3.ZERO)
		var win := _add_box(Models.slot_of("window:" + wname), size,
			ContentDB.box_center(pos, size), c)
		# 窗板自己发亮 —— 室内没有太阳，这块板在假装外面是白天。
		# 别给太亮：近距离看会直接过曝成一块白斑。
		var wmi := win.get_node_or_null("Greybox") as MeshInstance3D
		if wmi != null:
			wmi.material_override = _make_material(c, 0.40)


## 吊灯：灯罩吊在墙顶下方 + 一盏不投影的 OmniLight 往下打光。
## 刻意不投影 —— 6 盏带阴影的灯在低配机器上会掉帧，而人森风本来也不需要硬阴影。
## 视角能抬头，所以灯罩是会被看到的 —— 它本来就挂在天花板上，属于正常画面。
func _build_ceiling_lights(colors: Dictionary) -> void:
	var raw: Variant = ContentDB.room.get("ceiling_lights", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	var lamp_c := ContentDB.col(colors.get("lamp"), Color("#FFF6E0"))
	var panel := Vector3(1.15, 0.1, 1.15)
	var idx := 0
	for item in raw:
		if typeof(item) != TYPE_ARRAY or item.size() < 2:
			continue
		idx += 1
		var x := float(item[0])
		var z := float(item[1])
		var body := _add_box(Models.slot_of("lamp:%d" % idx), panel,
			Vector3(x, room_size.y - 0.1, z), lamp_c)
		var lmi := body.get_node_or_null("Greybox") as MeshInstance3D
		if lmi != null:
			# 灯罩自己也别太亮 —— 抬头近距离看它会直接过曝成一团白光。
			lmi.material_override = _make_material(lamp_c, 0.16)

		# 灯本体和灯罩拉开一截，光才铺得开 —— 挤在一起会烤出一块白斑。
		var l := OmniLight3D.new()
		l.name = "Lamp_%d" % idx
		l.position = Vector3(x, room_size.y - 0.8, z)
		l.light_color = Color("#FFF3E0")
		l.light_energy = LAMP_ENERGY
		l.omni_range = LAMP_RANGE
		l.shadow_enabled = false
		# 只照第 1 层 —— 天花板在第 2 层，所以它不会被灯烤出一块白斑。
		l.light_cull_mask = 1
		add_child(l)


## 布景：尺寸统一乘 prop_scale。个别物件可以自己写 scale 覆盖
## （门是 1.0 —— 它是墙面/尺度的参照，缩了整屋会变得像玩具）。
## collide 是「碰撞做到多高」，同样按 prop_scale 换算（整组工位桌用它把碰撞压到桌面）。
## rot 是「绕 Y 轴转多少度」—— 一组工位要背靠背拼成岛的时候靠它把第二组翻过来。
func _build_props() -> void:
	var props: Variant = ContentDB.room.get("props", [])
	if typeof(props) != TYPE_ARRAY:
		return
	for p in props:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pname := str(p.get("name", "Prop"))
		var k := float(p.get("scale", prop_scale))
		var size := ContentDB.vec3(p.get("size"), Vector3(0.5, 0.5, 0.5)) * k
		var pos := ContentDB.vec3(p.get("pos"), Vector3.ZERO)
		var collide := float(p.get("collide", -1.0)) * k
		var body := _add_box(Models.slot_of("prop:" + pname), size,
			ContentDB.box_center(pos, size),
			ContentDB.col(p.get("color"), Color("#E6DFD2")), "", collide)
		# 转的是宿主节点本身：灰盒、碰撞体、挂上来的真模型一起转。
		# 转轴就是节点原点（= 灰盒的底面中心），所以转完不会挪位置。
		var rot := float(p.get("rot", 0.0))
		if not is_zero_approx(rot):
			body.rotation_degrees = Vector3(0.0, rot, 0.0)
		# 「微微发光」（玻璃幕墙）/「提亮改色」（饮水机）：都是挂上真模型之后才设得了 ——
		# 灰盒没有材质覆盖可言（灰盒的颜色就是它本身）。见 _style_model 的注释。
		var model_node: Node = body.get_node_or_null("Model")
		if model_node is Node3D:
			_style_model(model_node, p.get("glow"), p.get("tint"))

		# ---- 2026-10-06 作者：「场景里的家具全部可探索，不是每个都挂感叹号，但每个都能点」----
		# 有 `explore` 字段的 prop（人台 / 饮水机 / 发财树 / 雕塑 / 会议桌 / 沙发）
		# 也是一个可探索点：给它头顶挂一个感叹号（id = explore 字段的值），点感叹号 →
		# 弹这条线索卡。家具模型本身**不可点**（作者上一轮明说「不要再点建模了」），
		# 搜证入口只有感叹号这一个。文案在 act1.json 的 rounds[].spots 里按这个 id 填。
		# ⚠ base_y 和小人同一套：`pos.y + 体高 30%`（第一版直接用 pos.y = 脚底 0，
		#   人台/雕塑的感叹号全贴在地上，核对图 L38 一眼就穿帮）。
		var explore_id := str(p.get("explore", ""))
		if explore_id != "":
			var icon_y := float(p.get("icon_y", pos.y + size.y * 0.30))
			_build_clue_icon(explore_id, _clue_icon_at(pos, size, icon_y))


func _build_spots() -> void:
	for s in ContentDB.spots:
		var id := str(s.get("id", ""))
		if id == "":
			continue
		# 和布景/ NPC 同一条规则：可以自己写 scale 覆盖 prop_scale。
		# ⚠ 已交付真模型的探索点（如公告栏）必须写 scale 1.0 —— 模型是照「游戏里的最终尺寸」
		#   归一化过的，再乘 0.8 就会和灰盒差一截，`_check_size` 立刻报「尺寸对不上」。
		var k := float(s.get("scale", prop_scale))
		var size := ContentDB.vec3(s.get("size"), Vector3(0.6, 0.3, 0.5)) * k
		var pos := ContentDB.vec3(s.get("pos"), Vector3.ZERO)
		var color := ContentDB.col(s.get("color"), Color("#D98C6A"))

		var slot := Models.slot_of("spot:" + id)
		var rot := float(s.get("rot", 0.0))
		# ⛔⛔ **探索点的 `size` 写的是「世界轴跨度」，不是「转过之前的跨度」** —— 这一点和
		#    `room.json` 的 props 相反（props 写转过之前的，因为 `_build_props` 没把宿主转角
		#    传给 `_add_box`；这里传了，所以两边差一次 x/z 互换）。实测口径（`scenes/_aabbprobe.tscn`）：
		#      · 公示板 `size [0.123, 1.1, 1.637]` rot −90 → **模型**在世界里的 x 跨度 = 0.123 ✓
		#      · 人事柜 `size [0.4396, 1.36, 0.8713]` rot −90 → 模型 x 跨度 = 0.4396 ✓
		#    验法：模型的正面朝 −Z、宽沿 x，`rot ±90` 之后宽就落到世界 z 上 —— 所以写进 JSON 的
		#    `size` 要按「转完」的样子写（x = 进深、z = 宽度）。
		# ⚠ 副作用（无害、但别踩）：灰盒 `BoxMesh` 是拿这个「世界轴」的 size 直接建、再被宿主转
		#    90°，于是**灰盒比模型多转了一次**，会伸进墙里（人事柜 min_x = −8.216、公示板 −8.759）。
		#    它 `collide_h = 0` **没有碰撞体**、又 `Greybox.visible = false`，所以看不见也撞不着 ——
		#    ⛔ 别让它复活成「可见」或「带碰撞」的东西，否则立刻会看到一块穿墙的板子。
		# ⛔⛔ 2026-10-06 作者：「线索中直接连接在感叹号上，不要再点建模了，搜证不是关键玩法」。
		#    所以探索点这一层**彻底退到幕后**：
		#      · `collide_h = 0` = **不要碰撞体** —— 原来 -1 会让桌面上的探索点变成
		#        半个「可点的隐形家具」，射线打下来先撞它、点哪儿都算点了那个位置；
		#      · 灰盒 `Greybox` **必须隐形** —— 它只是「挂模型用的锚点 + 记录已看过」，
		#        不是给人看的东西。它露出来的样子就是吧台台面上那个土黄色方块
		#        （作者截图里专门指出来的「穿模」那块）。有真模型的话模型会自己挂上来，
		#        灰盒留着也只是当尺寸基准。
		var body := _add_box(slot, size, ContentDB.box_center(pos, size), color, "spot", 0.0, rot)
		var grey := body.get_node_or_null("Greybox") as MeshInstance3D
		if grey != null:
			grey.visible = false
		if not is_zero_approx(rot):
			body.rotation_degrees = Vector3(0.0, rot, 0.0)
		body.set_meta("spot_id", id)
		_spot_nodes[id] = body
		# 2026-10-05 晚：不再给探索点加发光 —— 改成头顶挂感叹号（作者要求）。
		# 高度基准 = 探索点自己的 `pos.y`（玩家要看的那一层），**不是**包围盒顶面。
		# 想让某个点单独高一点/低一点，在 JSON 里写 `icon_y`（世界 y）覆盖。
		# ⛔ 2026-10-06：光叠一个 `CLUE_ICON_LIFT` 不够 —— 贴墙的物件会被插穿，
		#    位置一律走 `_clue_icon_at()`（它顺带做「离墙 / 别插进宿主」两件事）。
		var icon_y := float(s.get("icon_y", pos.y))
		_build_clue_icon(id, _clue_icon_at(pos, size, icon_y))


## 感叹号该浮在哪（返回**世界坐标的圆心**）。
##
## ⛔⛔ 2026-10-06 作者截图反馈「穿模」：只把 `CLUE_ICON_LIFT` 叠在 `pos.y` 上不够 ——
##    贴墙的两件东西，圆心**整个落在宿主包围盒里**：
##      · 公示板 `spot:bulletin` `pos=[-7.94,1.35,4.4] size=[0.123,1.1,1.637]`
##        —— 那个 1.35 是**板的下沿**不是面，圆心正插在板子里（作者截图就是这一根）；
##      · 人事柜 `spot:hr_cabinet` `pos=[-7.55,0,2.0] size=[0.6,1.7,1.8]`
##        —— 圆心也在柜体里（柜子还没挂模型所以看不出来，模型一进来必穿）。
##
## ⛔ 但**不能**改成「浮到包围盒顶面之上」—— 那条路作者已经否过一次：吧台顶 1.62、
##    柜顶 1.70 会把图标顶到 2 米往上，「飘在半空跟物件没关系了」。他要的是
##    **贴着物件招手**。所以下面推的是**水平方向**，`pos.y + LIFT` 这个
##    「玩家要看的那一层」原封不动。
##
## 感叹号是 billboard（永远正面朝相机，且绕 Y 轴转），最坏占地就是：
##    水平 ±`CLUE_ICON_H*AR/2`（≈0.259）、竖直 ±`CLUE_ICON_H/2`（=0.19）。
## 判定顺序：
##   ① 图标整个在宿主**上方**（`y_bottom >= 顶面 + PAD`）→ 只管别贴墙（桌面 / 吧台走这条，画面不变）；
##   ② 竖直跟宿主重叠 → 从水平四向里挑「推得最少、且推出去不撞墙」的一向推出去；
##   ③ 四向都推不出去（罕见）→ 兜底抬到顶面之上。
func _clue_icon_at(pos: Vector3, size: Vector3, base_y: float) -> Vector3:
	var hw := CLUE_ICON_H * CLUE_ICON_AR * 0.5 + CLUE_ICON_PAD      # 水平所需净空
	var hh := CLUE_ICON_H * 0.5
	var half := size * 0.5
	var rsize := ContentDB.vec3(ContentDB.room.get("size"), Vector3(16.0, 4.5, 12.0))
	var lim_x := maxf(0.0, rsize.x * 0.5 - hw)
	var lim_z := maxf(0.0, rsize.z * 0.5 - hw)

	var y_bottom := base_y + CLUE_ICON_LIFT
	# ① 本来就完全在宿主上方 —— 只把圆心收进「离墙还有净空」的范围里。
	var x := clampf(pos.x, -lim_x, lim_x)
	var z := clampf(pos.z, -lim_z, lim_z)
	if y_bottom < pos.y + size.y + CLUE_ICON_PAD:
		# ② 竖直重叠 → 水平让开。候选 = 四条边各往外推「半个宿主 + 净空」。
		var cands: Array[Vector2] = [Vector2(half.x + hw, 0.0), Vector2(-half.x - hw, 0.0),
				Vector2(0.0, half.z + hw), Vector2(0.0, -half.z - hw)]
		var best := INF
		for c in cands:
			var px := pos.x + c.x
			var pz := pos.z + c.y
			if absf(px) > lim_x or absf(pz) > lim_z:
				continue          # 推出去会插进墙 —— 这一向作废
			if absf(px - pos.x) < half.x + hw - 0.001 and absf(pz - pos.z) < half.z + hw - 0.001:
				continue          # 推得不够，圆心还在宿主 footprint 里
			var d := c.length()
			if d < best:
				best = d
				x = px
				z = pz
		if best == INF:
			y_bottom = pos.y + size.y + CLUE_ICON_PAD       # ③ 兜底
	return Vector3(x, y_bottom + hh, z)


# ---------------------------------------------------------------- 线索感叹号
##
## 作者 2026-10-05 晚的反馈：「不要再使用你那个发光线索定位了，建模太大太丑，
## 线索的提示和搜索都靠这个感叹号，有线索的地方会出现感叹号，点了感叹号就可以弹出线索框」。
##
## 所以：
##   · 探索点**不再发光**（那层自发光 overlay 去掉了）；
##   · 改成**每个还有线索的探索点头顶挂一个感叹号**，看过就收起来；
##   · 感叹号用 Sprite3D + billboard —— 永远正面朝相机。俯视 / 平视 / 斜角都是正的。
##
## ⛔ Sprite3D **不参与物理**，射线打不到它（这条当年导致「点感叹号没反应」）——
##    现在每个感叹号下面**另挂一个 `Area3D`（`Pick`，独占 `CLUE_PICK_LAYER`）**当拾取体，
##    见 `_build_clue_icon` 后半段。点感叹号 = **唯一**的搜证入口。
##
## ⛔ 图标**不穿模**靠两件事一起：① 用的是「黑描边 + 笔画白填充」的贴图（不透明才有遮挡）；
##    ② 圆心位置走 `_clue_icon_at()` —— 贴墙的物件（公示板 / 人事柜）会被水平推开，见那里。
##    作者 2026-10-06 的截图就是公示板那根插进了板子里。
##
## ⛔ 也不能改用「世界空间里一个面片」去贴 —— 相机是跟着玩家绕的，
##    固定朝向的牌子绕到背面就是一个纸片侧面。billboard 是唯一稳的。
const CLUE_ICON_TEX := "res://assets/textures/ui/icon_clue.png"
## 感叹号拾取体（Area3D）占的物理层。**独占一层**是为了跟玩家 / NPC / 家具分开，
## 避免「点地面走路」的射线误撞；查询那边的 mask 是全开的，所以照样打得到它。
const CLUE_PICK_LAYER := 1 << 2

## 「矛盾态」的颜色（答错时把那个物件的感叹号染成这个）。
const C_CONFLICT := Color("#8FA9C4")
## 感叹号**图片高**（米）。图标本身 542×397，宽按比例自动 ≈1.365 倍。
## ⚠ 2026-10-05 晚作者反馈「感叹号缩小」+「建模太大太丑」—— 从 0.62 收到 0.44。
## ⚠ 2026-10-06 作者再要「稍微缩小一点」→ **0.38**。0.38 米 ≈ 小人（1.30 米）的
##   三成高，浮在物件上方像个提示角标、不抢戏。
## ⛔ 缩小不影响手感：拾取体是从「物件高度 + 0.12」算的立方体（见 _build_clue_icon），
##    并不是图标本身在接射线，点起来照样宽松。
const CLUE_ICON_H := 0.38
## `icon_clue.png` 的宽高比（542×397）。感叹号的**水平半宽** = `CLUE_ICON_H * AR / 2`。
## ⛔ 自检里有判据核对它跟真贴图对得上 —— 换了图不改这里，净空就算错。
const CLUE_ICON_AR := 1.36524
## 感叹号离一切实体额外留的余量（米）。见 `_clue_icon_at`。
const CLUE_ICON_PAD := 0.06
## 图标下沿离**物件交互面**多少米。
##
## ⛔ 别拿「包围盒顶面」当**基准** —— 第一版就是那么算的：吧台顶面 1.62 米、
##    人事柜顶面 1.70 米，感叹号全被顶到 2 米往上，飘在半空跟物件没关系了。
##    作者要的是「这个位置有线索，来点点看」，**贴着物件招手**才对。
## 基准 = 探索点自己的 `pos.y`（桌面 0.6 / 吧台 1.28 / 柜子 0.0）——
## 也就是「玩家要看的那一层」，感叹号就浮在这一层往上一点。
## ⚠ 2026-10-06：顶面**只当「要不要水平让开」的判据**用（见 `_clue_icon_at`），
##   不再影响高度 —— 凡 `pos.y + LIFT` 已经高过顶面的（桌面 / 吧台），画面跟原来一模一样。
const CLUE_ICON_LIFT := 0.42
## 上下轻浮多少米 / 多少秒一个来回。静止的图标像贴纸，飘一点才「在招呼你」。
const CLUE_ICON_BOB := 0.035
const CLUE_ICON_PERIOD := 1.9

var _clue_icon_clock := 0.0


## ⛔ 高度一律用**世界 y**，并且把图标挂在 main 下（不是挂在探索点上）。
##    第一版挂在宿主（方块中心）下、用局部 half_from_center 换算，吧台那根飘到
##    天花板下面 —— 因为 host 的 pos.y 语义 + 方块中心 + 半个高，三层叠起来容易错。
##    挂 main 下、给世界坐标，`_clue_icon_at()` 算出来是什么就是什么，一眼能对。
## `at` = **图标圆心**的世界坐标（`_clue_icon_at` 已经把 lift / 让位都算完了）。
func _build_clue_icon(id: String, at: Vector3) -> void:
	if not ResourceLoader.exists(CLUE_ICON_TEX):
		return
	var tex: Texture2D = load(CLUE_ICON_TEX)
	if tex == null:
		return
	var sp := Sprite3D.new()
	sp.name = "ClueIcon_" + id
	sp.texture = tex
	# 按「图片高 = CLUE_ICON_H」定尺寸，宽跟着比例走（别写死宽，换图就变形）。
	var k := CLUE_ICON_H / float(tex.get_height())
	sp.pixel_size = k
	# `at` 已经是**圆心**的世界坐标（`_clue_icon_at` 算好的，别在这里再抬）。
	sp.position = at
	sp.set_meta("base_y", at.y)
	# 永远正面朝相机。
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.no_depth_test = false          # 还是要被墙和家具挡（不然隔墙也看得见）
	sp.render_priority = 1
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sp)

	# ---- 拾取体（2026-10-06 新增）----
	# ⛔ Sprite3D **不参与物理**，射线打不到它。所以另挂一个 Area3D 当点击目标：
	#    点感叹号 = 唯一的「搜证」入口，家具模型本身不再可点（作者要求）。
	# ⛔ 盒做成**立方体**而不是薄片：图标是 billboard、朝向随相机转，薄片从侧面
	#    点不着；立方体从任何角度看都是同一条命中线，手感才一致。
	# 挂在 sp 下面 —— 自然跟着上下轻浮一起动，不用单独同步。
	var area := Area3D.new()
	area.name = "Pick"
	area.set_meta("spot_id", id)
	area.add_to_group("clue")
	# 独占一层：只当射线目标，不跟任何东西发生物理交互（mask=0）。
	area.collision_layer = CLUE_PICK_LAYER
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var iw := CLUE_ICON_H * float(tex.get_width()) / float(tex.get_height())
	var side := maxf(iw, CLUE_ICON_H) + 0.12      # 比图标大一圈，好点
	bs.size = Vector3(side, CLUE_ICON_H + 0.12, side)
	cs.shape = bs
	area.add_child(cs)
	sp.add_child(area)

	_clue_icons[id] = sp


## 有线索 = 显示 + 可点，看过 = 收起 + 摘拾取层。一次刷新全部。
## ⛔ 还要看**这一轮用不用这个位置** —— 每轮的探索点集合可以不一样
##    （data/act1.json 的 rounds[].spots），没列进来的感叹号不该出现。
func _refresh_clue_icons() -> void:
	for id in _clue_icons:
		var in_round := not ContentDB.round_spot(round_idx, id).is_empty()
		_set_clue_pick(id, in_round and not scanned.has(id))


## ⛔ 光把图标 `visible = false` **拦不住射线** —— Godot 的物理不看可见性，
##    隐藏的 Area3D 照样会被打到（「已经看过的线索点还能点开」就是这么来的）。
##    所以收图标的时候必须把拾取层一起摘掉。
func _set_clue_pick(id: String, on: bool) -> void:
	var sp: Node3D = _clue_icons.get(id)
	if sp == null:
		return
	sp.visible = on
	var area := sp.get_node_or_null("Pick") as Area3D
	if area != null:
		area.collision_layer = CLUE_PICK_LAYER if on else 0


func _tick_clue_icons(delta: float) -> void:
	_clue_icon_clock += delta
	var dy := sin(_clue_icon_clock * TAU / CLUE_ICON_PERIOD) * CLUE_ICON_BOB
	for id in _clue_icons:
		var sp: Node3D = _clue_icons[id]
		if sp == null or not sp.visible:
			continue
		var base_y := float(sp.get_meta("base_y", 0.0))
		sp.position.y = base_y + dy


func _build_npcs() -> void:
	# ⚠ 2026-10-06：以前是「看完全部探索点 → 四个 NPC 一起发光」提示可以去找人聊。
	#   现在小人自己就是可探索点（作者要求），所以改成**每人头顶挂一个感叹号**，
	#   和家具位置同一套：有线索就亮、看过就收、进下一轮全部重亮。
	var bub_raw: Variant = ContentDB.objects.get("_bubble", {})
	_bubble_global = bub_raw if typeof(bub_raw) == TYPE_DICTIONARY else {}
	for n in ContentDB.npcs:
		var id := str(n.get("id", ""))
		if id == "":
			continue
		# 和布景同一条规则：可以自己写 scale 覆盖 prop_scale。
		# 4 个角色都是 1.30 米的真模型（作者 2026-10-05 反馈「小人有点小」，从 1.04 提上来的），
		# 所以这里写 scale: 1.0，size 直接就是实测米数 —— 再乘 0.8 就缩回 1.04 了。
		var k := float(n.get("scale", prop_scale))
		var size := ContentDB.vec3(n.get("size"), Vector3(0.5, 1.3, 0.5)) * k
		var pos := ContentDB.vec3(n.get("pos"), Vector3.ZERO)
		var color := ContentDB.col(n.get("color"), Color("#8FA9C4"))
		var body := _add_box(Models.slot_of("npc:" + id), size,
			ContentDB.box_center(pos, size), color, "npc")
		# 和布景同一条规则：rot 是绕 Y 轴转多少度，转的是宿主节点，
		# 灰盒、碰撞体、挂上来的真模型一起转。老板要靠这个面朝沙发。
		var rot := float(n.get("rot", 0.0))
		if not is_zero_approx(rot):
			body.rotation_degrees = Vector3(0.0, rot, 0.0)
		body.set_meta("npc_id", id)
		_npc_nodes[id] = body
		var idle_raw: Variant = n.get("idle")
		var idle: Dictionary = idle_raw if typeof(idle_raw) == TYPE_DICTIONARY else {}
		_npc_make_pivot(id, body, size, idle)

		# 头顶的思考框。挂在宿主上（不是枢轴上）—— 这样它不会跟着呼吸/摇晃抖，
		# 而且宿主绕 Y 转的时候它在转轴上，位置一点不动。
		var bub := _bubble_cfg(n.get("bubble"))
		if bool(bub.get("enable", true)):
			var bb: Node3D = BubbleScript.new()
			bb.configure(bub, size, id)
			body.add_child(bb)
			_npc_bubbles[id] = bb

		# ---- 小人身上的感叹号（2026-10-06 作者：「每一轮都可以点击小人获得小人身上的线索，
		#      小人也是可探索点」）----
		# 和小人**身体**一样走「有线索就挂感叹号」那一套 —— 于是点感叹号、点人本身两条路都通
		# （见 `_handle_click`），和家具位置完全同构。
		# ⚠ 位置仍走 `_clue_icon_at()`：人的 `pos.y` 是**脚底**（0），直接用它会算到脚踝那么低
		#   （截图里看着像掉在地上）。所以基准按**体高 30%** 取（1.30 米的人 → 0.39 米），
		#   图标中心 ≈ 1.0 米 = 胸口高度，像别在身上的一个提示角标。
		# ⛔ 别改成「浮到头顶之上」：头顶已经有一个思考框（`_bubble`），两个东西会叠在一起；
		#   而且人高 1.3 米，再往上就是 2 米开外、变成作者否过的「飘在半空」。
		# 想让某个人单独高一点/低一点，在 objects.json 里写 `icon_y`（世界 y）覆盖。
		var icon_y := float(n.get("icon_y", pos.y + size.y * 0.30))
		_build_clue_icon(id, _clue_icon_at(pos, size, icon_y))

	_apply_idle_lines()


## 四个小人**头顶思考框里那句话**：每轮一份，全在 data/act1.json 的 `rounds[].idle_lines`。
## 刚搭好场景调一次，**轮末刷新时还要再调一次** —— 同一批人，换了一批心事。
## ⚠ 字不在贴图上（贴图只是形状底），所以换话不用重画，改个字符串就行。
func _apply_idle_lines() -> void:
	var said := PackedStringArray()
	var missing := []
	for nid in _npc_bubbles:
		var bub: Node3D = _npc_bubbles[nid]
		if bub == null:
			continue
		var line := ContentDB.round_idle_line(round_idx, nid)
		bub.set_text(line)
		if line == "":
			missing.append(nid)
		else:
			said.append("%s「%s」" % [nid, line])
	if not missing.is_empty():
		push_warning("第 %d 轮的 idle_lines 里这几个小人没写台词：%s" % [round_idx + 1, str(missing)])
	print("[idle] 第 %d 轮头顶台词：%s" % [round_idx + 1, ", ".join(said)])


## ⚠ 2026-10-06：`_light_npcs()` / `_darken_npcs()`（把 NPC 整体点亮成「可以去找他问了」）
##    **已删除** —— 作者改成「小人也是可探索点」，提示改成**人身上的感叹号**（见 `_build_npcs`），
##    和家具同一套。凡是「谁还能点」的显示，一律由 `_refresh_clue_icons()` 统一管。


# ------------------------------------------------------- NPC 待机动作与互动
##
## 作者交来的 4 个角色都是**单张静态网格**：一个节点、一个 mesh、**没有骨骼、没有蒙皮**
## （glb_info 里就是「节点 1 / 网格 1」）。所以这里播不了骨骼动画，改用
## 「骨架之外的程序化表演」让它活起来 —— 全部在代码里算，不依赖任何美术资产：
##
##   · 呼吸    —— 以**脚底为轴**的上下浮动 + 极轻微的压扁/拉长（squash & stretch）
##   · 站姿    —— 绕脚底前后左右各晃 1~2°，两条不同频率的正弦叠加，不像机器在摆
##   · 偶尔动  —— 一条很慢的波，只在峰值附近给一个小幅度的「换重心 / 抬头」
##   · 看你    —— 你走近 3.6 米以内，它会慢慢把头转过来对着你
##   · 被点    —— 点它会「一顿」（点头 + 弹一下），然后回到待机
##
## 每个人的相位、频率、幅度都按 id 派生 —— 同一个人每次进游戏表现一致，
## 不同的人互不相同，不会像三胞胎同步做操。老板额外**放慢减幅**：他陷在沙发里休息，
## 用 1.04 米小人那种轻快节奏会显得很出戏。
##
## ⚠ 整套动作都作用在「脚底枢轴」上（见 `_npc_make_pivot`），
## 所以摇晃看起来是「以脚为轴晃身体」，不是「以腰为轴转」。碰撞体一点不动 ——
## 那是 StaticBody3D 的固有形状，动画只碰视觉。

const NPC_LOOK_RANGE := 2.4     # 多近才转头看你
const NPC_LOOK_NEAR := 0.9      # 到这个距离才转满 —— 中间是渐入，不是「一进圈就猛转」
const NPC_LOOK_SPEED := 1.1     # 转头速度（低 = 慢半拍，不吓人）
const NPC_LOOK_MAX := 150.0     # 最多转多少度
const NPC_REACT_TIME := 0.55    # 被点之后「一顿」持续多久

## 头顶的思考框。形状参数全在 data/objects.json 的 `_bubble` 里，这里只管挂上去。
const BubbleScript := preload("res://scripts/thought_bubble.gd")

var _npc_pivot := {}            # npc_id -> Node3D  脚底枢轴
var _npc_style := {}            # npc_id -> Dictionary  这个人专属的相位与幅度
var _npc_look := {}             # npc_id -> float   当前转头的角度（弧度，相对宿主）
var _npc_react := {}            # npc_id -> float   被点的余韵，1 → 0
var _npc_bubbles := {}          # npc_id -> Node3D  头顶的思考框
var _bubble_global := {}        # objects.json 的 `_bubble`：所有人的默认值
var _npc_clock := 0.0


## 给一个 NPC 挂上「脚底枢轴」，并把全部视觉（灰盒 / 真模型）挪进去。
## 之后所有动作只动这个枢轴：转它 = 整个人绕脚底晃，缩它 = 从脚往上涨。
##
## idle 是 objects.json 里这个人的可选覆盖项，两项都是**乘在默认值上的系数**：
##   speed  —— 整体快慢（呼吸/摇晃/小动作的频率）
##   amount —— 整体幅度（起伏多高、晃多少度）
## 0 就是完全定住。老板写的是 {speed: 0.5, amount: 0.4} —— 他陷在沙发里休息，
## 用 1.04 米小人那种轻快节奏会显得很出戏。
func _npc_make_pivot(id: String, body: StaticBody3D, size: Vector3, idle: Dictionary) -> void:
	var pivot := Node3D.new()
	pivot.name = "Anim"
	pivot.position = Vector3(0.0, -size.y * 0.5, 0.0)   # 枢轴落在鞋底
	body.add_child(pivot)
	for c in body.get_children():
		if c == pivot:
			continue
		if c is MeshInstance3D or c.name == "Model":
			c.reparent(pivot, true)     # 保持世界变换，画面不会跳一下

	# 用 id 派生一套「个人参数」。同一个 id 永远得到同一套，不同的人互不相同。
	#
	# ⚠ 关于「飘」：这套动作**只能动「脚底枢轴」**。枢轴在鞋底，缩放是从脚往上涨，
	#   所以呼吸只用 scale、不用 position.y —— 一旦给 position.y 加减，
	#   整只脚就会离地，看着就像气球飘起来了（作者 2026-10-05 反馈）。
	#   唯一允许的纵向位移是「往下沉一点点」（体重感），沉多少都不会离地。
	var h := float(abs(hash(id)) % 977) / 977.0
	var sp := float(idle.get("speed", 1.0))
	var am := float(idle.get("amount", 1.0))
	_npc_pivot[id] = pivot
	_npc_style[id] = {
		"base_y": -size.y * 0.5,
		"ph": h * TAU,                                  # 相位：错开，免得同步
		"sink": 0.005 * am,                             # 只往下沉的体重感（米），永不离地
		"breath": 0.008 * am,                           # 压扁/拉长幅度（从脚往上，脚不动）
		"hz_breath": 0.30 * sp,                         # 呼吸频率（Hz）—— 成人静息约 0.25
		"hz_sway": (0.14 + h * 0.05) * sp,              # 左右摇晃频率
		"deg_sway": 1.1 * am,
		"hz_lean": (0.11 + h * 0.04) * sp,              # 前后倾频率
		"deg_lean": 0.8 * am,
		"deg_fidget": 3.0 * am,                         # 偶尔动一下的幅度
		"hz_fidget": (0.055 + h * 0.02) * sp,           # 约 20 秒来一次
	}
	_npc_look[id] = 0.0
	_npc_react[id] = 0.0


## 把 objects.json 的 `_bubble` 和这一条自己的 `bubble` 拼起来（后者覆盖前者）。
func _bubble_cfg(local_raw: Variant) -> Dictionary:
	var cfg: Dictionary = _bubble_global.duplicate()
	if typeof(local_raw) == TYPE_DICTIONARY:
		for k in (local_raw as Dictionary):
			cfg[k] = (local_raw as Dictionary)[k]
	return cfg


## NPC 动画总调度。放在 _process 里是为了跟渲染帧对齐 —— 呼吸靠物理帧会一顿一顿。
func _tick_npcs(delta: float) -> void:
	if _npc_pivot.is_empty():
		return
	_npc_clock += delta
	var t := _npc_clock
	for id in _npc_pivot:
		var pivot: Node3D = _npc_pivot[id]
		var st: Dictionary = _npc_style[id]
		if not is_instance_valid(pivot):
			continue
		var ph := float(st["ph"])

		# --- 呼吸：一根正弦同时管「长高」和「胖瘦」，两者反相（涨上去就瘦，沉下来就胖）。
		#     全部作用在枢轴的 scale 上 —— 枢轴在鞋底，所以**脚底一点不动**，
		#     只有头顶在动。position.y 只允许往下沉（体重感），永远不离地。
		var br := sin(t * float(st["hz_breath"]) * TAU + ph)
		var f := float(st["breath"]) * br
		pivot.scale = Vector3(1.0 - f * 0.5, 1.0 + f, 1.0 - f * 0.5)
		pivot.position.y = float(st["base_y"]) - float(st["sink"]) * (0.5 - 0.5 * br)

		# --- 站姿：两条不同频率的正弦，一个管左右一个管前后 ---
		var sway := sin(t * float(st["hz_sway"]) * TAU + ph * 1.7)
		var lean := sin(t * float(st["hz_lean"]) * TAU + ph * 2.3)

		# --- 偶尔动一下：慢波的 14 次幂，绝大部分时间 ≈ 0，峰值附近才突起 ---
		var fidget := pow(maxf(0.0, sin(t * float(st["hz_fidget"]) * TAU + ph * 5.1)), 14.0)

		var rx := deg_to_rad(float(st["deg_lean"])) * lean
		var rz := deg_to_rad(float(st["deg_sway"])) * sway
		rx += deg_to_rad(float(st["deg_fidget"])) * fidget

		# --- 看你：走近就把头转过来。朝玩家 = 让模型的 -Z 指向你 ---
		# 距离算一次，转头和思考框共用。
		var host: Node3D = _npc_nodes[id]
		var dist := INF
		var to_p := Vector3.ZERO
		if player != null:
			to_p = player.global_position - host.global_position
			to_p.y = 0.0
			dist = to_p.length()
		var want_look := 0.0
		if dist < NPC_LOOK_RANGE and dist > 0.05:
			# 渐入：远的那一半几乎不转，走近了才给满。
			# 以前是一进圈就直接怼到 120°，整个人瞬间拧过去 —— 看着像飘。
			var k := clampf((NPC_LOOK_RANGE - dist) / maxf(0.01, NPC_LOOK_RANGE - NPC_LOOK_NEAR), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			# 宿主已经转过 rot，所以先算世界朝向，再减掉宿主的偏航。
			var world := atan2(-to_p.x, -to_p.z)
			want_look = wrapf(world - host.global_rotation.y, -PI, PI)
			want_look = clampf(want_look, -deg_to_rad(NPC_LOOK_MAX), deg_to_rad(NPC_LOOK_MAX)) * k
		var look: float = _npc_look[id]
		look = lerp_angle(look, want_look, 1.0 - exp(-NPC_LOOK_SPEED * delta))
		_npc_look[id] = look
		# 转头时叠一点零碎的小动作，静止转头看起来像在滑轨上
		var look_y := look + deg_to_rad(1.6) * sin(t * 1.3 + ph * 3.1)

		# --- 被点之后「一顿」：sin 的一次突起，0 → 1 → 0 ---
		var r: float = _npc_react[id]
		if r > 0.0:
			r = maxf(0.0, r - delta / NPC_REACT_TIME)
			_npc_react[id] = r
			var hit := sin(r * PI)
			rx += deg_to_rad(10.0) * hit            # 点头
			pivot.position.y -= 0.010 * hit         # 往下一沉（不是往上弹 —— 往上就离地了）
			pivot.scale = Vector3(1.0 + 0.05 * hit, 1.0 - 0.06 * hit, 1.0 + 0.05 * hit)
			look_y += deg_to_rad(6.0) * hit

		pivot.rotation = Vector3(rx, look_y, rz)

		# --- 头顶的思考框：走近弹出来，走开收回去 ---
		var bb: Node3D = _npc_bubbles.get(id, null)
		if bb != null:
			bb.set_distance(dist)


## 被点 / 说话时叫一下：让这个人「一顿」。
func _npc_nudge(id: String) -> void:
	if _npc_react.has(id):
		_npc_react[id] = 1.0


## 主角是「一件神器 / 一支笔」，第一人称下你根本看不到自己 ——
## 所以**一个可见网格都不做**，只留一个胶囊碰撞体（走路、贴墙、相机跟随全靠它）。
## 也没有对应的模型槽位：模型对照表里找不到主角这一行。低头看脚下也只会看到地板。
func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = ContentDB.vec3(ContentDB.room.get("spawn"), Vector3(-6.8, 0.0, -1.5))
	player.name = "Player"

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.05
	cs.shape = cap
	cs.position = Vector3(0.0, 0.525, 0.0)
	player.add_child(cs)

	add_child(player)


func _build_marker() -> void:
	marker = MeshInstance3D.new()
	var slot := Models.slot_of("builtin:Marker")
	marker.name = slot if slot != "" else "TargetMarker"
	marker.set_meta("slot", slot)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.02
	cm.radial_segments = 24
	marker.mesh = cm
	var m := _make_material(Color("#D98C6A"))
	m.albedo_color.a = 0.7
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = m
	marker.visible = false
	add_child(marker)

	if slot != "":
		Models.attach(marker, slot, Vector3(0.6, 0.02, 0.6), marker, 0.0)


## 悬浮记录仪。相机不是玩家的子节点：位置每帧从玩家同步，
## 朝向只由 yaw / pitch 决定 —— 走动不会连带扭视角，转头也不会连带挪位置。
func _build_camera(cfg: Dictionary) -> void:
	eye_height = float(cfg.get("eye_height", 3.0))
	mouse_sens = float(cfg.get("mouse_sens", 0.13))
	pitch_min = float(cfg.get("pitch_min", -80.0))
	pitch_max = float(cfg.get("pitch_max", 22.0))
	yaw = float(cfg.get("yaw", -90.0))
	pitch = float(cfg.get("pitch", -34.0))

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(cfg.get("fov", 55.0))
	camera.near = 0.05
	camera.far = 160.0
	add_child(camera)
	camera.current = true
	_sync_camera()


# ---------------------------------------------------------------- 输入与移动

## `layer_mask`：非 0 时**只打这个物理层**（只看感叹号层时传 `CLUE_PICK_LAYER`）。
## 图标背后常压着家具 / 墙 / 小人自己，按「最近命中」会被它们截胡 ——「看得到、点不着」。
func _ray_at(screen_pos: Vector2, layer_mask: int = 0) -> Dictionary:
	if camera == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 500.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# 感叹号的拾取体是 Area3D（Sprite3D 不参与物理），所以**必须收 Area**。
	q.collide_with_areas = true
	q.collide_with_bodies = true
	if layer_mask != 0:
		# 只看那一层：实体（家具 / 墙 / 人）不再截胡，所以只扫 Area。
		q.collision_mask = layer_mask
		q.collide_with_bodies = false
	# 把玩家自己排除掉 —— 相机就在玩家正上方，视角压得很低时射线会先打中自己的碰撞体。
	if player != null:
		q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _handle_click(screen_pos: Vector2) -> void:
	# ⭐⭐ 2026-10-06 夜作者实测「部长的感叹号点不了」：他的图标被水平推开到沙发角落上方，
	#    视线里**先撞上沙发 / 他自己**，按「最近命中」永远轮不到感叹号。
	#    → 先**只打感叹号那一层**：只要射线经过图标（哪怕背后压着东西），命中的就是它。
	var clue_hit := _ray_at(screen_pos, CLUE_PICK_LAYER)
	if not clue_hit.is_empty():
		var cn: Object = clue_hit.get("collider")
		if cn is Node3D and (cn as Node3D).is_in_group("clue"):
			_open_spot(str((cn as Node3D).get_meta("spot_id", "")))
			return
	var hit := _ray_at(screen_pos)
	if hit.is_empty():
		return
	var body: Object = hit.get("collider")
	if body == null or not (body is Node3D):
		return
	var node := body as Node3D

	if node.is_in_group("floor"):
		pending_spot = ""
		_walk_to(hit.get("position", Vector3.ZERO))
	elif node.is_in_group("clue"):
		# 2026-10-06 作者：「线索直接连接在感叹号上，不要再点建模了，搜证不是关键玩法」。
		# 点感叹号 = **直接弹线索框**，不走过去。探索点的碰撞体已经撤掉（见 _build_spots），
		# 所以「点家具开线索」这条老路彻底不存在了。
		_open_spot(str(node.get_meta("spot_id", "")))
	elif node.is_in_group("spot"):
		_click_spot(str(node.get_meta("spot_id", "")), node)
	elif node.is_in_group("npc"):
		# 2026-10-06 作者：「每一轮都可以点击小人获得小人身上的线索，小人也是可探索点」。
		# 所以点人和点家具**同一条路** —— 直接弹他这一轮的那张线索卡（不再「走过去说话」，
		# 也不再靠说话触发判断题；题目在本轮看完之后自动弹）。
		_open_npc(str(node.get_meta("npc_id", "")))


func _walk_to(p: Vector3) -> void:
	target_pos = Vector3(p.x, 0.0, p.z)
	has_target = true
	_last_dist = INF
	_stuck_time = 0.0
	marker.global_position = Vector3(p.x, 0.03, p.z)
	marker.visible = true


## 停在目标前面一点，别把目标点设在桌子里面 —— 否则角色会一直顶着桌子走不到。
func _approach_point(target: Vector3) -> Vector3:
	var p := player.global_position
	var flat := Vector3(target.x - p.x, 0.0, target.z - p.z)
	if flat.length() < 0.01:
		return target
	var ap := Vector3(target.x, 0.0, target.z) - flat.normalized() * 0.9
	var m := 0.9
	ap.x = clampf(ap.x, -room_size.x * 0.5 + m, room_size.x * 0.5 - m)
	ap.z = clampf(ap.z, -room_size.z * 0.5 + m, room_size.z * 0.5 - m)
	return ap


## NPC 的待机动作走 _process（跟渲染帧对齐），走路/相机走 _physics_process（跟物理帧对齐）。
## 混在一起的话，呼吸会跟着物理帧一顿一顿 —— 60Hz 的物理帧和显示刷新率对不上就会抖。
func _process(delta: float) -> void:
	_tick_npcs(delta)
	_tick_clue_icons(delta)


func _physics_process(delta: float) -> void:
	if player != null:
		_step_player(delta)
	_sync_camera()


func _step_player(delta: float) -> void:
	# 键盘优先：一按 WASD 就取消当前的点地目标。
	var manual := _manual_move()
	if manual != Vector3.ZERO:
		has_target = false
		pending_spot = ""
		marker.visible = false
		player.velocity = manual * WALK_SPEED
		player.move_and_slide()
		return

	if not has_target:
		player.velocity = Vector3.ZERO
		player.move_and_slide()
		return

	var to := target_pos - player.global_position
	to.y = 0.0
	var dist := to.length()

	# 到了，或者被家具顶住 0.6 秒走不动了 —— 两种都算到。
	if dist <= ARRIVE_EPS or (dist > _last_dist - 0.008 and _stuck_time > 0.6):
		_finish_walk()
		return
	if dist > _last_dist - 0.008:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_dist = dist

	player.velocity = to.normalized() * WALK_SPEED
	player.move_and_slide()


func _finish_walk() -> void:
	has_target = false
	_stuck_time = 0.0
	_last_dist = INF
	player.velocity = Vector3.ZERO
	player.move_and_slide()
	marker.visible = false
	if pending_spot != "":
		var id := pending_spot
		pending_spot = ""
		_open_spot(id)


# ---------------------------------------------------------------- 探索

func _click_spot(id: String, node: Node3D) -> void:
	if id == "":
		return
	if player.global_position.distance_to(node.global_position) <= INTERACT_RANGE:
		_open_spot(id)
	else:
		pending_spot = id
		_walk_to(_approach_point(node.global_position))
		hud.set_hint("走过去看看……")


## 点感叹号（或直接点小人）→ 弹这张纸卡。
## ⛔ 文案取的是**当前轮**的（`round_spot`），不是 objects.json 里的 ——
##    同一个位置每轮换一套内容，这就是「轮末线索刷新」。
## ⭐ 2026-10-06 起：**看完一处就把它的 `clue`（结论）记进右边「已记下的东西」** ——
##    纸卡上那句「记到右边了」以前是空头支票，右栏其实什么都没记（作者反馈「你探索完之后
##    没有记录结论在右面」）。
func _open_spot(id: String) -> void:
	var s := ContentDB.round_spot(round_idx, id)
	if s.is_empty():
		return
	var already := scanned.has(id)
	hud.show_card(str(s.get("name", "")), s.get("lines", []), already)
	if already:
		return

	scanned[id] = true
	_douse(id)
	var c := str(s.get("clue", ""))
	if c.strip_edges() != "":
		# 回顾用：先把"这一轮找到过这个点"记一笔（与下面的文本去重**无关** ——
		# 回顾是按轮次翻的，同一句话在两轮出现也该各记各的）。
		_note_found(round_idx, id)
		if not clues.has(c):
			clues.append(c)
			hud.set_journal(story, clues)
	_refresh_progress()
	_refresh_hint()


## 点小人 = 点他的线索。走的是 `_open_spot` 同一条路（小人也是可探索点）。
## 本轮没把这个人列进探索点（作者把这一行留空了）时给一句他的待机台词，
## 免得「点了没反应」—— 点了没反应才是真的僵硬。
func _open_npc(npc_id: String) -> void:
	if npc_id == "":
		return
	_npc_nudge(npc_id)
	if ContentDB.round_spot(round_idx, npc_id).is_empty():
		var npc := ContentDB.get_npc(npc_id)
		hud.show_dialog(str(npc.get("idle_line", "他摇了摇头。")))
		return
	_open_spot(npc_id)


# ---------------------------------------------------------------- 轮次状态机
##
## 一轮 = 「看完本轮全部可探索点（家具 + 小人）→ **自动**一道一道弹本轮的判断题 → 轮末过场」。
## 轮末过场之后线索刷新：`scanned` 清空、感叹号全部回来、文案换成 act1.json 的下一套。
## 几何（探索点位置 / 大小 / 模型）从头到尾只有一份，切轮次不重建场景。
##
## 探索点集合**每轮可以不同** —— `_round_ids()` 只认本轮列出来的那些（`act1.json` 的
## `rounds[].spots`，作者把某一行留空就是这一轮不用它），别的位置的感叹号会藏起来
## （见 `_refresh_clue_icons`）。
##
## ⭐ 2026-10-06 作者的改动：
##   · **小人也是可探索点**（点人 = 弹他的线索卡，和点家具同构）；
##   · **看完就自动出题** —— 不再需要「走过去跟谁说话」才出题。链条只有一条：
##     关掉最后一张线索卡（`modal_closed`）→ `_on_modal_closed()` → 出下一道题 /
##     轮末过场。⛔ 所以出题的**唯一入口**是这里，别再在别处弹 `show_question`。

## 本轮实际用到的探索点 id。
func _round_ids() -> Array[String]:
	return ContentDB.round_spot_ids(round_idx)


## 本轮的探索点都看完了吗。
## ⚠ **本轮一个可探索点都没列**（作者把这一轮整轮留空）也算「看完了」——
##   不然 `_round_done()` 永远是 false，这一轮就再也走不到判断题、直接卡死。
func _round_done() -> bool:
	var ids := _round_ids()
	if ids.is_empty():
		return true
	return scanned.size() >= ids.size()


## 本轮已答的题数。
func _round_answered() -> int:
	var n := 0
	for q in ContentDB.round_questions(round_idx):
		if answered.has(str(q.get("id", ""))):
			n += 1
	return n


## 本轮的题都答完了吗。
func _round_q_done() -> bool:
	var qs := ContentDB.round_questions(round_idx)
	return qs.size() > 0 and _round_answered() >= qs.size()


## 顶部进度条：第一幕 · 第 2/3 轮 · 已调查 3/6。
func _refresh_progress() -> void:
	var ids := _round_ids()
	hud.set_progress_round(str(ContentDB.act.get("act", "设计部")),
		round_idx + 1, maxi(1, ContentDB.round_count()), scanned.size(), ids.size())


func _refresh_hint() -> void:
	if not _round_done():
		hud.set_hint("第 %d 轮　·　点感叹号看线索（也可以直接点人）（%d/%d）"
			% [round_idx + 1, scanned.size(), _round_ids().size()])
	elif not _round_q_done():
		hud.set_hint("这一轮看完了 —— 该下判断了。")
	else:
		hud.set_hint("按住鼠标拖动看四周　·　点地面走过去")


## 本轮题都答完 → 弹轮末过场。最后一句之后接「下一轮」或「收幕」。
## `_round_end_shown` 是防重入闸：出题链条上任何一次 `modal_closed` 都可能落到这里
## （比如玩家又点了一遍已经看过的位置），没有它轮末卡会一遍遍弹。
func _show_round_end() -> void:
	if _round_end_shown:
		return
	_round_end_shown = true
	var e := ContentDB.round_end(round_idx)
	var has_next := round_idx + 1 < ContentDB.round_count()
	hud.show_round_end(round_idx + 1, maxi(1, ContentDB.round_count()),
		str(e.get("title", "第 %d 轮 · 结束" % (round_idx + 1))),
		e.get("lines", []), has_next)


## 轮末过场点了按钮：还有下一轮就推进 + 刷新线索，否则收幕。
##
## ⛔⛔ 2026-10-06 夜作者实测「第一轮转第二轮卡住、能直接跳过后两轮」：
##    第一版这里**只推轮次、没关纸卡**（`hud.show_round_end` 的按钮也没关），
##    于是按下之后轮次悄悄 +1、纸卡却原样停着，再按一下又 +1 —— 连按三次直接收幕。
##    修法：**推进之前先把纸卡关掉**（放在这里而不是只放在按钮里，因为
##    `advance_requested` 的任何调用方都该看到「卡没了」这个结果），
##    并且 `hud.show_round_end` 的按钮自己也关一次（双保险，见那里的注释）。
func _on_advance() -> void:
	if hud != null:
		hud.close_modal()
	if round_idx + 1 >= ContentDB.round_count():
		hud.show_act_end(story, clues)
		return
	round_idx += 1
	scanned.clear()               # ← 线索刷新：所有感叹号（含小人身上的）重新亮起来
	_round_end_shown = false
	_refresh_clue_icons()
	_apply_idle_lines()           # ← 头顶思考框里那句话也跟着换（每轮一份）
	_refresh_progress()
	_refresh_hint()
	# ⚠ 这一轮要是**一个可探索点都没列**（作者把整轮留空），就没有「关掉纸卡」这个动作
	#   来启动出题链条 —— 会卡在「什么都没有」的画面里。这里补一脚。
	if _round_ids().is_empty():
		_on_modal_closed()


func _douse(id: String) -> void:
	# 「看过了」= 收感叹号 + 摘掉它的拾取层（见 _set_clue_pick 的注释）。
	_set_clue_pick(id, false)


## 答错时给那个物件打个「矛盾」标记。
##
## ⚠ 2026-10-06 改：探索点的灰盒已经**隐形**了（见 _build_spots），
##   所以标记只能打在**感叹号**上 —— 把图标染成冷蓝，跟「还有线索」的
##   黑白图标区分开，一眼看出「这里答错过」。有真模型的物件同时压一层冷光。
func _mark_conflict(id: String) -> void:
	if id == "":
		return
	var sp := _clue_icons.get(id) as Sprite3D
	if sp != null:
		sp.modulate = C_CONFLICT
	_set_glow(_spot_nodes.get(id), true, C_CONFLICT)


# ---------------------------------------------------------------- 判定
##
## ⛔⛔ 2026-10-06 作者：「我希望每一轮探索后直接弹出判断题，而不是还要和小人交流」。
##    所以「找谁问」这条入口**整条删掉**了（原来的 `_talk_to` / `_next_question`）——
##    出题只有一个入口：`_on_modal_closed()`（关掉一张会 fire 的纸卡之后）。
##    链条：看完最后一处 → 纸卡「知道了」→ `modal_closed` → 出第 1 题 →
##    答完 → 反馈卡「继续」→ `modal_closed` → 出下一题 …… → 轮末过场。

## 下一道该问的题（本轮、还没答、题干填全了的）。
##
## ⚠ 三条兜底，一条都不能少：
##   · 选项为空的题**跳过** —— 作者还没填完的题不该把流程卡死在这里；
##   · `requires` 满足的优先；
##   · 前置怎么都满足不了（比如它要的那题被删了）→ 也照问，别让三轮走不下去。
func _next_round_question() -> Dictionary:
	var pending: Array[Dictionary] = []
	for q in ContentDB.round_questions(round_idx):
		var qid := str(q.get("id", ""))
		if qid == "" or answered.has(qid):
			continue
		var opts: Variant = q.get("options", [])
		if typeof(opts) != TYPE_ARRAY or (opts as Array).is_empty():
			continue
		pending.append(q)
	if pending.is_empty():
		return {}
	for q in pending:
		if _prereq_ok(q):
			return q
	return pending[0]


func _prereq_ok(q: Dictionary) -> bool:
	var need: Variant = q.get("requires", [])
	if typeof(need) != TYPE_ARRAY:
		return true
	for r in need:
		if not answered.has(str(r)):
			return false
	return true


func _on_option_chosen(qid: String, index: int) -> void:
	var q := ContentDB.round_question(round_idx, qid)
	if q.is_empty() or answered.has(qid):
		return
	var opts: Variant = q.get("options", [])
	if typeof(opts) != TYPE_ARRAY or index < 0 or index >= opts.size():
		return
	var opt: Dictionary = opts[index]
	var correct := bool(opt.get("correct", false))
	answered[qid] = correct
	# 回顾用：记下当时选了哪一项（题干 / 文案都还能从 ContentDB 现取，存选择就够）。
	answer_log[qid] = {
		"round": round_idx,
		"chosen": str(opt.get("text", "")),
		"correct": correct,
	}

	if correct:
		var t := str(q.get("on_correct", ""))
		if t != "":
			story.append(t)
	else:
		var t2 := str(q.get("on_wrong", ""))
		if t2 != "":
			clues.append(t2)
		if MARK_CONFLICT_SPOT:
			_mark_conflict(str(q.get("target", "")))

	hud.set_journal(story, clues)
	hud.show_feedback(q, correct, str(opt.get("text", "")))


# ---------------------------------------------------------------- 回顾（只读回看）
## 2026-10-14 作者要求：右上角「回顾 ▼」→ 选轮次看结论 / 选判断题看当时的选择。
## ⛔ 这一整段都是**只读**：不推进轮次、不改 scanned / answered / clues / story。
## ⛔ 没玩到的轮次不开入口（作者：「没玩到那关的线索回溯不能点击」）。

## 某一轮拿到过结论就记一笔（只存 id —— 原文按那一轮现取）。
func _note_found(round_i: int, id: String) -> void:
	var arr: Array = found_by_round.get(round_i, [])
	if not arr.has(id):
		arr.append(id)
	found_by_round[round_i] = arr


## 下拉菜单的模型：每一轮到没到、已记几条；判断题答过没有。
func _review_menu_model() -> Dictionary:
	var total := ContentDB.round_count()
	var rounds: Array = []
	for r in range(total):
		var f: Array = found_by_round.get(r, [])
		rounds.append({
			"no": r + 1,
			"reached": r <= round_idx,
			"found": f.size(),
		})
	var answered_n := 0
	for r in range(mini(round_idx + 1, total)):
		for q in ContentDB.round_questions(r):
			if answer_log.has(str(q.get("id", ""))):
				answered_n += 1
	return {
		"rounds": rounds,
		"questions": {"reached": answered_n > 0, "answered": answered_n},
	}


func _on_review_requested(kind: String, index: int) -> void:
	if kind == "round":
		_review_round(index)
	elif kind == "questions":
		_review_questions()


## 第 r 轮的结论列表（只列**已经找到**的 —— 没找到的不给看，也不占位）。
## ⛔ 原文必须用 `round_spot(r, id)`，**不是**当前的 `round_idx`：
##    同一个 id 每轮的 name / lines / clue 都不同，取错轮就等于给玩家看错内容。
func _review_round(r: int) -> void:
	var entries: Array = []
	var ids: Array = found_by_round.get(r, [])
	for id in ids:
		var s := ContentDB.round_spot(r, str(id))
		if s.is_empty():
			continue
		entries.append({
			"spot": str(id),
			"name": str(s.get("name", "")),
			"lines": s.get("lines", []),
			"clue": str(s.get("clue", "")),
		})
	hud.show_review_round(r + 1, entries)


## 判断题列表。编号按全幕内容顺序（第 1 轮 1~3 → 第 2 轮 4~6 → 第 3 轮 7~10）；
## 只列**已经答过**的题，没答的不出现。
func _review_questions() -> void:
	var entries: Array = []
	var n := 0
	for r in range(ContentDB.round_count()):
		for q in ContentDB.round_questions(r):
			n += 1
			var qid := str(q.get("id", ""))
			var rec: Variant = answer_log.get(qid, null)
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = rec
			entries.append({
				"no": n,
				"round": r + 1,
				"prompt": str(q.get("prompt", "")),
				"chosen": str(d.get("chosen", "")),
				"correct": bool(d.get("correct", false)),
				"on_correct": str(q.get("on_correct", "")),
				"on_wrong": str(q.get("on_wrong", "")),
			})
	hud.show_review_questions(entries)


## 关掉一张「会 fire」的纸卡之后 —— 现在这是**唯一**的流程推进入口：
##   线索卡关掉 → 本轮看完了吗？没看完 → 什么都不做；
##                 看完了 → 出下一道题；题目出完了 → 轮末过场。
## 判断题反馈卡关掉 → 同样落到这里 → 接下一道 / 轮末。
##
## ⛔ 所以 `show_card` 必须 `fire = true`（不然看完最后一个位置之后链条断在纸卡上，
##    玩家再也等不到那道题）。「有人跟你说话」那张仍是 `fire = false`：它只是台词，
##    不该去推流程。
func _on_modal_closed() -> void:
	if not _round_done():
		return
	if _round_q_done():
		_show_round_end()
		return
	var q := _next_round_question()
	if q.is_empty():
		_show_round_end()          # 题目都出完了（含「作者还没填」被跳过的）→ 直接收这一轮
		return
	hud.show_question(q)


func _on_restart() -> void:
	# 外面有入口壳（app.gd）时，重开的是**本幕** —— 不要退回标题页。
	# 用 has_method 探测，所以直接 load main.tscn 跑地图（自检 / 截图）时也不受影响。
	var shell := get_parent()
	if shell != null and shell.has_method("restart_act"):
		shell.restart_act()
	else:
		get_tree().reload_current_scene()
