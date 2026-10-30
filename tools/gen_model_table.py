"""从 data/*.json 生成建模对照表（HTML + CSV）。

用法：
  C:/Users/33667/.workbuddy/binaries/python/versions/3.13.12/python.exe tools/gen_model_table.py

输入：data/model_map.json（槽位与绑定）+ data/room.json + data/objects.json（位置与尺寸）
输出：docs/建模对照表.html、docs/建模对照表.csv

改完 model_map.json 或挪动了家具位置，重跑一次即可，不用手改表。
"""

import json
import os
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
DOCS = os.path.join(ROOT, "docs")
MODELS = os.path.join(ROOT, "assets", "models")

ZONE_CN = {
    "B": "建筑外壳",
    "F": "家具布景",
    "J": "可交互道具",
    "A": "角色",
    "FX": "特效辅助",
}
PRIO_CN = {1: "必做", 2: "接着做", 3: "可跳过"}
PRIO_CLASS = {1: "p1", 2: "p2", 3: "p3"}


def load(name):
    with open(os.path.join(DATA, name), "r", encoding="utf-8") as f:
        return json.load(f)


def has_model(slot):
    for ext in ("glb", "gltf", "tscn", "scn"):
        if os.path.exists(os.path.join(MODELS, slot + "." + ext)):
            return ext
    return None


def resolve_geometry(bind, room, objs):
    """把 bind 解析成 (底面中心 xyz, 尺寸 xyz)。查不到就返回 None。

    尺寸一律用「缩放后」的值 —— 布景/探索点/NPC 都会乘 room.json 里的 prop_scale，
    所以对照表就是场景里的真值，建模直接照表做即可。"""
    kind, _, key = bind.partition(":")
    rs = room.get("size", [16.0, 4.5, 12.0])
    ps = float(room.get("prop_scale", 1.0))

    if kind == "builtin":
        if key == "Floor":
            return (0.0, -0.05, 0.0), (rs[0], 0.1, rs[2])
        if key == "Ceiling":
            return (0.0, rs[1], 0.0), (rs[0] + 1.2, 0.2, rs[2] + 1.2)
        if key == "Marker":
            return None, (0.6, 0.02, 0.6)
    if kind == "wall":
        for w in room.get("walls", []):
            if w.get("name") == key:
                return tuple(w.get("pos", [0, 0, 0])), tuple(w.get("size", [1, 1, 1]))
    if kind == "window":
        for w in room.get("windows", []):
            if w.get("name") == key:
                return tuple(w.get("pos", [0, 0, 0])), tuple(w.get("size", [1, 1, 1]))
    if kind == "lamp":
        lights = room.get("ceiling_lights", [])
        i = int(key)
        if 1 <= i <= len(lights):
            xz = lights[i - 1]
            return (float(xz[0]), rs[1] - 0.1, float(xz[1])), (1.15, 0.1, 1.15)
    if kind == "prop":
        for p in room.get("props", []):
            if p.get("name") == key:
                k = float(p.get("scale", ps))   # 个别物件可自带 scale 覆盖
                return tuple(p.get("pos", [0, 0, 0])), tuple(v * k for v in p.get("size", [1, 1, 1]))
    if kind == "spot":
        for s in objs.get("spots", []):
            if s.get("id") == key:
                return tuple(s.get("pos", [0, 0, 0])), tuple(v * ps for v in s.get("size", [1, 1, 1]))
    if kind == "npc":
        for n in objs.get("npcs", []):
            if n.get("id") == key:
                return tuple(n.get("pos", [0, 0, 0])), tuple(v * ps for v in n.get("size", [1, 1, 1]))
    return None, None


def resolve_rot(bind, room):
    """这个位置绕 Y 轴转了多少度（只有布景支持 rot，其余都是 0）。

    朝向必须写进表里：模型自带的朝向是「正面朝 -Z」，一旦某个位置转了 180°，
    照 0° 做出来的模型放进去就是反的。两组工位背靠背就是靠这个字段。"""
    kind, _, key = bind.partition(":")
    if kind == "prop":
        for p in room.get("props", []):
            if p.get("name") == key:
                return float(p.get("rot", 0.0))
    return 0.0


