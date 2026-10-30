extends Node
## 内容数据源。
## 全部内容都在 res://data/*.json 里，改文案只改 JSON，不用碰代码。

const ROOM_PATH := "res://data/room.json"
## 布局：每个探索点 / NPC / 布景「摆在哪、多大」（几何，和 3D 绑死）。
const OBJECTS_PATH := "res://data/objects.json"
## 第一幕的全部**文案**：三轮 × (探索点文案 + 判断题 + 轮末过场)。
## ⚠ 2026-10-06 从 questions.json 合并进来的 —— 位置写在 objects.json，
##   「说什么」写在 act1.json，两边靠 id 对起来。`questions.json` 已退休。
const ACT_PATH := "res://data/act1.json"
## 进入页 / 选幕页的文案与三幕配置。
const FRONTEND_PATH := "res://data/frontend.json"
## 前情提要 + 引导剧情。
const INTRO_PATH := "res://data/intro.json"

var room: Dictionary = {}
var objects: Dictionary = {}
var spots: Array[Dictionary] = []
var npcs: Array[Dictionary] = []
## 第一幕的轮次表（每一轮 = 一批探索点文案 + 一批判断题 + 一段过场）。
var act: Dictionary = {}
var rounds: Array[Dictionary] = []
var frontend: Dictionary = {}
var intro: Dictionary = {}
var errors: Array[String] = []


func _ready() -> void:
	room = _read(ROOM_PATH)
	var obj := _read(OBJECTS_PATH)
	objects = obj
	spots = _dict_array(obj.get("spots", []))
	npcs = _dict_array(obj.get("npcs", []))
	act = _read(ACT_PATH)
	rounds = _dict_array(act.get("rounds", []))
	frontend = _read(FRONTEND_PATH)
	intro = _read(INTRO_PATH)

	if errors.is_empty():
		print("[ContentDB] 载入完成：%d 个探索点 / %d 个 NPC / %d 轮 / %d 幕"
			% [spots.size(), npcs.size(), rounds.size(), _dict_array(frontend.get("acts", [])).size()])
	else:
		for e in errors:
			push_error("[ContentDB] " + e)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("找不到 " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("JSON 解析失败：" + path)
		return {}
	return parsed


func _dict_array(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item)
	return out


func get_spot(id: String) -> Dictionary:
	for s in spots:
		if str(s.get("id", "")) == id:
			return s
	return {}


func get_npc(id: String) -> Dictionary:
	for n in npcs:
		if str(n.get("id", "")) == id:
			return n
	return {}


func get_question(id: String) -> Dictionary:
	for i in range(rounds.size()):
		var q := round_question(i, id)
		if not q.is_empty():
			return q
	return {}


# ---------------------------------------------------------------- 轮次（第一幕三轮搜证）
##
## 一轮 = 「看完本轮的探索点 → 找人答本轮的判断题 → 轮末过场」，轮末线索刷新。
## 这里只负责查表，流程在 main.gd。

func round_count() -> int:
	return rounds.size()


func round_of(i: int) -> Dictionary:
	if i < 0 or i >= rounds.size():
		return {}
	return rounds[i]


## 第 i 轮里某个探索点的**文案**（`name/hint/lines/clue`）。
## 位置和大小在 objects.json，那边只有一份；这里每轮一份，用来「刷新线索」。
func round_spot(i: int, id: String) -> Dictionary:
	for s in _dict_array(round_of(i).get("spots", [])):
		if str(s.get("id", "")) == id:
			return s
	return {}


## 第 i 轮实际用到的探索点 id，顺序就是数组顺序。
## ⚠ 每轮可以只用一部分位置 —— 没列进来的，感叹号不会出现。
## ⚠ 2026-10-06 起 `spots[]` 里**同时也放小人（NPC）的 id**：作者要求「每一轮都可以点击小人
##   获得小人身上的线索，小人也是可探索点」。所以这里两种 id 都要放行 —— 只认 objects.json
##   的 `spots` 会把四个小人整批滤掉（表现就是「点了没反应、进度条还差 4 个」）。
func round_spot_ids(i: int) -> Array[String]:
	var out: Array[String] = []
	for s in _dict_array(round_of(i).get("spots", [])):
		var id := str(s.get("id", ""))
		if id != "" and is_explorable(id):
			out.append(id)
	return out


## 这个 id 是不是一个「可探索点」—— 家具位置（objects.json 的 spots）、小人（npcs）、
## 或「布景里挂了 explore 字段的家具」（room.json 的 props，作者 2026-10-06 要的
## 「场景里的家具全部可探索」）都算。
func is_explorable(id: String) -> bool:
	return not get_spot(id).is_empty() or not get_npc(id).is_empty() or not explore_prop(id).is_empty()


## 布景里「挂了 explore 字段、指向这个 id」的 prop（人台 / 饮水机 / 发财树 / 雕塑 /
## 会议桌 / 沙发这类既是道具又是探索目标的东西）。几何（pos/size/rot）从这来。
func explore_prop(id: String) -> Dictionary:
	for p in _dict_array(room.get("props", [])):
		if str(p.get("explore", "")) == id:
			return p
	return {}


## 可探索点的显示名。家具用 objects.json 的 `name`，小人用 npc 的 `name`，
## explore-prop 用它的 `explore_name`（没有就用 prop 的 name）。
func explorable_name(id: String) -> String:
	var s := get_spot(id)
	if not s.is_empty():
		return str(s.get("name", ""))
	var n := get_npc(id)
	if not n.is_empty():
		return str(n.get("name", ""))
	var p := explore_prop(id)
	if not p.is_empty():
		return str(p.get("explore_name", p.get("name", "")))
	return ""


func round_questions(i: int) -> Array[Dictionary]:
	return _dict_array(round_of(i).get("questions", []))


func round_question(i: int, qid: String) -> Dictionary:
	for q in round_questions(i):
		if str(q.get("id", "")) == qid:
			return q
	return {}


func round_end(i: int) -> Dictionary:
	var e: Variant = round_of(i).get("end", {})
	return e if typeof(e) == TYPE_DICTIONARY else {}


## 第 i 轮里某个小人**头顶思考框**要说的那句话（一人一句，每轮一份）。
## ⚠ 文案住 act1.json 的 `rounds[].idle_lines`，形状/位置住 objects.json 的 `bubble` ——
##   这是「几何一份、文案每轮一份」那条分界线的延续，改文案别碰 .gd。
func round_idle_line(i: int, npc_id: String) -> String:
	var raw: Variant = round_of(i).get("idle_lines", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return ""
	return str((raw as Dictionary).get(npc_id, ""))


## [x, y, z] -> Vector3
func vec3(raw: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if typeof(raw) == TYPE_ARRAY and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback


func col(raw: Variant, fallback: Color = Color.WHITE) -> Color:
	if typeof(raw) == TYPE_STRING and str(raw).begins_with("#"):
		return Color(str(raw))
	return fallback


## 方块的底面贴在 y = pos.y 上，这里换算成方块中心点。
func box_center(pos: Vector3, size: Vector3) -> Vector3:
	return Vector3(pos.x, pos.y + size.y * 0.5, pos.z)
