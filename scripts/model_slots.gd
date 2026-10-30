extends Node
## 模型槽位管理器 —— 灰盒方块 ⇄ 真模型 的自动替换
##
## 约定只有一条：
##   把模型导出成 assets/models/<模型名>.glb，重启游戏就自动替换。
##   没有文件就继续用灰盒方块，不报错、不阻塞。
##
## 关键：**一个模型可以顶多个位置**。
##   6 张工位桌、12 把椅子、7 扇窗，各只需要做一份模型 ——
##   哪个槽位用哪个模型，写在 model_map.json 的 model 字段里（不写就是同名）。
##   所以「要做的模型数」比「位置数」少得多，report() 会把两个数都报出来。
##
## 槽位名规则：SM_<Zone>_<Name>[_<Variant>]，Zone = B 建筑 / F 家具 / J 可交互 / A 角色 / FX 特效。
##
## 模型规范：
##   原点在底面中心，米制，Y-up，朝向 -Z，Metallic 0 / Roughness 0.85，不做法线与 ORM。

const MAP_PATH := "res://data/model_map.json"
const MODEL_DIR := "res://assets/models"

## 想看灰盒长相时把它改成 true —— 所有真模型都会让位，方便对比。
const FORCE_GREYBOX := false

var entries: Array[Dictionary] = []      # 按 model_map.json 顺序
var by_slot := {}                        # slot -> entry
var by_bind := {}                        # bind -> slot

var used: Array[String] = []             # 用了真模型的槽位（位置）
var used_models := {}                    # 用了真模型的模型名（去重）
var grey: Array[String] = []             # 还是灰盒的槽位
var _warnings: Array[String] = []


func _ready() -> void:
	_load_map()


