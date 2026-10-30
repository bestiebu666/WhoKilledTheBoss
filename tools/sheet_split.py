"""把一张横向拼图切成 N 份分别存 —— 用来放大看四视图里某一格。

用法：blender --background --python tools/sheet_split.py -- <拼图.png> <份数> <输出前缀>
"""
import bpy
import os
import sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
src, n, prefix = argv[0], int(argv[1]), argv[2]

im = bpy.data.images.load(src)
W, H = im.size
import numpy as np
px = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)
tw = W // n
for i in range(n):
    tile = px[:, i * tw:(i + 1) * tw, :]
    out = bpy.data.images.new("t%d" % i, width=tw, height=H, alpha=True)
    out.pixels = tile.reshape(-1).tolist()
    out.filepath_raw = "%s_%d.png" % (prefix, i)
    out.file_format = "PNG"
    out.save()
    print("[split] %s_%d.png" % (prefix, i))
    bpy.data.images.remove(out)
bpy.data.images.remove(im)
