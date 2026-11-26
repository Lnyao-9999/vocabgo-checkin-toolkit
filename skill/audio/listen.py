import sys, os, time, json, wave, glob
import numpy as np
import sounddevice as sd

SR = 16000

def pick_device(name_hint):
    devs = sd.query_devices()
    if name_hint and str(name_hint).isdigit():
        i = int(name_hint)
        if devs[i]['max_input_channels'] > 0:
            return i, devs[i]['name']
    if str(name_hint).lower() == 'loopback':
        # WASAPI loopback: a render endpoint exposed with input channels
        for i, d in enumerate(devs):
            if d['max_input_channels'] > 0:
                n = d['name'].lower()
                if 'output' in n or '扬声器' in d['name'] or 'speaker' in n:
                    return i, d['name']
        idx, name = sd.default.device[0], devs[sd.default.device[0]]['name']
        return idx, name
    for i, d in enumerate(devs):
        if d['max_input_channels'] > 0 and name_hint and name_hint in d['name']:
            return i, d['name']
    # fallback: default input
    di = sd.default.device[0]
    if di is not None and di >= 0:
        return di, devs[di]['name']
    return None, None

def record(seconds, hint, gain=1.0):
    idx, name = pick_device(hint)
    if idx is None:
        raise SystemExit('no input device')
    n = int(SR * seconds)
    try:
        audio = sd.rec(n, samplerate=SR, channels=1, dtype='float32', device=idx)
        sd.wait()
    except Exception:
        # fall back to the device's native samplerate, then resample
        native = int(sd.query_devices(idx)['default_samplerate'])
        audio = sd.rec(int(native * seconds), samplerate=native, channels=1, dtype='float32', device=idx)
        sd.wait()
        a = audio[:, 0]
        t = np.linspace(0, len(a) / native, num=n, endpoint=False)
        a = np.interp(t, np.linspace(0, len(a) / native, num=len(a), endpoint=False), a).astype(np.float32)
        return a * gain, name
    a = audio[:, 0] * gain
    return a, name

def save_wav(path, a):
    a = np.clip(a, -1.0, 1.0)
    pcm = (a * 32767.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())

def load_wav(path):
    with wave.open(path, 'rb') as w:
        n = w.getnframes(); ch = w.getnchannels(); sw = w.getsampwidth(); sr = w.getframerate()
        raw = w.readframes(n)
    if sw == 2:
        a = np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768.0
    elif sw == 4:
        a = np.frombuffer(raw, dtype='<i4').astype(np.float32) / 2147483648.0
    else:
        a = np.frombuffer(raw, dtype=np.uint8).astype(np.float32) / 128.0 - 1.0
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    if sr != SR:
        # simple linear resample
        t = np.linspace(0, len(a) / sr, num=int(len(a) * SR / sr), endpoint=False)
        a = np.interp(t, np.linspace(0, len(a) / sr, num=len(a), endpoint=False), a).astype(np.float32)
    return a

def trim(a, thresh_ratio=0.12, pad=0.08):
    if len(a) == 0: return a
    env = np.abs(a)
    # smooth
    k = max(1, int(SR * 0.01))
    env = np.convolve(env, np.ones(k) / k, mode='same')
    peak = env.max()
    if peak <= 1e-6: return a[:0]
    mask = env > peak * thresh_ratio
    idx = np.where(mask)[0]
    if len(idx) == 0: return a[:0]
    s = max(0, idx[0] - int(SR * pad)); e = min(len(a), idx[-1] + int(SR * pad))
    return a[s:e]

