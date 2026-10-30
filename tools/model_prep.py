"""Blender 无头：批量把交付来的 glb 归一化成游戏能直接用的模型。

用法：
  D:/blender/blender.exe --background --python tools/model_prep.py -- <清单.json>

清单.json：

{
  "models_dir": "assets/models",
  "probe_dir":  "docs/probe_prep",
  "items": [
    { "src": "<源.glb>", "name": "SM_F_Sofa",
      "fit": "height",          # height / width / depth / max —— 按哪个轴等比缩放
      "target": 0.70,           # 该轴的目标米数
      "stretch": [1.0, 1.0, 0.55],  # 单轴拉伸（**只乘某几个轴，不整体等比**），默认 [1,1,1]
                                    #   数字      0.55            = 只乘高（Blender Z），等价于老的 squash
                                    #   对象      {"axis":"x","k":1.17} = 只乘宽（Blender X）
                                    #   数组      [1.17, 1.0, 1.32]  = [X, Y, Z] 各乘各的
                                    # 换算：Blender X = Godot 宽 x，Blender Y = Godot 深 z，Blender Z = Godot 高 y
                                    # ⛔ 想「只改一个维度」必须用它；改 fit/target 是**等比**，会把别的轴一起带走
      "squash": 0.55,           # 【旧名，仍兼容】等价于 stretch = 只乘高
      "tex": 2048,              # 贴图最长边上限
      "tint": "#F2836B",        # 换色：按亮度重映射，保留明暗与接缝（不写 = 不动）
      "tint_ref": 90,           # 「多亮才算目标色」按亮度分位数（默认 90；要整体变白就压到 40~60）
      "tint_gamma": 1.0,        # <1 再提一把中间调（暗件仍压得住），默认 1.0 不动
      "yaw": 0,                 # 绕 Z 预转多少度（把模型的正面转到 -Z）
      "decimate": "none",       # none（默认，不砍面）/ planar / collapse
      "tris": 0,                # 只在 decimate=collapse 时当上限用
      "angle": 1.0,             # 只在 decimate=planar 时用（共面夹角阈值，度）
      "weld": true,             # 焊重复顶点（零视觉损失），默认开
      "probe": true             # 是否出四视图自检图
    }
  ]
}

每个模型做的事：
  1. 导入 → 合并成一个对象 → 烘掉所有变换
  2. 按 fit 轴等比缩放（保持原始比例，绝不拉伸）
  3. 原点移到包围盒「底面中心」（游戏约定：原点在底面中心，Y-up，朝向 -Z）
  4. 焊掉重复顶点（remove_doubles）—— AI 生成的模型常是「每个三角形各自三个顶点」的
     散装网格，这一步零视觉损失，还能让后面的处理不容易出错
  5. 材质瘦身：只留 Base Color 那条链，去掉 Normal / ORM，Metallic 0 / Roughness 0.85
  6. 贴图缩到 tex（上限）；如填了 tint 就按亮度重映射换成目标色（保留明暗与接缝）
  7. 按 decimate 指定的方式处理面数（**默认不砍**）
  8. 出「正面 / 背面 / 俯视 / 斜视」四视图拼成一张自检图
  9. 对象名改成模型名，导出到 models_dir/<name>.glb

!! 顺序很重要：四视图必须在第 5~7 步**之后**渲染，
   否则你看到的是「还没被动过」的模型，减面造成的破损永远验不出来。

注意：源文件只读，产物写到输出路径。
"""
import bpy
import os
import sys
import json
import math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argv:
    raise SystemExit(__doc__)

with open(argv[0], "r", encoding="utf-8") as f:
    CFG = json.load(f)

# ⚠ 清单里的 paths 一律写成**相对工程根**（如 "assets/models"）；这里统一按
#    「本脚本 = tools/xxx.py，上一级 = 工程根」解析成绝对路径 —— 换机器 / 换 cwd 都不会跑飞
#    （原来写死 ./...，发给别人就跑不了）。
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = CFG.get("models_dir", "")
PROBE_DIR = CFG.get("probe_dir", "")
if MODELS_DIR and not os.path.isabs(MODELS_DIR):
    MODELS_DIR = os.path.join(ROOT, MODELS_DIR)
if PROBE_DIR and not os.path.isabs(PROBE_DIR):
    PROBE_DIR = os.path.join(ROOT, PROBE_DIR)

