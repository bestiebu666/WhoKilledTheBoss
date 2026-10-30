# -*- coding: utf-8 -*-
"""生成《设计部 · 文案填充表》.xlsx —— 作者填完之后直接发回来，把内容写进 data/act1.json。

为什么要有这张表：
    文案全部住在 data/act1.json 里，但 JSON 让作者手改很容易踩格式的坑
    （少个逗号、引号、换行符）。所以做一张 Excel：**一列一个字段**，
    作者只填文字，回给我之后按「轮次 + 位置/题号」对号入座写回 JSON。

表的结构（5 张 sheet）：
    ① 说明        —— 怎么填、哪些列别动
    ② 可探索点    —— **总表**：这一共有哪些可探索的地方（objects.json 的 spots +
                      room.json 里带 explore 的家具 + 4 个小人），纯参考、不用填。作者照着它决定每轮用哪几个。
    ③ 探索点文案  —— 3 轮 × **全部**可探索点：名称 / 提示语 / 三条观察句 / 线索结论
    ④ 判断题      —— 题干 / 最多 3 个选项 / 哪个对 / 答对答错反馈
    ⑤ 轮末过场    —— 每轮结束那一段

⭐ 「每一轮的探索点可以不一样」怎么填：
    ③ 那张表里每一轮都**把全部可探索点列一遍**。这一轮不想用的位置，
    把那一行的**文字列整行留空** —— 我写回 JSON 时会把这一行从这一轮删掉，
    表现就是「这一轮它头顶没有感叹号、也不进进度分母」。

⭐ 2026-10-06 的流程变化（和上一版表不同的地方）：
    · **小人也是可探索点** —— 每轮的 `spots` 里现在同时有 4 个小人的 id；
    · **看完本轮全部可探索点 → 自动一道一道弹判断题**（不再需要「找小人说话」）；
    · 看过的位置会把 `clue`（线索结论）**记到右边「已记下的东西」**。

用法：
    "C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe" tools/make_fill_sheet.py
"""

import io
import json
import os

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT = os.path.join(ROOT, "data", "act1.json")
OBJ = os.path.join(ROOT, "data", "objects.json")
ROOM = os.path.join(ROOT, "data", "room.json")
OUT = os.path.join(ROOT, "docs", "设计部_文案填充表.xlsx")

HEAD_FILL = PatternFill("solid", fgColor="4B4A47")
HEAD_FONT = Font(color="FFFFFF", bold=True, size=11)
TODO_FILL = PatternFill("solid", fgColor="FFF3CD")     # 还没填的格子
FILLED_FILL = PatternFill("solid", fgColor="F2F7F2")   # 已经有内容的格子
NPC_FILL = PatternFill("solid", fgColor="E7F0F7")      # 「这是个小人」的行标
LOCK_FONT = Font(color="888780", size=10)              # 「别改」的列
THIN = Side(style="thin", color="D8D5CC")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP = Alignment(wrap_text=True, vertical="top")

## 小人（NPC）的 id -> 中文名。小人没有 objects.json 的 spots 条目，名字要单独取。
NPC_CN = {"feng": "凤凰男", "intern1": "实习 1 号", "boss": "老板",
          "director": "外聘设计总监", "any": "随便谁"}

## 「这个可探索点在哪儿」—— 给作者的定位说明（纯参考列，不写回 JSON）。
WHERE = {
    "feng_desk": "三人办公桌 · 最西边那个位子（桌面）",
    "empty_seat": "三人办公桌 · 中间那个空位（桌面）",
    "intern1_desk": "三人办公桌 · 最东边那个位子（桌面）",
    "leader_desk": "背靠背长桌 · 南排西边那格（外聘设计总监的位子）",
    "boss_desk": "背靠背长桌 · 南排东边那格（部长的位子）",
    "hr_cabinet": "西墙靠北 · 双开门档案柜（门朝屋里）",
    "pantry": "屋子中间偏东 · 长条吧台的台面",
    "bulletin": "西墙偏南 · 贴墙的公告栏 / 考勤板",
    "mannequin_01": "★陈列角 · 1 号人台（黑色长外套）",
    "mannequin_02": "★陈列角 · 2 号人台（灰绿斜襟长裙）",
    "mannequin_03": "★陈列角 · 3 号人台（黑皮夹克短裙）",
    "mannequin_04": "★陈列角 · 4 号人台（紫黑哥特礼服）",
    "watercooler": "东南角 · 饮水机（调高过、偏白）",
    "moneytree_01": "东墙 · 发财树 1 号（窗边）",
    "moneytree_02": "西墙 · 发财树 2 号（门边）",
    "sculpture": "东北角 · 黑立像雕塑（3.25 米高）",
    "meetingtable": "中间偏西 · 长条会议桌（4.8 米，桌旗）",
    "sofa": "东南角 · 沙发（老板坐在这）",
    "feng": "★小人 · 站在自己工位前面",
    "intern1": "★小人 · 站在自己工位前面",
    "boss": "★小人 · 东南角的沙发上",
    "director": "★小人 · 站在服装展架那块空地上",
}


