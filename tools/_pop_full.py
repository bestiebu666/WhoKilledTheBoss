# -*- coding: utf-8 -*-
"""开始页整图（波普风）合成：设计稿 1:1 上屏版。

作者 2026-10-06 要求「1比1做成这样，直接贴图上去，放到游戏里做开始页面，底下两个可交互」。

成品 = 2276x1280（正好 16:9 = 游戏窗口比例）：
  - 中间 x[237,2038] = 设计稿 A（1801x1280）原样
  - 左右各 237px = A 左/右边缘镜像（接缝像素级连续）
  - 右下角水印：用作者自己擦干净的底图 B 同区域覆盖
  - 两个按钮：A 图里连装饰一起抠掉（B 图同位置补底纹，露出星爆），
    游戏里改贴透明素材 btn_*_pop.png（TextureButton，可 hover 缩放/点击）
  - 镜像产生的反字（左 IAAAALALW 竖条 / 右 MY BEATING FOR YOU 白条）用补丁内干净底纹平移涂盖

输出：
  assets/textures/ui/title_pop_full.png   成品背景
  shots/_logowork/60_full_check.png       全图缩略自验
  shots/_logowork/61_btn_zone.png         按钮抠除区放大自验
  shots/_logowork/62_patch_zone.png       两个涂盖区自验
  同时打印两个按钮的「黑条对齐」贴回矩形（写进 frontend.json）
"""
import os
import numpy as np
from PIL import Image

A_PATH = r'C:\Users\33667\.workbuddy\clipboard-images\clipboard-2026-10-05T10-07-41-122Z-7543bb88.jpg'
B_PATH = r'D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219\42013a2d8891ef2ba95117eebbd66cea.jpg'
OUT_DIR = ROOT
CHK_DIR = OUT_DIR + r'\shots\_logowork'

PAD = 237                      # 左右补丁宽 = (1280*16/9 - 1801) / 2
FULL_W, FULL_H = 1801 + PAD * 2, 1280   # 2276 x 1280

imA = np.asarray(Image.open(A_PATH).convert('RGB')).astype(np.float32)
imB = np.asarray(Image.open(B_PATH).convert('RGB')).astype(np.float32)
assert imA.shape == (1280, 1801, 3) and imB.shape == (1280, 1801, 3)

a = imA.copy()

# ---- 1. 右下角水印：B 图同区域覆盖（作者已擦干净）----
a[1125:1280, 1440:1801] = imB[1125:1280, 1440:1801]

# ---- 2. 抠两个按钮（含装饰云底）：B 图同位置补底纹 ----
BTN1 = (585, 845, 535, 1005)   # y0,y1,x0,x1  开始游戏（含刀/星/虚线）
BTN2 = (830, 1050, 545, 985)   # 前情提要（含猫/星/虚线）
for y0, y1, x0, x1 in (BTN1, BTN2):
    a[y0:y1, x0:x1] = imB[y0:y1, x0:x1]

# ---- 3. 镜像扩幅 ----
full = np.zeros((FULL_H, FULL_W, 3), np.float32)
full[:, PAD:PAD + 1801] = a
full[:, :PAD] = a[:, :PAD, ::-1]              # 左镜像
full[:, PAD + 1801:] = a[:, 1801 - PAD:, ::-1]  # 右镜像

# ---- 4. 涂镜像反字/重复主体 ----
# 程序生成 2x2 棋盘格（颜色从修好水印的青/黑格区采样 + 高斯噪声仿 JPEG 颗粒）。
# 图内采样带两次翻车（黄格区 / 底图自带的「100」标签贴纸都会被平铺出异物），
# 程序格子是唯一能保证「无异物」的填充。
# 颜色采样：水印修复后的右下角格纹区，按亮度分位取「亮青 / 深黑」两组均值
# （均值法会被白点污染 —— 第一次采出 青=107,148,151 黑=30,90,97 的脏色）
_reg = a[1200:1280, 1564:1801].reshape(-1, 3)
_lum = _reg @ np.array([0.299, 0.587, 0.114])
_cy = _reg[_lum > np.percentile(_lum, 70)].mean(0)
_dk = _reg[_lum < np.percentile(_lum, 25)].mean(0)
print('采样色  青=%s 黑=%s' % (_cy.astype(int), _dk.astype(int)))

