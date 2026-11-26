"""Self-test: play TTS templates through the PC speakers, record via the mic,
and score the matcher on a candidate subset.

Usage:
  python selftest.py --words beam,midst,groan,compliment --device 6 --gain 12
  python selftest.py --words beam,midst,groan,compliment --device 6 --gain 12 --bank templates
"""
import os, sys, time, json, glob, argparse, winsound
import numpy as np
import listen as L

HERE = os.path.dirname(os.path.abspath(__file__))

def load_templates(bank):
    out = {}
    for wav in glob.glob(os.path.join(bank, '*.wav')):
        w = os.path.splitext(os.path.basename(wav))[0]
        b = L.trim(L.load_wav(wav))
        if len(b) > 0:
            out[w] = L.mfcc(b)
    return out

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--words', required=True)
    p.add_argument('--bank', default=os.path.join(HERE, 'templates'))
    p.add_argument('--device', default='6')
    p.add_argument('--gain', type=float, default=12.0)
    p.add_argument('--seconds', type=float, default=2.5)
    p.add_argument('--reps', type=int, default=1)
    args = p.parse_args()

    played = [w.strip() for w in args.words.split(',') if w.strip()]
    tpl = load_templates(args.bank)
    print('bank_size=%d playing=%s device=%s' % (len(tpl), played, args.device))

    ok = 0; total = 0; rows = []
    for rep in range(args.reps):
        for w in played:
            path = os.path.join(args.bank, w + '.wav')
            if not os.path.exists(path):
                print('skip', w, '(no template)'); continue
            winsound.PlaySound(path, winsound.SND_FILENAME | winsound.SND_ASYNC)
            time.sleep(0.15)
            a, name = L.record(args.seconds, args.device, args.gain)
            at = L.trim(a)
            if len(at) == 0:
                rows.append((w, 'SILENT', '', 0)); total += 1; continue
            q = L.mfcc(at)
            scores = sorted(((L.dtw_dist(q, t), k) for k, t in tpl.items()))
            top = scores[0][1]
            rank = [k for _, k in scores].index(w) + 1
            good = (top == w)
            ok += 1 if good else 0; total += 1
            rows.append((w, top, 'OK' if good else 'MISS#%d' % rank, round(scores[0][0], 2)))
            time.sleep(0.2)

    print('--- results ---')
    for r in rows:
        print('  %-12s -> %-12s %-8s %s' % r)
    print('ACCURACY: %d/%d = %.0f%%' % (ok, total, 100.0 * ok / max(1, total)))

if __name__ == '__main__':
    main()