func _load_map() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		push_error("[模型槽位] 找不到 " + MAP_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[模型槽位] " + MAP_PATH + " 解析失败")
		return
	var raw: Variant = (parsed as Dictionary).get("slots", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for it in raw:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = it
		var slot := str(e.get("slot", ""))
		if slot == "":
			continue
		entries.append(e)
		by_slot[slot] = e
		var b := str(e.get("bind", ""))
		if b != "":
			by_bind[b] = slot


## "prop:Desk_1" -> "SM_F_Desk_01"（查不到就返回空串，表示这东西没有槽位）
func slot_of(bind_key: String) -> String:
	return str(by_bind.get(bind_key, ""))


func entry(slot: String) -> Dictionary:
	return by_slot.get(slot, {})


## 这个槽位用哪个模型文件。model_map.json 里没写 model 字段就是同名。
func model_of(slot: String) -> String:
	var m := str(entry(slot).get("model", ""))
	return m if m != "" else slot


## 槽位自带的「绕 Y 转多少度」——**只管真模型**。
## 为什么需要它：模型按约定归一化时朝向是固定的（正面 -Z、宽沿 x），
## 但同一个模型顶到不同位置时，宽可能得顺着墙走（沿 z）。与其为了一个位置
## 回去重跑流水线改 yaw、把其它位置一起带坏，不如在槽位这里写一句 rot。
## ⚠ 灰盒方块的 size 是**转之前**的尺寸 —— 转完 x/z 跨度互换是正常的，
##   所以 `_check_size` 要先把预期尺寸跟着转一下再比（见 _expected_in_host）。
func slot_rot(slot: String) -> float:
	return float(entry(slot).get("rot", 0.0))


## 模型名 -> 用到它的槽位列表。一天做三个模型的节奏全靠这张表算出来。
func models_index() -> Dictionary:
	var out := {}
	for e in entries:
		var s := str(e.get("slot", ""))
		if s == "":
			continue
		var m := model_of(s)
		if not out.has(m):
			out[m] = []
		(out[m] as Array).append(s)
	return out


## 一共要做几个模型（去重后）。
func model_count() -> int:
	return models_index().size()


func cn_name(slot: String) -> String:
	var e := entry(slot)
	return str(e.get("cn", slot))


func tri_budget(slot: String) -> int:
	return int(entry(slot).get("tri", 0))


## 找真模型：assets/models/<模型名>.glb / .gltf / .tscn / .scn，找到就实例化，找不到返回 null。
func resolve(slot: String) -> Node3D:
	if FORCE_GREYBOX or slot == "":
		return null
	var key := model_of(slot)
	for ext in ["glb", "gltf", "tscn", "scn"]:
		var p := "%s/%s.%s" % [MODEL_DIR, key, ext]
		if not ResourceLoader.exists(p):
			continue
		var res := load(p)
		if res is PackedScene:
			var n := (res as PackedScene).instantiate()
			if n is Node3D:
				return n as Node3D
			_warn("%s 不是 3D 场景，" % [p] + "已跳过")
			n.queue_free()
	return null


## 把真模型挂到灰盒方块身上：灰盒的盒子隐藏（碰撞保留当基准），模型接管外观。
## host 原点是方块中心时，模型要下移半个高度，才能让底面贴到方块底面。
## y_off 传 0.0 表示「host 原点就在底面」，不做偏移（玩家胶囊、点击落点圈就是这种）。
## host_yaw：宿主节点在 attach 之后还会绕 Y 转多少度。核对尺寸要按「转完的姿态」比，
## 所以调用方必须提前告诉它，别等转完再说（见 main.gd._add_box 的注释）。
func attach(host: Node3D, slot: String, expect_size: Vector3, grey_mesh: MeshInstance3D,
		y_off: float = 1.0e9, host_yaw: float = 0.0) -> bool:
	if slot == "":
		return false
	var model := resolve(slot)
	if model == null:
		grey.append(slot)
		return false

	if grey_mesh != null:
		grey_mesh.visible = false
	model.name = "Model"
	var off := -expect_size.y * 0.5 if y_off > 1.0e8 else y_off
	model.position = Vector3(0.0, off, 0.0)
	# 槽位自带的朝向：绕宿主原点（底面中心）转，转完不挪位置、不改高度。
	# 宿主上如果另外还有 rot（比如 props 里写的），那是第二层 —— 模型只负责这一层。
	var rot := slot_rot(slot)
	if not is_zero_approx(rot):
		model.rotation_degrees = Vector3(0.0, rot, 0.0)
	host.add_child(model)

	used.append(slot)
	used_models[model_of(slot)] = true
	_check_size(slot, model, expect_size, host, host_yaw)
	_check_tris(slot, model)
	return true


func _check_size(slot: String, model: Node3D, expect: Vector3, host: Node3D,
		host_yaw: float = 0.0) -> void:
	var aabb := _aabb_of(model, host)
	if aabb.size == Vector3.ZERO:
		return
	var ex := _expected_in_host(slot, expect, host_yaw)
	if ex.x <= 0.0 or ex.y <= 0.0 or ex.z <= 0.0:
		return
	var rx := aabb.size.x / ex.x
	var ry := aabb.size.y / ex.y
	var rz := aabb.size.z / ex.z
	if minf(minf(rx, ry), rz) < 0.6 or maxf(maxf(rx, ry), rz) > 1.6:
		_warn("%s（%s）尺寸对不上灰盒：模型 %.2f×%.2f×%.2f / 预期 %.2f×%.2f×%.2f —— 请检查是否忘了 Apply Scale"
			% [slot, cn_name(slot), aabb.size.x, aabb.size.y, aabb.size.z, ex.x, ex.y, ex.z])


## 灰盒 size 写的是**没转过**的尺寸（宽沿 x、厚沿 z，和模型的自然朝向一致）。
## 但宿主上可能叠了两层转角：① 槽位自己写的 rot（模型相对宿主转）；
## ② 宿主本身还要转（props/spots 里的 rot，整个方块连模型一起转）。
## 两层都按 90/270 把 x/z 换一换（整角叠加后仍是 90 的奇数倍就换轴），
## 否则逐轴比值会拿「宽」去比「厚」（2026-10-05 公告栏就是这么报的「宽在 x 不在 z」）。
func _expected_in_host(slot: String, expect: Vector3, host_yaw: float = 0.0) -> Vector3:
	var total := fposmod(slot_rot(slot) + host_yaw, 360.0)
	if absf(total - 90.0) < 1.0 or absf(total - 270.0) < 1.0:
		return Vector3(expect.z, expect.y, expect.x)
	return expect


func _check_tris(slot: String, model: Node3D) -> void:
	var budget := tri_budget(slot)
	if budget <= 0:
		return
	var t := _tri_of(model)
	if t > budget:
		_warn("%s（%s）面数 %d 超预算 %d —— 如果这是作者刻意保留的高模，就把 data/model_map.json 里这条的 tri 改成实际面数；否则再考虑减面。" % [slot, cn_name(slot), t, budget])


## 折算到「灰盒方块所在的空间」里的包围盒，这样旋转过的父节点也不会算错。
func _aabb_of(n: Node3D, host: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var to_host := host.global_transform.affine_inverse()
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var mi := cur as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = (to_host * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _tri_of(n: Node3D) -> int:
	var t := 0
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var mi := cur as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var m: Mesh = mi.mesh
		for i in m.get_surface_count():
			var arr := m.surface_get_arrays(i)
			if arr.size() <= Mesh.ARRAY_INDEX or arr[Mesh.ARRAY_INDEX] == null:
				continue
			var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
			t += int(float(idx.size()) / 3.0)
	return t


func _warn(msg: String) -> void:
	_warnings.append(msg)
	push_warning("[模型槽位] " + msg)


## 收工播报：console 里一眼看清「要几个模型、换了几个、哪些位置还是灰盒」。
func report() -> void:
	var need := model_count()
	var lines := PackedStringArray()
	lines.append("[模型槽位] %d 个位置，一共只需要做 %d 个模型" % [entries.size(), need])
	lines.append("[模型槽位] 已换 %d/%d 个模型，还有 %d 个位置在用灰盒"
		% [used_models.size(), need, grey.size()])
	if not used_models.is_empty():
		var names := PackedStringArray(used_models.keys())
		names.sort()
		lines.append("[模型槽位] 已替换：" + ", ".join(names))
	if not grey.is_empty() and used.size() > 0:
		lines.append("[模型槽位] 还是灰盒的位置（%d 个）：" % grey.size() + ", ".join(PackedStringArray(grey)))
	if _warnings.is_empty():
		lines.append("[模型槽位] 尺寸与面数全部通过")
	else:
		lines.append("[模型槽位] %d 条提醒：" % _warnings.size())
		for w in _warnings:
			lines.append("   - " + w)
	for l in lines:
		print(l)
