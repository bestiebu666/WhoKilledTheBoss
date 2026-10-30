## 开发用探针：报告贴图在 .godot/imported 里被烘成什么压缩格式，以及内置字体能否加载。
## 用途：安卓导出必须用 GPU 能采样的格式 —— 安卓(GLES3/Vulkan)支持 ETC2/ASTC，
##      不支持 S3TC(DXT)；桌面显卡则反过来更常见。所以导出前要确认格式。
## 运行：Godot_*_console.exe --headless --path <工程> --script res://scripts/_texfmt.gd
## 被 Android/Windows 预设的 scripts/_*.gd 排除规则挡在包外，不会进游戏。
extends SceneTree

## Godot Image.Format 枚举里我们需要认得的那几个
const FMT_NAMES := {
	17: "DXT1 (S3TC — 桌面/仅 x86)",
	19: "DXT5 (S3TC — 桌面/仅 x86)",
	22: "BPTC_RGBA (桌面)",
	30: "ETC2_RGB8 (安卓 OK)",
	31: "ETC2_RGBA8 (安卓 OK)",
	32: "ETC2_RGB8A1 (安卓 OK)",
	35: "ASTC_4x4 (安卓 OK)",
}

const PATHS := [
	"res://assets/models/SM_A_Npc_Boss_Color.png",
	"res://assets/models/SM_F_Bar_texture_pbr_20250901.png",
	"res://assets/models/SM_B_Window_Wall_texture_pbr_20250901.png",
	"res://assets/textures/floor/floor_a.jpg",
	"res://assets/textures/ui/card_clue.png",
	"res://assets/textures/ui/title_bg_pop.png",
]


func _init() -> void:
	print("=== 贴图压缩格式探针 ===")
	var bad := 0
	for p in PATHS:
		if not FileAccess.file_exists(p):
			print("  %-56s [缺文件]" % p)
			continue
		var raw_exists := FileAccess.file_exists(p)
		var t: Resource = load(p)
		var fmt := -1
		var sz := "?"
		if t is Texture2D:
			var img: Image = (t as Texture2D).get_image()
			if img != null:
				fmt = img.get_format()
				sz = "%dx%d" % [img.get_width(), img.get_height()]
		var nm: String = FMT_NAMES.get(fmt, "其它/未压缩")
		if fmt == 17 or fmt == 19 or fmt == 22:
			bad += 1
		print("  %-56s fmt=%-3d %-26s %-10s raw=%s" % [p, fmt, nm, sz, str(raw_exists)])
	print("  —— 桌面专用(S3TC/BPTC)贴图数：%d" % bad)

	print("=== 内置字体探针 ===")
	var fp := "res://assets/font.ttf"
	print("  FileAccess.file_exists(%s) = %s" % [fp, str(FileAccess.file_exists(fp))])
	print("  ResourceLoader.exists(%s)  = %s" % [fp, str(ResourceLoader.exists(fp))])
	if FileAccess.file_exists(fp):
		var ff := FontFile.new()
		var rc := ff.load_dynamic_font(fp)
		var ok := ff.has_char(0x8C01) and ff.has_char(0x6740) and ff.has_char(0x677F)
		print("  load_dynamic_font rc=%d  名称=%s  汉字『谁杀板』可绘制=%s"
			% [rc, ff.get_font_name(), str(ok)])
	quit()
