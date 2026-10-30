## 开发用探针：验证「导出后」和「本机开发」两条字体加载路径都能拿到中文字体。
## 背景：frontend.gd / hud.gd / thought_bubble.gd 现在都写成
##   if ResourceLoader.exists(...): load()          ← 导出后走这条（包内只有 .fontdata）
##   elif FileAccess.file_exists(...): FontFile     ← 本机开发走这条（磁盘上有裸 .ttf）
## 这个脚本把两条路都跑一遍，避免「能编译但拿到 null」。
## 运行：Godot_*_console.exe --headless --path <工程> --script res://scripts/_fontprobe.gd
extends SceneTree

const FD := "res://assets/font.ttf"


func _line(tag: String, f: Font) -> void:
	if f == null:
		print("  %-22s -> null（拿不到字体！）" % tag)
		return
	var nm := "?"
	if f is FontFile:
		nm = (f as FontFile).get_font_name()
	var chars := [0x8C01, 0x6740, 0x677F, 0x8001, 0x9AD8, 0x5174]   # 谁 杀 板 老 高 兴
	var miss := []
	for c in chars:
		if not f.has_char(c):
			miss.append(String.chr(c))
	print("  %-22s -> %s  汉字缺失=%s" % [tag, nm, str(miss) if miss else "无 ✓"])


func _init() -> void:
	print("=== 字体加载路径探针 ===")
	print("  ResourceLoader.exists(%s) = %s" % [FD, str(ResourceLoader.exists(FD))])
	print("  FileAccess.file_exists(%s) = %s" % [FD, str(FileAccess.file_exists(FD))])

	# 路径 1：ResourceLoader（导出后唯一可行）
	var a: Font = null
	if ResourceLoader.exists(FD):
		a = load(FD) as Font
	_line("ResourceLoader.load()", a)

	# 路径 2：FileAccess + load_dynamic_font（本机开发）
	var b: Font = null
	if FileAccess.file_exists(FD):
		var ff := FontFile.new()
		if ff.load_dynamic_font(FD) == OK:
			b = ff
	_line("FileAccess+dynamic", b)

	# 兜底：SystemFont（安卓上大概率不出汉字）
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans SC", "sans-serif"])
	sf.allow_system_fallback = true
	_line("SystemFont 兜底", sf)

	# 真用一次：拿主题实际会用的那一个来排版一行中文，确认不报错
	var th := Theme.new()
	th.default_font = a if a != null else b
	th.default_font_size = 18
	if th.default_font != null:
		print("  Theme 实际字体 = %s" % (th.default_font.get_font_name() if th.default_font is FontFile else th.default_font.get_class()))
	print("=== 结束 ===")
	quit()
