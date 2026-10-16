# 新キャラクター 3 案 × 3 姿勢の原画（1 点ずつ）と、比較一覧（3 列×3 行、同じ倍率）を作る
# 使い方: python tools/character_candidates/sheet.py docs/design-reference/characters/candidates-2026-10-16
# （Home への配置の見本は、ビルド確認の画面写真から部品を切り出して作ったので、ここには入れていない）
import sys
import zlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import newchars as nc

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
SCALE = 4.0          # 1 単位 = 4 画素（立った姿の全身の高さ 100 単位 = 400 画素。3 案とも同じ倍率）
LINE = 2.3           # 輪郭の見える太さ（単位）
CELL = (560, 520)    # 1 点の大きさ
GROUND = 470         # 地面の高さ（画素）。3 姿勢とも足元をそろえる

poses = [("stand", "立つ"), ("sit", "座る"), ("coffee", "コーヒー")]
designs = [("A", "A まんまる"), ("B", "B もちもち"), ("C", "C すっきり・やさしい")]
names = {"stand": "standing", "sit": "sitting", "coffee": "coffee"}
cells = {}
for d, _ in designs:
    for p, _ in poses:
        # 地面（100 単位）を GROUND に、真ん中（50 単位）を中央に
        origin = (50 - CELL[0] / 2 / SCALE, 100 - GROUND / SCALE)
        img = nc.render(d, p, CELL, SCALE, origin, LINE, ss=4, seed=zlib.crc32(f"{d}-{p}".encode()) % 1000)
        img.save(out / f"{d}-{names[p]}.png")
        cells[(d, p)] = img

font = ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc", 30)
small = ImageFont.truetype("C:/Windows/Fonts/YuGothM.ttc", 22)
title = ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc", 40)
LEFT, TOP = 150, 170
W = LEFT + CELL[0] * 3 + 40
H = TOP + CELL[1] * 3 + 80
sheet = Image.new("RGB", (W, H), nc.BG)
dr = ImageDraw.Draw(sheet)
dr.text((40, 30), "TimyCue 新キャラクター 3 案（比較候補）", fill=(61, 55, 48), font=title)
dr.text((40, 88), "3 案とも同じ倍率（立った姿の全身の高さをそろえる）。座る・コーヒーも立つと同じ縮尺。背景は無地、床・影なし", fill=(120, 110, 100), font=small)
for j, (d, label) in enumerate(designs):
    x = LEFT + CELL[0] * j
    dr.text((x + CELL[0] / 2 - dr.textlength(label, font=font) / 2, TOP - 48), label, fill=(61, 55, 48), font=font)
for i, (p, label) in enumerate(poses):
    y = TOP + CELL[1] * i
    dr.text((40, y + CELL[1] / 2 - 18), label, fill=(61, 55, 48), font=font)
    for j, (d, _) in enumerate(designs):
        sheet.paste(cells[(d, p)], (LEFT + CELL[0] * j, y))
for j in range(1, 3):
    x = LEFT + CELL[0] * j
    dr.line((x, TOP - 10, x, TOP + CELL[1] * 3), fill=(233, 225, 212), width=2)
for i in range(1, 3):
    y = TOP + CELL[1] * i
    dr.line((LEFT, y, LEFT + CELL[0] * 3, y), fill=(233, 225, 212), width=2)
sheet.save(out / "new-characters-3x3.png")
print("保存", out)
