import bpy, numpy as np, sys, os

args = sys.argv[sys.argv.index("--") + 1:]
src = args[0]
out = args[1]
x0, x1, y0, y1 = [float(v) for v in args[2:6]]   # 都是 0~1 的比例，y 从「图像上方」算起
zoom = int(args[6]) if len(args) > 6 else 2

im = bpy.data.images.load(src)
w, h = im.size
a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)   # 注意：第 0 行是图像**底边**

# 「距图像上边 y」→ 数组行号（数组是 bottom-up）
r0 = int(h - y1 * h)
r1 = int(h - y0 * h)
c0 = int(x0 * w)
c1 = int(x1 * w)
crop = a[max(0, r0):min(h, r1), max(0, c0):min(w, c1)]

crop = np.repeat(np.repeat(crop, zoom, axis=0), zoom, axis=1)

oh, ow = crop.shape[0], crop.shape[1]
ni = bpy.data.images.new("crop", width=ow, height=oh, alpha=True)
ni.pixels = crop.ravel().tolist()
ni.filepath_raw = out
ni.file_format = "PNG"
ni.save()
print("[crop] %s -> %s  %dx%d (zoom %d)" % (src, out, ow, oh, zoom))