AXIS = {"width": 0, "depth": 1, "height": 2, "x": 0, "y": 1, "z": 2}
# 别名对照（Blender 轴 ↔ Godot 轴）：x/width = Godot 宽 x，y/depth = Godot 深 z，z/height = Godot 高 y
# glTF 是 Y-up，导进 Blender 变 Z-up：Blender 的 z = 高度。
# 映射关系：(x, y, z)_gltf → (x, -z, y)_blender，所以 **glTF 的 -Z（约定正面）在 Blender 里是 +Y**。
# 于是「看到模型正面」= 相机站在 +Y 往 -Y 看 —— 也就是四视图里的**第 2 格**。
#
# !! 2026-10-05 实测订正：这里原来写反了（写成「相机站在 -Y 往 +Y 看」）。
#    用 SM_F_DeskBench 验的：它的椅子在 -Z 侧，而**第 2 格**才看得见椅子。
#    所以：第 1 格 = glTF +Z 侧（模型若守约定，这一格看到的是背面）；
#          第 2 格 = glTF -Z 侧 = 约定正面。
#    判断「这个模型要不要 yaw 180」就看第 1 格：第 1 格是正脸 → 它朝 +Z → 要转 180。


def log(msg):
    print("[prep] " + msg, flush=True)


def world_bbox(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.objects):
        for it in list(coll):
            try:
                coll.remove(it)
            except Exception:
                pass


def do_import(path):
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except AttributeError:
        bpy.ops.wm.gltf_import(filepath=path)


def join_meshes():
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("[prep] 没导入到网格")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def slim_material():
    """只留 Base Color 那条链；其余节点（法线 / ORM / Mix）全丢。"""
    dropped = []
    for mat in list(bpy.data.materials):
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)

        allowed = set()
        if bsdf is not None:
            allowed.add(bsdf)
        for n in nt.nodes:
            if n.type == "OUTPUT_MATERIAL":
                allowed.add(n)
        if bsdf is not None and bsdf.inputs["Base Color"].is_linked:
            stack = [bsdf.inputs["Base Color"].links[0].from_node]
            while stack:
                n = stack.pop()
                if n in allowed:
                    continue
                allowed.add(n)
                for inp in n.inputs:
                    for l in inp.links:
                        stack.append(l.from_node)

        for n in list(nt.nodes):
            if n in allowed:
                continue
            tag = ""
            if n.type == "TEX_IMAGE" and n.image:
                tag = " (%s %s)" % (n.image.name, tuple(n.image.size))
            dropped.append("%s%s" % (n.type, tag))
            nt.nodes.remove(n)

        if bsdf is not None:
            for sock in ("Metallic", "Roughness"):
                if sock in bsdf.inputs:
                    for l in list(bsdf.inputs[sock].links):
                        nt.links.remove(l)
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.85
            for l in list(bsdf.inputs["Normal"].links):
                nt.links.remove(l)
    if dropped:
        log("   丢掉材质节点：" + ", ".join(dropped))


def shrink_textures(tex_max):
    """tex_max <= 0 表示不限，保持原始分辨率。只缩不打包 —— 打包统一放到最后。"""
    for img in list(bpy.data.images):
        if img.name == "Render Result" or img.size[0] == 0:
            continue
        if img.users == 0:
            log("   清掉没人用的贴图 %s %s" % (img.name, tuple(img.size)))
            bpy.data.images.remove(img)
            continue
        if tex_max > 0 and max(img.size) > tex_max:
            log("   贴图 %s %s → %d" % (img.name, tuple(img.size), tex_max))
            img.scale(tex_max, tex_max)