def fmt3(v):
    return "×".join(("%.2f" % x).rstrip("0").rstrip(".") for x in v)


def prop_scale_of(room):
    return float(room.get("prop_scale", 1.0))


def build_rows(mm, room, objs):
    rows = []
    for e in mm.get("slots", []):
        slot = e.get("slot", "")
        model = e.get("model", "") or slot
        zone = slot.split("_")[1] if len(slot.split("_")) > 1 else "?"
        pos, size = resolve_geometry(str(e.get("bind", "")), room, objs)
        ext = has_model(model)
        rows.append(
            {
                "sn": e.get("sn", ""),
                "slot": slot,
                "model": model,
                "zone": zone,
                "cn": e.get("cn", ""),
                "group": e.get("group", ""),
                "kind": e.get("kind", ""),
                "pos": pos,
                "size": size,
                "rot": resolve_rot(str(e.get("bind", "")), room),
                "tri": e.get("tri", 0),
                "prio": e.get("prio", 3),
                "tripo": e.get("tripo", ""),
                "note": e.get("note", ""),
                "status": ("已有 " + ext) if ext else "灰盒",
            }
        )
    # 统计每个模型被多少个位置共用 —— 这是「实际要做的模型数」的依据。
    counts = {}
    for r in rows:
        counts[r["model"]] = counts.get(r["model"], 0) + 1
    for r in rows:
        r["reuse"] = counts[r["model"]]
    return rows


# ---------------------------------------------------------------- HTML

