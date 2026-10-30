# -*- coding: utf-8 -*-
"""作者给的三张 UI 素材 -> Godot 能直接用的 PNG。

来源 / 用途：
    感叹号   D:\\...\\6371dfc0...\\7c07ccdd....jpg   线索提示（替代 3D 发光）—— 头顶挂的角标
    问号框   D:\\...\\4f1a310d...\\07eefd33....jpg   点感叹号弹的「线索框」底图
    便签框   D:\\...\\4f1a310d...\\678c5d83....jpg   右上角「已记下的东西」面板底图

⛔⛔ 2026-10-06 作者的反馈（这一版重做的原因）：
    「你的线索框贴图有问题，没有显示全，能不能重新抠图导入一下」
  上一版错在哪：把整张照片（**白纸 + 一圈波点纸**）原样贴进 UI ——
  卡片矩形里白纸黑框只占中间一块，四周全是不该出现的波点纸，
  看起来就是「框没显示全、歪在一边」。
  作者真正要的：**把白纸黑框从波点纸背景里抠出来**，卡片 = 白纸黑框本身。
  （而白纸**内部**要填实 —— 作者 2026-10-05 晚说过「里面的白色都是填充的，
    不是让你扣框的」。所以是「抠外圈、留内部」，不是「抠白」也不是「全留」。）

现在的做法（见 make_frame）：
    ① 「黑线」= 亮度 < 175 的像素（阈值放宽是为了把 JPEG 压出来的 1px 缝隙堵上）；
    ② 从画布四边往里**灌水**，能走到的都算「框外」—— 波点纸走得通，于是整片被抠掉；
       ⛔ 框内的白纸被黑框**围死**、问号 / 星 / 便签 的黑线自己也是闭合环，
          灌水都灌不进去 —— 所以框内白纸、问号里的白、便签里的白全部保得住。
    ③ **兜底**：框内矩形里凡是「亮像素（> 235）」一律强制 alpha=1。
       这一步只补白、不碰黑线（黑线本来就不在灌水结果里），所以装饰不会被擦掉。
    ④ 裁到内容 bbox 输出 —— 这一步才让「卡片矩形 = 白纸黑框」。

⛔ 三个踩过的坑（别再回去）：
    · 「按亮度一刀切把白判成背景」+「离黑线多远的保护区」= 框内白纸被整片镂空；
    · 用一个大矩形 `fill_box` 把整块刷白 = 把问号 / 星 / 便签**擦掉了**
      （作者后来专门说「没有显示全」，就是这一版）；
    · 「整张照片全留」= 卡片四周带一圈波点纸，同样被说成「没显示全」。

输出（assets/textures/ui/）：
    icon_clue.png        感叹号图标（RGBA，尺寸 = 内容，**黑描边 + 笔画内部白**）
    card_clue.png        问号线索框（RGBA，已裁到黑框）
    card_journal.png     便签「已记下的东西」框（RGBA，已裁到「黑框 + 星 + 便签」）

⛔⛔ 三张图**共用同一条判据**：从画布四边灌水抠背景。
    「黑线围起来的白 = 内容、要留；跟画布边缘连通的白纸 = 背景、要抠」。
    别再用「按亮度当 alpha」那一套 —— 感叹号就是那么翻的车（2026-10-06）。

脚本会把两张框的**文字安全区**按输出图比例打出来 —— hud.gd 的 CARD_*_SAFE 直接抄。

用法：
    "C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe" tools/ui_card_prep.py
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

D1 = r"D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\6371dfc09d97d33a3cb8f5aff65d6d5b"
D2 = r"D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219"
OUT = os.path.join(ROOT, "assets", "textures", "ui")
CHK = os.path.join(ROOT, "shots", "_logowork")
LUM = np.array([0.2126, 0.7152, 0.0722], np.float32)

os.makedirs(OUT, exist_ok=True)
os.makedirs(CHK, exist_ok=True)


def load(p: str) -> np.ndarray:
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32)


def lum(a: np.ndarray) -> np.ndarray:
    return a @ LUM


def dilate(m: np.ndarray, r: int) -> np.ndarray:
    out = m.copy()
    for _ in range(r):
        nb = out.copy()
        nb[1:, :] |= out[:-1, :]
        nb[:-1, :] |= out[1:, :]
        nb[:, 1:] |= out[:, :-1]
        nb[:, :-1] |= out[:, 1:]
        out = nb
    return out


def flood_from_border(cand: np.ndarray, max_iter: int = 60000) -> np.ndarray:
    """从画布四边往里灌水，返回「和边缘连通」的掩码。

    ⛔ 必须用**连通性**，不能用「离黑线多远」。灌水的语义天然正确：
       只有从画布边缘走得到的区域才是背景；被黑线围死的框内区域一律保得住。
    """
    seed = np.zeros_like(cand)
    seed[0, :] = cand[0, :]
    seed[-1, :] = cand[-1, :]
    seed[:, 0] = cand[:, 0]
    seed[:, -1] = cand[:, -1]
    for _ in range(max_iter):
        nb = np.zeros_like(seed)
        nb[1:, :] |= seed[:-1, :]
        nb[:-1, :] |= seed[1:, :]
        nb[:, 1:] |= seed[:, :-1]
        nb[:, :-1] |= seed[:, 1:]
        new = nb & cand & ~seed
        if not new.any():
            return seed
        seed |= new
    raise SystemExit("灌水不收敛")


def bbox_of(mask: np.ndarray) -> tuple:
    ys, xs = np.where(mask)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def box3(m: np.ndarray) -> np.ndarray:
    """3x3 均值（零填充）。只给硬掩码外沿做 1px 软边，不需要高斯。"""
    h, w = m.shape
    s = np.zeros((h + 2, w + 2), np.float32)
    s[1:-1, 1:-1] = m.astype(np.float32)
    acc = np.zeros((h, w), np.float32)
    for dy in range(3):
        for dx in range(3):
            acc += s[dy:dy + h, dx:dx + w]
    return acc / 9.0


# ---------------------------------------------------------------- 1. 感叹号
## ⛔⛔ 2026-10-06 作者第二次反馈（这一版重做的原因）：
##    「感叹号是有白色底的哦，不要全扣了只留黑框……不要纯黑框」
## 上一版错在哪：拿**亮度当 alpha**（`(250-L)/220`）——
##    笔画内部的白 L≈254 → alpha≈0，于是整只图标只剩三根黑线框。
## 正确做法 = 跟 `btn_prep.py` / 两张纸框**同一套判据**：从画布四边灌水。
##    ① 「可通行区」= 亮像素（L >= INK_LEVEL），黑描边是墙；
##    ② 从画布四边灌：**笔画外面的白纸**跟边缘连通 → 抠掉；
##       **笔画内部的白**被黑描边围死 → 灌不进去 → 留住（这就是「白色底」）；
##    ③ 掩码 3x3 均值做 1px 软边 + 纯黑芯回写 1.0（别把黑线模糊了）。
## ⚠ INK_LEVEL 的选取：源图极干净（纸 L≈254、纯黑 L<60、下分位 5% 还有 242），
##    200 正好卡在描边抗锯齿的斜坡上 —— 边缘位置才准。
##    探过 185 / 200 / 215，保留面积都是 8.5%（纯黑线只占 4.3%），
##    说明内部白确实被围死了、没有从缝里漏出去。
def make_icon(ink_level: float = 200.0, keep_paper: bool = False,
              save: bool = True) -> np.ndarray:
    """keep_paper=True 时退化成「整张白纸都留」（备选方案，只用于对照图，不落盘）。"""
    a = load(os.path.join(D1, "7c07ccdd5804c483c7bb42b13bb81d07.jpg"))
    L = lum(a)

    if keep_paper:
        alpha = np.ones_like(L, np.float32)
    else:
        ink = dilate(L < ink_level, 1)     # 加粗 1px：堵住 JPEG 压出来的 1px 缝
        bg = flood_from_border(~ink)
        hard = (~bg).astype(np.float32)
        alpha = box3(hard)
        alpha[L < 120.0] = 1.0             # 纯黑芯保持实心
        print("   灌水背景占 %.1f%%（= 抠掉的白纸）  保留 %.1f%%（黑线只占 %.1f%%）"
              % (100.0 * bg.mean(), 100.0 * (~bg).mean(), 100.0 * (L < ink_level).mean()))

    # ⛔ 必须裁到内容 bbox —— 源图 909x1212 里「!!!」只占中间一条横带，
    #    不裁的话 Sprite3D 按「图片高 = CLUE_ICON_H」定尺寸，图标会被压成一小条。
    x0, y0, x1, y1 = bbox_of(alpha > 0.5)
    m = 4
    x0, y0 = max(0, x0 - m), max(0, y0 - m)
    x1, y1 = min(a.shape[1], x1 + m), min(a.shape[0], y1 + m)
    a = a[y0:y1, x0:x1]
    alpha = alpha[y0:y1, x0:x1]

    rgb = np.clip(a, 0, 255)               # 黑线保持黑、白底保持白，直接留原色
    rgba = np.dstack([rgb, alpha * 255.0]).round().clip(0, 255).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    if save:
        img.save(os.path.join(OUT, "icon_clue.png"))
        print("icon_clue.png      %dx%d  AR=%.4f  不透明均值 %.2f"
              % (img.width, img.height, img.width / float(img.height), alpha.mean()))
    return np.asarray(img)


def icon_compare() -> None:
    """对照图：抠好的（留笔画内部白） vs 整张白纸都留 —— 让作者一眼挑。"""
    img = Image.open(os.path.join(OUT, "icon_clue.png")).convert("RGBA")
    # ⛔ 备选方案**不能落盘** —— 否则会把正式产物 icon_clue.png 覆盖掉。
    paper = Image.fromarray(make_icon(keep_paper=True, save=False), "RGBA")
    cells = [("A 灌水抠白纸（正式产物）", img), ("B 整张白纸都留（备选）", paper)]
    bgs = [(255, 255, 255), (0xD9, 0xBE, 0x96), (0x4B, 0x4A, 0x47),
           (0x8F, 0xA9, 0xC4)]
    pad, lab = 12, 26
    cw = max(c[1].width for c in cells)
    ch = max(c[1].height for c in cells)
    sheet = Image.new("RGB",
                      (pad + len(cells) * (cw + pad), lab + len(bgs) * (ch + pad) + pad),
                      (245, 245, 245))
    d = ImageDraw.Draw(sheet)
    try:                                   # 中文标签要有中文字体，默认点阵字画不出
        f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 18)
    except Exception:
        f = ImageFont.load_default()
    for ci, (name, im) in enumerate(cells):
        x = pad + ci * (cw + pad)
        d.text((x, 4), name, fill=(20, 20, 20), font=f)
        for ri, c in enumerate(bgs):
            y = lab + ri * (ch + pad)
            bg = Image.new("RGB", (cw, ch), c)
            bg.paste(im, ((cw - im.width) // 2, (ch - im.height) // 2), im)
            sheet.paste(bg, (x, y))
    sheet.save(os.path.join(CHK, "u01_icon_compare.png"))
    print("对照图 -> shots/_logowork/u01_icon_compare.png")

    # 单张产物预览（三种底）
    sheet2 = Image.new("RGB", (pad + 3 * (img.width + pad), img.height + 2 * pad), (255, 255, 255))
    for i, c in enumerate([(255, 255, 255), (0xD9, 0xBE, 0x96), (0x4B, 0x4A, 0x47)]):
        bg = Image.new("RGB", img.size, c)
        bg.paste(img, (0, 0), img)
        sheet2.paste(bg, (pad + i * (img.width + pad), pad))
    sheet2.save(os.path.join(CHK, "u01_icon_on_bg.png"))


# ---------------------------------------------------------------- 2/3. 两个纸框
def make_frame(src: str, out_name: str, tag: str, box: tuple, safe: tuple, extra: list,
               ink_level: float = 120.0, paper_level: float = 235.0,
               inset: int = 14) -> None:
    """把「白纸 + 黑框（+ 装饰）」从波点纸背景里抠出来。

    box   = 黑框**外沿** bbox(x0, y0, x1, y1)，源图像素（投影法量，见量测输出）
    safe  = 文字安全区 bbox，源图像素 —— 要**让开框内的大装饰**（问号 / 星）
    extra = 框外必须一起保留的装饰 bbox 列表（问号的上半 / 左下的便签）

    ⛔ `ink_level` 别往上调：波点纸那些灰圆点亮度约 165~185，一放到 175
       整片点阵就被当成「黑线」保留下来 —— 抠完框外会浮着一层脏点
       （第一版就是这个症状）。纯黑框线 / 问号的黑是 < 60，放 120 分得很开。
    ⛔ 最后**必须按 `box ∪ extra` 的矩形把外面砍掉**：作者手绘的框线会在框外
       甩出几十像素的「起笔 / 收笔」毛刺，不砍的话卡片会比框大一圈、框在卡片里
       偏到一边 —— 那正是作者说的「没显示全 / 框歪了」。
    """
    a = load(src)
    h, w, _ = a.shape
    L = lum(a)

    ink = dilate(L < ink_level, 2)          # 线加粗，堵住 JPEG 压出来的缝
    bg = flood_from_border(~ink)
    alpha = np.where(bg, 0.0, 1.0)

    # 兜底：框内矩形里的**亮像素**（白纸）一律补实。只补白、不动黑线 ——
    # 黑线本来就不在灌水结果里（`bg` 是「非黑线」的子集），所以装饰不会被擦。
    bx0, by0, bx1, by1 = box
    ix0, iy0 = max(0, bx0 + inset), max(0, by0 + inset)
    ix1, iy1 = min(w, bx1 - inset), min(h, by1 - inset)
    sub_L = L[iy0:iy1, ix0:ix1]
    sub_a = alpha[iy0:iy1, ix0:ix1]
    sub_a[sub_L > paper_level] = 1.0
    alpha[iy0:iy1, ix0:ix1] = sub_a

    print("   [%s] 灌水背景占 %.1f%%（= 抠掉的波点纸）" % (tag, 100.0 * bg.mean()))

    # 把「框 ∪ 装饰」之外的一切砍掉（手绘毛刺就是这么清掉的）。pad 6px 让框线
    # 自己的锯齿边留着，不然会像被刀切过。
    pad = 6
    keep = np.zeros((h, w), bool)
    keep[max(0, by0 - pad):min(h, by1 + pad), max(0, bx0 - pad):min(w, bx1 + pad)] = True
    for (ex0, ey0, ex1, ey1) in extra:
        keep[max(0, ey0 - pad):min(h, ey1 + pad), max(0, ex0 - pad):min(w, ex1 + pad)] = True
    alpha[~keep] = 0.0

    # 裁到内容 bbox —— 这一步让「卡片矩形 = 白纸黑框」而不是整张照片
    cx0, cy0, cx1, cy1 = bbox_of(keep & (alpha > 0.5))
    m = 2
    cx0, cy0 = max(0, cx0 - m), max(0, cy0 - m)
    cx1, cy1 = min(w, cx1 + m), min(h, cy1 + m)
    out_a = a[cy0:cy1, cx0:cx1]
    out_al = alpha[cy0:cy1, cx0:cx1]

    rgba = np.dstack([out_a, out_al * 255.0]).round().clip(0, 255).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    img.save(os.path.join(OUT, out_name))
    ow, oh = img.size
    print("%-18s %dx%d  (裁掉画布外圈: x<%d / x>%d / y<%d / y>%d)"
          % (out_name, ow, oh, cx0, cx1, cy0, cy1))
    print("   AR = %.6f" % (ow / float(oh)))

    sl, st, sr, sb = safe
    p = ((sl - cx0) / ow, (st - cy0) / oh, (sr - cx0) / ow, (sb - cy0) / oh)
    print("   安全区 px(源图) = %d, %d, %d, %d" % safe)
    print("   * CARD_%s_SAFE = Vector4(%.3f, %.3f, %.3f, %.3f)" % (tag.upper(), *p))
    print("   * 可写区 %d x %d px（占图 %.0f%% x %.0f%%）"
          % (sr - sl, sb - st, 100.0 * (p[2] - p[0]), 100.0 * (p[3] - p[1])))

    # 自验：中灰底（白纸 / 透明都看得清）+ 安全区红框
    chk = Image.new("RGB", (ow, oh), (110, 110, 118))
    chk.paste(img, (0, 0), img)
    d = ImageDraw.Draw(chk)
    d.rectangle([sl - cx0, st - cy0, sr - cx0, sb - cy0], outline=(255, 40, 40), width=3)
    chk.save(os.path.join(CHK, "u02_%s_check.png" % tag))


def main() -> None:
    make_icon()
    icon_compare()
    # ---- 问号线索框：源图 900x1196，黑框外沿 (67,150)-(783,1133) ----
    # 安全区让开框内右上那只大问号（问号最低点 y≈530），上边取 560。
    # extra = 问号探到框外的那半截（量测：框外黑像素「上」组 x[531,814] y[25,149]）。
    make_frame(os.path.join(D2, "07eefd33c558d3b5e1ead0300c2b529a.jpg"),
               "card_clue.png", "clue",
               box=(67, 150, 783, 1133), safe=(103, 560, 747, 1097),
               extra=[(525, 12, 828, 156)])

    # ---- 便签「已记下的东西」框：源图 856x1126，黑框外沿 (87,19)-(802,1047) ----
    # 星压在框内右上（最下到 y≈299），安全区上边取 320 让它。
    # extra = 左下角那张探出框外的便签（量测：框外黑像素「左」组 x[45,80] y[725,983]）。
    make_frame(os.path.join(D2, "678c5d83a3002b4ab7206209b19f9f09.jpg"),
               "card_journal.png", "journal",
               box=(87, 19, 802, 1047), safe=(123, 320, 766, 1011),
               extra=[(35, 620, 350, 1035)])

    print("saved to", OUT)


if __name__ == "__main__":
    main()
