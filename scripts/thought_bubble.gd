extends Node3D
## 头顶的「二次元思考框」—— 一张平面贴图，永远正面朝相机（billboard）。
## 玩家走近自动弹出来，走开收回去。**内容先空着**，以后往 cfg.text 里写。
##
## 形状全部取自漫画对话框：
##   cloud       扇贝边云朵（「心理描写」那种）+ 可选放射线
##   spike       尖锐星芒（「震惊/爆炸」那种），尖角细长、边往内凹
##   box_tail    圆角方框 + 左下角一条尾巴（最普通的「对白」）
##   panel_tail  斜格面板 + 尾巴 + 网点（「旁白/正式」那种）
##   burst       爆炸锯齿（老的锯齿形状，留着没删）
##   round       最素的圆
##   square      圆角方框（骨架圆盘密排出来的）
##
## 为什么不用 png：形状参数（尖角数、手绘抖动、描边粗细、放射线、网点、配色）
## 全部外置在 objects.json 里（`_bubble` 是默认值，每个 NPC 自己那份 `bubble` 覆盖它），
## 改个数字重开就换一个样子。贴图是**运行时现画**的，同参数的人共用一张（缓存住）。
##
## 用法：
##   var b := preload("res://scripts/thought_bubble.gd").new()
##   b.configure(cfg, 宿主尺寸, id)   # cfg 见 objects.json 的 _bubble
##   body.add_child(b)
##   b.set_distance(到玩家的水平距离)   # 每帧喂一次，它自己决定弹 / 收

const TEX_W := 384          # 贴图宽（像素）
const TEX_H := 465          # 贴图高（像素）
const SHAPE_W := 3.124      # 形状在「形状空间」里的总宽（单位）
const SHAPE_H := 3.750
const SHAPE_MID := 0.485    # 形状原点相对贴图中心的抬升（单位）——
                            # 底下那三个递减小圆占了下半张，名字里的「mid」是历史遗留
## 形状空间的单位 → 像素。描边粗细按像素给，跟贴图分辨率解耦。
const UNIT := TEX_W * 0.96 / SHAPE_W
const OUT_R := 1.42         # 各种形状统一的外接半径
const CORNER_R := 0.30      # 方框的圆角

## ⚠ 形状空间里 **+y 是朝下的**（朝着头顶 —— 底下那三个小圆就是正 y）。
## 所以「尾巴往下的形状」在 `_poly()` 里是按自然坐标系（+y 朝上）搭好、最后统一翻的。
## 放射线的角度也按这个空间算：90° = 朝下。

static var _cached := {}    # key -> { "tex": ImageTexture, "bb": Rect2 }
static var _font_cache: Font = null   # 中文字体（全项目共用一份，见 _ui_font()）


## ⛔ Label3D 的**默认字体不含汉字** —— 中文会整句变空白（不报错、不报缺字，
##   就是什么都没有）。所以必须显式给一个中文字体，和 hud.gd / frontend.gd 同一套：
##   工程里有 `assets/font.ttf` 就用它（发布时带上），否则退回系统字体。
static func _ui_font() -> Font:
	if _font_cache != null:
		return _font_cache
	# ⚠ 两条路都要试：导出后 .ttf 会被 Godot 当作「已导入字体」，**裸文件不再进包** ——
	#   FileAccess 读 res://assets/font.ttf 会返回 false，必须用 ResourceLoader 取 .fontdata。
	if ResourceLoader.exists("res://assets/font.ttf"):
		var lf := load("res://assets/font.ttf") as Font
		if lf != null:
			_font_cache = lf
			return _font_cache
	if FileAccess.file_exists("res://assets/font.ttf"):
		var ff := FontFile.new()
		if ff.load_dynamic_font("res://assets/font.ttf") == OK:
			_font_cache = ff
			return _font_cache
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Microsoft YaHei", "微软雅黑", "Noto Sans CJK SC",
		"Source Han Sans SC", "SimHei", "PingFang SC", "sans-serif",
	])
	sf.allow_system_fallback = true
	_font_cache = sf
	return _font_cache

