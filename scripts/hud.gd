class_name Hud
extends CanvasLayer
## 全部 UI 都在代码里生成，没有 .tscn 依赖 —— 少一处会坏的地方。
##
## 2026-10-05 晚大改：作者给了一套**手绘波普风**的新底图，要求
##   · 线索框（点感叹号弹出来的）从「白底圆角卡」改成 `card_clue.png`（波点纸 + 大问号）
##   · 右上角「已记下的东西」面板从卡片改成 `card_journal.png`（波点纸 + 星）
## 2026-10-13：作者**重画了这两张框**（问号更收敛、去掉便签铅笔），底图由
##   tools/ui_card_reprep.py 重新抠出 —— 下面的 AR / SAFE 四个常量同步换过。
##   ⛔ 换底图**必须**一起改这四个常量：底图是按这两个比例被拉伸铺满卡片的，
##      比例不改，新框就会被拉歪/压扁。
## 2026-10-13 二次：作者要求「整个游戏的字体稍微改大一点」—— 见下面的 FONT_SCALE。
##   字号没有逐处改，全部从 `_label()` / `_button()` 两个口子统一乘系数。
## 所以本文件现在有两种版式：
##   1. **纸卡版式**（_build_paper_modal）：底图是一张手绘纸，文字必须落在**纸的空白区**里。
##      空白区不是猜的 —— 是 tools/ui_card_prep.py（首版）/ ui_card_reprep.py（2026-10-13 换图）
##      量出来的比例（见 CARD_* 常量）。
##   2. **普通卡版式**：老的白底圆角卡（答对/答错反馈、幕结束还在用）。
##
## ⚠ 叠字用**绝对定位**而不是容器流式布局 —— 纸上的空白区是不规则手绘的，
##   只有按比例定死左右边距才能保证文字不压到黑框和问号。

signal option_chosen(qid: String, index: int)
signal modal_closed()
signal restart_requested()
## 轮末过场点了「继续搜证」—— 外层推进到下一轮（线索刷新）。
signal advance_requested()
## 2026-10-14 回顾入口（右上角「回顾 ▼」）选中某项时发出来。
##   `kind` = "round"（`index` = 轮次，0 起）或 "questions"（`index` 恒为 0）。
## ⛔ 内容由 main.gd 组装后回灌（`show_review_round` / `show_review_questions`）——
##    hud 只负责画，「没到达的轮次不可点」这条规则只写在 main 里一处。
signal review_requested(kind: String, index: int)

const C_TEXT := "#4B4A47"
const C_MUTED := "#888780"
const C_CARD := "#FBF6EC"
const C_BORDER := "#C8A57B"
const C_ACCENT := "#D98C6A"
const C_BLUE := "#8FA9C4"
const C_GREEN := "#9BB39A"
## 回顾列表里「超链接」条目的墨蓝（2026-10-14 新增，只用于回顾页，不影响别处）。
const C_LINK := "#2C5C86"
## 回顾下拉面板的固定宽度（含 _panel_style 的 16px 内边距 ×2 + 190px 行宽）。
const REVIEW_MENU_W := 222.0
## 回顾列表每页几条。⛔ 别调大过 7：纸卡内容超高时 `_layout_paper_text` 会把
## 整页等比缩小（最低 0.58），条目一多就糊成一团 —— 分页比缩字好看得多。
const REVIEW_PAGE := 6

## ---------------------------------------------------------------- 全局字号总开关
## 2026-10-13：作者要求「整个游戏的字体稍微改大一点」。
##
## 本工程**没有统一的 Theme 资源** —— 三个 UI 脚本各建各的主题、字号也各写各的。
## 所以这里不去改散落在几十处的字号字面量（既不现实，以后也没法一键调回去），
## 而是**只加一个倍数**：本文件的文字全都要经过 `_label()` / `_button()` /
## `_paper_button()` 这几个口子，在口子里乘一下系数，等于一次性把所有文字
## **按比例**放大。
##
## ⚠ 同一个开关在 frontend.gd / topview.gd 里也各有一份（本工程 UI 常量一向是
##   每个文件一份，三份都带这段注释）。**要调大小就三个文件一起改**。
##
## 1.0 = 原样；1.15 = 放大 15%。实测建议区间 1.0 ~ 1.2：
##   · 再小几乎看不出区别；再大，右边「已记下的东西」那栏（最小 13px 的条目）
##     会明显要滚动才能看全 —— 那栏本来就刚好装满一张便签纸。
const FONT_SCALE := 1.15

## ---------------------------------------------------------------- 纸卡底图
## 两张纸的比例和**安全区**都来自 tools/ui_card_reprep.py 的实测输出。
## 安全区 = 黑框内侧能写字的地方，用**占整图的比例**表示（跟缩放无关）。
const TEX_CLUE := "res://assets/textures/ui/card_clue.png"
const TEX_JOURNAL := "res://assets/textures/ui/card_journal.png"
## 线索框（点感叹号弹出）：输出图 1062×1556（**已经裁到黑框本身**，卡片矩形边就是框边）。
## ⚠ 2026-10-06：之前这里放的是「整张照片」的尺寸，卡片里白纸黑框只占中间一块、
##   四周全是波点纸 —— 作者看到的就是「框没显示全」。现在换成抠好的版本。
## ⚠ 上边界让开框内右上那只大问号（2026-10-13 版它占到卡片 31% 高），可写区在纸的中下部。
const CARD_CLUE_AR := 0.682519
const CARD_CLUE_SAFE := Vector4(0.104, 0.312, 0.902, 0.931)
## 记录框（右上角「已记下的东西」）：输出图 1110×1611，同样已裁到「黑框 + 右上星」。
## 上边界让开框内右上那颗星（占卡片 20% 高）。
const CARD_JOURNAL_AR := 0.689013
const CARD_JOURNAL_SAFE := Vector4(0.101, 0.200, 0.917, 0.934)

