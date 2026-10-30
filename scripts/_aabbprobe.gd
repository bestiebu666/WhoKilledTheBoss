extends Node
## 一次性探针：把每个探索点 **在世界坐标里的实际包围盒** 打出来。
## 用途：确认 `objects.json` 里的 `size` 到底是「世界轴跨度」还是「转过之前的跨度」——
## 自检的 `_aabb_of()` 对 rot 90/270 会换 x/z，而公示板那组数（size.x = 0.123 是厚度）
## 看起来又像世界轴。两边对不上，必须实测，不能猜。
var main: Node3D


func _ready() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for i in range(6):
		await get_tree().process_frame

	print("=== 探索点的世界包围盒（实测，含灰盒与真模型） ===")
	for s in ContentDB.spots:
		var id := str(s.get("id", ""))
		var nd: Node3D = main._spot_nodes.get(id)
		if nd == null:
			continue
		var box := _world_box(nd)
		var r := nd.rotation_degrees.y
		print("%-13s rot=%-7.1f  JSON size=%-24s  实测世界 min=(%.3f, %.3f, %.3f) size=(%.3f, %.3f, %.3f)"
			% [id, r, str(s.get("size")), box.position.x, box.position.y, box.position.z,
			box.size.x, box.size.y, box.size.z])
		for ch in nd.get_children():
			var mi := ch as MeshInstance3D
			if mi != null and mi.mesh != null:
				var b := _world_box_of_mesh(mi)
				print("      · %-10s size=(%.3f, %.3f, %.3f)  min_x=%.3f  visible=%s"
					% [ch.name, b.size.x, b.size.y, b.size.z, b.position.x, mi.visible])
	get_tree().quit(0)


func _world_box(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var b := _world_box_of_mesh(mi)
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _world_box_of_mesh(mi: MeshInstance3D) -> AABB:
	var t := mi.global_transform
	var a := mi.mesh.get_aabb()
	return t * a


func _meshes(n: Node) -> Array:
	var out: Array = []
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.append(k)
			var mi := k as MeshInstance3D
			if mi != null and mi.mesh != null:
				out.append(mi)
	return out