var _sprite: Sprite3D
var _label: Label3D
var _range := 2.6           # 多近才弹出来（米）
var _pop := 0.16            # 弹出用多少秒
var _bob := 0.008           # 轻微的上下飘（米）—— 太小就死板，太大就成气球
var _base_y := 0.0          # 贴图中心的本地高度
var _text_dy := 0.0         # 内容位相对贴图中心的偏移（米）
var _near := false
var _t := 0.0               # 弹出进度 0 → 1
var _phase := 0.0
var _clock := 0.0
var _text := ""             # 现在框里那句话（轮末刷新会换，自检用）
var _style := "cloud"       # 这一份用的是哪种形状（自检用）
var _art_h := 0.0           # 形状在贴图里的实际高度（米，自检用）
var _art_w := 0.0           # 形状在贴图里的实际宽度（米，自检用）
var _art_bottom := 0.0      # 形状最低那点的本地高度（米，自检用）


## cfg：objects.json 的 `_bubble`（每个 NPC 的 `bubble` 已在外层合并过）。
## host_size：宿主灰盒尺寸，用来把框摆到头上去。
## id：给每个人的飘幅错开相位用，不然四个框会同步上下。
func configure(cfg: Dictionary, host_size: Vector3, id: String = "") -> void:
	name = "Bubble"
	_range = float(cfg.get("range", 2.6))
	_pop = maxf(0.05, float(cfg.get("pop", 0.16)))
	_bob = float(cfg.get("bob", 0.008))
	_phase = float(abs(hash(id)) % 977) / 977.0 * TAU

	var h := maxf(0.12, float(cfg.get("h", 0.72)))
	var lift := float(cfg.get("lift", 0.10))
	var sx := float(cfg.get("sx", 1.10))
	var sy := float(cfg.get("sy", 0.98))
	var dots_on := int(cfg.get("dots", 1)) != 0
	var pixel := h / float(TEX_H)

	var prep := _prep(cfg)
	var tex: ImageTexture = prep["tex"]
	var bb: Rect2 = prep["bb"]
	_style = str(cfg.get("style", "cloud"))
	_art_h = bb.size.y * sy * UNIT * pixel
	_art_w = bb.size.x * sx * UNIT * pixel

	# 形状下沿（形状空间里 qy 最大的那一点）在贴图里的位置。
	# local_y(qy) = C + (SHAPE_MID - qy * sy) * UNIT * pixel，其中 C 是贴图中心的高度。
	#  · 带三个小圆时，锚点是**贴图底边**（小圆要指着头顶）
	#  · 不带时，锚点是**形状自己的下沿** —— 否则形状会跟头顶之间空出一大块
	var head_top := host_size.y * 0.5
	# 放射线是长在轮廓**外面**的，R(θ) 表量不到它 —— 得手工加上，
	# 否则那圈线会往头顶里戳进去。反正只有朝下那几条，一律按最远算。
	var ray_ext := 0.0
	if int(cfg.get("rays", 0)) > 0:
		ray_ext = float(cfg.get("ray_gap", 0.10)) + float(cfg.get("ray_len", 0.46))
	if dots_on:
		_base_y = head_top + lift + h * 0.5
	else:
		_base_y = head_top + lift - (SHAPE_MID - (bb.end.y + ray_ext) * sy) * UNIT * pixel

	# 内容位落在**形状**中心，不是落在整张图中心。
	# ⚠ 带尾巴的形状不能按包围盒中心取 —— 尾巴把包围盒往下拉了，
	#   照包围盒居中会把字压到框底。这两种形状的「框体中心」就是搭建用的原点（qy = 0）。
	var styled := str(cfg.get("style", "cloud"))
	var has_tail := styled == "box_tail" or styled == "panel_tail"
	var qc := 0.0 if has_tail else bb.position.y + bb.size.y * 0.5
	_text_dy = (SHAPE_MID - qc * sy) * UNIT * pixel \
		+ float(cfg.get("text_dy", 0.0)) * UNIT * pixel
	# 形状最低那点在本地多高（含朝着头顶伸出去的放射线）—— 自检要盯「别糊到脸上」
	_art_bottom = _base_y + (SHAPE_MID - (bb.end.y + ray_ext) * sy) * UNIT * pixel

	_sprite = Sprite3D.new()
	_sprite.name = "Art"
	_sprite.texture = tex
	_sprite.pixel_size = pixel
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 用 DISCARD 而不是半透明：白色填充本来就是不透明的，
	# 走不透明队列就不会和房间里的发光 overlay 抢排序。
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.35
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.position = Vector3(0.0, _base_y, 0.0)
	add_child(_sprite)

	# 内容位 —— 字是**单独的 Label3D**，不在贴图上，所以换一句话不用重画贴图（见 set_text）。
	var fs := int(cfg.get("font_size", 64))
	_text = str(cfg.get("text", ""))
	_label = Label3D.new()
	_label.name = "Text"
	_label.text = _text
	# ⛔ 不设字体 = 中文全空白（默认字体没有汉字），见 _ui_font()
	_label.font = _ui_font()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# ⚠ 必须 no_depth_test：文字和形状底是同一个平面上的前后关系，
	# 给个固定 z 偏移只在相机站某一侧时才「在前面」，换个方向就被白底盖住了。
	_label.no_depth_test = true
	_label.render_priority = 2
	_label.font_size = fs
	_label.pixel_size = float(cfg.get("line_h", 0.17)) / float(fs)
	_label.outline_size = 0
	_label.modulate = Color(str(cfg.get("line", "#1B1B1B")))
	# 内容宽度跟着**形状实际宽度**走（贴图宽度对所有形状都一样，直接写死 240
	# 会让面板/方框上的字溢出到框外面去）。
	var tw := clampf(float(cfg.get("text_w", 0.72)), 0.2, 1.0)
	_label.width = maxf(40.0, _art_w * tw / pixel)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector3(0.0, _base_y + _text_dy, 0.0)
	_label.visible = _label.text != ""
	add_child(_label)

	_apply(0.0)