## 线索框在屏幕上的高度（像素）。宽度按底图比例算。
## 定 620 的理由：一屏 1152 高（录制用 1920×1080 时更小），减去上下留白还有余量，
## 而且纸上的正文一行约能放 34 个中文字（够写「一张年会奖券压在杯子底下，
## 一等奖是「和老板共进晚饭」。」这种长度的一行）。
const CARD_CLUE_H := 620.0
## 右侧便签面板的宽度（像素）。高度按底图比例。
## 定 330：原面板 314 宽。安全区左右各让掉 ~13% 之后（贴图缩下来边距会变窄，
## 见 CARD_JOURNAL_SAFE 的注释），实际可写宽约 260px —— 一行能放 16 个中文字。
const CARD_JOURNAL_W := 330.0

var modal_visible := false
## 纸卡的出口状态：
##   `_modal_closable` = 允许「点窗外 / ESC」关（「知道了」这类）；
##   `_modal_fire`     = 关掉之后要不要补发 `modal_closed`
##                       （判断题反馈要发，外层靠它决定还有没有下一题；看线索不发）。
var _modal_closable := false
var _modal_fire := false

var _ui: Control
var _chip: Label
var _hint_label: Label
var _journal_root: Control
var _journal_box: VBoxContainer
var _journal_empty: Label
var _scroll: ScrollContainer          ## 「已记下的东西」的滚动容器（条目会越攒越长）
var _modal_layer: Control
var _body: VBoxContainer
var _title: Label
var _modal_col: VBoxContainer
var _modal_pad: MarginContainer
var _modal_paper_box: Control
var _modal_paper: TextureRect

## ---- 回顾（2026-10-14 新增）----
var _review_chip_node: Button          ## 右上角「回顾 ▼」
var _review_menu: PanelContainer       ## 点开后浮在下方的下拉
var _review_menu_box: VBoxContainer
var _tip: PanelContainer               ## 悬停提示（自建，不用原生 tooltip，见 _build_tip）
var _tip_label: Label
var _review_round_no := 0              ## 当前正在看的轮次（显示用）
var _review_entries: Array = []        ## 当前轮次的结论条目（main 组装）
var _review_page := 0                  ## 结论列表翻到第几页
var _review_qs: Array = []             ## 判断题条目（main 组装）
var _review_q_page := 0                ## 判断题列表翻到第几页
## main.gd 注入：返回下拉菜单要显示的模型（哪些轮次已到达 / 已记几条 / 判断题能不能点）。
var review_menu_model: Callable


func _ready() -> void:
	layer = 10
	_ui = Control.new()
	_ui.name = "UI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = _make_theme()
	add_child(_ui)
	_build_chip()
	_build_journal()
	_build_hint()
	_build_modal()
	# 这两个最后建 —— 要盖在纸卡层上面（下拉、悬停提示都该浮在最上层）。
	_build_review_menu()
	_build_tip()


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


func _panel_style(bg: String, border: String, radius: int = 14, width: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg)
	sb.border_color = Color(border)
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(16)
	return sb


func _label(text: String, size: int = 15, color: String = C_TEXT, wrap_w: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color(color))
	if wrap_w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_w, 0)
	return l


func _button(text: String, cb: Callable, primary: bool = false, width: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 44)
	var sb := _panel_style(C_ACCENT if primary else "#FFFFFF", C_BORDER, 10, 2)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("#FFFFFF") if primary else Color(C_TEXT))
	b.add_theme_color_override("font_hover_color", Color("#FFFFFF") if primary else Color(C_TEXT))
	b.add_theme_font_size_override("font_size", _fs(16))
	b.pressed.connect(cb)
	return b


## 手绘纸上的按钮：作者画的纸是**白纸 + 黑线**，所以按钮也走同一套 ——
## 白底 + 粗黑描边 + 黑字，跟纸是一家的。旧的珊瑚红实心按钮摆上去像贴纸。
func _paper_button(text: String, cb: Callable, width: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 42)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#FFFFFF")
	sb.border_color = Color("#1B1B1B")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color("#F0EDE4")
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, hov if k == "hover" else sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("#1B1B1B"))
	b.add_theme_color_override("font_hover_color", Color("#1B1B1B"))
	b.add_theme_font_size_override("font_size", _fs(16))
	b.pressed.connect(cb)
	return b


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------- 常驻组件

func _build_chip() -> void:
	var p := PanelContainer.new()
	p.name = "Chip"
	p.position = Vector2(22, 18)
	p.add_theme_stylebox_override("panel", _panel_style(C_CARD, C_BORDER, 12, 2))
	_ui.add_child(p)
	_chip = _label("设计部 · 已调查 0/0", 16)
	p.add_child(_chip)


