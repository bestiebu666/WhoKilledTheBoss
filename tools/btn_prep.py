"""把作者给的「白底手绘按钮图」抠成透明底 PNG，并且**统一到同一块画布**上，
让两个按钮的黑色横条**大小完全一致、位置严格对齐**。

用法（**用带 PIL 的系统 python，不是 Blender**）：
    "C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe" tools/btn_prep.py

为什么不能直接「亮度 > 阈值 = 透明」：
    这两张稿子的图案是**黑描边 + 白填充**（横条内部就是白的）。按亮度一刀切，
    横条内部的白会被一起抠掉，浅底上就只剩一个空框、完全不是作者画的样子。
    做法和 logo_prep.py 一样：**从画布四边往里灌水**（flood fill）。
    背景是一整片连通的白、从边缘走得到；横条内部的白被黑描边圈住灌不进去，
    于是「从边缘可达的白」才是真背景。

为什么要"同一块画布"：
    两张图是 AI 分别生成的，同一个横条在两张图里的**像素尺寸不一样**
    （实测 前情提要 726px 宽 / 开始游戏 506px 宽，差 1.43 倍），四周的装饰
    （猫、剑、火花）伸出去的范围也不一样。直接各裁各的摆上去，两条横条会一个
    大一个小、还左右错开。这里的做法是：
        1. 量出每张图的「黑条」矩形；
        2. 按黑条等比缩放到统一的 BAR_TARGET 宽度 → 两条黑条一样大；
        3. 算出各图内容相对**黑条中心**的外扩量，两个取大者作为公共画布的半宽/半高；
        4. 把两张图都贴进这块画布，且**黑条中心压在同一像素上** → 严格对齐。
    两块画布尺寸相同、黑条位置相同，于是「大小一致对齐」是被构造出来的，不是估的。

⛔ 图片源在微信的 RWTemp 下，**会被清理**。要长期复现，把原图另存到项目外。
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

# 作者发来的原图（微信收图目录，会被清理 —— 只当"当时那份"的出处记录）
SRC_DIR = r"D:\xwechat_files\wxid_6z2g8f1replf22_4b59\temp\RWTemp\2026-10\4f1a310d00d6c0add6425a1a5ee1e219"

# 页面底色，和 scripts/frontend.gd 的 _page 默认底色一致（出预览用）
PAGE = (0xED, 0xE7, 0xDC)

# 统一的黑条目标宽度（源像素）。600 让两张图都只是轻微重采样：
# 前情提要 726→600（缩 0.83），开始游戏 506→600（放 1.19）。
BAR_TARGET = 600.0

# window = 在这块窗口里找内容（**故意排除了右下角的水印**，水印都在这之外）
# bar    = 目视 + 剖面量出来的「黑色横条」外接矩形 (x0, y0, x1, y1)，闭区间
SPEC = [
    dict(
        key="recap",
        out="assets/textures/ui/btn_recap.png",
        src=os.path.join(SRC_DIR, "1728fd5b541491b4799ad1c4dc39d13a.jpg"),
        window=(170, 660, 1100, 1180),
        bar=(247, 828, 972, 1071),
        note="「前情提要」——横条 + 右上角猫脸 + 左右火花。棒体 726×244 px。",
    ),
    dict(
        key="start",
        out="assets/textures/ui/btn_start.png",
        src=os.path.join(SRC_DIR, "7679eb506d75ddbd0deb609571448c6c.jpg"),
        window=(230, 400, 995, 850),
        bar=(278, 556, 789, 728),
        note="「开始游戏」——横条 + 斜插进来的剑 + 火花。棒体 512×173 px。"
             "棒体右端被剑挡住，靠**宽高比和另一张一致**（2.96 vs 2.98）反推右边界。",
    ),
]


def flood_from_border(cand: np.ndarray, max_iter: int = 20000) -> np.ndarray:
    """从画布四边往里扩散，返回「和边缘连通、且长得像背景」的掩码。

    纯 numpy 逐次膨胀：每轮把当前掩码往四邻扩一格，只往 cand 里走。
    cand 是「近白的像素」，所以灌不进被黑描边圈起来的横条内部。
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
    raise SystemExit("[btn] 灌水 %d 轮还没收敛 —— thresh 是不是太低了" % max_iter)


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


