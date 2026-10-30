extends Node
## 字体大小改动的前后对比工具。**不是游戏的一部分**，只是用来核对改字号后的画面。
##
## 跑法（⛔ **不要加 --headless**，需要真实 GPU 渲染）：
##   FONTCHECK_TAG=before  Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_fontcheck.tscn
##   FONTCHECK_TAG=after   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_fontcheck.tscn
##
## 输出到 res://shots/_fontcheck/<tag>/：
##   · 每一屏一张 png（有文字的屏都覆盖到：进入页 / 前情提要 / 引导剧情 / 选幕页 /
##     锁定幕提示 / 信息卡 / 记录框 / 判断题 / 答错反馈）
##   · labels.txt —— 每个可见 Label 的**实际字号 / 位置 / 尺寸 / 最小尺寸**。
##     改前改后各跑一次，diff 这个文件就能确认「字真的变大了」以及「有没有被挤出容器」。
##
## ⛔ 刻意写到 shots/_fontcheck/ 子目录、不碰 shots/ 根目录 —— 不覆盖作者的正式截图。
##
## ⚠ 纸卡（线索框/判断题）的内容有一个「装不下就等比缩」的兜底（见 hud.gd 的
##   _layout_paper_text）。如果字放大后把内容顶出纸内高，那个兜底会**把整块缩回去**，
##   结果字反而没变大。所以每次跑完都打印一行「纸卡内容缩放」—— 必须 = 1.000 才算数。

const OUT_ROOT := "res://shots/_fontcheck/"

var _out_dir := ""


func _ready() -> void:
	_out_dir = OUT_ROOT + _tag() + "/"
	DirAccess.make_dir_recursive_absolute(_out_dir)

	# ---- 进入页一组（和地图无关，先截完再卸掉）----
	var app: Node = (load("res://scenes/app.tscn") as PackedScene).instantiate()
	add_child(app)
	await _settle(10)
	await _shot("00_进入页_标题")

	var entry: Frontend = app.get("entry")
	if entry != null:
		entry.show_recap()
		await _settle(5)
		await _shot("01_前情提要")

		entry.advance_recap()
		await _settle(5)
		await _shot("02_引导剧情")

		entry.show_acts()
		await _settle(5)
		await _shot("03_选幕页")

		# 点一下锁着的第二幕 —— 下面那句提示是选幕页里唯一的运行时文字
		var locked_btn := entry.act_button(1)
		if locked_btn != null:
			locked_btn.pressed.emit()
		await _settle(14)
		await _shot("04_锁定幕提示")

	app.queue_free()
	await _settle(10)

	# ---- 第一幕：HUD 的三处文字 ----
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _settle(50)

	# 05 信息卡（纸卡版式：标题 + 正文段落 + 「知道了」按钮）
	main._open_spot("feng_desk")
	await _settle(8)
	await _shot("05_信息卡")
	_report_paper_scale(main)
	main.hud._dismiss()

	# 06 记录框攒满条目（右上角那栏，条目字号最小，最该看清）
	for s in ContentDB.round_spot_ids(0):
		main._open_spot(str(s))
		main.hud.close_modal()
	await _settle(8)
	await _shot("06_记录框_满")

	# 07 判断题（纸卡版式 + 选项按钮，最容易挤）
	main._open_spot(str(ContentDB.round_spot_ids(0)[0]))
	await _settle(2)
	main.hud._dismiss()
	await _settle(8)
	await _shot("07_判断题")
	_report_paper_scale(main)

	# 08 答错的反馈卡
	main._on_option_chosen("q1_feng_rich", _wrong_index(0, "q1_feng_rich"))
	await _settle(8)
	await _shot("08_答错了")
	_report_paper_scale(main)

	print("[fontcheck] 完成 → " + _out_dir)
	Audio.shutdown()
	get_tree().quit(0)


## 输出子目录名。用环境变量传，免得改前改后各维护一份脚本。
func _tag() -> String:
	var t := OS.get_environment("FONTCHECK_TAG").strip_edges()
	return t if t != "" else "run"


## 纸卡内容有没有被「装不下就等比缩」的兜底缩掉。1.000 = 没缩、字号真的生效了。
func _report_paper_scale(main: Node3D) -> void:
	if main.hud == null or not main.hud.modal_visible or main.hud._modal_col == null:
		return
	print("[fontcheck]   纸卡内容缩放 = %.3f（1.000 = 字没被缩回去）" % main.hud._modal_col.scale.x)


## 某道题**错误选项**的下标（0 起）。和 shot.gd 里同一套 —— 选项顺序是作者填的、
## 随时会改，所以别手写下标（写死会「以为在答错、其实在答对」）。
func _wrong_index(round_i: int, qid: String) -> int:
	var opts: Variant = ContentDB.round_question(round_i, qid).get("options", [])
	var n := (opts as Array).size() if typeof(opts) == TYPE_ARRAY else 0
	if n <= 1:
		return 0
	for i in range(n):
		if not bool(((opts as Array)[i] as Dictionary).get("correct", false)):
			return i
	return 0


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out_dir + name + ".png"
	var err := img.save_png(path)
	_dump_labels(name)
	print("[fontcheck] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])


## 把当前屏所有**可见且有文字**的 Label 导出来，追加到 labels.txt。
## 改前改后各跑一次、diff 它，就能量化确认字号变化与容器是否被撑破。
func _dump_labels(screen: String) -> void:
	var path := _out_dir + "labels.txt"
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return

	f.store_line("=== %s ===" % screen)
	var rows: Array[String] = []
	_collect(get_tree().root, rows)
	rows.sort()
	for r in rows:
		f.store_line(r)
	f.store_line("")
	f.close()


func _collect(n: Node, rows: Array[String]) -> void:
	var l := n as Label
	if l != null and l.is_visible_in_tree() and l.text.strip_edges() != "":
		_row(rows, "L", l.get_theme_font_size("font_size"), l, l.text, false)
	# 只认 Button —— TextureButton（进入页那两张美术按钮）没有 text 属性，也不是文字。
	var b := n as Button
	if b != null and b.is_visible_in_tree() and b.text.strip_edges() != "":
		_row(rows, "B", b.get_theme_font_size("font_size"), b, b.text,
			b.custom_minimum_size.y > 0.0)
	for c in n.get_children():
		_collect(c, rows)


## kind: L=Label / B=Button。fixed=控件自带固定最小高（按钮是这样）——
## 固定高的控件字号一放大就可能把文字顶出边框，所以单独标出来便于核对。
func _row(rows: Array[String], kind: String, fs: int, ctl: Control, text: String,
		fixed: bool) -> void:
	var txt := text.replace("\n", "⏎")
	if txt.length() > 34:
		txt = txt.substr(0, 34) + "…"
	rows.append("%s fs=%-3d pos=(%6.1f,%6.1f) size=(%6.1f,%6.1f) min=(%6.1f,%6.1f)%s %s"
		% [kind, fs, ctl.global_position.x, ctl.global_position.y, ctl.size.x, ctl.size.y,
		ctl.get_combined_minimum_size().x, ctl.get_combined_minimum_size().y,
		" 固定高" if fixed else "", txt])