def checker(x0, x1, y0, y1, cell=110, seed=7):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    parity = ((xx // cell) + (yy // cell)) % 2
    img = np.where(parity[..., None] == 0, _dk, _cy).astype(np.float32)
    # 白点：原图青格/黑格都带 ~6px 白点（间距 ~55px），撒点补质感，别让程序格太「数字」
    white = np.array([236, 249, 251], np.float32)
    for gy in range(y0 - y0 % 55 + 27, y1, 55):
        for gx in range(x0 - x0 % 55 + 27, x1, 55):
            r2 = (yy - gy) ** 2 + (xx - gx) ** 2
            m = r2 <= 36
            img[m] = img[m] * 0.15 + white * 0.85
    img += rng.normal(0, 5.0, img.shape)
    return np.clip(img, 0, 255)

# 左：IAAAALALW 竖条镜像区（A 里 x[20,190] y[330,805] → full x[47,217]）
full[330:805, 40:225] = checker(40, 225, 330, 805)
# 右：场记板+MY BEATING FOR YOU 白条镜像区（y[505,1280] 整段）
#     （场记板镜像会翻出第二块板，白条会翻反字 —— 一并换掉，接缝就是「画面边缘裁切」的自然观感）
full[505:FULL_H, PAD + 1801:] = checker(PAD + 1801, FULL_W, 505, FULL_H)

# ---- 5. 按钮素材贴回矩形（目视框 + 整幅面积对齐）----
# 素材与原稿按钮的黑条构图比例不同（作者素材是重新构图的），黑条对不上；
# 但整幅「按钮组区」（黑条+装饰+云底）比例一致（≈1.9），按整幅面积对齐。
# 组区 bbox 为 64_barA_check.png 目视核实值：(x0, x1, y0, y1)
ZONE1 = (555, 990, 590, 830)    # 开始游戏组区（含刀/星/虚线/云底）
ZONE2 = (555, 970, 843, 1040)   # 前情提要组区（含猫/星/虚线/云底）

def full_rect(zone, img_w, img_h, pad=PAD):
    x0, x1, y0, y1 = zone
    k = ((x1 - x0) * (y1 - y0) / (img_w * img_h)) ** 0.5   # 面积对齐
    px = (x0 + x1) / 2 - k * img_w / 2 + pad
    py = (y0 + y1) / 2 - k * img_h / 2
    return [round(px), round(py), round(px + k * img_w), round(py + k * img_h)], k

r1, k1 = full_rect(ZONE1, 760, 391)
r2, k2 = full_rect(ZONE2, 904, 461)
print('素材1 btn_start_pop(760x391) k=%.3f 贴回成品图矩形:' % k1, r1)
print('素材2 btn_recap_pop(904x461) k=%.3f 贴回成品图矩形:' % k2, r2)
for r, (y0, y1, x0, x1) in ((r1, BTN1), (r2, BTN2)):
    assert r[0] - PAD >= x0 - 12 and r[2] - PAD <= x1 + 12, '素材1超出抠除区 %s vs %s' % (r, (x0, x1))
    assert r[1] >= y0 - 12 and r[3] <= y1 + 12, '素材超出抠除区 %s' % r

# ---- 6. 输出 ----
out = np.clip(full, 0, 255).astype(np.uint8)
Image.fromarray(out).save(OUT_DIR + r'\assets\textures\ui\title_pop_full.png')

# 自验图
Image.fromarray(out).resize((1138, 640), Image.LANCZOS).save(CHK_DIR + r'\60_full_check.png')
bz = Image.fromarray(out[540:1100, 700:1350])
bz.save(CHK_DIR + r'\61_btn_zone.png')
Image.fromarray(out[280:900, 0:320]).save(CHK_DIR + r'\62_patch_left.png')
Image.fromarray(out[900:1280, 1900:2276]).save(CHK_DIR + r'\63_patch_right.png')

# 黑条 bbox 目视验证：画到原图和素材上
va = Image.fromarray(imA.astype(np.uint8))
from PIL import ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
vd = ImageDraw.Draw(va)
for zone, col in ((ZONE1, (255, 0, 0)), (ZONE2, (0, 128, 255))):
    vd.rectangle([zone[0], zone[2], zone[1], zone[3]], outline=col, width=4)
va.crop((430, 560, 1030, 1080)).save(CHK_DIR + r'\64_barA_check.png')

# 模拟游戏最终效果：素材贴回成品图（背景已抠按钮 → 贴素材 ≈ 游戏里的样子）
def _paste_rgba(path, rect):
    sp = Image.open(path).convert('RGBA')
    sp = sp.resize((rect[2] - rect[0], rect[3] - rect[1]), Image.LANCZOS)
    layer = Image.new('RGBA', (FULL_W, FULL_H), (0, 0, 0, 0))
    layer.paste(sp, (rect[0], rect[1]), sp)
    return layer

sim = Image.fromarray(out).convert('RGBA')
sim = Image.alpha_composite(sim, _paste_rgba(OUT_DIR + r'\assets\textures\ui\btn_start_pop.png', r1))
sim = Image.alpha_composite(sim, _paste_rgba(OUT_DIR + r'\assets\textures\ui\btn_recap_pop.png', r2))
sim = sim.convert('RGB')
sim.resize((1138, 640), Image.LANCZOS).save(CHK_DIR + r'\66_sim_game.png')
sim.crop((640, 500, 1360, 1120)).save(CHK_DIR + r'\67_sim_btns.png')
print('saved checks 60-67')
print('saved title_pop_full.png + checks')
