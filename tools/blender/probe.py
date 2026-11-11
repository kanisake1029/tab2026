import bpy, sys, os
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
OUT = sys.argv[sys.argv.index('--') + 1]
U = LocationService.get_user_data()
bpy.ops.wm.read_factory_settings(use_empty=True)
h = HumanService.create_human()
def mh(d):
    d = os.path.join(U, *d.split('/'))
    return [os.path.join(d, n) for n in os.listdir(d) if n.endswith('.mhclo')][0]
for kind, name in [('Eyes', 'eyes/low-poly'), ('Eyebrows', 'eyebrows/eyebrow001'), ('Eyelashes', 'eyelashes/eyelashes01'), ('Hair', 'hair/short02')]:
    HumanService.add_mhclo_asset(mh(name), h, asset_type=kind, subdiv_levels=0)
HumanService.add_builtin_rig(h, 'game_engine')
rig = h.parent
L = []
L.append('mods ' + str([(m.name, m.type) for m in h.modifiers]))
L.append('vgroups ' + str(len(h.vertex_groups)) + ' ' + ', '.join(g.name for g in h.vertex_groups if not g.name.startswith('joint-'))[:3000])
L.append('verts %d faces %d' % (len(h.data.vertices), len(h.data.polygons)))
L.append('uv ' + str([u.name for u in h.data.uv_layers]) + ' mats ' + str([m.name for m in h.data.materials]))
L.append('rig ' + str(rig.name if rig else None))
if rig:
    for b in rig.data.bones:
        L.append(f'  bone {b.name} parent={b.parent.name if b.parent else None} head={tuple(round(v,3) for v in b.head_local)} tail={tuple(round(v,3) for v in b.tail_local)}')
for c in h.children:
    L.append(f'child {c.name} verts={len(c.data.vertices)} mods={[m.type for m in c.modifiers]} vg={len(c.vertex_groups)} mats={[m.name for m in c.data.materials]}')
    for m in c.data.materials:
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image:
                    L.append('   tex ' + n.image.filepath + f' {n.image.size[0]}x{n.image.size[1]}')
for m in h.data.materials:
    if m and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                L.append(' bodytex ' + n.image.filepath)
open(OUT, 'w', encoding='utf8').write('\n'.join(L))
