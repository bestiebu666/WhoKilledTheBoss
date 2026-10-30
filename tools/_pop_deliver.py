# -*- coding: utf-8 -*-
"""出最终交付：开始页合成图（底图 + logo + 两个按钮）。"""
import os
import shutil
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SRC = os.path.join(ROOT, "shots", "_logowork", "q_comp.png")
MOCK = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-47-58-589Z-7543bb88.jpg'
OUTD = os.path.join(ROOT, "shots")
CHK = os.path.join(ROOT, "shots", "_logowork")

im = Image.open(SRC).convert('RGB')
im.save(OUTD + r'\开始页_波普风_合成.png')
im.resize((im.width // 2, im.height // 2), Image.LANCZOS).save(OUTD + r'\开始页_波普风_合成_half.png')

# 对照图：上=示意图 下=合成
mk = Image.open(MOCK).convert('RGB')
sheet = Image.new('RGB', (im.width, im.height * 2 + 14), (255, 255, 255))
sheet.paste(mk, (0, 0)); sheet.paste(im, (0, im.height + 14))
sheet.resize((im.width // 2, (im.height * 2 + 14) // 2), Image.LANCZOS).save(OUTD + r'\开始页_对照_示意vs合成.png')

# 右下角水印校验
im.crop((1400, 1050, 1801, 1280)).save(CHK + r'\w_corner.png')
print('尺寸', im.size)
print('saved 开始页_波普风_合成.png / _half.png / 开始页_对照_示意vs合成.png')