def cut_one(item: dict, thresh: float, pad: int) -> dict:
    """抠一张：裁到内容框 → 灌水去底 → 返回（未缩放的）RGBA 与棒体中心。"""
    im = Image.open(item["src"]).convert("RGB")
    rgb = np.asarray(im).astype(np.float32)
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)

    x0, y0, x1, y1 = item["window"]
    win = lum[y0:y1 + 1, x0:x1 + 1]
    m = win < thresh
    if not m.any():
        raise SystemExit("[btn] %s 窗口里一点内容都没有" % item["key"])
    ys, xs = np.where(m)
    cx0, cx1 = x0 + xs.min() - pad, x0 + xs.max() + pad
    cy0, cy1 = y0 + ys.min() - pad, y0 + ys.max() + pad
    h, w = lum.shape
    cx0, cy0 = max(0, cx0), max(0, cy0)
    cx1, cy1 = min(w - 1, cx1), min(h - 1, cy1)
    print("[btn] %-6s 内容外框 x %d..%d y %d..%d → 裁成 %d×%d"
          % (item["key"], cx0 + pad, cx1 - pad, cy0 + pad, cy1 - pad,
             cx1 - cx0 + 1, cy1 - cy0 + 1))

    rgb = rgb[cy0:cy1 + 1, cx0:cx1 + 1]
    lum = lum[cy0:cy1 + 1, cx0:cx1 + 1]

    # 候选背景 = 三通道都够白（用最小通道，避免偏色的灰被判成背景）
    cand = rgb.min(axis=2) >= thresh
    bg = flood_from_border(cand)
    alpha = np.where(bg, 0.0, 1.0)
    print("[btn] %-6s 背景占 %.1f%%（从边缘灌水得到，横条内部的白被保住）"
          % (item["key"], bg.mean() * 100.0))

    # 边缘羽化：紧贴背景的一圈按「有多黑」给半透明，吃掉 JPEG 压出来的灰边。
    dark_cut = thresh - 60.0
    band = dilate(bg, 2) & ~bg
    soft = np.clip((thresh - lum) / (thresh - dark_cut), 0.0, 1.0)
    alpha[band] = np.minimum(alpha[band], soft[band])

    bx0, by0, bx1, by1 = item["bar"]
    bar_w = float(bx1 - bx0 + 1)
    bar_h = float(by1 - by0 + 1)
    bcx = (bx0 + bx1) * 0.5 - cx0
    bcy = (by0 + by1) * 0.5 - cy0
    print("[btn] %-6s 黑条 %.0f×%.0f px（宽高比 %.3f），条心在裁图内的 (%.1f, %.1f)"
          % (item["key"], bar_w, bar_h, bar_w / bar_h, bcx, bcy))

    rgba = np.dstack([rgb, alpha * 255.0]).round().clip(0, 255).astype(np.uint8)
    return dict(item=item, rgba=Image.fromarray(rgba, "RGBA"),
                bar_w=bar_w, bar_h=bar_h, bcx=bcx, bcy=bcy)


