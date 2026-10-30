# -*- coding: utf-8 -*-
"""作者新给的「手绘波普」框 -> Godot 可直接用的 RGBA PNG。

沿用 tools/ui_card_prep.py 的判据（从画布四边灌水抠背景），针对本批新素材增强两处：

  ① **按连通域大小滤噪**（MIN_BLOB）。新素材是 AI 生成 JPEG，纯黑像素里混着
     大量细小噪点，右下角还有「豆包AI生成」水印（笔画细、被拆成许多小块）。
     只保留 >= MIN_BLOB 像素的连通域 —— 水印与噪点一并清掉，框和装饰全部保住。
     ⛔ 这一步必须早于「灌水」，也必须早于「黑线保持实心」—— 否则水印的暗像素
        会被当成黑线留在 alpha 里，最右/最下就被水印顶到画布边缘（实测踩过）。
  ② **形态学闭运算封缝**。手绘框线是分段画的：问号那张的框有 ~10px 缺口，
     直接灌水会从缺口漏进去、框内白纸被当背景抠掉（实测 enclosed 仅 0.1%）。
     `binary_closing(disk(seal))` 先封缺口（问号框 seal=6、星星框缝小 seal=2）。

输出 assets/textures/ui/{card_clue,card_journal}.png，并打印 AR 与安全区比例，
hud.gd 的 CARD_*_AR / CARD_*_SAFE 直接抄。

用法：
    D:/Python312/python.exe tools/ui_card_reprep.py
"""

import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "_ui_src")
OUT = os.path.join(ROOT, "assets", "textures", "ui")
CHK = r"D:\WorkBuddyWorkspace\Claw\_godot_import"
LUM = np.array([0.2126, 0.7152, 0.0722], np.float32)

INK_LEVEL = 120.0     # 纯黑（框线 / 问号 / 星）的亮度上限；波点纸的灰点约 139~185，分得开
MIN_BLOB = 1000       # 连通域小于此值 = 噪点 / 水印碎片，丢弃


def disk(r: int) -> np.ndarray:
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return (x * x + y * y) <= r * r


def box3(m: np.ndarray) -> np.ndarray:
    h, w = m.shape
    s = np.zeros((h + 2, w + 2), np.float32)
    s[1:-1, 1:-1] = m.astype(np.float32)
    acc = np.zeros((h, w), np.float32)
    for dy in range(3):
        for dx in range(3):
            acc += s[dy:dy + h, dx:dx + w]
    return acc / 9.0


def bbox(mask: np.ndarray):
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def drop_small(mask: np.ndarray, min_size: int) -> np.ndarray:
    lbl, n = ndimage.label(mask)
    if n == 0:
        return mask
    sizes = ndimage.sum(np.ones_like(lbl), lbl, index=range(1, n + 1))
    return np.isin(lbl, [i + 1 for i in range(n) if sizes[i] >= min_size])


