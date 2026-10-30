extends Node
## 把四个人的思考框**贴图原图**直接导出来拼一张对照图 —— 不经过 3D 场景，
## 所以不会被人、椅子、墙挡住，能一眼和参考图对上。
##
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/bubbletx.tscn
##
## 顺便报一遍「墨色像素占比」，改参数时能立刻看出形状有没有被画空。

const OUT_DIR := "res://shots/"
const ORDER := ["feng", "intern1", "boss", "director"]
const BG := Color("#B9C6D2")      # 中灰底：白框和黑墨线都看得清

const BubbleScript := preload("res://scripts/thought_bubble.gd")

var main: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	await _settle(30)

	var tw := int(BubbleScript.TEX_W)
	var th := int(BubbleScript.TEX_H)
	var gap := 24
	var sheet := Image.create(tw * 2 + gap * 3, th * 2 + gap * 3, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)

	for i in range(ORDER.size()):
		var nid: String = ORDER[i]
		var cfg: Dictionary = main._bubble_cfg(_npc_by_id(nid).get("bubble"))
		# 走同一个 _prep，拿到的就是游戏里那张
		var tex: ImageTexture = BubbleScript._shared_texture(cfg)
		var img := tex.get_image()
		var col := i % 2
		var row := i / 2
		var dst := Vector2i(gap + col * (tw + gap), gap + row * (th + gap))
		sheet.blend_rect(img, Rect2i(0, 0, tw, th), dst)

		# 统计：白底 / 墨线各占多少，确认「真的画出来了」而不是一片空白
		var ink := 0
		var solid := 0
		for yy in range(0, th, 2):
			for xx in range(0, tw, 2):
				var c := img.get_pixel(xx, yy)
				if c.a > 0.5:
					solid += 1
					if c.r < 0.45 and c.g < 0.45 and c.b < 0.45:
						ink += 1
		var total := (th / 2) * (tw / 2)
		print("    %-9s %-11s 不透明 %5.1f%%  其中墨线 %4.1f%%"
			% [nid, str(cfg.get("style", "?")),
			   100.0 * float(solid) / float(total), 100.0 * float(ink) / float(total)])

	# 贴图是 384×465，2×2 拼起来不到 1K，直接存原尺寸，别缩
	var path := OUT_DIR + "思考框_贴图对照.png"
	var err := sheet.save_png(path)
	print("[bubbletx] %s -> %s" % [path, "ok" if err == OK else "ERR %d" % err])
	print("[bubbletx] 左→右、上→下：%s" % ", ".join(ORDER))
	get_tree().quit(0)


func _npc_by_id(id: String) -> Dictionary:
	for n in ContentDB.npcs:
		if str(n.get("id", "")) == id:
			return n
	return {}


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