## 右上角「已记下的东西」—— 2026-10-05 晚换成作者画的**便签纸**底图。
##
## ⚠ 关键点：**底图是不透明的手绘纸**，所以文字必须用**绝对定位**摆进纸的空白区，
##   不能再靠 PanelContainer 的 content_margin 流式排 —— 那样文字会从纸的左上角
##   开始流，直接压到黑框上。这里做法：纸按 CARD_JOURNAL_W 定宽、按比例定高；
##   纸自己铺满整块；文字盒子按 CARD_JOURNAL_SAFE 算出「纸内安全区」再摆进去。
func _build_journal() -> void:
	_journal_root = Control.new()
	_journal_root.name = "Journal"
	_ui.add_child(_journal_root)

	var tex: Texture2D = _load_tex(TEX_JOURNAL)
	if tex == null:
		# 底图没了就退回老的白卡版式 —— 宁可难看，也不能整块面板消失。
		_build_journal_fallback()
		return

	var h := CARD_JOURNAL_W / CARD_JOURNAL_AR
	_journal_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_journal_root.offset_left = -CARD_JOURNAL_W - 22.0
	_journal_root.offset_right = -22.0
	_journal_root.offset_top = 18.0
	_journal_root.offset_bottom = 18.0 + h

	var paper := TextureRect.new()
	paper.name = "Paper"
	paper.texture = tex
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal_root.add_child(paper)

	# 文字盒子 = 纸内安全区。用 **MarginContainer 铺满整张纸 + 四边留白** ——
	# 和弹窗同一套做法（锚点百分比 + 手动 position 那版文字会跑到纸外）。
	var s := CARD_JOURNAL_SAFE
	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", int(round(CARD_JOURNAL_W * s.x)))
	pad.add_theme_constant_override("margin_top", int(round(h * s.y)))
	pad.add_theme_constant_override("margin_right", int(round(CARD_JOURNAL_W * (1.0 - s.z))))
	pad.add_theme_constant_override("margin_bottom", int(round(h * (1.0 - s.w))))
	_journal_root.add_child(pad)

	var iw := CARD_JOURNAL_W * (s.z - s.x)
	var box := VBoxContainer.new()
	box.name = "TextBox"
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(box)

	# 标题行 = 「已记下的东西」+ 右上角「回顾 ▼」。
	# ⛔ 标题文案原样保留（只是从"单独一行"挪进 HBox），一个字没改。
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head_title := _label("已记下的东西", 16, "#1B1B1B")
	head_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(head_title)
	head.add_child(_review_chip())
	box.add_child(head)
	_journal_empty = _label("左边看看，右边就会记下来。", 13, C_MUTED, iw)
	box.add_child(_journal_empty)
	# ⭐ 2026-10-06：作者要求「探索完把结论记到右面」之后，这里会越攒越长
	#（每轮 10 条结论 × 3 轮 + 答题的新剧情/新线索），便签纸装不下。
	# 所以条目放进**可滚动**的容器，并且每次更新**自动滚到最底** ——
	# 刚记下的那条永远在眼前，想看旧的往上滚。
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_scroll)
	_journal_box = VBoxContainer.new()
	_journal_box.add_theme_constant_override("separation", 9)
	_journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_journal_box)


func _build_journal_fallback() -> void:
	var p := PanelContainer.new()
	p.name = "JournalFallback"
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.offset_left = -336.0
	p.offset_right = -22.0
	p.offset_top = 18.0
	p.offset_bottom = 330.0
	p.add_theme_stylebox_override("panel", _panel_style(C_CARD, C_BORDER, 12, 2))
	_journal_root.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(292, 0)
	p.add_child(box)
	box.add_child(_label("已记下的东西", 16, C_TEXT))
	_journal_empty = _label("左边看看，右边就会记下来。", 13, C_MUTED, 292)
	box.add_child(_journal_empty)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(292, 200)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_scroll)
	_journal_box = VBoxContainer.new()
	_journal_box.add_theme_constant_override("separation", 10)
	_journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_journal_box)


func _build_hint() -> void:
	var p := PanelContainer.new()
	p.name = "HintBar"
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.offset_left = -330.0
	p.offset_right = 330.0
	p.offset_top = -72.0
	p.offset_bottom = -20.0
	p.add_theme_stylebox_override("panel", _panel_style(C_CARD, C_BORDER, 14, 2))
	_ui.add_child(p)
	_hint_label = _label("", 15, C_TEXT)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(_hint_label)


## 弹窗层。两种版式共用这一层：
##   `_modal_paper` 有贴图 = 走**纸卡版式**（线索框 / 判断题 / 有人跟你说话）
##   `_modal_card`  有 stylebox = 走**普通卡版式**（答对答错 / 幕结束）
func _build_modal() -> void:
	_modal_layer = Control.new()
	_modal_layer.name = "Modal"
	_modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.visible = false
	_ui.add_child(_modal_layer)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.16, 0.15, 0.14, 0.34)
	# STOP：遮罩自己收点击 —— 点纸外面空白就等于「关掉」（仅 `_modal_closable` 时生效）。
	# 卡片上的按钮是**后添加**的子节点，盖在遮罩上面，所以按钮照常能按到。
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_modal_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_layer.add_child(center)

	# ---- 纸卡版式 ----
	# ⛔ 纸和文字**必须装进同一个容器**（`_modal_paper_box`），由 CenterContainer
	#    统一居中。第一版把 TextureRect 和 VBox 当成两个并列子节点塞进 CenterContainer，
	#    结果各自按自己的 minimum_size 居中 → 两张纸叠在不同位置、
	#    文字浮在纸外面（06_信息卡 那张图就是这么翻的车）。
	# ⛔⛔ 这个盒子**必须是普通 Control，且四个锚点都钉死**（left=top=0, right=bottom=0），
	#    不能是 PanelContainer / 任何会「按内容自适应」的容器：
	#    · PanelContainer 的尺寸 = 子节点 minimum size → 文字一多就把纸撑成整屏
	#      （06_信息卡 第四版截图，纸直接铺满还溢出）。
	#    · 用普通 Control + `custom_minimum_size` + `size` 直接赋值，再让
	#      `CenterContainer`（父节点）按这个尺寸居中 —— 尺寸完全由我们说了算。
	#    ⛔ 纸和文字**必须装进同一个**容器，否则各自按自己的 minimum_size 居中、错位。
	_modal_paper_box = Control.new()
	_modal_paper_box.name = "PaperBox"
	_modal_paper_box.visible = false
	_modal_paper_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_modal_paper_box)

	_modal_paper = TextureRect.new()
	_modal_paper.name = "Paper"
	# ⛔ 这一行漏过一次：TextureRect 建出来是**没有贴图**的，必须显式 load。
	#    漏了的表现是「文字在、纸不在」（06_信息卡 那张截图），而且不报任何错。
	_modal_paper.texture = _load_tex(TEX_CLUE)
	_modal_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_modal_paper.stretch_mode = TextureRect.STRETCH_SCALE
	_modal_paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_paper_box.add_child(_modal_paper)

	_modal_pad = MarginContainer.new()
	_modal_pad.name = "PaperPad"
	_modal_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_paper_box.add_child(_modal_pad)

	_modal_col = VBoxContainer.new()
	_modal_col.name = "PaperText"
	_modal_col.add_theme_constant_override("separation", 10)
	_modal_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_pad.add_child(_modal_col)
	_title = _label("", 22, "#1B1B1B")
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 11)
	_modal_col.add_child(_title)
	_modal_col.add_child(_body)