def resize_premul(img: Image.Image, size) -> Image.Image:
    """等比缩放 RGBA。**先做预乘**再缩，否则透明区的白会被插值混进描边、边界发白。"""
    a = np.asarray(img).astype(np.float32)
    al = a[:, :, 3:4] / 255.0
    pm = np.dstack([a[:, :, :3] * al, a[:, :, 3]])
    sm = Image.fromarray(pm.round().clip(0, 255).astype(np.uint8), "RGBA")
    sm = sm.resize(size, Image.LANCZOS)
    b = np.asarray(sm).astype(np.float32)
    al2 = b[:, :, 3:4] / 255.0
    rgb2 = np.where(al2 > 0.004, b[:, :, :3] / np.maximum(al2, 1e-6), 255.0)
    return Image.fromarray(
        np.dstack([rgb2, b[:, :, 3]]).round().clip(0, 255).astype(np.uint8), "RGBA")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--thresh", type=float, default=246.0)
    ap.add_argument("--pad", type=int, default=4)
    ap.add_argument("--bar-target", type=float, default=BAR_TARGET)
    ap.add_argument("--preview", default="docs/_btn_preview.png")
    a = ap.parse_args()

    cuts = [cut_one(it, a.thresh, a.pad) for it in SPEC]

    # 等比缩放到统一的黑条宽度，并算出内容相对**条心**的外扩量
    print()
    for c in cuts:
        k = a.bar_target / c["bar_w"]
        c["k"] = k
        c["size"] = (max(1, int(round(c["rgba"].width * k))),
                     max(1, int(round(c["rgba"].height * k))))
        c["bcx_s"] = c["bcx"] * k
        c["bcy_s"] = c["bcy"] * k
        c["left"] = c["bcx_s"]
        c["right"] = c["size"][0] - c["bcx_s"]
        c["top"] = c["bcy_s"]
        c["bottom"] = c["size"][1] - c["bcy_s"]
        print("[btn] %-6s ×%.3f → %d×%d，条心 (%.1f, %.1f)，外扩 左%.0f 右%.0f 上%.0f 下%.0f"
              % (c["item"]["key"], k, c["size"][0], c["size"][1],
                 c["bcx_s"], c["bcy_s"], c["left"], c["right"], c["top"], c["bottom"]))

    # 画布怎么定，**横竖不一样** —— 这是「大小一致对齐」的关键：
    #   横向：两图**共用一条画布**，以条心为中心、左右各取两图的最大外扩。
    #         于是两张图宽度相同、黑条都落在画布正中 → 居中摆上去就左右对齐了。
    #   纵向：**各图自己做紧**（裁到内容边界就停，只留 pad）。
    #         ⛔ 别纵向也取公共高度！两张图伸出去的高度差得多（剑往上伸得远、猫伸得近），
    #         取公共高度会在矮的那张底下留一大块透明空隙 —— 那块空隙照样占布局高度，
    #         两个按钮之间就被撑开一条大缝（实测缝宽变成参考图的 4 倍）。
    #         对齐靠的是横向，纵向只要紧。
    half_w = int(np.ceil(max(max(c["left"], c["right"]) for c in cuts)))

    out_imgs = {}
    for c in cuts:
        small = resize_premul(c["rgba"], c["size"])
        canvas = (half_w * 2, c["size"][1])
        px = int(round(half_w - c["bcx_s"]))
        c["px"], c["py"] = px, 0
        c["canvas"] = canvas
        plate = Image.new("RGBA", canvas, (0, 0, 0, 0))
        plate.alpha_composite(small, (px, 0))
        dst = c["item"]["out"]
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        plate.save(dst)
        out_imgs[c["item"]["key"]] = plate
        print("[btn] 写出 %-34s %dx%d  %.0f KB  透明 %.1f%%"
              % (dst, plate.width, plate.height,
                 os.path.getsize(dst) / 1024.0,
                 (np.asarray(plate)[:, :, 3] < 128).mean() * 100.0))
    print("[btn] 两张图共用同一条横向画布，宽 %d（黑条中心在 x=%d）" % (half_w * 2, half_w))

    # ---- 自检 ----
    # ⚠ 不要指望"再去 PNG 里量一遍黑条宽度"来验收：黑条右端被剑/火花压着，
    #   用 alpha 量出来的宽度会虚高 10~12%（实测 recap 617、start 674）。真正靠得住的
    #   是**构造不变量** —— 两张图共用同一条横向画布、条心按定义压在画布横向正中。
    print()
    ok = True
    for c in cuts:
        plate = np.asarray(out_imgs[c["item"]["key"]])[:, :, 3] > 128
        # 报一个"黑条左端外侧实心边"的位置（用连续 25 列都过半实当作黑条本体，
        # 这样细的装饰弧线不会被算进来）—— 只报数、不判罚。
        bar_h_px = a.bar_target * c["bar_h"] / c["bar_w"]
        yc = int(round(c["bcy_s"]))
        y0 = max(0, int(round(yc - bar_h_px / 2)))
        y1 = min(plate.shape[0] - 1, int(round(yc + bar_h_px / 2)))
        frac = plate[y0:y1 + 1].mean(axis=0) > 0.5
        edges = np.where(np.convolve(frac.astype(np.int32), np.ones(25, np.int32), "valid") == 25)[0]
        left = int(edges.min()) if edges.size else -1
        off = abs(c["px"] + c["bcx_s"] - half_w)
        if off > 1.0:
            ok = False
        print("[chk] %-6s 画布 %dx%d  黑条 %.0f×%.0f → 画布内宽 %.0f（两图一致）；"
              "左端实心边 x=%d（横向画布中 %d，差 %+d）；条心横向偏移 %.2f px"
              % (c["item"]["key"], c["canvas"][0], c["canvas"][1], c["bar_w"], c["bar_h"],
                 a.bar_target, left, half_w, left - half_w, off))
    same_w = len({im.size[0] for im in out_imgs.values()}) == 1
    print("[chk] 两张图共用同一条横向画布（宽 %d）：%s"
          % (half_w * 2, same_w))
    print("[chk] 结论：%s"
          % ("OK —— 黑条一样大、横向条心压在同一列上（纵向各自做紧，不留空缝）"
             if (ok and same_w) else "不通过，看上面的偏差"))

    # ---- 预览：按 data/frontend.json 里的**真实数字**排一遍（免得预览和游戏里两套数字对不上）----
    if a.preview:
        t = json.load(open("data/frontend.json", encoding="utf-8"))["title"]
        logo_w = float(t.get("logo_w", 680))
        btn_w = float(t.get("btn_w", 300))
        gap_logo = float(t.get("logo_gap", 62))
        gap_btn = float(t.get("btn_gap", 14))
        lift = float(t.get("lift", 0))
        W, H = 1600, 900
        pg = Image.new("RGBA", (W, H), PAGE + (255,))
        items = []
        lg = Image.open(str(t["logo"]).replace("res://", "")).convert("RGBA")
        lh = int(round(logo_w * lg.height / lg.width))
        items.append((lg.resize((int(round(logo_w)), lh), Image.LANCZOS), gap_logo))
        for key in ("start", "recap"):
            b = out_imgs[key]
            bw = int(round(btn_w))
            bh = int(round(btn_w * b.height / b.width))
            items.append((b.resize((bw, bh), Image.LANCZOS), gap_btn))
        gaps = [g for _, g in items[1:]]
        total = sum(im.height for im, _ in items) + sum(gaps) + lift
        y = (H - total) // 2
        for i, (im, _) in enumerate(items):
            pg.alpha_composite(im, ((W - im.width) // 2, int(round(y))))
            y += im.height + (gaps[i] if i < len(gaps) else 0)
        pg.convert("RGB").save(a.preview)
        print("[btn] 预览 %s（%d×%d，数字直接读 data/frontend.json）" % (a.preview, W, H))


if __name__ == "__main__":
    sys.exit(main())
