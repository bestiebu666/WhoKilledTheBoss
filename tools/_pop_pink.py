# -*- coding: utf-8 -*-
"""用「粉色」特征在示意图和 logo 素材里各找文字块，反算缩放与平移。"""
import os
import numpy as np
from PIL import Image
from collections import deque
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MOCK = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-47-58-589Z-7543bb88.jpg'
CUT = os.path.join(ROOT, "shots", "_logowork", "pop2_logo_cut.png")
OUT = os.path.join(ROOT, "shots", "_logowork")

def pink(rgb):
    r, g, b = rgb[..., 0].astype(np.float32), rgb[..., 1].astype(np.float32), rgb[..., 2].astype(np.float32)
    return np.clip(r - 0.55 * (g + b), 0, None)

def comps(mask, minpx=200):
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
                    for dy, dx in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
                        ny, nx = cy+dy, cx+dx
                        if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = nid; q.append((ny, nx))
                if cnt >= minpx:
                    out.append((cnt, x0, y0, x1, y1))
    out.sort(reverse=True)
    return out

mock = np.asarray(Image.open(MOCK).convert('RGB'))
cut = np.asarray(Image.open(CUT).convert('RGBA'))
cut_rgb = cut[..., :3]; cut_a = cut[..., 3].astype(np.float32) / 255.0

Pm = pink(mock)
Pl = pink(cut_rgb) * cut_a
for th in (30, 45, 60):
    print('mock  pink>%d 像素 %d (%.2f%%)' % (th, (Pm > th).sum(), 100*(Pm > th).mean()))
for th in (30, 45, 60):
    print('cut   pink>%d 像素 %d (%.2f%%)' % (th, (Pl > th).sum(), 100*(Pl > th).mean()))

for th in (45,):
    print('\n=== mock 粉色连通域 top6 (th=%d) ===' % th)
    for c in comps(Pm > th)[:6]:
        print('  面积%6d bbox=(%d,%d)-(%d,%d) w=%d h=%d' % (c[0], c[1], c[2], c[3], c[4], c[3]-c[1]+1, c[4]-c[2]+1))
    print('=== logo 素材 粉色连通域 top6 (th=%d) ===' % th)
    for c in comps(Pl > th)[:6]:
        print('  面积%6d bbox=(%d,%d)-(%d,%d) w=%d h=%d' % (c[0], c[1], c[2], c[3], c[4], c[3]-c[1]+1, c[4]-c[2]+1))

# 视觉诊断：把两边粉色 mask 叠出来
Image.fromarray(np.clip(Pm, 0, 255).astype(np.uint8)).save(OUT + r'\p_mock_pink.png')
Image.fromarray(np.clip(Pl, 0, 255).astype(np.uint8)).save(OUT + r'\p_cut_pink.png')
print('saved p_mock_pink.png p_cut_pink.png')
