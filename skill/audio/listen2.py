"""Record system audio via WASAPI loopback using the `soundcard` library,
then score against the TTS template bank (same matcher as listen.py).

Why: PortAudio (sounddevice) only exposes loopback for some endpoints; the
default speaker "扬声器 (Realtek(R) Audio)" is not one of them, while
soundcard can open a loopback recorder for the *default* speaker directly.

Usage:
  python listen2.py --seconds 3                 # record default-speaker loopback + match
  python listen2.py --seconds 3 --speaker "N50Pro 6"   # pick another speaker
  python listen2.py --match-only rec.wav        # score an existing wav
"""
import os, sys, json, glob, time, argparse
import numpy as np
import soundcard as sc
import listen as L

SR = 16000

def record(seconds, speaker_hint=''):
    spk = None
    if speaker_hint:
        for s in sc.all_speakers():
            if speaker_hint.lower() in s.name.lower():
                spk = s; break
    if spk is None:
        spk = sc.default_speaker()
    mic = sc.get_microphone(spk.name, include_loopback=True)
    try:
        rec = mic.recorder(samplerate=SR)
    except Exception:
        rec = mic.recorder(samplerate=48000)
    with rec as recorder:
        data = recorder.record(numframes=int(recorder.samplerate * seconds))
    a = np.asarray(data, dtype=np.float32)
    if a.ndim > 1:
        a = a.mean(axis=1)
    if recorder.samplerate != SR:
        t = np.linspace(0, len(a) / recorder.samplerate, num=int(len(a) * SR / recorder.samplerate), endpoint=False)
        a = np.interp(t, np.linspace(0, len(a) / recorder.samplerate, num=len(a), endpoint=False), a).astype(np.float32)
    return a, spk.name

def match(a, bank='templates'):
    at = L.trim(a)
    if len(at) == 0:
        return {'error': 'silent'}
    q = L.mfcc(at)
    out = []
    for wav in glob.glob(os.path.join(bank, '*.wav')):
        w = os.path.splitext(os.path.basename(wav))[0]
        b = L.trim(L.load_wav(wav))
        if len(b) == 0: continue
        out.append({'word': w, 'dist': round(L.dtw_dist(q, L.mfcc(b)), 3)})
    out.sort(key=lambda r: r['dist'])
    return {'dur': round(len(at) / SR, 2), 'peak': round(float(np.abs(a).max()), 3), 'ranking': out[:6]}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--seconds', type=float, default=3.0)
    p.add_argument('--speaker', default='')
    p.add_argument('--bank', default='templates')
    p.add_argument('--save', default='')
    p.add_argument('--match-only', default='')
    args = p.parse_args()
    if args.match_only:
        a = L.load_wav(args.match_only)
        print(json.dumps(match(a, args.bank), ensure_ascii=False)); return
    a, name = record(args.seconds, args.speaker)
    if args.save:
        L.save_wav(args.save, a)
    res = match(a, args.bank)
    res['speaker'] = name
    print(json.dumps(res, ensure_ascii=False))

if __name__ == '__main__':
    main()