func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


# ---------------------------------------------------------------- 回顾（只读回看）
## 2026-10-14 作者要求：右上角加「回顾 ▼」，玩家**随时、不限次数**可以
##   · 选「第 N 轮」→ 看那一轮**已经找到**的结论 → 点一条，重新弹出当时那张线索卡；
##   · 选「判断题」→ 看**已经答过**的题（第 X 道）→ 点一道，重新弹出当时的选择结果。
##
## ⛔⛔ 三条铁律（照抄，别走样）：
##   1. 回顾卡一律 `_open_paper(标题, true, false)` —— **closable=true / fire=false**。
##      `fire=true` 是给「关掉线索卡 → 接下一道判断题」那条链条用的；
##      回顾若用了它，玩家随手关一张回顾卡就把剧情往前推了 —— 这是本功能最危险的坑。
##   2. 内容一律由 main.gd 组装后传进来，hud 不碰轮次逻辑
##      （「没到达的轮次不可点」这条规则只在 main 里实现一处）。
##   3. **只加不改**：本段不动任何既有文案、既有分支、既有版式常量。

## 下拉要显示的模型：{ "rounds":[{"no":1,"reached":true,"found":5},…],
##                     "questions":{"reached":true,"answered":3} }

## 右上角那颗「回顾 ▼」。样式跟纸卡上的其他按钮一家（白底黑框）。
func _review_chip() -> Button:
	var b := Button.new()
	b.name = "ReviewChip"
	b.text = "回顾 ▼"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 26.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#FFFFFF")
	sb.border_color = Color("#1B1B1B")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(6)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color("#F0EDE4")
	for k in ["normal", "pressed"]:
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("#1B1B1B"))
	b.add_theme_color_override("font_hover_color", Color("#1B1B1B"))
	b.add_theme_color_override("font_pressed_color", Color("#1B1B1B"))
	b.add_theme_font_size_override("font_size", _fs(13))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_toggle_review_menu)
	_bind_tip(b, "点击查看线索")
	_review_chip_node = b
	return b


## 下拉面板。挂到 `_ui`（**不**挂进记录框）—— 它要能浮到便签纸外面去。
func _build_review_menu() -> void:
	_review_menu = PanelContainer.new()
	_review_menu.name = "ReviewMenu"
	_review_menu.visible = false
	_review_menu.custom_minimum_size = Vector2(REVIEW_MENU_W, 0.0)
	_review_menu.add_theme_stylebox_override("panel",
		_panel_style("#FBF6EC", "#1B1B1B", 8, 2))
	_ui.add_child(_review_menu)
	_review_menu_box = VBoxContainer.new()
	_review_menu_box.name = "Rows"
	_review_menu_box.add_theme_constant_override("separation", 2)
	_review_menu.add_child(_review_menu_box)


func _toggle_review_menu() -> void:
	if _review_menu != null and _review_menu.visible:
		_close_review_menu()
	else:
		_open_review_menu()


func _open_review_menu() -> void:
	if _review_menu == null:
		return
	_hide_tip()
	_refresh_review_menu()
	_review_menu.visible = true
	# 右边缘跟「回顾」按钮右边缘对齐 —— 按钮贴着屏幕右上，不对齐会伸出画面。
	var r: Rect2 = Rect2()
	if _review_chip_node != null:
		r = _review_chip_node.get_global_rect()
	_review_menu.position = Vector2(
		maxf(4.0, r.end.x - REVIEW_MENU_W), r.end.y + 4.0)


func _close_review_menu() -> void:
	if _review_menu != null:
		_review_menu.visible = false


## 每次打开都重画 —— 轮次到达状态、已记条数、已答数都会变。
func _refresh_review_menu() -> void:
	_clear(_review_menu_box)
	var model: Dictionary = {}
	if review_menu_model.is_valid():
		model = review_menu_model.call()

	var rounds: Variant = model.get("rounds", [])
	if typeof(rounds) == TYPE_ARRAY:
		for item in (rounds as Array):
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = item
			var no := int(d.get("no", 0))
			var reached := bool(d.get("reached", false))
			var label := "第 %d 轮" % no
			if reached:
				label += "　（已记 %d 条）" % int(d.get("found", 0))
			var rno := no - 1
			var cb := func() -> void:
				_close_review_menu()
				review_requested.emit("round", rno)
			_review_menu_box.add_child(_menu_row(
				label, reached, cb, "点击查看线索", "还没到这一轮"))

	_review_menu_box.add_child(HSeparator.new())

	var qd: Variant = model.get("questions", {})
	var q_ok := false
	var q_n := 0
	if typeof(qd) == TYPE_DICTIONARY:
		q_ok = bool((qd as Dictionary).get("reached", false))
		q_n = int((qd as Dictionary).get("answered", 0))
	var q_label := "判断题"
	if q_ok:
		q_label += "　（已答 %d 道）" % q_n
	var q_cb := func() -> void:
		_close_review_menu()
		review_requested.emit("questions", 0)
	_review_menu_box.add_child(_menu_row(
		q_label, q_ok, q_cb, "点击查看线索", "还没答过判断题"))


