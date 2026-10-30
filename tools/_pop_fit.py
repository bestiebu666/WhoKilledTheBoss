# -*- coding: utf-8 -*-
"""暴力拟合：把三张素材贴到底图上，最小化与示意图的像素差，定出 (scale, x, y)。"""
import os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG   = r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\42013a2d8891ef2ba95117eebbd66cea.jpg'
MOCK = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-47-58-589Z-7543bb88.jpg'
CUT = os.path.join(ROOT, "shots", "_logowork")

bg = np.asarray(Image.open(BG).convert('RGB')).astype(np.float32)
mk = np.asarray(Image.open(MOCK).convert('RGB')).astype(np.float32)
H, W = bg.shape[:2]

def fit(name, scales, xs, ys):
    src = Image.open(CUT + '\\' + name).convert('RGBA')
    best = None
    for s in scales:
        L = src.resize((max(1, int(src.width*s)), max(1, int(src.height*s))), Image.LANCZOS)
        la = np.asarray(L).astype(np.float32)
        a = (la[..., 3:4] / 255.0); rgb = la[..., :3]
        hh, ww = a.shape[:2]
        wgt_full = (1.0 + 2.0*a[..., 0]).sum()
        for y in ys:
            y0, y1 = max(0, y), min(H, y+hh)
            if y1 <= y0: continue
            for x in xs:
                x0, x1 = max(0, x), min(W, x+ww)
                if x1 <= x0: continue
                sa = a[y0-y:y1-y, x0-x:x1-x]
                srgb = rgb[y0-y:y1-y, x0-x:x1-x]
                comp = sa*srgb + (1-sa)*bg[y0:y1, x0:x1]
                # 只在素材覆盖处比，加权 1+2a；画外部分按 200 罚（防「缩到很小躲开」的退化解）
                wgt = 1.0 + 2.0*sa
                diff = np.abs(comp - mk[y0:y1, x0:x1]).mean(2)
                wsum = float(wgt[..., 0].sum())
                sc = float(((diff*wgt[..., 0]).sum() + 200.0*(wgt_full - wsum)) / wgt_full)
                if best is None or sc < best[0]:
                    best = (sc, s, x, y, ww, hh)
    return best

print('=== logo ===')
b = fit('pop2_logo_cut.png', np.arange(0.85, 1.451, 0.05), range(-220, 121, 25), range(-240, 261, 25))
print('  粗: score=%.2f s=%.2f x=%d y=%d' % (b[0], b[1], b[2], b[3]))
b = fit('pop2_logo_cut.png', np.arange(b[1]-0.05, b[1]+0.051, 0.01),
        range(b[2]-25, b[2]+26, 5), range(b[3]-25, b[3]+26, 5))
print('  细: score=%.2f s=%.3f x=%d y=%d rect=(%d,%d)-(%d,%d)' % (b[0], b[1], b[2], b[3], b[2], b[3], b[2]+b[4], b[3]+b[5]))
LOGO = b

print('=== btn_start ===')
b = fit('pop2_btn_start_cut.png', np.arange(0.46, 0.701, 0.02), range(470, 631, 15), range(540, 721, 15))
print('  粗: score=%.2f s=%.2f x=%d y=%d' % (b[0], b[1], b[2], b[3]))
b = fit('pop2_btn_start_cut.png', np.arange(b[1]-0.03, b[1]+0.031, 0.01),
        range(b[2]-20, b[2]+21, 4), range(b[3]-20, b[3]+21, 4))
print('  细: score=%.2f s=%.3f x=%d y=%d rect=(%d,%d)-(%d,%d)' % (b[0], b[1], b[2], b[3], b[2], b[3], b[2]+b[4], b[3]+b[5]))
BTN1 = b

print('=== btn_recap ===')
b = fit('pop2_btn_recap_cut.png', np.arange(0.28, 0.501, 0.02), range(480, 651, 15), range(780, 951, 15))
print('  粗: score=%.2f s=%.2f x=%d y=%d' % (b[0], b[1], b[2], b[3]))
b = fit('pop2_btn_recap_cut.png', np.arange(b[1]-0.03, b[1]+0.031, 0.01),
        range(b[2]-20, b[2]+21, 4), range(b[3]-20, b[3]+21, 4))
print('  细: score=%.2f s=%.3f x=%d y=%d rect=(%d,%d)-(%d,%d)' % (b[0], b[1], b[2], b[3], b[2], b[3], b[2]+b[4], b[3]+b[5]))
BTN2 = b

print('\n=== PARAMS ===')
print('logo,%.3f,%d,%d' % (LOGO[1], LOGO[2], LOGO[3]))
print('btn_start,%.3f,%d,%d' % (BTN1[1], BTN1[2], BTN1[3]))
print('btn_recap,%.3f,%d,%d' % (BTN2[1], BTN2[2], BTN2[3]))