## 每帧喂一次到玩家的水平距离。它自己决定弹 / 收，不用外面管。
func set_distance(d: float) -> void:
	_near = d <= _range


## 现在是不是弹出来的（自检用）。
func is_open() -> bool:
	return _near


## 弹出进度 0 → 1（自检用，量的是「真的弹开了」而不是「标记成该弹了」）。
func progress() -> float:
	return _t


## 这个框用的是哪种形状（自检用）。
func style_of() -> String:
	return _style


## 形状在贴图里的实际高度（米）—— 自检用来盯「四个框大小别差太多」。
func art_height() -> float:
	return _art_h


## 形状在贴图里的实际宽度（米）。
func art_width() -> float:
	return _art_w


## 形状最低那点的本地高度（米，相对宿主原点）。宿主原点在身体中心，
## 所以这个值必须 > 半个身高，框才没糊在脸上。
func art_bottom() -> float:
	return _art_bottom


## 换一句话（轮末线索刷新用）。字不在贴图上，所以**不用重画**，改一个字符串就行。
## ⚠ 收起状态下不能把它顶出来 —— 可见性仍然由「有没有靠近」决定（见 _apply）。
func set_text(t: String) -> void:
	_text = t
	if _label == null:
		return
	_label.text = t
	_label.visible = t != "" and _t > 0.001


## 现在框里那句话（自检用）。
func text_of() -> String:
	return _text


func _process(delta: float) -> void:
	_clock += delta
	var step := delta / _pop
	_t = clampf(_t + (step if _near else -step), 0.0, 1.0)
	_apply(_t)