## 下拉里的一行。`enabled=false` 就是「还没到这一轮」——置灰且点不动。
func _menu_row(text: String, enabled: bool, cb: Callable,
		tip_on: String, tip_off: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(190.0, 34.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_content_margin_all(8)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color("#F0EDE4")
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", _fs(14))
	b.add_theme_color_override("font_color", Color("#1B1B1B"))
	b.add_theme_color_override("font_hover_color", Color("#1B1B1B"))
	b.add_theme_color_override("font_pressed_color", Color("#1B1B1B"))
	b.add_theme_color_override("font_disabled_color", Color(C_MUTED))
	b.disabled = not enabled
	if enabled:
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(cb)
		_bind_tip(b, tip_on)
	else:
		_bind_tip(b, tip_off)
	return b


## 悬停提示（作者要的「光标靠近弹出『点击查看线索』」）。
## ⛔ 故意**不用** Godot 原生的 `tooltip_text`：原生提示走默认主题、不挂本工程字体，
##    安卓上没有中文字体 → 会变方框。自建一个小面板才稳（字体从 _ui 主题继承）。
func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.name = "Tip"
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.10, 0.94)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	_tip.add_theme_stylebox_override("panel", sb)
	_tip_label = _label("点击查看线索", 13, "#F5F2EA")
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_label)
	_ui.add_child(_tip)


func _bind_tip(c: Control, text: String) -> void:
	c.mouse_entered.connect(func() -> void: _show_tip(text, c))
	c.mouse_exited.connect(_hide_tip)


func _show_tip(text: String, c: Control) -> void:
	if _tip == null or c == null:
		return
	_tip_label.text = text
	_tip.visible = true
	var want := _tip.get_combined_minimum_size()
	var vp := _ui.get_viewport_rect().size
	var p := c.get_global_rect()
	var pos := Vector2(p.position.x, p.end.y + 4.0)
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - want.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - want.y - 4.0))
	_tip.position = pos


func _hide_tip() -> void:
	if _tip != null:
		_tip.visible = false


## -------------------------------------------------- 回顾页（纸卡版式，逐级返回）

## 第 N 轮的结论列表。`entries` 每项 = {spot, name, lines, clue}（main 组装）。
## ⭐ 分页：一轮最多 14 条，全塞一张纸会被等比缩小糊成一片（见 REVIEW_PAGE）。
func show_review_round(round_no: int, entries: Array) -> void:
	_review_round_no = round_no
	_review_entries = entries
	_review_page = 0
	_render_review_round()


func _render_review_round() -> void:
	_open_paper("回顾 · 第 %d 轮" % _review_round_no, true, false)
	if _review_entries.is_empty():
		_add_paragraphs(["这一轮还没有记下结论。"])
		_action_row().add_child(_paper_button("关上", _dismiss, 150.0))
		return
	var total := _review_entries.size()
	_review_page = _clamp_page(total, _review_page)
	var lo := _review_page * REVIEW_PAGE
	var hi := mini(lo + REVIEW_PAGE, total)
	_add_note("第 %d-%d 条 / 共 %d 条　·　点一条回看当时的线索。" % [lo + 1, hi, total])
	for i in range(lo, hi):
		var idx := i
		var e: Dictionary = _review_entries[i]
		_body.add_child(_paper_entry(
			_entry_label(str(e.get("name", "")), str(e.get("clue", ""))),
			func() -> void: _render_review_clue(idx)))
	var row := _action_row()
	if _review_page > 0:
		row.add_child(_paper_button("上一页", _review_prev_page, 92.0))
	if _review_page < _page_count(total) - 1:
		row.add_child(_paper_button("下一页", _review_next_page, 92.0))
	row.add_child(_paper_button("关上", _dismiss, 92.0))


func _review_prev_page() -> void:
	_review_page -= 1
	_render_review_round()


func _review_next_page() -> void:
	_review_page += 1
	_render_review_round()


## 线索详情 —— 卡面跟「点感叹号弹出」的那张**一模一样**（标题 = 名字，正文 = lines）。
## 作者明确「不用补措辞」，所以这里一个字都不额外加。
func _render_review_clue(idx: int) -> void:
	if idx < 0 or idx >= _review_entries.size():
		return
	var e: Dictionary = _review_entries[idx]
	_open_paper(str(e.get("name", "")), true, false)
	_add_paragraphs(e.get("lines", []))
	var row := _action_row()
	row.add_child(_paper_button("返回", _render_review_round, 130.0))
	row.add_child(_paper_button("关上", _dismiss, 130.0))


## 判断题列表。`entries` 每项 = {no, round, prompt, chosen, correct, on_correct, on_wrong}。
func show_review_questions(entries: Array) -> void:
	_review_qs = entries
	_review_q_page = 0
	_render_review_questions()


func _render_review_questions() -> void:
	_open_paper("回顾 · 判断题", true, false)
	if _review_qs.is_empty():
		_add_paragraphs(["还没有答过的判断题。"])
		_action_row().add_child(_paper_button("关上", _dismiss, 150.0))
		return
	var total := _review_qs.size()
	_review_q_page = _clamp_page(total, _review_q_page)
	var lo := _review_q_page * REVIEW_PAGE
	var hi := mini(lo + REVIEW_PAGE, total)
	_add_note("第 %d-%d 道 / 共 %d 道　·　点一道回看当时的选择。" % [lo + 1, hi, total])
	for i in range(lo, hi):
		var idx := i
		var e: Dictionary = _review_qs[i]
		_body.add_child(_paper_entry(
			"第 %d 道　·　第 %d 轮　·　%s" % [
				int(e.get("no", 0)), int(e.get("round", 0)),
				"答对" if bool(e.get("correct", false)) else "答错"],
			func() -> void: _render_review_question(idx)))
	var row := _action_row()
	if _review_q_page > 0:
		row.add_child(_paper_button("上一页", _review_q_prev_page, 92.0))
	if _review_q_page < _page_count(total) - 1:
		row.add_child(_paper_button("下一页", _review_q_next_page, 92.0))
	row.add_child(_paper_button("关上", _dismiss, 92.0))


