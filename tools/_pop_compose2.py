# -*- coding: utf-8 -*-
"""参数化合成：底图 + logo + 两按钮。出合成图 + 与示意图的叠加/并排核对图。

用法: python _pop_compose2.py  (参数写死在 PARAMS 里)
"""
import os
import sys
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG   = r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\42013a2d8891ef2ba95117eebbd66cea.jpg'
MOCK = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-47-58-589Z-7543bb88.jpg'
CUT = os.path.join(ROOT, "shots", "_logowork")
OUT = os.path.join(ROOT, "shots", "_logowork")

# (文件名, 左上角x, 左上角y, 目标缩放)
PARAMS = [
    ("pop2_logo_cut.png",      -94,  132, 0.94),
    ("pop2_btn_start_cut.png", 536,  617, 0.573),
    ("pop2_btn_recap_cut.png", 553,  847, 0.384),
]
# 允许命令行覆盖：name,x,y,s;name,x,y,s
if len(sys.argv) > 1:
    PARAMS = []
    for part in sys.argv[1].split(';'):
        n, x, y, s = part.split(',')
        PARAMS.append((n, float(x), float(y), float(s)))

base = Image.open(BG).convert('RGB')
W, H = base.size
canvas = np.asarray(base).astype(np.float32)

def lum(x):
    return x @ np.array([0.2126, 0.7152, 0.0722], np.float32)

def paste(name, x, y, scale):
    im = Image.open(CUT + '\\' + name).convert('RGBA')
    im = im.resize((max(1, int(im.width*scale)), max(1, int(im.height*scale))), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    hh, ww = arr.shape[:2]
    px, py = int(round(x)), int(round(y))
    # 白场匹配
    pl = lum(arr[..., :3]); pmask = pl > 228
    region = canvas[max(py, 0):min(py+hh, H), max(px, 0):min(px+ww, W)]
    if region.size:
        rl = lum(region); bmask = rl > 215
        if pmask.sum() > 50 and bmask.sum() > 50:
            gain = np.median(region[bmask], 0) / np.maximum(np.median(arr[..., :3][pmask], 0), 1)
            gain = np.clip(gain, 0.88, 1.06)
            arr[..., :3] = np.clip(arr[..., :3] * gain, 0, 255)
    alpha = arr[..., 3:4] / 255.0
    xa, ya, xb, yb = max(px, 0), max(py, 0), min(px+ww, W), min(py+hh, H)
    sa = alpha[ya-py:yb-py, xa-px:xb-px]
    canvas[ya:yb, xa:xb] = canvas[ya:yb, xa:xb]*(1-sa) + arr[ya-py:yb-py, xa-px:xb-px, :3]*sa
    return (px, py, px+ww, py+hh)

print('== 合成 ==')
for n, x, y, s in PARAMS:
    print('  %-26s -> rect %s' % (n, paste(n, x, y, s)))

out = Image.fromarray(canvas.round().clip(0, 255).astype(np.uint8))
out.save(OUT + r'\q_comp.png')

# 叠加核对：示意图=红通道, 合成=绿通道（对齐→黄）
mk = np.asarray(Image.open(MOCK).convert('L')).astype(np.float32)
cp = np.asarray(out.convert('L')).astype(np.float32)
ov = np.dstack([mk, cp, np.zeros_like(mk)]).clip(0, 255).astype(np.uint8)
Image.fromarray(ov).save(OUT + r'\q_overlay.png')

# 并排
sbs = Image.new('RGB', (W, H*2+16), (255, 255, 255))
sbs.paste(Image.open(MOCK).convert('RGB'), (0, 0))
sbs.paste(out, (0, H+16))
sbs.resize((W//2, (H*2+16)//2), Image.LANCZOS).save(OUT + r'\q_sbs.png')

# 局部放大：logo 区 / 按钮区
out.crop((0, 0, 1250, 800)).save(OUT + r'\q_logo.png')
out.crop((430, 560, 1030, 1080)).save(OUT + r'\q_btns.png')
print('saved q_comp / q_overlay / q_sbs / q_logo / q_btns')
