# 3D の人体（MPFB）をアプリ用に書き出す
#  blender-launcher.exe -b --python export_body.py -- <出力フォルダ>
#  出力：body.bin（形・骨・体格と顔の調整ごとの差分）と、肌・目・眉・まつ毛・髪の画像
#
#  body.bin の中身（リトルエンディアン）
#   'TBDY' u32 版 / u32 JSON の長さ / JSON / 0 で 4バイトにそろえる / データ
#   JSON に部品（体・目・眉・まつ毛・髪）と骨と差分の一覧、データの位置（バイト）が書いてある
#  座標は Blender のまま（m、Z が上、人は −Y を向く）
import bpy, bmesh, sys, os, json, struct, math
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.locationservice import LocationService

OUT = sys.argv[sys.argv.index('--') + 1]
os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'progress.txt'), 'w').close()
U = LocationService.get_user_data()
SYS = LocationService.get_mpfb_data()
LOG = []


def log(s):
    LOG.append(str(s))
    with open(os.path.join(OUT, 'progress.txt'), 'a', encoding='utf8') as fp:
        fp.write(str(s) + '\n')


def mhclo(rel):
    d = os.path.join(U, *rel.split('/'))
    return [os.path.join(d, n) for n in os.listdir(d) if n.endswith('.mhclo')][0]


PARTS = [('Eyes', 'eyes/low-poly'), ('Eyebrows', 'eyebrows/eyebrow001'), ('Eyelashes', 'eyelashes/eyelashes01')]
HAIRS = ['short01', 'short02', 'short03', 'short04', 'afro01']


def base_macro():
    d = dict(TargetService.get_default_macro_info_dict())
    d.update(gender=1.0, age=0.5, muscle=0.5, weight=0.5, height=0.5, proportions=0.5)
    d['race'] = {'asian': 1 / 3, 'african': 1 / 3, 'caucasian': 1 / 3}
    return d


