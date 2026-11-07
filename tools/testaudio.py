#!/usr/bin/env python3
"""Audio-quality tests: is there anything between the file and clean sound?

Synthetic signals (sines, a sweep, square waves, noise, DC, silence, impulses, two-tone stereo, 6 channels) are
written as 16-bit WAV and as FLAC (16 and 24 bit, written by the ground-truth encoder in mkflac.py), played through the
real tool, and judged on the OUTPUT alone, the way an ear or an analyser would:

  exactness      the output is the source, sample for sample (24-bit sources: truncated to 16 bits, nothing else)
  stutter        the same bytes come out however the callback sizes its requests (1 frame, random sizes, one huge
                 request); the stream has exactly the promised length; seeks land on the right sample at every
                 frame edge and its neighbours
  clicks         no step between consecutive samples larger than the signal itself allows
  spectrum       a coherent sine comes out with the SINAD of its own bit depth and no spurious tone above -90 dBFS
  channels       left is left, right is right, mono is on both, 6 channels leak nothing into the stereo pair
  level          volume is the exact q8 gain; 0 is silence; 256 is untouched; DC and silence stay put; full-scale
                 peaks neither wrap nor clip wrongly
  damage         a flipped bit never produces noise: the damaged frame is silence (or dropped), everything else exact

    testaudio.py [--tool build/peepdump] [--seed N]        testaudio.py --gen DIR   (write the signals as files)
"""
import argparse, os, random, struct, subprocess, sys, tempfile
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
import mkflac

ap = argparse.ArgumentParser()
ap.add_argument('--tool', default='build/peepdump'); ap.add_argument('--seed', type=int, default=1); ap.add_argument('--gen')
a = ap.parse_args()
RATE = 44100; N = 16384            # 2^14 frames: a coherent window for FFTs

def sine(k, amp, n=N, ph=0.0): return amp * np.sin(2 * np.pi * k * np.arange(n) / n + ph)      # k whole cycles in n frames

