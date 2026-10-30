class_name Frontend
extends CanvasLayer
## 进入游戏的那一层：标题页 → （前情提要 / 选幕页）→ 交给 app.gd 去加载那一幕。
##
## 全部 UI 代码生成，没有 .tscn 依赖 —— 和 hud.gd 一个路子。
## 文案与三幕配置全在 data/frontend.json、data/intro.json，改内容不用碰这个文件。
##
## 流程：
##   标题页 ──「开始游戏」──→ 选幕页 ──点第一幕──→ 发出 act_chosen(场景路径)
##        └──「前情提要」──→ 前情提要 + 引导剧情（逐段点开）──→ 选幕页
##
## 锁定态：acts 里 locked=true 的幕点不动，只在下方给一句提示（不弹窗、不跳页）。

signal act_chosen(scene_path: String)

## 六组基色，和 hud.gd 用的是同一套（暖木 / 米白 / 雾蓝 / 鼠尾草绿 / 珊瑚红 / 墨灰）。
## ⚠️ 调色板在 hud.gd 里也有一份 —— 换配色要两个文件一起改。
const C_TEXT := "#4B4A47"
const C_MUTED := "#888780"
const C_CARD := "#FBF6EC"
const C_BORDER := "#C8A57B"
const C_ACCENT := "#D98C6A"
const C_BLUE := "#8FA9C4"
const C_GREEN := "#9BB39A"
## 锁住的幕用的颜色：底色压灰、文字压低对比。
## ⚠ 波普风选幕页里这两行字是叠在美术的**浅灰锁**上的，太浅会糊 —— 所以
##   波普版不用 C_LOCK_TEXT，另用下面这个深一档的灰。
const C_LOCK_BG := "#E8E3D9"
const C_LOCK_TEXT := "#A6A196"
## 波普版锁定文字的灰（叠在美术灰锁上，要比 C_LOCK_TEXT 深一档才读得清）。
const C_POP_LOCK := "#6E6A62"

## ---------------------------------------------------------------- 全局字号总开关
## 2026-10-13：作者要求「整个游戏的字体稍微改大一点」。
##
## 本工程**没有统一的 Theme 资源** —— 三个 UI 脚本各建各的主题、字号也各写各的。
## 所以这里不去改散落在几十处的字号字面量（既不现实，以后也没法一键调回去），
## 而是**只加一个倍数**：本文件的文字全都要经过 `_label()` / `_button()` 这两个
## 口子，在口子里乘一下系数，等于一次性把所有文字**按比例**放大。
##
## ⚠ 同一个开关在 hud.gd / topview.gd 里也各有一份（本工程 UI 常量一向是每个文件
##   一份，三份都带这段注释）。**要调大小就三个文件一起改**，只改一个会让那一屏
##   和别的屏字号对不上。
##
## 1.0 = 原样；1.15 = 放大 15%。实测建议区间 1.0 ~ 1.2：
##   · 再小几乎看不出区别；再大，hud 右上角「已记下的东西」那栏（最小 13px 的条目）
##     会明显需要滚动才能看全（那栏本来就刚好装满）。
const FONT_SCALE := 1.15

## 当前页：title / recap / acts
var page := "title"
## 最近一次点「锁定幕」给出的提示（自检要看它）。
var last_locked_hint := ""

var _ui: Control
var _title_page: Control
var _recap_page: Control
var _acts_page: Control

var _recap_entries: Array = []      ## [{kind, text}, ...] —— 前情提要在前、引导剧情在后
var _recap_index := 0
var _recap_kind: Label
var _recap_text: Label
var _recap_step: Label
var _recap_buttons: HBoxContainer

var _act_hint: Label
var _act_buttons: Array[Button] = []


func _ready() -> void:
	# 比 Hud（layer 10）高一层 —— 进入页永远盖在地图 UI 上面。
	layer = 20

	_ui = Control.new()
	_ui.name = "UI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = _make_theme()
	add_child(_ui)

	_recap_entries = _build_recap_entries()

	_title_page = _build_title_page()
	_recap_page = _build_recap_page()
	_acts_page = _build_acts_page()
	_ui.add_child(_title_page)
	_ui.add_child(_recap_page)
	_ui.add_child(_acts_page)

	show_title()


# ---------------------------------------------------------------- 字体 / 样式

## 把「设计字号」换算成**实际字号** —— 本文件的每一个字号都必须过这里，见 FONT_SCALE。
func _fs(base: int) -> int:
	return maxi(1, int(round(float(base) * FONT_SCALE)))


