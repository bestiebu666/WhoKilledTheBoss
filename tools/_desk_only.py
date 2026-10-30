import json, io, os

d = json.load(io.open('tools/model_prep_list.json', encoding='utf-8'))
bar = [it for it in d['items'] if it.get('name') == 'SM_F_Desk3P']
assert len(bar) == 1, bar
only = {
    '_note': '临时：只重出办公桌 SM_F_Desk3P，别动 assets/models 里其余 17 个模型。',
    'models_dir': d['models_dir'],
    'probe_dir': d['probe_dir'],
    'items': bar,
}
json.dump(only, io.open('tools/_desk_only.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
it = bar[0]
print('已写 tools/_desk_only.json')
print('src     =', it['src'], '存在=', os.path.exists(it['src']))
print('fit/tgt =', it['fit'], it['target'])
print('stretch =', it.get('stretch'))
print('yaw     =', it.get('yaw'), ' tex =', it.get('tex'), ' tint =', it.get('tint', '(无)'))
