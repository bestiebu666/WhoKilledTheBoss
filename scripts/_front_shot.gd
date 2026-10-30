extends Node
## 前情提要 / 引导剧情的**逐段**核对图（作者 2026-10-06 把开场正文写来之后加的）。
##
## 为什么单独做一个：shot.gd 只截「前情提要第 1 段 + 第 2 段」两张，段数一多就核不完；
## 这个探针会把 recap + intro 的**每一段**都截一张，配 tools/intro_shot_sheet.py 拼成一张总表。
##
## 跑法（不要加 --headless，需要真实渲染）：
##   Godot_v4.7.2-stable_win64_console.exe --path . res://scenes/_frontshot.tscn
##
## 产出：shots/前情提要_00_标题.png、前情提要_01..NN.png（一段一张）、前情提要_99_选幕.png。

const OUT_DIR := "res://shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var app: Node = (load("res://scenes/app.tscn") as PackedScene).instantiate()
	add_child(app)
	await _settle(10)
	await _shot("前情提要_00_标题")

	var fe: Frontend = app.get("entry")
	if fe == null:
		print("[frontshot] ERR 拿不到 Frontend 实例")
		get_tree().quit(1)
		return

	fe.show_recap()
	await _settle(6)
	var total := fe.recap_total()
	print("[frontshot] 前情提要 + 引导剧情 共 %d 段" % total)

	for i in range(total):
		var nm := "前情提要_%02d" % (i + 1)
		await _shot(nm)
		print("[frontshot] %s  [%s] %s / %d  «%s»"
			% [nm, fe.recap_kind(), str(i + 1), total, fe.recap_text().left(20).replace("\n", " ")])
		if i < total - 1:
			fe.advance_recap()
			await _settle(5)

	fe.show_acts()
	await _settle(6)
	await _shot("前情提要_99_选幕")

	app.queue_free()
	await _settle(6)
	Audio.shutdown()   # 放掉 BGM 资源，退出日志才干净
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	if err != OK:
		print("[frontshot] save ERR %d -> %s" % [err, path])
