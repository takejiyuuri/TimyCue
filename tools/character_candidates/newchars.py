# TimyCue 新キャラクター 3 案（A まんまる・B もちもち・C すっきり）の描き方と、姿勢ごとの部品
# 2026-10-16 の比較候補の原画を作る道具（アプリのコードではない。正式なキャラクターは spec §88.4 の「2 シンプル」のまま）
# 単位：立った姿の全身の高さを 100 とする（y は下向き、地面は 100）。部品（頭・胴・腕・脚・小物）を分けて持ち、あとで動かせる形にする
import math
import random
from PIL import Image, ImageDraw

OUTLINE = (107, 76, 56)     # やわらかいブラウン
FILL = (255, 252, 245)      # 白〜アイボリー
EYE = (58, 40, 29)
CUP = (247, 206, 164)       # 小物：やさしいアプリコット
COFFEE = (140, 96, 64)
STEAM = (196, 178, 160)
BG = (250, 245, 236)        # Home の背景（アイボリー）


# ---------- 形（点の並び） ----------
def rot_pt(p, c, deg):
    a = math.radians(deg)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a))


def ellipse(cx, cy, w, h, rot=0, n=180):
    pts = [(cx + w / 2 * math.cos(2 * math.pi * i / n), cy + h / 2 * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return [rot_pt(p, (cx, cy), rot) for p in pts] if rot else pts


def rrect(cx, cy, w, h, r, rot=0, n=16):
    r = max(0.01, min(r, w / 2, h / 2))
    pts = []
    for ox, oy, st in [(cx + w / 2 - r, cy + h / 2 - r, 0), (cx - w / 2 + r, cy + h / 2 - r, 90),
                       (cx - w / 2 + r, cy - h / 2 + r, 180), (cx + w / 2 - r, cy - h / 2 + r, 270)]:
        for i in range(n + 1):
            a = math.radians(st + 90 * i / n)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return [rot_pt(p, (cx, cy), rot) for p in pts] if rot else pts


def limb(jx, jy, length, width, angle, r=None):
    """付け根から伸びる棒。angle 0 で真下、正は画面で時計回り（左の腕を外へ開く向き）"""
    a = math.radians(angle)
    cx, cy = jx - math.sin(a) * length / 2, jy + math.cos(a) * length / 2
    return rrect(cx, cy, width, length, width / 2 if r is None else r, angle)


def blob(points, n=24):
    """点を通るなめらかな閉じた曲線（Catmull-Rom）"""
    out = []
    m = len(points)
    for i in range(m):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % m], points[(i + 2) % m]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    return out


def quad(s, c, e, n=40):
    return [((1 - t) ** 2 * s[0] + 2 * (1 - t) * t * c[0] + t * t * e[0],
             (1 - t) ** 2 * s[1] + 2 * (1 - t) * t * c[1] + t * t * e[1]) for t in (i / n for i in range(n + 1))]


def transform(path, center, deg):
    return [rot_pt(p, center, deg) for p in path]


# ---------- やわらかい線で描く ----------
def resample(pts, step, closed=True):
    src = pts + [pts[0]] if closed else pts
    out = [src[0]]
    carry = 0.0
    for a, b in zip(src, src[1:]):
        seg = math.dist(a, b)
        if seg == 0:
            continue
        d = step - carry
        while d <= seg:
            t = d / seg
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            d += step
        carry = seg - (d - step)
    return out


class Painter:
    """部品の値（単位）を画素に直し、細かく描いてから縮める（なめらかな線）"""

    def __init__(self, size, scale, origin, line_units, ss=4, bg=BG, seed=7, wobble=0.22):
        self.ss = ss
        self.size = size
        self.k = scale * ss
        self.origin = origin
        self.lw = line_units * self.k          # 輪郭の線の太さ（見える太さの 2 倍で描き、内側は塗りで隠す）
        self.img = Image.new("RGB", (size[0] * ss, size[1] * ss), bg)
        self.d = ImageDraw.Draw(self.img)
        self.rng = random.Random(seed)
        self.wobble = wobble * scale * ss / 4  # 手描きの揺らぎ（単位→画素）

    def px(self, path):
        ox, oy = self.origin
        return [((x - ox) * self.k, (y - oy) * self.k) for x, y in path]

    def soften(self, path, closed=True):
        """輪郭をほんの少し揺らす（硬すぎない線）"""
        p = resample(self.px(path), max(1.0, self.ss * 0.5), closed)
        n = len(p)
        if n < 4 or self.wobble <= 0:
            return p
        ph = [self.rng.uniform(0, 2 * math.pi) for _ in range(3)]
        out = []
        for i in range(n):
            t = i / n
            a, b = p[i - 1], p[(i + 1) % n]
            nx, ny = -(b[1] - a[1]), b[0] - a[0]
            ln = math.hypot(nx, ny) or 1
            off = self.wobble * (0.6 * math.sin(2 * math.pi * 3 * t + ph[0]) + 0.4 * math.sin(2 * math.pi * 7 * t + ph[1]))
            out.append((p[i][0] + nx / ln * off, p[i][1] + ny / ln * off))
        return out

    def stamp(self, pts, width_fn, color):
        for i, (x, y) in enumerate(pts):
            r = width_fn(i, len(pts)) / 2
            self.d.ellipse((x - r, y - r, x + r, y + r), fill=color)

    def ring_width(self):
        ph = [self.rng.uniform(0, 2 * math.pi) for _ in range(2)]
        lw = self.lw
        return lambda i, n: lw * (1 + 0.10 * math.sin(2 * math.pi * 2 * i / n + ph[0]) + 0.05 * math.sin(2 * math.pi * 5 * i / n + ph[1]))

    def group(self, paths, fill=FILL, outline=OUTLINE):
        """まとめて描く：外側の輪郭だけが残り、重なった所に線が出ない（ひと続きの形）"""
        soft = [self.soften(p) for p in paths]
        for p in soft:
            self.stamp(p, self.ring_width(), outline)
        for p in soft:
            self.d.polygon(p, fill=fill)

    def shape(self, path, fill=FILL, outline=OUTLINE):
        self.group([path], fill, outline)

    def ring(self, path, outline=OUTLINE, scale=1.0):
        """塗らずに線だけ（カップの持ち手など）"""
        p = self.soften(path)
        w = self.ring_width()
        self.stamp(p, lambda i, n: w(i, n) * 0.5 * scale, outline)

    def stroke(self, path, color=OUTLINE, scale=0.5):
        """開いた線（細部・湯気）。両端を少し細くする"""
        p = resample(self.px(path), max(1.0, self.ss * 0.5), closed=False)
        lw = self.lw * scale
        self.stamp(p, lambda i, n: lw * (0.6 + 0.4 * math.sin(math.pi * i / max(1, n - 1))), color)

    def fill(self, path, color):
        self.d.polygon(self.px(path), fill=color)

    def eyes(self, eyes, color=EYE):
        for (cx, cy, w, h) in eyes:
            self.d.polygon(self.px(ellipse(cx, cy, w, h, n=64)), fill=color)

    def result(self):
        return self.img.resize(self.size, Image.LANCZOS)


# ---------- 小物：コーヒーカップ ----------
def cup_parts(cx, cy, w, h, handle="right", tilt=0):
    body = rrect(cx, cy, w, h, min(w, h) * 0.32)
    hx = cx + (w / 2 + w * 0.12) * (1 if handle == "right" else -1)
    hand = ellipse(hx, cy - h * 0.02, w * 0.42, h * 0.56)
    surface = ellipse(cx, cy - h / 2 + h * 0.16, w * 0.8, h * 0.2)
    parts = dict(body=body, handle=hand, surface=surface)
    if tilt:
        parts = {k: transform(v, (cx, cy), tilt) for k, v in parts.items()}
    return parts


def draw_cup(pt, cup, steam=True):
    pt.ring(cup["handle"], scale=1.0)
    pt.shape(cup["body"], fill=CUP)
    pt.fill(cup["surface"], COFFEE)
    if steam:
        xs = [p[0] for p in cup["body"]]
        ys = [p[1] for p in cup["body"]]
        cx, top = (min(xs) + max(xs)) / 2, min(ys)
        w = max(xs) - min(xs)
        for dx in (-w * 0.18, w * 0.18):
            x = cx + dx
            pt.stroke(quad((x, top - 2.2), (x - w * 0.16, top - 5.5), (x + w * 0.02, top - 9.5)), color=STEAM, scale=0.42)


# ---------- A まんまる ----------
def A(pose):
    if pose == "stand":
        body = blob([(50, 60), (64, 63), (70, 72), (71, 83), (66, 92), (50, 95), (34, 92), (29, 83), (30, 72), (36, 63)])
        back = [body, limb(32, 70, 13, 11, 28), limb(68, 70, 13, 11, -28),
                limb(42, 86, 14, 12.5, 0, r=6), limb(58, 86, 14, 12.5, 0, r=6)]
        return dict(back=back, head=ellipse(50, 34, 72, 66), eyes=[(39.5, 41, 5.4, 6.2), (60.5, 41, 5.4, 6.2)])
    if pose == "sit":
        body = blob([(50, 72), (66, 75), (73.5, 85), (72.5, 94.5), (50, 99), (27.5, 94.5), (26.5, 85), (34, 75)])
        back = [body, limb(29.5, 79, 12, 11, 42), limb(70.5, 79, 12, 11, -42)]
        front = [ellipse(40, 96, 13.5, 9.5), ellipse(60, 96, 13.5, 9.5)]
        return dict(back=back, head=ellipse(50, 47.5, 72, 66), eyes=[(39.5, 55, 5.4, 6.0), (60.5, 55, 5.4, 6.0)],
                    front_each=front)
    if pose == "coffee":
        body = blob([(50, 60), (64, 63), (70, 72), (71, 83), (66, 92), (50, 95), (34, 92), (29, 83), (30, 72), (36, 63)])
        back = [body, limb(42, 86, 14, 12.5, 0, r=6), limb(58, 86, 14, 12.5, 0, r=6)]
        head_c = (50, 66)
        head = transform(ellipse(50, 34, 72, 66), head_c, -3)
        eyes = [(41, 43.5, 5.4, 5.4), (60.5, 42.5, 5.4, 5.4)]
        arms = [limb(33.5, 72, 13, 10.5, -104), limb(66.5, 72, 13, 10.5, 104)]
        cup = cup_parts(50, 67.5, 17, 14)
        return dict(back=back, head=head, eyes=eyes, arms_front=arms, cup=cup)


# ---------- B もちもち ----------
# 頭と体がひと続き（あごの線なし）。頭の丸みと、下がふっくら広い体のあいだに、やわらかいくびれ。全体は少し横に広い
B_STAND = [(50, 4), (63, 5.5), (73.5, 11.5), (80, 21), (81.5, 32), (80, 41), (77, 48.5), (79.5, 55.5), (86, 63), (90.5, 73),
           (91.5, 85), (87, 93), (74, 97), (50, 97.6), (26, 97), (13, 93), (8.5, 85), (9.5, 73), (14, 63), (20.5, 55.5),
           (23, 48.5), (20, 41), (18.5, 32), (20, 21), (26.5, 11.5), (37, 5.5)]
B_SIT = [(50, 22), (63, 23.5), (73.5, 29.5), (80, 39), (81, 48.5), (79, 56), (77, 61.5), (81, 67.5), (89, 75), (93.5, 84),
         (94, 92), (88.5, 97.5), (74, 99.4), (50, 99.8), (26, 99.4), (11.5, 97.5), (6, 92), (6.5, 84), (11, 75), (19, 67.5),
         (23, 61.5), (21, 56), (19, 48.5), (20, 39), (26.5, 29.5), (37, 23.5)]


def B(pose):
    c = (50, 100)
    if pose == "stand":
        tilt = -3
        sil = [blob(B_STAND), ellipse(13.5, 66, 10, 14, 30), ellipse(86.5, 66, 10, 14, -30)]
        front = [ellipse(38, 97.6, 15, 6.6), ellipse(62, 97.6, 15, 6.6)]
        eyes = [(40.5, 29, 5.0, 6.0), (59.5, 29, 5.0, 6.0)]
    elif pose == "sit":
        tilt = -6
        sil = [blob(B_SIT), ellipse(9, 84, 9.5, 12.5, 34), ellipse(91, 84, 9.5, 12.5, -34)]
        front = [ellipse(37, 98.4, 14.5, 7.4), ellipse(63, 98.4, 14.5, 7.4)]
        eyes = [(40.5, 47, 5.0, 5.6), (59.5, 47, 5.0, 5.6)]
    else:  # coffee
        tilt = 3
        sil = [blob(B_STAND)]
        front = [ellipse(38, 97.6, 15, 6.6), ellipse(62, 97.6, 15, 6.6)]
        eyes = [(41.5, 31.5, 5.0, 5.4), (58.5, 31.5, 5.0, 5.4)]
        arms = [transform(ellipse(37.5, 64, 11, 13, -42), c, tilt), transform(ellipse(62.5, 64, 11, 13, 42), c, tilt)]
        cup = {k: transform(v, c, tilt) for k, v in cup_parts(50, 60, 17, 14).items()}
    parts = dict(merged=[transform(p, c, tilt) for p in sil],
                 front_each=[transform(p, c, tilt) for p in front],
                 eyes=[rot_pt(e[:2], c, tilt) + e[2:] for e in eyes])
    if pose == "coffee":
        parts.update(arms_front=arms, cup=cup)
    return parts


# ---------- C すっきり・やさしい ----------
C_TORSO = [(50, 44), (60, 45.5), (64, 52), (65, 64), (63, 74), (57, 78.5), (50, 79), (43, 78.5), (37, 74), (35, 64), (36, 52), (40, 45.5)]


def C(pose):
    legs = [limb(44, 74, 22, 8.5, 0), limb(56, 74, 22, 8.5, 0), ellipse(42.6, 96.4, 12.5, 7.0), ellipse(57.4, 96.4, 12.5, 7.0)]
    if pose == "stand":
        arms = [limb(37, 49, 25, 7.5, 13), limb(63, 49, 25, 7.5, -13)]
        return dict(arms_back=arms, legs=legs, torso=blob(C_TORSO), head=ellipse(50, 23, 46, 44),
                    eyes=[(43.5, 25, 3.8, 4.6), (56.5, 25, 3.8, 4.6)])
    if pose == "sit":
        torso = blob([(50, 66), (60, 67.5), (64, 74), (65, 84), (62, 92), (50, 95), (38, 92), (35, 84), (36, 74), (40, 67.5)])
        arms = [limb(37, 71, 22, 7.5, 28), limb(63, 71, 22, 7.5, -28)]
        front = [ellipse(43, 95.5, 12.5, 9), ellipse(57, 95.5, 12.5, 9)]
        return dict(arms_back=arms, torso=torso, head=ellipse(50, 45, 46, 44), front_each=front,
                    eyes=[(43.5, 47, 3.8, 4.6), (56.5, 47, 3.8, 4.6)])
    if pose == "coffee":
        left = [limb(37, 49, 25, 7.5, 10)]
        right_arm = [limb(63, 49, 13, 7.5, -22), limb(67.5, 60, 13.5, 7.5, 144)]
        cup = cup_parts(57.5, 47.5, 12.5, 10.5)
        return dict(arms_back=left, legs=legs, torso=blob(C_TORSO), head=transform(ellipse(50, 23, 46, 44), (50, 45), 3),
                    eyes=[(45, 26.5, 3.8, 4.2), (57.5, 27, 3.8, 4.2)], arm_front=right_arm, cup=cup)


DESIGNS = dict(A=A, B=B, C=C)


def bounds(parts):
    pts = []
    for k, v in parts.items():
        if k == "eyes":
            continue
        if k == "cup":
            for p in v.values():
                pts += p
            continue
        if isinstance(v, list) and v and isinstance(v[0], list):
            for p in v:
                pts += p
        elif isinstance(v, list):
            pts += v
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def render(design, pose, size, scale, origin, line_units, ss=4, bg=BG, wobble=0.22, seed=11):
    parts = DESIGNS[design](pose)
    pt = Painter(size, scale, origin, line_units, ss=ss, bg=bg, seed=seed, wobble=wobble)
    # 描く順：後ろの腕 → 脚 → 胴（＋胴とひと続きの腕・脚）→ 頭 → 手前の腕 → 小物 → 手前の足 → 目
    if "arms_back" in parts:
        for a in parts["arms_back"]:
            pt.shape(a)
    if "legs" in parts:
        pt.group(parts["legs"])
    if "back" in parts:
        pt.group(parts["back"])
    if "merged" in parts:
        pt.group(parts["merged"])
    if "torso" in parts:
        pt.shape(parts["torso"])
    if "head" in parts:
        pt.shape(parts["head"])
    if "arms_front" in parts and design == "A":
        pt.group(parts["arms_front"])
    if "arm_front" in parts:
        pt.group(parts["arm_front"])
    if "cup" in parts:
        if design == "B":
            draw_cup(pt, parts["cup"])
            for a in parts["arms_front"]:
                pt.shape(a)
        else:
            draw_cup(pt, parts["cup"])
            if design == "A":
                # 両手でカップを包む：手の先をカップの手前に
                for side in (-1, 1):
                    hx = 50 + side * 8.6
                    pt.shape(ellipse(hx, 69.5, 7.2, 8.6, side * 10))
    if "front_each" in parts:
        for f in parts["front_each"]:
            pt.shape(f)
    pt.eyes(parts["eyes"])
    return pt.result()
