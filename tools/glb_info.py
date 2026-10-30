#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""看一眼 .glb —— 建模交付前的自检工具。

打印：节点层级 / 网格 / 面数 / 材质 / 整体包围盒，并可与目标尺寸比对。
用它先确认「尺寸对不对、原点在哪、朝向对不对」，再丢进 assets/models/。

用法：
    python tools/glb_info.py <文件.glb>
    python tools/glb_info.py <文件.glb> --expect 3.6x0.6x0.64
"""
import json
import struct
import sys


# ---------- glb 解析 ----------

def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 12:
        raise SystemExit("文件太小，不是 glb")
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise SystemExit("不是 glb（magic = %r）—— 请导出为 glTF Binary (.glb)" % magic)
    off = 12
    js = None
    bin_len = 0
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:          # 'JSON'
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:        # 'BIN'
            bin_len = clen
        off += 8 + clen
    if js is None:
        raise SystemExit("没找到 JSON chunk")
    return js, bin_len, len(data), version


# ---------- 矩阵 ----------

def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]                # glTF 是列主序
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0.0, 0.0, 0.0])
    r = node.get("rotation", [0.0, 0.0, 0.0, 1.0])   # xyzw
    s = node.get("scale", [1.0, 1.0, 1.0])
    x, y, z, w = r
    rm = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    return [
        [rm[0][0] * s[0], rm[0][1] * s[1], rm[0][2] * s[2], t[0]],
        [rm[1][0] * s[0], rm[1][1] * s[1], rm[1][2] * s[2], t[1]],
        [rm[2][0] * s[0], rm[2][1] * s[1], rm[2][2] * s[2], t[2]],
        [0.0, 0.0, 0.0, 1.0],
    ]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def xform(m, p):
    return [
        m[0][0] * p[0] + m[0][1] * p[1] + m[0][2] * p[2] + m[0][3],
        m[1][0] * p[0] + m[1][1] * p[1] + m[1][2] * p[2] + m[1][3],
        m[2][0] * p[0] + m[2][1] * p[1] + m[2][2] * p[2] + m[2][3],
    ]


IDENT = [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]


# ---------- 遍历 ----------

def collect(js):
    """返回 (行列表, 包围盒 min/max, 总面数, 材质名列表)。"""
    nodes = js.get("nodes", [])
    meshes = js.get("meshes", [])
    accs = js.get("accessors", [])
    mats = js.get("materials", [])
    scene = js.get("scenes", [{}])[js.get("scene", 0)] if js.get("scenes") else {}

    rows = []
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    total_tris = 0
    got_box = [False]

    def visit(idx, parent_m, depth, is_root):
        node = nodes[idx]
        m = mat_mul(parent_m, node_matrix(node))
        name = node.get("name", "(未命名 #%d)" % idx)
        tris = 0
        bb = None
        if "mesh" in node:
            for prim in meshes[node["mesh"]].get("primitives", []):
                mode = prim.get("mode", 4)
                if "indices" in prim:
                    n = accs[prim["indices"]]["count"]
                else:
                    n = accs[prim["attributes"]["POSITION"]]["count"]
                if mode == 4:
                    tris += n // 3
                pos_acc = accs[prim["attributes"]["POSITION"]]
                if "min" in pos_acc and "max" in pos_acc:
                    a, b = pos_acc["min"], pos_acc["max"]
                    corners = [
                        [a[0] if i & 1 else b[0],
                         a[1] if i & 2 else b[1],
                         a[2] if i & 4 else b[2]] for i in range(8)
                    ]
                    pts = [xform(m, c) for c in corners]
                    pmin = [min(p[k] for p in pts) for k in range(3)]
                    pmax = [max(p[k] for p in pts) for k in range(3)]
                    for k in range(3):
                        lo[k] = min(lo[k], pmin[k])
                        hi[k] = max(hi[k], pmax[k])
                    got_box[0] = True
                    size = [pmax[k] - pmin[k] for k in range(3)]
                    if bb is None:
                        bb = (pmin, size)
                    else:
                        bb = ([min(bb[0][k], pmin[k]) for k in range(3)],
                              [max(bb[1][k], size[k]) for k in range(3)])
        total_tris_local = [tris]
        rows.append((depth, name, tris, node.get("mesh"), bb, is_root, node))
        nonlocal total_tris
        total_tris += tris
        for c in node.get("children", []):
            visit(c, m, depth + 1, False)

    for r in scene.get("nodes", []):
        visit(r, IDENT, 0, True)

    mat_names = []
    for mt in mats:
        mat_names.append(mt.get("name", "(未命名材质)"))
    return rows, (lo, hi) if got_box[0] else None, total_tris, mat_names


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    expect = None
    if "--expect" in sys.argv:
        raw = sys.argv[sys.argv.index("--expect") + 1]
        expect = [float(x) for x in raw.lower().replace("*", "x").split("x")]

    js, bin_len, file_len, version = load_glb(path)
    rows, box, tris, mat_names = collect(js)

    print("文件      :", path)
    print("大小      : %.1f KB（几何数据 %.1f KB）" % (file_len / 1024.0, bin_len / 1024.0))
    print("glTF 版本 : %d   生成器: %s" % (
        version, js.get("asset", {}).get("generator", "未知")))
    print("节点 %d / 网格 %d / 材质 %d / 面数 %d"
          % (len(js.get("nodes", [])), len(js.get("meshes", [])), len(mat_names), tris))
    if mat_names:
        print("材质      :", ", ".join(mat_names))
    imgs = js.get("images", [])
    if imgs:
        print("贴图 %d 张 :" % len(imgs),
              ", ".join(i.get("name") or i.get("mimeType", "?") for i in imgs))

    print("\n-- 节点层级 --")
    for depth, name, t, mesh_idx, bb, is_root, node in rows:
        mark = ""
        if is_root:
            mark = "  [根]"
        extra = ""
        if "mesh" in node:
            extra = "  网格#%d" % node["mesh"]
        if t:
            extra += "  %d 面" % t
        if bb is not None:
            extra += "  局部包围盒 %.3f×%.3f×%.3f" % tuple(bb[1])
        print("  " * depth + "- " + name + mark + extra)

    if box is None:
        print("\n!! 没有任何 POSITION 包围盒 —— 模型可能是空的")
        return
    lo, hi = box
    size = [hi[k] - lo[k] for k in range(3)]
    print("\n-- 整体包围盒（glTF 坐标，Y-up，单位米）--")
    print("  min   : (%.3f, %.3f, %.3f)" % tuple(lo))
    print("  max   : (%.3f, %.3f, %.3f)" % tuple(hi))
    print("  尺寸  : %.3f × %.3f × %.3f   (x 宽 / y 高 / z 深)" % tuple(size))
    print("  底面  : y = %.3f" % lo[1])
    print("  水平中心: x = %.3f, z = %.3f" % ((lo[0] + hi[0]) / 2.0, (lo[2] + hi[2]) / 2.0))

    print("\n-- 与游戏里的约定比对 --")
    ok = True
    if abs(lo[1]) > 0.02:
        print("  ! 底面不在 y=0（在 y=%.3f）—— 原点不是底面中心，挂进场景会整体上浮/下沉" % lo[1])
        ok = False
    if abs((lo[0] + hi[0]) / 2.0) > 0.02 or abs((lo[2] + hi[2]) / 2.0) > 0.02:
        print("  ! 水平原点不在包围盒中心 —— 原件原点没落在底心")
        ok = False
    if ok:
        print("  √ 原点就在底面中心")

    if expect:
        print("\n  预期尺寸 %.2f × %.2f × %.2f" % tuple(expect))
        for i, ax in enumerate("xyz"):
            r = size[i] / expect[i] if expect[i] else 0.0
            flag = "√" if 0.6 <= r <= 1.6 else "!"
            print("    %s: 实际 %.3f / 预期 %.3f = %.2f 倍  %s" % (ax, size[i], expect[i], r, flag))


if __name__ == "__main__":
    main()
