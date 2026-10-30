"""把 scripts/_front_shot.gd 拍出来的「前情提要逐段图」拼成一张总表。

    python tools/intro_shot_sheet.py

输入  shots/前情提要_00_标题.png、shots/前情提要_01..NN.png、shots/前情提要_99_选幕.png
输出  shots/前情提要_总表.png（标题页 + 每一段 + 选幕页，按播放顺序从左到右、从上到下）

段数不写死：从 data/intro.json 现读 recap 有几段，用来标每格是「前情提要」还是「引导剧情」。
用系统 Python（带 Pillow）：C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe
"""

import glob
import io
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = ROOT + "/shots"
INTRO = ROOT + "/data/intro.json"

COLS = 5
CELL_W = 400          # 每格宽（像素）
LABEL_H = 40          # 每格顶部标签带的高度
GAP = 8
BG = (245, 243, 238)
FG = (27, 27, 27)

FONT_CANDIDATES = [
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/msyhbd.ttc",
    "C:/Windows/Fonts/simhei.ttf",
]


def load_font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default()


def recap_count():
    """data/intro.json 里 recap 有几段非空正文 —— 用来分「前情提要 / 引导剧情」。"""
    try:
        d = json.load(io.open(INTRO, encoding="utf-8"))
    except (OSError, ValueError):
        return -1
    return sum(1 for t in d.get("recap", []) if str(t).strip() != "")


def collect():
    """按播放顺序收图：标题 → 01..NN（按数字排，不是按字符串）→ 选幕。"""
    items = []
    head = f"{SHOTS}/前情提要_00_标题.png"
    if os.path.exists(head):
        items.append((head, "标题页"))
    numbered = glob.glob(f"{SHOTS}/前情提要_[0-9][0-9].png")
    numbered = [p for p in numbered if not os.path.basename(p).startswith("前情提要_00_")
                and not os.path.basename(p).startswith("前情提要_99_")]
    numbered.sort(key=lambda p: int(re.search(r"_(\d+)\.png$", p).group(1)))
    items.extend((p, "") for p in numbered)
    tail = f"{SHOTS}/前情提要_99_选幕.png"
    if os.path.exists(tail):
        items.append((tail, "选幕页"))
    return items


def main():
    items = collect()
    if not items:
        print(f"[ERR] {SHOTS}/前情提要_*.png 一张都没有 —— 先跑 res://scenes/_frontshot.tscn")
        return 1

    probe = Image.open(items[0][0])
    scale = CELL_W / probe.width
    cell_h = int(round(probe.height * scale))

    rows = (len(items) + COLS - 1) // COLS
    W = COLS * CELL_W + (COLS + 1) * GAP
    H = rows * (cell_h + LABEL_H) + (rows + 1) * GAP
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    f_label = load_font(19)

    n_recap = recap_count()
    seq = 0     # 正文段号（跳过标题页 / 选幕页）

    for idx, (path, special) in enumerate(items):
        r, c = divmod(idx, COLS)
        x = GAP + c * (CELL_W + GAP)
        y = GAP + r * (cell_h + LABEL_H + GAP)

        if special:
            tag = special
        else:
            seq += 1
            if n_recap < 0:
                tag = f"第 {seq} 段"
            elif seq <= n_recap:
                tag = f"第 {seq} 段 · 前情提要"
            else:
                tag = f"第 {seq} 段 · 引导剧情"

        im = Image.open(path).convert("RGB").resize((CELL_W, cell_h), Image.LANCZOS)
        sheet.paste(im, (x, y + LABEL_H))
        d.rectangle([x, y, x + CELL_W, y + cell_h + LABEL_H],
                    outline=(190, 186, 178), width=1)
        d.text((x + 8, y + LABEL_H // 2 - 11), tag, font=f_label, fill=FG)

    out = f"{SHOTS}/前情提要_总表.png"
    sheet.save(out)
    print(f"[ok] {out}  ({W}×{H})  共 {len(items)} 格"
          f"（正文 {seq} 段：前情提要 {n_recap} + 引导剧情 {seq - n_recap}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
