# -*- coding: utf-8 -*-
"""探明两个按钮素材：内容真实范围 + 水印位置。"""
import os
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SRCS = {
    "btn_start": r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\7679eb506d75ddbd0deb609571448c6c.jpg',
    "btn_recap": r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\1728fd5b541491b4799ad1c4dc39d13a.jpg',
}
OUT = os.path.join(ROOT, "shots", "_logowork")

for k, p in SRCS.items():
    a = np.asarray(Image.open(p).convert('RGB')).astype(np.int16)
    H, W = a.shape[:2]
    mn = a.min(2)
    for th in (200, 230, 244):
        m = mn < th
        if m.sum() == 0:
            print(k, 'th', th, '空'); continue
        ys, xs = np.where(m)
        print(f'{k} {W}x{H} th={th}: bbox=({xs.min()},{ys.min()})-({xs.max()},{ys.max()}) w={xs.max()-xs.min()+1} h={ys.max()-ys.min()+1}')
    # 每行前景数，找内容底边
    m = mn < 230
    rows = m.sum(1)
    nz = np.where(rows > 2)[0]
    print('   行前景>2 的范围: y', nz.min(), '..', nz.max())
    # 打印下半部分行前景数
    print('   行前景数(每 40 行):', [(int(y), int(rows[y])) for y in range(0, H, 40)][-8:])
    # 保存底部条带供目视
    Image.fromarray(a[max(0, nz.max()-260):H].astype(np.uint8)).save(OUT + f'\\h_{k}_bottom.png')
    Image.fromarray(a[:nz.min()+120].astype(np.uint8)).save(OUT + f'\\h_{k}_top.png')
print('saved h_*_bottom/top')
