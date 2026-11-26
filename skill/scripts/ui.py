"""ui.py - locate clickable boxes in a vocabgo mini-program screenshot.

Coordinates are computed from the image every time (nothing hard-coded).

Usage: python ui.py screen.png [--debug]

Output JSON:
{
 "size":[w,h],
 "kind":"options|chips|grid|spelling|dialog|unknown",
 "rows":[{"i","x","y","w","h"}],     # full-width bordered rows (4-choice questions)
 "chips":[{"i","x","y","w","h"}],    # small bordered boxes (word chips / tiles)
 "buttons":[{"i","x","y","w","h"}],  # solid green buttons (继续/提交/开始练习)
 "input":{"x","y","w","h"}|null,     # spelling underline
 "back":{"x","y"}|null
}

Method (colour-agnostic): page background is uniform (#F7F7F7). Any bordered
box shows up as long horizontal runs of "non-background" pixels at its top and
bottom edge; pairing those lines yields the box. Solid green buttons are found
as large filled green blobs.
"""
import sys, json
import numpy as np
from PIL import Image

BG = np.array([247, 247, 247])
GREEN = np.array([7, 193, 96])

def runs(idx, min_len=1):
    out = []
    if len(idx) == 0: return out
    s = p = idx[0]
    for i in idx[1:]:
        if i == p + 1:
            p = i
        else:
            if p - s + 1 >= min_len: out.append((s, p))
            s = p = i
    if p - s + 1 >= min_len: out.append((s, p))
    return out

def components(mask, min_px=500):
    ys, xs = np.nonzero(mask)
    pts = set(zip(ys.tolist(), xs.tolist()))
    seen = set(); out = []
    for start in list(pts):
        if start in seen: continue
        stack = [start]; seen.add(start)
        y0 = y1 = start[0]; x0 = x1 = start[1]; n = 0
        while stack:
            y, x = stack.pop(); n += 1
            if y < y0: y0 = y
            if y > y1: y1 = y
            if x < x0: x0 = x
            if x > x1: x1 = x
            for nb in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
                if nb in pts and nb not in seen:
                    seen.add(nb); stack.append(nb)
        if n >= min_px:
            out.append({'n': n, 'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1})
    return out

def main():
    path = sys.argv[1]
    img = np.asarray(Image.open(path).convert('RGB')).astype(int)
    H, W = img.shape[:2]
    res = {'size': [W, H], 'kind': 'unknown', 'rows': [], 'chips': [], 'buttons': [], 'input': None, 'back': None}

    # non-background mask (anything that is not the flat page colour)
    diff = np.abs(img - BG[None, None, :]).max(axis=2)
    nb = diff > 12

    # horizontal structure lines: rows with a long non-bg run
    lines = []
    for y in range(int(H * 0.10), int(H * 0.97)):
        xs = np.where(nb[y])[0]
        for (s, e) in runs(xs.tolist(), 55):
            if e - s >= 55:
                lines.append((y, s, e))
    # merge lines on adjacent rows with the same extent
    merged = []
    for (y, s, e) in lines:
        if merged and y - merged[-1][0] <= 2 and abs(s - merged[-1][1]) <= 8 and abs(e - merged[-1][2]) <= 8:
            continue
        merged.append((y, s, e))

    # pair lines into boxes
    boxes = []
    for i, (y1, s1, e1) in enumerate(merged):
        for (y2, s2, e2) in merged[i + 1:]:
            h = y2 - y1
            if h < 20: continue
            if h > 95: break
            if abs(s1 - s2) <= 14 and abs(e1 - e2) <= 14:
                boxes.append({'x0': min(s1, s2), 'x1': max(e1, e2), 'y0': y1, 'y1': y2})
                break
    # dedupe
    seen = set(); uniq = []
    for b in boxes:
        k = (b['y0'] // 8, b['x0'] // 10)
        if k in seen: continue
        seen.add(k); uniq.append(b)
    # drop boxes that sit inside a bigger one (pairing artefacts)
    uniq.sort(key=lambda b: -(b['x1']-b['x0'])*(b['y1']-b['y0']))
    kept = []
    for b in uniq:
        cx = (b['x0']+b['x1'])/2.0; cy = (b['y0']+b['y1'])/2.0
        inside = False
        for k in kept:
            if k['x0']-4 <= cx <= k['x1']+4 and k['y0']-4 <= cy <= k['y1']+4:
                inside = True; break
        if not inside:
            kept.append(b)
    uniq = kept

    for b in uniq:
        w = b['x1'] - b['x0'] + 1; h = b['y1'] - b['y0'] + 1
        item = {'x': (b['x0'] + b['x1']) // 2, 'y': (b['y0'] + b['y1']) // 2, 'w': w, 'h': h}
        if h < 32:
            continue
        if w >= 300 and h >= 40:
            res['rows'].append(item)
        elif 45 <= w <= 320 and 28 <= h <= 85:
            res['chips'].append(item)
    res['rows'].sort(key=lambda o: o['y'])
    res['chips'].sort(key=lambda c: (c['y'], c['x']))
    for i, o in enumerate(res['rows'], 1): o['i'] = i
    for i, c in enumerate(res['chips'], 1): c['i'] = i

    # solid green blobs -> buttons / selected chips
    gm = (np.abs(img - GREEN[None, None, :]).max(axis=2) <= 45)
    for c in components(gm, 700):
        w = c['x1'] - c['x0'] + 1; h = c['y1'] - c['y0'] + 1
        if c['n'] < 0.6 * w * h: continue
        if w >= 140 and 26 <= h <= 95:
            res['buttons'].append({'x': (c['x0']+c['x1'])//2, 'y': (c['y0']+c['y1'])//2, 'w': w, 'h': h})
        elif 40 <= w < 140 and 20 <= h <= 80:
            res['chips'].append({'x': (c['x0']+c['x1'])//2, 'y': (c['y0']+c['y1'])//2, 'w': w, 'h': h, 'sel': True})
    res['buttons'].sort(key=lambda b: b['y'])
    for i, b in enumerate(res['buttons'], 1): b['i'] = i

    # spelling underline: a thin, single-colour horizontal line (text rows are not uniform)
    for y in range(int(H * 0.11), int(H * 0.26)):
        xs = np.where(nb[y])[0]
        for (s, e) in runs(xs.tolist(), 50):
            if not (50 <= e - s <= 360):
                continue
            seg = img[y, s:e + 1]
            if seg.std(axis=0).max() <= 14 and seg.mean(axis=0).min() > 90:
                res['input'] = {'x': (s + e) // 2, 'y': y - 12, 'w': e - s + 1, 'h': 24}
                break
        if res['input']: break

    # back control
    band = img[int(H * 0.05):int(H * 0.11), :int(W * 0.30)]
    dm = (band.max(axis=2) <= 130)
    ys, xs = np.nonzero(dm)
    if len(xs) > 15:
        res['back'] = {'x': int(xs.mean()), 'y': int(ys.mean()) + int(H * 0.05)}

    # page kind
    if len(res['rows']) >= 3:
        res['kind'] = 'options'
    elif len(res['chips']) >= 10:
        res['kind'] = 'grid'
    elif len(res['chips']) >= 3:
        res['kind'] = 'chips'
    elif res['input']:
        res['kind'] = 'spelling'
    elif res['buttons']:
        res['kind'] = 'dialog'

    print(json.dumps(res, ensure_ascii=False))
    if '--debug' in sys.argv:
        print('lines=%d boxes=%d' % (len(merged), len(uniq)), file=sys.stderr)

if __name__ == '__main__':
    main()