CSS = """
:root {
  --ink: #2b2a27;
  --ink-soft: #6b6862;
  --line: #d9d3c8;
  --paper: #fbf9f5;
  --card: #ffffff;
  --accent: #b5643c;
  --p1: #b5643c;
  --p2: #7d8f6d;
  --p3: #9a958d;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 40px 32px 72px;
  background: var(--paper);
  color: var(--ink);
  font-family: "Microsoft YaHei", "PingFang SC", "Noto Sans SC", -apple-system, sans-serif;
  font-size: 14px;
  line-height: 1.7;
}
.wrap { max-width: 1180px; margin: 0 auto; }
.kicker { margin: 0 0 6px; font-size: 12px; letter-spacing: 0.18em; color: var(--accent); }
h1 { margin: 0 0 10px; font-size: 27px; letter-spacing: 0.02em; }
.sub { margin: 0 0 6px; color: var(--ink-soft); }
.meta { margin: 0 0 30px; font-size: 12px; color: var(--ink-soft); }
h2 {
  margin: 40px 0 14px; font-size: 17px;
  padding-bottom: 8px; border-bottom: 2px solid var(--ink);
}
h2 .en { font-size: 11px; letter-spacing: 0.14em; color: var(--ink-soft); margin-left: 10px; font-weight: 400; }
.steps { margin: 0; padding: 0; list-style: none; counter-reset: s; }
.steps li {
  counter-increment: s; position: relative;
  padding: 12px 16px 12px 52px; margin-bottom: 8px;
  background: var(--card); border: 1px solid var(--line); border-radius: 8px;
}
.steps li::before {
  content: counter(s); position: absolute; left: 16px; top: 12px;
  width: 24px; height: 24px; border-radius: 50%;
  background: var(--accent); color: #fff;
  font-size: 13px; text-align: center; line-height: 24px;
}
.steps b { font-weight: 700; }
code {
  padding: 1px 6px; border-radius: 4px;
  background: #f0ebe2; border: 1px solid var(--line);
  font-family: Consolas, "Cascadia Mono", monospace; font-size: 12.5px;
}
.spec { margin: 0; padding: 0; list-style: none; }
.spec li { padding: 7px 0 7px 0; border-bottom: 1px dashed var(--line); }
.spec li:last-child { border-bottom: 0; }
.spec em { font-style: normal; color: var(--accent); font-weight: 700; margin-right: 8px; }
.zones { display: flex; flex-wrap: wrap; gap: 10px; margin: 0 0 8px; padding: 0; list-style: none; }
.zones li {
  flex: 1 1 150px; padding: 12px 14px;
  background: var(--card); border: 1px solid var(--line); border-radius: 8px;
}
.zones .z { font-size: 12px; color: var(--ink-soft); letter-spacing: 0.06em; }
.zones .n { font-size: 22px; font-weight: 700; }
.zones .t { font-size: 11.5px; color: var(--ink-soft); }
table { width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--line); }
caption { caption-side: top; text-align: left; font-size: 12px; color: var(--ink-soft); padding: 0 0 8px; }
th, td { padding: 8px 10px; border: 1px solid var(--line); vertical-align: top; text-align: left; }
thead th { background: #f2ece2; font-size: 12px; letter-spacing: 0.04em; white-space: nowrap; }
tbody tr:nth-child(even) { background: #fdfbf8; }
tr.zone-row td { background: #efe8dc; font-weight: 700; letter-spacing: 0.06em; }
td.slot { font-family: Consolas, "Cascadia Mono", monospace; font-size: 12.5px; white-space: nowrap; }
td.num, td.center { text-align: center; white-space: nowrap; }
.two { font-size: 12px; color: var(--ink-soft); }
.badge {
  display: inline-block; padding: 1px 7px; border-radius: 999px;
  font-size: 11.5px; color: #fff; white-space: nowrap;
}
.badge.p1 { background: var(--p1); }
.badge.p2 { background: var(--p2); }
.badge.p3 { background: var(--p3); }
.grey { color: var(--ink-soft); }
.hit { color: var(--accent); font-weight: 700; }
.reuse { display: inline-block; padding: 0 7px; margin-left: 4px; border-radius: 999px; background: #eaf1e4; color: #5c7350; font-size: 11px; white-space: nowrap; }
.mdl { font-family: Consolas, "Cascadia Mono", monospace; font-size: 12.5px; white-space: nowrap; }
.tripo { margin-top: 4px; font-family: Consolas, monospace; font-size: 11.5px; color: #8a857c; }
footer { margin-top: 36px; padding-top: 14px; border-top: 1px solid var(--line); font-size: 12px; color: var(--ink-soft); }
@media print {
  body { background: #fff; padding: 0; font-size: 11px; }
  h2 { page-break-after: avoid; }
  tr { page-break-inside: avoid; }
  thead { display: table-header-group; }
}
"""


