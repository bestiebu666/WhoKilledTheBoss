## 把两张同机位的图上下拼成一张对比图（上 = 第一张，下 = 第二张）。
## 环境里没有 PIL，所以走 Blender + numpy —— 和 tools/img_crop.py 一个路子。
##
## 用法：
##   blender --background --python tools/_ab_compare.py -- A.png B.png out.png [宽 1100]
##
## 注意 numpy 数组第 0 行是图像**底边**，所以 concatenate([P, Q]) 出来 P 在下、Q 在上。
import bpy, numpy as np, sys

args = sys.argv[sys.argv.index("--") + 1:]
top, bot, out = args[0], args[1], args[2]
width = int(args[3]) if len(args) > 3 else 1100


def load(p):
    im = bpy.data.images.load(p)
    w, h = im.size
    return np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)


def resize(a, nw):
    h, w = a.shape[0], a.shape[1]
    nh = int(round(h * nw / w))
    yi = (np.arange(nh) * (h / nh)).astype(np.int32)
    xi = (np.arange(nw) * (w / nw)).astype(np.int32)
    return a[yi][:, xi]


a_top = resize(load(top), width)
a_bot = resize(load(bot), width)
gap = np.zeros((6, width, 4), dtype=np.float32)
gap[..., 3] = 1.0
gap[..., :3] = 0.08
# 数组第 0 行是图像底边 —— 所以想让 bot 显示在下面，它必须排在前面。
res = np.concatenate([a_bot, gap, a_top], axis=0)

oh, ow = res.shape[0], res.shape[1]
ni = bpy.data.images.new("ab", width=ow, height=oh, alpha=True)
ni.pixels = res.ravel().tolist()
ni.filepath_raw = out
ni.file_format = "PNG"
ni.save()
print("[ab] %s + %s -> %s  %dx%d" % (top, bot, out, ow, oh))