## t = 0 收起、1 弹出。中间过冲一下，弹出来才有「啵」的感觉。
func _apply(t: float) -> void:
	if _sprite == null:
		return
	var e := 1.0 - pow(1.0 - t, 3.0)                    # ease-out
	var s := 0.55 + 0.45 * e + 0.10 * sin(e * PI)       # 轻微的过冲
	_sprite.scale = Vector3(s, s, s)
	_label.scale = Vector3(s, s, s)
	var a := clampf(t * 1.6, 0.0, 1.0)
	var mc := _sprite.modulate
	mc.a = a
	_sprite.modulate = mc
	var lc := _label.modulate
	lc.a = a
	_label.modulate = lc
	var alive := t > 0.001
	_sprite.visible = alive
	_label.visible = alive and _label.text != ""
	if alive:
		var bob := _bob * sin(_clock * 0.9 + _phase)
		_sprite.position.y = _base_y + bob
		_label.position.y = _base_y + _text_dy + bob


# ---------------------------------------------------------------- 贴图

## 缓存 key。只把**影响画面**的项算进去（h / lift / range 这些只影响摆放，不算）。
static func _key(cfg: Dictionary) -> String:
	var skip := ["text", "enable", "range", "pop", "bob", "lift", "h", "text_dy", "_id"]
	var ks := cfg.keys()
	ks.sort()
	var parts := PackedStringArray()
	for k in ks:
		var kk := str(k)
		if skip.has(kk):
			continue
		parts.append("%s=%s" % [kk, str(cfg[k])])
	return "|".join(parts)


static func _prep(cfg: Dictionary) -> Dictionary:
	var key := _key(cfg)
	if _cached.has(key):
		return _cached[key]
	var tab := _table(cfg, 720)
	var d := {
		"tex": _raster(cfg, tab),
		"bb": _bbox_of_table(tab),
	}
	_cached[key] = d
	return d


static func _shared_texture(cfg: Dictionary) -> ImageTexture:
	return _prep(cfg)["tex"]


## R(θ) 表的包围盒（形状空间，**+y 朝下**）。
static func _bbox_of_table(tab: PackedFloat32Array) -> Rect2:
	var k_count := tab.size()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in range(k_count):
		var th := TAU * float(k) / float(k_count)
		var p := Vector2(cos(th) * tab[k], sin(th) * tab[k])
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.y)
	return Rect2(lo, hi - lo)


# ---------------------------------------------------------------- 轮廓

## R(θ) 表：从形状中心朝 θ 方向射一条线，交在离中心多远。
## 所有形状都保证「相对中心是星形的」，一张表就够描述整个轮廓 ——
## 判断内外退化成一句「距离 < R(θ)」，快、且边缘不会抖。
static func _table(cfg: Dictionary, k_count: int) -> PackedFloat32Array:
	var style := str(cfg.get("style", "cloud"))
	if style == "burst":
		return _table_burst(cfg, k_count)
	if style == "spike":
		return _table_spike(cfg, k_count)
	if style == "box_tail" or style == "panel_tail":
		return _poly_table(_poly(cfg), k_count)
	return _table_disks(cfg, k_count)


## 三角波：n 个尖角朝外、n 个尖角朝内。方波会更像齿轮，三角波才像漫画的爆炸。
static func _table_burst(cfg: Dictionary, k_count: int) -> PackedFloat32Array:
	var tab := PackedFloat32Array()
	tab.resize(k_count)
	var n := maxi(6, int(cfg.get("bumps", 13)))
	var mid := float(cfg.get("burst_mid", 1.03))
	var amp := float(cfg.get("burst_amp", 0.36)) * mid
	for k in range(k_count):
		var t := float(n) * float(k) / float(k_count)
		var tri := 4.0 * absf(t - float(int(t + 0.5))) - 1.0     # -1 → +1 → -1
		# 一点点不齐，免得像机器切的
		tab[k] = mid + amp * tri * (1.0 + 0.05 * sin(t * 7.3))
	return tab


