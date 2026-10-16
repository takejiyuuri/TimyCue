# 正式キャラクター 3 モード（spec §88.4）の再現を、アプリ（CharacterFigure）と同じ部品・同じ順で描くための共通の部品。
# 値は TimyCue/Features/Character/CharacterPose+Official.swift と同じ（単位は原画の人型「立つ」の切り出しの画素）。
# アプリのコードではない（原画との比べる画像を作るための道具。2026-10-16 H2 の前提作業 1）
import math
import numpy as np
from PIL import Image
from scipy import ndimage

# ---- 原画の切り出し（timycue-character-3modes.webp の「主なポーズ・動作例」の「立つ」。原画の画素のまま） ----
STAND_BOXES = {"turtle": (45, 450, 140, 555), "human": (545, 450, 640, 555), "rabbit": (1045, 445, 1130, 555)}


def crop_standing(webp_path):
    im = Image.open(webp_path).convert("RGB")
    return {mode: im.crop(box) for mode, box in STAND_BOXES.items()}


def masks(image, S=4):
    """原画の切り出しから、キャラクター全体（輪郭の線を含む）と、輪郭の内側の白い形を取り出す（S 倍の細かさ）"""
    im = image.resize((image.width * S, image.height * S), Image.LANCZOS)
    a = np.asarray(im).astype(float)
    dark = a.mean(2) < 140
    lab, _ = ndimage.label(~dark)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])))
    sil = ~np.isin(lab, list(border))
    inner = ndimage.binary_opening(ndimage.binary_fill_holes(sil & ~dark), iterations=2)
    return a, dark, sil, inner


# ---- 形（アプリの CharacterPose と同じ決まり：角度は度、正は画面で時計回り、0 で真下） ----
def ellipse(X, Y, cx, cy, w, h, rot=0):
    r = math.radians(rot)
    c, s = math.cos(r), math.sin(r)
    dx, dy = X - cx, Y - cy
    u, v = dx * c + dy * s, -dx * s + dy * c
    return (u / (w / 2)) ** 2 + (v / (h / 2)) ** 2 <= 1


def rrect(X, Y, cx, cy, w, h, rad, rot=0):
    r = math.radians(rot)
    c, s = math.cos(r), math.sin(r)
    dx, dy = X - cx, Y - cy
    u, v = dx * c + dy * s, -dx * s + dy * c
    rad = max(0, min(rad, w / 2, h / 2))
    qx, qy = np.abs(u) - (w / 2 - rad), np.abs(v) - (h / 2 - rad)
    d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rad
    return d <= 0


def limb(X, Y, jx, jy, length, width, angle, corner=None):
    a = math.radians(angle)
    cx, cy = jx - math.sin(a) * length / 2, jy + math.cos(a) * length / 2
    rad = width / 2 if corner is None else corner
    return rrect(X, Y, cx, cy, width, length, min(rad, width / 2, length / 2), angle)


# 本体の部品の値（fit_body.py で当てはめた値。左右対称）
# 中心 x、頭（中心 y・幅・高さ）、胴（中心 y・幅・高さ・角の丸みの割合）、脚（中心からの横のずれ・付け根 y・長さ・幅・角度・角の丸み）、
# 腕（中心からの横のずれ・付け根 y・長さ・幅・外へ開く角度）
BODY = [45.25, 40.03, 63.74, 59.55, 71.36, 34.94, 34.5, 0.1, 10.03, 81.61, 11.81, 7.8, 0.0, 2.0, 13.11, 63.41, 19.65, 7.65, 27.95]


def body_mask(X, Y, p=BODY):
    c, hcy, hw, hh, bcy, bw, bh, bcr, ldx, ljy, llen, lwid, lang, lcor, adx, ajy, alen, awid, aang = p
    m = ellipse(X, Y, c, hcy, hw, hh)
    m |= rrect(X, Y, c, bcy, bw, bh, bcr * bw)
    for sgn in (-1, 1):
        m |= limb(X, Y, c + sgn * ldx, ljy, llen, lwid, -sgn * lang, lcor)
        m |= limb(X, Y, c + sgn * adx, ajy, alen, awid, -sgn * aang)
    return m


