"""顔の切り抜き（一覧画像とアイコンの書き出しで共通）"""
from PIL import Image


def face_box(img):
    """背景（四隅の色）と違う色の所を人物として、頭のてっぺんと頭の幅から、顔を中心にした正方形と背景色を返す"""
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
    if not lefts:
        return (0, 0, img.width, img.width), bg
    lefts.sort()
    rights.sort()
    l, r = lefts[len(lefts) // 2], rights[len(rights) // 2]
    head = r - l
    side = head * 1.35
    cx = (l + r) / 2
    cy = top + head * 0.72  # 顔の中心（頭のてっぺんから頭の幅の約7割下）
    return tuple(int(v * 4) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2)), bg


def face_crop(img, size):
    """顔を中心にした正方形（はみ出した所は背景の色）"""
    box, bgc = face_box(img)
    ox, oy = img.width // 2, img.height // 2
    pad = Image.new('RGB', (img.width * 2, img.height * 2), bgc)
    pad.paste(img, (ox, oy))
    return pad.crop((box[0] + ox, box[1] + oy, box[2] + ox, box[3] + oy)).resize((size, size), Image.LANCZOS)
