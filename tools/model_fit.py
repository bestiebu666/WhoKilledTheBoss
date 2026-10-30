"""Blender 无头：把交付过来的 glb 归一化成游戏能直接用的模型。

用法：
  D:/blender/blender.exe --background --python tools/model_fit.py -- <源glb> <输出glb> <模型名> [宽度] [面数上限]

做的事：
  1. 导入 → 合并成一个对象、烘掉所有变换
  2. 打印「高度剖面 / 深度剖面」—— 用来确认桌面在哪、椅子在哪一侧
  3. 等比缩放到指定宽度（保持原始比例）
  4. 原点移到包围盒「底面中心」（游戏的约定）
  5. 材质瘦身：去掉 Normal / ORM 贴图，留下的贴图缩到 1024 并打包
  6. Decimate 到面数上限以内
  7. 对象名改成模型名，导出 glb

注意：源文件不动，产物写到输出路径。
"""
import bpy
import os
import sys
import math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 3:
    raise SystemExit(__doc__)

SRC = argv[0]
OUT = argv[1]
MODEL = argv[2]
WIDTH = float(argv[3]) if len(argv) > 3 else 4.7
TRI_CAP = int(argv[4]) if len(argv) > 4 else 20000
TEX_MAX = int(argv[5]) if len(argv) > 5 else 1024

# ---------------------------------------------------------------- 导入 + 合并
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not meshes:
    raise SystemExit("[fit] 没导入到网格")
print("[fit] 导入 %d 个网格对象" % len(meshes))

bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.join()
obj = bpy.context.object
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def world_bbox(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


obj.data.calc_loop_triangles()
tris0 = len(obj.data.loop_triangles)
lo, hi = world_bbox(obj)
size = hi - lo
print("[fit] 原始：面数 %d / 尺寸 宽X %.3f × 深Y %.3f × 高Z %.3f" % (tris0, size.x, size.y, size.z))

# ---------------------------------------------------------------- 剖面（用来定桌面高度、分辨椅子在哪侧）
verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
NB = 24
print("[fit] 高度剖面（z 从下往上，数字 = 该层顶点占比）")
for i in range(NB):
    z0 = lo.z + size.z * i / NB
    z1 = lo.z + size.z * (i + 1) / NB
    n = sum(1 for v in verts if z0 <= v.z < z1)
    bar = "#" * int(40.0 * n / max(1, len(verts)))
    print("   z %6.3f ~ %6.3f  %5d  %s" % (z0, z1, n, bar))

print("[fit] 深度剖面（y 从 -Y 到 +Y，数字 = 该层最高点的 z）")
for i in range(NB):
    y0 = lo.y + size.y * i / NB
    y1 = lo.y + size.y * (i + 1) / NB
    seg = [v.z for v in verts if y0 <= v.y < y1]
    if seg:
        print("   y %6.3f ~ %6.3f  顶点 %5d  最高 z %6.3f  最低 z %6.3f"
              % (y0, y1, len(seg), max(seg), min(seg)))

# ---------------------------------------------------------------- 缩放
k = WIDTH / size.x
obj.scale = (k, k, k)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
lo, hi = world_bbox(obj)
size = hi - lo
print("[fit] 缩放到宽 %.3f 米后：宽X %.3f × 深Y %.3f × 高Z %.3f  （系数 %.4f）"
      % (WIDTH, size.x, size.y, size.z, k))

# ---------------------------------------------------------------- 原点 = 底面中心
obj.location -= Vector(((lo.x + hi.x) / 2.0, (lo.y + hi.y) / 2.0, lo.z))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
lo, hi = world_bbox(obj)
print("[fit] 原点归位后：min (%.3f, %.3f, %.3f)  max (%.3f, %.3f, %.3f)"
      % (lo.x, lo.y, lo.z, hi.x, hi.y, hi.z))

# ---------------------------------------------------------------- 材质瘦身
print("[fit] 材质处理")
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)

    # 只保留「喂 Base Color 的那条链」，其余节点（法线贴图 / ORM / Mix 之类）全丢。
    # 不去猜插槽名叫什么 —— 直接顺着 Base Color 往回追，追不到的一律删。
    allowed = set()
    if bsdf is not None:
        allowed.add(bsdf)
    for n in nt.nodes:
        if n.type == "OUTPUT_MATERIAL":
            allowed.add(n)
    if bsdf is not None and bsdf.inputs["Base Color"].is_linked:
        stack = [bsdf.inputs["Base Color"].links[0].from_node]
        while stack:
            n = stack.pop()
            if n in allowed:
                continue
            allowed.add(n)
            for inp in n.inputs:
                for l in inp.links:
                    stack.append(l.from_node)

    for n in list(nt.nodes):
        if n in allowed:
            continue
        tag = ""
        if n.type == "TEX_IMAGE" and n.image:
            tag = "  贴图 %s %s" % (n.image.name, tuple(n.image.size))
        print("   丢掉节点 %-20r %s%s" % (n.name, n.type, tag))
        nt.nodes.remove(n)

    # 基础材质参数按工程约定钉死
    if bsdf is not None:
        for sock in ("Metallic", "Roughness"):
            if sock in bsdf.inputs:
                for l in list(bsdf.inputs[sock].links):
                    nt.links.remove(l)
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Roughness"].default_value = 0.85
        for l in list(bsdf.inputs["Normal"].links):
            nt.links.remove(l)

for img in list(bpy.data.images):
    if img.name == "Render Result" or img.size[0] == 0:
        continue
    if img.users == 0:
        print("   清掉没人用的贴图 %s %s" % (img.name, tuple(img.size)))
        bpy.data.images.remove(img)
        continue
    if max(img.size) > TEX_MAX:
        print("   贴图 %s %s → %d" % (img.name, tuple(img.size), TEX_MAX))
        img.scale(TEX_MAX, TEX_MAX)
    try:
        img.pack()
    except Exception as e:
        print("   ! 打包失败 %s: %s" % (img.name, e))

# ---------------------------------------------------------------- 减面
obj.data.calc_loop_triangles()
tris = len(obj.data.loop_triangles)
if tris > TRI_CAP:
    m = obj.modifiers.new("Decimate", "DECIMATE")
    m.decimate_type = "COLLAPSE"
    m.ratio = float(TRI_CAP) / float(tris)
    bpy.ops.object.modifier_apply(modifier=m.name)
    obj.data.calc_loop_triangles()
    print("[fit] 减面 %d → %d（上限 %d）" % (tris, len(obj.data.loop_triangles), TRI_CAP))
else:
    print("[fit] 面数 %d 已在上限 %d 内，不减" % (tris, TRI_CAP))

# ---------------------------------------------------------------- 导出
obj.name = MODEL
obj.data.name = MODEL
os.makedirs(os.path.dirname(OUT), exist_ok=True)
kw = dict(filepath=OUT, export_format="GLB")
try:
    bpy.ops.export_scene.gltf(**kw, export_apply=True, export_yup=True)
except TypeError:
    bpy.ops.export_scene.gltf(**kw)

lo, hi = world_bbox(obj)
print("[fit] 导出 %s" % OUT)
print("[fit] 最终 面数 %d / 尺寸 宽X %.3f × 深Y %.3f × 高Z %.3f / 文件 %.1f KB"
      % (len(obj.data.loop_triangles), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z,
         os.path.getsize(OUT) / 1024.0))
print("[fit] 换算到 glTF/Godot 坐标：宽 x %.3f / 高 y %.3f / 深 z %.3f"
      % (hi.x - lo.x, hi.z - lo.z, hi.y - lo.y))