def hex_to_rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def recolour(tint_hex, ref_pct=90.0, gamma=1.0):
    """把 Base Color 贴图整体换成目标色，但**保留原有的明暗与接缝**。

    交付来的贴图几乎都是**烘焙图集**：真正的表面是一片片浅色岛，岛与岛之间填深色缝。
    所以既不能整体乘一个颜色（浅色会被一起压暗，整块发闷），也不能填平均色
    （缝会糊成一片，接缝全丢）。这里按亮度重映射：

        参考亮度 ref = 全图亮度的 ref_pct 分位
        每个像素     out = 目标色 × (自身亮度 / ref) ^ gamma

    亮的地方正好落在目标色上，暗的地方（岛间的缝、烘焙的 AO）按比例压暗 ——
    缝还在、明暗还在，但整块东西变成了新颜色。

    !! `ref_pct` 决定「多亮才算目标色」，直接决定改完是「白」还是「灰」：
       - 默认 90 分位 = 只有最亮的那 10% 到目标色 —— 木头、皮革这种中间调大片的资产
         改完是**灰的**（2026-10-06 三人办公桌就栽在这：作者要白，出来一片灰）。
       - 要「整体就是白的」，把 ref_pct 压到表面的典型亮度（看 tools/tex_hist.py 的
         分位数）：亮面统统顶到目标色、缝和缝隙自然留在下面。
       `gamma < 1` 再额外提一把中间调（暗部抬得少、亮部抬得多），显示器那种深色件
       仍然压得住，不会跟着泛白。

    ⚠ Blender 对 8bit 贴图的 `.pixels` 给的是**原始 sRGB 编码值**，不是线性值
      （已用已知灰阶实测确认）。所以目标色直接用 sRGB 分量，**千万别转线性**，
      一转整块布会亮一大截。
    """
    import numpy as np
    tgt = np.array(hex_to_rgb(tint_hex), dtype=np.float32)
    lum_w = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    for img in list(bpy.data.images):
        if img.size[0] == 0 or img.users == 0:
            continue
        w, h = img.size
        buf = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        px = buf.reshape(-1, 4)
        lum = px[:, :3] @ lum_w
        ref = float(np.percentile(lum, ref_pct))
        if ref <= 1e-4:
            log("   ! %s 整张都是黑的，跳过改色" % img.name)
            continue
        k = np.clip(lum / ref, 0.0, 1.0)
        if abs(gamma - 1.0) > 1e-6:
            k = np.power(k, gamma)
        px[:, :3] = tgt[None, :] * k[:, None]
        img.pixels.foreach_set(buf)
        img.update()
        log("   改色 %s → %s（参考分位 p%.0f = %.3f，gamma %.2f，落在目标色上的像素约 %.0f%%）"
            % (img.name, tint_hex, ref_pct, ref, gamma, (k > 0.985).mean() * 100.0))


## glTF 导出器对「内存里改过但没打包」的图片行为不确定 —— 显式打包，
## 保证导出去的是改过色的那一版，不是原始那一版。
def pack_images():
    for img in list(bpy.data.images):
        if img.size[0] == 0 or img.users == 0:
            continue
        try:
            img.pack()
        except Exception as e:
            log("   ! 打包失败 %s: %s" % (img.name, e))


def render_sheet(name, size, probe_dir):
    """三视图拼一张：正面 / 俯视 / 斜视。用 Workbench，快、且能看清形状与朝向。"""
    os.makedirs(probe_dir, exist_ok=True)
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.display.shading.light = "STUDIO"
    scn.display.shading.color_type = "TEXTURE"
    scn.display.shading.show_shadows = True
    scn.display.shading.show_cavity = True
    scn.display.shading.background_type = "VIEWPORT"
    scn.display.shading.background_color = (0.93, 0.93, 0.93)
    scn.render.resolution_x = size
    scn.render.resolution_y = size
    scn.render.film_transparent = False
    scn.render.image_settings.file_format = "PNG"

    cam_data = bpy.data.cameras.new("probe_cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("probe_cam", cam_data)
    scn.collection.objects.link(cam)
    scn.camera = cam

    w, d, h = size_box
    span = max(w, d, h) * 1.3
    cam_data.ortho_scale = span
    cz = h * 0.5

    shots = [
        # 第 1 格 = glTF +Z 侧（模型若朝向有误，这里就是它的正脸）；第 2 格 = glTF -Z = 约定正面
        ("plus_z", (0.0, -span * 2.0, cz), (math.radians(90), 0.0, 0.0)),
        ("minus_z", (0.0, span * 2.0, cz), (math.radians(90), 0.0, math.radians(180))),
        ("top", (0.0, 0.0, span * 2.0), (0.0, 0.0, 0.0)),
        ("iso", (span * 1.4, -span * 1.4, span * 1.4), None),
    ]
    tiles = []
    for tag, loc, rot in shots:
        cam.location = loc
        if rot is None:
            # 让相机看向 (0,0,h/2)
            direction = Vector((0.0, 0.0, cz)) - Vector(loc)
            cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        else:
            cam.rotation_euler = rot
        out = os.path.join(probe_dir, "_tmp_%s_%s.png" % (name, tag))
        scn.render.filepath = out
        bpy.ops.render.render(write_still=True)
        tiles.append(out)

    # 横向拼成一张（用 numpy 直接搬像素，省得装 Pillow）
    import numpy as np
    arrs = []
    for t in tiles:
        im = bpy.data.images.load(t)
        px = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)
        arrs.append(px)
        bpy.data.images.remove(im)
        os.remove(t)
    sheet = np.concatenate(arrs, axis=1)
    out_img = bpy.data.images.new("sheet_%s" % name, width=sheet.shape[1], height=sheet.shape[0], alpha=True)
    out_img.pixels = sheet.reshape(-1).tolist()
    out_path = os.path.join(probe_dir, "%s.png" % name)
    out_img.filepath_raw = out_path
    out_img.file_format = "PNG"
    out_img.save()
    bpy.data.images.remove(out_img)

    bpy.data.objects.remove(cam)
    bpy.data.cameras.remove(cam_data)
    log("   四视图 → %s" % out_path)


