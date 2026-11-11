"""選手の顔アイコンのセットを、ローカルの ComfyUI（Animagine XL 4.0）で作る。

使い方（ComfyUI を --listen 127.0.0.1 --port 8188 で起動しておく）:
    python gen_faces.py --start 0 --count 8 --out <出力フォルダ>
各画像の特徴（年齢・肌・髪型・髪の色・ひげ・メガネ・輪郭・表情）は faces.json に書く。アプリはこの特徴で、選手の顔データに近い顔を割り当てる。
架空の人物だけ。実在の選手・既存の作品のキャラクターには似せない（キャラクター名・作品名は入れない）。
"""
import argparse
import json
import os
import random
import time
import urllib.request

API = 'http://127.0.0.1:8188'
CKPT = 'animagine-xl-4.0-opt.safetensors'

SKINS = [('asian', 0.78, 'japanese, east asian, light skin'), ('tan', 0.08, 'tan skin'), ('dark', 0.07, 'dark skin, dark-skinned male'), ('white', 0.07, 'pale skin')]
AGES = [('young', 0.35, 'man in his early 20s'), ('prime', 0.40, 'man in his late 20s'), ('veteran', 0.25, 'man in his late 30s, slight wrinkles')]
# アプリの髪型（FaceLook.hairStyle）：0 短髪 1 スポーツ刈り 2 もみあげ長め 3 アフロ 4 襟足長め 5 坊主 6 ツンツン 7 ウェーブ長髪
HAIRS = [(0, 'short hair, sporty haircut, forehead'), (1, 'very short hair, crew cut, forehead'), (2, 'short hair, sideburns, forehead'), (3, 'short afro'), (4, 'short hair, nape hair'), (5, 'buzz cut, shaved head'), (6, 'short spiked hair, forehead'), (7, 'short wavy hair')]
BEARDS = [(0, 0.55, ''), (1, 0.15, 'stubble'), (2, 0.08, 'goatee'), (3, 0.06, 'mustache'), (4, 0.06, 'mustache, goatee'), (5, 0.10, 'full beard')]
FACES = [(0, 'round face'), (1, 'slim face'), (2, 'square jaw'), (3, 'long face')]
EXPR = ['closed mouth, serious', 'expressionless, closed mouth', 'light smile', 'grin', 'closed mouth, determined', 'smile']
NEG = ('lowres, bad anatomy, bad hands, text, error, missing fingers, extra digits, fewer digits, cropped, worst quality, low quality, '
       'low score, bad score, average score, signature, watermark, username, blurry, female, 1girl, multiple boys, hat, baseball cap, helmet, long hair, medium hair, bob cut, bangs, hair over eyes, hair between eyes, bishounen, pretty boy, handsome, beautiful man, idol, rugged, muscular, old man, elderly, teenager, child, chibi, glasses, eyewear, baseball uniform, jersey, pinstripes, delicate features, androgynous, slim, large eyes, sparkling eyes, long eyelashes, makeup, shiny hair, '
       'jpeg artifacts, sketch, monochrome, letters, logo, english text, gradient background, dark background, close-up, face focus, cropped head, out of frame, dutch angle, from above, dramatic lighting')


def pick(r, items):
    x = r.random() * sum(i[1] for i in items)
    for i in items:
        x -= i[1]
        if x < 0:
            return i
    return items[-1]


