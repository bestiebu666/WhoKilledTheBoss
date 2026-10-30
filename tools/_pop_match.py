# -*- coding: utf-8 -*-
"""在示意图里自动定位 logo（洋红特征 FFT 互相关 + 多尺度）。"""
import os
import numpy as np
from PIL import Image

MOCK = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-47-58-589Z-7543bb88.jpg'
LOGO = os.path.join(ROOT, "shots", "_logowork", "pop2_logo_cut.png")
OUT = os.path.join(ROOT, "shots", "_logowork")

def feat(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return np.clip(r - (g + b) * 0.5, 0, None)

def local_stats(P, h, w):
    H, W = P.shape
    c1 = np.zeros((H + 1, W + 1)); c2 = np.zeros((H + 1, W + 1))
    c1[1:, 1:] = np.cumsum(np.cumsum(P, 0), 1)
    c2[1:, 1:] = np.cumsum(np.cumsum(P * P, 0), 1)
    def box(c):
        return c[h:H+1, w:W+1] - c[0:H-h+1, w:W+1] - c[h:H+1, 0:W-w+1] + c[0:H-h+1, 0:W-w+1]
    n = h * w
    s1 = box(c1); s2 = box(c2)
    mean = s1 / n
    var = np.maximum(s2 - n * mean * mean, 1e-6)
    return mean, np.sqrt(var)

def ncc(P, T):
    H, W = P.shape; h, w = T.shape
    Tm = T - T.mean(); tn = np.sqrt((Tm * Tm).sum())
    if tn < 1e-6 or h >= H or w >= W: return None
    F = np.fft.rfft2(P, (H + h - 1, W + w - 1))
    G = np.fft.rfft2(Tm[::-1, ::-1], (H + h - 1, W + w - 1))
    corr = np.fft.irfft2(F * G, (H + h - 1, W + w - 1))[:H, :W]
    _, std = local_stats(P, h, w)
    n = h * w
    return corr[:H - h + 1, :W - w + 1] / (tn * std * np.sqrt(n))

mock = np.asarray(Image.open(MOCK).convert('RGB')).astype(np.float32)
logo = Image.open(LOGO).convert('RGBA')
la = np.asarray(logo).astype(np.float32)
lg = la[..., :3]
alpha = (la[..., 3:4] / 255.0)
# 只保留 logo 洋红区域做模板
lf = feat(lg) * alpha[..., 0]

P = feat(mock)
print('mock', P.shape, 'logo', lf.shape)

best = None
for s in np.arange(0.55, 1.30, 0.02):
    h = max(8, int(lf.shape[0] * s)); w = max(8, int(lf.shape[1] * s))
    T = np.asarray(Image.fromarray(lf.astype(np.uint8)).resize((w, h), Image.BILINEAR)).astype(np.float32)
    sc = ncc(P, T)
    if sc is None: continue
    idx = np.unravel_index(np.argmax(sc), sc.shape)
    v = sc[idx]
    if best is None or v > best[0]:
        best = (v, s, idx[1], idx[0], w, h)
    print(f'  s={s:.2f} {w}x{h}  peak={v:.3f} @ ({idx[1]},{idx[0]})')

v, s, x, y, w, h = best
print(f'\n最佳: scale={s:.3f}  bbox abs=({x},{y})-({x+w},{y+h})  w={w} h={h}  NCC={v:.3f}')

# 诊断图
from PIL import ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = Image.open(MOCK).convert('RGB').copy()
dr = ImageDraw.Draw(d)
dr.rectangle([x, y, x + w, y + h], outline=(255, 0, 0), width=4)
d.save(OUT + r'\m_logo_match.png')
print('saved m_logo_match.png')
