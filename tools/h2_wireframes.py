# H2 の画面見本（ワイヤーフレーム）6 つの状態。時刻・予定・電池の残量・行の間は仮のデータ
# 使い方: python tools/h2_wireframes.py docs/design-reference/characters/official-3modes docs/design-reference/h2-wireframes
# （2026-10-16 H2 実装前の整合性確認の資料。アプリのコードではない。Q91・Q92 の位置は仮）
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

src = Path(sys.argv[1])
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
K = 2                       # 1pt = 2 画素
W, H = 393, 852             # 画面（pt）
BG = (250, 245, 236)
DARK = (61, 55, 48)
GRAY = (138, 129, 120)
LINE = (233, 225, 212)
ORANGE = (251, 141, 60)
NOW = (201, 102, 42)
CARD = (252, 229, 200)
TRACK = (239, 232, 220)
FACE = (255, 253, 248)
PLATE = (247, 241, 230)
ARC = {"green": (181, 216, 164), "yellow": (244, 222, 150), "coral": (242, 167, 151)}
ALERT = (196, 84, 60)
NOTE = (40, 120, 200)


def font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc" if bold else "C:/Windows/Fonts/YuGothM.ttc", int(size * K))


def P(v):
    return int(round(v * K))


# ---------- キャラクター（正式原画の切り出しから背景を抜き、本体 36pt に） ----------
def cutout(name):
    im = Image.open(src / name).convert("RGBA")
    w, h = im.size
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2), (w // 2, 0)]:
        try:
            ImageDraw.floodfill(im, seed, (0, 0, 0, 0), thresh=42)
        except Exception:
            pass
    return im.crop(im.getbbox())


HUMAN_BODY_PX = 157          # 原画の人型の頭のてっぺんから足まで（画素）
SCALE = 36 * K / HUMAN_BODY_PX
CHAR = {}
for mode, name in (("turtle", "turtle-mode.png"), ("human", "human-mode.png"), ("rabbit", "rabbit-mode.png")):
    c = cutout(name)
    CHAR[mode] = c.resize((round(c.width * SCALE), round(c.height * SCALE)), Image.LANCZOS)
MODE_NAME = {"turtle": "亀モード", "human": "人型モード", "rabbit": "うさぎモード"}


# ---------- 部品 ----------
def text(d, xy, s, size, color=DARK, bold=False, anchor="la"):
    d.text((P(xy[0]), P(xy[1])), s, fill=color, font=font(size, bold), anchor=anchor)


def battery(d, right, top, level=0.8):
    f = font(12, True)
    label = f"{int(level * 100)}%"
    bw, bh = 22, 11
    x1 = right - 3
    x0 = x1 - bw
    d.rounded_rectangle((P(x0), P(top), P(x1), P(top + bh)), radius=P(3), outline=DARK, width=P(1.2))
    d.rounded_rectangle((P(x0 + 2), P(top + 2), P(x0 + 2 + (bw - 4) * level), P(top + bh - 2)), radius=P(1.5), fill=DARK)
    d.rounded_rectangle((P(x1 + 1), P(top + 3.5), P(x1 + 3), P(top + bh - 3.5)), radius=P(1), fill=DARK)
    d.text((P(x0 - 5), P(top + bh / 2)), label, fill=DARK, font=f, anchor="rm")


def clock(d, cx, cy, D, now_h, now_m, target_m, label_target, caption):
    r = D / 2
    ring = D * 0.06
    remaining = (target_m - now_m) % 60 or 60
    color = ARC["green"] if remaining > 30 else ARC["yellow"] if remaining > 15 else ARC["coral"]
    box = (P(cx - r), P(cy - r), P(cx + r), P(cy + r))
    d.ellipse(box, fill=TRACK)
    a0 = now_m / 60 * 360 - 90
    a1 = a0 + remaining / 60 * 360
    d.pieslice(box, a0, a1, fill=color)
    inner = r - ring
    d.ellipse((P(cx - inner), P(cy - inner), P(cx + inner), P(cy + inner)), fill=FACE)
    for i in range(12):
        ang = math.radians(i * 30 - 90)
        long = i % 3 == 0
        r0 = inner - (9 if long else 5)
        r1 = (r + 3) if long else inner - 1.5
        d.line((P(cx + r0 * math.cos(ang)), P(cy + r0 * math.sin(ang)), P(cx + r1 * math.cos(ang)), P(cy + r1 * math.sin(ang))),
               fill=(188, 181, 172), width=P(1.2 if long else 1))
    hour_ang = math.radians(((now_h % 12) + now_m / 60) * 30 - 90)
    min_ang = math.radians(now_m * 6 - 90)
    d.line((P(cx), P(cy), P(cx + D * 0.265 * math.cos(hour_ang)), P(cy + D * 0.265 * math.sin(hour_ang))), fill=DARK, width=P(3))
    d.line((P(cx), P(cy), P(cx + D * 0.365 * math.cos(min_ang)), P(cy + D * 0.365 * math.sin(min_ang))), fill=DARK, width=P(2))
    pr = D * 0.34 / 2
    d.ellipse((P(cx - pr), P(cy - pr), P(cx + pr), P(cy + pr)), fill=PLATE, outline=LINE, width=P(1))
    text(d, (cx, cy - pr * 0.42), "出発まで" if label_target == "出発" else "開始まで", 11, GRAY, anchor="mm")
    num = str(remaining)
    fn = font(27, True)
    d.text((P(cx - 4), P(cy + pr * 0.18)), num, fill=DARK, font=fn, anchor="mm")
    nw = d.textlength(num, font=fn) / K
    text(d, (cx - 4 + nw / 2 + 1, cy + pr * 0.18 + 6), "分", 11, DARK, True, anchor="ls")
    mid = r - ring / 2
    na = math.radians(now_m * 6 - 90)
    ta = math.radians(target_m * 6 - 90)
    nr = D * 0.03 / 2 * 2
    d.ellipse((P(cx + mid * math.cos(na) - nr), P(cy + mid * math.sin(na) - nr), P(cx + mid * math.cos(na) + nr), P(cy + mid * math.sin(na) + nr)),
              fill=FACE, outline=DARK, width=P(1.2))
    tr = D * 0.043 / 2 * 2
    d.ellipse((P(cx + mid * math.cos(ta) - tr), P(cy + mid * math.sin(ta) - tr), P(cx + mid * math.cos(ta) + tr), P(cy + mid * math.sin(ta) + tr)), fill=DARK)
    lr = r + 10
    text(d, (cx + lr * math.cos(na), cy + lr * math.sin(na)), "いま", 10, GRAY, anchor="mm")
    text(d, (cx + (r + 16) * math.cos(ta), cy + (r + 16) * math.sin(ta)), label_target, 11, DARK, True, anchor="mm")
    text(d, (cx, cy + r + 27), caption, 13, GRAY, anchor="mm")


def tabbar(d):
    y0, h, w = 770, 60, 236
    x0 = (W - w) / 2
    d.rounded_rectangle((P(x0), P(y0), P(x0 + w), P(y0 + h)), radius=P(30), fill=(255, 252, 245), outline=(236, 228, 216), width=P(1))
    items = [("ホーム", True), ("カレンダー", False), ("設定", False)]
    for i, (label, sel) in enumerate(items):
        cx = x0 + w / 6 * (2 * i + 1)
        if sel:
            d.rounded_rectangle((P(cx - 36), P(y0 + 5), P(cx + 36), P(y0 + h - 5)), radius=P(25), fill=(240, 234, 224))
            d.ellipse((P(cx - 9), P(y0 + 13), P(cx + 9), P(y0 + 31)), fill=ORANGE)
        elif label == "カレンダー":
            d.rounded_rectangle((P(cx - 9), P(y0 + 14), P(cx + 9), P(y0 + 31)), radius=P(2), outline=DARK, width=P(2))
        else:
            d.ellipse((P(cx - 9), P(y0 + 13), P(cx + 9), P(y0 + 31)), outline=DARK, width=P(3))
        text(d, (cx, y0 + 44), label, 9, ORANGE if sel else DARK, True, anchor="mm")


def row_dot(d, y, kind, color=None):
    x = 24
    if kind == "now":
        d.ellipse((P(x - 7), P(y - 7), P(x + 7), P(y + 7)), fill=ORANGE)
    elif kind == "dep":
        d.ellipse((P(x - 4.5), P(y - 4.5), P(x + 4.5), P(y + 4.5)), fill=BG, outline=GRAY, width=P(1.4))
    else:
        d.ellipse((P(x - 4.5), P(y - 4.5), P(x + 4.5), P(y + 4.5)), fill=color)


def screen(state):
    img = Image.new("RGB", (P(W), P(H)), BG)
    d = ImageDraw.Draw(img)
    # Dynamic Island と Safe Area（見本の目印）
    d.rounded_rectangle((P((W - 126) / 2), P(11), P((W + 126) / 2), P(48)), radius=P(19), fill=(0, 0, 0))
    for x in range(0, W, 8):
        d.line((P(x), P(59), P(x + 4), P(59)), fill=(200, 210, 225), width=1)
    text(d, (W - 6, 52), "Safe Area", 8, (160, 175, 200), anchor="rs")
    text(d, (16, 64), "10月16日（金）", 20, DARK, True)
    battery(d, W - 16, 69)
    text(d, (16, 93), "終日　見本の終日予定（仮）", 12, GRAY)
    y_band_left = 112
    if state.get("finished"):
        text(d, (16, y_band_left), f"終わった予定 {state['finished']}件 ›", 13, GRAY)
        y_band_left += 24
    if state.get("message"):
        text(d, (16, y_band_left + 6), state["message"], 22, ALERT, True)
        y_band_left += 46
    if state.get("clock"):
        c = state["clock"]
        D = 0.40 * W
        cx = W - 30 - D / 2
        cy = 104 + D / 2
        clock(d, cx, cy, D, c["h"], c["m"], c["target"], c["label"], c["caption"])
        band_bottom = cy + D / 2 + 40
    else:
        band_bottom = y_band_left
    # 人型（「いま」の直上の定位置）→ 過ぎた出発の点 → いま
    fig = CHAR[state["mode"]]
    past = state.get("past")
    now_top = max(band_bottom, y_band_left + fig.height / K) + 8 + (26 if past else 0)
    fig_bottom = now_top - 6 - (26 if past else 0)
    img.paste(fig, (P(13), P(fig_bottom) - fig.height), fig)
    pitch = state.get("pitch", 44)
    y = now_top + 12
    first = y
    rows = state["rows"]
    if past:
        py = now_top - 14
        row_dot(d, py, "dep")
        text(d, (40, py), past, 13, GRAY, anchor="lm")
        first = py
    # 行の位置を先に決めてから線を引く
    layout = []
    yy = y
    hidden = 0
    for i, r in enumerate(rows):
        bottom = yy + (42 if r[0] == "main" else 10)
        if bottom + 34 > 760:
            hidden = sum(1 for rr in rows[i:] if rr[0] in ("ev", "main"))
            break
        layout.append((r, yy))
        yy += (64 if r[0] == "main" else pitch)
    last_y = layout[-1][1] + (30 if layout[-1][0][0] == "main" else 0)
    d.line((P(24), P(first), P(24), P(last_y + (26 if hidden else 14))), fill=LINE, width=P(2.5))
    row_dot(d, y, "now")
    text(d, (44, y), f"いま  {state['now']}", 17, NOW, True, anchor="lm")
    for r, ry in layout[1:] if rows and rows[0][0] == "now" else layout:
        kind = r[0]
        if kind == "dep":
            row_dot(d, ry, "dep")
            text(d, (44, ry), r[1], 14, GRAY, anchor="lm")
        elif kind == "main":
            d.rounded_rectangle((P(40), P(ry - 14), P(W - 16), P(ry + 42)), radius=P(12), fill=CARD)
            row_dot(d, ry, "ev", (247, 185, 131))
            text(d, (54, ry + 1), r[1], 17, DARK, True, anchor="lm")
            text(d, (54 + 44, ry + 25), r[2], 13, GRAY, anchor="lm")
        elif kind == "ev":
            row_dot(d, ry, "ev", r[2])
            text(d, (44, ry), r[1], 16, DARK, anchor="lm")
    if hidden:
        hy = last_y + 30
        text(d, (44, hy), f"ほか {hidden} 件 ›", 15, NOTE, True, anchor="lm")
    tabbar(d)
    return img


GREEN, YELLOW, MINT, PURPLE = (160, 200, 140), (240, 210, 120), (150, 210, 190), (190, 170, 220)
BASE_ROWS = [("now",), ("dep", "9:15  出発・車"), ("main", "9:30  A社打合せ", "広島市中区（見本）"), ("ev", "10:00  社内レビュー", GREEN),
             ("ev", "10:15  見本さんへ連絡", YELLOW), ("dep", "12:45  出発・徒歩"), ("ev", "13:00  歯医者", MINT), ("ev", "18:00  電話：見本さん", PURPLE)]
MANY_ROWS = [("now",), ("dep", "9:15  出発・車"), ("main", "9:30  A社打合せ", "広島市中区（見本）"), ("ev", "10:00  社内レビュー", GREEN),
             ("ev", "10:15  見本さんへ連絡", YELLOW), ("ev", "11:00  資料の確認", GREEN), ("ev", "11:30  見本の打合せ", YELLOW),
             ("dep", "12:45  出発・徒歩"), ("ev", "13:00  歯医者", MINT), ("ev", "14:00  見本の作業", GREEN), ("ev", "15:30  見本の電話", PURPLE),
             ("ev", "16:00  見本の確認", YELLOW), ("ev", "17:00  見本の連絡", MINT), ("ev", "18:00  電話：見本さん", PURPLE)]
STATES = [
    dict(key="1-noclock-turtle", title="1 時計なし・亀モード", mode="turtle", now="7:50", rows=BASE_ROWS,
         note=["いま 7:50 ／ 出発 9:15（85 分前）", "出発まで 60 分より前 → 時計なし（§88.6）", "見た目：亀（61 分以上前）。演出帯は低く"]),
    dict(key="2-clock-human", title="2 時計あり・人型モード", mode="human", now="8:30", rows=BASE_ROWS,
         clock=dict(h=8, m=30, target=15, label="出発", caption="8:30 → 9:15 出発予定"),
         note=["いま 8:30 ／ 出発 9:15（45 分前）", "時計 40％・右上寄り。弧は緑（60〜31 分）", "見た目：人型（60〜31 分前）。動作は落ち着いた日常"]),
    dict(key="3-clock-rabbit", title="3 時計あり・うさぎモード", mode="rabbit", now="8:52", rows=BASE_ROWS,
         clock=dict(h=8, m=52, target=15, label="出発", caption="8:52 → 9:15 出発予定"),
         note=["いま 8:52 ／ 出発 9:15（23 分前）", "弧は黄（30〜16 分）", "見た目：うさぎ（耳は必ず）。強く焦らせない"]),
    dict(key="4-overdue-past-departure", title="4 出発時刻超過・過ぎた出発の点", mode="rabbit", now="9:18",
         rows=[("now",), ("main", "9:30  A社打合せ", "広島市中区（見本）"), ("ev", "10:00  社内レビュー", GREEN), ("ev", "10:15  見本さんへ連絡", YELLOW),
               ("dep", "12:45  出発・徒歩"), ("ev", "13:00  歯医者", MINT), ("ev", "18:00  電話：見本さん", PURPLE)],
         message="出発時刻を3分過ぎています", past="9:15  出発・車（過ぎた出発）",
         note=["いま 9:18 ／ 出発 9:15 を 3 分過ぎた（未出発）", "時計は終わり、知らせを大きく（位置は Q92 の仮）", "並び：人型 → 過ぎた出発（1 行）→ いま（Q87）。見た目：うさぎのまま（Q90）"]),
    dict(key="5-many-events-more", title="5 予定が多く「ほか○件」", mode="human", now="8:30", rows=MANY_ROWS, pitch=34,
         clock=dict(h=8, m=30, target=15, label="出発", caption="8:30 → 9:15 出発予定"),
         note=["いま 8:30 ／ 予定 11 件（仮）", "行の間を詰め、入らない分は「ほか○件」", "件数は出していない予定の数（出発の点は数えない）"]),
    dict(key="6-no-location", title="6 場所なしの予定を案内", mode="rabbit", now="9:40", finished=1,
         rows=[("now",), ("main", "10:00  オンライン会議", "場所なし（見本）"), ("dep", "12:45  出発・徒歩"), ("ev", "13:00  歯医者", MINT),
               ("ev", "18:00  電話：見本さん", PURPLE)],
         clock=dict(h=9, m=40, target=0, label="開始", caption="9:40 → 10:00 開始予定"),
         note=["いま 9:40 ／ 開始 10:00（20 分前）。出発の点なし", "時計は「開始まで」。見た目は開始までの時間で（Q90）", "「終わった予定 1件」の位置は Q91 の仮"]),
]

screens = []
for st in STATES:
    im = screen(st)
    im.save(out / f"h2-{st['key']}.png")
    screens.append((st, im))

# 6 つを並べる（3×2）。説明は列の幅で折り返す
S = 0.62
sw, sh = int(P(W) * S), int(P(H) * S)
gapx, gapy, left, top = 60, 70, 60, 230
fb = ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc", 34)
fm = ImageFont.truetype("C:/Windows/Fonts/YuGothM.ttc", 25)
ft = ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc", 50)
fs = ImageFont.truetype("C:/Windows/Fonts/YuGothM.ttc", 28)
measure = ImageDraw.Draw(Image.new("RGB", (1, 1)))


def wrap(s, f, width):
    lines, cur = [], ""
    for ch in s:
        if measure.textlength(cur + ch, font=f) > width:
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines


sheet_w = left * 2 + sw * 3 + gapx * 2
cap_lines = [[l for note in st["note"] for l in wrap(note, fm, sw)] for st, _ in screens]
cap_h = 70 + max(len(c) for c in cap_lines) * 34 + 20
foot = ["※ 時刻・日付・予定名・場所・電池の残量・行の間（ふだん 44pt、予定が多いとき 34pt）は、すべて仮のデータです。人型は正式原画の切り出しを縮めて置いた見本（本体 36pt）。",
        "※ 「終わった予定 ○件」の位置（状態 6）と、大きな知らせの位置（状態 4）は、未決の Q91・Q92 の仮。点線は Safe Area の上の線、上の黒い形は Dynamic Island。"]
foot_lines = [l for f in foot for l in wrap(f, fs, sheet_w - left * 2)]
sub = wrap("Home だけ標準のステータスバーを出さず、右上にアプリ独自の電池の表示。時計 40％・右上寄り、人型（本体 36pt）は「いま」の直上（spec §88.2・§88.3）", fs, sheet_w - left * 2)
top = 120 + len(sub) * 40 + 30
sheet = Image.new("RGB", (sheet_w, top + (sh + cap_h) * 2 + gapy + 30 + len(foot_lines) * 40 + 40), (243, 236, 225))
d = ImageDraw.Draw(sheet)
d.text((left, 36), "H2 の画面見本（ワイヤーフレーム）6 つの状態", fill=DARK, font=ft)
for j, l in enumerate(sub):
    d.text((left, 112 + j * 40), l, fill=GRAY, font=fs)
radius = int(P(47) * S)
mask = Image.new("L", (sw, sh), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=radius, fill=255)
for i, ((st, im), lines) in enumerate(zip(screens, cap_lines)):
    col, row = i % 3, i // 3
    x = left + col * (sw + gapx)
    y = top + row * (sh + cap_h + gapy)
    d.rounded_rectangle((x - 8, y - 8, x + sw + 7, y + sh + 7), radius=radius + 8, fill=(40, 36, 32))
    sheet.paste(im.resize((sw, sh), Image.LANCZOS), (x, y), mask)
    d.text((x, y + sh + 22), st["title"], fill=DARK, font=fb)
    for j, line in enumerate(lines):
        d.text((x, y + sh + 74 + j * 34), line, fill=GRAY, font=fm)
fy = top + (sh + cap_h) * 2 + gapy + 10
for j, l in enumerate(foot_lines):
    d.text((left, fy + j * 40), l, fill=GRAY, font=fs)
sheet.save(out / "h2-wireframes.png")
print("保存", out, sheet.size)
