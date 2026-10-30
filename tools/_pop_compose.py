# -*- coding: utf-8 -*-
"""把抠好的三张透明素材合成到去水印底图上，出开始页成品。"""
import os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BASE = r"D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\42013a2d8891ef2ba95117eebbd66cea.jpg"
UI = os.path.join(ROOT, "assets", "textures", "ui")
OUT = os.path.join(ROOT, "shots")

base = Image.open(BASE).convert("RGB")
W, H = base.size
canvas = np.asarray(base).astype(np.float32)

def lum(x): return x @ np.array([0.2126, 0.7152, 0.0722], np.float32)

def paste(name, cx, cy, target_w):
    im = Image.open(os.path.join(UI, name))
    k = target_w / im.width
    im = im.resize((int(im.width*k), int(im.height*k)), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    hh, ww = arr.shape[:2]
    px, py = int(cx - ww/2), int(cy - hh/2)
    # 白场匹配: patch 白中位 → 底图覆盖区白中位
    pl = lum(arr[..., :3]); pmask = pl > 228
    region = canvas[max(py,0):min(py+hh,H), max(px,0):min(px+ww,W)]
    rl = lum(region); bmask = rl > 215
    if pmask.sum() > 50 and bmask.sum() > 50:
        gain = np.median(region[bmask], 0) / np.maximum(np.median(arr[..., :3][pmask], 0), 1)
        gain = np.clip(gain, 0.86, 1.06)
        arr[..., :3] = np.clip(arr[..., :3] * gain, 0, 255)
        print("  %-22s %dx%d  gain %s" % (name, ww, hh, np.round(gain, 3)))
    alpha = arr[..., 3:4] / 255.0
    xa, ya, xb, yb = max(px,0), max(py,0), min(px+ww,W), min(py+hh,H)
    sa = alpha[ya-py:yb-py, xa-px:xb-px]
    canvas[ya:yb, xa:xb] = canvas[ya:yb, xa:xb]*(1-sa) + arr[ya-py:yb-py, xa-px:xb-px, :3]*sa
    return (px, py, px+ww, py+hh)

print("== 合成 ==")
b1 = paste("title_logo_pop.png", 700, 480, 800)
b2 = paste("btn_start_pop.png", 620, 860, 430)
b3 = paste("btn_recap_pop.png", 840, 1085, 430)
print("logo  bbox", b1)
print("btn1  bbox", b2)
print("btn2  bbox", b3)

out = Image.fromarray(canvas.round().clip(0,255).astype(np.uint8))
out.save(os.path.join(OUT, "开始页_波普风.png"))
out.resize((W//2, H//2), Image.LANCZOS).save(os.path.join(OUT, "开始页_波普风_half.png"))
print("saved 开始页_波普风.png", out.size)
