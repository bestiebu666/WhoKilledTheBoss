# -*- coding: utf-8 -*-
"""把作者填好的《设计部_文案填充表》.xlsx 写回 data/act1.json。

对号入座的钥匙（不靠行号，靠这两列 —— 作者可以插行、删行、调顺序）：
    ③ 探索点文案 : 「轮次」+「位置 ID」（家具和小人同一种写法）
    ④ 判断题     : 「轮次」+「题号」
    ⑤ 轮末过场   : 「轮次」

规则：
    · 文字列**全空** = 这一轮这个位置/这道题不要了 → 直接从 JSON 里删掉
      （探索点删掉 = 这一轮它头上没有感叹号、也不进进度分母；判断题删掉 = 这轮少一道题）。
      ⭐ 「每一轮的探索点可以不一样」就是靠这条实现的。
    · 「正确选项」写 1 / 2 / 3，或 1,3（都算对）。
    · 「备注（不用填）」那一列**不参与判断**，也不会写进 JSON（题目现在不靠找人触发）。
    · 选项留空的那几列直接不生成（所以支持 2 选项）。
    · ⭐ 表里的位置 id 必须**场景里真的有**（objects.json 的 spots / npcs，或 room.json 里
      带 explore 的 prop）。不存在的 id 会被跳过并报警 —— 免得写出一个「点不开的空位」。

写回前会把原文件备份成 `act1.json.bak`。

用法：
    "C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe" tools/apply_fill_sheet.py
    # 也可以把作者发回来的那份 xlsx 路径直接当参数传进来（他手上那份不在仓库里）：
    "C:/Users/33667/AppData/Local/Programs/Python/Python312/python.exe" tools/apply_fill_sheet.py "D:\\...\\设计部_文案填充表 副本(AI).xlsx"
"""

import io
import json
import os
import re
import shutil
import sys

from openpyxl import load_workbook

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT = os.path.join(ROOT, "data", "act1.json")
SHEET = os.path.join(ROOT, "docs", "设计部_文案填充表.xlsx")


def sheet_path() -> str:
    """默认读仓库里那份空白模板；命令行给了路径就用那个（作者发回来的那份）。"""
    return sys.argv[1] if len(sys.argv) > 1 else SHEET

NPC_ID = {"凤凰男": "feng", "实习 1 号": "intern1", "实习1号": "intern1",
          "老板": "boss", "外聘设计总监": "director", "总监": "director",
          "随便谁": "any", "任何": "any"}


def rd_no(v) -> int:
    """「第 2 轮」-> 1（0 起）。"""
    m = re.search(r"(\d+)", str(v or ""))
    return (int(m.group(1)) - 1) if m else -1


def txt(v) -> str:
    return "" if v is None else str(v)