def html_escape(s):
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def build_html(mm, rows, generated, room):
    models = sorted({r["model"] for r in rows})
    done_models = sorted({r["model"] for r in rows if r["status"].startswith("已有")})
    out = []
    out.append("<!DOCTYPE html>")
    out.append('<html lang="zh-CN">')
    out.append("<head>")
    out.append('<meta charset="utf-8">')
    out.append('<meta name="viewport" content="width=device-width, initial-scale=1">')
    out.append("<title>建模对照表 · 办公室八卦 Demo</title>")
    out.append("<style>%s</style>" % CSS)
    out.append("</head>")
    out.append("<body><div class=\"wrap\">")

    out.append("<header>")
    out.append('<p class="kicker">办公室八卦 Demo · 第一幕</p>')
    out.append("<h1>灰盒槽位 · 建模对照表</h1>")
    out.append(
        '<p class="sub">%d 个摆放位置，但<b>只需要做 %d 个模型</b>（已完成 %d）。'
        "一个模型可以顶多个位置：6 张工位桌、12 把椅子、5 扇窗各只需一份。"
        "模型文件名 = <code>model</code> 名，丢进 <code>assets/models/</code> 就自动替换，不用改一行代码。<br>"
        "表里的尺寸<b>已经含了统一缩放</b>（<code>prop_scale</code> %s）—— 照表做即可，不要再自己缩。</p>"
        % (len(rows), len(models), len(done_models), prop_scale_of(room))
    )
    out.append(
        '<p class="meta">生成时间 %s ｜ 源文件 <code>data/model_map.json</code> '
        "｜ 重跑 <code>tools/gen_model_table.py</code> 即可刷新</p>" % generated
    )
    out.append("</header>")

    # 三步替换法
    out.append('<h2>替换三步<span class="en">HOW TO SWAP</span></h2>')
    out.append('<ol class="steps">')
    out.append(
        "<li><b>照着做。</b>把 <code>assets/placeholders/greybox_reference.glb</code> 拖进 Blender，"
        "每个方块的名字就是槽位名，位置和尺寸都是真值 —— 照着描，或者干脆当比例参照。</li>"
    )
    out.append(
        "<li><b>照名字导出。</b>原点放<b>底面中心</b>、Y-up、Apply Transform（location 也要 Apply），"
        "导出 glb，<b>文件名必须等于「导出文件名」那一列</b>，例如 <code>SM_F_Desk.glb</code>。"
        "一个模型顶多个位置的时候（表里标了「×N 处复用」），只导这一份就行。</li>"
    )
    out.append(
        "<li><b>丢进去就行。</b>放进 <code>assets/models/</code>，重开游戏自动替换。"
        "控制台会播报「已换真模型 N · 仍是灰盒 M」，尺寸或面数不对还会点名提醒。</li>"
    )
    out.append("</ol>")

    # 命名规则
    out.append('<h2>命名规则与建模规范<span class="en">CONVENTIONS</span></h2>')
    out.append("<ul class=\"spec\">")
    out.append(
        "<li><em>命名</em><code>SM_&lt;Zone&gt;_&lt;Name&gt;[_&lt;Variant&gt;]</code>"
        "　Zone：B 建筑 / F 家具 / J 可交互 / A 角色 / FX 特效</li>"
    )
    out.append(
        "<li><em>单位</em>米。尺寸照表里给的来（已含统一缩放），不要自己再缩。</li>"
    )
    out.append(
        "<li><em>原点</em>放在物体<b>底面中心</b>（底面贴在表里的 y 上），没有例外 —— "
        "主角是相机本身，不做模型。</li>"
    )
    out.append(
        "<li><em>朝向</em>面向 -Z（glTF 默认正面）。椅子、人、有正反面的东西都照这个来。"
        "表里写了「绕 Y 轴转 X°」的位置是<b>场景替它转的</b>，你照 0° 做即可，别自己做反。"
        "两组工位背靠背拼成一个岛，就是靠这个字段把其中一组翻 180°。</li>"
    )
    out.append(
        "<li><em>材质</em>Metallic 0、Roughness 0.85、只用 Base Color。"
        "不做法线贴图、不做 ORM、不做真实反射。</li>"
    )
    out.append(
        "<li><em>配色</em>六组基色：暖木 <code>#C8A57B</code> 米白 <code>#EDE7DC</code> "
        "雾蓝 <code>#8FA9C4</code> 鼠尾草绿 <code>#9BB39A</code> "
        "珊瑚红 <code>#D98C6A</code> 墨灰 <code>#4B4A47</code>。</li>"
    )
    out.append(
        "<li><em>复用</em>表里标了「×N 处复用」的，就是多个位置共用同一个模型文件。"
        "只做一个、只导出一份，不要加 _01 / _02 后缀。</li>"
    )
    out.append(
        "<li><em>面数</em>表里给了每个模型的预算。人森风不怕少，超了就砍 —— 游戏会自动提醒。</li>"
    )
    out.append("</ul>")

    # 分组汇总
    out.append('<h2>分组汇总<span class="en">BY GROUP</span></h2>')
    out.append('<ul class="zones">')
    for z, cn in ZONE_CN.items():
        zs = [r for r in rows if r["zone"] == z]
        if not zs:
            continue
        zmodels = sorted({r["model"] for r in zs})
        seen = set()
        tri = 0
        for r in zs:
            if r["model"] in seen:
                continue
            seen.add(r["model"])
            tri += int(r["tri"])
        done = len({r["model"] for r in zs if r["status"].startswith("已有")})
        out.append(
            '<li><p class="z">%s · %s</p><p class="n">%d</p>'
            '<p class="t">位置 %d 个 ｜ 要做 %d 个模型 ｜ 面数预算 %s ｜ 已有 %d</p></li>'
            % (z, cn, len(zmodels), len(zs), len(zmodels), "{:,}".format(tri), done)
        )
    out.append("</ul>")
    seen_all = set()
    total_tri = 0
    for r in rows:
        if r["model"] in seen_all:
            continue
        seen_all.add(r["model"])
        total_tri += int(r["tri"])
    out.append(
        '<p class="meta">合计 %d 个摆放位置，要做 %d 个模型，面数预算 %s（去重后）。</p>'
        % (len(rows), len(models), "{:,}".format(total_tri))
    )

    # 主表
    out.append('<h2>槽位总表<span class="en">ALL SLOTS</span></h2>')
    out.append("<table>")
    out.append(
        "<caption>位置 = 底面中心的 X / 抬升 Y / Z；尺寸 = 长 × 高 × 宽（米）。"
        "模型一律照「正面朝 -Z」做 —— 表里写了「绕 Y 轴转 X°」的位置，是场景替它转的，你不要自己做反。"
        "同一行模型复用多次的，只在第一次出现的地方给面数预算。"
        "灰盒的碰撞会一直保留，所以模型稍微大一点点也不影响走路和点击。</caption>"
    )
    out.append("<thead><tr>")
    for h in ("编号", "摆在哪儿（场景节点）", "导出文件名（= 模型名）", "中文名", "位置 / 尺寸", "面数预算", "优先级", "状态", "做法与备注"):
        out.append("<th>%s</th>" % h)
    out.append("</tr></thead><tbody>")

    first_of_model = {}
    for r in rows:
        if r["model"] not in first_of_model:
            first_of_model[r["model"]] = r["slot"]

    for z, cn in ZONE_CN.items():
        zs = [r for r in rows if r["zone"] == z]
        if not zs:
            continue
        out.append(
            '<tr class="zone-row"><td colspan="9">%s · %s（%d 个位置 / %d 个模型）</td></tr>'
            % (z, cn, len(zs), len({r["model"] for r in zs}))
        )
        for r in zs:
            pos, size = r["pos"], r["size"]
            turn = (
                '<br><span class="hit">绕 Y 轴转 %d°</span>' % int(r["rot"])
                if abs(float(r.get("rot", 0.0))) > 0.01
                else ""
            )
            if pos is not None and size is not None:
                geo = "%s<br>%s%s" % (
                    "(%s)" % ", ".join("%.2f" % v for v in pos),
                    fmt3(size) + " m",
                    turn,
                )
            elif size is not None:
                geo = '<span class="grey">跟随点击点</span><br>%s m%s' % (fmt3(size), turn)
            else:
                geo = '<span class="grey">不适用</span>'
            status = (
                '<span class="hit">%s</span>' % html_escape(r["status"])
                if r["status"].startswith("已有")
                else '<span class="grey">灰盒</span>'
            )
            note = html_escape(r["note"])
            tripo = (
                '<div class="tripo">Tripo: %s</div>' % html_escape(r["tripo"])
                if r["tripo"]
                else ""
            )
            reuse = (
                '<span class="reuse">×%d 处复用</span>' % r["reuse"] if r["reuse"] > 1 else ""
            )
            if first_of_model[r["model"]] == r["slot"]:
                tri_cell = "{:,}".format(int(r["tri"])) if int(r["tri"]) else "—"
            else:
                tri_cell = '<span class="grey">同上</span>'
            out.append(
                "<tr id=\"%s\"><td class=\"num\">%s</td><td class=\"slot\">%s</td>"
                "<td class=\"mdl\">%s%s</td>"
                "<td>%s<br><span class=\"two\">%s</span></td>"
                "<td class=\"two\">%s</td><td class=\"num\">%s</td>"
                "<td class=\"center\"><span class=\"badge %s\">%s</span></td>"
                "<td class=\"center\">%s</td><td class=\"two\">%s%s</td></tr>"
                % (
                    r["slot"],
                    r["sn"],
                    r["slot"],
                    r["model"],
                    reuse,
                    html_escape(r["cn"]),
                    html_escape(r["group"]),
                    geo,
                    tri_cell,
                    PRIO_CLASS[r["prio"]],
                    PRIO_CN[r["prio"]],
                    status,
                    note,
                    tripo,
                )
            )
    out.append("</tbody></table>")

    out.append(
        "<footer>灰盒工程：<code>.</code>（已在 Godot 工程列表里，"
        "打开 Godot 点进去即可）　｜　"
        "自检：<code>res://scenes/selftest.tscn</code></footer>"
    )
    out.append("</div></body></html>")
    return "\n".join(out)


