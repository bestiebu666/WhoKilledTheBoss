# -*- coding: utf-8 -*-
"""三张波普风素材（白底）→ 透明 PNG。灌水法抠底，边缘半透明吃 JPEG 灰边。"""
import os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SRCS = {
    "logo": (r"D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\6371dfc09d97d33a3cb8f5aff65d6d5b\c525203dda0371db828ad1b6e595680e.jpg", None),
    "btn1": (r"D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\1084ffd07a548cbe37834b724cb7fb39.jpg", (820, 1258, 1005, 1280)),
    "btn2": (r"D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\1728fd5b541491b4799ad1c4dc39d13a.jpg", (1005, 1826, 1275, 1932)),
}
OUT = os.path.join(ROOT, "assets", "textures", "ui")
os.makedirs(OUT, exist_ok=True)
THRESH = 246.0

def flood_from_border(cand, max_iter=40000):
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

for key, (src, wm) in SRCS.items():
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    if wm:
        x0, y0, x1, y1 = wm
        a[y0:y1, x0:x1] = 255.0
    h, w, _ = a.shape
    cand = a.min(axis=2) >= THRESH
    bg = flood_from_border(cand)
    alpha = np.where(bg, 0.0, 1.0)
    dark_cut = THRESH - 60.0
    band = dilate(bg, 2) & ~bg
    soft = np.clip((THRESH - a @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / (THRESH - dark_cut), 0.0, 1.0)
    alpha[band] = np.minimum(alpha[band], soft[band])
    ys, xs = np.where(alpha > 0.02)
    y0c, y1c = max(0, ys.min()-2), min(h, ys.max()+3)
    x0c, x1c = max(0, xs.min()-2), min(w, xs.max()+3)
    rgba = np.dstack([a, alpha*255.0]).round().clip(0, 255).astype(np.uint8)[y0c:y1c, x0c:x1c]
    img = Image.fromarray(rgba, "RGBA")
    name = {"logo": "title_logo_pop.png", "btn1": "btn_start_pop.png", "btn2": "btn_recap_pop.png"}[key]
    img.save(os.path.join(OUT, name))
    print("%-5s -> %s  %dx%d  内容bbox x[%d,%d] y[%d,%d]  背景占%.1f%%  半透明边缘%d px" % (
        key, name, img.width, img.height, x0c, x1c, y0c, y1c, 100*bg.mean(), band.sum()))