func _review_q_prev_page() -> void:
	_review_q_page -= 1
	_render_review_questions()


func _review_q_next_page() -> void:
	_review_q_page += 1
	_render_review_questions()


## 每页条数 / 页数 / 夹取页码（三处共用，避免两套列表各写一份）。
func _page_count(total: int) -> int:
	return maxi(1, ceili(float(total) / float(REVIEW_PAGE)))


func _clamp_page(total: int, page: int) -> int:
	return clampi(page, 0, _page_count(total) - 1)


## 判断题结果 —— 卡片标题就是「第 X 道」（作者点名的）。末行小结是作者允许加的。
func _render_review_question(idx: int) -> void:
	if idx < 0 or idx >= _review_qs.size():
		return
	var e: Dictionary = _review_qs[idx]
	var no := int(e.get("no", 0))
	var rnd := int(e.get("round", 0))
	var correct := bool(e.get("correct", false))
	_open_paper("第 %d 道" % no, true, false)
	_add_paragraphs([str(e.get("prompt", ""))])
	_add_paragraphs(["你选了「%s」。" % str(e.get("chosen", ""))])
	_add_paragraphs(["答对了。" if correct else "答错了。"])
	var t := str(e.get("on_correct", "") if correct else e.get("on_wrong", ""))
	if t != "":
		_add_paragraphs(t.split("\n"))
	_add_note("小结：第 %d 轮的这道题，你当时判断%s。" % [rnd, "正确" if correct else "有误"])
	var row := _action_row()
	row.add_child(_paper_button("返回", _render_review_questions, 130.0))
	row.add_child(_paper_button("关上", _dismiss, 130.0))


## 列表条目（纸上的一行「超链接」）：透明底 + 墨蓝字 + 下划线，悬停亮一块。
## ⛔ Button 不会自动换行 —— 所以文字**先截断**（见 `_entry_label`），并开 `clip_text` 兜底。
func _paper_entry(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = "ReviewEntry"
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 32.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(C_LINK)
	sb.border_width_bottom = 1
	sb.set_content_margin_all(6)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(1, 1, 1, 0.6)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(C_LINK))
	b.add_theme_color_override("font_hover_color", Color("#1B3F5C"))
	b.add_theme_color_override("font_pressed_color", Color("#1B3F5C"))
	b.add_theme_font_size_override("font_size", _fs(15))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	_bind_tip(b, "点击查看线索")
	return b


## 条目文字 = 「名字：结论」；太长就截断（全文在详情页，这里只是列表）。
func _entry_label(name: String, clue: String) -> String:
	var s := clue.strip_edges()
	var n := name.strip_edges()
	if s == "":
		s = n
	elif n != "":
		s = n + "：" + s
	var iw: float = CARD_CLUE_H * CARD_CLUE_AR * (CARD_CLUE_SAFE.z - CARD_CLUE_SAFE.x)
	var maxc := int(maxf(8.0, iw / float(_fs(15)) * 0.92))
	return _ellipsis(s, maxc)


func _ellipsis(s: String, maxc: int) -> String:
	if maxc <= 1 or s.length() <= maxc:
		return s
	return s.substr(0, maxc - 1) + "…"


# ---------------------------------------------------------------- 对外接口

func set_progress(done: int, total: int) -> void:
	_chip.text = "设计部 · 已调查 %d/%d" % [done, total]


## 轮次显示。三轮流程里这行会变成「第 1 轮 · 已调查 0/6」。
func set_progress_round(act: String, round_no: int, rounds: int, done: int, total: int) -> void:
	if rounds > 1:
		_chip.text = "%s · 第 %d/%d 轮 · 已调查 %d/%d" % [act, round_no, rounds, done, total]
	else:
		_chip.text = "%s · 已调查 %d/%d" % [act, done, total]


func set_hint(text: String) -> void:
	_hint_label.text = text


func set_journal(story: Array, clues: Array) -> void:
	_clear(_journal_box)
	if story.is_empty() and clues.is_empty():
		_journal_empty.visible = true
		return
	_journal_empty.visible = false
	var w := CARD_JOURNAL_W * (CARD_JOURNAL_SAFE.z - CARD_JOURNAL_SAFE.x)
	if not story.is_empty():
		_journal_box.add_child(_label("新剧情", 14, C_GREEN, w))
		for s in story:
			_journal_box.add_child(_label("· " + _first_line(str(s)), 13, C_TEXT, w))
	if not clues.is_empty():
		_journal_box.add_child(_label("新线索", 14, C_BLUE, w))
		for c in clues:
			_journal_box.add_child(_label("· " + _first_line(str(c)), 13, C_TEXT, w))
	# 条目多了要滚到底 —— 刚记下的那条必须在眼前（⛔ 布局要等一帧才算得出来）。
	call_deferred("_scroll_journal_bottom")


func _scroll_journal_bottom() -> void:
	if _scroll == null or not _scroll.visible:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar != null:
		_scroll.scroll_vertical = int(bar.max_value)


func _first_line(s: String) -> String:
	var lines := s.split("\n")
	return lines[0] if lines.size() > 0 else s


