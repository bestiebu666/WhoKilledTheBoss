# -*- coding: utf-8 -*-
"""模糊去噪后差分，干净定位示意图上贴的 logo / 按钮。"""
import os
import numpy as np
from PIL import Image, ImageFilter
from collections import deque
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-47-58-589Z-7543bb88.jpg'
BG   = r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\42013a2d8891ef2ba95117eebbd66cea.jpg'
OUT = os.path.join(ROOT, "shots", "_logowork")

R = 5
m = Image.open(MOCK).convert('L').filter(ImageFilter.GaussianBlur(R))
b = Image.open(BG).convert('L').filter(ImageFilter.GaussianBlur(R))
a = np.asarray(m).astype(np.int16); c = np.asarray(b).astype(np.int16)
d = np.abs(a - c)
print('模糊后 diff>25 占比 %.2f%%  >40 %.2f%%' % (100*(d > 25).mean(), 100*(d > 40).mean()))

mask = (d > 25).astype(np.uint8)
H, W = mask.shape
lab = np.zeros((H, W), np.int32); nid = 0; out = []
for y in range(H):
    for x in range(W):
        if mask[y, x] and lab[y, x] == 0:
            nid += 1; q = deque([(y, x)]); lab[y, x] = nid
            x0 = x1 = x; y0 = y1 = y; cnt = 0
            while q:
                cy, cx = q.popleft(); cnt += 1
                if cx < x0: x0 = cx
                if cx > x1: x1 = cx
                if cy < y0: y0 = cy
                if cy > y1: y1 = cy
                for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                    ny, nx = cy+dy, cx+dx
                    if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and lab[ny, nx] == 0:
                        lab[ny, nx] = nid; q.append((ny, nx))
            if cnt >= 400:
                out.append((cnt, x0, y0, x1, y1))
out.sort(reverse=True)
print('连通域(面积>=400) top12:')
for o in out[:12]:
    print('  面积%7d bbox=(%d,%d)-(%d,%d) w=%d h=%d' % (o[0], o[1], o[2], o[3], o[4], o[3]-o[1]+1, o[4]-o[2]+1))

# 保存 diff 可视化：差异处标红
vis = np.asarray(Image.open(MOCK).convert('RGB')).copy()
vis[mask > 0] = (vis[mask > 0] * 0.25 + np.array([255, 0, 0]) * 0.75).astype(np.uint8)
Image.fromarray(vis).save(OUT + r'\d_diff_vis.png')
Image.fromarray(np.clip(d*4, 0, 255).astype(np.uint8)).save(OUT + r'\d_diff_gray.png')
print('saved d_diff_vis.png d_diff_gray.png')