def process(src_name: str, out_name: str, tag: str, seal: int) -> None:
    a = np.asarray(Image.open(os.path.join(SRC, src_name)).convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    L = a @ LUM

    ink = drop_small(L < INK_LEVEL, MIN_BLOB)                                  # ① 去噪 / 去水印
    sealed = ndimage.binary_closing(ndimage.binary_dilation(ink, iterations=2), structure=disk(seal))  # ② 封缝

    lbl, n = ndimage.label(~sealed)
    border = set(lbl[0, :].tolist()) | set(lbl[-1, :].tolist()) | set(lbl[:, 0].tolist()) | set(lbl[:, -1].tolist())
    border.discard(0)
    bg = np.isin(lbl, list(border))
    alpha = (~bg).astype(np.float32)

    # 框内最大连通白区 = 框的内腔，用来定位框、也算装饰检出区域的上界
    enc_lbl, enc_n = ndimage.label(~bg & ~sealed)
    interior = None
    if enc_n:
        sizes = ndimage.sum(np.ones_like(enc_lbl), enc_lbl, index=range(1, enc_n + 1))
        interior = bbox(enc_lbl == int(np.argmax(sizes)) + 1)

    alpha = box3(alpha)
    alpha[ink] = 1.0                                                          # 真黑线保持实心（只认真 ink）

    # 裁到内容 bbox —— 卡片矩形 = 白纸黑框（+ 探出框外的装饰）
    x0, y0, x1, y1 = bbox(alpha > 0.5)
    m = 2
    x0, y0 = max(0, x0 - m), max(0, y0 - m)
    x1, y1 = min(w, x1 + m), min(h, y1 + m)
    ow, oh = x1 - x0, y1 - y0

    rgba = np.dstack([np.clip(a[y0:y1, x0:x1], 0, 255), alpha[y0:y1, x0:x1] * 255.0]).round().clip(0, 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, out_name))
    print("%-18s %dx%d  AR=%.6f   (裁剪 x[%d,%d) y[%d,%d))" % (out_name, ow, oh, ow / float(oh), x0, x1, y0, y1))
    print("   框内腔 bbox = %s" % (interior,))
    print("   灌水背景占 %.1f%%" % (100.0 * bg.mean()))

    # ---- 安全区：让开框内右上的装饰（星 / 问号）----
    # ⛔ 左右下三边必须取自**框内腔**（interior），不能取最外侧 ink bbox ——
    #    ink bbox 含探出框外的手绘毛刺，照它算出来的安全区会盖到框线上。
    # 装饰最下沿 = 「框内腔左半到腔右界再往里 90px + 上 70%」区域里最靠下的黑像素。
    #    再往里收 90px 是为了排掉**框自己的内层描边**（实测不排会把 y 顶到 1193）。
    pad = 28
    ix0, iy0, ix1, iy1 = interior if interior else (0, 0, w, h)
    reg_x1 = max(ix0 + 10, ix1 - 90)
    reg = np.zeros((h, w), bool)
    reg[0:int(h * 0.70), int(w * 0.50):reg_x1] = True
    ys, _ = np.where(ink & reg)
    deco_bottom = int(ys.max()) if len(ys) else 0
    print("   装饰最低点 y=%d（检出区 x[%d,%d)）" % (deco_bottom, int(w * 0.50), reg_x1))

    # 左右各让开 PAD_X：手绘框有**内外两层描边**，只按腔体算边距文字会压到内层线。
    PAD_X, PAD_TOP, PAD_BOT, PAD_MIN_TOP = 58, 30, 45, 58
    sl = ix0 + PAD_X
    sr = ix1 - PAD_X
    sb = iy1 - PAD_BOT
    st = max(iy0 + PAD_MIN_TOP, deco_bottom + PAD_TOP)
    p = ((sl - x0) / ow, (st - y0) / oh, (sr - x0) / ow, (sb - y0) / oh)
    print("   * CARD_%s_AR = %.6f" % (tag.upper(), ow / float(oh)))
    print("   * CARD_%s_SAFE = Vector4(%.3f, %.3f, %.3f, %.3f)" % (tag.upper(), *p))
    print("   * 可写区 %.0f%% x %.0f%%" % (100.0 * (p[2] - p[0]), 100.0 * (p[3] - p[1])))

    # ---- 自验图：中灰底 + 安全区红框 + 裁剪蓝框 ----
    chk = Image.new("RGB", (w, h), (110, 110, 118))
    chk.paste(Image.fromarray(rgba, "RGBA"), (x0, y0), Image.fromarray(rgba, "RGBA"))
    d = ImageDraw.Draw(chk)
    d.rectangle([sl, st, sr, sb], outline=(255, 40, 40), width=4)
    chk.save(os.path.join(CHK, "_chk_%s.png" % tag))
    print("   自验图 -> %s\\_chk_%s.png" % (CHK, tag))
    print()


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    process("card_clue_src.jpg", "card_clue.png", "clue", seal=6)
    process("card_journal_src.jpg", "card_journal.png", "journal", seal=2)
    print("saved to", OUT)


if __name__ == "__main__":
    main()
