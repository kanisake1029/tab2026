# 素材付きの見本（肌・目・眉・まつ毛・髪）。体格の違う3人
import bpy, sys, math, os
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.locationservice import LocationService

OUT = sys.argv[sys.argv.index('--') + 1]
U = LocationService.get_user_data()
def f(*p):
    return os.path.join(U, *p)
def mhclo(dirname):
    d = f(*dirname.split('/'))
    for n in os.listdir(d):
        if n.endswith('.mhclo'):
            return os.path.join(d, n)
bpy.ops.wm.read_factory_settings(use_empty=True)
log = []
people = [
    dict(muscle=0.55, weight=0.55, height=0.55, race='asian', skin='young_asian_male', hair='short02', brow='eyebrow001'),
    dict(muscle=0.85, weight=0.6, height=0.75, race='african', skin='young_african_male', hair='short04', brow='eyebrow007'),
    dict(muscle=0.45, weight=0.85, height=0.45, race='caucasian', skin='young_caucasian_male', hair='short03', brow='eyebrow010'),
]
for i, pp in enumerate(people):
    d = dict(TargetService.get_default_macro_info_dict())
    d.update(gender=1.0, age=0.5, muscle=pp['muscle'], weight=pp['weight'], height=pp['height'])
    d['race'] = {'asian': 0.0, 'african': 0.0, 'caucasian': 0.0}
    d['race'][pp['race']] = 1.0
    h = HumanService.create_human(macro_detail_dict=d)
    try:
        HumanService.set_character_skin(f('skins', pp['skin'], pp['skin'] + '.mhmat'), h, skin_type='ENHANCED_SSS')
    except Exception as e:
        log.append('skin ' + repr(e))
    for kind, name in [('Eyes', 'eyes/high-poly'), ('Eyebrows', 'eyebrows/' + pp['brow']), ('Eyelashes', 'eyelashes/eyelashes01'), ('Hair', 'hair/' + pp['hair'])]:
        try:
            HumanService.add_mhclo_asset(mhclo(name), h, asset_type=kind, subdiv_levels=0)
        except Exception as e:
            log.append(kind + ' ' + repr(e))
    HumanService.add_builtin_rig(h, 'game_engine')
    rig = h.parent
    (rig or h).location.x = (i - 1) * 0.75
    log.append(f'{h.name} dims={tuple(round(v,3) for v in h.dimensions)} children={[c.name for c in h.children]}')
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
bpy.context.scene.collection.objects.link(cam)
cam.location = (0, -7.5, 1.0)
cam.rotation_euler = (math.radians(90), 0, 0)
cam.data.lens = 55
bpy.context.scene.camera = cam
for rot, e in [((50, 10, 30), 3.0), ((60, 0, -140), 1.2)]:
    s = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
    s.data.energy = e
    s.rotation_euler = tuple(math.radians(a) for a in rot)
    bpy.context.scene.collection.objects.link(s)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x, sc.render.resolution_y = 1000, 1000
sc.world = bpy.data.worlds.new('w'); sc.world.color = (0.55, 0.6, 0.66)
sc.render.filepath = OUT + '_full.png'
bpy.ops.render.render(write_still=True)
cam.location = (0, -2.2, 1.68)
cam.data.lens = 85
sc.render.filepath = OUT + '_face.png'
bpy.ops.render.render(write_still=True)
open(OUT + '.txt', 'w', encoding='utf8').write('\n'.join(log))