def traits(i):
    r = random.Random(1000 + i * 7919)
    skin = pick(r, SKINS)
    age = pick(r, AGES)
    hw = {'asian': [3, 3, 0.6, 0, 0.3, 2, 0.4, 0.1], 'tan': [3, 2, 1, 0.5, 0.5, 1.5, 0.5, 0.5], 'dark': [1, 2, 0.3, 2, 0.2, 3, 0.5, 0.2], 'white': [3, 1.5, 1, 0, 0.6, 1, 0.5, 0.8]}[skin[0]]
    hair = pick(r, [(h[0], hw[h[0]], h[1]) for h in HAIRS])
    if skin[0] == 'asian':
        color = pick(r, [('black', 0.8, 'black hair'), ('dark_brown', 0.15, 'dark brown hair'), ('brown', 0.05, 'brown hair')])
    elif skin[0] == 'white':
        color = pick(r, [('blonde', 0.35, 'blonde hair'), ('brown', 0.45, 'brown hair'), ('black', 0.2, 'black hair')])
    else:
        color = pick(r, [('black', 0.8, 'black hair'), ('dark_brown', 0.2, 'dark brown hair')])
    bw = [b[1] * (1.6 if age[0] == 'veteran' and b[0] else 1) * (0.4 if age[0] == 'young' and b[0] else 1) for b in BEARDS]
    beard = pick(r, [(b[0], w, b[2]) for b, w in zip(BEARDS, bw)])
    glasses = False  # 試合でメガネはかけない
    face = FACES[r.randrange(len(FACES))]
    expr = EXPR[r.randrange(len(EXPR))]
    grey = age[0] == 'veteran' and r.random() < 0.2
    return {
        'i': i, 'skin': skin[0], 'age': age[0], 'hairStyle': hair[0], 'hairColor': 'grey' if grey else color[0],
        'beard': beard[0], 'glasses': glasses, 'face': face[0], 'expr': expr,
        'prompt': ', '.join(t for t in [
            '1boy, male focus, solo, upper body, looking at viewer, straight-on, centered, semi-realistic, japanese baseball player, ordinary man, average-looking, plain face, modest, unremarkable, natural skin texture, small eyes, subtle features', age[2], skin[2], hair[2],
            'grey hair' if grey else color[2], beard[2], '', face[1], expr,
            'wearing plain bright green t-shirt, chroma key green shirt, solid green clothes, crew neck', 'plain white background, simple background, soft lighting',
            'masterpiece, high score, great score, absurdres'] if t),
        'seed': r.randrange(1 << 31),
    }


def workflow(t):
    return {
        '1': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': CKPT}},
        '2': {'class_type': 'CLIPTextEncode', 'inputs': {'text': t['prompt'], 'clip': ['1', 1]}},
        '3': {'class_type': 'CLIPTextEncode', 'inputs': {'text': NEG, 'clip': ['1', 1]}},
        '4': {'class_type': 'EmptyLatentImage', 'inputs': {'width': 832, 'height': 1216, 'batch_size': 1}},
        '5': {'class_type': 'KSampler', 'inputs': {'model': ['1', 0], 'positive': ['2', 0], 'negative': ['3', 0], 'latent_image': ['4', 0],
                                                   'seed': t['seed'], 'steps': 28, 'cfg': 5.0, 'sampler_name': 'euler_ancestral', 'scheduler': 'normal', 'denoise': 1.0}},
        '6': {'class_type': 'VAEDecode', 'inputs': {'samples': ['5', 0], 'vae': ['1', 2]}},
        '7': {'class_type': 'SaveImage', 'inputs': {'images': ['6', 0], 'filename_prefix': f"face_{t['i']:04d}"}},
    }


def post(path, data):
    req = urllib.request.Request(API + path, data=json.dumps(data).encode(), headers={'Content-Type': 'application/json'})
    return json.loads(urllib.request.urlopen(req).read())


def get(path):
    return json.loads(urllib.request.urlopen(API + path).read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--start', type=int, default=0)
    ap.add_argument('--count', type=int, default=8)
    ap.add_argument('--out', required=True)  # ComfyUI の output フォルダ
    a = ap.parse_args()
    meta_path = os.path.join(a.out, 'faces.json')
    meta = json.load(open(meta_path, encoding='utf-8')) if os.path.exists(meta_path) else {}
    for i in range(a.start, a.start + a.count):
        t = traits(i)
        if str(i) in meta and os.path.exists(os.path.join(a.out, meta[str(i)]['file'])):
            continue
        pid = post('/prompt', {'prompt': workflow(t)})['prompt_id']
        t0 = time.time()
        while True:
            h = get('/history/' + pid)
            if pid in h:
                break
            time.sleep(0.5)
        img = h[pid]['outputs']['7']['images'][0]['filename']
        t['file'] = img
        meta[str(i)] = t
        json.dump(meta, open(meta_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        print(f"{i} {img} {time.time() - t0:.1f}s", flush=True)


if __name__ == '__main__':
    main()