## 尖锐星芒：n 根细长的尖刺。尖刺长度逐根不同（手画的），
## 边用 `pow(tri, spike_sharp)` 往内凹 —— 指数 > 1 才会凹，= 1 就是直边星形。
static func _table_spike(cfg: Dictionary, k_count: int) -> PackedFloat32Array:
	var n := maxi(5, int(cfg.get("bumps", 11)))
	var mid := float(cfg.get("spike_mid", 1.00))
	var amp := float(cfg.get("spike_amp", 0.44)) * mid
	var pw := maxf(0.6, float(cfg.get("spike_sharp", 1.40)))
	var jit := clampf(float(cfg.get("jitter", 0.16)), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 20261005))
	var tip := PackedFloat32Array()
	var vs := PackedFloat32Array()
	tip.resize(n)
	vs.resize(n)
	for i in range(n):
		tip[i] = 1.0 + jit * 0.55 * (rng.randf() - 0.5)
		vs[i] = 1.0 + jit * 0.30 * (rng.randf() - 0.5)
	var tab := PackedFloat32Array()
	tab.resize(k_count)
	for k in range(k_count):
		var t := float(n) * float(k) / float(k_count)
		var i := int(t) % n
		var f := t - float(int(t))
		var tri := 1.0 - absf(2.0 * f - 1.0)          # 0 = 谷，1 = 尖
		var outer := mid + amp * tip[i]
		var inner := mid - amp * 0.62 * vs[i]
		tab[k] = inner + (outer - inner) * pow(tri, pw)
	return tab


## 上面那些「一堆圆盘的并集」：cloud / round / square。
static func _table_disks(cfg: Dictionary, k_count: int) -> PackedFloat32Array:
	var tab := PackedFloat32Array()
	tab.resize(k_count)
	var spine := _spine(cfg)
	var cx: PackedFloat32Array = spine[0]
	var cy: PackedFloat32Array = spine[1]
	var cr: PackedFloat32Array = spine[2]
	var nd := cx.size()
	for k in range(k_count):
		var th := TAU * float(k) / float(k_count)
		var ux := cos(th)
		var uy := sin(th)
		var best := 0.0
		for i in range(nd):
			var proj := ux * cx[i] + uy * cy[i]
			var d2 := cx[i] * cx[i] + cy[i] * cy[i]
			var disc := proj * proj - d2 + cr[i] * cr[i]
			if disc <= 0.0:
				continue
			best = maxf(best, proj + sqrt(disc))
		tab[k] = best
	return tab


## 多边形轮廓的 R(θ)：每根射线取**所有交点里最远的那个**。
## 只要形状相对中心是星形的（box_tail / panel_tail 都是：尾巴直接长在底边上、
## 中间没有缝），最远交点就是外轮廓，填充区间就是 [0, R(θ)]，前后一致。
static func _poly_table(poly: PackedVector2Array, k_count: int) -> PackedFloat32Array:
	var tab := PackedFloat32Array()
	tab.resize(k_count)
	var n := poly.size()
	for k in range(k_count):
		var th := TAU * float(k) / float(k_count)
		var ux := cos(th)
		var uy := sin(th)
		var best := 0.0
		for i in range(n):
			var a := poly[i]
			var b := poly[(i + 1) % n]
			var ex := b.x - a.x
			var ey := b.y - a.y
			# 解 t·u = a + s·(b-a)
			var den := ux * ey - uy * ex
			if absf(den) < 1e-9:
				continue
			var t := (a.x * ey - a.y * ex) / den
			if t <= 0.0:
				continue
			var s := 0.0
			if absf(ex) > absf(ey):
				s = (t * ux - a.x) / ex
			else:
				s = (t * uy - a.y) / ey
			if s < 0.0 or s > 1.0:
				continue
			best = maxf(best, t)
		tab[k] = maxf(best, 0.02)
	return tab


