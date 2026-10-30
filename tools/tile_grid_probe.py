"""量一张「格子砖」贴图里是几列几行 —— 铺地板之前必须先知道这个数。

用法：
  D:/blender/blender.exe --background --python tools/tile_grid_probe.py -- <图1> [图2 ...]

⚠ **图要传绝对路径** —— Blender 的当前目录不是工程目录，相对路径会静默读不到（什么都不打印）。

为什么需要它：
  作者说「一格大概 50 厘米」，但一张图里有几格决定了「一张图该铺多大」。
  4 列 × 6 行 → 一张图铺开是 4×0.5 × 6×0.5 = 2.0 × 3.0 米；
  要是 5 列 × 7 行，同样的 50 厘米就变成 2.5 × 3.5 米，铺地板的块数完全不一样。
  肉眼看图容易数错（边缘那排总半格半格地露着），所以直接量。

怎么做：
  把图转灰度 → 沿 X / Y 求相邻像素差分之和（砖缝是亮线，会在缝处给出尖峰）
  → 减掉低频趋势 → 对「尖峰间距」求自相关，最强的那一档间距就是**一个格子的像素宽度**。
  再拿图宽/图高除以它，四舍五入就是列数/行数。

读输出：
  `像素周期 320 → 4 列（余 12 px）` —— 余数明显（比如占了周期的 1/3）说明数得不太准，
  自己拿「图宽 ÷ 周期」心算一下、或者在图上量两个缝的距离复核。
"""
import sys
import numpy as np
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argv:
    raise SystemExit(__doc__)


def load(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(buf)
    a = buf.reshape(h, w, 4)[..., :3]        # 第 0 行 = 图像底边
    bpy.data.images.remove(im)
    return a


def period(profile):
    """一维「缝强度」→ 周期性最强的间距（像素）。"""
    p = profile - np.convolve(profile, np.ones(31) / 31.0, mode="same")   # 去低频趋势
    best, best_s = 0, -1e9
    for d in range(20, len(p) // 2):
        s = float(np.dot(p[:-d], p[d:]))
        if s > best_s:
            best_s, best = s, d
    return best


for path in argv:
    img = load(path)
    h, w, _ = img.shape
    g = img @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    dx = np.abs(np.diff(g, axis=1)).sum(axis=0)
    dy = np.abs(np.diff(g, axis=0)).sum(axis=1)
    px = period(dx)
    py = period(dy)
    print("TILE %s  %dx%d  ratio %.4f" % (path.replace("\\", "/").split("/")[-1], w, h, w / h))
    print("      X: 周期 %d px → %.2f 列（余 %d px）" % (px, w / px, w % px))
    print("      Y: 周期 %d px → %.2f 行（余 %d px）" % (py, h / py, h % py))