EYES = [(35.0, 46.1), (56.8, 46.1)]
EYE_SIZE = (4.9, 5.1)
ARM_LINES = [((26.8, 78.0), (26.1, 81.0), (25.0, 84.0)), ((63.2, 78.0), (63.9, 81.0), (65.0, 84.0))]
OUTLINE_RATIO = 0.0385       # 本体の全身の高さに対する輪郭の太さ
# 甲羅は見る人から見て左（2026-10-16 決定・2026-10-17 確認。spec §88.4）。形・大きさは原画の亀「立つ」を測った値で、
# 「立つ」は右に描かれているので、本体の中心 x = 45.25 で左右を入れ替えた（「立つ」の位置は cx=74.0・rot=10）
SHELL = dict(cx=16.5, cy=67.5, w=23.5, h=38, rot=-10)
SHELL_PATTERN = [
    [(-0.18, -0.30), (0.18, -0.30), (0.26, -0.08), (0.18, 0.16), (-0.18, 0.16), (-0.26, -0.08), (-0.18, -0.30)],
    [(-0.18, 0.16), (-0.12, 0.36), (0.12, 0.36), (0.18, 0.16)],
    [(0.26, -0.08), (0.47, -0.12)], [(-0.26, -0.08), (-0.47, -0.12)],
    [(0.18, -0.30), (0.28, -0.40)], [(-0.18, -0.30), (-0.28, -0.40)],
    [(0.18, 0.16), (0.40, 0.24)], [(-0.18, 0.16), (-0.40, 0.24)],
]
EARS = [dict(cx=23.9, cy=-1.5, w=15.8, h=29.5, rot=-30), dict(cx=66.6, cy=-1.5, w=15.8, h=29.5, rot=30)]
EAR_INNERS = [dict(cx=25.9, cy=3.0, w=8.6, h=22.0, rot=-28), dict(cx=64.6, cy=3.0, w=8.6, h=22.0, rot=28)]
FACE_OPENING = dict(cx=45.25, cy=46.2, w=57.2, h=51.8)
# 色（原画を測った値。CharacterPalette.official・CharacterGearPalette.official と同じ）
OUTLINE = (0x36, 0x19, 0x0A)
FILL = (0xFE, 0xFA, 0xF2)
SHELL_FILL = (0xBA, 0xBE, 0x85)
SHELL_LINE = (0x96, 0x9B, 0x60)
EAR_INNER = (0xF8, 0xBC, 0xB0)
HOOD_LINE = (0xDC, 0xAF, 0x96)
MODE_GEAR = {"turtle": {"shell"}, "human": set(), "rabbit": {"hood"}}


def body_height():
    c, hcy, hw, hh, *_ = BODY
    return BODY[9] + BODY[10] - (hcy - hh / 2)


def _segments(X, Y, pts, width):
    m = np.zeros(X.shape, bool)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((X - x0) * dx + (Y - y0) * dy) / (dx * dx + dy * dy), 0, 1)
        m |= np.hypot(X - (x0 + t * dx), Y - (y0 + t * dy)) <= width / 2
    return m


def _quad(p0, p1, p2, n=12):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in np.linspace(0, 1, n)]


def _shell_lines():
    r = math.radians(SHELL["rot"])
    out = []
    for line in SHELL_PATTERN:
        pts = []
        for u, v in line:
            x, y = u * SHELL["w"], v * SHELL["h"]
            pts.append((SHELL["cx"] + x * math.cos(r) - y * math.sin(r), SHELL["cy"] + x * math.sin(r) + y * math.cos(r)))
        out.append(pts)
    return out


def render(mode, box=(0, -22, 95, 100), px_per_unit=2.0, S=8):
    """アプリと同じ順で描く：甲羅 → 耳 → 本体 → 顔まわりの線 → 目 → 腕の線。透明の背景の RGBA を返す"""
    x0, y0, x1, y1 = box
    ys, xs = np.mgrid[0:(y1 - y0) * S, 0:(x1 - x0) * S]
    X, Y = x0 + (xs + 0.5) / S, y0 + (ys + 0.5) / S
    img = np.zeros(X.shape + (4,), float)
    ow = OUTLINE_RATIO * body_height()
    gear = MODE_GEAR[mode]

    def paint(mask, color):
        img[mask, :3] = np.array(color) / 255
        img[mask, 3] = 1

    def outlined(mask, fill=FILL):
        paint(ndimage.distance_transform_edt(~mask) / S <= ow, OUTLINE)
        paint(mask, fill)

    if "shell" in gear:
        sm = ellipse(X, Y, SHELL["cx"], SHELL["cy"], SHELL["w"], SHELL["h"], SHELL["rot"])
        outlined(sm, SHELL_FILL)
        for line in _shell_lines():
            paint(_segments(X, Y, line, ow * 0.55) & sm, SHELL_LINE)
    if "hood" in gear:
        for e, i in zip(EARS, EAR_INNERS):
            outlined(ellipse(X, Y, e["cx"], e["cy"], e["w"], e["h"], e["rot"]))
            paint(ellipse(X, Y, i["cx"], i["cy"], i["w"], i["h"], i["rot"]), EAR_INNER)
    outlined(body_mask(X, Y))
    if "hood" in gear:
        f = FACE_OPENING
        pts = [(f["cx"] + f["w"] / 2 * math.cos(t), f["cy"] + f["h"] / 2 * math.sin(t)) for t in np.linspace(math.pi, 2 * math.pi, 25)]
        paint(_segments(X, Y, pts, ow * 0.7), HOOD_LINE)
    for ex, ey in EYES:
        paint(ellipse(X, Y, ex, ey, *EYE_SIZE), OUTLINE)
    for line in ARM_LINES:
        paint(_segments(X, Y, _quad(*line), ow), OUTLINE)
    im = Image.fromarray((img * 255).astype(np.uint8), "RGBA")
    return im.resize((round((x1 - x0) * px_per_unit), round((y1 - y0) * px_per_unit)), Image.LANCZOS)