## 形状 = 一堆圆盘的并集。返回 [cx, cy, cr]。
##
##   cloud  扇贝边云朵。bumps 个圆盘摆成一圈
##   round  最素的圆。一个圆盘
##   square 圆角方框。圆盘沿着方框的**骨架**密排，间距远小于半径，
##          所以四条边是直的，只有四个角是圆的
static func _spine(cfg: Dictionary) -> Array:
	var style := str(cfg.get("style", "cloud"))
	var jit := clampf(float(cfg.get("jitter", 0.16)), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 20261005))
	var cx := PackedFloat32Array()
	var cy := PackedFloat32Array()
	var cr := PackedFloat32Array()

	if style == "round":
		cx.append(0.0)
		cy.append(0.0)
		cr.append(OUT_R)
	elif style == "square":
		var a := OUT_R - CORNER_R
		var m := maxi(2, int(ceil(2.0 * a / 0.05)))
		for i in range(m + 1):
			var f := -a + 2.0 * a * float(i) / float(m)
			cx.append(f); cy.append(-a); cr.append(CORNER_R)
			cx.append(f); cy.append(a); cr.append(CORNER_R)
			cx.append(-a); cy.append(f); cr.append(CORNER_R)
			cx.append(a); cy.append(f); cr.append(CORNER_R)
	else:
		var n := maxi(6, int(cfg.get("bumps", 11)))
		var ring := 1.0
		# 盘半径必须大于相邻圆心的半弦（ring · sin(π/n)），否则几个鼓包会断开。
		var disk := maxf(0.42, 1.12 * sin(PI / float(n)))
		for i in range(n):
			var ang := (float(i) + jit * 0.35 * (rng.randf() - 0.5)) * TAU / float(n)
			var rr := ring * (1.0 + jit * 0.30 * (rng.randf() - 0.5))
			cx.append(cos(ang) * rr)
			cy.append(sin(ang) * rr)
			cr.append(disk * (1.0 + jit * 0.45 * (rng.randf() - 0.5)))
	return [cx, cy, cr]


# ---------------------------------------------------------------- 方框 + 尾巴

## 圆角方框 + 左下角一条尾巴。
##
## **在「+y 朝上」的自然坐标系里搭**（和 `_poly_table` 要的 +y 朝下相反），
## 搭完在最后统一翻 —— 这样写 tail_tip_y 的时候脑子不用拧着，负数就是「往下伸」。
static func _poly(cfg: Dictionary) -> PackedVector2Array:
	var style := str(cfg.get("style", "box_tail"))
	var hw := float(cfg.get("bw", OUT_R))
	var hh := float(cfg.get("bh", 0.95))
	var r := clampf(float(cfg.get("bcorner", CORNER_R)), 0.02, minf(hw, hh) * 1.2)
	var tx0 := float(cfg.get("tail_x0", -0.26))
	var tx1 := float(cfg.get("tail_x1", -0.98))
	var tip := Vector2(float(cfg.get("tail_tip_x", -0.72)), float(cfg.get("tail_tip_y", -1.62)))

	var pts := PackedVector2Array()
	_line(pts, Vector2(-hw + r, hh), Vector2(hw - r, hh))
	_arc(pts, Vector2(hw - r, hh - r), r, 90.0, 0.0)
	_line(pts, Vector2(hw, hh - r), Vector2(hw, -hh + r))
	_arc(pts, Vector2(hw - r, -hh + r), r, 0.0, -90.0)
	_line(pts, Vector2(hw - r, -hh), Vector2(tx0, -hh))
	pts.append(tip)
	pts.append(Vector2(tx1, -hh))
	_line(pts, Vector2(tx1, -hh), Vector2(-hw + r, -hh))
	_arc(pts, Vector2(-hw + r, -hh + r), r, -90.0, -180.0)
	_line(pts, Vector2(-hw, -hh + r), Vector2(-hw, hh - r))
	_arc(pts, Vector2(-hw + r, hh - r), r, 180.0, 90.0)

	# 手绘感：沿径向叠两条低频正弦，看着就不像 CAD 切的
	_wobble(pts, cfg)

	# 面板：先错切（近大远小那个味道）再整体转一点
	if style == "panel_tail":
		var tilt := deg_to_rad(float(cfg.get("tilt", -7.0)))
		var skew := float(cfg.get("skew", 0.16))
		for i in range(pts.size()):
			var p := pts[i]
			p.x += skew * (p.y / maxf(0.001, hh))
			pts[i] = p.rotated(tilt)

	# 翻到「+y 朝下」
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, -p.y))
	return out