def build(macro):
    """骨 → 部品（骨の重みが付く順）"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    h = HumanService.create_human(macro_detail_dict=macro)
    HumanService.add_builtin_rig(h, 'game_engine')
    parts = {}
    for kind, rel in PARTS:
        parts[rel.split('/')[0]] = HumanService.add_mhclo_asset(mhclo(rel), h, asset_type=kind, subdiv_levels=0)
    for hn in HAIRS:
        parts['hair_' + hn] = HumanService.add_mhclo_asset(mhclo('hair/' + hn), h, asset_type='Hair', subdiv_levels=0)
    return h, h.parent, parts


def body_positions(h):
    """形の調整（シェイプキー）を反映した体の頂点の位置（骨・隠す処理は外して）"""
    states = [(m, m.show_viewport) for m in h.modifiers]
    for m, _ in states:
        m.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    ev = h.evaluated_get(dg)
    me = ev.to_mesh()
    co = [tuple(v.co) for v in me.vertices]
    ev.to_mesh_clear()
    for m, s in states:
        m.show_viewport = s
    return co


def part_positions(o):
    return [tuple(v.co) for v in o.data.vertices]


def bone_points(rig):
    return [tuple(b.head_local) + tuple(b.tail_local) for b in rig.data.bones]


# ───────── 基準の人 ─────────
h, rig, parts = build(base_macro())
bones = [b.name for b in rig.data.bones]
bone_index = {n: i for i, n in enumerate(bones)}
log(f'bones {len(bones)}')

# 体の頂点：「body」の頂点だけ（目・歯・まつ毛の補助の形は除く）
body_g = h.vertex_groups['body'].index
keep = [any(g.group == body_g for g in v.groups) for v in h.data.vertices]
faces = [p for p in h.data.polygons if all(keep[i] for i in p.vertices)]
used = sorted({i for p in faces for i in p.vertices})
remap = {old: new for new, old in enumerate(used)}
log(f'body verts {len(used)} faces {len(faces)}')


def weights_of(obj, vidx_list):
    """頂点ごとに重みの大きい骨4本"""
    gname = {g.index: g.name for g in obj.vertex_groups}
    out = []
    for vi in vidx_list:
        v = obj.data.vertices[vi]
        ws = [(bone_index[gname[g.group]], g.weight) for g in v.groups if gname.get(g.group) in bone_index and g.weight > 1e-4]
        ws.sort(key=lambda x: -x[1])
        ws = ws[:4]
        s = sum(w for _, w in ws) or 1.0
        ws = [(b, w / s) for b, w in ws] + [(0, 0.0)] * (4 - len(ws))
        out.append(ws)
    return out


def tri_uv(obj, faces_list, remap_fn):
    """三角形の番号と、頂点ごとの UV（UV の継ぎ目では頂点を分ける）"""
    uvl = obj.data.uv_layers.active.data
    verts = []  # (元の頂点, u, v)
    key = {}
    idx = []
    for p in faces_list:
        loop = list(p.loop_indices)
        ids = []
        for li in loop:
            vi = obj.data.loops[li].vertex_index
            u, v = uvl[li].uv
            k = (vi, round(u, 5), round(v, 5))
            if k not in key:
                key[k] = len(verts)
                verts.append(k)
            ids.append(key[k])
        for t in range(1, len(ids) - 1):
            idx += [ids[0], ids[t], ids[t + 1]]
    return verts, idx


blob = bytearray()


def put(b):
    global blob
    while len(blob) % 4:
        blob.append(0)
    off = len(blob)
    blob += b
    return off, len(b)


def pack_part(name, obj, faces_list, vsel):
    verts, idx = tri_uv(obj, faces_list, None)
    src = [v[0] for v in verts]
    w = weights_of(obj, src)
    pos = body_positions(obj) if obj == h else part_positions(obj)
    P = b''.join(struct.pack('<3f', *pos[s]) for s in src)
    UV = b''.join(struct.pack('<2f', v[1], v[2]) for v in verts)
    JW = b''.join(struct.pack('<4B4B', *[j for j, _ in ww], *[max(0, min(255, round(x * 255))) for _, x in ww]) for ww in w)
    I = struct.pack(f'<{len(idx)}H', *idx)
    assert len(verts) < 65536
    mats = [m.name for m in obj.data.materials if m]
    tex = None
    for m in obj.data.materials:
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image:
                    tex = bpy.path.abspath(n.image.filepath)
                    break
    log(f'part {name} verts {len(verts)} tris {len(idx)//3} tex {tex}')
    return dict(name=name, src=src, count=len(verts), pos=put(P), uv=put(UV), jw=put(JW), idx=put(I), tris=len(idx) // 3, tex=tex)


meta_parts = [pack_part('body', h, faces, used)]
for k, o in parts.items():
    meta_parts.append(pack_part(k, o, list(o.data.polygons), None))
base_pos = {'body': body_positions(h)}
for k, o in parts.items():
    base_pos[k] = part_positions(o)
base_bones = bone_points(rig)
bone_meta = [dict(name=b.name, parent=bone_index[b.parent.name] if b.parent else -1, head=list(b.head_local), tail=list(b.tail_local),
                  matrix=[list(r) for r in b.matrix_local]) for b in rig.data.bones]

# ───────── 差分 ─────────
deltas = []


def record(name, pos_by_part, bones_now):
    entry = dict(name=name, parts={})
    for mp in meta_parts:
        pn = mp['name']
        cur, base = pos_by_part[pn], base_pos[pn]
        d = []
        for ni, s in enumerate(mp['src']):
            dx, dy, dz = cur[s][0] - base[s][0], cur[s][1] - base[s][1], cur[s][2] - base[s][2]
            if abs(dx) + abs(dy) + abs(dz) > 2e-5:
                d.append((ni, dx, dy, dz))
        if not d:
            continue
        mx = max(max(abs(a), abs(b), abs(c)) for _, a, b, c in d) or 1e-6
        sc = mx / 32767
        data = struct.pack(f'<{len(d)}H', *[x[0] for x in d]) + b''.join(struct.pack('<3h', round(a / sc), round(b / sc), round(c / sc)) for _, a, b, c in d)
        entry['parts'][pn] = dict(n=len(d), scale=sc, data=put(data))
    bd = [c - b for cur, base in zip(bones_now, base_bones) for c, b in zip(cur, base)]
    entry['bones'] = put(struct.pack(f'<{len(bd)}f', *bd))
    deltas.append(entry)
    log(f'delta {name} parts={list(entry["parts"].keys())}')


def snapshot(hh, rr, pp):
    pos = {'body': body_positions(hh)}
    for k, o in pp.items():
        pos[k] = part_positions(o)
    return pos, bone_points(rr)


# 体格の大きな調整（作り直して測る）
MACROS = [('muscle-', dict(muscle=0.0)), ('muscle+', dict(muscle=1.0)), ('weight-', dict(weight=0.0)), ('weight+', dict(weight=1.0)),
          ('height-', dict(height=0.0)), ('height+', dict(height=1.0)),
          ('age-', dict(age=0.34)), ('age+', dict(age=0.75)),
          ('race-asian', dict(race={'asian': 1.0, 'african': 0.0, 'caucasian': 0.0})), ('race-african', dict(race={'asian': 0.0, 'african': 1.0, 'caucasian': 0.0})),
          ('race-caucasian', dict(race={'asian': 0.0, 'african': 0.0, 'caucasian': 1.0}))]
for name, ch in MACROS:
    m = base_macro()
    m.update(ch)
    hh, rr, pp = build(m)
    pos, bn = snapshot(hh, rr, pp)
    record(name, pos, bn)

# 細かい調整（基準の人に1つずつ足して、骨と部品を合わせ直して測る）
h, rig, parts = build(base_macro())
TD = os.path.join(SYS, 'targets')
all_targets = {}
for d in os.listdir(TD):
    p = os.path.join(TD, d)
    if os.path.isdir(p):
        for n in os.listdir(p):
            if n.endswith('.target.gz'):
                all_targets[n[:-10]] = os.path.join(p, n)
PAIRS = [('decr', 'incr'), ('down', 'up'), ('in', 'out'), ('backward', 'forward'), ('less', 'more'), ('compress', 'uncompress'), ('concave', 'convex'), ('narrow', 'wide'), ('close', 'open')]
DETAILS = [
    # 体
    'measure-bust-circ', 'measure-waist-circ', 'measure-hips-circ', 'measure-shoulder-dist', 'measure-napetowaist-dist', 'torso-scale-depth',
    'measure-upperarm-length', 'measure-lowerarm-length', 'measure-upperarm-circ', 'lowerarm-muscle', 'upperarm-muscle', 'upperleg-muscle', 'lowerleg-muscle',
    'measure-neck-circ', 'measure-neck-height', 'buttocks-volume', 'stomach-pregnant',
    # 顔
    'head-scale-horiz', 'head-scale-vert', 'head-scale-depth', 'head-fat', 'head-oval', 'head-round', 'head-square', 'head-triangular',
    'nose-scale-horiz', 'nose-scale-vert', 'nose-scale-depth', 'nose-hump', 'nose-curve', 'nose-point-width', 'nose-nostrils-width', 'nose-trans',
    'mouth-scale-horiz', 'mouth-lowerlip-volume', 'mouth-upperlip-volume', 'mouth-trans',
    'eye-scale', 'eye-trans', 'eye-height2', 'eye-epicanthus', 'eye-corner1', 'eye-bag',
    'chin-width', 'chin-prominent', 'chin-height', 'chin-bones', 'cheek-bones', 'cheek-volume', 'ear-scale', 'ear-flap',
    'forehead-scale-vert', 'forehead-nubian', 'eyebrows-trans', 'eyebrows-angle',
]


def files_for(feature):
    """(負の向きのファイル群, 正の向きのファイル群, 単独のファイル群)。左右（l-・r-）は一緒に"""
    for neg, pos in PAIRS:
        fn = [all_targets[k] for k in (f'{feature}-{neg}', f'l-{feature}-{neg}', f'r-{feature}-{neg}') if k in all_targets]
        fp = [all_targets[k] for k in (f'{feature}-{pos}', f'l-{feature}-{pos}', f'r-{feature}-{pos}') if k in all_targets]
        if fn or fp:
            return fn, fp, []
    single = [all_targets[k] for k in (feature, f'l-{feature}', f'r-{feature}') if k in all_targets]
    return [], [], single


def apply_measure(paths, label):
    keys = [TargetService.load_target(h, p, weight=1.0, name=f'tmp{i}') for i, p in enumerate(paths)]
    HumanService.refit(h)
    pos, bn = snapshot(h, rig, parts)
    record(label, pos, bn)
    for k in keys:
        h.shape_key_remove(k)
    HumanService.refit(h)


for feat in DETAILS:
    fn, fp, single = files_for(feat)
    if fn:
        apply_measure(fn, feat + '-')
    if fp:
        apply_measure(fp, feat + '+')
    if single:
        apply_measure(single, feat + '+')
    if not (fn or fp or single):
        log('MISSING ' + feat)

# ───────── 画像（スマホ向けに縮める） ─────────
def save_small(src, dst, size):
    img = bpy.data.images.load(src)
    if max(img.size) > size:
        img.scale(size, size)
    img.filepath_raw = dst
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


texmap = {}
for mp in meta_parts:
    if mp['tex'] and os.path.exists(mp['tex']):
        dst = f'{mp["name"]}.png'
        save_small(mp['tex'], os.path.join(OUT, dst), 512 if mp['name'] != 'eyes' else 256)
        texmap[mp['name']] = dst
skins = {}
for age in ['young', 'middleage', 'old']:
    for race in ['asian', 'african', 'caucasian']:
        name = f'{age}_{race}_male'
        d = os.path.join(U, 'skins', name)
        mat = os.path.join(d, name + '.mhmat')
        if not os.path.exists(mat):
            continue
        tex = None
        for line in open(mat, encoding='utf8', errors='ignore'):
            if line.startswith('diffuseTexture'):
                tex = os.path.join(d, os.path.basename(line.split()[1]))
        if tex and os.path.exists(tex):
            save_small(tex, os.path.join(OUT, f'skin_{age}_{race}.png'), 1024)
            skins[f'{age}_{race}'] = f'skin_{age}_{race}.png'

meta = dict(
    version=1, up='Z', forward='-Y', bones=bone_meta,
    parts=[{k: v for k, v in mp.items() if k not in ('src', 'tex')} | {'tex': texmap.get(mp['name'])} for mp in meta_parts],
    deltas=deltas, skins=skins,
)
js = json.dumps(meta, ensure_ascii=False).encode('utf8')
head = b'TBDY' + struct.pack('<II', 1, len(js)) + js
while len(head) % 4:
    head += b'\0'
with open(os.path.join(OUT, 'body.bin'), 'wb') as f:
    f.write(struct.pack('<I', len(head)))  # データの始まり（この 4バイトの後ろからの位置）
    f.write(head)
    f.write(blob)
open(os.path.join(OUT, 'export_log.txt'), 'w', encoding='utf8').write('\n'.join(LOG))
