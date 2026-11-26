"""Score an existing wav against the template bank (no recording).

Usage: python match_file.py --wav last_rec.wav --bank templates
"""
import os, sys, json, glob, argparse
import numpy as np
import listen as L

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--wav', default='last_rec.wav')
    p.add_argument('--bank', default='templates')
    args = p.parse_args()
    bank = os.path.dirname(os.path.abspath(args.bank)) if False else args.bank
    a = L.load_wav(args.wav)
    at = L.trim(a)
    peak = float(np.abs(a).max()) if len(a) else 0.0
    if len(at) == 0:
        print(json.dumps({'error': 'silent', 'peak': round(peak, 4)})); return
    q = L.mfcc(at)
    out = []
    for wav in glob.glob(os.path.join(bank, '*.wav')):
        w = os.path.splitext(os.path.basename(wav))[0]
        b = L.trim(L.load_wav(wav))
        if len(b) == 0: continue
        out.append({'word': w, 'dist': round(L.dtw_dist(q, L.mfcc(b)), 3)})
    out.sort(key=lambda r: r['dist'])
    print(json.dumps({'peak': round(peak, 4), 'dur': round(len(at)/16000, 2), 'ranking': out[:6]}, ensure_ascii=False))

if __name__ == '__main__':
    main()