static func _line(pts: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	var n := maxi(1, int(ceil(from.distance_to(to) / 0.09)))
	for i in range(1, n + 1):
		pts.append(from.lerp(to, float(i) / float(n)))


## 从 a0 画到 a1（度），**不含起点** —— 上一段线正好停在起点上，不用重复。
static func _arc(pts: PackedVector2Array, c: Vector2, rr: float, a0: float, a1: float) -> void:
	var n := maxi(4, int(ceil(rr * absf(deg_to_rad(a1 - a0)) / 0.09)))
	for i in range(1, n + 1):
		var a := deg_to_rad(a0 + (a1 - a0) * float(i) / float(n))
		pts.append(c + Vector2(cos(a), sin(a)) * rr)


## 轮廓的径向扰动。只跟 θ 有关，所以扰完还是「一个 θ 对一个半径」—— 星形性保住了。
static func _wobble(pts: PackedVector2Array, cfg: Dictionary) -> void:
	var amt := clampf(float(cfg.get("jitter", 0.16)), 0.0, 1.0) * 0.22
	if amt <= 0.0001:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 20261005)) + 7717
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	for i in range(pts.size()):
		var p := pts[i]
		var th := atan2(p.y, p.x)
		var k := 1.0 + amt * (0.62 * sin(3.0 * th + p1) + 0.38 * sin(5.0 * th + p2))
		pts[i] = p * k


# ---------------------------------------------------------------- 光栅化

