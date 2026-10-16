# 正式キャラクター 3 モードの再現と原画を並べた比較画像を作る（2026-10-16 H2 の前提作業 1。アプリのコードではない）
# 使い方: python tools/character_3modes/make_comparison.py docs/design-reference/characters/official-3modes
#   → official-3modes/reproduction/ に
#      comparison.png      原画の「立つ」・再現・重ね合わせ（赤＝再現の線）を 3 モードぶん。
#                          亀は「立つ」を左右反転して並べる（甲羅は正式に見る人から見て左。「立つ」は右に描かれている）
#      reproduction-36pt.png  3 モードを本体 36pt（画面の 3 倍の画素）で並べたもの
#      stand-*.png         原画の「主なポーズ・動作例」の「立つ」の切り出し（原画の画素のまま）
# 原画（timycue-character-3modes.webp）は変えない
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps
sys.path.insert(0, str(Path(__file__).resolve().parent))
import shapes

src = Path(sys.argv[1])
out = src / "reproduction"
out.mkdir(parents=True, exist_ok=True)
crops = shapes.crop_standing(src / "timycue-character-3modes.webp")
for mode, im in crops.items():
    im.save(out / f"stand-{mode}.png")

K = 2
BOX = (-8, -22, 87, 100)
BG = (250, 245, 236, 255)
# 原画の切り出しを再現と同じ座標に置く。亀は人型と同じ縮尺で、横に 0.9 画素ずれている。
# 亀は甲羅の側を正式（見る人から見て左）に合わせて左右反転する。反転すると本体の中心が切り出しの x = 48.85 に来るので -3.6 ずらす。
# うさぎの「立つ」は耳の分だけ 0.82 倍で描かれているので、フードの中心 (41.6, 55.8) を頭の中心へ合わせて 1/0.82 倍にする
PLACE = {"turtle": (1.0, (-3.6, 0.2)), "human": (1.0, (0.0, 0.0)), "rabbit": (0.82, None)}
MIRROR = {"turtle"}


def placed(mode):
    im = crops[mode].convert("RGBA")
    if mode in MIRROR:
        im = ImageOps.mirror(im)
    scale, offset = PLACE[mode]
    canvas = Image.new("RGBA", ((BOX[2] - BOX[0]) * K, (BOX[3] - BOX[1]) * K), BG)
    if offset is None:
        f = K / scale
        im = im.resize((round(im.width * f), round(im.height * f)), Image.LANCZOS)
        ox = (45.25 - 41.6 / scale - BOX[0]) * K
        oy = (40.03 - 55.8 / scale - BOX[1]) * K
    else:
        im = im.resize((im.width * K, im.height * K), Image.LANCZOS)
        ox, oy = (offset[0] - BOX[0]) * K, (offset[1] - BOX[1]) * K
    canvas.alpha_composite(im, (round(ox), round(oy)))
    return canvas


def overlay(original, reproduction):
    base = Image.blend(original.convert("L").convert("RGBA"), Image.new("RGBA", original.size, (255, 255, 255, 255)), 0.45)
    a = np.asarray(reproduction).copy()
    lines = (a[..., 3] > 0) & (a[..., :3].mean(2) < 120)
    red = np.zeros_like(a)
    red[lines] = (220, 40, 40, 230)
    base.alpha_composite(Image.fromarray(red, "RGBA"))
    return base


def font(size):
    for path in ["/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf", "C:/Windows/Fonts/YuGothM.ttc"]:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


rows = []
for mode, label in [("turtle", "亀モード"), ("human", "人型モード"), ("rabbit", "うさぎモード")]:
    original = placed(mode)
    drawn = shapes.render(mode, BOX, K)
    on_bg = Image.new("RGBA", original.size, BG)
    on_bg.alpha_composite(drawn)
    rows.append((label, [original, on_bg, overlay(original, drawn)]))
W, H = rows[0][1][0].size
sheet = Image.new("RGBA", (W * 3 + 40, (H + 40) * 3 + 50), (255, 255, 255, 255))
d = ImageDraw.Draw(sheet)
for i, title in enumerate(["原画（立つ。亀は左右反転）", "再現（アプリと同じ形）", "重ね合わせ（赤＝再現の線）"]):
    d.text((10 + i * (W + 15), 14), title, fill=(60, 40, 30), font=font(15))
for r, (label, images) in enumerate(rows):
    y = 50 + r * (H + 40)
    d.text((10, y), label, fill=(60, 40, 30), font=font(22))
    for i, im in enumerate(images):
        sheet.alpha_composite(im, (10 + i * (W + 15), y + 30))
sheet.convert("RGB").save(out / "comparison.png")

# 本体 36pt（画面の 3 倍の画素 = 108 画素）で 3 モードを並べる。足元をそろえる
px = 36 * 3 / shapes.body_height()
figures = [shapes.render(m, BOX, px) for m in ["turtle", "human", "rabbit"]]
strip = Image.new("RGBA", (sum(f.width for f in figures) + 40 * 4, figures[0].height + 40), BG)
x = 40
for f in figures:
    strip.alpha_composite(f, (x, 20))
    x += f.width + 40
strip.convert("RGB").save(out / "reproduction-36pt.png")
print("saved", out)