def mel_fb(n_mels=26, n_fft=512, sr=SR):
    def hz2mel(f): return 2595.0 * np.log10(1.0 + f / 700.0)
    def mel2hz(m): return 700.0 * (10.0 ** (m / 2595.0) - 1.0)
    mels = np.linspace(hz2mel(80), hz2mel(sr / 2), n_mels + 2)
    hz = mel2hz(mels)
    bins = np.floor((n_fft + 1) * hz / sr).astype(int)
    fb = np.zeros((n_mels, n_fft // 2 + 1), dtype=np.float32)
    for m in range(1, n_mels + 1):
        l, c, r = bins[m - 1], bins[m], bins[m + 1]
        if r <= l: continue
        for k in range(l, min(c, fb.shape[1])):
            fb[m - 1, k] = (k - l) / max(1, c - l)
        for k in range(c, min(r, fb.shape[1])):
            fb[m - 1, k] = (r - k) / max(1, r - c)
    return fb

FB = mel_fb()

def mfcc(a, n_mfcc=13, win=0.025, hop=0.010):
    if len(a) < int(SR * 0.05): return np.zeros((1, n_mfcc), dtype=np.float32)
    a = np.append(a[0], a[1:] - 0.97 * a[:-1])  # pre-emphasis
    wl = int(SR * win); hl = int(SR * hop)
    if len(a) < wl: a = np.pad(a, (0, wl - len(a)))
    frames = 1 + max(0, (len(a) - wl) // hl)
    idx = np.arange(wl)[None, :] + hl * np.arange(frames)[:, None]
    F = a[idx] * np.hamming(wl)[None, :]
    spec = np.abs(np.fft.rfft(F, n=512)) ** 2
    mel = spec @ FB.T
    logmel = np.log(mel + 1e-10)
    # DCT-II
    n = logmel.shape[1]
    k = np.arange(n_mfcc)[:, None]; m = np.arange(n)[None, :]
    dct = np.cos(np.pi * k * (2 * m + 1) / (2 * n)) * np.sqrt(2.0 / n)
    cc = logmel @ dct.T
    cc = cc[:, 1:]  # drop c0
    cc = (cc - cc.mean(axis=0)) / (cc.std(axis=0) + 1e-6)
    return cc.astype(np.float32)

def dtw_dist(A, B):
    n, m = len(A), len(B)
    if n == 0 or m == 0: return 1e9
    D = np.full((n + 1, m + 1), np.inf, dtype=np.float32)
    D[0, 0] = 0
    for i in range(1, n + 1):
        ai = A[i - 1]
        for j in range(1, m + 1):
            cost = np.sqrt(((ai - B[j - 1]) ** 2).sum())
            D[i, j] = cost + min(D[i - 1, j], D[i, j - 1], D[i - 1, j - 1])
    return float(D[n, m] / (n + m))

def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--seconds', type=float, default=3.0)
    p.add_argument('--device', default='loopback')
    p.add_argument('--templates', default='templates')
    p.add_argument('--save', default='last_rec.wav')
    p.add_argument('--gain', type=float, default=1.0)
    p.add_argument('--prewait', type=float, default=0.0)
    args = p.parse_args()

    if args.prewait > 0: time.sleep(args.prewait)
    a, name = record(args.seconds, args.device, args.gain)
    save_wav(args.save, a)
    rms = float(np.sqrt(np.mean(a ** 2))) if len(a) else 0.0
    peak = float(np.abs(a).max()) if len(a) else 0.0
    if peak > 0.95 and peak > 0:
        a = a * (0.9 / peak)   # avoid clipping artefacts
    at = trim(a)
    if len(at) == 0:
        print(json.dumps({'error': 'silent', 'device': name, 'rms': round(rms, 5), 'peak': round(peak, 4)}))
        return
    q = mfcc(at)
    results = []
    for wav in sorted(glob.glob(os.path.join(args.templates, '*.wav'))):
        b = trim(load_wav(wav))
        if len(b) == 0: continue
        t = mfcc(b)
        results.append({'word': os.path.splitext(os.path.basename(wav))[0], 'dist': round(dtw_dist(q, t), 3)})
    results.sort(key=lambda r: r['dist'])
    print(json.dumps({'device': name, 'rms': round(rms, 5), 'peak': round(peak, 4),
                      'dur': round(len(at) / SR, 2), 'ranking': results[:6]}, ensure_ascii=False))

if __name__ == '__main__':
    main()