def load(path):
    return json.load(io.open(path, encoding="utf-8"))


## ★ 占位稿的判据：文案里带「待填」就是还没写。
## ⚠ 这里**不分轮次**一律洗空 —— 新版表里连第 1 轮的 NPC 也还是占位稿
## （家具那 6 条是作者已经给的，NPC 那 4 条是这一版新加的、还没写）。
## 要是按轮次洗，第 1 轮的「（第 1 轮 · 待填）」会被当成真内容倒进表里，
## 作者会以为已经填过了。
def clean(v, no=0):
    s = str(v) if v is not None else ""
    return "" if "待填" in s else s


def style_header(ws, row, widths):
    for i, w in enumerate(widths, start=1):
        c = ws.cell(row=row, column=i)
        c.fill = HEAD_FILL
        c.font = HEAD_FONT
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        c.border = BORDER
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = ws.cell(row=row + 1, column=1)


def is_npc(sid):
    return sid in NPC_CN and sid != "any"


def main():
    act = load(ACT)
    obj = load(OBJ)
    room = load(ROOM)
    geo = {s["id"]: s for s in obj["spots"]}
    npc = {n["id"]: n for n in obj["npcs"]}
    # 可探索家具（room.json 里带 explore 字段的 prop）—— 名称从 explore_name / name 取
    expl = {str(p.get("explore")): p for p in room.get("props", [])
            if str(p.get("explore", ""))}
    rounds = act["rounds"]

    def name_of(sid):
        if sid in NPC_CN and sid != "any":
            return NPC_CN[sid]
        if sid in geo:
            return geo[sid].get("name", "")
        if sid in expl:
            return expl[sid].get("explore_name", expl[sid].get("name", ""))
        return ""

    # 总表 = 场景里**所有**可探索点：objects.json 的 spots + room.json 里带 explore 的家具 + 小人。
    # ⚠ 顺序：先把第 1 轮用到的排前面（那是作者当前的关注顺序），剩下的补在后面。
    # ⛔ **不能用「第 1 轮的 spots」当全集** —— 那样没被第 1 轮用到的位置在表里根本不会出现，
    #    作者想给某一轮加一个位置就只能自己手插行。2026-10-06 那次就是这么出岔子的：
    #    作者在表里手写了 boss_desk / leader_desk 两行（场景里当时还没有这两个位置），
    #    写回时被安全网跳过，整段文案没能进游戏。
    all_ids = []
    for rd in rounds[:1]:
        for sp in rd.get("spots", []):
            if sp["id"] not in all_ids:
                all_ids.append(sp["id"])
    for sid in (list(geo)
                + [str(p.get("explore")) for p in room.get("props", []) if str(p.get("explore", ""))]
                + list(npc)):
        if sid and sid not in all_ids:
            all_ids.append(sid)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    wb = Workbook()

    # ------------------------------------------------------------ ① 说明
    ws = wb.active
    ws.title = "说明"
    ws.column_dimensions["A"].width = 18
    ws.column_dimensions["B"].width = 100
    lines = [
        ("怎么用", "只填**白底 / 黄底**的文字列。填完把文件发回来，我直接写进 data/act1.json。"),
        ("哪些别动", "「轮次」「位置 ID / 题号」「这是哪个位置」三列是**对号入座的钥匙**，别改名、别删行 —— 不然内容不知道该塞到哪儿。"),
        ("先看哪张", "先看「② 可探索点」—— 那就是这一共有哪些可以探索的地方：%d 个位置（探索点 + 可探索家具 + 小人）。"
                     % len(all_ids)),
        ("每轮不一样", "「③ 探索点文案」里每一轮都把**全部 %d 个位置**列了一遍。**这一轮不用的位置，把那一行的文字列整行留空** —— "
                       "我写回时会把它从这一轮摘掉（这一轮它头上不会有感叹号，也不进进度分母）。"
                       % len(all_ids)),
        ("谁是小人", "位置 ID 后面带「★小人」的就是那四个角色 —— 他们跟家具一样可以点、一样出线索卡、一样算进度。"),
        ("观察句", "点开一个位置，纸卡里按顺序显示的几句话。写几行就填几行，第 2/3 行留空就是两句。"),
        ("线索结论", "「线索总结」那一列 —— 看完这个位置之后会**记到右边「已记下的东西」**里。一句话，越短越好。"),
        ("换行", "同一格里想分段（比如答对反馈里的「【新剧情】」另起一行）：单元格里按 Alt+Enter。"),
        ("判断题·选项", "最多 3 个选项。只填 2 个就前两列有字、第三列留空。「正确选项」填 1 / 2 / 3，也可以填多个（比如 1,3）表示都算对。"),
        ("判断题·怎么触发", "★ 现在**不用填「找谁问」了** —— 本轮探索点全部看完，题目会**自动一道一道弹出来**（按表里的顺序）。答完最后一道自动进轮末过场。"),
        ("判断题·顺序", "想控制先问哪道：把「③ 判断题」里那些行的先后顺序调整即可（同一轮内）。"),
        ("每轮几道题", "第 2、3 轮现在各留了 3 行空模板；用不到的行**整行留空**，我会跳过（留着空行也不会卡流程）。"),
        ("轮末过场", "每轮最后一道题答完弹的那张纸。正文一句一行（Alt+Enter 换行）。"),
    ]
    ws.cell(row=1, column=1, value="《设计部》文案填充表 —— 填法").font = Font(bold=True, size=15)
    for i, (k, v) in enumerate(lines, start=3):
        ws.cell(row=i, column=1, value=k).font = Font(bold=True, size=11)
        ws.cell(row=i, column=1).alignment = Alignment(vertical="top")
        c = ws.cell(row=i, column=2, value=v)
        c.alignment = WRAP
        ws.row_dimensions[i].height = 34

    # ------------------------------------------------------------ ② 可探索点总表
    ws = wb.create_sheet("② 可探索点")
    head = ["位置 ID", "类型", "这是哪个位置", "大概在哪"]
    for i, h in enumerate(head, start=1):
        ws.cell(row=1, column=i, value=h)
    style_header(ws, 1, [16, 10, 20, 56])
    r = 2
    for sid in all_ids:
        typ = "★小人" if is_npc(sid) else "家具/位置"
        ws.cell(row=r, column=1, value=sid).font = LOCK_FONT
        ws.cell(row=r, column=2, value=typ)
        ws.cell(row=r, column=3, value=name_of(sid))
        ws.cell(row=r, column=4, value=WHERE.get(sid, ""))
        for j in range(1, 5):
            ws.cell(row=r, column=j).border = BORDER
            if is_npc(sid):
                ws.cell(row=r, column=j).fill = NPC_FILL
        ws.row_dimensions[r].height = 20
        r += 1

    # ------------------------------------------------------------ ③ 探索点文案
    ws = wb.create_sheet("③ 探索点文案")
    head = ["轮次", "位置 ID（别改）", "这是哪个位置（别改）", "探索点名称", "提示语",
            "观察句 1", "观察句 2", "观察句 3", "线索结论"]
    for i, h in enumerate(head, start=1):
        ws.cell(row=1, column=i, value=h)
    style_header(ws, 1, [7, 16, 20, 18, 26, 34, 34, 34, 30])

    r = 2
    for rd in rounds:
        # ⭐ 每一轮都把**全部**可探索点列一遍（不只是在用的那些）—— 作者要「这一轮加一个位置」
        #    时直接在这一轮找那一行填字就行；这一轮不想用的，文字列整行留空。
        # ⚠ 顺序：**本轮已有的点保持它们现在的先后**（那是作者的意思，写回时按表里的行序落盘），
        #    没用过的点补在这一块的后面。这样「表格 ⇄ JSON」往返是**逐字一致**的。
        by_id = {s["id"]: s for s in rd.get("spots", [])}
        ordered = [s["id"] for s in rd.get("spots", [])]
        for sid in all_ids:
            if sid not in by_id:
                ordered.append(sid)
        for sid in ordered:
            sp = by_id.get(sid, {})
            ws.cell(row=r, column=1, value="第 %d 轮" % rd["no"]).border = BORDER
            c2 = ws.cell(row=r, column=2, value=sid)
            c2.font = LOCK_FONT
            c2.border = BORDER
            c3 = ws.cell(row=r, column=3, value=name_of(sid))
            c3.font = LOCK_FONT
            c3.border = BORDER
            for j in (1, 2, 3):
                if is_npc(sid):
                    ws.cell(row=r, column=j).fill = NPC_FILL
            vals = [clean(sp.get("name", "")), clean(sp.get("hint", ""))]
            ls = [clean(x) for x in sp.get("lines", [])]
            while len(ls) < 3:
                ls.append("")
            vals += ls[:3] + [clean(sp.get("clue", ""))]
            for j, v in enumerate(vals, start=4):
                c = ws.cell(row=r, column=j, value=v if v else None)
                c.alignment = WRAP
                c.border = BORDER
                # ⭐ 有内容 = 绿底，空的 = 黄底。比「按轮次上色」诚实：
                #   第 1 轮那 4 个新加的小人还没写，就该是黄的。
                c.fill = FILLED_FILL if v else TODO_FILL
            ws.row_dimensions[r].height = 46
            r += 1

    # ------------------------------------------------------------ ④ 判断题
    ws = wb.create_sheet("④ 判断题")
    head = ["轮次", "题号（别改）", "题干", "选项 1", "选项 2", "选项 3（可空）",
            "正确选项", "备注（不用填）", "答对反馈", "答错反馈"]
    for i, h in enumerate(head, start=1):
        ws.cell(row=1, column=i, value=h)
    style_header(ws, 1, [7, 12, 34, 20, 20, 20, 9, 14, 40, 40])

    r = 2
    for rd in rounds:
        # ⛔ **不能**像第一版那样「第 2/3 轮一律换成三个空模板」—— 那是在文案还没写、
        #    表纯粹当空白模板发的时代写的。现在文案已经填回来了，再换空模板 = 表里看不到
        #    第 2/3 轮的真题，写回时会把它们整批删掉（往返测试抓到过：第 2/3 轮各剩 0 道）。
        #    ⭐ 正确做法：**先照实导出**，再用空模板行**补齐到 3 道**（作者想加题往下写就行）。
        qs = list(rd.get("questions", []))
        for k in range(len(qs), 3):
            qs.append({"id": "q%d_%s" % (rd["no"], "abcd"[k % 4]), "prompt": "", "options": []})
        for q in qs:
            opts = [o.get("text", "") for o in q.get("options", [])]
            while len(opts) < 3:
                opts.append("")
            correct = ",".join(str(i + 1) for i, o in enumerate(q.get("options", []))
                               if o.get("correct"))
            vals = [clean(q.get("prompt", ""))] + \
                   [clean(o) for o in opts[:3]] + \
                   [correct, NPC_CN.get(str(q.get("npc", "any")), str(q.get("npc", "any"))),
                    clean(q.get("on_correct", "")), clean(q.get("on_wrong", ""))]
            ws.cell(row=r, column=1, value="第 %d 轮" % rd["no"]).border = BORDER
            c2 = ws.cell(row=r, column=2, value=q["id"])
            c2.font = LOCK_FONT
            c2.border = BORDER
            for j, v in enumerate(vals, start=3):
                c = ws.cell(row=r, column=j, value=v if v else None)
                c.alignment = WRAP
                c.border = BORDER
                if j == 8:
                    c.font = LOCK_FONT
                else:
                    c.fill = FILLED_FILL if v else TODO_FILL
            ws.row_dimensions[r].height = 64
            r += 1

    # ------------------------------------------------------------ ⑤ 轮末过场
    ws = wb.create_sheet("⑤ 轮末过场")
    head = ["轮次", "标题", "正文（一句一行，Alt+Enter 换行）"]
    for i, h in enumerate(head, start=1):
        ws.cell(row=1, column=i, value=h)
    style_header(ws, 1, [7, 22, 96])
    r = 2
    for rd in rounds:
        e = rd.get("end", {})
        ws.cell(row=r, column=1, value="第 %d 轮" % rd["no"]).border = BORDER
        for j, v in ((2, clean(e.get("title", ""))),
                     (3, "\n".join(clean(x) for x in e.get("lines", [])))):
            c = ws.cell(row=r, column=j, value=v if v else None)
            c.alignment = WRAP
            c.border = BORDER
            c.fill = FILLED_FILL if v else TODO_FILL
        ws.row_dimensions[r].height = 60
        r += 1

    wb.save(OUT)
    print("saved ->", OUT)
    print("  ① 说明 / ② 可探索点(%d 个) / ③ 探索点文案(%d 行 = %d 轮 × %d 个位置) / ④ 判断题 / ⑤ 轮末过场"
          % (len(all_ids), len(all_ids) * len(rounds), len(rounds), len(all_ids)))


if __name__ == "__main__":
    main()
