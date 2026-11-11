"""生成した顔を、アプリに入れる2枚の小さな画像（128px の正方形 webp。丸くはアプリで切る）と特徴の一覧にする。
  f0000.webp   ：顔・髪・首（背景と緑のシャツは透明）
  f0000_s.webp ：シャツの陰影（白〜灰色。透明でない所がシャツ）。アプリが球団の色をかけてユニフォームにする
    python export_icons.py <ComfyUI の output> <アプリの assets/faces> [見本の png]
"""
import colorsys
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from sheet_lib import face_box  # noqa: E402

SIZE = 128


def crop_bust(img):
    """頭から肩まで（顔の正方形を広げる）。はみ出した所は背景の色"""
    box, bgc = face_box(img)
    side = (box[2] - box[0]) * 1.75
    cx = (box[0] + box[2]) / 2
    top = box[1] - side * 0.04
    b = (int(cx - side / 2), int(top), int(cx + side / 2), int(top + side))
    ox, oy = img.width, img.height
    pad = Image.new('RGB', (img.width * 3, img.height * 3), bgc)
    pad.paste(img, (ox, oy))
    return pad.crop((b[0] + ox, b[1] + oy, b[2] + ox, b[3] + oy)).resize((SIZE, SIZE), Image.LANCZOS), bgc


def split(img, bgc):
    """背景（四隅の色に近い所）と緑のシャツを分ける。縁はなめらかに"""
    face = Image.new('RGBA', img.size)
    shirt = Image.new('RGBA', img.size)
    fp, sp, src = face.load(), shirt.load(), img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = src[x, y]
            hh, ss, vv = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            dist = abs(r - bgc[0]) + abs(g - bgc[1]) + abs(b - bgc[2])
            bg_a = max(0.0, min(1.0, (dist - 18) / 40))  # 背景らしさの逆（0＝背景）
            green = 45 / 360 <= hh <= 175 / 360 and ss > 0.12 and vv > 0.10
            if green and y > h * 0.35:
                shade = int(150 + 105 * min(1.0, vv / 0.85))  # シャツの陰影（明るいほど白）
                sp[x, y] = (shade, shade, shade, int(255 * bg_a))
                fp[x, y] = (0, 0, 0, 0)
            else:
                fp[x, y] = (r, g, b, int(255 * bg_a))
    return face, shirt


def main():
    src, dst = sys.argv[1], sys.argv[2]
    preview = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(dst, exist_ok=True)
    meta = json.load(open(os.path.join(src, 'faces.json'), encoding='utf-8'))
    out = []
    samples = []
    skipped = 0
    for k in sorted(meta, key=int):
        t = meta[k]
        p = os.path.join(src, t['file'])
        if not os.path.exists(p):
            continue
        img = Image.open(p).convert('RGB')
        box, bgc0 = face_box(img)
        # 背景が白くない（顔が画面いっぱい・背景に色）か、頭が大きすぎる絵は切り分けられないので使わない
        if sum(bgc0) < 3 * 215 or (box[2] - box[0]) > img.width * 0.85:
            skipped += 1
            continue
        bust, bgc = crop_bust(img)
        face, shirt = split(bust, bgc)
        name = f"f{int(k):04d}"
        face.save(os.path.join(dst, name + '.webp'), 'WEBP', quality=85, method=6)
        shirt.save(os.path.join(dst, name + '_s.webp'), 'WEBP', quality=70, method=6)
        out.append({'id': name, 'skin': t['skin'], 'age': t['age'], 'hair': t['hairStyle'], 'color': t['hairColor'], 'beard': t['beard'], 'glasses': t['glasses'], 'face': t['face']})
        if preview and len(samples) < 16:
            samples.append((face, shirt))
    json.dump(out, open(os.path.join(dst, 'faces.json'), 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    print(len(out), 'faces ->', dst, 'skipped', skipped)
    if preview:
        # 見本：球団の色（オレンジ・紺・赤・緑）をかけて丸く
        from PIL import ImageDraw
        colors = [(242, 169, 0), (30, 58, 138), (220, 38, 38), (22, 163, 74)]
        sheet = Image.new('RGB', (len(samples) * 140, 140), (255, 255, 255))
        for i, (face, shirt) in enumerate(samples):
            c = colors[i % 4]
            base = Image.new('RGBA', (SIZE, SIZE), (226, 232, 240, 255))
            tint = Image.new('RGBA', (SIZE, SIZE), c + (255,))
            sh = Image.composite(Image.blend(tint, Image.merge('RGBA', (*shirt.split()[:3], Image.new('L', (SIZE, SIZE), 255))), 0.0), base, shirt.split()[3])
            # 陰影を掛ける
            px, spx = sh.load(), shirt.load()
            for y in range(SIZE):
                for x in range(SIZE):
                    a = spx[x, y][3]
                    if a:
                        f = spx[x, y][0] / 255
                        px[x, y] = tuple(int(c[j] * f) for j in range(3)) + (255,)
            sh.alpha_composite(face)
            mask = Image.new('L', (SIZE, SIZE), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, SIZE - 1, SIZE - 1), fill=255)
            sheet.paste(sh.convert('RGB'), (i * 140 + 6, 6), mask)
        sheet.save(preview)
        print('preview', preview)


if __name__ == '__main__':
    main()
