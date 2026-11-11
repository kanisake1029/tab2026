# MPFB の人体を作って、体格の数値を変えた見本を描き出す（試し）
import bpy, sys, math, os
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

OUT = sys.argv[sys.argv.index('--') + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
info = TargetService.get_default_macro_info_dict()
log = [str(info)]
xs = []
for i, (muscle, weight, height, race) in enumerate([(0.5, 0.5, 0.5, 'asian'), (0.9, 0.6, 0.7, 'african'), (0.4, 0.9, 0.4, 'caucasian')]):
    d = dict(info)
    d['gender'] = 1.0
    d['age'] = 0.5
    d['muscle'] = muscle
    d['weight'] = weight
    d['height'] = height
    d['race'] = {'asian': 0.0, 'african': 0.0, 'caucasian': 0.0}
    d['race'][race] = 1.0
    h = HumanService.create_human(macro_detail_dict=d)
    h.location.x = i * 0.9
    HumanService.add_builtin_rig(h, 'game_engine')
    log.append(f'{h.name} verts={len(h.data.vertices)} dims={tuple(round(v,3) for v in h.dimensions)}')
# カメラと光
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
bpy.context.scene.collection.objects.link(cam)
cam.location = (0.9, -6.0, 1.0)
cam.rotation_euler = (math.radians(90), 0, 0)
cam.data.lens = 50
bpy.context.scene.camera = cam
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
sun.data.energy = 3
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
bpy.context.scene.collection.objects.link(sun)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x, sc.render.resolution_y = 900, 900
sc.world = bpy.data.worlds.new('w'); sc.world.color = (0.6, 0.65, 0.7)
sc.render.filepath = OUT + '.png'
bpy.ops.render.render(write_still=True)
open(OUT + '.txt', 'w', encoding='utf8').write('\n'.join(log))
