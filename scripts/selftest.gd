extends Node
## 端到端自检：无人值守把「点击移动 → 弹信息卡 → 出题 → 正误 → 解锁剧情/线索 → 落幕」跑一遍。
## 跑法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/selftest.tscn

## main.gd 没有 `class_name`（`main` 在自检里只是个 `Node3D`），拿不到它的常量，
## 所以显式 preload 一次 —— 感叹号的净空判据要用 `CLUE_ICON_H / AR / PAD`。
const MainGd := preload("res://scripts/main.gd")

var fails := 0
var checks := 0


func _check(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("  PASS   %s" % label)
	else:
		fails += 1
		print("  FAIL   %s" % label)


## 把当前弹窗里所有可见文字拼起来，用来核对「正文到底有没有渲染出来」。
func _modal_text(hud: Hud) -> String:
	var out := ""
	for c in hud._body.get_children():
		if c is Label:
			out += (c as Label).text + "\n"
		else:
			for cc in c.get_children():
				if cc is Label:
					out += (cc as Label).text + "\n"
	return out


## 数一张纸卡里有几个按钮。
##
## ⛔ 这条判据是拿血换来的：2026-10-06 作者点开线索框之后**关不掉**，整个游戏点哪儿
##    都没反应，只能强退 —— 因为那一版 `show_card` 忘了给出口按钮，而弹窗层是
##    MOUSE_FILTER_STOP。所以现在**每一张纸卡都必须在弹出时至少有一个按钮**。
func _count_buttons(n: Node) -> int:
	var c := 0
	if n is Button:
		c += 1
	for ch in n.get_children():
		c += _count_buttons(ch)
	return c


## 卡片上第一个**真的能按**的按钮（用 `is_visible_in_tree()` 判，不是节点自己的 `visible`）。
## ⛔ 纸卡关掉的实现是 `_modal_layer.visible = false`，按钮自己的 `visible` 还是 true ——
##    拿它当判据会以为「关掉的卡还能按」。
func _first_button(n: Node) -> Button:
	if n == null:
		return null
	for ch in n.get_children():
		if ch is Button and (ch as Button).is_visible_in_tree():
			return ch as Button
		var inner := _first_button(ch)
		if inner != null:
			return inner
	return null


## 灰盒盒子的 MeshInstance3D —— 用来核对发光 overlay、矛盾态底色这些。
## 取宿主身上那个灰盒网格。**必须递归找**：NPC 的视觉被挪到了「脚底枢轴 Anim」下面
## （2026-10-05 加待机动作时改的），直接 body.get_node("Greybox") 会拿到 null。
func _grey(body: Node3D) -> MeshInstance3D:
	if body == null:
		return null
	return body.find_child("Greybox", true, false) as MeshInstance3D


## 取宿主身上那个真模型根节点。同样要递归 —— NPC 的 Model 也被挪进枢轴里了。
func _model_of(host: Node3D) -> Node3D:
	if host == null:
		return null
	return host.find_child("Model", true, false) as Node3D


## 抽样数一张贴图里不透明的像素（隔 step 个取一个）—— 用来比「这四张是不是同一个形状」。
func _solid_count(img: Image, step: int) -> int:
	if img == null:
		return -1
	var n := 0
	for yy in range(0, img.get_height(), step):
		for xx in range(0, img.get_width(), step):
			if img.get_pixel(xx, yy).a > 0.5:
				n += 1
	return n


## 一批数里有几种不同的值。
func _uniq_count(vals: Array) -> int:
	var seen := {}
	for v in vals:
		seen[str(v)] = true
	return seen.size()


## 宿主视觉的「脚底高度 / 头顶高度」（世界坐标）。
##
## ⚠ 取每个网格**局部包围盒的底面中心**变换到世界，**不是**包围盒的 8 个角 ——
## 角点在身体一倾斜时会甩出十几毫米的假位移（AABB 是个松垮的盒子，并不贴着身体），
## 那个数字会把「脚到底有没有离地」测错。第一版就是这么误判成 FAIL 的。
func _vis_bounds(host: Node3D) -> Vector2:
	var lo := INF
	var hi := -INF
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var mi := cur as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a: AABB = mi.mesh.get_aabb()
		var c2 := a.get_center()
		var bot: Vector3 = mi.global_transform * Vector3(c2.x, a.position.y, c2.z)
		var top: Vector3 = mi.global_transform * Vector3(c2.x, a.position.y + a.size.y, c2.z)
		lo = minf(lo, bot.y)
		hi = maxf(hi, top.y)
	return Vector2(lo, hi)


## 一直等到条件成立，最多等 max_frames 帧。
## **别硬数帧** —— headless 下的实际帧率跟带窗口时不一样，数死了就会时快时慢地失败
## （2026-10-05 加待机动作的断言时踩到的：同样的 80 帧，有的机器上收不回去）。
func _wait_until(pred: Callable, max_frames: int) -> void:
	var waited := 0
	while waited < max_frames and not bool(pred.call()):
		await get_tree().process_frame
		waited += 1


## 按槽位名找场景里那个「宿主」节点。
## 必须用 slot meta 匹配，不能比节点名 —— 模型内部也可能有同名节点
## （Blender 里对象名如果用了位置名，glb 里就会带一个，场景里就出现两个同名节点）。
func _slot_node(root: Node, slot: String) -> Node3D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if str(cur.get_meta("slot", "")) == slot:
			return cur as Node3D
		for c in cur.get_children():
			stack.append(c)
	return null


## 从 JSON 的 pos / size / rot 直接算世界包围盒，返回
## [x_min, x_max, y_min, y_max, z_min, z_max]。
## ⛔ rot 是 90 或 270 时**要把 x / z 的跨度对调** —— 绕 Y 转 90° 就是把
##    宽度那一维转到深度那一维上（门就是靠这个上西墙的）。
func _aabb_of(d: Dictionary) -> Array:
	var pos := ContentDB.vec3(d.get("pos"), Vector3.ZERO)
	var sz := ContentDB.vec3(d.get("size"), Vector3.ZERO)
	var r := int(roundf(float(d.get("rot", 0.0)))) % 360
	if r == 90 or r == 270:
		sz = Vector3(sz.z, sz.y, sz.x)
	return [pos.x - sz.x * 0.5, pos.x + sz.x * 0.5,
		pos.y, pos.y + sz.y,
		pos.z - sz.z * 0.5, pos.z + sz.z * 0.5]


## 两个包围盒的最小重叠厚度（不相交就是负数）。三条轴取最小 = 真正「插进去多深」。
func _aabb_overlap(a: Array, b: Array) -> float:
	return minf(minf(minf(float(a[1]) - float(b[0]), float(b[1]) - float(a[0])),
			minf(float(a[3]) - float(b[2]), float(b[3]) - float(a[2]))),
		minf(float(a[5]) - float(b[4]), float(b[5]) - float(a[4])))


func _ready() -> void:
	print("=== 第一幕自检开始 ===")

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	print("[0] 数据与场景")
	# ⚠ 2026-10-06 更晚：作者「办公室一共有 6 张桌子……4 是外聘设计总监的，5 为空，6 是部长的」
	#    —— 两张三人长桌背靠背 = 6 个座位，原来只在北排做了 3 个点，这次把南排那两个
	#    （`leader_desk` / `boss_desk`）补上 → objects.json 的 spots **6 → 8**。
	#    这条数**跟着 objects.json 现读的意思**：它就是「JSON 有没有被改坏」的冒烟测试，
	#    数据变了就跟着改这个数（别改成 `>= 6` 那种放水写法）。
	_check(ContentDB.spots.size() == 8, "读到 8 个探索点（6 张桌子：北排 3 + 南排 3，其中南排中间那个空位没有点）")
	_check(ContentDB.npcs.size() == 4, "读到 4 个 NPC")
	_check(ContentDB.round_count() == 3, "读到 3 轮（第一幕是三轮搜证）")
	# ⭐ 2026-10-06 作者：「场景里的家具全部可探索，小人也是可探索点」→
	#    每轮 = 探索点（objects.json 的 spots）+ 可探索家具（room.json 的 explore 字段）+ 4 个小人。
	# ⚠ 2026-10-06 晚：作者「只用的上布告栏，白板之类的都可以删掉了」→ 白板删掉，可探索家具 11→10。
	# ⚠ 同日晚些：加了南排两个工位探索点 → 场景可探索点总数 **20 → 22**（8 spots + 10 家具 + 4 小人）。
	#    这条数**跟着 objects/room 现读**，别再硬编。
	# ⚠ 2026-10-06 更晚：作者把三轮文案填回来了 —— **每一轮的探索点是不同子集**
	#    （表里没写、或整行留空的点，这一轮就没有它）。所以**不能再钉「每轮 20 个」**，
	#    改成钉「每轮都非空 + 三轮不是同一个集合（子集机制真的生效）」。
	var n_explore_props := 0
	for p in ContentDB.room.get("props", []):
		if str((p as Dictionary).get("explore", "")) != "":
			n_explore_props += 1
	var n_round := ContentDB.spots.size() + n_explore_props + ContentDB.npcs.size()
	var round_sizes: Array[int] = []
	var pool: Array[String] = []
	var seen_pool := {}
	var empty_rounds: Array[String] = []
	for ri_ in range(ContentDB.round_count()):
		var ids_ri := ContentDB.round_spot_ids(ri_)
		round_sizes.append(ids_ri.size())
		if ids_ri.is_empty():
			empty_rounds.append("第%d轮" % (ri_ + 1))
		for sid_ri in ids_ri:
			if not seen_pool.has(sid_ri):
				seen_pool[sid_ri] = true
				pool.append(sid_ri)
	_check(empty_rounds.is_empty(),
		"每一轮都至少有一个可探索点（空的是：%s）" % str(empty_rounds))
	_check(pool.size() > 0 and pool.size() <= n_round,
		"三轮用到的位置都是场景里真有的可探索点（三轮合计 %d 个 / 场景共 %d 个）"
		% [pool.size(), n_round])
	_check(round_sizes[0] != round_sizes[1] or round_sizes[1] != round_sizes[2],
		"三轮的探索点不是同一个集合（各轮 %s 个）—— 「每一轮可以不一样」真的生效了"
		% str(round_sizes))
	_check(ContentDB.round_questions(0).size() >= 1,
		"第一轮有判断题（%d 道）" % ContentDB.round_questions(0).size())
	_check(ContentDB.errors.is_empty(), "JSON 没有任何错误")
	# 每轮列出来的探索点 id 都必须在 objects.json 里真有那个位置 —— 拼错一个字母
	# 就是一个「永远点不开的空位」，而眼睛看不出来（感叹号压根不会出现）。
	# ⚠ 2026-10-06 起「探索点」包括**小人**（NPC），所以不能用 `get_spot()` 判 ——
	#   那会把四个小人整批误判成悬空。
	var dangling: Array[String] = []
	var no_answer: Array[String] = []
	for i in range(ContentDB.round_count()):
		for sid in ContentDB.round_spot_ids(i):
			if not ContentDB.is_explorable(sid):
				dangling.append("第%d轮:%s" % [i + 1, sid])
		for q in ContentDB.round_questions(i):
			var ok := false
			var opts: Variant = q.get("options", [])
			if typeof(opts) == TYPE_ARRAY:
				for o in opts:
					if typeof(o) == TYPE_DICTIONARY and bool((o as Dictionary).get("correct", false)):
						ok = true
			if not ok:
				no_answer.append("第%d轮:%s" % [i + 1, str(q.get("id", "?"))])
	_check(dangling.is_empty(), "每轮的探索点 id 都对得上 objects.json（悬空 %s）" % str(dangling))
	_check(no_answer.is_empty(), "每道判断题都至少有一个正确选项（缺 %s）" % str(no_answer))
	_check(main.hud != null, "HUD 已生成")
	_check(main.camera != null and main.camera.current, "相机已就位")

	print("[0b] 感叹号不穿模（作者 2026-10-06 截图：公示板那根插进了板子里）")
	# ⛔ 判据口径：感叹号是 **billboard**（绕 Y 轴永远朝相机、竖轴不动），所以它的
	#    最坏占地就是 `水平 ±H*AR/2` × `竖直 ±H/2`。只要圆心同时满足
	#      ① 离四面墙都有半个图宽的余量；
	#      ② 对宿主**要么整个浮在其顶面之上、要么水平让开「半个宿主 + 半个图宽」**，
	#    任何视角都不会插进去。
	# ⚠ y 用 `base_y`（不抖动的基准）判 —— 图标会上下轻浮（`CLUE_ICON_BOB`），
	#   拿实时 `position.y` 判会随相位忽过忽挂。
	var ar := 0.0
	var tex_aspect := 0.0
	var probe_tex: Texture2D = load(str(MainGd.CLUE_ICON_TEX))
	if probe_tex != null and probe_tex.get_height() > 0:
		tex_aspect = float(probe_tex.get_width()) / float(probe_tex.get_height())
	ar = MainGd.CLUE_ICON_AR
	_check(absf(ar - tex_aspect) < 0.01,
		"CLUE_ICON_AR 跟真贴图对得上（常量 %.5f vs 贴图 %.5f）" % [ar, tex_aspect])
	var chw := MainGd.CLUE_ICON_H * ar * 0.5
	var chh := MainGd.CLUE_ICON_H * 0.5
	var rsz := ContentDB.vec3(ContentDB.room.get("size"), Vector3(16.0, 4.5, 12.0))
	var hit_wall: Array[String] = []
	var hit_host: Array[String] = []
	# ⚠ 2026-10-06 起**小人身上也有感叹号**，所以这里要连 npcs 一起量 —— 只量 spots
	#   的话，小人那四根插进身体里都不会有人发现。
	# ⚠ 2026-10-06 再改：**可探索家具（room.json 的 explore 字段）身上也有感叹号**，
	#   一起量，别让人台/饮水机/雕塑那几根插进自己身体里。
	var hosts: Array[Dictionary] = []
	hosts.append_array(ContentDB.spots)
	hosts.append_array(ContentDB.npcs)
	for p in ContentDB.room.get("props", []):
		var eid := str((p as Dictionary).get("explore", ""))
		if eid != "":
			var pe: Dictionary = p.duplicate()
			pe["id"] = eid          # 让下面用 explore_id 当 key 找感叹号
			hosts.append(pe)
	for s in hosts:
		var sid := str(s.get("id", ""))
		var sp2: Sprite3D = main._clue_icons.get(sid) as Sprite3D
		if sp2 == null:
			continue
		var c := sp2.position
		if absf(c.x) > rsz.x * 0.5 - chw + 0.001 or absf(c.z) > rsz.z * 0.5 - chw + 0.001:
			hit_wall.append(sid)
		var spos := ContentDB.vec3(s.get("pos"), Vector3.ZERO)
		var ssz := ContentDB.vec3(s.get("size"), Vector3(0.6, 0.3, 0.5))
		var cy := float(sp2.get_meta("base_y", c.y)) - MainGd.CLUE_ICON_BOB
		var above: bool = (cy - chh) >= spos.y + ssz.y - 0.001
		var aside: bool = absf(c.x - spos.x) >= ssz.x * 0.5 + chw - 0.001 \
				or absf(c.z - spos.z) >= ssz.z * 0.5 + chw - 0.001
		if not (above or aside):
			hit_host.append(sid)
	_check(hit_wall.is_empty(), "每个感叹号离四面墙都有半个图宽的余量（贴墙的：%s）" % str(hit_wall))
	_check(hit_host.is_empty(), "每个感叹号都不插在宿主包围盒里（插了的：%s）" % str(hit_host))

	# ⭐⭐ 2026-10-06 夜新增：**开局（第 1 轮）只该亮本轮列出来的那几个感叹号**。
	# ⛔ 第一版 `_ready()` 从头到尾**没有调过 `_refresh_clue_icons()`** —— `_build_clue_icon()`
	#    建出来的 Sprite3D 默认 `visible = true`，而「按本轮点位显隐」第一次发生在**切轮次**
	#    的时候，于是开局 22 个感叹号全亮：作者实测「好多不需要搜证的也标了感叹号」，
	#    HUD 写着 0/14、画面上却有 22 个（多出来的 8 个正是三轮都没文案的那些点位）。
	# ⛔ 判据**别写死数字**：本轮该亮几个从 `act1.json` 现读；「不该亮的」也现算。
	var newr1 := ContentDB.round_spot_ids(0)
	var newlit: Array[String] = []
	for iid in main._clue_icons:
		var isp: Sprite3D = main._clue_icons[iid]
		if isp != null and isp.visible:
			newlit.append(str(iid))
	_check(newlit.size() == newr1.size(),
		"开局只亮本轮的 %d 个感叹号（实亮 %d 个）" % [newr1.size(), newlit.size()])
	var newextra: Array[String] = []
	for iid2 in newlit:
		if not newr1.has(iid2):
			newextra.append(iid2)
	_check(newextra.is_empty(), "没有「本轮用不到却亮着」的感叹号（多出来的：%s）" % str(newextra))
	# 反向：**三轮都没出现过**的点位必须一直是暗的（作者：「很多不需要搜证的也标了感叹号」）。
	var newallr: Array[String] = []
	for nri in range(ContentDB.round_count()):
		for nrid in ContentDB.round_spot_ids(nri):
			if not newallr.has(nrid):
				newallr.append(nrid)
	var newnever: Array[String] = []
	for iid3 in main._clue_icons:
		if not newallr.has(str(iid3)):
			newnever.append(str(iid3))
	var newwrong: Array[String] = []
	for iid4 in newnever:
		var nsp2: Sprite3D = main._clue_icons[iid4]
		if nsp2 != null and nsp2.visible:
			newwrong.append(iid4)
	_check(newwrong.is_empty(),
		"三轮都没文案的 %d 个点位一个都没亮（亮着的：%s）" % [newnever.size(), str(newwrong)])

	print("[0c] 小人也是可探索点（作者 2026-10-06：「点小人获得小人身上的线索」）")
	var no_icon: Array[String] = []
	for n in ContentDB.npcs:
		var nid := str(n.get("id", ""))
		if main._clue_icons.get(nid) == null:
			no_icon.append(nid)
	_check(no_icon.is_empty(), "四个小人身上都挂了感叹号（缺：%s）" % str(no_icon))
	var npc_in_round := 0
	var r0 := ContentDB.round_spot_ids(0)
	for n in ContentDB.npcs:
		if r0.has(str(n.get("id", ""))):
			npc_in_round += 1
	_check(npc_in_round == ContentDB.npcs.size(),
		"本轮探索点列表里 4 个小人全在（实到 %d 个）—— 小人当然也会出现在进度分母里" % npc_in_round)
	_check(ContentDB.explorable_name("boss") == "老板",
		"`explorable_name()` 能同时取家具和人的名字（boss → %s）" % ContentDB.explorable_name("boss"))
	# ⛔ 人的 `pos.y` 是**脚底**（0）。拿它当基准，图标会被推到脚踝那么低、看着像掉在地上，
	#    所以 `_build_npcs` 改成按**体高 30%** 取基准（1.30 米的人 → 图标中心 ≈ 1.0 米 = 胸口）。
	#    这条判据就是钉住这件事的：一旦有人把它改回 `pos.y`，立刻报出来。
	var low_icons: Array[String] = []
	for n in ContentDB.npcs:
		var nid2 := str(n.get("id", ""))
		var nsp := main._clue_icons.get(nid2) as Sprite3D
		if nsp == null:
			continue
		var ncy := float(nsp.get_meta("base_y", nsp.position.y)) - MainGd.CLUE_ICON_BOB
		var nh := ContentDB.vec3(n.get("size"), Vector3(0.5, 1.3, 0.5)).y
		if ncy < nh * 0.60:
			low_icons.append("%s(y=%.2f / 体高%.2f)" % [nid2, ncy, nh])
	_check(low_icons.is_empty(),
		"小人身上的感叹号在胸口高度、不是掉在脚边（偏低的：%s）" % str(low_icons))

	# ⛔ 可探索家具同理：立着的家具（体高 >= 1 米）的感叹号不能贴地 —— 第一版拿
	#   `pos.y`（脚底 0）当基准，人台/雕塑的图标全掉在地上（核对图 L38 穿帮）。
	#   规矩 = 和小人同一套：`pos.y + 体高 30%`。这条钉住它。
	var low_props: Array[String] = []
	for p in ContentDB.room.get("props", []):
		var eid := str((p as Dictionary).get("explore", ""))
		if eid == "":
			continue
		var psp := main._clue_icons.get(eid) as Sprite3D
		if psp == null:
			low_props.append(eid + "(没挂感叹号)")
			continue
		var pcy := float(psp.get_meta("base_y", psp.position.y)) - MainGd.CLUE_ICON_BOB
		var ph := ContentDB.vec3(p.get("size"), Vector3(0.5, 1.0, 0.5)).y
		if ph >= 1.0 and pcy < ph * 0.20:
			low_props.append("%s(y=%.2f / 体高%.2f)" % [eid, pcy, ph])
	_check(low_props.is_empty(),
		"可探索家具的感叹号浮在身上、不是掉在脚边（问题：%s）" % str(low_props))
	var missing_icons: Array[String] = []
	for p2 in ContentDB.room.get("props", []):
		var eid2 := str((p2 as Dictionary).get("explore", ""))
		if eid2 != "" and main._clue_icons.get(eid2) == null:
			missing_icons.append(eid2)
	_check(missing_icons.is_empty(),
		"%d 个可探索家具每件都挂了感叹号（缺：%s）" % [n_explore_props, str(missing_icons)])

	print("[1] 小人也是探索点：点他弹他的线索卡（本轮没看完不会出题）")
	# ⭐ 2026-10-06 作者：「每一轮都可以点击小人获得小人身上的线索，小人也是可探索点」。
	_check(main._clue_icons.has("feng"), "小人身上挂了感叹号 —— 他也是一个可探索点")
	main._open_npc("feng")
	await get_tree().process_frame
	_check(main.hud.modal_visible, "点小人会弹纸卡")
	_check(main.hud._title.text == ContentDB.explorable_name("feng"),
		"卡片标题就是这个人（实到「%s」）" % main.hud._title.text)
	_check(_count_buttons(main.hud._body) >= 1, "线索卡带出口按钮（不会把人锁死）")
	_check(main.scanned.has("feng"), "点过之后记进「已调查」")
	_check(main.clues.size() == 1, "结论当场记到右边「已记下的东西」（%d 条）" % main.clues.size())
	var feng_icon := main._clue_icons.get("feng") as Sprite3D
	_check(feng_icon != null and not feng_icon.visible, "看过之后他身上的感叹号收起来")

	# ⭐⭐ 2026-10-06 夜作者实测「部长的感叹号点不了」：他的图标被水平推到沙发角落上方，
	#    视线里先撞上沙发 / 他自己，按「最近命中」永远轮不到它（见 main._handle_click 的修复）。
	#    这里做**对比实验**：① 普通射线（最近命中）复现「点了没反应」；② 只看感叹号层 → 修复后走这条。
	var bicon: Node3D = main._clue_icons.get("boss") as Node3D
	var bcam: Camera3D = main.camera as Camera3D
	if bicon != null and bcam != null:
		var bscr: Vector2 = bcam.unproject_position(bicon.global_position)
		var plain: Dictionary = main._ray_at(bscr)
		var plain_id := "(空)"
		if not plain.is_empty() and plain.get("collider") is Node3D:
			var pn := plain.get("collider") as Node3D
			plain_id = str(pn.get_meta("spot_id", pn.get_meta("npc_id", String(pn.name))))
		var bhit: Dictionary = main._ray_at(bscr, main.CLUE_PICK_LAYER)
		var bhit_id := "(空)"
		if not bhit.is_empty() and bhit.get("collider") is Node3D:
			bhit_id = str((bhit.get("collider") as Node3D).get_meta("spot_id", ""))
		print("[boss] 普通射线(最近命中) → %s ；只看感叹号层 → %s" % [plain_id, bhit_id])
		_check(bhit_id == "boss",
			"部长的感叹号**点得着**（只看感叹号层命中「%s」；普通射线先撞到「%s」= 作者看到的点不了）" % [bhit_id, plain_id])
	else:
		_check(false, "部长的感叹号在场景里（找不到图标或相机）")

	main.hud._dismiss()
	await get_tree().process_frame
	_check(not main.hud.modal_visible, "关得掉")
	_check(main.round_idx == 0 and main.story.is_empty() and main.answered.is_empty(),
		"本轮还没看完 → 关掉卡片不会提前出题、也不会替玩家答题")

	print("[2] 远处点物件 → 自动走过去 → 自动打开")
	var first: Dictionary = ContentDB.spots[0]
	var id0 := str(first["id"])
	var node0: Node3D = main._spot_nodes[id0]
	_check(main.player.global_position.distance_to(node0.global_position) > main.INTERACT_RANGE,
		"起点离探索点够远，会触发走路（%.2f m）" % main.player.global_position.distance_to(node0.global_position))
	main._click_spot(id0, node0)
	_check(main.pending_spot == id0, "记下了待打开的探索点")
	_check(main.has_target, "开始走路")
	var waited := 0
	while main.pending_spot != "" and waited < 900:
		await get_tree().physics_frame
		waited += 1
	_check(main.scanned.has(id0), "走到了并自动打开（耗时 %d 物理帧）" % waited)
	_check(main.hud.modal_visible, "信息卡可见")
	_check(_count_buttons(main.hud._body) >= 1, "信息卡带「知道了」按钮 —— 就是作者点开线索后卡死的那一处")
	main.hud.close_modal()

	print("[3] 看完本轮剩下的全部可探索点 → 自动弹判断题")
	var r1 := ContentDB.round_spot_ids(0)
	# ⚠ 起手取「本轮还没看过的那几个」，而不是「下标从 1 开始」—— 作者填表时把小人排在了前面
	#    （r1[0] 不一定就是 [2] 刚看过的那一个），按下标跳会漏掉一个点、链条也就接不上。
	var todo1: Array[String] = []
	for sid1 in r1:
		if not main.scanned.has(sid1):
			todo1.append(sid1)
	for sid1 in todo1:
		main._open_spot(sid1)
		# ⛔ 必须走**真正的出口**（`_dismiss` 会 fire `modal_closed`）—— 链条就靠它往后走。
		#    用 `close_modal()` 会把链条掐断，表现就是「看完最后一个位置什么也不发生」。
		main.hud._dismiss()
	_check(main.scanned.size() == r1.size(),
		"第一轮 %d 个可探索点全部记录（实到 %d）" % [r1.size(), main.scanned.size()])
	_check(main.clues.size() == r1.size(),
		"每看一处就在右边「已记下的东西」留一条结论（实到 %d 条 / 应 %d 条）" % [main.clues.size(), r1.size()])
	_check(main.hud.modal_visible and main.hud._title.text == "判断题",
		"看完最后一个位置 → **自动**弹出判断题（不用再找小人说话）")
	_check(main.answered.is_empty(), "只是把题弹出来，没有替玩家答题")
	var feng_icon2 := main._clue_icons.get("feng") as Sprite3D
	_check(feng_icon2 != null and not feng_icon2.visible, "看过的小人身上的感叹号也收起来了")


	print("[4] 第一题：答错（题目是自动弹出来的，没经过任何 NPC）")
	# ⭐ 2026-10-06 晚：文案由作者填回来了 —— 判据**一律从 round_questions(0) 现读**，
	#    不再硬编「珠宝生意 / 专业能力 / 被划掉的那个」这种占位稿里的字，也不再写死
	#    「选第几个选项」的下标。作者改文案、改选项顺序，这些判据都不该跟着翻。
	var qs1: Array[Dictionary] = ContentDB.round_questions(0)
	_check(qs1.size() >= 3, "第一轮至少 3 道判断题（实为 %d）" % qs1.size())
	var q_first: Dictionary = qs1[0]
	var q_first_id := str(q_first.get("id", ""))
	var q_first_prompt := str(q_first.get("prompt", ""))
	var q_first_target := str(q_first.get("target", ""))
	var q_first_opts: Array = q_first.get("options", [])
	var q_first_wrong := -1
	for ofi in range(q_first_opts.size()):
		if not bool((q_first_opts[ofi] as Dictionary).get("correct", false)):
			q_first_wrong = ofi
			break
	_check(q_first_target != "" and main._clue_icons.get(q_first_target) != null,
		"第 1 道题（%s）挂着矛盾态目标位置（%s）" % [q_first_id, q_first_target])
	_check(q_first_wrong >= 0, "第 1 道题里挑得到一个「错」选项")
	_check(_count_buttons(main.hud._body) == q_first_opts.size(),
		"判断题按选项数给按钮（%d 个选项 / %d 个按钮）" % [q_first_opts.size(), _count_buttons(main.hud._body)])
	_check(q_first_prompt != "" and _modal_text(main.hud).contains(q_first_prompt),
		"自动弹出的是本轮的**第 1 道**题（按数组顺序）")
	# ⚠ 右栏现在**从探索阶段开始就一直在攒结论**了，所以这里量的是「增量」不是绝对值。
	var clues_before: int = main.clues.size()
	main._on_option_chosen(q_first_id, q_first_wrong)
	await get_tree().process_frame
	_check(main.clues.size() == clues_before + 1,
		"答错 → 右栏多出 1 条新线索（%d → %d）" % [clues_before, main.clues.size()])
	_check(main.story.is_empty(), "答错不产新剧情")
	_check(main.answered.get(q_first_id) == false, "记录为答错")
	var ding := main._clue_icons.get(q_first_target) as Sprite3D
	_check(ding != null and ding.modulate != Color.WHITE, "答错后该物件的感叹号变为矛盾态（染色）")
	_check(main.hud._title.text == "答错了", "反馈面板写「答错了」")
	var wrong_text := _modal_text(main.hud)
	var q_first_bad := str(q_first.get("on_wrong", "")).split("\n")
	_check(q_first_bad.size() > 0 and q_first_bad[0] != "" and wrong_text.contains(q_first_bad[0]),
		"答错时 on_wrong 正文真的渲染出来了")
	main.hud._continue()

	print("[5] 第二题：答对（反馈关掉后自动接上下一道）")
	var q_second: Dictionary = qs1[1]
	var q_second_id := str(q_second.get("id", ""))
	var q_second_prompt := str(q_second.get("prompt", ""))
	var q_second_opts: Array = q_second.get("options", [])
	var q_second_ok := -1
	for osi in range(q_second_opts.size()):
		if bool((q_second_opts[osi] as Dictionary).get("correct", false)):
			q_second_ok = osi
			break
	_check(q_second_ok >= 0, "第 2 道题（%s）里有正确选项" % q_second_id)
	_check(main.hud._title.text == "判断题",
		"第一题反馈关掉后**自动**弹出第二道（现在：%s）" % main.hud._title.text)
	_check(q_second_prompt != "" and _modal_text(main.hud).contains(q_second_prompt),
		"接上的是第 2 道题（不是又弹回第 1 道）")
	main._on_option_chosen(q_second_id, q_second_ok)
	await get_tree().process_frame
	_check(main.story.size() == 1, "答对 → 解锁 1 条新剧情")
	_check(main.hud._title.text == "答对了", "反馈面板写「答对了」")
	_check(_count_buttons(main.hud._body) >= 1, "答对/答错反馈卡带「继续」按钮")
	var right_text := _modal_text(main.hud)
	var q_second_good := str(q_second.get("on_correct", "")).split("\n")
	_check(q_second_good.size() > 0 and q_second_good[0] != "" and right_text.contains(q_second_good[0]),
		"答对时 on_correct 正文真的渲染出来了")
	_check(right_text.contains("【新剧情】"), "正文带着【新剧情】标记")
	main.hud._continue()

	print("[6] 第三题：前置满足后自动接上（`requires` 生效）")
	var q_third: Dictionary = qs1[2]
	var q_third_id := str(q_third.get("id", ""))
	var q_third_prompt := str(q_third.get("prompt", ""))
	var q_third_opts: Array = q_third.get("options", [])
	var q_third_ok := -1
	for oti in range(q_third_opts.size()):
		if bool((q_third_opts[oti] as Dictionary).get("correct", false)):
			q_third_ok = oti
			break
	var req3: Variant = q_third.get("requires", [])
	_check(typeof(req3) == TYPE_ARRAY and not (req3 as Array).is_empty(),
		"第 3 道题（%s）确实带 `requires` —— 前两题答完才轮到它" % q_third_id)
	_check(main.hud._title.text == "判断题",
		"第二题反馈关掉后自动弹出第三道（现在：%s）" % main.hud._title.text)
	_check(q_third_ok >= 0, "第 3 道题里有正确选项")
	_check(q_third_prompt != "" and _modal_text(main.hud).contains(q_third_prompt),
		"第三题就是 `requires` 那道（题干对得上）")
	main._on_option_chosen(q_third_id, q_third_ok)
	await get_tree().process_frame
	_check(main.story.size() == 2, "第三题答对 → 新剧情累计 2 条")
	main.hud._continue()
	await get_tree().process_frame
	_check(main.hud._title.text.begins_with("第一轮"),
		"第一轮 %d 题答完 → 弹轮末过场（不是直接收幕）" % qs1.size())
	_check(main.round_idx == 0 and main.scanned.size() == r1.size(),
		"过场弹出时还停在第一轮、调查记录还在")
	# 防重入：轮末卡还开着的时候，任何一次多余的 modal_closed 都不该再弹一张（之前会叠）。
	var ended_twice := false
	main._on_modal_closed()
	await get_tree().process_frame
	ended_twice = main.hud._title.text.begins_with("第一轮")
	_check(ended_twice, "轮末过场有防重入闸（重复触发不会再弹一张）")

	print("[6b] 轮末推进 → 线索刷新")
	# ⛔⛔ 这里必须**真的按那个按钮**，不能拿 `main._on_advance()` 糊过去。
	#    · 第一版写成 `_dismiss()` —— 轮末卡的出口是按钮发 `advance_requested`，
	#      `_dismiss` 发的是 `modal_closed`，根本不是一条线（当时 7 条全挂，见旧注释）。
	#    · 第二版改成了直接调 `_on_advance()` —— 能过，但**绕过了按钮本身**。
	#      于是「按钮发了信号却没关纸卡」这个 bug 一路溜到作者手上：
	#      他实测「第一轮转第二轮卡住了、没有继续按键，而且能连点直接跳过后两轮」。
	#    ⭐ 判据必须站在**玩家真的会走的那条路**上：按按钮 → 轮次 +1 **且卡片关掉**。
	_check(_count_buttons(main.hud._body) >= 1,
		"轮末过场带了出口按钮（%d 个）" % _count_buttons(main.hud._body))
	var end_btn := _first_button(main.hud._body)
	_check(end_btn != null, "找得到那个按钮（文本「%s」）" % ("" if end_btn == null else end_btn.text))
	if end_btn != null:
		end_btn.pressed.emit()
	await get_tree().process_frame
	_check(main.round_idx == 1, "点「继续搜证」→ 进第 2 轮")
	_check(not main.hud.modal_visible, "点了之后纸卡**真的关掉了**（作者卡住就是这个：轮次偷偷 +1、卡还停在屏幕上）")
	var end_btn2 := _first_button(main.hud._body)
	_check(end_btn2 == null, "关掉之后按钮按不到了（连点不会一路滑到收幕）")
	main._on_modal_closed()
	await get_tree().process_frame
	_check(main.round_idx == 1, "关掉之后不会自己再往前推一轮")
	_check(main.scanned.is_empty(), "线索刷新：已调查记录清空")
	var feng_icon3 := main._clue_icons.get("feng") as Sprite3D
	_check(feng_icon3 != null and feng_icon3.visible, "小人身上的感叹号也跟着重新亮起")
	var r2 := ContentDB.round_spot_ids(1)
	var relit := 0
	for sid2 in r2:
		var sp2 := main._clue_icons.get(sid2) as Sprite3D
		if sp2 != null and sp2.visible:
			relit += 1
	_check(relit == r2.size(), "第 2 轮 %d 个感叹号全部重新亮起（实到 %d）" % [r2.size(), relit])
	var a0 := str(ContentDB.round_spot(0, "feng_desk").get("lines", []))
	var a1 := str(ContentDB.round_spot(1, "feng_desk").get("lines", []))
	_check(a0 != a1, "同一位置第 2 轮换了一套文案（这就是「线索刷新」）")
	_check(main.hud._chip.text.contains("第 2/3 轮"), "顶部进度条显示轮次（现在：%s）" % main.hud._chip.text)

	print("[7] 重复操作不重复计数")
	var name1 := str(ContentDB.round_spot(1, str(first["id"])).get("name", ""))
	main._open_spot(id0)
	await get_tree().process_frame
	_check(main.scanned.size() == 1, "第 2 轮里看第一个 → 记 1 个")
	_check(main.hud._title.text == name1, "重新查看会再弹一次信息卡")
	main.hud.close_modal()
	main._open_spot(id0)
	await get_tree().process_frame
	_check(main.scanned.size() == 1, "重复查看不算新的")
	main.hud.close_modal()

	print("[8] 模型槽位、编号与复用")
	## 6 张单桌 + 6 把工位椅合并成 2 组「3 连工位桌」：位置 53→43，模型总数不变（24）。
	## 2026-10-05 第一批收了 11 件资产（饮水机 / 沙发 / 发财树 ×2 / 人台 ×3 / 老板 / 设计总监 + 凤凰男、实习 1 号换模型）：
	## 位置 43→51，模型 24→32。
	## 2026-10-05 第二批：3 个旧人台 → **4 件新服装展架 + 1 座雕塑**（作者说旧的「太老土」）：
	## 位置 51→53，模型 32→34（-3 +4 +1）。
	## 2026-10-06：作者说「删掉那个褐色桌子」—— `Reception` prop 撤掉，F-10 槽位一并删：
	## 位置 53→52，模型 34→33。
	## 2026-10-06 同日稍后：作者给了真落地窗，顶掉北墙那排小窗 —— B-08/B-09 两个槽位删掉、
	## 共用模型 SM_B_Window_NS 废弃（模型 -1），B-07 改成落地窗 SM_B_Window_Wall（模型 +1）：
	## 位置 52→50，模型 33→33（一减一加扯平）。
	## 2026-10-06 再稍后：作者说「素材复用拼接这个落地窗把整面墙铺满」—— 落地窗拆成 A/B 两扇
	## （同一个 glb 实例两次）：位置 50→51，模型仍然 33（复用，不多做一个 glb）。
	## 2026-10-06 再再稍后：作者又给了**圆形地毯**（新模型，不是复用）：位置 51→52，模型 33→34。
	## 2026-10-06 再再再稍后：作者「删掉会议桌，以及那些椅子」—— 会议区的 F-03~F-09 七个槽位全删
	##   （共用模型 SM_F_Chair 与会议桌 SM_F_MeetingTable 两个目标一起消失）；
	##   同一轮又给了**吧台**（新模型 SM_F_Bar）：位置 52→**46**（-7 +1），模型 34→**33**（-2 +1）。
	## 2026-10-05 晚些：作者做了一张**新的会议桌**（「会议桌(1).glb」，493,934 面），在俯视图上
	##   手绘了一个黑框 + 框里一个竖长椭圆，要求放在那儿 —— 新增 F-27 槽位（新模型，不是恢复旧槽位）：
	##   位置 46→**47**，模型 33→**34**。
	## 2026-10-05 再稍后：作者又给了**三把办公转椅**（灰绿 / 褐 / 黑，各 50 万面），
	##   在俯视图上画了 5 个圈，要求「随机放在 6 个工位、有一把可以散漫地远离桌子」——
	##   新增 F-28~F-33 六个槽位（3 个模型 × 6 个位置，复用）：
	##   位置 47→**53**，模型 34→**37**。
	## 2026-10-05 再再稍后：作者说「删掉最开始生成的那些占位的建模，例如那些植物」——
	##   4 个绿植（F-13~F-16，共用同一个占位模型 SM_F_Plant）连同 props 全删；
	##   原「茶水间台面」灰盒（J-05）也删掉，探索点整套搬到**吧台**上（改名「吧台」）：
	##   位置 53→**49**（-4），模型 37→**36**（-1，SM_F_Plant 整个消失）。
	## 2026-10-06 晚：作者「我写了一下文案，发现只用的上布告栏，白板之类的都可以删掉了」——
	##   南墙白板（F-12）连 prop 一起删（它一直是灰盒）：位置 49→**48**，模型 36→**35**。
	## 2026-10-06 更晚：作者「就是沙发靠着的那面墙上的两个灰块」—— 东墙那两扇灰盒窗
	##   （B-10 / B-11，共用 SM_B_Window_EW）也删，共用模型一起消失：
	##   位置 48→**46**（-2），模型 35→**34**（-1）。
	## 2026-10-06 再晚：作者「办公室一共有 6 张桌子……4 是外聘设计总监的，5 为空，6 是部长的」
	##   —— 南排两个桌面探索点（`leader_desk` / `boss_desk`）各加一个槽位
	##   （J-07 / J-08，都是灰盒、各自一个「模型名」）：位置 46→**48**（+2），模型 34→**36**（+2）。
	## 数字跟着 model_map.json 走，改表就得改这儿。
	var need_places := 48
	var need_models := 36
	_check(Models.entries.size() == need_places,
		"对照表读到 %d 个位置（实为 %d）" % [need_places, Models.entries.size()])
	_check(Models.model_count() == need_models,
		"只用做 %d 个模型（实为 %d）—— 复用把工作量压下来了" % [need_models, Models.model_count()])

	var bad_slot := []
	var bad_bind := []
	var bad_model := []
	for e in Models.entries:
		var s := str(e.get("slot", ""))
		if s == "" or not s.begins_with("SM_") or Models.by_slot.get(s, null) == null:
			bad_slot.append(s)
		if str(e.get("bind", "")) == "":
			bad_bind.append(s)
		var m := Models.model_of(s)
		if m == "" or not m.begins_with("SM_"):
			bad_model.append(s)
	_check(bad_slot.is_empty(), "每个位置都有合法的 SM_ 名字：%s" % str(bad_slot))
	_check(bad_bind.is_empty(), "每个位置都绑定了场景里的对象：%s" % str(bad_bind))
	_check(bad_model.is_empty(), "每个位置都能算出模型名：%s" % str(bad_model))

	_check(Models.model_of("SM_F_DeskBench_01") == "SM_F_Desk3P"
		and Models.model_of("SM_F_DeskBench_02") == "SM_F_Desk3P",
		"两排三人办公桌共用一份 SM_F_Desk3P（一份模型顶两个位置）")
	# 2026-10-06 作者把整个会议区删了（「删掉会议桌，以及那些椅子」）。
	# 但 2026-10-05 晚些他又做了一张**全新的会议桌**并重新标了位置 → F-27，
	# 再稍后又给了**三把办公转椅** → F-28~F-33（SM_F_Chair_01/02/03）。
	# 所以这里钉三条：
	#   ① 旧的 `SM_F_Chair`（灰盒时代的会议椅，**没有数字后缀**）永远不许回来；
	#   ② Meeting* 的槽位/模型只许有 F-27 这一个 —— 挡住「手滑把旧 7 条槽位贴回来」；
	#   ③ 新给的 6 把工位椅正好是 3 个模型 × 6 个位置（复用），别少摆一个。
	var old_chair := []
	for e in Models.entries:
		if str(e.get("slot", "")) == "SM_F_Chair":
			old_chair.append(str(e.get("slot", "")))
	for m in Models.models_index():
		if str(m) == "SM_F_Chair":
			old_chair.append("model:" + str(m))
	_check(old_chair.is_empty(),
		"旧的会议椅 SM_F_Chair（无后缀）永远不再出现：%s" % str(old_chair))
	var meeting_slots := []
	for e in Models.entries:
		if str(e.get("slot", "")).contains("Meeting"):
			meeting_slots.append(str(e.get("slot", "")))
	_check(meeting_slots == ["SM_F_MeetingTable"],
		"会议桌只有作者新给的 F-27 这一个槽位：%s" % str(meeting_slots))
	var meeting_models := []
	for m in Models.models_index():
		if str(m).contains("Meeting"):
			meeting_models.append(str(m))
	_check(meeting_models == ["SM_F_MeetingTable"],
		"会议桌模型只有 F-27 引用的 SM_F_MeetingTable：%s" % str(meeting_models))
	# 2026-10-05 再稍后：作者给的三把办公转椅 → 6 个工位（3 模型 × 6 位置，复用）。
	var chair_slots := []
	var chair_models := []
	for e in Models.entries:
		var sl := str(e.get("slot", ""))
		if sl.begins_with("SM_F_Chair_"):
			chair_slots.append(sl)
			var m := Models.model_of(sl)
			if not chair_models.has(m):
				chair_models.append(m)
	chair_slots.sort()
	chair_models.sort()
	_check(chair_slots == ["SM_F_Chair_N1", "SM_F_Chair_N2", "SM_F_Chair_N3",
			"SM_F_Chair_S1", "SM_F_Chair_S2", "SM_F_Chair_S3"],
		"6 把工位椅槽位齐全（北排 3 + 南排 3）：%s" % str(chair_slots))
	_check(chair_models == ["SM_F_Chair_01", "SM_F_Chair_02", "SM_F_Chair_03"],
		"工位椅只用 3 个模型（每把复用两次）：%s" % str(chair_models))
	# 「散漫」那把：作者圈 ⑤ 明显离开桌子边缘 → 南排 3 斜着摆、不贴桌。
	_check(Models.model_of("SM_F_Chair_S3") == "SM_F_Chair_03",
		"散漫的那把（南排 3）用的是 SM_F_Chair_03")

	# 摆位几何：作者要的是「每把椅子都在办公桌前」+「有一把（南排 3/第二列第三个）
	# 比较散漫地远离办公桌」。这两条要能量出来，不能只看图。
	#   ① 北排 3 把的**南沿**要贴上 DeskBench_1 的**北沿**（间隙 0 ± 0.10 米 ——
	#      略负也算过，办公椅椅面塞进桌沿底下 1~2 厘米是正常的）；
	#   ② 南排 1/2 的**北沿**要贴上 DeskBench_2 的**南沿**，同样 0.10 米容差；
	#   ③ 南排 3（散漫那把）相反：**必须离桌 ≥ 0.25 米**，且朝向不是正对桌子（rot 不在 0/180 附近）。
	var chair_pos := {}
	var chair_size := {}
	var chair_rot := {}
	var desk1_c := Vector3.ZERO      # DeskBench_1（北排桌子）中心
	var desk2_c := Vector3.ZERO      # DeskBench_2（南排桌子）中心
	var desk_depth := 0.665
	var desk_width := 3.862
	for p in ContentDB.room.get("props", []):
		var pd: Dictionary = p
		var cnm := str(pd.get("name", ""))
		if cnm.begins_with("Chair_"):
			chair_pos[cnm] = ContentDB.vec3(pd.get("pos"), Vector3.ZERO)
			chair_size[cnm] = ContentDB.vec3(pd.get("size"), Vector3.ZERO)
			chair_rot[cnm] = posmod(int(roundf(float(pd.get("rot", 0.0)))), 360)
		elif cnm == "DeskBench_1":
			desk1_c = ContentDB.vec3(pd.get("pos"), Vector3.ZERO)
			var dsz: Vector3 = ContentDB.vec3(pd.get("size"), Vector3.ZERO)
			desk_depth = dsz.z
			desk_width = dsz.x
		elif cnm == "DeskBench_2":
			desk2_c = ContentDB.vec3(pd.get("pos"), Vector3.ZERO)
	# ⚠ 从 props 现读，别写死 —— 桌子挪位置时写死的判据会集体翻车（2026-10-05 挪 0.45 米就是这样）。
	var desk1_n: float = desk1_c.z - desk_depth * 0.5   # 北排桌子的北沿
	var desk2_s: float = desk2_c.z + desk_depth * 0.5   # 南排桌子的南沿
	var near_ok := true
	var near_txt := PackedStringArray()
	for cn in ["Chair_N1", "Chair_N2", "Chair_N3"]:
		if not chair_pos.has(cn):
			near_ok = false
			continue
		# 北排椅子在桌子**北**侧 → 用它的**南沿**去贴桌子北沿。
		var s: float = (chair_pos[cn] as Vector3).z + (chair_size[cn] as Vector3).z * 0.5
		var g: float = s - desk1_n
		near_txt.append("%s %+.3f" % [cn, g])
		if absf(g) > 0.10:
			near_ok = false
	for cn in ["Chair_S1", "Chair_S2"]:
		if not chair_pos.has(cn):
			near_ok = false
			continue
		# 南排椅子在桌子**南**侧 → 用它的**北沿**去贴桌子南沿。
		var n: float = (chair_pos[cn] as Vector3).z - (chair_size[cn] as Vector3).z * 0.5
		var g: float = desk2_s - n
		near_txt.append("%s %+.3f" % [cn, g])
		if absf(g) > 0.10:
			near_ok = false
	_check(near_ok, "北排 3 把 + 南排 1/2 都贴在办公桌沿（间隙米：%s）" % "、".join(near_txt))
	# 朝向（2026-10-05 作者先要「椅子都面朝桌子」，随后又要「所有办公椅转向 180 度」）。
	# 现在钉的是**转向之后**这一版：北排 `rot 180`（面朝北/窗）、南排 1/2 `rot 0`（面朝南），
	# 即**背对桌子**。清单里三把椅子模型都 `yaw 180` 过，所以 `rot 0` = 面朝 −Z（北）。
	# 改朝向时把期望值跟着改，别放宽成「怎么都行」。
	var face_bad := PackedStringArray()
	for cn in ["Chair_N1", "Chair_N2", "Chair_N3"]:
		if int(chair_rot.get(cn, -1)) != 180:
			face_bad.append("%s=%d" % [cn, int(chair_rot.get(cn, -1))])
	for cn in ["Chair_S1", "Chair_S2"]:
		if int(chair_rot.get(cn, -1)) != 0:
			face_bad.append("%s=%d" % [cn, int(chair_rot.get(cn, -1))])
	_check(face_bad.is_empty(),
		"5 把（北排 3 + 南排 1/2）朝向 = 转向 180° 之后的值（北排 180 / 南排 0，背对桌）%s"
			% ("" if face_bad.is_empty() else "：不对的是 " + "、".join(face_bad)))
	# 散漫那把：南排 3 要**离开桌子**（桌岛东南角外面的空地）、还得是斜的。
	# 它坐在桌岛东侧偏北，纯看 z 间隙会得到负值 —— 所以量「椅子中心到桌岛矩形的最短距离」。
	# ⚠ `chair_rot` 已经归一化到 [0,360)（见上面 `posmod`，负数也翻正）—— 所以
	#   「斜摆」= 归一化后的值不在 0 / 180 附近（容许 5° 误差，防浮点）。
	#   当前 `Chair_S3 rot = -65` → 归一化 **295°**（= 作者要的「再顺时针 90°」）。
	var s3_rot: int = int(chair_rot.get("Chair_S3", 0))
	var s3_slanted: bool = absf(s3_rot - 0.0) > 5.0 and absf(s3_rot - 180.0) > 5.0
	var s3_dist := 999.0
	if chair_pos.has("Chair_S3"):
		var cp: Vector3 = chair_pos["Chair_S3"]
		# 桌岛矩形：由两组桌子的中心 ± 半宽/半深现算（桌子挪了这里自动跟着走）。
		var isl_x0: float = desk1_c.x - desk_width * 0.5
		var isl_x1: float = desk1_c.x + desk_width * 0.5
		var isl_z0: float = desk1_n
		var isl_z1: float = desk2_s
		var dx := maxf(maxf(isl_x0 - cp.x, cp.x - isl_x1), 0.0)
		var dz := maxf(maxf(isl_z0 - cp.z, cp.z - isl_z1), 0.0)
		s3_dist = sqrt(dx * dx + dz * dz)
	_check(s3_dist >= 0.25 and s3_slanted,
		"「散漫」的南排 3 确实离开了办公桌：椅心离桌岛 %.3f 米、朝向 %d°（不是正对桌）" % [s3_dist, s3_rot])
	# 北排椅子别撞到北墙落地窗（窗内表面 z=-5.52）。
	var win_hit := PackedStringArray()
	for cn in ["Chair_N1", "Chair_N2", "Chair_N3"]:
		if not chair_pos.has(cn):
			continue
		var n: float = (chair_pos[cn] as Vector3).z - (chair_size[cn] as Vector3).z * 0.5
		if n < -5.52:
			win_hit.append("%s 北沿 %.3f" % [cn, n])
	_check(win_hit.is_empty(),
		"北排椅子没戳进北墙落地窗（窗内表面 z=-5.52）%s"
			% ("" if win_hit.is_empty() else "：撞了 " + "、".join(win_hit)))

	var n_win_left := []
	for e in Models.entries:
		if str(e.get("slot", "")).begins_with("SM_B_Window_N"):
			n_win_left.append(str(e.get("slot", "")))
	_check(n_win_left.is_empty(),
		"北墙那排小窗（SM_B_Window_N1/N2/N3）已从对照表里清干净：%s" % str(n_win_left))

	var idx := Models.models_index()
	var no_place := []
	for m in idx:
		if (idx[m] as Array).is_empty():
			no_place.append(m)
	_check(no_place.is_empty(), "没有孤立模型（做了却没人用）：%s" % str(no_place))

	var used_slots := {}
	var unknown := []
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var nm := str(cur.get_meta("slot", ""))
		if nm == "":
			continue
		used_slots[nm] = true
		if Models.entry(nm).is_empty():
			unknown.append(nm)
	_check(unknown.is_empty(), "场景里的编号全部能在对照表里查到：%s" % str(unknown))
	_check(used_slots.size() == Models.entries.size(),
		"对照表 %d 个位置全部在场景里落地（实到 %d）" % [Models.entries.size(), used_slots.size()])

	var binds := {}
	var dup := []
	for e in Models.entries:
		var b := str(e.get("bind", ""))
		if binds.has(b):
			dup.append(b)
		binds[b] = true
	_check(dup.is_empty(), "没有两个位置绑到同一个对象：%s" % str(dup))

	# 每个探索点、NPC、布景都能通过 bind 查到自己的槽位 —— 明天替换靠的就是这条链路。
	var no_slot := []
	for s in ContentDB.spots:
		if Models.slot_of("spot:" + str(s.get("id", ""))) == "":
			no_slot.append(str(s.get("id", "")))
	for n in ContentDB.npcs:
		if Models.slot_of("npc:" + str(n.get("id", ""))) == "":
			no_slot.append(str(n.get("id", "")))
	for p in ContentDB.room.get("props", []):
		if Models.slot_of("prop:" + str(p.get("name", ""))) == "":
			no_slot.append(str(p.get("name", "")))
	for w in ContentDB.room.get("windows", []):
		if Models.slot_of("window:" + str(w.get("name", ""))) == "":
			no_slot.append("window:" + str(w.get("name", "")))
	for i in range(1, ContentDB.room.get("ceiling_lights", []).size() + 1):
		if Models.slot_of("lamp:%d" % i) == "":
			no_slot.append("lamp:%d" % i)
	_check(no_slot.is_empty(), "探索点 / NPC / 布景 / 窗 / 灯 都能查到槽位：%s" % str(no_slot))

	_check(Models.used.size() + Models.grey.size() == need_places,
		"每个位置都被判定过一次（真模型 %d + 灰盒 %d = %d）"
		% [Models.used.size(), Models.grey.size(), need_places])

	# 被替换的位置，场景里那个节点下面应该真的挂着一个 Model 子节点。
	var no_model := []
	var still_grey := []
	for s in Models.used:
		var host := _slot_node(main, s)
		if _model_of(host) == null:
			no_model.append(s)
		elif _grey(host) != null and _grey(host).visible:
			still_grey.append(s)
	_check(no_model.is_empty(), "换上的真模型真的挂进场景了：%s" % str(no_model))
	_check(still_grey.is_empty(), "有真模型的位置，灰盒方块已经让位：%s" % str(still_grey))

	# 一个模型顶多个位置。⚠ 2026-10-05 晚些原作者删掉 4 盆占位绿植（SM_F_Plant）之后，
	# 这条复用示例改由**工位椅**来演示：3 个模型（Chair_01/02/03）顶 6 个位置。
	# ⛔ 别写死「哪几个槽位用 Chair_01」—— 作者会随机换椅子颜色（S3 那把就换过），
	#   只数「六个位置里有多少个真的挂上了 Model」，再数「一共只用了 3 个不同 glb」。
	var seated := 0
	for cn in ["Chair_N1", "Chair_N2", "Chair_N3", "Chair_S1", "Chair_S2", "Chair_S3"]:
		var h := _slot_node(main, "SM_F_%s" % cn)
		if h != null and h.get_node_or_null("Model") != null:
			seated += 1
	_check(seated == 6, "6 个工位位都挂上了真椅子（实到 %d 个）" % seated)
	var chair_glbs := {}
	for e in Models.entries:
		var sl := str(e.get("slot", ""))
		if sl.begins_with("SM_F_Chair_") and Models.used.has(sl):
			chair_glbs[Models.model_of(sl)] = true
	_check(chair_glbs.size() == 3, "6 个工位椅只用了 3 个 glb（实为 %d 个）—— 复用把工作量压下来了" % chair_glbs.size())

	# 灰盒的碰撞必须留着 —— 走路和点击都靠它。
	var desk := _slot_node(main, "SM_F_DeskBench_01")
	var desk_have_collide := desk != null and desk.get_node_or_null("Collision") != null
	_check(desk_have_collide, "灰盒的碰撞体还在，点击与移动不受影响")
	_check(desk != null and desk.get_node_or_null("Model") != null,
		"三人办公桌（3 连位）真的换上了 SM_F_Desk3P 模型")

	var bench_grey: MeshInstance3D = null
	if desk != null:
		bench_grey = _grey(desk)
	var bw := -1.0
	var bh := -1.0
	var bd := -1.0
	if bench_grey != null and bench_grey.mesh is BoxMesh:
		var bmx: BoxMesh = bench_grey.mesh as BoxMesh
		bw = bmx.size.x
		bh = bmx.size.y
		bd = bmx.size.z
	# 2026-10-06 作者换的「三人办公桌」SM_F_Desk3P：宽 3.862 米（和老的逐位一样）、
	# 高 0.970 米（老 0.994，几乎一样），**但新模型没把椅子做进去** → 进深从 1.517 掉到 0.665。
	_check(absf(bw - 3.86) < 0.06 and absf(bh - 0.97) < 0.06 and absf(bd - 0.665) < 0.06,
		"三人办公桌占位 %.2f×%.2f×%.2f 米（宽×高×深）—— 三个工位连成一排、无椅子" % [bw, bh, bd])

	# ---- 两组工位要「背靠背贴成一个岛」，不是两条各朝各的平行排 ----
	# 模型自带的朝向是「椅子在 -Z 那一侧」，所以：一组不转 = 椅子朝北；另一组转 180° = 椅子朝南。
	# 两组的 z 相差正好一个进深 —— 隔板对隔板、缝隙为 0。
	var desk2 := _slot_node(main, "SM_F_DeskBench_02")
	var rot1 := 0.0
	var rot2 := 0.0
	if desk != null:
		rot1 = desk.rotation_degrees.y
	if desk2 != null:
		rot2 = desk2.rotation_degrees.y
	_check(desk2 != null, "第二组工位桌也在场景里")
	_check(absf(rot1) < 0.01 and absf(absf(rot2) - 180.0) < 0.01,
		"两组的朝向正好相反（%.0f° / %.0f°）—— 椅子甩到岛的外侧两条通道上，不是都朝同一边"
		% [rot1, rot2])

	var island_n := 0.0
	var island_s := 0.0
	var bench_gap := 999.0
	if desk != null and desk2 != null and bd > 0.0:
		var dz := absf(desk2.global_position.z - desk.global_position.z)
		bench_gap = absf(dz - bd)
		island_n = minf(desk.global_position.z, desk2.global_position.z) - bd * 0.5
		island_s = maxf(desk.global_position.z, desk2.global_position.z) + bd * 0.5
	_check(bench_gap < 0.03,
		"两组紧紧贴着：中心距 %.2f 米 = 一个进深，中间缝隙 %.2f 米" % [bd + bench_gap, bench_gap])
	_check(bench_gap < 0.03 and absf(island_s - island_n - bd * 2.0) < 0.03,
		"合起来就是一个岛：南北通长 %.2f 米（= 两个进深），中间没有过道" % (island_s - island_n))

	# 注意：main 声明成 Node3D，main.room_size 是动态属性 —— 这里必须显式写 float，
	# 用 := 推断会报「Cannot infer the type of wall_n」。
	var wall_n: float = -main.room_size.z * 0.5
	_check(island_n - wall_n > 0.5,
		"岛的最北端（含椅子）离北墙还有 %.2f 米 —— 没插进墙里" % (island_n - wall_n))

	# 原来两个 NPC 的灰盒正好站在两组工位之间的中缝上（z = -3.15），两组一贴合，人就卡在两张桌子中间。
	# 现在 NPC 有四个（老板在东南角沙发、外聘设计总监在靠窗人台那边），所以判据不能只看 z ——
	# 必须**同时**落在工位岛那个矩形的 X 和 Z 范围里，才算真的卡在桌子里。
	var island_x0 := 999.0
	var island_x1 := -999.0
	for sname in ["SM_F_DeskBench_01", "SM_F_DeskBench_02"]:
		var nd := _slot_node(main, sname)
		if nd != null:
			island_x0 = minf(island_x0, nd.global_position.x - bw * 0.5)
			island_x1 = maxf(island_x1, nd.global_position.x + bw * 0.5)
	var npc_inside := []
	for n in ContentDB.npcs:
		var np := ContentDB.vec3(n.get("pos"), Vector3.ZERO)
		if np.x > island_x0 and np.x < island_x1 and np.z > island_n and np.z < island_s:
			npc_inside.append("%s(x=%.2f, z=%.2f)" % [str(n.get("id", "")), np.x, np.z])
	_check(npc_inside.is_empty(),
		"没有 NPC 卡在两张桌子中间了（原来两个都站在中缝上）：%s" % str(npc_inside))

	# NPC 之间不许叠在一起 —— 四个人的站位是手填的，很容易改着改着就撞上。
	var ps: float = main.prop_scale
	var npc_overlap := []
	for i in ContentDB.npcs.size():
		var a: Dictionary = ContentDB.npcs[i]
		var ap := ContentDB.vec3(a.get("pos"), Vector3.ZERO)
		var asz := ContentDB.vec3(a.get("size"), Vector3(0.5, 1.3, 0.5)) * ps
		_check(absf(ap.y) < 0.001, "%s 站在地上（y = 0）" % str(a.get("id", "")))
		for j in range(i + 1, ContentDB.npcs.size()):
			var b: Dictionary = ContentDB.npcs[j]
			var bp := ContentDB.vec3(b.get("pos"), Vector3.ZERO)
			var bsz := ContentDB.vec3(b.get("size"), Vector3(0.5, 1.3, 0.5)) * ps
			if absf(ap.x - bp.x) < (asz.x + bsz.x) * 0.5 and absf(ap.z - bp.z) < (asz.z + bsz.z) * 0.5:
				npc_overlap.append("%s × %s" % [str(a.get("id", "")), str(b.get("id", ""))])
	_check(npc_overlap.is_empty(), "四个 NPC 互相不重叠：%s" % str(npc_overlap))

	print("[8b] 交付资产：都挂上了、尺寸对得上、摆放有道理")

	# 尺寸 / 面数容差 —— model_slots 会把对不上的写进 _warnings，这里统一兜住。
	# ⚠ 自检里 main.tscn 会被重开好几遍（换幕 / 重走一遍），每遍都重新 attach 一次，
	#   同一个槽位就会重复告警 N 条。判「有没有问题」之前先按内容去重，别把「重开 3 次」
	#   读成「3 个模型不合格」。
	var mw: Variant = Models.get("_warnings")
	var uniq: Array = []
	if typeof(mw) == TYPE_ARRAY:
		for w in (mw as Array):
			if not uniq.has(w):
				uniq.append(w)
	_check(typeof(mw) == TYPE_ARRAY and uniq.is_empty(),
		"所有真模型的尺寸和面数都在容差内：%s" % str(uniq))

	# 同一件东西的转角**只能写一处**：槽位（model_map 的 rot，转模型）和宿主
	# （objects/room.json 的 rot，转整个方块）是两层，两处都写角度会叠加。
	# 2026-10-05 公告栏就这么背对观众了一次（90 + 90 = 180），尺寸还照样过检 ——
	# 因为 180° 时 x/z 跨度不变，`_check_size` 看不出来。这条专门盯这种「转了两遍」。
	var double_rot: Array = []
	for s in ContentDB.spots:
		var sid := str(s.get("id", ""))
		var sl := Models.slot_of("spot:" + sid)
		if sl == "":
			continue
		if absf(float(s.get("rot", 0.0))) > 0.1 and absf(Models.slot_rot(sl)) > 0.1:
			double_rot.append("探索点 %s（槽位 %s）" % [sid, sl])
	for p in ContentDB.room.get("props", []):
		var pn := str(p.get("name", ""))
		var sl2 := Models.slot_of("prop:" + pn)
		if sl2 == "":
			continue
		if absf(float(p.get("rot", 0.0))) > 0.1 and absf(Models.slot_rot(sl2)) > 0.1:
			double_rot.append("布景 %s（槽位 %s）" % [pn, sl2])
	_check(double_rot.is_empty(), "转角只写了一处（槽位 rot 与宿主 rot 不叠加）：%s" % str(double_rot))

	var delivered := {
		"SM_F_WaterCooler": "饮水机",
		"SM_F_Sofa": "沙发",
		"SM_F_MoneyTree_01": "发财树 1",
		"SM_F_MoneyTree_02": "发财树 2",
		"SM_F_Mannequin_01": "展架 1",
		"SM_F_Mannequin_02": "展架 2",
		"SM_F_Mannequin_03": "展架 3",
		"SM_F_Mannequin_04": "展架 4",
		"SM_F_Sculpture": "雕塑",
		"SM_A_Npc_Feng": "凤凰男",
		"SM_A_Npc_Intern1": "实习 1 号",
		"SM_A_Npc_Boss": "老板",
		"SM_A_Npc_Director": "外聘设计总监",
		"SM_B_Window_Wall_A": "北墙落地窗西扇",
		"SM_B_Window_Wall_B": "北墙落地窗东扇",
		"SM_B_Door_Main": "设计部的玻璃门",
		"SM_F_Carpet": "沙发下的圆形地毯",
		"SM_F_Bar": "吧台",
	}
	var missing := []
	for slot in delivered:
		var host := _slot_node(main, slot)
		if _model_of(host) == null:
			missing.append(str(delivered[slot]))
	_check(missing.is_empty(), "18 件资产全都换上了真模型：缺 %s" % str(missing))

	# 摆放要求（用户原话）：展架散布在靠窗那块空地上、朝向随意；沙发靠墙角；
	# 饮水机在沙发旁边；老板没有在办公，在沙发附近休息；
	# 雕塑「放在房间的角落，和沙发在同一条线的另一个角，靠近窗户那边」（东北角）。
	var sofa := _slot_node(main, "SM_F_Sofa")
	var cooler := _slot_node(main, "SM_F_WaterCooler")
	var boss_node := _slot_node(main, "SM_A_Npc_Boss")
	var sofa_pos := sofa.global_position if sofa != null else Vector3.ZERO

	# ---- 吧台（2026-10-06 作者：「把这个吧台放到沙发附近……位置参考 6」）----
	# 那个 ⑥ 是他拿手写笔圈在「会议椅 3」上的（shots/布置俯视图_作者标注版.png），
	# 反算回世界坐标 x = +5.40，和会议椅 3 的 x 逐位吻合。
	# **2026-10-06 稍后**：作者又说「吧台太小了，放大到长度和地毯直径一样差不多」——
	# 清单改成 `fit width 4.8` **等比**放大 4.332 倍（那时高度跟着到了 2.26 米）。
	# **2026-10-05 再稍后**：作者要「变矮一点，和沙发一样高」→ 加 `stretch 0.560177` **只压高**
	# → **4.80 × 1.266 × 2.08 米**（长度、进深都没动）。
	# 于是从三条变成六条：① 真模型挂上了；② 落在 ⑥ 那个点上；③ 长度 = 地毯直径；
	# ④ 「沙发附近」＝ 不挨着沙发、也不跑远；⑤ 进深 2.08 米没顶到地毯；⑥ 高度 = 沙发高度。
	var bar_node := _slot_node(main, "SM_F_Bar")
	_check(bar_node != null and _model_of(bar_node) != null,
		"吧台真的换上了 SM_F_Bar 模型（原会议区那块空地上）")
	var bar_pos := Vector3.ZERO
	var bar_size := Vector3.ZERO
	var bar_prop := {}
	var sofa_edge_n := 0.0
	var sofa_size_y := 0.0
	var carpet_edge_n := 0.0
	var carpet_dia := 0.0
	for p in ContentDB.room.get("props", []):
		var pd: Dictionary = p
		var nm := str(pd.get("name", ""))
		if nm == "Bar":
			bar_pos = ContentDB.vec3(pd.get("pos"), Vector3.ZERO)
			bar_size = ContentDB.vec3(pd.get("size"), Vector3.ZERO)
			bar_prop = pd
		elif nm == "Sofa":
			var sp := ContentDB.vec3(pd.get("pos"), Vector3.ZERO)
			var ss := ContentDB.vec3(pd.get("size"), Vector3.ZERO)
			sofa_size_y = ss.y
			# 沙发 rot -90 → 本地宽 3.9 落在世界 z 上，本地深 3.211 落在世界 x 上
			sofa_edge_n = sp.z - ss.x * 0.5
		elif nm == "Carpet":
			# 地毯是个正圆，北缘 = 圆心 z − 半径。
			# ⚠ 下面地毯那段里另有 carpet_pos / carpet_size / carpet_r 同名变量，
			# 这里刻意换一套名字 —— GDScript 的 `var` 重名会直接 Parse Error（已踩两次）。
			var bcp := ContentDB.vec3(pd.get("pos"), Vector3.ZERO)
			var bcz := ContentDB.vec3(pd.get("size"), Vector3.ZERO)
			carpet_dia = bcz.x
			carpet_edge_n = bcp.z - bcz.x * 0.5
	_check(absf(bar_pos.x - 5.40) < 0.05 and absf(bar_pos.z - 0.00) < 0.05,
		"吧台落在标注 ⑥ 那个点上（x=%.2f, z=%.2f）—— x 是原会议椅 3 的位置，z 从 0.30 让到 0.00 是给放大后的进深腾地方"
		% [bar_pos.x, bar_pos.z])
	_check(absf(bar_size.x - carpet_dia) < 0.05,
		"吧台长度 %.2f 米 = 地毯直径 %.2f 米（作者原话：「放大到长度和地毯直径一样差不多」）"
		% [bar_size.x, carpet_dia])
	# 2026-10-05 稍后作者要求「把我的吧台建模变矮一点，和沙发一样高就行」——
	# 清单加 `stretch 0.560177`（**一个数字 = 只乘高**，不是等比），长度和进深都没动。
	_check(absf(bar_size.y - 1.266) < 0.05 and absf(bar_size.z - 2.077) < 0.05,
		"吧台尺寸 %.2f×%.2f×%.2f 米（宽×高×深）—— 只压高到 1.266，长度 4.8 / 进深 2.08 都保住了"
		% [bar_size.x, bar_size.y, bar_size.z])
	# ⭐ 新不变量（比写死 1.266 更强）：吧台高度**必须等于沙发高度** —— 以后沙发改高这里自动跟着红。
	_check(sofa_size_y > 0.1 and absf(bar_size.y - sofa_size_y) < 0.02,
		"吧台和沙发一样高（%.3f vs %.3f 米）—— 作者原话「和沙发一样高就行」"
		% [bar_size.y, sofa_size_y])
	var bar_gap := sofa_edge_n - (bar_pos.z + bar_size.z * 0.5)
	_check(bar_gap > 0.2 and bar_gap < 2.0,
		"吧台在沙发附近：南沿离沙发北沿 %.2f 米（既不叠上沙发、也没跑出「附近」）" % bar_gap)
	var bar_carpet_gap := carpet_edge_n - (bar_pos.z + bar_size.z * 0.5)
	_check(bar_carpet_gap > 0.10 and bar_carpet_gap < 2.0,
		"放大后的吧台没有顶到地毯：吧台南沿 z=%.2f、地毯北缘 z=%.2f，净空 %.2f 米"
		% [bar_pos.z + bar_size.z * 0.5, carpet_edge_n, bar_carpet_gap])

	# 和门那条一样的体检：吧台也别长到隔壁家具身上（放大后它有 4.8 米宽 × 2.08 米深，
	# 是**全屋最大的一件**，位置一挪就容易蹭到人 —— 地毯也在这一圈被查）。
	var bar_aabb := _aabb_of(bar_prop)
	var bar_clash := PackedStringArray()
	for src in [["布景", ContentDB.room.get("props", [])], ["探索点", ContentDB.spots], ["NPC", ContentDB.npcs]]:
		for it in (src[1] as Array):
			var d := it as Dictionary
			var nm2 := str(d.get("name", d.get("id", "?")))
			if nm2 == "Bar" or not d.has("size") or not d.has("pos"):
				continue
			var ov := _aabb_overlap(bar_aabb, _aabb_of(d))
			if ov > 0.05:
				bar_clash.append("%s(%s) 叠了 %.2f 米" % [nm2, src[0], ov])
	_check(bar_clash.is_empty(),
		"吧台没和别的布景 / 探索点 / NPC 叠在一起%s"
			% ("：没有" if bar_clash.is_empty() else "：撞上了 " + "、".join(bar_clash)))

	# 「小人」的身高就是后面量比例的那把尺子：用户说展架「有两个小人高」、
	# 雕塑「2.5 个小人高」。这里的小人 = 1.30 米的 NPC。
	var doll_h := 0.0
	for n in ContentDB.npcs:
		var nd: Dictionary = n
		doll_h = maxf(doll_h,
			float(ContentDB.vec3(nd.get("size"), Vector3.ZERO).y) * float(nd.get("scale", 1.0)))
	_check(absf(doll_h - 1.3) < 0.02, "小人身高 %.2f 米 —— 后面按它量展架和雕塑的比例" % doll_h)

	# room.json 的 props 才是摆位的真值（宿主节点的 global_position 也源自它）。
	var mt1_pos := Vector3.ZERO
	var sculpt_pos := Vector3.ZERO
	var sculpt_h := 0.0
	var man_pos := PackedVector3Array()
	var man_yaw := PackedFloat32Array()
	var man_h := 0.0
	for p in ContentDB.room.get("props", []):
		var pd: Dictionary = p
		var nm := str(pd.get("name", ""))
		var ppos := ContentDB.vec3(pd.get("pos"), Vector3.ZERO)
		var psc := float(pd.get("scale", 1.0))
		if nm.begins_with("Mannequin_"):
			man_pos.append(ppos)
			man_yaw.append(float(pd.get("rot", 0.0)))
			man_h = maxf(man_h, float(ContentDB.vec3(pd.get("size"), Vector3.ZERO).y) * psc)
		elif nm == "Sculpture":
			sculpt_pos = ppos
			sculpt_h = float(ContentDB.vec3(pd.get("size"), Vector3.ZERO).y) * psc
		elif nm == "MoneyTree_01":
			mt1_pos = ppos

	_check(man_pos.size() == 4, "陈列角摆了 4 个展架（实为 %d）" % man_pos.size())
	# 「人的 1.5 倍就可以」（作者先说过「两个小人高」，点进游戏发现太高，改回 1.5 倍）
	_check(absf(man_h - doll_h * 1.5) < 0.06,
		"展架高 %.2f 米 = 小人的 %.2f 倍（用户要求 1.5 倍）" % [man_h, man_h / doll_h])

	if man_pos.size() == 4:
		var mnx := 999.0
		var mxx := -999.0
		var mnz := 999.0
		var mxz := -999.0
		var closest := 999.0
		for i in range(4):
			mnx = minf(mnx, man_pos[i].x)
			mxx = maxf(mxx, man_pos[i].x)
			mnz = minf(mnz, man_pos[i].z)
			mxz = maxf(mxz, man_pos[i].z)
			for j in range(i + 1, 4):
				closest = minf(closest, man_pos[i].distance_to(man_pos[j]))
		# 「应该随意的散布在那块空地」—— 东西要拉开，南北也要错开，不能站成一条线。
		# 位置是照作者 2026-10-06 在俯视图上手写的 1/2/3/4 标号复现的，跨度就是 3.3 米。
		_check(mxx - mnx > 2.8, "四个展架东西方向拉开了 %.2f 米" % (mxx - mnx))
		_check(mxz - mnz > 0.8,
			"四个展架南北方向也错开 %.2f 米 —— 不是排成一条直线" % (mxz - mnz))
		# ⚠ 中心距的门槛不能按「看着别挤」拍 —— 这 4 个坐标是作者手写的，本来就密
		# （① 和 ② 的标注只差 1.2 米）。1.25 米是「两个 0.9 米宽的展架转开之后
		# 在 x 或 z 上还能分开」的下限，再严就得改他的标注了，那是本末倒置。
		_check(closest > 1.25, "四个展架互相不挤（最近的两个相距 %.2f 米）" % closest)
		# 「朝向不一样」+ 仍然朝着屋里（180° 才是正对房间，别面壁）。
		var same_yaw := []
		var facing_wall := []
		for i in range(4):
			if man_yaw[i] < 90.0 or man_yaw[i] > 270.0:
				facing_wall.append("%d 号 %.0f°" % [i + 1, man_yaw[i]])
			for j in range(i + 1, 4):
				var d: float = absf(fposmod(man_yaw[i] - man_yaw[j] + 180.0, 360.0) - 180.0)
				if d < 15.0:
					same_yaw.append("%d/%d 号只差 %.0f°" % [i + 1, j + 1, d])
		_check(same_yaw.is_empty(), "四个展架朝向各不相同（两两至少差 15°）：%s" % str(same_yaw))
		_check(facing_wall.is_empty(),
			"四个展架都朝着屋里，没有面壁（rot 都落在 90°~270°）：%s" % str(facing_wall))
		# 还得站在北边那片空地上（这两条是上一轮的要求，不能丢）。
		# 门槛从 z < -3.9 放宽到 z < -2.0：作者这轮把展架往南挪到了 z = -3.40，
		# 「不贴北墙、往房间内部挪」本来就是他要的；-2.0 后面是工位岛的南沿（-2.32），
		# 再往南就越过他说的「办公桌最里面那个边界」了。
		var in_spot := 0
		for i in range(4):
			if man_pos[i].z < -2.0 and man_pos[i].z > -6.0 and man_pos[i].x > island_x1:
				in_spot += 1
		_check(in_spot == 4,
			"四个展架都还在靠北边、工位岛东侧的那块空地上（x > %.2f，%d/4）" % [island_x1, in_spot])

	var sculptor := _slot_node(main, "SM_F_Sculpture")
	_check(sculptor != null and _model_of(sculptor) != null, "雕塑也挂上了真模型")
	# 「黑色雕塑应该有 2.5 个小人高」
	_check(absf(sculpt_h - doll_h * 2.5) < 0.08,
		"雕塑高 %.2f 米 = 小人的 %.2f 倍（用户要求 2.5 个小人高）" % [sculpt_h, sculpt_h / doll_h])
	# 「放在房间的角落……太靠边了，删掉那个褐色桌子，把黑色雕塑移动到那里」。
	# 原 `Reception`（褐色前台桌）在 [6.6, 0, -4.6]；作者在俯视图上圈的是 x≈6.13, z≈-4.39。
	_check(sculpt_pos.x > 5.9 and sculpt_pos.x < 7.1 and sculpt_pos.z < -4.1 and sculpt_pos.z > -5.1,
		"雕塑落在原来那张褐色前台桌那一带（x=%.2f, z=%.2f），不再贴着东北墙角" % [sculpt_pos.x, sculpt_pos.z])
	_check(sculpt_pos.distance_to(mt1_pos) < 2.0,
		"雕塑就在发财树 1 旁边（相距 %.2f 米）" % sculpt_pos.distance_to(mt1_pos))

	# 2026-10-06 作者：「微调一下雕塑的朝向，让它不要面朝沙发，转向朝向门口」。
	# 本轮的门在西墙 (x=-7.88, z=-1.5)，沙发在东南角 (6.394, 4.05)。
	# 雕塑的正面 = 模型本地的 -Z 绕 Y 轴转 rot 之后指的方向 = (-sin rot, 0, -cos rot)。
	var sculpt_rot := 0.0
	var door_pos := Vector3.ZERO
	var sofa_p := Vector3.ZERO
	for p in ContentDB.room.get("props", []):
		var pd2: Dictionary = p
		var nm2 := str(pd2.get("name", ""))
		if nm2 == "Sculpture":
			sculpt_rot = float(pd2.get("rot", 0.0))
		elif nm2 == "Door_Main":
			door_pos = ContentDB.vec3(pd2.get("pos"), Vector3.ZERO)
		elif nm2 == "Sofa":
			sofa_p = ContentDB.vec3(pd2.get("pos"), Vector3.ZERO)
	var face_dir := Vector3(-sin(deg_to_rad(sculpt_rot)), 0.0, -cos(deg_to_rad(sculpt_rot)))
	var flat_self := Vector3(sculpt_pos.x, 0.0, sculpt_pos.z)
	var to_door := (Vector3(door_pos.x, 0.0, door_pos.z) - flat_self).normalized()
	var to_sofa := (Vector3(sofa_p.x, 0.0, sofa_p.z) - flat_self).normalized()
	var ang_door := rad_to_deg(acos(clampf(face_dir.dot(to_door), -1.0, 1.0)))
	var ang_sofa := rad_to_deg(acos(clampf(face_dir.dot(to_sofa), -1.0, 1.0)))
	_check(ang_door < 3.0, "雕塑正面朝着门口（rot %.0f°，与门方向只差 %.2f°）" % [sculpt_rot, ang_door])
	_check(ang_sofa > 50.0, "雕塑不再面朝沙发（与沙发方向差 %.1f°）" % ang_sofa)

	# 落地窗（作者 2026-10-06）：「这个落地窗的高度是遍布一整面墙……优先放在办公桌和人台
	# 那一段的墙上」。等比缩放把宽度定死成 7.78 米。随后作者又说：
	# 「你可以素材复用拼接这个落地窗把整面墙铺满吗」—— 北墙 16 米塞不下第三扇（3 × 7.78 = 23.3），
	# 所以就是 **2 扇并排**：合计 15.56 米，两侧各余 0.22 米（正好藏在墙角），中缝落在 x = 0。
	# **两扇是同一个 SM_B_Window_Wall.glb 的两个实例** —— 素材复用，只多一个槽位、不多一个模型。
	var rsize := ContentDB.vec3(ContentDB.room.get("size"), Vector3(16.0, 4.5, 12.0))
	var room_w := rsize.x
	var room_h := rsize.y
	var win_names := []
	var win_h := 0.0
	var win_min_x := 999.0
	var win_max_x := -999.0
	var win_back_ok := true
	for p in ContentDB.room.get("props", []):
		var pd3: Dictionary = p
		var nm3 := str(pd3.get("name", ""))
		var p3 := ContentDB.vec3(pd3.get("pos"), Vector3.ZERO)
		var s3 := ContentDB.vec3(pd3.get("size"), Vector3.ZERO)
		if nm3.begins_with("Window_Wall"):
			win_names.append(nm3)
			win_h = maxf(win_h, s3.y)
			win_min_x = minf(win_min_x, p3.x - s3.x * 0.5)
			win_max_x = maxf(win_max_x, p3.x + s3.x * 0.5)
			if absf((p3.z - s3.z * 0.5) - (-6.0)) > 0.06:
				win_back_ok = false
	_check(win_names.size() == 2,
		"北墙是 2 扇落地窗并排：%s" % str(win_names))
	_check(absf(win_h - room_h) < 0.05,
		"落地窗高 %.2f 米 = 墙高 %.2f 米（「高度遍布一整面墙」）" % [win_h, room_h])
	_check(Models.model_of("SM_B_Window_Wall_A") != ""
		and Models.model_of("SM_B_Window_Wall_A") == Models.model_of("SM_B_Window_Wall_B"),
		"两扇窗是同一个模型的两个实例（素材复用，不多做一个 glb）")
	var win_span := win_max_x - win_min_x
	_check(win_span > room_w - 0.6,
		"两扇合起来铺满北墙 %.2f 米 / 房宽 %.2f 米" % [win_span, room_w])
	var gap_l := win_min_x + room_w * 0.5
	var gap_r := room_w * 0.5 - win_max_x
	_check(gap_l >= 0.0 and gap_l < 0.25 and gap_r >= 0.0 and gap_r < 0.25,
		"两端只剩一条缝（左 %.3f / 右 %.3f 米 —— 16 米塞不下第三扇的余数）" % [gap_l, gap_r])
	_check(win_back_ok, "两扇窗背面都贴着北墙内表面（-6.00）")
	# ⭐ 2026-10-06 晚 作者：「我写了一下文案，发现只用的上布告栏，白板之类的都可以删掉了」
	#   → 南墙那块白板连 prop 一起删（它一直是灰盒、没出过 glb），墙上只留公告栏。
	#   这里钉住「别被加回来」—— 加回来就是一个没人填文案的悬空可探索点。
	var wb_left := false
	for wbp in ContentDB.room.get("props", []):
		if str((wbp as Dictionary).get("name", "")) == "Whiteboard":
			wb_left = true
	_check(not wb_left, "白板 Whiteboard 已经从 room.json 里删掉了（墙上只留公告栏）")
	# 顺手钉住：房间里的可探索家具再没有一件是**挂在高处**的 —— 白板是最后一个。
	var wall_hang: Array[String] = []
	for whp in ContentDB.room.get("props", []):
		var whe := str((whp as Dictionary).get("explore", ""))
		var whc: Dictionary = whp
		if whe != "" and ContentDB.vec3(whc.get("pos"), Vector3.ZERO).y > 1.0:
			wall_hang.append(whe)
	_check(wall_hang.is_empty(),
		"可探索家具没有一件挂在高处了（挂墙的可探索物件住 objects.json 的探索点，不占 prop）：%s"
		% str(wall_hang))
	# 「让这个落地窗外的蓝天微微发光」—— 看真模型的材质是不是真开着自发光。
	var win_host := _slot_node(main, "SM_B_Window_Wall_A")
	_check(win_host != null and _has_emissive(win_host),
		"落地窗玻璃开着自发光（「让窗外的蓝天微微发光」）")

	# 前台桌必须真的删掉 —— 留着就会和 3.25 米的雕塑叠在一起。
	var reception_left := false
	for p in ContentDB.room.get("props", []):
		if str((p as Dictionary).get("name", "")) == "Reception":
			reception_left = true
	_check(not reception_left, "褐色前台桌 Reception 已经从 room.json 里删掉了")

	# 「可以适当往房间内部移动，但是不要超过办公桌最里面那里的边界」：
	# 往南挪了约 1 米，但展架不能**落进工位岛的矩形范围**里。
	# ⚠ 2026-10-06 换新三人办公桌后，这条不能只比 z 了 —— 新桌子没有椅子、进深从 1.52 掉到
	#    0.665 米，工位岛南沿从 z=-2.32 缩到 -3.60，而展架本来就在岛**东侧**（x 根本不相交）。
	#    所以改成和 NPC 那条一样的 2D 判断：x 和 z 同时落进岛里，才算「挪进办公桌」。
	if man_pos.size() > 0:
		var north_most := 99.0
		var inside_island := []
		for i in range(man_pos.size()):
			north_most = minf(north_most, man_pos[i].z)
			if man_pos[i].x > island_x0 and man_pos[i].x < island_x1 \
					and man_pos[i].z > island_n and man_pos[i].z < island_s:
				inside_island.append("%d 号(x=%.2f, z=%.2f)" % [i + 1, man_pos[i].x, man_pos[i].z])
		_check(inside_island.is_empty(),
			"没有展架落进工位岛（x %.2f~%.2f，z %.2f~%.2f）里：%s"
			% [island_x0, island_x1, island_n, island_s, str(inside_island)])
		_check(north_most > -4.9,
			"最北的展架 z=%.2f 离北墙（-6.0）还有 %.2f 米 —— 不再贴着墙站" % [north_most, north_most + 6.0])

	var sofa_rot := sofa.rotation_degrees.y if sofa != null else 0.0
	_check(sofa != null and sofa_pos.x > 6.3 and sofa_pos.z > 3.9,
		"沙发卡在东南墙角（x=%.2f, z=%.2f）" % [sofa_pos.x, sofa_pos.z])
	# 沙发是 L 形，模型自带的拐角在东北角；rot -90 才能把拐角转到东南墙角。
	_check(absf(sofa_rot + 90.0) < 0.01,
		"沙发转了 %.0f° —— L 的拐角正对东南墙角，长边贴东墙、短边贴南墙" % sofa_rot)
	# 「至少和三个桌子差不多大」：三连工位桌 3.86 米，沙发不能明显小于它。
	var sofa_span := 0.0
	for p in ContentDB.room.get("props", []):
		if str((p as Dictionary).get("name", "")) == "Sofa":
			var sv := ContentDB.vec3((p as Dictionary).get("size"), Vector3.ZERO)
			sofa_span = maxf(sv.x, sv.z)
	_check(sofa_span >= 3.8,
		"沙发最长边 %.2f 米 —— 和三连工位桌（3.86 米）一个量级，没缩成小沙发" % sofa_span)

	# ---- 2026-10-06：地面改成「随机铺的格子砖」----
	# 作者给了 4 张地砖贴图，要求「随机平铺」「一格大概 50 厘米」「不要太糊」。
	# 代码在 main.gd 的 _build_floor_tiles()，参数在 room.json 的 floor_tiles 段。
	# 一张图是 cols × rows 个格子（实测 4 × 6），所以它是**一块「铺块」**而不是能平铺的材质 ——
	# 一块 2.0 × 3.0 米，16 × 12 的地面正好 8 × 4 = 32 块。
	var ft_cfg: Variant = ContentDB.room.get("floor_tiles")
	_check(typeof(ft_cfg) == TYPE_DICTIONARY, "room.json 里有 floor_tiles 配置（地砖贴图）")
	var ft: Dictionary = ft_cfg if typeof(ft_cfg) == TYPE_DICTIONARY else {}
	var ft_cell := float(ft.get("cell", 0.5))
	var ft_cols := maxi(1, int(ft.get("cols", 4)))
	var ft_rows := maxi(1, int(ft.get("rows", 6)))
	var ft_files: Array = ft.get("files", [])
	var tiles := main.get_node_or_null("FloorTiles")
	_check(tiles != null, "场景里生成了 FloorTiles 节点（地面不再是一整块灰盒）")
	var n_tile := tiles.get_child_count() if tiles != null else 0
	var nx_ft := maxi(1, int(round(rsize.x / (ft_cell * ft_cols))))
	var nz_ft := maxi(1, int(round(rsize.z / (ft_cell * ft_rows))))
	_check(n_tile == nx_ft * nz_ft, "地面铺了 %d 块（%d × %d）" % [n_tile, nx_ft, nz_ft])
	var cell_w := 0.0
	var cell_d := 0.0
	var used_tex := {}
	var cover_min := Vector2(999.0, 999.0)
	var cover_max := Vector2(-999.0, -999.0)
	for fti in (tiles.get_children() if tiles != null else []):
		var ftmi := fti as MeshInstance3D
		if ftmi == null or not (ftmi.mesh is PlaneMesh):
			continue
		var ftpsz: Vector2 = (ftmi.mesh as PlaneMesh).size
		cell_w = ftpsz.x / float(ft_cols)
		cell_d = ftpsz.y / float(ft_rows)
		var ftsm := ftmi.material_override as StandardMaterial3D
		if ftsm != null and ftsm.albedo_texture != null:
			used_tex[ftsm.albedo_texture.resource_path] = true
		cover_min.x = minf(cover_min.x, ftmi.position.x - ftpsz.x * 0.5)
		cover_min.y = minf(cover_min.y, ftmi.position.z - ftpsz.y * 0.5)
		cover_max.x = maxf(cover_max.x, ftmi.position.x + ftpsz.x * 0.5)
		cover_max.y = maxf(cover_max.y, ftmi.position.z + ftpsz.y * 0.5)
	_check(absf(cell_w - ft_cell) < 0.02 and absf(cell_d - ft_cell) < 0.02,
		"一格 %.3f × %.3f 米 ≈ 50 厘米（作者要求「格子大小大概 50cm」）" % [cell_w, cell_d])
	_check(used_tex.size() >= 3,
		"%d 张贴图随机用上了 %d 张 —— 不是一张图铺到底" % [ft_files.size(), used_tex.size()])
	_check(cover_min.x <= -rsize.x * 0.5 + 0.01 and cover_max.x >= rsize.x * 0.5 - 0.01
		and cover_min.y <= -rsize.z * 0.5 + 0.01 and cover_max.y >= rsize.z * 0.5 - 0.01,
		"地砖铺满整间、边上没留缝（x %.2f~%.2f / z %.2f~%.2f，房间 %.1f × %.1f）"
		% [cover_min.x, cover_max.x, cover_min.y, cover_max.y, rsize.x, rsize.z])
	# 上面铺了砖，原来那块灰盒地面就必须关掉渲染 —— 两张面都在 y=0，不关会 z-fighting 闪。
	var floor_grey_off := false
	var floor_bodies := main.get_tree().get_nodes_in_group("floor")
	for fbd in floor_bodies:
		var fbmi := (fbd as Node).get_node_or_null("Greybox") as MeshInstance3D
		if fbmi != null and fbmi.layers == 0:
			floor_grey_off = true
	_check(floor_grey_off, "灰盒地面的网格已关掉渲染（只留碰撞体，地砖不会闪）")

	# ---- 2026-10-06：沙发底下的圆形地毯 ----
	# 作者原话「这是我做的地毯，应该在沙发底下，你调整它的大小，使其应该比沙发大」。
	# 模型本身是 1.190 米直径的**正圆**、厚 0.084 米 —— 等比放大到 4.8 米，所以能写死这几条：
	#   ① 直径 > 沙发最长边（「应该比沙发大」）；
	#   ② 是正圆（等比缩放不会把圆压成椭圆）；
	#   ③ 躺着的地毯不穿墙（东切点 ≤ 8.00、南切点 ≤ 6.00）；
	#   ④ 从沙发朝屋里的那两侧探出来 —— 这才叫「铺在沙发底下」；
	#   ⑤ 它没有碰撞体（只有 34 厘米厚的平铺物，加了碰撞盒玩家会被劝在边上绕）。
	var carpet_nm := ""
	var carpet_pos := Vector3.ZERO
	var carpet_size := Vector3.ZERO
	var carpet_collide := 999.0
	var sofa_wx := 0.0	# 沙发在世界 x 方向的跨度（rot -90 → 和模型 size 交换）
	var sofa_wz := 0.0
	for p in ContentDB.room.get("props", []):
		var pc: Dictionary = p
		var pnm := str(pc.get("name", ""))
		var csz := ContentDB.vec3(pc.get("size"), Vector3.ZERO)
		if pnm == "Carpet":
			carpet_nm = pnm
			carpet_pos = ContentDB.vec3(pc.get("pos"), Vector3.ZERO)
			carpet_size = csz
			carpet_collide = float(pc.get("collide", -1.0))
		elif pnm == "Sofa":
			sofa_wx = csz.z
			sofa_wz = csz.x
	_check(carpet_nm != "", "沙发底下铺了一张地毯（props 里有 Carpet）")
	var carpet_r := carpet_size.x * 0.5
	_check(carpet_size.x > sofa_span + 0.3,
		"地毯直径 %.2f 米 > 沙发最长边 %.2f 米 —— 「应该比沙发大」" % [carpet_size.x, sofa_span])
	_check(absf(carpet_size.x - carpet_size.z) < 0.05,
		"地毯还是正圆（%.2f × %.2f）—— 等比放大没有把圆压成椭圆" % [carpet_size.x, carpet_size.z])
	_check(carpet_pos.x + carpet_r <= 8.01 and carpet_pos.z + carpet_r <= 6.01,
		"地毯没穿墙（东切点 %.2f ≤ 8.00，南切点 %.2f ≤ 6.00）" % [carpet_pos.x + carpet_r, carpet_pos.z + carpet_r])
	var sofa_west := sofa_pos.x - sofa_wx * 0.5
	var sofa_north := sofa_pos.z - sofa_wz * 0.5
	_check(carpet_pos.x - carpet_r < sofa_west - 0.3,
		"地毯从沙发西侧探出 %.2f 米" % [sofa_west - (carpet_pos.x - carpet_r)])
	_check(carpet_pos.z - carpet_r < sofa_north - 0.3,
		"地毯从沙发北侧探出 %.2f 米" % [sofa_north - (carpet_pos.z - carpet_r)])
	_check(is_zero_approx(carpet_collide),
		"地毯写了 collide 0 = 不要碰撞体（本来就只有 %.2f 米厚，加了玩家会被劝在边上绕）" % carpet_size.y)
	var carpet_node := _slot_node(main, "SM_F_Carpet")
	_check(carpet_node != null and carpet_node.get_node_or_null("Collision") == null,
		"地毯场景节点里真的没有 Collision —— 玩家能直接踩上去")
	# 「地毯有点太厚了，稍微把它调薄一点」—— 2026-10-06 给归一化加了只压高度的 squash 0.55，
	# 厚 0.339 → 0.187 米。⚠ 这事**不能靠 target 改**：target 是等比缩放，一改直径也跟着变，
	# 而 4.8 米那个直径是专门按沙发定过的。区间卡得松一点，只验「明显薄了」。
	_check(carpet_size.y > 0.10 and carpet_size.y < 0.25,
		"地毯压薄了（厚 %.3f 米，原来 0.339 —— 只压高度、直径没动）" % carpet_size.y)

	var cooler_pos := cooler.global_position if cooler != null else Vector3.ZERO
	var cooler_rot := cooler.rotation_degrees.y if cooler != null else 0.0
	var cooler_gap := cooler.global_position.distance_to(sofa_pos) if cooler != null else 999.0
	_check(cooler != null and cooler_gap < 3.0,
		"饮水机就在沙发旁边（离沙发 %.2f 米）" % cooler_gap)
	_check(absf(cooler_rot - 180.0) < 0.01,
		"饮水机转了 %.0f° —— 出水口朝屋里，不是背对房间" % cooler_rot)
	# 「把饮水机调高 50cm」—— 模型等比归一化到 1.60 米（原 1.10，系数 1.4545）。
	# 只验高度；长宽是等比带出来的（0.525 × 0.502），不该单独去改。
	var cooler_size := Vector3.ZERO
	for p in ContentDB.room.get("props", []):
		if str((p as Dictionary).get("name", "")) == "WaterCooler":
			cooler_size = ContentDB.vec3((p as Dictionary).get("size"), Vector3.ZERO)
	_check(absf(cooler_size.y - 1.6) < 0.02,
		"饮水机调高了 50 厘米（高 %.2f 米，原 1.10；长宽等比跟到 %.2f × %.2f）"
		% [cooler_size.y, cooler_size.x, cooler_size.z])
	# 「颜色灰度调小，变得更白一点」—— 走 prop 的 tint，给模型材质盖一层提亮的 albedo。
	_check(_has_tint(cooler),
		"饮水机的材质被提亮了（tint gain > 1 —— 「灰度调小，变得更白一点」）")

	var boss_gap := boss_node.global_position.distance_to(sofa_pos) if boss_node != null else 999.0
	_check(boss_node != null and boss_gap < 2.6,
		"老板在沙发附近（离沙发 %.2f 米），没在自己工位" % boss_gap)

	# ---- 2026-10-05：NPC 待机动作与互动 ----
	# 4 个角色都是「单张静态网格、没有骨骼」，动作全靠代码程序化演出来。
	# 这里验四件事：枢轴挂上了 / 真的在动 / 四个人不同步 / 走近会转头、点了会一顿。
	print("[8c] NPC 待机动作与互动")

	var no_pivot := []
	for nid in main._npc_nodes:
		if main._npc_pivot.get(nid, null) == null:
			no_pivot.append(nid)
	_check(no_pivot.is_empty(),
		"四个 NPC 都挂了「脚底枢轴」—— 动作只动它，碰撞体一点不动：%s" % str(no_pivot))

	# 等几帧，看枢轴真的在动（位置 + 转角一起量）
	var pv: Node3D = main._npc_pivot["feng"]
	# 显式标类型：_npc_nodes 是 Dictionary，直接点属性推不出类型，GDScript 会 Parse Error。
	var feng_host: Node3D = main._npc_nodes["feng"]
	var y0 := pv.position.y
	var z0 := pv.rotation.z
	for i in range(25):
		await get_tree().process_frame
	var drift := absf(pv.position.y - y0) + absf(pv.rotation.z - z0)
	_check(drift > 0.0005,
		"待机动作真的在动（25 帧里起伏+摇晃共变化 %.5f）" % drift)

	# ⚠ 本轮核心回归：**脚不许离地**。
	# 上一版把呼吸做成「枢轴 position.y ±2 厘米」，整只脚跟着一起上下 ——
	# 作者原话「一靠近像气球一样飘起来了」。
	# 现在呼吸只走 scale（枢轴在鞋底，缩放是从脚往上涨），
	# position.y 只允许**往下沉**。所以：脚底高度几乎不变，而且永远不高于静止值。
	var feng_style: Dictionary = main._npc_style["feng"]
	main.has_target = false
	main.player.global_position = feng_host.global_position + Vector3(0.0, 0.0, 1.2)
	await _wait_until(func() -> bool: return absf(float(main._npc_look["feng"])) > deg_to_rad(30.0), 600)
	var foot_lo := INF
	var foot_hi := -INF
	var rise := -INF
	for i in range(150):
		await get_tree().process_frame
		var fb := _vis_bounds(feng_host)
		foot_lo = minf(foot_lo, fb.x)
		foot_hi = maxf(foot_hi, fb.x)
		var dy := pv.position.y - float(feng_style["base_y"])
		rise = maxf(rise, dy)
	_check((foot_hi - foot_lo) < 0.008,
		"站在身边时脚底一共只动 %.1f 毫米 —— 不再像气球一样浮起来（上一版 25 毫米）"
		% ((foot_hi - foot_lo) * 1000.0))
	_check(rise <= 0.0005,
		"枢轴从不往上抬（最高只到静止位 %+.2f 毫米）—— 只会往下沉，不会离地"
		% (rise * 1000.0))

	# 相位不同才不会像三胞胎同步做操
	var ph_feng := float(main._npc_style["feng"]["ph"])
	var ph_boss2 := float(main._npc_style["boss"]["ph"])
	_check(absf(ph_feng - ph_boss2) > 0.05,
		"每个人的动作相位不同（凤凰男 %.2f / 老板 %.2f）" % [ph_feng, ph_boss2])
	# 老板陷在沙发里休息，节奏要明显比别人慢
	_check(float(main._npc_style["boss"]["breath"]) < float(main._npc_style["feng"]["breath"]),
		"老板的呼吸幅度比别人小（%.3f < %.3f 米）—— 他是在休息，不是在站着"
		% [float(main._npc_style["boss"]["breath"]), float(main._npc_style["feng"]["breath"])])

	# 灵敏度：**渐入**。远了几乎不转，走近了才慢慢转 ——
	# 上一版是一进 3.6 米就直接怼到 120°（整个人瞬间拧过去，看着就是「飘」）。
	main.player.global_position = feng_host.global_position + Vector3(0.0, 0.0, 3.6)
	await _wait_until(func() -> bool: return absf(float(main._npc_look["feng"])) < deg_to_rad(6.0), 900)
	var far_deg := rad_to_deg(absf(float(main._npc_look["feng"])))
	_check(far_deg < 6.0,
		"站在 3.6 米外几乎不转头（%.1f°）—— 上一版在这个距离已经猛拧到 116°" % far_deg)

	# 走进 2.4 米（转头范围）才转
	main.player.global_position = feng_host.global_position + Vector3(0.0, 0.0, 1.6)
	await _wait_until(func() -> bool: return absf(float(main._npc_look["feng"])) > deg_to_rad(30.0), 900)
	var look_deg := rad_to_deg(absf(float(main._npc_look["feng"])))
	_check(look_deg > 30.0, "走近到 1.6 米才转头看你（转了 %.0f°）" % look_deg)

	main.player.global_position = Vector3(5.0, 0.0, 4.0)
	await _wait_until(func() -> bool: return absf(float(main._npc_look["feng"])) < 0.15, 900)
	_check(absf(float(main._npc_look["feng"])) < 0.15,
		"走开之后头会转回原来朝的方向（剩 %.1f°）" % rad_to_deg(absf(float(main._npc_look["feng"]))))
	main.player.global_position = Vector3(-6.8, 0.0, -1.5)

	print("[8d] 头顶的二次元思考框")
	var no_bub := []
	for nid in main._npc_nodes:
		if main._npc_bubbles.get(nid, null) == null:
			no_bub.append(nid)
	_check(no_bub.is_empty(), "四个 NPC 头顶都挂了思考框：%s" % str(no_bub))

	var fbub: Variant = main._npc_bubbles.get("feng", null)
	main.player.global_position = feng_host.global_position + Vector3(0.0, 0.0, 5.0)
	await _wait_until(func() -> bool: return float(fbub.progress()) <= 0.0, 600)
	_check(float(fbub.progress()) <= 0.001,
		"站远了思考框自己收回去（进度 %.2f）" % float(fbub.progress()))

	main.player.global_position = feng_host.global_position + Vector3(0.0, 0.0, 1.2)
	await _wait_until(func() -> bool: return float(fbub.progress()) >= 0.999, 600)
	_check(float(fbub.progress()) >= 0.999,
		"走近了思考框自动弹出来（进度 %.2f）" % float(fbub.progress()))

	# 弹出范围来自 JSON，不是写死在代码里
	_check(absf(float(main._bubble_global.get("range", -1.0)) - 2.6) < 0.01,
		"弹出距离读的是 objects.json 的 _bubble.range = %.1f 米" % float(main._bubble_global.get("range", -1.0)))
	# ---- 框里那句话：一人一句、每轮一份，文案住 act1.json 的 rounds[].idle_lines ----
	print("[8d-1] 头顶思考框里的话（一人一句 · 每轮一份）")
	var POOL := ["不想加班", "好倒霉", "发生什么了？", "老板还好吗？", "怎么会这样", "摸鱼中...."]
	var idle_missing := []
	var used := {}
	for ri in range(ContentDB.round_count()):
		for nid in main._npc_nodes:
			var ln := ContentDB.round_idle_line(ri, nid)
			if ln == "":
				idle_missing.append("R%d/%s" % [ri + 1, nid])
			used[ln] = true
	_check(idle_missing.is_empty(),
		"每一轮四个小人头顶都排了一句话（共 %d 个坑）：%s"
		% [ContentDB.round_count() * main._npc_nodes.size(),
			"全齐" if idle_missing.is_empty() else str(idle_missing)])
	var off_pool := []
	for k in used:
		if not POOL.has(str(k)):
			off_pool.append(str(k))
	_check(off_pool.is_empty() and used.size() == POOL.size(),
		"用的就是作者给的那 6 句、且一句不落（实际用了 %d 句）：%s"
		% [used.size(), "全在池子里" if off_pool.is_empty() else str(off_pool)])

	# 真的挂到框上了（不是只躺在 JSON 里）：现在这一轮，四个框的文本 == 表里那四句
	var mismatch := []
	for nid in main._npc_nodes:
		var bub5: Variant = main._npc_bubbles.get(nid, null)
		if bub5 == null:
			mismatch.append("%s 没框" % nid)
			continue
		var want := ContentDB.round_idle_line(main.round_idx, nid)
		if str(bub5.text_of()) != want:
			mismatch.append("%s 框里是「%s」该是「%s」" % [nid, str(bub5.text_of()), want])
	_check(mismatch.is_empty(),
		"四个框里挂的就是本轮表里那四句：%s"
		% ("全对" if mismatch.is_empty() else str(mismatch)))

	# ⛔ 字得**真的画出来**。中文最坑的一条：Label3D 的默认字体没有汉字 ——
	#   「文本非空、Label3D 可见」全过，屏幕上却一个字都没有（不报错、不报缺字）。
	#   所以这里两条都要：① 接了字体且这个字体**认得汉字**；② 弹出来时 Label3D 真的可见。
	main.player.global_position = feng_host.global_position + Vector3(0.0, 0.0, 1.2)
	await _wait_until(func() -> bool: return float(fbub.progress()) >= 0.999, 600)
	var lbl := fbub.get_node_or_null("Text") as Label3D
	_check(lbl != null and lbl.font != null,
		"框里的字接了字体（默认字体没有汉字，不接就是一片空白）")
	var has_cjk := lbl != null and lbl.font != null and lbl.font.has_char(0x4E0D)   # 「不」
	_check(has_cjk, "这个字体认得汉字（试了「不」U+4E0D）—— 否则整句会变空白")
	_check(lbl != null and lbl.visible and lbl.text != "",
		"弹出来之后框里的字是真可见的（「%s」visible=%s）"
		% ["" if lbl == null else lbl.text, "?" if lbl == null else str(lbl.visible)])

	# 轮末刷新**真的**换话：把轮次搬到「另一个轮」，四个框的文本必须跟着变，再搬回来。
	# ⚠ 别硬编成第 2 轮 —— 前面 [4] 那组用例跑完时 round_idx 已经停在 1 了，
	#   再赋一次 1 等于没换，判据会「永远 FAIL」（第一次就是这么翻的车）。
	var said_before := []
	for nid in main._npc_nodes:
		var bbv: Variant = main._npc_bubbles.get(nid, null)
		said_before.append("" if bbv == null else str(bbv.text_of()))
	var keep_round: int = main.round_idx
	var other_round: int = (keep_round + 1) % ContentDB.round_count()
	main.round_idx = other_round
	main._apply_idle_lines()
	var said_after := []
	var changed := 0
	for nid in main._npc_nodes:
		var bbw: Variant = main._npc_bubbles.get(nid, null)
		said_after.append("" if bbw == null else str(bbw.text_of()))
		if said_after[said_after.size() - 1] != said_before[said_after.size() - 1]:
			changed += 1
	main.round_idx = keep_round
	main._apply_idle_lines()
	_check(changed == main._npc_nodes.size(),
		"轮到下一轮头顶的话真的换了（4 个人换了 %d 个）：第 %d 轮 %s → 第 %d 轮 %s"
		% [changed, keep_round + 1, str(said_before), other_round + 1, str(said_after)])

	# 弹出来之后得**真的可见、真的有大小、贴图真的是画出来的**，
	# 不是「标记成该弹了」而已。贴图是运行时按参数现画的，画空了这里就得报。
	var art := fbub.get_node_or_null("Art") as Sprite3D
	var art_scale := -1.0
	if art != null:
		art_scale = art.scale.x
	_check(art != null and art.visible and art_scale > 0.9,
		"弹出来之后是真的可见、尺寸也到位（scale %.2f）" % art_scale)
	var lit := 0
	var tex_img: Image = null
	if art != null and art.texture is ImageTexture:
		tex_img = (art.texture as ImageTexture).get_image()
	var tw := 0
	var th := 0
	if tex_img != null:
		tw = tex_img.get_width()
		th = tex_img.get_height()
		for yy in range(0, th, 4):
			for xx in range(0, tw, 4):
				if tex_img.get_pixel(xx, yy).a > 0.5:
					lit += 1
	_check(tex_img != null and lit > 300,
		"思考框的贴图是真画出来的（%d×%d，抽样有 %d 个不透明像素）" % [tw, th, lit])

	# ---- 四个人的形状各不一样（参考图第一列那四个）----
	print("[8e] 四个人的思考框形状")
	var want_style := {
		"feng": "spike", "intern1": "box_tail",
		"boss": "cloud", "director": "panel_tail",
	}
	var bad_style := []
	var h_lo := 99.0
	var h_hi := 0.0
	var solids := []
	for nid in want_style:
		var bb2: Variant = main._npc_bubbles.get(nid, null)
		if bb2 == null:
			bad_style.append("%s 没挂上" % nid)
			continue
		var got := str(bb2.style_of())
		if got != str(want_style[nid]):
			bad_style.append("%s 是 %s（该是 %s）" % [nid, got, want_style[nid]])
		var ah := float(bb2.art_height())
		h_lo = minf(h_lo, ah)
		h_hi = maxf(h_hi, ah)
		var sp2 := (bb2 as Node3D).get_node_or_null("Art") as Sprite3D
		if sp2 != null and sp2.texture is ImageTexture:
			solids.append(_solid_count((sp2.texture as ImageTexture).get_image(), 6))
	_check(bad_style.is_empty(),
		"四个人的形状就是参考图第一列那四个（星芒 / 方框+尾巴 / 云朵+射线 / 斜格面板）：%s"
		% ("全对" if bad_style.is_empty() else str(bad_style)))
	_check(solids.size() == 4 and _uniq_count(solids) == 4,
		"四张形状贴图互不相同（不透明抽样 %s）—— 不是四个人共用一个形状" % str(solids))
	_check(h_lo > 0.45 and h_hi < 0.85 and h_hi / maxf(0.001, h_lo) < 1.4,
		"四个框是一个量级（%.2f~%.2f 米，最大/最小 %.2f）" % [h_lo, h_hi, h_hi / maxf(0.001, h_lo)])
	# 形状在头**上面**：形状最低那点必须高过头顶（宿主半高 0.65），否则框会糊在脸上
	var below := []
	for nid in want_style:
		var bb4: Variant = main._npc_bubbles.get(nid, null)
		if bb4 == null:
			continue
		var got_b := float(bb4.art_bottom())
		if got_b < 0.66:
			below.append("%s %.2f" % [nid, got_b])
	_check(below.is_empty(), "框的下沿都在头顶之上（%s）"
		% ("都合格，最低 0.70 米 > 半身高 0.65" if below.is_empty() else str(below)))

	# 近一点的那张脸朝向：模型是静态网格，只能整只转。角度上限别太夸张。
	main.player.global_position = Vector3(-6.8, 0.0, -1.5)

	# 被点会「一顿」，然后自己收回去
	main._npc_nudge("feng")
	_check(float(main._npc_react["feng"]) > 0.9, "点 NPC 会「一顿」")
	await _wait_until(func() -> bool: return float(main._npc_react["feng"]) <= 0.0, 600)
	_check(float(main._npc_react["feng"]) <= 0.0, "「一顿」之后会自己回到待机")
	# 「一顿」也不许把人弹起来（上一版这里是 +4.5 厘米的跳）
	var pv2: Node3D = main._npc_pivot["feng"]
	main._npc_nudge("feng")
	var jump := -INF
	for i in range(40):
		await get_tree().process_frame
		jump = maxf(jump, pv2.position.y - float(feng_style["base_y"]))
	_check(jump <= 0.0005,
		"被点「一顿」也不会把人弹起来（最高 %+.2f 毫米，只会往下坐）" % (jump * 1000.0))
	await _wait_until(func() -> bool: return float(main._npc_react["feng"]) <= 0.0, 600)

	# 回归：枢轴插进来之后 _grey() 一度找不到灰盒，把整个自检搞崩过。这里盯住。
	var ans_before: int = main.answered.size()
	main._open_npc("feng")
	await get_tree().process_frame
	_check(main.hud.modal_visible, "点小人仍然能弹出面板 —— 加动画没把交互弄坏")
	_check(main.hud._title.text == ContentDB.explorable_name("feng"),
		"弹的还是他本人那张卡（实到「%s」）" % main.hud._title.text)
	main.hud.close_modal()
	_check(main.answered.size() == ans_before, "只是弹卡片，没有替玩家答题")

	print("[9] 房间外壳：有天花板，抬头只看得到室内")
	var rs: Vector3 = main.room_size
	_check(rs.x >= 14.0 and rs.z >= 10.0, "房间 %.0f×%.0f 米、层高 %.1f 米 —— 够大" % [rs.x, rs.z, rs.y])
	_check(rs.x * rs.z >= 150.0, "可用面积 %.0f 平方米" % (rs.x * rs.z))

	# 天花板回来了 —— 视角能抬头，所以必须有一块顶把上方封住。
	var ceil_node := _slot_node(main, "SM_B_Ceiling")
	_check(ceil_node != null, "天花板存在 —— 抬头看到的是一块顶，不是天空、也不是建模边界")
	if ceil_node != null:
		var ccs := ceil_node.get_node_or_null("Collision") as CollisionShape3D
		var cb: BoxShape3D = null
		if ccs != null:
			cb = ccs.shape as BoxShape3D
		_check(cb != null and cb.size.x > rs.x and cb.size.z > rs.z,
			"天花板比四面墙还大一圈 —— 贴到墙边抬到头也露不出缝")
		_check(absf(ceil_node.global_position.y - (rs.y + 0.1)) < 0.05,
			"天花板盖在 %.1f 米高，正好压住墙面顶端" % rs.y)

	_check(main.pitch_max > 0.0,
		"视角能往上抬（pitch 上限 +%.0f°）—— 抬得到天花板" % main.pitch_max)
	var fov_half: float = main.camera.fov * 0.5
	# 贴到墙边时，打中墙顶需要的仰角 ≈ atan((墙高 - 相机高) / 最近水平距离)。
	# 只要「pitch 上限 + 半视场」比这个角小，抬到头也翻不出房间。
	var nearest := 0.36
	var blind := rad_to_deg(atan((rs.y - main.eye_height) / nearest))
	_check(main.pitch_max + fov_half < blind,
		"抬到头也只 %.1f°（pitch 上限 %.0f° + 半视场 %.1f°），打不到 %.0f° 的墙顶 —— 翻到房间外面去" % [
			main.pitch_max + fov_half, main.pitch_max, fov_half, blind])
	_check(rs.y > main.eye_height,
		"墙（%.1f 米）比相机（%.2f 米）高 —— 水平视线打到的永远是墙" % [rs.y, main.eye_height])
	_check(main.pitch < 0.0, "默认是俯视（pitch %.0f°）—— 主角比 NPC 高，不会面对面" % main.pitch)
	_check(main.eye_height > 2.2,
		"相机 %.2f 米，比小人（1.30 米）高一倍多 —— 高高在上的神器视角" % main.eye_height)

	var short_walls := []
	for w in ContentDB.room.get("walls", []):
		if float(w["size"][1]) < rs.y - 0.01:
			short_walls.append(str(w["name"]))
	_check(short_walls.is_empty(),
		"四面墙都是满高 %.1f 米，没有半高挡板：%s" % [rs.y, str(short_walls)])

	_check(Models.slot_of("builtin:Base") == "", "玩具箱底座已移除 —— 不是看微缩模型，是站在房间里")
	# ⭐ 2026-10-06 更晚：作者指着截图「就是沙发靠着的那面墙上的两个灰块」（= 东墙 E1/E2
	#   那两扇没出过 glb 的灰盒窗）→ `windows` 数组清空，全屋只剩北墙那两扇真落地窗。
	var east_win_left: Array = ContentDB.room.get("windows", [])
	_check(east_win_left.is_empty(),
		"东墙那两扇灰盒窗已经删干净（windows 数组现在是空的，实为 %d 项）"
		% east_win_left.size())
	# 顺手钉住：全屋的「发光窗面」只剩北墙那两扇 prop 落地窗 —— 再没有别的灰盒窗板冒出来。
	var glow_win := 0
	for pw in ContentDB.room.get("props", []):
		if str((pw as Dictionary).get("name", "")).begins_with("Window_Wall"):
			glow_win += 1
	_check(glow_win == 2,
		"发光窗面只剩北墙那 2 扇落地窗（实为 %d 扇）—— 删掉灰盒窗后屋里不会变暗" % glow_win)

	# 主角不做建模：玩家节点下不该有任何可见网格，对照表里也不该有它的位置。
	var pmesh: Array[MeshInstance3D] = main._mesh_list(main.player)
	_check(pmesh.is_empty(), "主角没有任何可见网格（低头也看不到自己）—— 实为 %d 个" % pmesh.size())
	_check(Models.slot_of("builtin:Player") == "", "主角没有建模槽位 —— 对照表里找不到它")
	_check(main.player.get_node_or_null("Collision") != null, "只留碰撞体，走路和相机跟随不受影响")

	# 整组工位桌的碰撞只做到桌面高度 —— 桌面上摆的探索点必须露在碰撞体外面，
	# 否则射线从 3 米高的相机打下来，会先撞到灰盒碰撞体，永远点不到那个探索点。
	var desk_node := _slot_node(main, "SM_F_DeskBench_01")
	var desk_h := -1.0
	var desk_top := -1.0
	if desk_node != null:
		var dcs := desk_node.get_node_or_null("Collision") as CollisionShape3D
		var dbb: BoxShape3D = null
		if dcs != null:
			dbb = dcs.shape as BoxShape3D
		if dbb != null:
			desk_h = dbb.size.y
			desk_top = desk_node.global_position.y + dcs.position.y + dbb.size.y * 0.5
	_check(absf(desk_h - 0.6) < 0.02,
		"工位桌的碰撞只做到桌面（%.2f 米高）—— 上半截隔板不挡射线" % desk_h)

	var spot_ok := true
	var spot_y := -1.0
	for s in ContentDB.spots:
		var sp := ContentDB.vec3(s.get("pos"), Vector3.ZERO)
		if sp.y > 0.3 and sp.y < 1.2:
			spot_y = sp.y
			if sp.y < desk_top - 0.02:
				spot_ok = false
	_check(spot_ok,
		"桌面上的探索点（y = %.2f 米）没被碰撞体埋掉（碰撞顶面 %.2f 米）" % [spot_y, desk_top])

	var npc_box := _grey(main._npc_nodes["feng"])
	var npc_h := -1.0
	if npc_box != null and npc_box.mesh is BoxMesh:
		npc_h = (npc_box.mesh as BoxMesh).size.y
	_check(absf(npc_h - 1.30) < 0.03,
		"NPC 是 1.30 米高 —— 作者反馈「我的小人建模有点小」，从 1.04 提上来的（现在 %.2f 米）" % npc_h)

	var door_box := _grey(_slot_node(main, "SM_B_Door_Main"))
	var door_h := -1.0
	var door_w := -1.0
	if door_box != null and door_box.mesh is BoxMesh:
		door_h = (door_box.mesh as BoxMesh).size.y
		door_w = (door_box.mesh as BoxMesh).size.x
	# 2026-10-06 作者先「把门也拉高一点，拉高 80cm」→ 2.5 → 3.30 米；
	# 再「不要只拉长，还应该拉宽一点，拉宽 80cm 左右」→ 4.627 → 5.427 米。
	# 两次都只动**一个维度**：归一化里的 `stretch: [1.1729, 1.0, 1.32]` 逐轴各乘各的。
	# ⛔ 直接把 target 写大是**等比缩放**：改高会带得宽一起涨（会到 6.11 米），
	#    改宽又会把高一起带跑 —— 所以门这两维必须分开调，这条断言就是钉住这件事。
	_check(absf(door_h - 3.30) < 0.03,
		"门拉高了 80cm（%.2f 米）—— 整屋的尺度参照，不跟着 prop_scale 缩" % door_h)
	_check(absf(door_w - 5.427) < 0.03,
		"门又拉宽了 80cm（%.2f 米）—— 宽度是四扇通铺带出来的，这次单独加了" % door_w)
	_check(absf(door_h / door_w - 3.30 / 5.427) < 0.01,
		"门的高宽比 %.3f 就是「先高 80 再加宽 80」的结果，没被等比放大带跑" % (door_h / door_w))

	# 门一变宽就容易「长到隔壁东西身上」—— 真踩过：门南端伸进西墙上的人事资料柜 0.51 米。
	# 这里拿门和全屋所有布景 / 探索点 / NPC 的世界包围盒逐个比对。
	# 容差 5 厘米：只放过「圆花盆的方包围盒蹭到门框」这种包围盒层面的擦边。
	var door_prop := {}
	for p in ContentDB.room.get("props", []):
		if str((p as Dictionary).get("name", "")) == "Door_Main":
			door_prop = p
	var door_aabb := _aabb_of(door_prop)
	var clash := PackedStringArray()
	for src in [["布景", ContentDB.room.get("props", [])], ["探索点", ContentDB.spots], ["NPC", ContentDB.npcs]]:
		for it in (src[1] as Array):
			var d := it as Dictionary
			var nm := str(d.get("name", d.get("id", "?")))
			if nm == "Door_Main" or not d.has("size") or not d.has("pos"):
				continue
			var ov := _aabb_overlap(door_aabb, _aabb_of(d))
			if ov > 0.05:
				clash.append("%s(%s) 叠了 %.2f 米" % [nm, src[0], ov])
	_check(clash.is_empty(),
		"门加宽后没有长到别的家具身上（最近的一件也没叠超过 5 厘米）%s"
			% ("：没有" if clash.is_empty() else "：撞上了 " + "、".join(clash)))

	# 相机在房间里、悬在玩家上方、水平位置跟着玩家。
	var cp: Vector3 = main.camera.global_position
	_check(absf(cp.y - main.eye_height) < 0.02, "相机悬在 %.2f 米高" % main.eye_height)
	_check(absf(cp.x) < rs.x * 0.5 and absf(cp.z) < rs.z * 0.5,
		"相机在房间内部（%.1f, %.1f），看不到外面" % [cp.x, cp.z])

	main.player.global_position = Vector3(2.5, 0.0, 1.5)
	main._sync_camera()
	_check(absf(main.camera.global_position.x - 2.5) < 0.01 and absf(main.camera.global_position.z - 1.5) < 0.01,
		"玩家移动后相机跟着走（第一人称跟随）")
	main.player.global_position = ContentDB.vec3(ContentDB.room.get("spawn"), Vector3(-6.8, 0.0, -1.5))
	main._sync_camera()

	print("[10] 环顾控制")
	main.yaw = 0.0
	main.pitch = 0.0
	main._look(100.0, 0.0)
	_check(main.yaw < -1.0, "鼠标右拖 → 视角右转（yaw %.1f）" % main.yaw)
	main._look(-100.0, 0.0)
	_check(absf(main.yaw) < 1.0, "往回拖 → 转回原方向（yaw %.1f）" % main.yaw)
	main._look(0.0, 100.0)
	_check(main.pitch < -1.0, "鼠标下拖 → 低头（pitch %.1f）" % main.pitch)
	main.pitch = main.pitch_max + 100.0
	main._look(0.0, -1.0)
	_check(main.pitch <= main.pitch_max + 0.01, "往头顶拖也只会回到 pitch 上限，不会翻过头")
	main.pitch = main.pitch_min - 100.0
	main._look(0.0, 1.0)
	_check(main.pitch >= main.pitch_min - 0.01, "低头有下限，不会穿到地板下面")
	# 能一路抬到天花板 —— 这是「物理上抬得上去」的直接证据。
	main.pitch = -34.0
	main._look(0.0, -10000.0)
	_check(absf(main.pitch - main.pitch_max) < 0.01 and main.pitch > 0.0,
		"一直往头顶拖，最终停在 pitch 上限 +%.0f°（能看天花板）" % main.pitch)
	main.pitch = -34.0
	main.yaw = -90.0
	main._sync_camera()

	print("[11] 拖拽不应触发点击（第一人称最容易出 bug 的地方）")
	main.has_target = false
	main.pending_spot = ""
	main._dragging = false
	var yaw_before: float = main.yaw
	var ev_down := InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.pressed = true
	ev_down.position = Vector2(600, 300)
	main._unhandled_input(ev_down)
	var ev_drag := InputEventMouseMotion.new()
	ev_drag.relative = Vector2(50, 10)
	ev_drag.position = Vector2(650, 310)
	main._unhandled_input(ev_drag)
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.position = Vector2(650, 310)
	main._unhandled_input(ev_up)
	_check(main.yaw != yaw_before, "拖动确实转了视角")
	_check(not main.has_target, "拖动 50 像素后松手：只转视角，不会顺带走一步")
	_check(not main._dragging, "松手后退出拖拽态")

	# 按下就松开（几乎没动）—— 这才算点击，会真的去射线取点。
	var ev_c_down := InputEventMouseButton.new()
	ev_c_down.button_index = MOUSE_BUTTON_LEFT
	ev_c_down.pressed = true
	ev_c_down.position = Vector2(640, 420)
	main._unhandled_input(ev_c_down)
	var ev_c_up := InputEventMouseButton.new()
	ev_c_up.button_index = MOUSE_BUTTON_LEFT
	ev_c_up.pressed = false
	ev_c_up.position = Vector2(640, 420)
	main._unhandled_input(ev_c_up)
	_check(not main._dragging, "原地按下松开被当作点击处理（没有卡在拖拽态）")
	main.has_target = false
	main.pending_spot = ""
	main.marker.visible = false

	print("[11b] 六个探索点都够得着（真的走一遍）")

	# 探索点必须**真的走得过去**：玩家能站到的地方到探针 ≤ INTERACT_RANGE(3.2)。
	# 不然玩家点了之后只会在原地打转，信息卡永远弹不出来。
	# ⚠ 对「吧台」尤其要紧 —— 探针钉在 4.8 米长吧台的台面上（`pos.y = 1.30`，台面高 1.266），
	#   玩家不可能站到台面高度，只能站在旁边的走道上够。`objects.json` 里 pantry 的
	#   `pos [5.40, 1.30, 0.35]` 就是按这条反算的（实测整条台面最近 1.7~1.9 米）。
	#
	# ⛔ **别拿「pending_spot 被清掉 / scanned 进了」当判据** —— 那是假通过。
	#   `_step_player` 里有个「被家具顶住 0.6 秒就走不动了 → `_finish_walk()`」的兜底，
	#   而 `_finish_walk()` 只要 `pending_spot` 非空就会 `_open_spot()`。
	#   所以哪怕探针在天上、在墙外面，走一会儿也会「成功打开」（2026-10-05 试过：
	#   把探针丢到西南死角，仍然 4/4「到达」）。**唯一诚实的判据是走完之后的实际距离。**
	#
	# ⛔ 这段必须放在所有依赖玩家位置的判据之后（它会把玩家挪来挪去）；
	#   ⛔ 变量名别跟前面重（`waited` 撞过，直接 Parse Error）。
	var spot_starts := [
		Vector3(-6.8, 0, -1.05), Vector3(0.0, 0, -2.6),
		Vector3(1.0, 0, 3.2), Vector3(-3.0, 0, 4.2),
	]
	var unreachable := []
	for s in ContentDB.spots:
		var sid := str(s.get("id", ""))
		var sn: Node3D = main._spot_nodes.get(sid)
		if sn == null:
			continue
		var best := 1.0e9
		for st in spot_starts:
			main.player.global_position = st
			main.pending_spot = ""
			main.has_target = false
			main.scanned.erase(sid)
			await get_tree().physics_frame
			main._click_spot(sid, sn)
			if main.pending_spot != "":
				var w2 := 0
				while main.pending_spot != "" and w2 < 900:
					await get_tree().physics_frame
					w2 += 1
			var d1: float = main.player.global_position.distance_to(sn.global_position)
			best = minf(best, d1)
		main.pending_spot = ""
		main.has_target = false
		main.scanned.erase(sid)
		main.hud.close_modal()
		if best > main.INTERACT_RANGE:
			unreachable.append("%s（最近只到 %.2f m）" % [sid, best])
	_check(unreachable.is_empty(),
		"每个探索点都能走到 %.1f m 以内（四个方向各试一次）：%s"
		% [main.INTERACT_RANGE, str(unreachable)])


	print("[12] 进入页：标题页 → 开始游戏 → 选幕页")
	_check(not ContentDB.frontend.is_empty(), "读到 data/frontend.json")
	_check(not ContentDB.intro.is_empty(), "读到 data/intro.json")

	# 2026-10-06 晚：作者把开场正文写来了（此前两个数组都是「（占位）…」稿）。
	# 判据刻意**不写死段数** —— 他会随时增删句子；只钉「两段都有正文」+「没有一段还是占位稿」。
	var intro_total := 0
	var intro_placeholder := 0
	for ikey in ["recap", "intro"]:
		for itxt_raw in ContentDB.intro.get(ikey, []):
			var itxt := str(itxt_raw)
			if itxt.strip_edges() == "":
				intro_placeholder += 1
				continue
			intro_total += 1
			if itxt.find("占位") >= 0:
				intro_placeholder += 1
	_check(intro_total >= 8, "前情提要 / 引导剧情都有正文（合计 %d 段）" % intro_total)
	_check(intro_placeholder == 0,
		"开场文案里一段占位稿都不剩（还有 %d 段是空的、或写着「占位」）" % intro_placeholder)

	var fe := Frontend.new()
	add_child(fe)
	await get_tree().process_frame
	await get_tree().process_frame      # 容器要第二帧才把 logo 的实际尺寸排好
	_check(fe.page == "title", "一进来停在标题页")
	_check(fe.find_button(str(ContentDB.frontend.get("start_label", ""))) != null, "标题页有「开始游戏」")
	_check(fe.find_button(str(ContentDB.frontend.get("recap_label", ""))) != null, "标题页有「前情提要」")

	# 标题 = 作者设计的 logo 图（谁杀死了老板）。作者给的源是**白底 JPG**，
	# 直接贴会在页面底色上糊出一个白方块，所以过了 tools/logo_prep.py 抠成透明底。
	# 这里两头都验：① 挂的是图不是文字；② 图真的有透明通道（白底抠掉了）。
	var logo := fe.find_child("Logo", true, false) as TextureRect
	_check(logo != null and logo.texture != null,
		"标题页挂的是作者设计的 logo 图（找不到才会退回文字标题）")
	var logo_alpha := -1.0
	var logo_w := 0
	var logo_h := 0
	if logo != null and logo.texture != null:
		logo_w = logo.texture.get_width()
		logo_h = logo.texture.get_height()
		var im: Image = (logo.texture as Texture2D).get_image()
		if im != null and not im.is_empty():
			var corners := [
				im.get_pixel(0, 0), im.get_pixel(im.get_width() - 1, 0),
				im.get_pixel(0, im.get_height() - 1),
				im.get_pixel(im.get_width() - 1, im.get_height() - 1),
			]
			var n_clear := 0
			for c in corners:
				if (c as Color).a < 0.2:
					n_clear += 1
			logo_alpha = n_clear
	_check(logo_w > 600 and logo_h > 400,
		"logo 图有 %d×%d 像素 —— 标题要够清楚，别拿缩略图当标题" % [logo_w, logo_h])
	_check(logo_alpha >= 3.0,
		"logo 四角有 %.0f/4 是透明的 —— 白底真的抠掉了，压在页面底色上不会露白方块" % logo_alpha)
	_check(logo != null and logo.size.y > 1.0
		and absf(logo.size.x / logo.size.y - float(logo_w) / float(logo_h)) < 0.02,
		"logo 挂在标题页上是按原图长宽比摆的（没有拉变形）")

	# ── 2026-10-06 作者改版：去掉卡片边框、删掉副标题、两个选项换成手绘图示 ──
	var ftitle: Dictionary = ContentDB.frontend.get("title", {})
	# 2026-10-06 波普风版：title.pop 一填，标题页就换成「整屏底图 + 素材绝对定位」——
	# 下面几条判据跟着分叉（旧版那几条是照居中流式布局写的，在波普版里本来就不成立）。
	var pop_mode: bool = typeof(ftitle.get("pop", null)) == TYPE_DICTIONARY \
		and not (ftitle.get("pop") as Dictionary).is_empty()
	var bb_start := fe.find_button("开始游戏")
	var bb_recap := fe.find_button("前情提要")
	# ⚠ 只在**标题页**里找 Card —— 前情提要页那边还有一张卡片（那个没动），
	#   从 fe 上直接 find_child 会先找到它。
	var tpage0 := fe.find_child("Title", true, false)
	_check(tpage0 != null and tpage0.find_child("Card", true, false) == null,
		"标题页不再有卡片（那个暖棕色的圆角框删掉了，内容直接坐在页面底色上）")
	_check(not ftitle.has("subtitle"),
		"「第一幕 · 设计部」那行副标题已经从内容里删掉了")
	_check(bb_start is TextureButton and bb_recap is TextureButton,
		"两个选项换成了作者手绘的图示（TextureButton，不再是色块按钮）")
	if pop_mode:
		_check(fe.find_child("Footer", true, false) == null,
			"波普版底图铺满整屏，不再贴底边那行操作提示（内容里 footer 留空）")
	else:
		_check(fe.find_child("Footer", true, false) != null,
			"贴屏幕底边那行操作提示还在（它不是卡片的一部分）")

	# 「大小一致对齐」是作者的原话。这条**不是靠调数字**做到的，而是靠两张图
	# **共用同一条横向画布**（tools/btn_prep.py 把它们等比缩到同一条黑条宽、把条心
	# 压在同一列上）—— 所以两张图的**宽度**必须逐像素相同。这里把这条不变量钉死：
	# 以后谁单独给其中一张换图、或只改一张的宽度，这里会立刻红。
	# ⚠ 高度**故意不同**：剑往上伸得远、猫伸得近，纵向各自裁紧（共用高度会在矮的
	#   那张底下留一块透明空隙，把两个按钮之间撑开一条大缝）。
	if bb_start is TextureButton and bb_recap is TextureButton:
		var stex: Texture2D = (bb_start as TextureButton).texture_normal
		var rtex: Texture2D = (bb_recap as TextureButton).texture_normal
		if pop_mode:
			# 波普版：两张图**不共用画布** —— 各自带自己那圈留白，摆位与缩放全照设计稿来。
			# 所以「宽度必须相同」不适用了，换成**更强**的一条：按钮实际摆出来的位置，
			# 必须等于「设计稿坐标 × 换算系数」—— 把「数据驱动」这件事钉死。
			var popd: Dictionary = ftitle.get("pop", {})
			var vs: Vector2 = fe.get_viewport().get_visible_rect().size
			if vs.x <= 1.0 or vs.y <= 1.0:
				vs = Vector2(1600, 900)
			var pk := minf(vs.x / float(popd.get("design_w", 1801)),
				vs.y / float(popd.get("design_h", 1013)))
			var n_btn := 0
			for raw in popd.get("layers", []):
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				var L: Dictionary = raw
				if str(L.get("action", "")) == "":
					continue
				var btn := fe.find_button(str(L.get("label", "")))
				_check(btn != null, "波普版按钮「%s」建出来了" % str(L.get("label", "")))
				if btn == null:
					continue
				_check(absf(btn.position.x - float(L.get("x", 0.0)) * pk) < 1.0
					and absf(btn.position.y - float(L.get("y", 0.0)) * pk) < 1.0,
					"「%s」摆位 = 设计稿坐标 × 换算系数（现在 %.0f,%.0f）"
					% [str(L.get("label", "")), btn.position.x, btn.position.y])
				n_btn += 1
			_check(n_btn == 2, "两张素材按钮都按 pop 配置摆好了（实为 %d）" % n_btn)
		else:
			_check(stex != null and rtex != null and stex.get_width() == rtex.get_width(),
				"两张按钮图共用同一条横向画布（宽 %d / %d）—— 黑条才会一样大、条心才会对齐"
				% [stex.get_width(), rtex.get_width()])
			_check(absf(bb_start.size.x - bb_recap.size.x) < 0.5 and bb_start.size.x > 1.0,
				"两个图示按钮摆出来的宽度一样（%.1f px）" % bb_start.size.x)
		_check(bb_start.size.y > 1.0 and bb_recap.size.y > 1.0
			and absf(bb_start.size.y - bb_start.size.x * stex.get_height() / float(stex.get_width())) < 1.0
			and absf(bb_recap.size.y - bb_recap.size.x * rtex.get_height() / float(rtex.get_width())) < 1.0,
			"两个图示各自按原图长宽比摆（%.0f px / %.0f px，高度不同是对的）"
			% [bb_start.size.y, bb_recap.size.y])
		# 作者 2026-10-06 又甩了张参考图：「按钮太大了，logo 太小了」。
		# 参考图里 logo 宽 ≈ 黑条宽的 3.9 倍（量出来 935 : 240）—— 钉一个宽松版。
		_check(logo != null and logo.size.x > bb_start.size.x * 2.0,
			"logo 明显比按钮大（logo %.0f px vs 按钮图 %.0f px）—— 照作者参考图来的"
			% [logo.size.x, bb_start.size.x])
		var bimg: Image = (stex as Texture2D).get_image()
		if bimg != null and not bimg.is_empty():
			var bclear := 0
			for bc in [bimg.get_pixel(0, 0), bimg.get_pixel(bimg.get_width() - 1, 0),
					bimg.get_pixel(0, bimg.get_height() - 1),
					bimg.get_pixel(bimg.get_width() - 1, bimg.get_height() - 1)]:
				if (bc as Color).a < 0.2:
					bclear += 1
			_check(bclear >= 3,
				"按钮图四角有 %d/4 是透明的 —— 白底真的抠掉了（浅底上不会糊出白方块）" % bclear)
		# 悬停反馈：图示是「黑线 + 白底」，**提亮没用**（0 × 1.1 还是 0），所以走缩放。
		bb_start.mouse_entered.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(bb_start.scale.x > 1.001,
			"鼠标移上去按钮会微微放大（%.3f）—— 黑白线稿只能靠缩放做反馈" % bb_start.scale.x)
		bb_start.mouse_exited.emit()
		await get_tree().create_timer(0.3).timeout
		_check(absf(bb_start.scale.x - 1.0) < 0.01,
			"鼠标移开后又缩回 1.0（%.3f）" % bb_start.scale.x)

	fe.find_button("开始游戏").pressed.emit()
	await get_tree().process_frame
	_check(fe.page == "acts", "点「开始游戏」→ 进选幕页")

	var acts: Array = ContentDB.frontend.get("acts", [])
	_check(acts.size() == 3, "选幕页有 3 幕（实为 %d）" % acts.size())
	_check(fe.act_button(0) != null and fe.act_button(1) != null and fe.act_button(2) != null,
		"三张幕卡都建出来了")
	_check(not bool((acts[0] as Dictionary).get("locked", false)), "第一幕是解锁的")
	_check(bool((acts[1] as Dictionary).get("locked", false))
		and bool((acts[2] as Dictionary).get("locked", false)),
		"第二、三幕都是锁住的")
	_check(str((acts[0] as Dictionary).get("scene", "")) == "res://scenes/main.tscn",
		"第一幕指向办公室地图（main.tscn）")
	_check(str((acts[1] as Dictionary).get("scene", "")) == ""
		and str((acts[2] as Dictionary).get("scene", "")) == "",
		"锁住的幕没有配场景 —— 想开也开不了")

	# ── 2026-10-05 波普风选幕页（作者给的第二页平面美术）──
	# acts_pop 一填，选幕页就换成「整屏底图 + 三块透明点击区」。和标题页 pop 同一套换算。
	var apop_raw: Variant = ContentDB.frontend.get("acts_pop", {})
	var apop_mode: bool = typeof(apop_raw) == TYPE_DICTIONARY \
		and not (apop_raw as Dictionary).is_empty()
	if apop_mode:
		var apop: Dictionary = apop_raw
		var apage := fe.find_child("Acts", true, false)
		_check(apage != null and apage.find_child("PopBg", true, false) != null,
			"选幕页铺上了作者的平面美术底图（PopBg）")
		var aw := 0
		var ah := 0
		if apage != null:
			var abg := apage.find_child("PopBg", true, false) as TextureRect
			if abg != null and abg.texture != null:
				aw = abg.texture.get_width()
				ah = abg.texture.get_height()
		_check(absf(float(aw) / float(ah) - 16.0 / 9.0) < 0.01,
			"底图是 16:9（%d×%d）—— 铺满屏不会留边、也不会被拉扁" % [aw, ah])
		# 三块点击区必须**照着设计稿坐标摆**（数据驱动这件事钉死，和标题页一条逻辑）。
		var avs: Vector2 = fe.get_viewport().get_visible_rect().size
		if avs.x <= 1.0 or avs.y <= 1.0:
			avs = Vector2(1600, 900)
		var ak := minf(avs.x / float(apop.get("design_w", 1920)),
			avs.y / float(apop.get("design_h", 1080)))
		var acards: Array = apop.get("cards", [])
		_check(acards.size() == 3, "美术上标了 3 个幕位（实为 %d）" % acards.size())
		var placed := 0
		for i in range(acards.size()):
			var r: Array = (acards[i] as Dictionary).get("rect", [])
			if r.size() < 4:
				continue
			var ab := fe.act_button(i)
			if ab == null:
				continue
			# x 会因居中而偏移（ox），但**宽高**必然等于设计稿宽高 × 系数 —— 这条不受居中影响，
			# 所以拿尺寸钉死，比钉绝对坐标稳。
			var wwant := (float(r[2]) - float(r[0])) * ak
			var hwant := (float(r[3]) - float(r[1])) * ak
			_check(absf(ab.size.x - wwant) < 1.0 and absf(ab.size.y - hwant) < 1.0,
				"第 %d 个幕位点击区尺寸 = 设计稿 rect × 换算系数（实为 %.0f×%.0f，应为 %.0f×%.0f）"
					% [i + 1, ab.size.x, ab.size.y, wwant, hwant])
			placed += 1
		_check(placed == 3, "三块点击区都照 rect 摆好了（实为 %d）" % placed)
		# 返回按钮也得存在（盖在美术的「返回」胶囊上）。
		var aback := fe.find_button(str(ContentDB.frontend.get("back_label", "返回标题")))
		_check(aback != null, "「返回」点击区建出来了（盖在美术的胶囊上）")
		_check(fe.find_child("HintPill", true, false) != null,
			"提示文字垫在白色胶囊上（卡片下面全是黑白格，纯字读不清）")

	print("[13] 锁住的幕点不动；第一幕才进地图")
	var chosen: Array = []
	fe.act_chosen.connect(func(p: String) -> void: chosen.append(p))

	fe.act_button(1).pressed.emit()
	await get_tree().process_frame
	_check(chosen.is_empty(), "点锁住的第二幕：不会进游戏")
	_check(fe.last_locked_hint.contains("第二幕"), "给出一句提示：%s" % fe.last_locked_hint)
	_check(fe.act_hint_text() == fe.last_locked_hint, "提示真的显示在页面上了")
	fe.act_button(2).pressed.emit()
	await get_tree().process_frame
	_check(chosen.is_empty(), "点锁住的第三幕：也不会进游戏")

	fe.act_button(0).pressed.emit()
	await get_tree().process_frame
	_check(chosen.size() == 1 and chosen[0] == "res://scenes/main.tscn",
		"点第一幕 → 发出「加载办公室地图」")

	print("[14] 前情提要：逐段播完才给「进入选幕」")
	fe.show_recap()
	await get_tree().process_frame
	_check(fe.page == "recap", "进到前情提要页")
	var total := fe.recap_total()
	_check(total >= 2, "前情提要有 %d 段（前情提要 + 引导剧情）" % total)
	_check(fe.recap_index() == 0, "每次进来都从头放")
	_check(fe.recap_text().strip_edges() != "", "第 1 段有正文：%s" % fe.recap_text().left(14))
	_check(fe.find_button("进入选幕") == null, "还没放完，不给「进入选幕」")
	_check(fe.find_button("继续") != null, "没放完时给的是「继续」")

	var recap_n := 0
	for t in ContentDB.intro.get("recap", []):
		if str(t).strip_edges() != "":
			recap_n += 1

	var kinds_ok := true
	for i in range(total):
		var want := str(ContentDB.intro.get("title", "")) if i < recap_n \
			else str(ContentDB.intro.get("intro_title", ""))
		if fe.recap_kind() != want:
			kinds_ok = false
		fe.advance_recap()
	_check(kinds_ok, "顺序对：先 %d 段前情提要，再 %d 段引导剧情" % [recap_n, total - recap_n])
	await get_tree().process_frame
	_check(fe.recap_index() == total - 1,
		"走到底就停住，不会越界（%d / %d）" % [fe.recap_index() + 1, total])
	_check(fe.find_button("进入选幕") != null, "最后一条才给「进入选幕」")

	fe.find_button("进入选幕").pressed.emit()
	await get_tree().process_frame
	_check(fe.page == "acts", "播完 → 落到选幕页")
	fe.queue_free()
	await get_tree().process_frame

	print("[15] 入口壳：选完幕才挂地图；「重新走一遍」不退回标题页")
	_check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/app.tscn",
		"工程入口场景已经切到 app.tscn")
	var app_packed: PackedScene = load("res://scenes/app.tscn")
	_check(app_packed != null, "app.tscn 能加载")
	var app: Node = app_packed.instantiate()
	add_child(app)
	await get_tree().process_frame
	var app_entry: Frontend = app.get("entry")
	var app_act0: Node = app.get("act")
	_check(app_entry != null, "一进来先挂上进入页，没有直接进地图")
	_check(app_act0 == null, "还没选幕，地图没有加载")
	if app_entry != null:
		_check(app_entry.page == "title", "进入页停在标题页")
		app_entry.act_button(0).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	var app_act: Node = app.get("act")
	var app_entry_gone: Frontend = app.get("entry")
	_check(app_act != null, "点第一幕 → 办公室地图挂上了")
	_check(app_entry_gone == null,
		"地图起来后进入页让位了（Frontend layer 20 > Hud 10，留着会盖住游戏）")
	_check(app_act != null and app_act.has_method("_open_spot"), "挂上的确实是第一幕的地图")
	_check(app_act != null and app_act.get("hud") != null, "地图自己的 HUD 也在")

	app.call("restart_act")
	await get_tree().process_frame
	await get_tree().process_frame
	var app_act2: Node = app.get("act")
	var app_entry2: Frontend = app.get("entry")
	_check(app_act2 != null and app_act2 != app_act, "「重新走一遍」重开的是本幕，不是退回标题页")
	_check(app_entry2 == null, "重开本幕不会把进入页塞回来")
	app.queue_free()
	await get_tree().process_frame

	# ---- 背景音乐（2026-10-06 作者给的 BGM）----
	# 这里只验「配置对 + 起播了」；「真的跨得过去循环点」要实时等 3 秒，塞进自检太慢，
	# 由 scenes/_bgmcheck.tscn 单独验（跑法见那个脚本的头注释）。
	var bgm_path := "res://assets/audio/bgm_main.ogg"
	_check(ResourceLoader.exists(bgm_path), "BGM 素材在：%s" % bgm_path)
	var bgm_stream: AudioStream = load(bgm_path)
	_check(bgm_stream is AudioStreamOggVorbis, "BGM 是 Ogg Vorbis（体积小、Godot 原生支持循环）")
	var bgm_loop := false
	var bgm_len := 0.0
	if bgm_stream is AudioStreamOggVorbis:
		bgm_loop = (bgm_stream as AudioStreamOggVorbis).loop
		bgm_len = bgm_stream.get_length()
	_check(bgm_loop, "BGM 的 loop 开着（⛔ 关掉的话音乐播完就彻底哑，而且不报错）")
	_check(bgm_len > 200.0 and bgm_len < 207.0,
		"BGM 时长 %.1f 秒 —— 首尾安静段已裁掉（原始素材 209.8 秒）" % bgm_len)
	var bgm_state: Dictionary = Audio.debug_state()
	var bgm_playing := false
	for bgm_k in bgm_state:
		if bool(bgm_state[bgm_k]["playing"]):
			bgm_playing = true
	_check(bgm_playing, "Audio autoload 已经起播（进游戏不会先静一拍，切场景也不会断）")
	Audio.shutdown()   # 跑完把音频资源放掉，退出日志才干净

	print("=== 自检结束：%d 项通过，%d 项失败 ===" % [checks - fails, fails])
	get_tree().quit(1 if fails > 0 else 0)


