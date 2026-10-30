"""纯 Python 快速窥探 glb：不解码贴图、不起 Blender。

用法：python tools/glb_peek.py <a.glb> [b.glb ...]

打：面数 / 顶点数 / 网格与图元数 / 材质 / 贴图分辨率 / 包围盒（含节点变换）。
只读 GLB 头 + JSON chunk + accessor 的 min/max，所以 100 MB 的模型也是秒开。
"""
import json
import os
import struct
import sys


def load_glb(path):
    with open(path, "rb") as f:
        magic, ver, total = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise SystemExit("不是 glb：%s" % path)
        chunks = []
        while f.tell() < total:
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            clen, ctype = struct.unpack("<II", hdr)
            data = f.read(clen)
            chunks.append((ctype, data))
    js = None
    bin_len = 0
    for ctype, data in chunks:
        if ctype == 0x4E4F534A:          # JSON
            js = json.loads(data.decode("utf-8"))
        elif ctype == 0x004E4942:        # BIN
            bin_len = len(data)
    return js, bin_len


# glTF 枚举
MODE_TRIS = 4


def mat4_mul(a, b):
    # 列主序 4x4
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            out[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
    return out


def mat_identity():
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def node_matrix(n):
    if "matrix" in n:
        return list(n["matrix"])
    m = mat_identity()
    t = n.get("translation", [0, 0, 0])
    r = n.get("rotation", [0, 0, 0, 1])   # x,y,z,w
    s = n.get("scale", [1, 1, 1])
    x, y, z, w = r
    # 旋转 → 矩阵（列主序）
    rot = [
        1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
        2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
        2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
        0, 0, 0, 1,
    ]
    sm = [s[0], 0, 0, 0, 0, s[1], 0, 0, 0, 0, s[2], 0, 0, 0, 0, 1]
    m = mat4_mul(rot, sm)
    m[12], m[13], m[14] = t[0], t[1], t[2]
    return m


def xform(m, p):
    x, y, z = p
    return (m[0] * x + m[4] * y + m[8] * z + m[12],
            m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14])


def report(path):
    js, bin_len = load_glb(path)
    print("=" * 70)
    print("文件  %s   %.1f MB   BIN %.1f MB"
          % (os.path.basename(path), os.path.getsize(path) / 1e6, bin_len / 1e6))
    accs = js.get("accessors", [])
    meshes = js.get("meshes", [])
    mats = js.get("materials", [])
    nodes = js.get("nodes", [])

    print("节点 %d / 网格 %d / 材质 %d / 贴图 %d / 动画 %d / 骨骼 %d"
          % (len(nodes), len(meshes), len(mats),
             len(js.get("images", [])), len(js.get("animations", [])),
             len(js.get("skins", []))))

    # 每个图元：面数、顶点数、顶点 attribute 名
    tot_tris = 0
    tot_v = 0
    for mi, m in enumerate(meshes):
        for pi, p in enumerate(m.get("primitives", [])):
            mode = p.get("mode", MODE_TRIS)
            idx = p.get("indices")
            if idx is not None:
                n = accs[idx]["count"]
            else:
                n = accs[p["attributes"]["POSITION"]]["count"]
            tris = n // 3 if mode == MODE_TRIS else 0
            v = accs[p["attributes"]["POSITION"]]["count"]
            tot_tris += tris
            tot_v += v
            attrs = ",".join(sorted(p["attributes"].keys()))
            matname = mats[p["material"]].get("name", "?") if "material" in p else "-"
            print("  mesh[%d] prim[%d]  面 %d  顶点 %d  材质 %r  属性 [%s]"
                  % (mi, pi, tris, v, matname, attrs))
    print("  >>> 合计面数 %d / 顶点 %d" % (tot_tris, tot_v))

    for i, im in enumerate(js.get("images", [])):
        bv = im.get("bufferView")
        sz = js["bufferViews"][bv]["byteLength"] if bv is not None else 0
        print("  贴图[%d] %r mime=%s 约 %.1f MB"
              % (i, im.get("name"), im.get("mimeType"), sz / 1e6))

    for i, mm in enumerate(mats):
        pbr = mm.get("pbrMetallicRoughness", {})
        print("  材质[%d] %r  baseColorTex=%s  metallic=%s roughness=%s  normalTex=%s  emissive=%s"
              % (i, mm.get("name"),
                 "yes" if "baseColorTexture" in pbr else "-",
                 pbr.get("metallicFactor", 1.0), pbr.get("roughnessFactor", 1.0),
                 "yes" if "normalTexture" in mm else "-",
                 "yes" if "emissiveTexture" in mm else "-"))

    # 世界包围盒
    lo = [1e18] * 3
    hi = [-1e18] * 3

    def walk(ni, parent):
        n = nodes[ni]
        m = mat4_mul(parent, node_matrix(n))
        if "mesh" in n:
            for p in meshes[n["mesh"]].get("primitives", []):
                a = accs[p["attributes"]["POSITION"]]
                mn, mx = a.get("min"), a.get("max")
                if not mn:
                    continue
                for corner in ((mn[0], mn[1], mn[2]), (mx[0], mx[1], mx[2]),
                               (mn[0], mn[1], mx[2]), (mn[0], mx[1], mn[2]),
                               (mx[0], mn[1], mn[2]), (mx[0], mx[1], mx[2]),
                               (mn[0], mx[1], mx[2]), (mx[0], mn[1], mx[2])):
                    w = xform(m, corner)
                    for k in range(3):
                        lo[k] = min(lo[k], w[k])
                        hi[k] = max(hi[k], w[k])
        for c in n.get("children", []):
            walk(c, m)

    scene = js.get("scenes", [{}])[js.get("scene", 0)]
    for ni in scene.get("nodes", []):
        walk(ni, mat_identity())

    if lo[0] < 1e17:
        print("  包围盒(glTF 空间, Y 朝上)：")
        print("     min (%.3f, %.3f, %.3f)   max (%.3f, %.3f, %.3f)"
              % (lo[0], lo[1], lo[2], hi[0], hi[1], hi[2]))
        print("     尺寸  宽X %.3f × 高Y %.3f × 深Z %.3f  (底面 y=%.3f)"
              % (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], lo[1]))
        print("     → Godot: 宽 x %.3f / 高 y %.3f / 深 z %.3f"
              % (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
    else:
        print("  包围盒：POSITION 没有 min/max，量不到")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    for p in args:
        try:
            report(p)
        except Exception as e:
            print("!! %s 出错：%s" % (p, e))
