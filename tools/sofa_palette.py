"""把同一块沙发布料换成几组候选色，拼成一张对比图 —— 用来快速挑颜色。

用法：
    D:/blender/blender.exe --background --python tools/sofa_palette.py

它读 tools/_tex/sofa_src.png（从沙发 glb 的 baseColorTexture 抽出来的那张底色贴图），
裁一块有代表性的布料，按 model_prep.py 里同一套「按亮度重映射」的公式分别换成
几组候选色，横向拼成一张 ——**换的就是 model_prep_list.json 里的 tint**，
所以图上相中哪组，把它的色号填进去重跑一次就成，不会和成品有偏差。

改色公式（与 model_prep.recolour 完全一致）：
    参考亮度 ref = 全图亮度的 90 分位（≈ 那片浅色岛）
    每个像素     out = 目标色 × (自身亮度 / ref)
"""
import bpy
import numpy as np
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SRC = os.path.join(ROOT, "tools", "_tex", "sofa_src.png")
OUT = os.path.join(ROOT, "shots", "沙发候选色.png")
CROP = 768          # 从贴图中心裁多大一块

# 顺序就是图上从左到右的顺序。
CAND = [
    ("蜜橘珊瑚", "#F2836B"),
    ("明黄芥末", "#F0B429"),
    ("薄荷青", "#5FC4A8"),
    ("薰衣草紫", "#A98BD9"),
]


def hex_to_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def lum_of(rgb):
    return rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


img = bpy.data.images.load(SRC)
w, h = img.size
buf = np.empty(w * h * 4, dtype=np.float32)
img.pixels.foreach_get(buf)
px = buf.reshape(h, w, 4)          # Blender 是下到上
bpy.data.images.remove(img)

# 裁中心一块
x0 = (w - CROP) // 2
y0 = (h - CROP) // 2
crop = px[y0:y0 + CROP, x0:x0 + CROP, :].copy()

ref = float(np.percentile(lum_of(crop[:, :, :3].reshape(-1, 3)), 90.0))
print("[palette] 参考亮度 %.3f（贴图 %dx%d，裁 %d 见方）" % (ref, w, h, CROP))

tiles = []
for cn, hx in CAND:
    t = crop.copy()
    lum = lum_of(t[:, :, :3].reshape(-1, 3)).reshape(CROP, CROP)
    k = np.clip(lum / ref, 0.0, 1.0)
    t[:, :, :3] = hex_to_rgb(hx)[None, None, :] * k[:, :, None]
    tiles.append(t)
    print("[palette]   %-6s %s" % (cn, hx))

sheet = np.concatenate(tiles, axis=1)
out = bpy.data.images.new("palette", width=sheet.shape[1], height=sheet.shape[0], alpha=True)
out.pixels = sheet.reshape(-1).tolist()
os.makedirs(os.path.dirname(OUT), exist_ok=True)
out.filepath_raw = OUT
out.file_format = "PNG"
out.save()
print("[palette] 写出 %s  （从左到右：%s）" % (OUT, " / ".join(c[0] for c in CAND)))
