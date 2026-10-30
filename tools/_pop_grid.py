# -*- coding: utf-8 -*-
"""给示意图打网格刻度，便于目视读坐标。"""
import os
import numpy as np
from PIL import Image, ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-47-58-589Z-7543bb88.jpg'
BG   = r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\42013a2d8891ef2ba95117eebbd66cea.jpg'
OUT = os.path.join(ROOT, "shots", "_logowork")

def gridded(im, step=50, big=100):
    im = im.convert('RGB').copy()
    d = ImageDraw.Draw(im)
    W, H = im.size
    for x in range(0, W, step):
        c = (255, 0, 0) if x % big == 0 else (255, 160, 0)
        w = 2 if x % big == 0 else 1
        d.line([(x, 0), (x, H)], fill=c, width=w)
    for y in range(0, H, step):
        c = (0, 0, 255) if y % big == 0 else (0, 200, 255)
        w = 2 if y % big == 0 else 1
        d.line([(0, y), (W, y)], fill=c, width=w)
    # 标数字
    for x in range(0, W, big):
        d.text((x + 3, 3), str(x), fill=(255, 0, 0))
        d.text((x + 3, H - 16), str(x), fill=(255, 0, 0))
    for y in range(0, H, big):
        d.text((3, y + 3), str(y), fill=(0, 0, 255))
        d.text((W - 46, y + 3), str(y), fill=(0, 0, 255))
    return im

mock = Image.open(MOCK)
bg = Image.open(BG)

g = gridded(mock)
g.save(OUT + r'\g00_mock_grid.png')
# 关键区域放大裁剪
g.crop((0, 0, 1300, 800)).save(OUT + r'\g01_logo.png')     # logo 区
g.crop((400, 520, 1100, 1120)).save(OUT + r'\g02_btns.png') # 两按钮区
print('mock', mock.size, 'bg', bg.size)

# 红绿叠加：mock=红, bg=绿；一致→黄
a = np.asarray(mock.convert('L')).astype(np.uint8)
b = np.asarray(bg.convert('L')).astype(np.uint8)
ov = np.dstack([a, b, np.zeros_like(a)])
Image.fromarray(ov).save(OUT + r'\g03_overlay.png')
print('saved g00..g03')