def weld_vertices(obj, max_dim):
    """焊重复顶点：合并「距离近到肉眼不可分」的顶点。

    Tripo / Meshy 这类 AI 生成的模型经常是「每个三角形各自三个顶点」的散装网格，
    顶点数虚高好几倍，而且每处接缝都是断开的 —— 这种拓扑一旦被减面，
    边缘塌缩就会把面片撕开，表现就是「表面碎成一片片」。
    这里合掉重复顶点是**零视觉损失**的清理（阈值只有 0.2‰ 最大边长）。
    """
    before = len(obj.data.vertices)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    try:
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=max_dim * 0.0002)
    finally:
        bpy.ops.object.mode_set(mode="OBJECT")
    after = len(obj.data.vertices)
    if after != before:
        log("   焊顶点 %d → %d（合并了 %d 个重复点）" % (before, after, before - after))
    else:
        log("   顶点没有重复的，跳过")
    return before - after


def apply_decimate(obj, it, tris_now):
    """按清单要求处理面数。默认什么都不做。"""
    mode = str(it.get("decimate", "none")).lower()
    if mode in ("", "none", "off"):
        log("   面数 %d —— 不动（清单里没要求减面）" % tris_now)
        return
    if mode == "planar":
        ang = float(it.get("angle", 1.0))
        m = obj.modifiers.new("Planar", "DECIMATE")
        m.decimate_type = "DISSOLVE"
        m.angle_limit = math.radians(ang)
        m.delimit = {"UV"}          # 保住 UV 缝，别让贴图错位
        bpy.ops.object.modifier_apply(modifier=m.name)
        obj.data.calc_loop_triangles()
        log("   保形减面（只合并夹角 < %.1f° 的共面三角形）%d → %d"
            % (ang, tris_now, len(obj.data.loop_triangles)))
        return
    if mode == "collapse":
        cap = int(it.get("tris", 0))
        if cap <= 0 or tris_now <= cap:
            log("   面数 %d 已在 %d 以内，不减" % (tris_now, cap))
            return
        m = obj.modifiers.new("Decimate", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = float(cap) / float(tris_now)
        bpy.ops.object.modifier_apply(modifier=m.name)
        obj.data.calc_loop_triangles()
        log("   !! 塌缩减面 %d → %d（上限 %d）—— 比例低于 20%% 时极易把面撕碎，慎用"
            % (tris_now, len(obj.data.loop_triangles), cap))
        return
    raise SystemExit("[prep] 不认识的 decimate 模式：%s" % mode)


REPORT = []

for it in CFG["items"]:
    src = it["src"]
    name = it["name"]
    fit = it.get("fit", "height")
    target = float(it["target"])
    tex_max = int(it.get("tex", 0))
    yaw = float(it.get("yaw", 0.0))
    want_probe = bool(it.get("probe", True))
    want_weld = bool(it.get("weld", True))

    log("=" * 56)
    log("%s  ←  %s" % (name, os.path.basename(src)))

    clear_scene()
    do_import(src)
    obj = join_meshes()

    obj.data.calc_loop_triangles()
    tris0 = len(obj.data.loop_triangles)
    lo, hi = world_bbox(obj)
    size = hi - lo
    log("   原始：面数 %d / 宽X %.3f × 深Y %.3f × 高Z %.3f" % (tris0, size.x, size.y, size.z))

    if abs(yaw) > 1e-6:
        import mathutils
        # !! glTF 导入器把物体的 rotation_mode 设成了 QUATERNION，
        #    这时候赋 rotation_euler 是**静默无效**的（不报错、不警告、尺寸也不变）。
        #    2026-10-05 踩过：5 件要转 180° 的模型全都没转，还以为是模型本身对称。
        #    必须先把 rotation_mode 掰回 XYZ 再赋值。
        obj.rotation_mode = "XYZ"
        obj.rotation_euler = mathutils.Euler((0.0, 0.0, math.radians(yaw)), "XYZ")
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        lo, hi = world_bbox(obj)
        size = hi - lo
        log("   预转 %.0f° 后：宽X %.3f × 深Y %.3f × 高Z %.3f" % (yaw, size.x, size.y, size.z))

    # 等比缩放：按 fit 轴对齐目标，其余轴顺势跟着走（不拉伸）
    if fit == "max":
        cur = max(size.x, size.y, size.z)
    else:
        cur = size[AXIS[fit]]
    if cur <= 1e-6:
        raise SystemExit("[prep] %s 的 %s 轴尺寸为 0，没法缩放" % (name, fit))
    k = target / cur
    obj.scale = (k, k, k)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 单轴拉伸：**只乘指定的轴**，其余轴原样不动。三种写法：
    #   数字       0.55                         → 只乘高（Blender Z）＝ 老的 squash
    #   对象       {"axis": "x", "k": 1.1729}    → 只乘某一个轴
    #   数组       [1.1729, 1.0, 1.32]           → [X, Y, Z] 三轴各乘各的
    # ⛔ 为什么不能用 fit/target：那是**等比**缩放，改一个轴会带着另外两个一起变。
    #    想「只拉高」或「只拉宽」就必须走这里。
    #    Blender X = Godot 宽 x，Blender Y = Godot 深 z，Blender Z = Godot 高 y。
    stretch = it.get("stretch", it.get("squash", 1.0))
    if isinstance(stretch, dict):
        _k = [1.0, 1.0, 1.0]
        _k[AXIS[str(stretch["axis"]).lower()]] = float(stretch["k"])
        stretch = _k
    elif not isinstance(stretch, (list, tuple)):
        stretch = [1.0, 1.0, float(stretch)]      # 只给一个数 = 只乘高
    s = [float(v) for v in stretch]
    if any(abs(v - 1.0) > 1e-6 for v in s):
        obj.scale = (s[0], s[1], s[2])
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        lo, hi = world_bbox(obj)
        size = hi - lo
        log("   单轴拉伸 ×(%.4f, %.4f, %.4f) → 宽X %.3f × 深Y %.3f × 高Z %.3f" % (s[0], s[1], s[2], size.x, size.y, size.z))

    # 原点 = 底面中心
    lo, hi = world_bbox(obj)
    obj.location -= Vector(((lo.x + hi.x) / 2.0, (lo.y + hi.y) / 2.0, lo.z))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo, hi = world_bbox(obj)
    size = hi - lo
    size_box = (size.x, size.y, size.z)
    log("   缩放到 %s %.3f（系数 %.4f）→ 宽X %.3f × 深Y %.3f × 高Z %.3f"
        % (fit, target, k, size.x, size.y, size.z))
    log("   换算到 Godot：宽 x %.3f / 高 y %.3f / 深 z %.3f  底面 y=%+.3f"
        % (size.x, size.z, size.y, lo.z))

    if bool(it.get("probe_only", False)):
        if want_probe:
            render_sheet(name, 420, PROBE_DIR)
        log("   只出图，不导出")
        REPORT.append({"name": name, "probe_only": True,
                       "w": round(size.x, 4), "h": round(size.z, 4), "d": round(size.y, 4)})
        continue

    if want_weld:
        weld_vertices(obj, max(size.x, size.y, size.z))

    slim_material()
    shrink_textures(tex_max)

    # 改色放在瘦身之后：先缩到目标分辨率的 1/4 像素量再算，快很多。
    tint = str(it.get("tint", "")).strip()
    if tint:
        recolour(tint, float(it.get("tint_ref", 90.0)), float(it.get("tint_gamma", 1.0)))

    pack_images()

    obj.data.calc_loop_triangles()
    apply_decimate(obj, it, len(obj.data.loop_triangles))

    # !! 四视图必须在这之后 —— 否则你看的是「还没被动过」的模型。
    if want_probe:
        render_sheet(name, 420, PROBE_DIR)

    obj.name = name
    obj.data.name = name
    out = os.path.join(MODELS_DIR, name + ".glb")
    os.makedirs(MODELS_DIR, exist_ok=True)
    try:
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB",
                                  export_apply=True, export_yup=True)
    except TypeError:
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB")

    lo, hi = world_bbox(obj)
    kb = os.path.getsize(out) / 1024.0
    log("   导出 %s  |  %d 面 / %.1f KB" % (out, len(obj.data.loop_triangles), kb))
    REPORT.append({
        "name": name,
        "src_tris": tris0,
        "tris": len(obj.data.loop_triangles),
        "w": round(hi.x - lo.x, 4),
        "h": round(hi.z - lo.z, 4),
        "d": round(hi.y - lo.y, 4),
        "kb": round(kb, 1),
    })

log("=" * 56)
log("汇总（Godot 坐标：宽 x / 高 y / 深 z）")
log(json.dumps(REPORT, ensure_ascii=False, indent=2))
