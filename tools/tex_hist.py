"""量一张 glb 里 Base Color 贴图的亮度分布 —— 用来定「改成白色」该按哪个分位数当参考。

用法：blender --background --python tools/tex_hist.py -- <源.glb>
"""
import bpy
import numpy as np
import sys

args = sys.argv[sys.argv.index("--") + 1:]
src = args[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
try:
    bpy.ops.import_scene.gltf(filepath=src)
except AttributeError:
    bpy.ops.wm.gltf_import(filepath=src)

LW = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
for img in bpy.data.images:
    if img.size[0] == 0:
        continue
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    px = buf.reshape(-1, 4)
    lum = px[:, :3] @ LW
    a = px[:, 3]
    keep = (a > 0.5) & (lum > 0.001)          # 丢掉透明区与纯黑背景
    l = lum[keep]
    print("[hist] %s  %dx%d  有效像素 %.1f%%" % (img.name, w, h, keep.mean() * 100.0))
    if l.size == 0:
        continue
    for p in (1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99):
        print("       p%-3d = %.3f" % (p, float(np.percentile(l, p))))
    for thr in (0.5, 0.7, 0.85):
        print("       亮过 %.2f 的像素占 %.1f%%" % (thr, (l > thr).mean() * 100.0))