static func _raster(cfg: Dictionary, tab: PackedFloat32Array) -> ImageTexture:
	var fill := Color(str(cfg.get("fill", "#FFFFFF")))
	var line := Color(str(cfg.get("line", "#1B1B1B")))
	var ow := maxf(1.0, float(cfg.get("outline", 9.0)))     # 描边总宽（像素，按 TEX_W 算）

	var K := tab.size()

	# --- 底下三个递减的小圆，指着头顶 ---
	var dx := PackedFloat32Array([-0.30, -0.38, -0.42])
	var dy := PackedFloat32Array([1.52, 1.92, 2.22])
	var dr := PackedFloat32Array([0.30, 0.19, 0.11])
	var dots_on := int(cfg.get("dots", 1)) != 0

	# --- 放射线（云朵底下那圈「强调线」）---
	var n_rays := maxi(0, int(cfg.get("rays", 0)))
	var ray_ang := PackedFloat32Array()
	if n_rays > 0:
		var a0 := deg_to_rad(float(cfg.get("ray_from", 55.0)))
		var a1 := deg_to_rad(float(cfg.get("ray_to", 125.0)))
		for j in range(n_rays):
			var f := 0.5 if n_rays == 1 else float(j) / float(n_rays - 1)
			ray_ang.append(a0 + (a1 - a0) * f)
	var ray_len := float(cfg.get("ray_len", 0.46))
	var ray_gap := float(cfg.get("ray_gap", 0.10))
	var ray_w := float(cfg.get("ray_w", 0.055))

	# --- 双线（贴边再压一道细线）---
	var dbl_on := int(cfg.get("double_line", 0)) != 0
	var dbl_gap := float(cfg.get("double_gap", 0.14))
	var dbl_w := maxf(0.6, float(cfg.get("double_width", 3.2)))

	# --- 网点（只铺在指定的那个角附近，越远越淡）---
	var ht_on := int(cfg.get("halftone", 0)) != 0
	var ht_step := maxf(0.05, float(cfg.get("halftone_step", 0.135)))
	var ht_dot := float(cfg.get("halftone_dot", 0.052))
	var ht_x := float(cfg.get("halftone_x", -1.15))
	var ht_y := float(cfg.get("halftone_y", 1.05))
	var ht_reach := maxf(0.2, float(cfg.get("halftone_reach", 1.55)))

	# 形状稍微压扁、拉宽一点，比正圆更像手画的
	var sx := float(cfg.get("sx", 1.10))
	var sy := float(cfg.get("sy", 0.98))

	var u := UNIT
	var ox := TEX_W * 0.5
	var oy := TEX_H * 0.5 - SHAPE_MID * u
	var half := ow * 0.5 / u          # 描边半宽（形状空间单位）
	var dgt := 1.0 / u                # 一个像素等于多少形状单位

	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	for py in range(TEX_H):
		var qy := (float(py) + 0.5 - oy) / sy / u
		for px in range(TEX_W):
			var qx := (float(px) + 0.5 - ox) / sx / u
			var d := sqrt(qx * qx + qy * qy)
			var ang := atan2(qy, qx)
			var f := fposmod(ang, TAU) * float(K) / TAU
			var i0 := int(f) % K
			# 注意：用 float(int(f)) 而不是 floor(f) —— floor() 返回 Variant，
			# 一写 := 就推断不出类型，GDScript 会直接 Parse Error。
			var fr := f - float(int(f))
			var rad := tab[i0] * (1.0 - fr) + tab[(i0 + 1) % K] * fr
			var g := rad - d
			# 放射线不能用 g 表达：g 是「离轮廓的距离」，射线整个位于轮廓**外面**，
			# 拿 g 去算覆盖度的话线里最多只有 0.5（半透明 → 看着是灰的，不是墨线）。
			# 所以它单独带一个覆盖度出来。
			var ray_cov := -1.0

			# 三个小圆：只在这个小范围里才需要算，省掉九成像素
			if dots_on and qy > 1.10 and qx > -0.90 and qx < 0.10:
				for j in range(3):
					var ex := qx - dx[j]
					var ey := qy - dy[j]
					g = maxf(g, dr[j] - sqrt(ex * ex + ey * ey))
			# 放射线：只算形状**外面**、且落在射线那圈半径带里的像素
			elif n_rays > 0 and g < 0.0:
				var rr := -g
				if rr > ray_gap and rr < ray_gap + ray_len:
					var hwr := ray_w * (1.0 - (rr - ray_gap) / ray_len)
					for j in range(n_rays):
						var da := absf(wrapf(ang - ray_ang[j], -PI, PI))
						var pd := da * d
						if pd < hwr:
							ray_cov = clampf(0.5 + (hwr - pd) * u, 0.0, 1.0)
							break

			var cov := ray_cov if ray_cov >= 0.0 else clampf(0.5 + g * u, 0.0, 1.0)
			if cov <= 0.004:
				continue
			# 描边是「骑在边界上」的一圈：|g| < 半宽就是墨线
			var lc := 1.0 if ray_cov >= 0.0 else clampf(0.5 + (half - absf(g)) * u, 0.0, 1.0)
			if dbl_on and ray_cov < 0.0:
				lc = maxf(lc, clampf(0.5 + (dbl_w * 0.5 * dgt - absf(g - dbl_gap)) * u, 0.0, 1.0))
			if ht_on and ray_cov < 0.0 and lc < 0.45:
				var hx := qx - ht_x
				var hy := qy - ht_y
				var ramp := clampf(1.0 - sqrt(hx * hx + hy * hy) / ht_reach, 0.0, 1.0)
				# 阈值别给太低：ramp 快淡到 0 时点半径不到一个像素，
				# 会铺成一层灰蒙蒙的雾（看着像面板上蒙了块脏），而不是网点。
				if ramp > 0.18:
					var gx := fposmod(qx + ht_step * 0.5, ht_step) - ht_step * 0.5
					var gy := fposmod(qy + ht_step * 0.5, ht_step) - ht_step * 0.5
					var rd := ht_dot * ramp
					if gx * gx + gy * gy < rd * rd:
						lc = 1.0
			var c := fill.lerp(line, lc)
			img.set_pixel(px, py, Color(c.r, c.g, c.b, cov))
	return ImageTexture.create_from_image(img)
