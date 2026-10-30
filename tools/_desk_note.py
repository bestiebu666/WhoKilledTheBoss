import json, io

p = 'data/room.json'
d = json.load(io.open(p, encoding='utf-8'))

NOTE = ('**2026-10-05**：作者给的 `assets/models/SM_F_Desk3P.glb` 又换了一版（最新「办公桌」，深蓝隔板 + 粉抽屉柜，'
        '1,499,060 面）。作者要求「大小位置不变」→ 清单里加 `stretch [1.0, 0.7829427, 0.9414504]` 把新模型的'
        '自然比例（fit width 3.862 后是 3.862×1.030×0.849）压回旧的 **3.862 × 0.970 × 0.665 米**，'
        '所以这一条的 `size` / `pos` / `rot` 一个数都没动，两个背靠背的桌子依旧严丝合缝（自检的「中心距 = 一个进深、缝隙 0」仍过）。')

hit = 0
def walk(o):
    global hit
    if isinstance(o, dict):
        if o.get('name') in ('DeskBench_1', 'DeskBench_2'):
            o['_note'] = NOTE
            hit += 1
        for v in o.values():
            walk(v)
    elif isinstance(o, list):
        for x in o:
            walk(x)

walk(d)
json.dump(d, io.open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('写了', hit, '条 _note')
