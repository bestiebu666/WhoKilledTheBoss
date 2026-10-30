import os
import bpy, numpy as np

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shots", "布置俯视图.png")
ROOM_X, ROOM_Z = 16.0, 12.0
VIA = (1920, 1200)

im = bpy.data.images.load(SRC)
w, h = im.size
a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)

cam_size = max(ROOM_Z + 5.6, (ROOM_X + 3.0) / (VIA[0] / VIA[1]))
ppm = h / cam_size
cx, cy = w * 0.5, h * 0.5


def to_world(sx, sy):
    return ((sx - cx) / ppm, (sy - cy) / ppm)


rgb = a[:, :, :3]
r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
# 手写的笔是**亮蓝**；NPC 名字用的是深蓝 #3F6EA8 = (0.247,0.431,0.659)，B-G 只有 0.23。
# 所以多加一条「B 和 G 要拉得开」，把 NPC 标签滤掉。
mask = (b > 0.70) & (r < 0.50) & ((b - g) > 0.30)
ys, xs = np.nonzero(mask)
print("亮蓝/手写笔 像素 %d 个（滤掉 NPC 标签后）" % len(xs))

pts = set(zip(ys.tolist(), xs.tolist()))
seen = set()
comps = []
for p in pts:
    if p in seen:
        continue
    stack = [p]
    seen.add(p)
    comp = []
    while stack:
        y, x = stack.pop()
        comp.append((y, x))
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                q = (y + dy, x + dx)
                if q in pts and q not in seen:
                    seen.add(q)
                    stack.append(q)
    if len(comp) >= 60:
        comps.append(comp)

comps.sort(key=len, reverse=True)
print("连通域 %d 个（>=60 像素的）" % len(comps))
for i, comp in enumerate(comps[:10]):
    arr = np.array(comp)
    gy = (h - 1) - arr[:, 0]        # 换成「距图像上边」
    gx = arr[:, 1].astype(np.float64)
    mx, my = gx.mean(), gy.mean()
    wx, wz = to_world(mx, my)
    print("  #%d  %5d px  中心(%.0f,%.0f) → x=%+.2f z=%+.2f | 像素 x %.0f~%.0f  y %.0f~%.0f"
          % (i + 1, len(comp), mx, my, wx, wz, gx.min(), gx.max(), gy.min(), gy.max()))
