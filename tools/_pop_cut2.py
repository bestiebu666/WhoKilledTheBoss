# -*- coding: utf-8 -*-
"""重抠三张素材（用作者现在给的最新文件）→ 透明 PNG（输出到 _logowork，不动游戏资产）。"""
import os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SRCS = {
    "logo": (r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\6371dfc09d97d33a3cb8f5aff65d6d5b\c525203dda0371db828ad1b6e595680e.jpg', []),
    "btn_start": (r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\7679eb506d75ddbd0deb609571448c6c.jpg',
                  [(0, 900, 1280, 1280)]),
    "btn_recap": (r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\1728fd5b541491b4799ad1c4dc39d13a.jpg',
                  [(0, 1250, 1280, 1932)]),
}
OUT = os.path.join(ROOT, "shots", "_logowork")
THRESH = 246.0

def flood_from_border(cand, max_iter=60000):
    seed = np.zeros_like(cand)
    seed[0, :] = cand[0, :]; seed[-1, :] = cand[-1, :]
    seed[:, 0] = cand[:, 0]; seed[:, -1] = cand[:, -1]
    for _ in range(max_iter):
        nb = np.zeros_like(seed)
        nb[1:, :] |= seed[:-1, :]; nb[:-1, :] |= seed[1:, :]
        nb[:, 1:] |= seed[:, :-1]; nb[:, :-1] |= seed[:, 1:]
        new = nb & cand & ~seed
        if not new.any():
            return seed
        seed |= new
    raise SystemExit("灌水不收敛")

def dilate(m, r):
    out = m.copy()
    for _ in range(r):
        nb = out.copy()
        nb[1:, :] |= out[:-1, :]; nb[:-1, :] |= out[1:, :]
        nb[:, 1:] |= out[:, :-1]; nb[:, :-1] |= out[:, 1:]
        out = nb
    return out

for key, (src, wms) in SRCS.items():
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    for x0, y0, x1, y1 in wms:
        a[y0:y1, x0:x1] = 255.0
    h, w, _ = a.shape
    cand = a.min(axis=2) >= THRESH
    bg = flood_from_border(cand)
    alpha = np.where(bg, 0.0, 1.0)
    dark_cut = THRESH - 60.0
    band = dilate(bg, 2) & ~bg
    soft = np.clip((THRESH - a @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / (THRESH - dark_cut), 0.0, 1.0)
    alpha[band] = np.minimum(alpha[band], soft[band])
    ys, xs = np.where(alpha > 0.05)
    y0c, y1c = max(0, ys.min()-2), min(h, ys.max()+3)
    x0c, x1c = max(0, xs.min()-2), min(w, xs.max()+3)
    rgba = np.dstack([a, alpha*255.0]).round().clip(0, 255).astype(np.uint8)[y0c:y1c, x0c:x1c]
    img = Image.fromarray(rgba, "RGBA")
    img.save(os.path.join(OUT, f'pop2_{key}_cut.png'))
    print(f'{key:10} 源{w}x{h} 抠出{img.width}x{img.height}  内容bbox x[{x0c},{x1c}] y[{y0c},{y1c}]  背景占{100*bg.mean():.1f}%')
print('saved pop2_*_cut.png')
