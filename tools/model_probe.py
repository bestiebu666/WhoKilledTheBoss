"""Blender 无头：看一眼交付过来的 glb —— 打信息 + 出四视图。

用法：
  D:/blender/blender.exe --background --python tools/model_probe.py -- <glb路径> [输出目录]

输出：
  <输出目录>/view_iso.png / view_front.png / view_side.png / view_top.png
并且把尺寸、朝向、材质、贴图情况打到 stdout。

单位说明：glTF 是 Y-up，导入 Blender 后 Z 朝上。所以 Blender 的 z = 高度。
"""
import bpy
import os
import sys
import math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = argv[0] if argv else r"D:\桌面\办公桌.glb"
OUT = argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "probe")

os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- 清场 + 导入
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if not objs:
    raise SystemExit("[probe] 没导入到任何网格")

print("=" * 60)
print("[probe] 源文件 %s" % SRC)
print("[probe] 网格对象 %d 个" % len(objs))
tris = 0
for o in objs:
    o.data.calc_loop_triangles()
    tris += len(o.data.loop_triangles)
    print("  - 对象 %r  顶点 %d / 面 %d / 材质 %s"
          % (o.name, len(o.data.vertices), len(o.data.loop_triangles),
             [m.name if m else "无" for m in o.data.materials]))
    print("      location=%s  rotation=%s  scale=%s"
          % (tuple(round(v, 4) for v in o.location),
             tuple(round(math.degrees(v), 2) for v in o.rotation_euler),
             tuple(round(v, 4) for v in o.scale)))
print("[probe] 总面数 %d" % tris)

imgs = [i for i in bpy.data.images if i.name != "Render Result"]
print("[probe] 贴图 %d 张：%s"
      % (len(imgs), [(i.name, i.size[0], i.size[1]) for i in imgs]))
for m in bpy.data.materials:
    if m.use_nodes:
        nodes = [n.type for n in m.node_tree.nodes]
        print("  - 材质 %r 节点 %s" % (m.name, nodes))

# ---------------------------------------------------------------- 世界包围盒
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in objs:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for i in range(3):
            lo[i] = min(lo[i], w[i])
            hi[i] = max(hi[i], w[i])
size = hi - lo
center = (lo + hi) / 2.0
print("[probe] 世界包围盒（Blender 坐标，Z 朝上 = 高度）")
print("        min    (%.3f, %.3f, %.3f)" % tuple(lo))
print("        max    (%.3f, %.3f, %.3f)" % tuple(hi))
print("        尺寸   宽X %.3f × 深Y %.3f × 高Z %.3f" % tuple(size))
print("        底面   z = %.3f" % lo[2])
print("        水平中心 x = %.3f, y = %.3f" % (center[0], center[1]))

# ---------------------------------------------------------------- 场景与相机
scene = bpy.context.scene
cam_data = bpy.data.cameras.new("ProbeCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(size) * 1.25
cam = bpy.data.objects.new("ProbeCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

world = bpy.data.worlds.new("ProbeWorld")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.75, 0.75, 1.0)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.6

sun_data = bpy.data.lights.new("ProbeSun", type="SUN")
sun_data.energy = 3.0
sun = bpy.data.objects.new("ProbeSun", sun_data)
sun.rotation_euler = (math.radians(52), 0.0, math.radians(35))
scene.collection.objects.link(sun)

scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = False
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
try:
    scene.view_settings.view_transform = "Standard"
except Exception:
    pass

D = max(size) * 2.4

VIEWS = {
    "iso":   Vector((0.85, -1.0, 0.55)),
    "front": Vector((0.0, -1.0, 0.12)),
    "side":  Vector((1.0, 0.0, 0.12)),
    "top":   Vector((0.02, -0.02, 1.0)),
}

for tag, d in VIEWS.items():
    cam.location = center + d.normalized() * D
    look = cam.location - center
    cam.rotation_euler = look.to_track_quat("Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, "view_%s.png" % tag)
    bpy.ops.render.render(write_still=True)
    print("[probe] 输出 %s" % scene.render.filepath)

print("=" * 60)
