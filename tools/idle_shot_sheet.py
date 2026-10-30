"""把 scripts/_idle_shot.gd 拍出来的 12 张头顶台词图拼成一张对照表。

    python tools/idle_shot_sheet.py

输出 shots/头顶台词_对照表.png（3 行 = 3 轮，4 列 = 凤凰男 / 实习1号 / 老板 / 总监）。
用系统 Python（带 Pillow）：C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

SHOTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shots")
ORDER = ["凤凰男", "实习1号", "老板", "总监"]
COLS, ROWS = 4, 3
CELL_W = 470          # 每格宽（像素）
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


def main():
    # 先按第一张图量出「一格的原始尺寸」，等比缩到 CELL_W
    first = f"{SHOTS}/头顶台词_R1_{ORDER[0]}.png"
    if not os.path.exists(first):
        print(f"[ERR] 找不到 {first} —— 先跑 res://scenes/_idleshot.tscn")
        return 1
    probe = Image.open(first)
    scale = CELL_W / probe.width
    cell_h = int(round(probe.height * scale))

    W = COLS * CELL_W + (COLS + 1) * GAP
    H = ROWS * (cell_h + LABEL_H) + (ROWS + 1) * GAP
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    f_label = load_font(22)
    f_note = load_font(20)

    missing = []
    for r in range(ROWS):
        for c in range(COLS):
            name = f"{SHOTS}/头顶台词_R{r + 1}_{ORDER[c]}.png"
            x = GAP + c * (CELL_W + GAP)
            y = GAP + r * (cell_h + LABEL_H + GAP)
            if not os.path.exists(name):
                missing.append(name)
                d.rectangle([x, y, x + CELL_W, y + cell_h + LABEL_H], outline=(200, 60, 60), width=2)
                d.text((x + 8, y + 8), "缺图", font=f_label, fill=(200, 60, 60))
                continue
            im = Image.open(name).convert("RGB").resize((CELL_W, cell_h), Image.LANCZOS)
            sheet.paste(im, (x, y + LABEL_H))
            d.rectangle([x, y, x + CELL_W, y + cell_h + LABEL_H],
                        outline=(190, 186, 178), width=1)
            d.text((x + 8, y + LABEL_H // 2 - 12), f"第 {r + 1} 轮 · {ORDER[c]}",
                   font=f_label, fill=FG)

    out = f"{SHOTS}/头顶台词_对照表.png"
    sheet.save(out)
    print(f"[ok] {out}  ({W}×{H})")
    if missing:
        print("[warn] 缺这几张：" + ", ".join(os.path.basename(m) for m in missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
