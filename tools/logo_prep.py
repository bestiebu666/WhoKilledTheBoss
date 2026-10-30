"""把作者给的「白底 logo JPG」抠成透明底 PNG，直接能用进 Godot 的 UI。

用法（**用带 PIL 的系统 python，不是 Blender**）：
    "C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe" tools/logo_prep.py <源.jpg> <输出.png>

为什么不能简单地「亮度 > 某阈值 = 透明」：
    这张稿子里**月亮是黑的、星星和咖啡杯是白的、剑刃是白的**。按亮度一刀切，
    杯子、剑刃、白星星会被一起抠掉，画面上就剩几个窟窿。

做法：**从四边往里灌水**（flood fill）。
    背景是一整片连通的白、并且**从画布边缘能走到**；而杯子/剑刃那些白
    都被黑描边圈住了，灌不进去。所以「从边缘可达的白」才是真背景。
    灌完之后再对紧贴背景的一圈像素按亮度给**半透明**，把 JPEG 压出来的
    灰边吃掉，边缘才不会有一圈白毛毛。

参数：
    --thresh  多少亮度以上算「白」（默认 246；JPEG 背景通常 250+）
    --pad     内容四周留多少像素（默认 6）
    --maxw    输出最长边上限（默认 0 = 不缩）
    --preview 出一张「贴在卡片底色上」的预览图，用来肉眼验收
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

# 卡片底色：和 scripts/frontend.gd 的 C_CARD 一致。
CARD = (0xFB, 0xF6, 0xEC)


def flood_from_border(cand: np.ndarray, max_iter: int = 20000) -> np.ndarray:
    """从画布四边往里扩散，返回「和边缘连通的候选背景」掩码。

    纯 numpy 的逐次膨胀：每轮把当前掩码往四邻扩一格，只往 cand 里走。
    cand 是「长得像背景」的像素（近白），所以不会穿进画里。
    """
    seed = np.zeros_like(cand)
    seed[0, :] = cand[0, :]
    seed[-1, :] = cand[-1, :]
    seed[:, 0] = cand[:, 0]
    seed[:, -1] = cand[:, -1]
    for i in range(max_iter):
        nb = np.zeros_like(seed)
        nb[1:, :] |= seed[:-1, :]
        nb[:-1, :] |= seed[1:, :]
        nb[:, 1:] |= seed[:, :-1]
        nb[:, :-1] |= seed[:, 1:]
        new = nb & cand & ~seed
        if not new.any():
            return seed
        seed |= new
    raise SystemExit("[logo] 灌水 %d 轮还没收敛，检查一下 thresh 是不是太低" % max_iter)


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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--thresh", type=float, default=246.0)
    ap.add_argument("--pad", type=int, default=6)
    ap.add_argument("--maxw", type=int, default=0)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()

    im = Image.open(a.src).convert("RGB")
    rgb = np.asarray(im).astype(np.float32)
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    h, w = lum.shape
    print("[logo] 源 %d×%d" % (w, h))

    # 内容边界：亮度低于阈值的像素范围（描边、彩色块都算内容）
    content = lum < a.thresh
    ys, xs = np.where(content)
    if ys.size == 0:
        raise SystemExit("[logo] 整张图都是白的？")
    y0, y1 = max(0, ys.min() - a.pad), min(h - 1, ys.max() + a.pad)
    x0, x1 = max(0, xs.min() - a.pad), min(w - 1, xs.max() + a.pad)
    print("[logo] 内容外框 x %d..%d  y %d..%d  → 裁成 %d×%d" % (x0, x1, y0, y1, x1 - x0 + 1, y1 - y0 + 1))
    rgb = rgb[y0:y1 + 1, x0:x1 + 1]
    lum = lum[y0:y1 + 1, x0:x1 + 1]
    h, w = lum.shape

    # 候选背景 = 三通道都够白（用最小通道，避免偏色的灰被当成背景）
    cand = rgb.min(axis=2) >= a.thresh
    bg = flood_from_border(cand)
    print("[logo] 背景占 %.1f%%（从边缘灌水得到）" % (bg.mean() * 100.0))

    alpha = np.where(bg, 0.0, 1.0)

    # 边缘羽化：紧贴背景的一圈按「有多黑」给半透明，吃掉 JPEG 灰边。
    # 纯白(255)→0，暗到 dark_cut 以下→1。
    dark_cut = a.thresh - 60.0
    band = dilate(bg, 2) & ~bg
    soft = np.clip((a.thresh - lum) / (a.thresh - dark_cut), 0.0, 1.0)
    alpha[band] = np.minimum(alpha[band], soft[band])
    # 半透明像素的 RGB 是「黑描边 + 白底」混出来的，直接留着会在浅底上发灰，
    # 所以把它们往最近的实色推一把（gamma 提对比），视觉上更干净。
    print("[logo] 边缘半透明像素 %d 个" % band.sum())

    out = np.dstack([rgb, alpha * 255.0]).round().clip(0, 255).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")

    if a.maxw and img.width > a.maxw:
        k = a.maxw / img.width
        img = img.resize((a.maxw, max(1, int(round(img.height * k)))), Image.LANCZOS)
        print("[logo] 缩到 %d×%d" % img.size)

    os.makedirs(os.path.dirname(a.dst), exist_ok=True)
    img.save(a.dst)
    print("[logo] 写出 %s  %dx%d  %.0f KB  透明像素 %.1f%%"
          % (a.dst, img.width, img.height, os.path.getsize(a.dst) / 1024.0,
             (np.asarray(img)[:, :, 3] < 128).mean() * 100.0))

    if a.preview:
        card = Image.new("RGBA", img.size, CARD + (255,))
        card.alpha_composite(img)
        card.convert("RGB").save(a.preview)
        print("[logo] 预览 %s（贴在卡片底色 #FBF6EC 上）" % a.preview)


if __name__ == "__main__":
    sys.exit(main())