func _make_theme() -> Theme:
	var th := Theme.new()
	# 优先用工程内自带的字体（发布时用），否则退回系统字体（本机开发用）。
	# ⚠ 两条路都要试：导出后 .ttf 会被 Godot 当作「已导入字体」，**裸文件不再进包** ——
	#   FileAccess 读 res://assets/font.ttf 会返回 false，必须用 ResourceLoader 取 .fontdata。
	#   （2026-10-13 实测：安卓包内只有 fontdata，没有裸 font.ttf；
	#     只走 FileAccess 就会退回系统字体 → 安卓上中文变方框）
	var bundled: Font = null
	if ResourceLoader.exists("res://assets/font.ttf"):
		bundled = load("res://assets/font.ttf") as Font
	elif FileAccess.file_exists("res://assets/font.ttf"):
		var ff := FontFile.new()
		if ff.load_dynamic_font("res://assets/font.ttf") == OK:
			bundled = ff
	if bundled != null:
		th.default_font = bundled
	if th.default_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Microsoft YaHei", "微软雅黑", "Noto Sans CJK SC",
			"Source Han Sans SC", "SimHei", "PingFang SC", "sans-serif",
		])
		sf.allow_system_fallback = true
		th.default_font = sf
	th.default_font_size = _fs(15)
	return th


func _panel_style(bg: String, border: String, radius: int = 14, width: int = 2,
		margin: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg)
	sb.border_color = Color(border)
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## 注意 mouse_filter 一律 IGNORE —— 幕卡是「Button 上面盖一层文字」，
## 文字必须让点击穿到下面的按钮上。
func _label(text: String, size: int = 15, color: String = C_TEXT, wrap_w: float = 0.0,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color(color))
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap_w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_w, 0)
	return l


func _button(text: String, cb: Callable, primary: bool = false, width: float = 170.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 46)
	b.focus_mode = Control.FOCUS_NONE
	var sb := _panel_style(C_ACCENT if primary else "#FFFFFF", C_BORDER, 10, 2, 8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("#FFFFFF") if primary else Color(C_TEXT))
	b.add_theme_color_override("font_hover_color", Color("#FFFFFF") if primary else Color(C_TEXT))
	b.add_theme_font_size_override("font_size", _fs(16))
	b.pressed.connect(cb)
	return b


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## 一页 = 整屏的暖色底 + 一个居中的内容盒。
func _page(name: String, bg: String = "#EDE7DC") -> Control:
	var pg := Control.new()
	pg.name = name
	pg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pg.mouse_filter = Control.MOUSE_FILTER_STOP
	pg.visible = false

	var bgr := ColorRect.new()
	bgr.name = "Bg"
	bgr.set_anchors_preset(Control.PRESET_FULL_RECT)
	bgr.color = Color(bg)
	bgr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pg.add_child(bgr)
	return pg


func _center(parent: Node) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


# ---------------------------------------------------------------- 标题页