def signals(bps):
    """name -> list of channel arrays (int64, in the integer range of `bps` bits)"""
    m = (1 << (bps - 1)) - 1; rng = np.random.RandomState(7)
    q = lambda x: np.clip(np.rint(x), -m - 1, m).astype(np.int64)
    t = np.arange(N) / RATE
    sweep = np.sin(2 * np.pi * 20 * (1000 ** (t / t[-1]) - 1) * t[-1] / np.log(1000))
    imp = np.zeros(N); imp[::997] = 1.0; imp[5] = -1.0
    return {
        'sine1k_-1dB': [q(m * 0.891 * sine(371, 1.0))], 'sine_fullscale': [q(m * sine(371, 1.0, ph=1.0))],
        'sine_20Hz': [q(m * 0.5 * sine(8, 1.0))], 'sine_18k': [q(m * 0.5 * sine(6690, 1.0))],
        'sweep': [q(m * 0.8 * sweep)], 'square_fullscale': [q(m * np.where(sine(37, 1.0) >= 0, 1.0, -1.0))],
        'noise': [q(m * rng.uniform(-1, 1, N))], 'dc': [np.full(N, m // 3 + 7, dtype=np.int64)], 'silence': [np.zeros(N, dtype=np.int64)],
        'impulses': [q(m * imp)], 'extremes': [np.array(([m, -m - 1] * 4 + [0, 0, m, m, -m - 1, -m - 1]) * 40, dtype=np.int64)],
        'two_tone': [q(m * 0.7 * sine(371, 1.0)), q(m * 0.7 * sine(1113, 1.0))],
        'six_channels': [q(m * 0.5 * sine(60 + 37 * c, 1.0)) for c in range(6)],
    }

def wav16(chans, rate=RATE):
    pcm = np.stack(chans, axis=1).astype('<i2'); ch = len(chans); body = pcm.tobytes()
    f = struct.pack('<HHIIHH', 1, ch, rate, rate * ch * 2, ch * 2, 16)
    return b'RIFF' + struct.pack('<I', 36 + len(body)) + b'WAVE' + b'fmt ' + struct.pack('<I', 16) + f + b'data' + struct.pack('<I', len(body)) + body

def flac(chans, bps, block=4096, rate=RATE):
    """-> (file bytes, [first sample of each FLAC frame], [byte length of each FLAC frame])"""
    rng = random.Random(3); total = len(chans[0]); frames = []; starts = []; pos = 0
    while pos < total:
        bs = min(block, total - pos)
        fb, _ = mkflac.encode_frame([c[pos:pos + bs] for c in chans], pos, len(frames), False, rate, bps, True, rng)
        frames.append(fb); starts.append(pos); pos += bs
    si = mkflac.streaminfo(block, block, rate, len(chans), bps, total)
    return b'fLaC' + bytes([0x80]) + len(si).to_bytes(3, 'big') + si + b''.join(frames), starts, [len(f) for f in frames]

def corpus():
    """(name, file bytes, source channels, bps, frame starts)"""
    out = []
    for name, ch in signals(16).items(): out.append(('wav16/' + name, wav16(ch), ch, 16, None))
    for bps in (16, 24):
        for name, ch in signals(bps).items():
            b, st, _ = flac(ch, bps, 4096 if name != 'extremes' else 192); out.append((f'flac{bps}/{name}', b, ch, bps, st))
    return out

if a.gen:
    os.makedirs(a.gen, exist_ok=True)
    for name, data, *_ in corpus():
        open(os.path.join(a.gen, name.replace('/', '_') + ('.wav' if name.startswith('wav') else '.flac')), 'wb').write(data)
    sys.exit(0)

checks = bad = 0
def check(name, ok, info=''):
    global checks, bad
    checks += 1
    if not ok:
        bad += 1; print(f'FAIL {name} {info}')

def play(data, *extra, chunk=1024):
    cmd = [a.tool, '-c', str(chunk), *extra]
    with tempfile.NamedTemporaryFile(suffix='.bin') as f:
        f.write(data); f.flush(); r = subprocess.run(cmd + [f.name], capture_output=True)
    out = r.stdout
    return r.returncode, (np.frombuffer(out, dtype='<i2').reshape(-1, 2).astype(np.int64) if len(out) % 4 == 0 else None)

def modern():
    """Library 0.4.0+ reports `bits=` and applies the volume to >16-bit sources before reducing to 16 bits."""
    d = flac([np.zeros(64, dtype=np.int64)], 24, 64)[0]
    with tempfile.NamedTemporaryFile(suffix='.flac') as f:
        f.write(d); f.flush(); r = subprocess.run([a.tool, '-E', f.name], capture_output=True)
    return b'bits=24' in r.stderr

WIDE = modern()

def expected(chans, bps, gain=256):
    st = np.repeat(chans[0][:, None], 2, axis=1) if len(chans) == 1 else np.stack(chans[:2], axis=1)
    if WIDE and bps > 16 and gain != 256: return (((st << (32 - bps)) * gain) >> 8) >> 16
    return ((st >> max(0, bps - 16)) * gain) >> 8

def tone_quality(x, k):
    """x: one channel, a coherent sine with k cycles in len(x) samples -> (SINAD in dB, largest spurious bin in dBFS)"""
    X = np.abs(np.fft.rfft(x.astype(np.float64))) / len(x) * 2       # amplitude spectrum
    sig = X[k]; X[0] = 0; X[k - 1:k + 2] = 0                         # leave out DC and the tone itself
    noise = np.sqrt(np.sum(X ** 2) / 2)                              # rms of everything else
    return 20 * np.log10((sig / np.sqrt(2)) / max(noise, 1e-9)), 20 * np.log10(max(X.max(), 1e-9) / 32768)

for name, data, chans, bps, starts in corpus():
    want = expected(chans, bps)
    rc, out = play(data)
    ok = rc == 0 and out is not None
    # --- exactness and length
    check(name + ' exact', ok and np.array_equal(out, want), 'first diff at %s' % (np.nonzero(out.ravel() != want.ravel())[0][:3] if ok and out.shape == want.shape else 'shape'))
    check(name + ' length', ok and len(out) == len(chans[0]), f'{None if out is None else len(out)} != {len(chans[0])}')
    # --- stutter: request sizes must not matter
    for label, opts in (('1 frame', ['-c', '1']), ('random A', ['-c', '3000', '-R', '11']), ('random B', ['-c', '97', '-R', '12']), ('one huge request', ['-c', '99999'])):
        if label == '1 frame' and len(chans[0]) > 20000: continue
        rc, o2 = play(data, *opts)
        check(f'{name} callback {label}', rc == 0 and o2 is not None and np.array_equal(o2, want))
    # --- clicks: no step bigger than the signal allows (judged on the output only)
    if name.split('/')[1] in ('sine1k_-1dB', 'sine_fullscale', 'sine_20Hz', 'sine_18k', 'two_tone'):
        k = {'sine1k_-1dB': 371, 'sine_fullscale': 371, 'sine_20Hz': 8, 'sine_18k': 6690, 'two_tone': 1113}[name.split('/')[1]]
        amp = 32768 * (0.891 if '1dB' in name else 0.5 if ('20Hz' in name or '18k' in name) else 1.0 if 'full' in name else 0.7)
        bound = amp * 2 * np.sin(np.pi * k / N) + 2
        rc, o2 = play(data, '-c', '500', '-R', '5')
        steps = np.abs(np.diff(o2, axis=0)).max() if o2 is not None else 1e9
        check(name + ' no clicks (largest step %d, allowed %d)' % (steps, bound), steps <= bound)
    # --- spectrum of coherent sines: the SINAD of 16-bit quantisation, no spurs
    if name.split('/')[1] in ('sine1k_-1dB', 'sine_20Hz', 'sine_18k'):
        k = {'sine1k_-1dB': 371, 'sine_20Hz': 8, 'sine_18k': 6690}[name.split('/')[1]]
        snr, spur = tone_quality(out[:, 0], k)
        check(f'{name} SINAD {snr:.1f} dB', snr >= 90 if 'sine_20Hz' not in name else snr >= 85)
        check(f'{name} spurious tones {spur:.1f} dBFS', spur <= -90)
    # --- channels
    if len(chans) == 2:
        check(name + ' left/right not swapped, no crosstalk', ok and np.array_equal(out[:, 0], want[:, 0]) and np.array_equal(out[:, 1], want[:, 1]) and not np.array_equal(out[:, 0], out[:, 1]))
    if len(chans) == 6: check(name + ' only the first two channels reach the output', ok and out.shape[1] == 2 and np.array_equal(out, want))
    # --- level: exact q8 gain
    if name.split('/')[1] in ('noise', 'sine_fullscale', 'extremes', 'dc', 'two_tone'):
        for g in (255, 164, 77, 1, 0):
            rc, o2 = play(data, '-g', str(g), '-R', str(g + 1), '-c', '777')
            check(f'{name} gain {g}', rc == 0 and o2 is not None and np.array_equal(o2, expected(chans, bps, g)))
    if name.split('/')[1] == 'silence': check(name + ' silence stays silent', ok and not out.any())
    if name.split('/')[1] == 'dc': check(name + ' DC is held', ok and (out == out[0]).all())
    if name.split('/')[1] in ('square_fullscale', 'extremes', 'sine_fullscale'):
        hi = (chans[0] > 0); check(name + ' peaks do not wrap', ok and (out[hi[:len(out)], 0] > 0).all() and (out[~hi[:len(out)] & (chans[0] < 0), 0] < 0).all())
    # --- a file cut short plays what is there, exactly, and then stops: no garbage, no read past the end
    if name.split('/')[1] in ('noise', 'two_tone'):
        for cut in (1, 3, 5, 6, 7, 1001):
            rc, o2 = play(data[:len(data) - cut], '-R', str(cut))
            n2 = 0 if o2 is None else len(o2)
            if starts is None:      # WAV: every complete frame that is left, nothing else
                ok_ = rc == 0 and o2 is not None and n2 == (len(data) - cut - 44) // (2 * len(chans)) and np.array_equal(o2, want[:n2])
            else:                   # FLAC: the frames that are complete come out exact; the cut one may only be dropped or silent
                ok_ = o2 is not None and np.array_equal(o2[:max(0, n2 - 4096)], want[:max(0, n2 - 4096)]) and n2 <= len(want) and (n2 == 0 or not o2[-1:].any() or np.array_equal(o2[-4096:], want[n2 - 4096:n2]))
            check(f'{name} cut short by {cut} bytes', ok_, f'{n2} frames')
    # --- seeks: every edge and its neighbours
    if starts:
        pts = sorted({0, 1, len(chans[0]) - 1, len(chans[0]), len(chans[0]) + 7} | {max(0, s + d) for s in starts[1:] for d in (-2, -1, 0, 1)})
        for t in pts[:: max(1, len(pts) // 14)]:
            rc, o2 = play(data, '-s', str(t), '-R', str(t + 3), '-c', '1500')
            check(f'{name} seek to {t}', rc == 0 and o2 is not None and np.array_equal(o2, want[min(t, len(want)):]))

# --- damage: a flipped bit may silence a frame or drop it, but must never make noise
for bps in (16, 24):
    ch = signals(bps)['sine1k_-1dB']; data, starts, sizes = flac(ch, bps, 2048); want = expected(ch, bps); rng = random.Random(bps)
    base = len(data) - sum(sizes)
    for trial in range(12):
        fr = rng.randrange(1, len(starts) - 1); lo = base + sum(sizes[:fr]); hi = lo + sizes[fr]
        d = bytearray(data); pos = rng.randrange(lo + 6, hi - 2); d[pos] ^= 1 << rng.randrange(8)
        rc, o2 = play(bytes(d)); s0 = starts[fr]
        if rc != 0 or o2 is None: check(f'flac{bps} damaged frame {fr}', False, 'rejected'); continue
        if len(o2) == len(want): ok_ = np.array_equal(o2[:s0], want[:s0]) and not o2[s0:s0 + 2048].any() and np.array_equal(o2[s0 + 2048:], want[s0 + 2048:])
        else: ok_ = len(o2) == len(want) - 2048 and np.array_equal(o2[:s0], want[:s0]) and np.array_equal(o2[s0:], want[s0 + 2048:])
        check(f'flac{bps} damaged frame {fr}: silence or drop, never noise', ok_)

print(f'{checks} audio checks, {bad} failures'); sys.exit(1 if bad else 0)
