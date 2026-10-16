# 本体（頭・胴・腕・脚）の部品の値を、原画の人型「立つ」の輪郭の内側の白い形に当てはめる（2026-10-16。アプリのコードではない）
# 使い方: python tools/character_3modes/fit_body.py docs/design-reference/characters/official-3modes/timycue-character-3modes.webp
# 重なりの割合（共通部分 ÷ 合わせた部分）が大きくなるよう、部品の値を少しずつ動かす。左右対称・脚はまっすぐ。
# 頭と腕は、はじめに全部の値を動かして当てはめた値（shapes.BODY）のまま。ここでは胴と脚を合わせ直す
# （胴は足の付け根の高さまで、脚はまっすぐ）。2 本の脚のあいだの浅い切れ込みを合わせるため、足元の真ん中のずれを 4 倍に数える。
# 結果は shapes.BODY と Swift（CharacterPose+Official.swift）の値に写す
import sys
from pathlib import Path
import numpy as np
from scipy.optimize import minimize
sys.path.insert(0, str(Path(__file__).resolve().parent))
import shapes

S = 4
image = shapes.crop_standing(sys.argv[1])["human"]
_, _, _, inner = shapes.masks(image, S)
ys, xs = np.mgrid[0:image.height * S, 0:image.width * S]
X, Y = (xs + 0.5) / S, (ys + 0.5) / S
weight = np.ones(inner.shape)
weight[(X > 34) & (X < 57) & (Y > 82)] = 4.0


def full(q):
    p = list(shapes.BODY)
    p[4], p[6] = q[0], q[1]
    p[7] = min(max(q[2], 0), 0.5)
    p[8:12] = q[3:7]
    p[12] = 0
    p[13] = min(max(q[7], 2), 7)
    return p


def loss(q):
    m = shapes.body_mask(X, Y, full(q))
    return ((m ^ inner) * weight).sum() / ((m | inner) * weight).sum()


best = minimize(loss, [70, 36, 0.2, 13, 80, 12.5, 15, 4], method="Powell", options={"xtol": 0.005, "ftol": 1e-8})
best = minimize(loss, best.x, method="Nelder-Mead", options={"xatol": 0.005, "fatol": 1e-9, "maxiter": 20000})
p = [round(float(v), 2) for v in full(best.x)]
m = shapes.body_mask(X, Y, p)
print("重なりの割合", round((m & inner).sum() / (m | inner).sum(), 4))
print("BODY =", p)