## 点感叹号 → 弹线索框（2026-10-05 晚换成问号纸底图）。
##
## ⛔⛔ 2026-10-06 血案：这一段一度**没有给关闭出口**（`_open_paper` 之后直接 `_add_note`
##    就结束），而 `_modal_layer` 是 `MOUSE_FILTER_STOP` —— 结果线索框一弹出来，
##    整个游戏点哪儿都没反应、也关不掉，作者只能强制退游戏。
##    现在**所有纸卡版式一律带出口**：底部按钮 + ESC + 点窗外（见 `_dismiss` /
##    `_modal_closable`），缺一不可。以后加新纸卡请照抄这三样。
##
## ⭐ 2026-10-06 晚：`fire` 改成 **true** —— 看完最后一处之后要靠这次 `modal_closed`
##    把流程接到判断题上（作者：「每一轮探索后直接弹出判断题，不要再和小人交流」）。
##    外层 `main._on_modal_closed()` 会在「本轮还没看完」时直接返回，所以中途关卡不会误触发出题。
func show_card(title: String, lines: Array, already: bool) -> void:
	_open_paper(title, true, true)
	_add_paragraphs(lines)
	_add_note("这个已经看过了。" if already else "结论记到右边了。")
	var row := _action_row()
	row.add_child(_paper_button("知道了", _dismiss, 170.0))


func show_dialog(text: String) -> void:
	_open_paper("有人跟你说话", true)
	_add_paragraphs([text])
	var row := _action_row()
	row.add_child(_paper_button("……嗯", _dismiss, 170.0))


func show_question(q: Dictionary) -> void:
	_open_paper("判断题")
	_add_paragraphs([str(q.get("prompt", ""))])
	var qid := str(q.get("id", ""))
	var opts: Variant = q.get("options", [])
	var n := 0
	if typeof(opts) == TYPE_ARRAY:
		for i in range(opts.size()):
			var o: Dictionary = opts[i]
			var idx := i
			_body.add_child(_paper_button(str(o.get("text", "")), func() -> void: option_chosen.emit(qid, idx), 360.0))
			n += 1
	if n == 0:
		# 题干还没填全（选项为空）时别把玩家锁死 —— 给一个出口。
		# ⚠ 出口还要**能推流程**：这张卡是链条上的一环，关掉必须发 modal_closed，
		#   否则玩家就停在这儿了。（`main._next_round_question()` 会跳过没选项的题，
		#   所以不会出现「关掉又被同一道题拦回来」的死循环。）
		_modal_fire = true
		var row0 := _action_row()
		row0.add_child(_paper_button("知道了", _dismiss, 170.0))
	else:
		_add_note("选一个。答错也会留下东西。")


## 答对/答错反馈 —— 纸卡版式。关了之后要发 `modal_closed`，外层靠它决定下一步
## （还有题就再来一道、没了就收尾），所以这里 `fire = true`。
func show_feedback(q: Dictionary, correct: bool, chosen: String) -> void:
	_open_paper("答对了" if correct else "答错了", true, true)
	_add_paragraphs(["你选了「%s」。" % chosen])
	var text := str(q.get("on_correct", "") if correct else q.get("on_wrong", ""))
	if text != "":
		_add_paragraphs(text.split("\n"))
	_add_note("记到右边了。" if correct else "线索记到右边了。")
	var row := _action_row()
	row.add_child(_paper_button("继续", _dismiss, 170.0))


## 一轮结束时那句话（三轮流程，每轮结束都来一次）。
## `has_next = false` 就是三轮走完了 —— 按钮变成「看接下来」，外层收幕。
##
## ⛔⛔ 2026-10-06 夜作者实测「第一轮转第二轮卡住了、没有继续按键，而且能直接跳过后两轮」——
##    根因就在这个按钮：它**只发了 `advance_requested`，没有关掉自己这张纸卡**。
##    于是按下之后轮次确实 +1 了，但纸卡原样停在屏幕上（还是「第一轮 · 结束」），
##    玩家怎么看都是「卡住了」；再按一下又 +1 —— 连按三次就一路滑到「第一幕 · 结束」。
##    ⭐ 规矩：按钮既然自称出口，就必须**真的把卡关掉**再发信号。
##    ⛔ 这张卡仍然 `closable = false`（不能 ESC / 点窗外）—— 因为它的出口**兼做推进**，
##      允许「无声地关掉」的话 `_round_end_shown` 已经是 true、这张卡不会再弹，玩家就永远
##      卡在这一轮了。所以三个出口里只保留按钮这一个，但它必须是**真的出口**。
func show_round_end(round_no: int, rounds: int, title: String, lines: Array,
		has_next: bool) -> void:
	_open_paper(title)
	_add_paragraphs(lines)
	var row := _action_row()
	row.add_child(_paper_button("继续搜证" if has_next else "看接下来",
		func() -> void:
			close_modal()
			advance_requested.emit(), 200.0))


func show_act_end(story: Array, clues: Array) -> void:
	_open_paper("第一幕 · 结束")
	_add_paragraphs([
		"设计部看完了，该问的也问完了。",
		"新剧情 %d 条，新线索 %d 条。" % [story.size(), clues.size()],
		"第二幕才轮到世界变色 —— 那一步不进第一幕。",
	])
	var row := _action_row()
	# 同上：按钮必须自己关掉卡片（这里虽然会重开场景，但别依赖「反正要重载」）。
	row.add_child(_paper_button("重新走一遍", func() -> void:
		close_modal()
		restart_requested.emit(), 200.0))


func close_modal() -> void:
	if _modal_layer == null:
		return
	_modal_layer.visible = false
	modal_visible = false
	_modal_closable = false
	_modal_fire = false
	_close_review_menu()
	_hide_tip()


## 纸卡的**唯一出口** —— 底部按钮、ESC、点窗外都走这里。
## `_modal_fire` 决定要不要在关闭后补发 `modal_closed` 给外层（判断题反馈需要）。
func _dismiss() -> void:
	if _modal_layer == null or not _modal_layer.visible:
		return
	var fire := _modal_fire
	close_modal()
	if fire:
		modal_closed.emit()


## 点纸外面的遮罩 = 关掉（只在允许关的纸卡上生效）。
func _on_dim_input(event: InputEvent) -> void:
	if not _modal_closable:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dismiss()


