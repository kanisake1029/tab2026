"""生成した顔の一覧画像（元の絵と、丸いアイコンに切り抜いた絵）を作る。
    python sheet.py <ComfyUI の output> <出力 png> [開始] [数]
"""
import json
import os
import sys

from PIL import Image, ImageDraw

out_dir, dst = sys.argv[1], sys.argv[2]
start = int(sys.argv[3]) if len(sys.argv) > 3 else 0
count = int(sys.argv[4]) if len(sys.argv) > 4 else 8
meta = json.load(open(os.path.join(out_dir, 'faces.json'), encoding='utf-8'))
ids = [str(i) for i in range(start, start + count) if str(i) in meta]
T = 256


def face_box(img):
    """背景（四隅の色）と違う色の所を人物として、頭のてっぺんと頭の幅から、顔を中心にした正方形を返す"""
    g = img.convert('RGB').resize((img.width // 4, img.height // 4))
    w, h = g.size
    px = g.load()
    corners = [px[1, 1], px[w - 2, 1]]
    bg = tuple(sum(c[i] for c in corners) // 2 for i in range(3))
    def ink(x, y):
        p = px[x, y]
        return abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2]) > 60
    top = 0
    for y in range(h):
        if sum(1 for x in range(w) if ink(x, y)) > w * 0.04:
            top = y
            break
    lefts, rights = [], []
    for y in range(top + int(h * 0.04), min(h, top + int(h * 0.20))):
        xs = [x for x in range(w) if ink(x, y)]
        if xs:
            lefts.append(xs[0])
            rights.append(xs[-1])
    lefts.sort()
    rights.sort()
    l, r = lefts[len(lefts) // 2], rights[len(rights) // 2]
    head = r - l
    side = head * 1.35
    cx = (l + r) / 2
    cy = top + head * 0.72  # 顔の中心（頭のてっぺんから頭の幅の約7割下）
    return tuple(int(v * 4) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2)), bg


def icon(img, size):
    box, bgc = face_box(img)
    pad = Image.new('RGB', (img.width * 2, img.height * 2), bgc)  # はみ出した所は背景の色
    pad.paste(img, (img.width // 2, img.height // 2))
    face = pad.crop(tuple(v + (img.width // 2 if k % 2 == 0 else img.height // 2) for k, v in enumerate(box))).resize((size, size), Image.LANCZOS)
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    bg = Image.new('RGB', (size, size), (238, 241, 245))
    bg.paste(face, (0, 0), mask)
    return bg


cols = 4
rows = (len(ids) + cols - 1) // cols
sheet = Image.new('RGB', (cols * T * 2, rows * T), (255, 255, 255))
for k, i in enumerate(ids):
    img = Image.open(os.path.join(out_dir, meta[i]['file'])).convert('RGB')
    x, y = (k % cols) * T * 2, (k // cols) * T
    sheet.paste(img.resize((T * 832 // 1216, T), Image.LANCZOS), (x, y))
    sheet.paste(icon(img, 160), (x + T + 48, y + 48))
sheet.save(dst)
print(dst, len(ids))