def main():
    mm = load("model_map.json")
    room = load("room.json")
    objs = load("objects.json")
    rows = build_rows(mm, room, objs)
    if not rows:
        print("没有读到任何槽位，检查 data/model_map.json")
        return 1

    os.makedirs(DOCS, exist_ok=True)
    generated = datetime.now().strftime("%Y-%m-%d %H:%M")

    html_path = os.path.join(DOCS, "建模对照表.html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(build_html(mm, rows, generated, room))

    csv_path = os.path.join(DOCS, "建模对照表.csv")
    with open(csv_path, "w", encoding="utf-8-sig", newline="") as f:
        f.write(
            "编号,摆在哪里(节点名),导出文件名(模型名),复用次数,中文名,分组,类型,"
            "位置X,底面Y,位置Z,朝向Y(度),长X,高Y,宽Z,面数预算,优先级,状态,Tripo提示词,备注\n"
        )
        for r in rows:
            p = r["pos"] or ("", "", "")
            s = r["size"] or ("", "", "")
            cells = [
                r["sn"],
                r["slot"],
                r["model"],
                r["reuse"],
                r["cn"],
                r["group"],
                r["kind"],
                ("%.2f" % p[0]) if p[0] != "" else "",
                ("%.2f" % p[1]) if p[1] != "" else "",
                ("%.2f" % p[2]) if p[2] != "" else "",
                ("%.0f" % float(r.get("rot", 0.0))),
                ("%.2f" % s[0]) if s[0] != "" else "",
                ("%.2f" % s[1]) if s[1] != "" else "",
                ("%.2f" % s[2]) if s[2] != "" else "",
                str(r["tri"]),
                PRIO_CN[r["prio"]],
                r["status"],
                r["tripo"],
                r["note"],
            ]
            f.write(",".join('"%s"' % str(c).replace('"', '""') for c in cells) + "\n")

    models = sorted({r["model"] for r in rows})
    done = sorted({r["model"] for r in rows if r["status"].startswith("已有")})
    print("[对照表] %d 个摆放位置 → 只需要做 %d 个模型（已有 %d）"
          % (len(rows), len(models), len(done)))
    prio1 = sorted({r["model"] for r in rows if r["prio"] == 1})
    prio2 = sorted({r["model"] for r in rows if r["prio"] == 2})
    print("[对照表] 必做 %d 个 / 接着做 %d 个 / 可跳过 %d 个"
          % (len(prio1), len(prio2), len(models) - len(prio1) - len(prio2)))
    print("[对照表] 必做清单：" + ", ".join(prio1))
    print("[对照表] 输出 %s" % html_path)
    print("[对照表] 输出 %s" % csv_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