func _build_title_page() -> Control:
	# 标题页底色：默认跟着 _page() 的暖灰走。写 `title.bg = "#FFFFFF"` 就变白底 ——
	# logo 里那块「爆炸框的白填充」会溶进白底，不再读成一张白贴纸。
	var t: Dictionary = ContentDB.frontend.get("title", {})
	var bg := str(t.get("bg", ""))
	var pg := _page("Title", bg if bg != "" else "#EDE7DC")

	# ── 波普风版（2026-10-06）：整屏底图 + 素材按设计稿绝对定位 ──
	# data/frontend.json 的 title.pop 一填就走这条路；不填就落到下面那套居中流式布局。
	var pop_raw: Variant = t.get("pop", {})
	if typeof(pop_raw) == TYPE_DICTIONARY and not (pop_raw as Dictionary).is_empty():
		_build_title_pop(pg, pop_raw as Dictionary)
		return pg

	# 作者 2026-10-06 要求：**不要那张卡片边框了**（原来那个暖棕色的圆角框），
	# 也不要「第一幕 · 设计部」那行副标题 —— 上面只留 logo。下面两个选项换成
	# 作者手绘的两张图示（剑 = 开始游戏、猫 = 前情提要）。
	# 所以这里不再有 PanelContainer，整组直接坐在页面底色上。
	var center := _center(pg)
	var box := VBoxContainer.new()
	box.name = "TitleBox"
	# 间距一律用显式 `_gap()` 垫，容器自己的 separation 设 0 —— 三段间距各是各的
	# （logo 与按钮之间要空得多、两个按钮之间要紧），用一个常量套不出来。
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	# 游戏标题 = 作者设计的 logo 图（谁杀死了老板）。找不到图就退回文字标题 ——
	# 换图只改 data/frontend.json，不用碰代码。
	var logo := _logo(t)
	if logo != null:
		box.add_child(logo)
	else:
		box.add_child(_label(str(t.get("name", "谁杀死了老板")), 46, C_TEXT, 0,
			HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_gap(float(t.get("logo_gap", 62))))

	box.add_child(_title_button(t, "start", "BtnStart", show_acts))
	box.add_child(_gap(float(t.get("btn_gap", 14))))
	box.add_child(_title_button(t, "recap", "BtnRecap", show_recap))

	# 「logo 位置靠上一点」：在整组底下垫一块透明高度，整组就往上顶 lift/2（内容外置，
	# 作者想再高一点只改 frontend.json 的 title.lift，不用碰代码）。
	var lift := float(t.get("lift", 0.0))
	if lift > 0.0:
		box.add_child(_gap(lift))

	# 操作提示贴在屏幕底边 —— 它不是上面那组的一部分，卡片没了它也不能跟着飘。
	var foot := _label(str(t.get("footer", "")), 13, C_MUTED, 0, HORIZONTAL_ALIGNMENT_CENTER)
	foot.name = "Footer"
	foot.anchor_left = 0.0
	foot.anchor_right = 1.0
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_top = -48.0
	foot.offset_bottom = -24.0
	foot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pg.add_child(foot)
	return pg


# ---------------------------------------------------------------- 标题页 · 波普风版

## 波普风开始页：一张整屏底图 + 几个按设计稿坐标绝对定位的素材。
##
## 全部内容在 data/frontend.json 的 title.pop 里（bg / design_w / design_h / layers）——
## 这个函数只负责「把设计稿坐标换算成屏幕坐标」，改摆位不用碰代码。
##
## 换算：设计稿 1801×1013 ↔ 当前逻辑视口。取 min(视口宽/设计稿宽, 视口高/设计稿高) 当缩放
## **系数 k**，再居中 —— 等比，所以窗口比例万一不是 16:9 也只是留边，不会把素材拉变形。
## ⛔ 别改用锚点按比例摊：那样横竖各按各的比例缩，比例一变素材就被拉扁。
func _build_title_pop(pg: Control, pop: Dictionary) -> void:
	# ① 整屏底图。设计稿和视口都是 16:9，所以直接铺满 —— 不裁不补。
	var bgpath := str(pop.get("bg", ""))
	if bgpath != "" and ResourceLoader.exists(bgpath):
		var bgr := TextureRect.new()
		bgr.name = "PopBg"
		bgr.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgr.texture = load(bgpath)
		bgr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgr.stretch_mode = TextureRect.STRETCH_SCALE
		bgr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pg.add_child(bgr)
	else:
		push_warning("[frontend] 波普底图读不出来（%s）—— 只画素材层" % bgpath)

	# ② 素材层。
	var dw := maxf(1.0, float(pop.get("design_w", 1801)))
	var dh := maxf(1.0, float(pop.get("design_h", 1013)))
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 1.0 or vs.y <= 1.0:
		vs = Vector2(1600.0, 900.0)      # 视口还没排好时的兜底（= 工程基准分辨率）
	var k := minf(vs.x / dw, vs.y / dh)
	var ox := (vs.x - dw * k) * 0.5
	var oy := (vs.y - dh * k) * 0.5

	for raw in pop.get("layers", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var L: Dictionary = raw
		var tpath := str(L.get("tex", ""))
		if tpath == "" or not ResourceLoader.exists(tpath):
			push_warning("[frontend] 波普素材找不到（%s）" % tpath)
			continue
		var tex: Texture2D = load(tpath)
		if tex == null or tex.get_width() <= 0:
			push_warning("[frontend] 波普素材读不出来（%s）" % tpath)
			continue
		var s := float(L.get("s", 1.0))
		var sz := Vector2(tex.get_width() * s * k, tex.get_height() * s * k)
		var pos := Vector2(ox + float(L.get("x", 0.0)) * k, oy + float(L.get("y", 0.0)) * k)
		var act := str(L.get("action", ""))
		if act != "":
			pg.add_child(_pop_button(L, tex, pos, sz, act))
		else:
			pg.add_child(_pop_logo(tex, pos, sz))


## 波普版里「不带 action」的层 = 纯图片（就是 logo）。
## ⛔ 名字必须叫 Logo —— 自检按这个名字找它，验「图挂上了 / 四角透明 / 没被拉变形」。
func _pop_logo(tex: Texture2D, pos: Vector2, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.name = "Logo"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.position = pos
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 波普版里「带 action」的层 = 按钮。尺寸已按素材长宽比算好，所以 STRETCH_SCALE 不会拉变形。
## 悬停 / 按下的反馈和旧版一样走缩放（⛔ 黑白线稿用 modulate 提亮没用：0 × 1.1 还是 0）。
func _pop_button(L: Dictionary, tex: Texture2D, pos: Vector2, sz: Vector2, act: String) -> TextureButton:
	var b := TextureButton.new()
	b.name = "BtnStart" if act == "start" else "BtnRecap"
	b.texture_normal = tex
	b.ignore_texture_size = true      # 尺寸我们自己给了，别让纹理尺寸顶掉
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("label", str(L.get("label", "")))   # 图示按钮没有 text，名字存这儿（自检靠它找）
	b.pressed.connect(show_acts if act == "start" else show_recap)
	b.mouse_entered.connect(_hover_btn.bind(b, true))
	b.mouse_exited.connect(_hover_btn.bind(b, false))
	b.button_down.connect(_press_btn.bind(b, true))
	b.button_up.connect(_press_btn.bind(b, false))
	return b


## 标题页的按钮 = 作者手绘的图示（TextureButton）。
##
## 图路径写在 data/frontend.json 的 title.btn_start / title.btn_recap，宽度写 btn_w
## （高度按图片长宽比自动算）。两条图由 `tools/btn_prep.py` 从白底 JPG 抠成透明底，
## **并且统一到同一块画布上** —— 所以两张图尺寸相同、里面的黑条一样大、条心对齐，
## 这里只要保证两张都用同一个 btn_w 就行，不用单独调某一个。
##
## 图找不到就退回老的文字按钮 —— 界面不会开天窗，改内容不用碰代码。
func _title_button(t: Dictionary, key: String, node_name: String, cb: Callable) -> BaseButton:
	var label := str(ContentDB.frontend.get("%s_label" % key, ""))
	var path := str(t.get("btn_%s" % key, ""))
	if path != "" and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null and tex.get_width() > 0:
			var b := TextureButton.new()
			b.name = node_name
			b.texture_normal = tex
			b.ignore_texture_size = true
			b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			var w := float(t.get("btn_w", 300))
			b.custom_minimum_size = Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			b.focus_mode = Control.FOCUS_NONE
			b.set_meta("label", label)      # 图示按钮没有 text，名字存这儿（自检靠它找）
			b.pressed.connect(cb)
			b.mouse_entered.connect(_hover_btn.bind(b, true))
			b.mouse_exited.connect(_hover_btn.bind(b, false))
			b.button_down.connect(_press_btn.bind(b, true))
			b.button_up.connect(_press_btn.bind(b, false))
			return b
		push_warning("[frontend] 标题按钮图读不出来（%s）—— 退回文字按钮" % path)
	else:
		push_warning("[frontend] 找不到标题按钮图（%s）—— 退回文字按钮" % path)
	var fb := _button(label, cb, key == "start", 320.0)
	fb.name = node_name
	return fb


## 鼠标悬停 / 按下的反馈。⛔ 图示是「黑线 + 白底」，**别用 modulate 提亮** ——
## 乘 1.1 对 0（黑）还是 0，等于没反应。改成轻微缩放：悬停放大 3%、按下缩到 97%。
## 缩放只影响绘制不影响布局，所以 pivot 要显式设成控件中心。
func _hover_btn(b: BaseButton, on: bool) -> void:
	if b == null or not is_inside_tree():
		return
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2.ONE * (1.03 if on else 1.0), 0.12)


func _press_btn(b: BaseButton, down: bool) -> void:
	if b == null or not is_inside_tree():
		return
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.08)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 标题用的 logo 图。路径与宽度写在 data/frontend.json 的 title.logo / title.logo_w。
##
## ⛔ 这张图必须是**透明底 PNG**。作者给的是**白底 JPG**，直接贴上来会在页面底色上
##    糊出一个白方块 —— 所以先过一遍 `tools/logo_prep.py`（从画布边缘灌水把白底抠掉，
##    杯子、剑刃、白星星这些被黑描边圈起来的白都留着）。
##
## 尺寸：只给宽度，高度按图片自己的长宽比算 —— 换一张图不用改任何数字。
## 找不到图就返回 null，标题页自动退回那行文字标题（改内容不用碰代码）。
func _logo(t: Dictionary) -> TextureRect:
	var path := str(t.get("logo", ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[frontend] 找不到标题 logo（%s）—— 退回文字标题" % path)
		return null
	var tex: Texture2D = load(path)
	if tex == null or tex.get_width() <= 0:
		push_warning("[frontend] 标题 logo 读不出来（%s）—— 退回文字标题" % path)
		return null

	var w := float(t.get("logo_w", 680))
	var h := w * float(tex.get_height()) / float(tex.get_width())
	var r := TextureRect.new()
	r.name = "Logo"
	r.texture = tex
	# 尺寸由我们自己按长宽比算好，所以让贴图直接铺满控件、按比例居中 —— 不会拉变形。
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(w, h)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ---------------------------------------------------------------- 前情提要 / 引导剧情

func _build_recap_page() -> Control:
	var pg := _page("Recap")
	var center := _center(pg)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(760, 330)
	card.add_theme_stylebox_override("panel", _panel_style(C_CARD, C_BORDER, 22, 3, 30))
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	_recap_kind = _label("", 15, C_BLUE)
	box.add_child(_recap_kind)

	_recap_text = _label("", 21, C_TEXT, 690)
	_recap_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_recap_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_recap_text)

	_recap_step = _label("", 13, C_MUTED)
	box.add_child(_recap_step)

	_recap_buttons = HBoxContainer.new()
	_recap_buttons.alignment = BoxContainer.ALIGNMENT_END
	_recap_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_recap_buttons)
	return pg


func _refresh_recap() -> void:
	if _recap_buttons == null:
		return
	_clear(_recap_buttons)

	var end_label := str(ContentDB.intro.get("end_label", "进入选幕"))
	if _recap_entries.is_empty():
		# 还没填剧情时的兜底 —— 不能因为内容是空的就把流程卡死在这儿。
		_recap_kind.text = "还没填"
		_recap_text.text = "前情提要和引导剧情都还是空的。\n把 data/intro.json 里的 recap / intro 两个数组填上就有了。"
		_recap_step.text = ""
		_recap_buttons.add_child(_button(end_label, show_acts, true, 180.0))
		return

	var i := clampi(_recap_index, 0, _recap_entries.size() - 1)
	var e: Dictionary = _recap_entries[i]
	_recap_kind.text = str(e.get("kind", ""))
	_recap_text.text = str(e.get("text", ""))
	_recap_step.text = "%d / %d" % [i + 1, _recap_entries.size()]

	if i >= _recap_entries.size() - 1:
		_recap_buttons.add_child(_button(end_label, show_acts, true, 180.0))
	else:
		_recap_buttons.add_child(_button(str(ContentDB.intro.get("skip_label", "跳过")), show_acts, false, 120.0))
		_recap_buttons.add_child(_button("继续", advance_recap, true, 140.0))


## 点一下出下一条；已经是最后一条就停住（由「进入选幕」按钮接走）。
func advance_recap() -> void:
	if _recap_entries.is_empty():
		return
	if _recap_index < _recap_entries.size() - 1:
		_recap_index += 1
		_refresh_recap()


# ---------------------------------------------------------------- 选幕页

func _build_acts_page() -> Control:
	var pg := _page("Acts")

	# ── 波普风版（2026-10-05，作者给的第二页平面美术）──
	# data/frontend.json 的 acts_pop 一填就走这条路；不填就落到下面那套居中卡片布局。
	var pop_raw: Variant = ContentDB.frontend.get("acts_pop", {})
	if typeof(pop_raw) == TYPE_DICTIONARY and not (pop_raw as Dictionary).is_empty():
		_build_acts_pop(pg, pop_raw as Dictionary)
		return pg

	var center := _center(pg)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	box.add_child(_label(str(ContentDB.frontend.get("acts_title", "选择第几幕")), 34, C_TEXT, 0,
		HORIZONTAL_ALIGNMENT_CENTER))

	var row := HBoxContainer.new()
	row.name = "ActRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)

	_act_buttons.clear()
	var acts: Variant = ContentDB.frontend.get("acts", [])
	if typeof(acts) == TYPE_ARRAY:
		for i in range(acts.size()):
			if typeof(acts[i]) != TYPE_DICTIONARY:
				continue
			var b := _act_card(acts[i], i)
			row.add_child(b)
			_act_buttons.append(b)

	_act_hint = _label(str(ContentDB.frontend.get("acts_hint", "")), 15, C_MUTED, 660,
		HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_act_hint)

	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(_button(str(ContentDB.frontend.get("back_label", "返回标题")), show_title, false, 150.0))
	box.add_child(back_row)
	return pg


## 波普风选幕页（作者 2026-10-05 给的第二页平面美术）。
##
## 美术上**已经把三个面板画好了**（设计A组 / 秘书处 / 老板办公室），所以这里
## 不再画卡片底 —— 只在这三块上面盖「透明按钮」占住点击区 + 叠一行幕名文字。
## 布景全在 data/frontend.json 的 acts_pop 里（rect 用底图设计稿像素），改摆位不用碰代码。
##
## 换算和标题页同一套：取 min(视口/设计稿) 当系数 k、居中 —— 等比，窗口比例变了只留边。
func _build_acts_pop(pg: Control, pop: Dictionary) -> void:
	# ① 整屏底图。
	var bgpath := str(pop.get("bg", ""))
	if bgpath != "" and ResourceLoader.exists(bgpath):
		var bgr := TextureRect.new()
		bgr.name = "PopBg"
		bgr.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgr.texture = load(bgpath)
		bgr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgr.stretch_mode = TextureRect.STRETCH_SCALE
		bgr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pg.add_child(bgr)
	else:
		push_warning("[frontend] 选幕页底图读不出来（%s）—— 只画按钮层" % bgpath)

	var dw := maxf(1.0, float(pop.get("design_w", 1920)))
	var dh := maxf(1.0, float(pop.get("design_h", 1080)))
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 1.0 or vs.y <= 1.0:
		vs = Vector2(1600.0, 900.0)
	var k := minf(vs.x / dw, vs.y / dh)
	var ox := (vs.x - dw * k) * 0.5
	var oy := (vs.y - dh * k) * 0.5

	# ② 三张幕卡：透明按钮占点击区 + 上面盖一层文字（mouse_filter 全 IGNORE）。
	var acts: Variant = ContentDB.frontend.get("acts", [])
	var cards: Variant = pop.get("cards", [])
	_act_buttons.clear()
	if typeof(cards) == TYPE_ARRAY:
		for i in range(cards.size()):
			if typeof(cards[i]) != TYPE_DICTIONARY:
				continue
			var card: Dictionary = cards[i]
			var r := _pop_rect(card.get("rect"), Vector4(0, 0, 100, 100))
			var pos := Vector2(ox + r.x * k, oy + r.y * k)
			var sz := Vector2((r.z - r.x) * k, (r.w - r.y) * k)
			var act_d: Dictionary = (acts[i] as Dictionary) if (typeof(acts) == TYPE_ARRAY
				and i < (acts as Array).size() and typeof(acts[i]) == TYPE_DICTIONARY) else {}
			var b := _act_hit(card, act_d, i, pos, sz)
			pg.add_child(b)
			_act_buttons.append(b)

	# ③ 返回按钮：盖在美术里那个「返回」胶囊上，同样用透明按钮接点击
	#    （美术已经把胶囊画好了，再画一个反而double）。
	var back: Variant = pop.get("back", {})
	if typeof(back) == TYPE_DICTIONARY and not (back as Dictionary).is_empty():
		var bd: Dictionary = back
		var r2 := _pop_rect(bd.get("rect"), Vector4(900, 743, 1034, 856))
		var bp := Vector2(ox + r2.x * k, oy + r2.y * k)
		var bs := Vector2((r2.z - r2.x) * k, (r2.w - r2.y) * k)
		var bb := _acts_back_hit(str(bd.get("label", ContentDB.frontend.get("back_label", "返回标题"))),
			bp, bs)
		pg.add_child(bb)

	# ④ 一行提示（点锁定幕时冒出来的那句）。卡片下面是黑白格 + 青，纯字读不清 ——
	#    所以垫一块**半透明白胶囊**，字压在上面。位置写在 acts_pop.hint_y（设计稿像素）。
	#    ⛔ 自检要读 `act_hint_text()`，所以这个 Label 必须挂到 `_act_hint` 上。
	var hint_y := float(pop.get("hint_y", 596.0))
	var hrow := CenterContainer.new()
	hrow.name = "HintRow"
	hrow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hrow.offset_top = oy + hint_y * k
	hrow.offset_bottom = oy + hint_y * k + 34.0
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pg.add_child(hrow)
	var pill := PanelContainer.new()
	pill.name = "HintPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.99, 0.97, 0.94, 0.88)
	hb.set_corner_radius_all(13)
	hb.set_content_margin_all(9)
	pill.add_theme_stylebox_override("panel", hb)
	hrow.add_child(pill)
	_act_hint = _label(str(ContentDB.frontend.get("acts_hint", "")), 16, C_TEXT, 0,
		HORIZONTAL_ALIGNMENT_CENTER)
	pill.add_child(_act_hint)


## 把 JSON 里的 rect（[x0,y0,x1,y1]，底图设计稿像素）读成 Vector4。
## 兼容两种写法：数组 4 个数、或字典 {x,y,w,h}。缺省用 fallback。
func _pop_rect(raw: Variant, fallback: Vector4) -> Vector4:
	if typeof(raw) == TYPE_ARRAY:
		var arr: Array = raw
		if arr.size() >= 4:
			return Vector4(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	elif typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw
		var x := float(d.get("x", fallback.x))
		var y := float(d.get("y", fallback.y))
		var w := float(d.get("w", fallback.z - fallback.x))
		var h := float(d.get("h", fallback.w - fallback.y))
		return Vector4(x, y, x + w, y + h)
	return fallback


## 波普版的一张幕卡 = 透明 Button（占住美术上画好的面板）+ 叠一层「幕名 / 地点 / 说明」。
## 锁住的幕：名字压暗 + 多一行「已锁定」，并且点了只给提示（和旧版行为一致）。
##
## ⛔ 名字必须叫 Act_1 / Act_2 / Act_3 —— 自检按 act_button(i) 取，那本数组就是它。
func _act_hit(card: Dictionary, act: Dictionary, index: int, pos: Vector2, sz: Vector2) -> Button:
	var locked := bool(act.get("locked", false))

	var b := Button.new()
	b.name = "Act_%d" % (index + 1)
	b.text = ""
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("act_index", index)
	b.set_meta("locked", locked)
	b.set_meta("label", str(card.get("label", "")))
	# 透明底：美术上的面板本身就是要露出来的，按钮只负责接点击。
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.pressed.connect(_on_act_pressed.bind(index))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6.0
	# ⭐ 文字从卡片顶往下留 12% 开始排 —— 美术卡片的**最顶上是一条窗标题栏**
	#    （带 × 号那条窄带），压上去会被裁掉；往下让开它，文字落在白色内容区的上沿。
	box.offset_top = sz.y * 0.12
	box.offset_right = -6.0
	box.offset_bottom = -6.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⭐ 文字**贴卡片上部**，别居中 —— 美术卡片中间印着房间名（设计A组 / 秘书处 /
	#    老板办公室）、底下是 YES/NO，居中会跟房间名撞车。
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 1)
	b.add_child(box)

	# 幕名（第一幕 / 第二幕 / 第三幕）：一行就够 —— 房间名美术已经印在卡片上了。
	box.add_child(_label(str(act.get("name", "第 %d 幕" % (index + 1))), 18,
		C_POP_LOCK if locked else C_TEXT, sz.x - 12.0, HORIZONTAL_ALIGNMENT_CENTER))
	# 地点 + 锁定态压成一行小字（解锁的是珊瑚色、锁住的压灰）。
	# ⭐ 地点可以留空（第二、三幕还没定名）—— 那就只显示「已锁定」，
	#    不会留一个孤零零的「·」分隔点。
	var sub := str(act.get("place", "")).strip_edges()
	if locked:
		sub = "已锁定" if sub == "" else sub + "　·　已锁定"
	if sub != "":
		box.add_child(_label(sub, 13, C_POP_LOCK if locked else C_ACCENT, sz.x - 12.0,
			HORIZONTAL_ALIGNMENT_CENTER))
	return b


## 波普版的「返回」按钮 = 盖在美术那个胶囊上的透明按钮。
## ⛔ **不要再写文字** —— 美术的胶囊里已经印着「返回」了，再加一层就重影。
## （旧版居中布局的「返回标题」四个字是文字按钮；波普版改成只接点击。）
func _acts_back_hit(label: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.name = "BtnBack"
	b.text = ""
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("label", label)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.pressed.connect(show_title)
	b.mouse_entered.connect(_hover_btn.bind(b, true))
	b.mouse_exited.connect(_hover_btn.bind(b, false))
	return b


## 一张幕卡 = 一个 Button（负责点击）+ 上面盖一层文字（mouse_filter 全 IGNORE）。
## 第一幕是米白卡片，锁住的幕压成灰底灰字 —— 一眼能看出哪个能点。
func _act_card(act: Dictionary, index: int) -> Button:
	var locked := bool(act.get("locked", false))

	var b := Button.new()
	b.name = "Act_%d" % (index + 1)
	b.text = ""
	b.custom_minimum_size = Vector2(224, 200)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("act_index", index)
	b.set_meta("locked", locked)

	var sb := _panel_style(C_LOCK_BG if locked else C_CARD,
		C_LOCK_TEXT if locked else C_BORDER, 16, 2, 0)
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_on_act_pressed.bind(index))

	var col := C_LOCK_TEXT if locked else C_TEXT
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18.0
	box.offset_top = 18.0
	box.offset_right = -18.0
	box.offset_bottom = -18.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	b.add_child(box)

	box.add_child(_label(str(act.get("name", "第 %d 幕" % (index + 1))), 26, col, 188,
		HORIZONTAL_ALIGNMENT_CENTER))
	# place / desc 允许留空（第二、三幕还没定名）—— 空就整行不建，别留一行空白。
	var place_txt := str(act.get("place", "")).strip_edges()
	if place_txt != "":
		box.add_child(_label(place_txt, 16, C_LOCK_TEXT if locked else C_ACCENT, 188,
			HORIZONTAL_ALIGNMENT_CENTER))
	var desc_txt := str(act.get("desc", "")).strip_edges()
	if desc_txt != "":
		box.add_child(_gap(8))
		box.add_child(_label(desc_txt, 13, C_LOCK_TEXT if locked else C_MUTED, 188,
			HORIZONTAL_ALIGNMENT_CENTER))
	if locked:
		box.add_child(_label("已锁定", 14, C_LOCK_TEXT, 188, HORIZONTAL_ALIGNMENT_CENTER))
	return b


func _on_act_pressed(index: int) -> void:
	var acts: Variant = ContentDB.frontend.get("acts", [])
	if typeof(acts) != TYPE_ARRAY or index < 0 or index >= acts.size():
		return
	var act: Dictionary = acts[index]
	var act_name := str(act.get("name", "第 %d 幕" % (index + 1)))

	if bool(act.get("locked", false)):
		last_locked_hint = str(ContentDB.frontend.get("locked_hint", "%s 还没做。")) % act_name
		_set_act_hint(last_locked_hint, C_ACCENT)
		if index < _act_buttons.size():
			_flash(_act_buttons[index])
		return

	var path := str(act.get("scene", ""))
	if path == "":
		last_locked_hint = "%s 没有配场景 —— 改 data/frontend.json 里的 scene。" % act_name
		_set_act_hint(last_locked_hint, C_ACCENT)
		return

	_set_act_hint("正在进入 %s ……" % act_name, C_GREEN)
	act_chosen.emit(path)


func _set_act_hint(text: String, color: String) -> void:
	if _act_hint == null:
		return
	_act_hint.text = text
	_act_hint.add_theme_color_override("font_color", Color(color))


## 点锁定幕时卡片闪一下，让「点了但没反应」有个可见的回应。
func _flash(b: Button) -> void:
	if b == null or not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(b, "modulate", Color(1.0, 1.0, 1.0, 0.45), 0.08)
	tw.tween_property(b, "modulate", Color.WHITE, 0.22)


# ---------------------------------------------------------------- 翻页

func _set_page(name: String) -> void:
	page = name
	# 进入页的三个子页（标题 / 前情 / 选幕）都走这里 —— BGM 在每个「页面入口」显式点一次，
	# 将来新增分支才不会漏掉音乐。同一首曲子重复点会自己 return，不会把音乐打回开头。
	Audio.play_bgm()
	if _title_page != null:
		_title_page.visible = name == "title"
	if _recap_page != null:
		_recap_page.visible = name == "recap"
	if _acts_page != null:
		_acts_page.visible = name == "acts"


func show_title() -> void:
	_set_page("title")


## 前情提要：从第一条重新放，先 recap、再 intro。
func show_recap() -> void:
	_recap_index = 0
	_refresh_recap()
	_set_page("recap")


func show_acts() -> void:
	_set_act_hint(str(ContentDB.frontend.get("acts_hint", "")), C_MUTED)
	_set_page("acts")


# ---------------------------------------------------------------- 给自检 / 调试用的口子

func act_button(index: int) -> Button:
	return _act_buttons[index] if index >= 0 and index < _act_buttons.size() else null


func act_hint_text() -> String:
	return _act_hint.text if _act_hint != null else ""


func recap_total() -> int:
	return _recap_entries.size()


func recap_index() -> int:
	return _recap_index


func recap_text() -> String:
	return _recap_text.text if _recap_text != null else ""


func recap_kind() -> String:
	return _recap_kind.text if _recap_kind != null else ""


## 按按钮上的文字找按钮（自检用；也方便以后改文案时对不上时排查）。
## ⚠ 标题页那两个按钮现在是**图示**（TextureButton），身上没有文字 —— 名字存在
##    meta `label` 里，所以这里两种都要认。返回 BaseButton（Button 和 TextureButton
##    的共同父类），调用方只用到 `pressed` 信号。
func find_button(label: String) -> BaseButton:
	var stack: Array[Node] = [_ui]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var b := cur as BaseButton
		if b != null:
			var with_text := cur as Button
			if (with_text != null and with_text.text == label) \
					or str(cur.get_meta("label", "")) == label:
				return b
		for c in cur.get_children():
			stack.append(c)
	return null


# ---------------------------------------------------------------- 数据

## 前情提要在前、引导剧情在后，拍成一条一条。
func _build_recap_entries() -> Array:
	var out: Array = []
	var recap_title := str(ContentDB.intro.get("title", "前情提要"))
	var intro_title := str(ContentDB.intro.get("intro_title", "引导剧情"))
	for t in _str_array(ContentDB.intro.get("recap", [])):
		out.append({"kind": recap_title, "text": t})
	for t in _str_array(ContentDB.intro.get("intro", [])):
		out.append({"kind": intro_title, "text": t})
	return out


func _str_array(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for s in raw:
		var t := str(s)
		if t.strip_edges() != "":
			out.append(t)
	return out