def main():
    act = json.load(io.open(ACT, encoding="utf-8"))
    wb = load_workbook(sheet_path())
    rounds = act["rounds"]
    changed = {"spot": 0, "q": 0, "end": 0, "drop_spot": 0, "drop_q": 0}

    # 场景里**真实存在**的可探索点 id（探索点 + 可探索家具 + 小人）。
    # ⭐ 表里出现了不在这个集合里的 id 就**不能写进去** —— 写进去等于凭空造一个
    #   「永远点不开的空位」（自检会报悬空 id）。位置被删掉之后表里残留的旧行
    #   （比如 2026-10-06 删掉的白板）就走这条路，只报警、不写。
    ob = json.load(io.open(os.path.join(ROOT, "data", "objects.json"), encoding="utf-8"))
    room = json.load(io.open(os.path.join(ROOT, "data", "room.json"), encoding="utf-8"))
    known = {str(s.get("id", "")) for s in ob.get("spots", [])}
    known |= {str(n.get("id", "")) for n in ob.get("npcs", [])}
    known |= {str(p.get("explore", "")) for p in room.get("props", []) if p.get("explore")}
    known.discard("")
    unknown = {}

    # ---------------------------------------------------------- ③ 探索点文案
    ws = wb["③ 探索点文案"]
    rows = list(ws.iter_rows(min_row=2, values_only=True))
    by_round = {}
    for r in rows:
        i = rd_no(r[0])
        if i < 0 or i >= len(rounds):
            continue
        sid = txt(r[1]).strip()
        if not sid:
            continue
        vals = [txt(x) for x in r[3:9]]          # 名称/提示语/观察句1-3/线索
        if sid not in known:
            # 场景里没有这个位置了 —— 只记「真的写了内容」的那种，最后统一报警。
            if any(v.strip() for v in vals[1:6]):
                unknown.setdefault(i, []).append(sid)
            continue
        by_round.setdefault(i, {})[sid] = vals

    for i, table in by_round.items():
        kept = []
        old = {s["id"]: s for s in rounds[i].get("spots", [])}
        # 以**表里的行序**为准 —— 作者调顺序 = 改感叹号出现的顺序（虽然现在不影响玩法）
        for sid, vals in table.items():
            name, hint, l1, l2, l3, clue = vals
            # ⛔ 「探索点名称」**不参与**「这一轮用不用它」的判定 —— 每轮的行里名字都是
            #   预填好的（家具名 / 人名），拿它判的话，作者把提示语/观察句/结论全留空之后
            #   这一行还会被当成「有用」，于是这一轮白多出一个点、点开是空的。
            #   「这一轮不用它」= 提示语 / 三条观察句 / 线索结论 **全空**。
            if not any(v.strip() for v in (hint, l1, l2, l3, clue)):
                changed["drop_spot"] += 1
                continue
            prev = old.get(sid, {})
            lines = [x for x in (l1, l2, l3) if x.strip() != ""]
            kept.append({
                "id": sid,
                "name": name or prev.get("name", sid),
                "hint": hint,
                "lines": lines,
                "clue": clue,
            })
            changed["spot"] += 1
        rounds[i]["spots"] = kept

    # ---------------------------------------------------------- ④ 判断题
    ws = wb["④ 判断题"]
    rows = list(ws.iter_rows(min_row=2, values_only=True))
    q_by_round = {}
    for r in rows:
        i = rd_no(r[0])
        if i < 0 or i >= len(rounds):
            continue
        qid = txt(r[1]).strip()
        if not qid:
            continue
        q_by_round.setdefault(i, []).append((qid, [txt(x) for x in r[2:10]]))

    for i, qlist in q_by_round.items():
        old = {str(q.get("id", "")): q for q in rounds[i].get("questions", [])}
        kept = []
        for qid, v in qlist:
            prompt, o1, o2, o3, correct, who, on_ok, on_bad = v
            # ⛔ 「备注（不用填）」那一列（下标 5）**不算内容** —— 它是给我看的参考，
            #    连它一起判的话，作者把一道题的题干/选项/反馈全删空之后，
            #    那一行还是会被当成「有内容」，凭空生成一道空题。
            content = [prompt, o1, o2, o3, correct, on_ok, on_bad]
            if not any(x.strip() for x in content):
                changed["drop_q"] += 1
                continue
            prev = old.get(qid, {})
            picks = [s.strip() for s in correct.replace("，", ",").split(",") if s.strip()]
            opts = []
            for n, o in enumerate((o1, o2, o3), start=1):
                if o.strip() == "":
                    continue
                opts.append({"text": o, "correct": str(n) in picks})
            npc = NPC_ID.get(who.strip(), who.strip() or prev.get("npc", "any"))
            q = {
                "id": qid,
                "npc": npc,
                "target": prev.get("target", ""),
                "prompt": prompt,
                "options": opts,
                "on_correct": on_ok,
                "on_wrong": on_bad,
            }
            if prev.get("requires"):
                q["requires"] = prev["requires"]
            kept.append(q)
            changed["q"] += 1
        rounds[i]["questions"] = kept

    # ---------------------------------------------------------- ⑤ 轮末过场
    ws = wb["⑤ 轮末过场"]
    for r in ws.iter_rows(min_row=2, values_only=True):
        i = rd_no(r[0])
        if i < 0 or i >= len(rounds):
            continue
        title = txt(r[1]).strip()
        body = [x for x in txt(r[2]).split("\n") if x.strip() != ""]
        if not title and not body:
            continue
        rounds[i]["end"] = {"title": title or rounds[i].get("end", {}).get("title", ""),
                            "lines": body}
        changed["end"] += 1

    shutil.copyfile(ACT, ACT + ".bak")
    io.open(ACT, "w", encoding="utf-8").write(
        json.dumps(act, ensure_ascii=False, indent=2) + "\n")
    print("写回 %s" % ACT)
    print("  更新探索点 %d 个（删掉 %d 个）/ 判断题 %d 道（删掉 %d 道）/ 轮末 %d 段"
          % (changed["spot"], changed["drop_spot"], changed["q"], changed["drop_q"],
             changed["end"]))
    for i, rd in enumerate(rounds):
        print("  第 %d 轮：%d 个位置 / %d 道题 / 过场「%s」"
              % (i + 1, len(rd.get("spots", [])), len(rd.get("questions", [])),
                 rd.get("end", {}).get("title", "")))

    if unknown:
        print()
        print("⚠⚠ 表里有 %d 个**场景里不存在**的位置，内容没有写进去（免得凭空造出"
              "点不开的空位）：" % sum(len(v) for v in unknown.values()))
        for i, ids in sorted(unknown.items()):
            print("    第 %d 轮：%s" % (i + 1, "、".join(ids)))
        print("  → 要么在 objects.json / room.json 里先把这些位置建出来，"
              "要么把表里那几行删掉。")


if __name__ == "__main__":
    main()