## ESC 兜底 —— 万一以后某个纸卡忘了给按钮，玩家也不会被锁死在里面。
## 2026-10-14：多了一件事 —— ESC 也用来收「回顾 ▼」的下拉（下拉优先）。
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		if _review_menu != null and _review_menu.visible:
			_close_review_menu()
			get_viewport().set_input_as_handled()
			return
		if modal_visible and _modal_closable:
			_dismiss()
			get_viewport().set_input_as_handled()
		return
	# 点下拉菜单和「回顾」按钮以外的地方 = 收起下拉，并把这下点击吃掉
	# （不然会顺手在场景里点走一步 —— 下拉的常规行为就是"第一下只关菜单"）。
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
			and _review_menu != null and _review_menu.visible:
		var inside := _review_menu.get_global_rect().has_point(mb.position)
		if not inside and _review_chip_node != null:
			inside = _review_chip_node.get_global_rect().has_point(mb.position)
		if not inside:
			_close_review_menu()
			get_viewport().set_input_as_handled()


func _continue() -> void:
	close_modal()
	modal_closed.emit()


# ---------------------------------------------------------------- 内部

## 打开纸卡版式：换贴图、算好纸尺寸、把内容盒子摆进安全区。
## `closable` = 允许点窗外 / ESC 关；`fire` = 关掉后补发 `modal_closed` 给外层。
func _open_paper(title: String, closable: bool = false, fire: bool = false) -> void:
	# 开纸卡时顺手收起下拉与悬停提示（它们不该浮在纸卡上面）。
	_close_review_menu()
	_hide_tip()
	_clear(_body)
	_title.text = title
	_title.add_theme_color_override("font_color", Color("#1B1B1B"))
	_modal_closable = closable
	_modal_fire = fire
	_modal_paper_box.visible = true
	_modal_layer.visible = true
	modal_visible = true
	call_deferred("_layout_paper_text")


## 纸的尺寸是运行时按「屏高」定的，所以内容盒子（在容器里绝对定位）
## 必须**等一帧**、等布局跑完再摆 —— 在同一帧里读 size 拿到的还是 0。
func _layout_paper_text() -> void:
	if _modal_paper_box == null or not _modal_paper_box.visible:
		return
	var vp := _ui.get_viewport_rect().size
	# 纸高：不多于屏高的 84%、也不多于 620；宽度按底图比例。
	var ph: float = minf(CARD_CLUE_H, vp.y * 0.84)
	var pw: float = ph * CARD_CLUE_AR
	# 屏太窄（窗口拉得很小）时按宽度再收一次，别让纸横着出画。
	var max_w: float = vp.x * 0.9
	if pw > max_w:
		pw = max_w
		ph = pw / CARD_CLUE_AR

	# 容器自己就是「纸」的大小 —— CenterContainer 靠它居中，纸铺满它就够了。
	_modal_paper_box.custom_minimum_size = Vector2(pw, ph)
	_modal_paper_box.size = Vector2(pw, ph)
	_modal_paper.size = Vector2(pw, ph)

	var s := CARD_CLUE_SAFE
	# MarginContainer 铺满整张纸，四边留白 = 纸尺寸 × 安全区比例。
	_modal_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_pad.add_theme_constant_override("margin_left", int(round(pw * s.x)))
	_modal_pad.add_theme_constant_override("margin_top", int(round(ph * s.y)))
	_modal_pad.add_theme_constant_override("margin_right", int(round(pw * (1.0 - s.z))))
	_modal_pad.add_theme_constant_override("margin_bottom", int(round(ph * (1.0 - s.w))))

	var iw := pw * (s.z - s.x)
	var ih := ph * (s.w - s.y)

	_title.custom_minimum_size = Vector2(iw, 0)
	# 正文宽度按「纸内宽」定。
	for c in _body.get_children():
		_apply_body_width(c, iw)
	# 内容比纸高的时候不缩字号，直接把整块内容**等比缩**到纸内 —— 缩字号会
	# 让同一张纸上不同次的字号乱跳，等比缩只是整体变小一点，观感统一。
	var need := _modal_col.get_combined_minimum_size().y
	if need > ih and need > 0.0:
		var k: float = clampf(ih / need, 0.58, 1.0)
		_modal_col.pivot_offset = Vector2.ZERO
		_modal_col.scale = Vector2(k, k)
	else:
		_modal_col.scale = Vector2.ONE


func _apply_body_width(n: Node, w: float) -> void:
	var l := n as Label
	if l != null and l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		l.custom_minimum_size.x = w
	for c in n.get_children():
		_apply_body_width(c, w)


func _add_paragraphs(lines: Variant) -> void:
	# 注意：String.split() 返回的是 PackedStringArray，不是 Array ——
	# 只判断 TYPE_ARRAY 会把整段正文静默吞掉，反馈面板就只剩一句「你选了……」。
	var arr: Array = []
	match typeof(lines):
		TYPE_ARRAY:
			arr = lines
		TYPE_PACKED_STRING_ARRAY:
			arr = Array(lines)
		TYPE_NIL:
			return
		_:
			arr = [str(lines)]
	var s := CARD_CLUE_SAFE
	var iw := CARD_CLUE_H * CARD_CLUE_AR * (s.z - s.x)   # 只作初值，_layout 会再修
	for line in arr:
		var t := str(line)
		if t.strip_edges() == "":
			continue
		_body.add_child(_label(t, 16, C_TEXT, iw))


func _add_note(text: String) -> void:
	var s := CARD_CLUE_SAFE
	var iw := CARD_CLUE_H * CARD_CLUE_AR * (s.z - s.x)
	var l := _label(text, 13, C_MUTED, iw)
	_body.add_child(l)
	call_deferred("_layout_paper_text")


func _action_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_body.add_child(row)
	call_deferred("_layout_paper_text")
	return row