## 「这个节点下面有没有开着自发光的材质？」—— 验落地窗那片「微微发光的玻璃」用。
## 刻意独立成一个函数：自检那个大函数里变量已经几百个，塞进去很容易撞名 ——
## 撞了就是 Parse Error、整个场景加载不了、末尾的 quit 永不执行（会假死十几分钟）。
func _has_emissive(root: Node) -> bool:
	var work: Array[Node] = [root]
	while not work.is_empty():
		var cur: Node = work.pop_back()
		for ch in cur.get_children():
			work.append(ch)
		var mi := cur as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var sm := mi.get_surface_override_material(si) as StandardMaterial3D
			if sm != null and sm.emission_enabled and sm.emission_energy_multiplier > 0.0:
				return true
	return false


## 「这个节点下面有没有被提亮过的材质？」—— 验饮水机那句「灰度调小、变得更白一点」用。
## 判别方式：albedo_color 有分量 > 1。正常材质的 albedo_color 不会超过 1
## （glb 导入出来基本都是纯白），**只有 tint.gain > 1 提亮过的才会 > 1**。
func _has_tint(root: Node) -> bool:
	var work: Array[Node] = [root]
	while not work.is_empty():
		var cur: Node = work.pop_back()
		for ch in cur.get_children():
			work.append(ch)
		var mi := cur as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var sm := mi.get_surface_override_material(si) as StandardMaterial3D
			if sm != null and maxf(sm.albedo_color.r, maxf(sm.albedo_color.g, sm.albedo_color.b)) > 1.001:
				return true
	return false
