"""仮のアプリアイコン（1024x1024、透明なし）を作る。正式なアイコンができたら差し替える。

使い方（Windows でも同じ）: python tools/make_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # 大きく描いてから縮めて、縁をなめらかにする
OUT = Path(__file__).resolve().parent.parent / "TimyCue/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

BACKGROUND = (250, 245, 236)  # ベージュ（仮）
FACE = (255, 253, 248)
RING = (233, 225, 212)
ARC = (244, 169, 106)  # 淡いオレンジ（仮）
HAND = (61, 55, 48)


def main() -> None:
    s = SIZE * SCALE
    img = Image.new("RGB", (s, s), BACKGROUND)
    d = ImageDraw.Draw(img)
    c = s // 2
    r = int(s * 0.34)
    d.ellipse((c - r, c - r, c + r, c + r), fill=FACE, outline=RING, width=int(s * 0.02))
    # 外周の残り時間の円弧（出発まで 45 分を表すイメージ）
    ar = int(s * 0.40)
    d.arc((c - ar, c - ar, c + ar, c + ar), start=-90, end=180, fill=ARC, width=int(s * 0.055))
    # 時計の針（10:10 ぐらい）
    w = int(s * 0.03)
    d.line((c, c, c - int(r * 0.45), c - int(r * 0.30)), fill=HAND, width=w)
    d.line((c, c, c + int(r * 0.55), c - int(r * 0.45)), fill=HAND, width=w)
    dot = int(s * 0.03)
    d.ellipse((c - dot, c - dot, c + dot, c + dot), fill=ARC)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"作成: {OUT}")


if __name__ == "__main__":
    main()
