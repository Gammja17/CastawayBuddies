#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Castaway Buddies (무인도 버디즈) - procedural audio generator.

Renders every music loop, ambience loop and sound effect from scratch with
numpy (no samples, no downloads). Deterministic: every file has a fixed seed.

    python tools/gen_audio.py              # render everything
    python tools/gen_audio.py day ocean    # render only some files (by name)

Output: assets/audio/{music,amb,sfx}/*.wav  (44.1 kHz, 16-bit PCM)

Looping files are rendered *circularly*: every note, decay and reverb tail
that runs past the loop end is wrapped back onto the start, so the file loops
sample-seamlessly. Looping files also carry a RIFF 'smpl' chunk (forward loop
over the whole file) which Godot's WAV importer picks up when the import
option "Loop Mode" is left at "Detect From WAV".
"""
import os
import struct
import sys
import time
import wave

import numpy as np

SR = 44100
TWO_PI = 2.0 * np.pi
PEAK_DB = -3.0
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "audio")
VERBOSE = bool(os.environ.get("CB_AUDIO_VERBOSE"))


# =============================================================================
# Basics
# =============================================================================
def nsamp(t):
    return int(round(t * SR))


def tvec(n):
    return np.arange(n) / SR


def hz(m):
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def nm(name):
    """Note name -> MIDI number ('C4' = 60, 'Bb3' = 58, 'F#5' = 78)."""
    pc = _PC[name[0].upper()]
    i = 1
    while i < len(name) and name[i] in "#b":
        pc += 1 if name[i] == "#" else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + pc


def db(x):
    return 20.0 * np.log10(max(float(x), 1e-12))


def rms(x):
    return float(np.sqrt(np.mean(np.square(x))))


# =============================================================================
# Filters (zero-phase FFT filters; circular for loops)
# =============================================================================
def rfreqs(n):
    return np.fft.rfftfreq(n, 1.0 / SR)


def lp(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def bump(fc, gain_db, width_oct=1.0):
    """Bell EQ: gain_db at fc, gaussian in log-frequency."""
    def h(f):
        d = np.log2(np.maximum(f, 1.0) / fc) / (width_oct / 2.0)
        return 10.0 ** (gain_db * np.exp(-0.5 * d * d) / 20.0)
    return h


def chain(*hs):
    def h(f):
        g = np.ones_like(f, dtype=float)
        for x in hs:
            g = g * x(f)
        return g
    return h


def pink(f):
    """-3 dB/octave magnitude tilt, unity at 1 kHz."""
    return 1.0 / np.sqrt(np.maximum(f, 20.0) / 1000.0)


def fast_len(n):
    best = 1 << max(0, (n - 1).bit_length())
    p5 = 1
    while p5 < best:
        p35 = p5
        while p35 < best:
            q = p35
            while q < n:
                q *= 2
            best = min(best, q)
            p35 *= 3
        p5 *= 5
    return best


def fft_filter(x, h, loop, pad=0.2):
    x = np.asarray(x, dtype=float)
    n = x.shape[-1]
    if loop:
        return np.fft.irfft(np.fft.rfft(x, axis=-1) * h(rfreqs(n)), n=n, axis=-1)
    p = nsamp(pad)
    m = fast_len(n + 2 * p)
    buf = np.zeros(x.shape[:-1] + (m,))
    buf[..., p:p + n] = x
    y = np.fft.irfft(np.fft.rfft(buf, axis=-1) * h(rfreqs(m)), n=m, axis=-1)
    return y[..., p:p + n]


# =============================================================================
# Envelopes / curves
# =============================================================================
def gate_env(n, dur, attack=0.005, release=0.05):
    """Raised-cos attack, hold until `dur`, raised-cos release, then silence."""
    e = np.ones(n)
    na = min(n, max(1, nsamp(attack)))
    e[:na] = 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    rs = max(0, nsamp(dur))
    nr = max(1, nsamp(release))
    if rs < n:
        k = min(nr, n - rs)
        e[rs:rs + k] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / nr)
        e[rs + k:] = 0.0
    return e


def env_perc(n, attack, tau, release=0.01):
    """Raised-cos attack -> exponential decay, short fade at the very end."""
    e = np.exp(-tvec(n) / tau)
    na = min(n, max(1, nsamp(attack)))
    e[:na] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    nr = min(n, max(1, nsamp(release)))
    e[n - nr:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr)
    return e


def fade_edges(x, a=0.001, r=0.02):
    x = np.array(x, dtype=float)
    n = x.shape[-1]
    na = min(n, max(1, nsamp(a)))
    nr = min(n, max(1, nsamp(r)))
    x[..., :na] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    x[..., n - nr:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr)
    return x


def smooth_curve(points, n, smooth_ms=10.0):
    """Piecewise-linear breakpoints [(t, v), ...] smoothed by a Hann kernel."""
    ts = np.array([p[0] for p in points], dtype=float)
    vs = np.array([p[1] for p in points], dtype=float)
    y = np.interp(tvec(n), ts, vs)
    k = nsamp(smooth_ms / 1000.0)
    if k > 2:
        ker = np.hanning(k)
        ker /= ker.sum()
        padded = np.concatenate([np.full(k, y[0]), y, np.full(k, y[-1])])
        y = np.convolve(padded, ker, mode="same")[k:k + n]
    return y


def smooth_random(n, rate_hz, rng, smooth_ms=30.0):
    """Smooth random wobble in [-1, 1]."""
    k = max(2, int(n / SR * rate_hz) + 2)
    pts = [(i * (n / SR) / (k - 1), v) for i, v in enumerate(rng.uniform(-1, 1, k))]
    return smooth_curve(pts, n, smooth_ms)


def periodic_lfo(rng, period, kmax=6, slope=1.0):
    """Smooth random function of time, exactly periodic in `period`, ~[-1, 1]."""
    ks = np.arange(1, kmax + 1)
    amps = 1.0 / ks ** slope
    phs = rng.uniform(0, TWO_PI, kmax)
    norm = amps.sum() * 0.6

    def f(t):
        v = 0.0
        for k, a, p in zip(ks, amps, phs):
            v = v + a * np.sin(TWO_PI * k * t / period + p)
        return np.clip(v / norm, -1.0, 1.0)
    return f


# =============================================================================
# Noise
# =============================================================================
class NoisePool:
    """Pre-filtered noise; hits take random slices (cheap per-hit noise)."""

    def __init__(self, rng, h, seconds=2.0):
        x = fft_filter(rng.standard_normal(nsamp(seconds)), h, loop=True)
        self.x = x / (np.std(x) + 1e-12)
        self.rng = rng

    def take(self, n):
        s = int(self.rng.integers(0, len(self.x) - n))
        return self.x[s:s + n].copy()


def spectral_noise(n, mag_fn, rng, loop=True, nfft=1764):
    """Noise with a time-varying spectrum, synthesised frame by frame.

    mag_fn(t, f) -> magnitude, with t = frame-centre times (k, 1) and
    f = bin frequencies (1, bins). A magnitude of 1 everywhere gives
    unit-variance white noise. loop=True wraps the overlap-add circularly.
    """
    hop = nfft // 4
    win = 0.5 - 0.5 * np.cos(TWO_PI * np.arange(nfft) / nfft)
    f = rfreqs(nfft)[None, :]
    scale = np.sqrt(nfft / 1.5)
    if loop:
        if n % hop:
            raise ValueError("loop length must be a multiple of the hop size")
        nfr = n // hop
        starts = np.arange(nfr) * hop
        out = np.zeros(n)
    else:
        nfr = int(np.ceil((n + nfft) / hop)) + 1
        starts = np.arange(nfr) * hop - nfft
        out = np.zeros(nfr * hop + 2 * nfft)
    centers = (starts + nfft / 2.0) / SR
    if loop:
        centers = centers % (n / SR)
    for c0 in range(0, nfr, 256):
        c1 = min(nfr, c0 + 256)
        mag = np.broadcast_to(mag_fn(centers[c0:c1, None], f), (c1 - c0, f.shape[1]))
        spec = mag * np.exp(1j * rng.uniform(0, TWO_PI, mag.shape))
        frames = np.fft.irfft(spec, n=nfft, axis=1) * (win * scale)
        for j in range(c1 - c0):
            s = int(starts[c0 + j])
            if loop:
                e = s + nfft
                if e <= n:
                    out[s:e] += frames[j]
                else:
                    k = n - s
                    out[s:] += frames[j, :k]
                    out[:e - n] += frames[j, k:]
            else:
                o = s + nfft
                out[o:o + nfft] += frames[j]
    return out if loop else out[nfft:nfft + n]


# =============================================================================
# Mixing, reverb, mastering, WAV output
# =============================================================================
class Bus:
    """Mono or stereo accumulation buffer. loop=True wraps writes circularly."""

    def __init__(self, n, ch=1, loop=False):
        self.x = np.zeros((ch, n))
        self.n, self.ch, self.loop = n, ch, loop

    def add(self, sig, t, gain=1.0, pan=0.0):
        sig = np.asarray(sig, dtype=float)
        if self.ch == 2:
            a = (np.clip(pan, -1, 1) + 1.0) * np.pi / 4.0
            gains = (np.cos(a) * np.sqrt(2.0) * gain, np.sin(a) * np.sqrt(2.0) * gain)
        else:
            gains = (gain,)
        i0 = int(round(t * SR))
        m = len(sig)
        if self.loop:
            i0 %= self.n
            pos = 0
            while pos < m:
                s = (i0 + pos) % self.n
                k = min(m - pos, self.n - s)
                for c in range(self.ch):
                    self.x[c, s:s + k] += gains[c] * sig[pos:pos + k]
                pos += k
        else:
            s0, e0 = max(0, i0), min(self.n, i0 + m)
            if e0 > s0:
                for c in range(self.ch):
                    self.x[c, s0:e0] += gains[c] * sig[s0 - i0:e0 - i0]


def make_ir(t60, seed, damp=0.45, predelay=0.02, length=None):
    """Synthetic diffuse reverb IR: noise with band-dependent exponential decay."""
    length = length if length is not None else min(max(t60 * 1.3, 0.6), 4.0)
    n = nsamp(length)
    rng = np.random.default_rng(seed)
    t = tvec(n)
    X = np.fft.rfft(rng.standard_normal(n))
    f = rfreqs(n)
    w_lo = 1.0 / (1.0 + (f / 450.0) ** 2)
    w_hi = (f / 3500.0) ** 2 / (1.0 + (f / 3500.0) ** 2)
    w_mid = np.clip(1.0 - w_lo - w_hi, 0.0, None)
    ir = np.zeros(n)
    for w, tt in ((w_lo, 1.15 * t60), (w_mid, t60), (w_hi, damp * t60)):
        ir += np.fft.irfft(X * w, n=n) * np.exp(-6.9078 * t / tt)
    ir *= 1.0 - np.exp(-t / 0.006)
    pd = nsamp(predelay)
    ir = np.concatenate([np.zeros(pd), ir])[:n]
    k = nsamp(0.1)
    ir[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)
    return ir / np.sqrt(np.sum(ir ** 2))


def convolve_ir(mono, irs, loop):
    """Convolve a mono send with one IR per output channel -> (len(irs), n)."""
    n = len(mono)
    out = []
    if loop:
        M = np.fft.rfft(mono)
        for ir in irs:
            irp = np.zeros(n)
            k = min(len(ir), n)
            irp[:k] = ir[:k]
            out.append(np.fft.irfft(M * np.fft.rfft(irp), n=n))
    else:
        m = fast_len(n + max(len(ir) for ir in irs))
        M = np.fft.rfft(mono, n=m)
        for ir in irs:
            out.append(np.fft.irfft(M * np.fft.rfft(ir, n=m), n=m)[:n])
    return np.array(out)


def master(x, drive=1.4, peak_db=PEAK_DB, loop=False):
    """tanh soft limiter + peak normalisation (pointwise: keeps loops seamless)."""
    x = np.atleast_2d(np.asarray(x, dtype=float))
    if loop:
        x = x - x.mean(axis=-1, keepdims=True)
    pk = np.max(np.abs(x))
    if pk <= 0:
        return x
    x = np.tanh(drive * x / pk) / np.tanh(drive)
    return x * (10.0 ** (peak_db / 20.0) / np.max(np.abs(x)))


class Song:
    """Named instrument buses -> EQ -> dry sum + shared reverb send -> master."""

    def __init__(self, n, stereo, loop):
        self.n, self.ch, self.loop = n, (2 if stereo else 1), loop
        self.buses, self.cfg = {}, {}

    def bus(self, name, gain=1.0, eq=None, send=0.0):
        if name not in self.buses:
            self.buses[name] = Bus(self.n, self.ch, self.loop)
            self.cfg[name] = (gain, eq, send)
        return self.buses[name]

    def mixdown(self, t60=1.5, damp=0.45, predelay=0.02, rev_gain=1.0,
                master_eq=None, drive=1.4, seed=0, fade_out=0.0):
        dry = np.zeros((self.ch, self.n))
        send = np.zeros(self.n)
        levels = []
        for name, b in self.buses.items():
            gain, eq, s = self.cfg[name]
            x = b.x if eq is None else fft_filter(b.x, eq, self.loop)
            x = x * gain
            levels.append((name, db(rms(x))))
            dry += x
            send += s * x.mean(axis=0)
        irs = [make_ir(t60, seed=seed + 17 * c, damp=damp, predelay=predelay) for c in range(self.ch)]
        out = dry + rev_gain * convolve_ir(send, irs, self.loop)
        if master_eq is not None:
            out = fft_filter(out, master_eq, self.loop)
        if fade_out > 0:
            k = nsamp(fade_out)
            out[:, -k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)
        if VERBOSE:
            print("    bus RMS: " + ", ".join("%s %.1f" % lv for lv in levels))
        return master(out, drive=drive, loop=self.loop)


def write_wav(path, x, loop=False):
    x = np.atleast_2d(x)
    ch, n = x.shape
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    if os.path.dirname(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.T.reshape(-1).tobytes())
    if loop:
        # RIFF 'smpl' chunk: one forward loop over the whole file (end inclusive).
        body = struct.pack("<9I", 0, 0, int(round(1e9 / SR)), 60, 0, 0, 0, 1, 0)
        body += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        with open(path, "r+b") as fh:
            fh.seek(0, 2)
            fh.write(b"smpl" + struct.pack("<I", len(body)) + body)
            size = fh.tell()
            fh.seek(4)
            fh.write(struct.pack("<I", size - 8))


def read_wav(path):
    with wave.open(path, "rb") as w:
        ch, n = w.getnchannels(), w.getnframes()
        raw = w.readframes(n)
    return (np.frombuffer(raw, dtype="<i2").astype(float) / 32768.0).reshape(n, ch).T


# =============================================================================
# Instruments (all return mono float arrays starting at the note onset)
# =============================================================================
def ks_pluck(freq, dur, rng, t60=1.2, bright=0.5, pos=0.18, release=0.04):
    """Karplus-Strong plucked string with fractional-delay tuning.

    The loop filter only reads samples >= N back, so it is computed one
    period-sized block at a time (vectorised)."""
    n = nsamp(dur + release) + 1
    P = SR / freq
    N = int(np.floor(P - 0.5))
    d = P - 0.5 - N
    h0, h1, h2 = 0.5 * (1.0 - d), 0.5, 0.5 * d          # avg filter * linear interp
    g = 10.0 ** (-3.0 / (t60 * freq))                   # per-period loss
    total = max(n, N + 3)
    y = np.zeros(total)
    exc = rng.uniform(-1.0, 1.0, N + 2)
    k = int(round((1.0 - bright) * N * 0.3))
    if k > 1:
        ker = np.hanning(k + 2)[1:-1]
        exc = np.convolve(exc, ker / ker.sum(), mode="same")
    exc = exc - 0.6 * np.roll(exc, max(1, int(pos * N)))  # pluck position comb
    exc -= exc.mean()
    y[:N + 2] = exc / (np.std(exc) + 1e-9)
    s = N + 2
    while s < total:
        e = min(s + N, total)
        L = e - s
        y[s:e] = g * (h0 * y[s - N:s - N + L] + h1 * y[s - N - 1:s - N - 1 + L]
                      + h2 * y[s - N - 2:s - N - 2 + L])
        s = e
    y = y[:n]
    return y * gate_env(n, dur, attack=0.0015, release=release)


def strum(bus, t, voicing, direction, vel, dur, rng, spread=0.011, t60=1.1,
          bright=0.55, pan=0.0, gain=1.0):
    """Ukulele strum over a 4-string voicing given in string order (G C E A)."""
    order = [0, 1, 2, 3] if direction == "D" else [3, 2, 1, 0]
    for j, si in enumerate(order):
        if direction == "U" and si == 0 and rng.random() < 0.5:
            continue
        tt = t + j * spread * (0.8 + 0.4 * rng.random())
        v = vel * (0.85 + 0.3 * rng.random()) * (0.75 if direction == "U" else 1.0)
        d = max(0.05, dur - j * spread)
        b = min(0.95, bright + (0.08 if direction == "U" else 0.0))
        bus.add(ks_pluck(hz(voicing[si]), d, rng, t60=t60, bright=b), tt, gain * v, pan)


def marimba(m, dur, rng, vel=1.0, hard=0.5):
    """Marimba bar: fundamental + tuned 4x/10x modes, fast upper-mode decay."""
    f0 = hz(m)
    tau = float(np.clip(0.5 * (523.25 / f0) ** 0.75, 0.15, 1.3))
    length = min(dur + 0.5, 5.0 * tau) + 0.1
    n = nsamp(length)
    t = tvec(n)
    y = np.sin(TWO_PI * f0 * t) * np.exp(-t / tau)
    for ratio, amp, tr in ((3.93, 0.30 * (0.4 + hard), 0.20), (9.24, 0.10 * hard, 0.07)):
        if f0 * ratio < 16000:
            y += amp * np.sin(TWO_PI * f0 * ratio * t + rng.uniform(0, TWO_PI)) * np.exp(-t / (tau * tr))
    k = nsamp(0.004)
    click = rng.standard_normal(k) * np.exp(-np.arange(k) / (k / 4.0))
    y[:k] += 0.06 * hard * np.convolve(click, np.ones(3) / 3.0, mode="same")
    y *= gate_env(n, length - 0.1, attack=0.0012 + 0.003 * (1.0 - hard), release=0.1)
    return vel * y


def vibes(m, dur, rng, vel=1.0, trem=4.5, depth=0.3):
    """Vibraphone: sine bar with 4x mode, motor tremolo, damper release."""
    f0 = hz(m)
    tau = float(np.clip(1.8 * (440.0 / f0) ** 0.5, 0.7, 3.0))
    n = nsamp(dur + 0.9)
    t = tvec(n)
    y = np.sin(TWO_PI * f0 * t) * np.exp(-t / tau)
    y += 0.20 * np.sin(TWO_PI * 4.0 * f0 * t + rng.uniform(0, TWO_PI)) * np.exp(-t / (0.18 * tau))
    if f0 * 9.9 < 16000:
        y += 0.04 * np.sin(TWO_PI * 9.9 * f0 * t + rng.uniform(0, TWO_PI)) * np.exp(-t / (0.05 * tau))
    y *= 1.0 - depth * 0.5 * (1.0 - np.cos(TWO_PI * trem * t + rng.uniform(0, TWO_PI)))
    y *= gate_env(n, dur + 0.3, attack=0.004, release=0.55)
    return vel * y


def steelpan(m, dur, rng, vel=1.0):
    """Steel drum: fundamental + blooming octave + twelfth, tiny pitch drop."""
    f0 = hz(m)
    tau = float(np.clip(0.8 * (440.0 / f0) ** 0.4, 0.3, 1.3))
    length = min(dur + 0.45, 4.0 * tau) + 0.08
    n = nsamp(length)
    t = tvec(n)
    tt = t + 0.01 * 0.02 * (1.0 - np.exp(-t / 0.02))     # starts 1% sharp
    y = np.sin(TWO_PI * f0 * tt) * np.exp(-t / tau)
    y += 0.10 * np.sin(TWO_PI * f0 * 1.0035 * tt) * np.exp(-t / tau)
    y += 0.55 * np.sin(TWO_PI * 2.003 * f0 * tt + 0.4) * np.exp(-t / (0.75 * tau)) * (1.0 - 0.7 * np.exp(-t / 0.025))
    y += 0.20 * np.sin(TWO_PI * 3.006 * f0 * tt + 1.1) * np.exp(-t / (0.4 * tau))
    if f0 * 4.01 < 16000:
        y += 0.08 * np.sin(TWO_PI * 4.01 * f0 * tt + 2.0) * np.exp(-t / (0.25 * tau))
    y *= gate_env(n, length - 0.08, attack=0.002, release=0.08)
    return vel * y


def glock(m, rng, vel=1.0, dur=1.2):
    """Glockenspiel / chime: free-bar partials 1, 2.76, 5.4, 8.93."""
    f0 = hz(m)
    n = nsamp(dur)
    t = tvec(n)
    tau = float(np.clip(0.9 * (1000.0 / f0) ** 0.4, 0.3, 1.5))
    y = np.sin(TWO_PI * f0 * t) * np.exp(-t / tau)
    for r, a, dcy in ((2.76, 0.28, 0.35), (5.40, 0.10, 0.15), (8.93, 0.04, 0.08)):
        if f0 * r < 17000:
            y += a * np.sin(TWO_PI * f0 * r * t + rng.uniform(0, TWO_PI)) * np.exp(-t / (tau * dcy))
    return vel * y * gate_env(n, dur - 0.05, attack=0.001, release=0.05)


def bass(m, dur, vel=1.0, bright=0.25, drive=1.3, boing=0.02, decay=1.5, rel=0.05):
    """Round bass: sine + a little 2nd/3rd harmonic, soft saturation."""
    f0 = hz(m)
    n = nsamp(dur + rel + 0.005)
    t = tvec(n)
    ph = TWO_PI * f0 * (t + boing * 0.012 * (1.0 - np.exp(-t / 0.012)))
    y = np.sin(ph) + bright * np.sin(2 * ph) + 0.4 * bright * np.sin(3 * ph) * np.exp(-t / 0.1)
    amp = (0.6 + 0.4 * np.exp(-t / 0.12)) * np.exp(-t / decay)
    y = np.tanh(drive * y * amp) / np.tanh(drive)
    return vel * y * gate_env(n, dur, attack=0.004, release=rel)


def pad_note(m, dur, rng, vel=1.0, attack=0.8, release=1.2, bright=0.4, voices=3,
             detune=8.0, nh=10, slope=1.3):
    """Soft additive pad: detuned voices, harmonics rolled off by `bright`."""
    f0 = hz(m)
    n = nsamp(dur + release + 0.01)
    t = tvec(n)
    y = np.zeros(n)
    for v in range(voices):
        cents = 0.0 if voices == 1 else (v / (voices - 1) - 0.5) * 2.0 * detune
        fv = f0 * 2.0 ** (cents / 1200.0)
        for h in range(1, nh + 1):
            a = bright ** (h - 1) / h ** slope
            if a < 0.004 or fv * h > 12000:
                break
            y += a * np.sin(TWO_PI * fv * h * t + rng.uniform(0, TWO_PI))
    return vel * y / voices * gate_env(n, dur, attack=attack, release=release)


def brass(m, dur, rng, vel=1.0, b_peak=0.82, b_sus=0.62, b_tau=0.15, attack=0.025,
          release=0.12, vib=0.005, voices=2, detune=5.0, nh=16):
    """Brass-ish additive tone whose brightness opens on the attack."""
    f0 = hz(m)
    n = nsamp(dur + release + 0.01)
    t = tvec(n)
    bright = (b_sus + (b_peak - b_sus) * np.exp(-t / b_tau)) * (0.55 + 0.45 * (1.0 - np.exp(-t / attack)))
    vibr = 1.0 + vib * np.sin(TWO_PI * 5.3 * t) * np.clip((t - 0.18) / 0.25, 0.0, 1.0)
    y = np.zeros(n)
    for v in range(voices):
        cents = 0.0 if voices == 1 else (v / (voices - 1) - 0.5) * 2.0 * detune
        fv = f0 * 2.0 ** (cents / 1200.0)
        ph = TWO_PI * np.cumsum(fv * vibr) / SR
        bp = np.ones(n)
        for h in range(1, nh + 1):
            if fv * h > 12000:
                break
            if h > 1:
                bp = bp * bright
            y += (1.0 / h) * bp * np.sin(h * ph + rng.uniform(0, TWO_PI))
    return vel * y / voices * gate_env(n, dur, attack=attack, release=release)


def kick(vel=1.0, f_hi=120.0, f_lo=50.0, decay=0.16, length=0.4):
    n = nsamp(length)
    t = tvec(n)
    ph = TWO_PI * (f_lo * t + (f_hi - f_lo) * 0.03 * (1.0 - np.exp(-t / 0.03)))
    return vel * np.sin(ph) * np.exp(-t / decay) * gate_env(n, length - 0.03, attack=0.001, release=0.03)


def tom(f0, rng, vel=1.0, decay=0.3, bend=0.5, noise=0.25, length=None):
    length = length if length is not None else decay * 5
    n = nsamp(length)
    t = tvec(n)
    ph = TWO_PI * f0 * (t + bend * 0.04 * (1.0 - np.exp(-t / 0.04)))
    y = np.sin(ph) * np.exp(-t / decay) + 0.15 * np.sin(1.59 * ph) * np.exp(-t / (decay * 0.4))
    k = nsamp(0.03)
    nb = fft_filter(rng.standard_normal(k), lp(1500, 2), loop=False, pad=0.01) * np.exp(-np.arange(k) / (k / 5.0))
    y[:k] += noise * nb / (np.max(np.abs(nb)) + 1e-9)
    return vel * y * gate_env(n, length - 0.03, attack=0.001, release=0.03)


def snare(pool, vel=1.0, decay=0.11, tone=190.0):
    n = nsamp(decay * 5)
    t = tvec(n)
    y = 0.5 * pool.take(n) * np.exp(-t / decay) + 0.6 * np.sin(TWO_PI * tone * t) * np.exp(-t / 0.05)
    return vel * y * gate_env(n, decay * 5 - 0.02, attack=0.0008, release=0.02)


def noise_hit(pool, vel=1.0, decay=0.03, attack=0.0005):
    n = nsamp(decay * 6)
    return vel * pool.take(n) * env_perc(n, attack, decay, release=0.005)


def shaker_hit(pool, vel=1.0, length=0.07, swish=0.008):
    n = nsamp(length)
    t = tvec(n)
    e = (1.0 - np.exp(-t / swish)) * np.exp(-t / (length * 0.28))
    return vel * pool.take(n) * e * gate_env(n, length - 0.006, attack=0.0005, release=0.006)


def wood(f, rng, vel=1.0, decay=0.045, click=0.3):
    """Woodblock / clave / generic small wooden or stony knock."""
    length = decay * 6 + 0.01
    n = nsamp(length)
    t = tvec(n)
    y = np.zeros(n)
    for r, a, dcy in ((1.0, 1.0, 1.0), (2.37, 0.45, 0.55), (3.97, 0.18, 0.35), (5.9, 0.07, 0.25)):
        if f * r < 16000:
            y += a * np.sin(TWO_PI * f * r * t + rng.uniform(0, TWO_PI)) * np.exp(-t / (decay * dcy))
    k = nsamp(0.002)
    y[:k] += click * rng.standard_normal(k) * np.linspace(1, 0, k)
    return vel * y * gate_env(n, length - 0.01, attack=0.0005, release=0.01)


def cricket_chirp(freq, pulses=3, rate=30.0):
    pl = 0.6 / rate
    n = nsamp(pulses / rate + 0.02)
    y = np.zeros(n)
    k = nsamp(pl)
    tt = tvec(k)
    pulse = np.sin(TWO_PI * freq * tt) * np.sin(np.pi * tt / pl) ** 2
    for p in range(pulses):
        s = nsamp(p / rate)
        y[s:s + k] += pulse * (1.0 - 0.15 * p / max(1, pulses - 1))
    return y


def slide_whistle(freq_curve, rng, breath=0.06, vib_rate=6.0, vib_depth=0.008):
    n = len(freq_curve)
    t = tvec(n)
    f = freq_curve * (1.0 + vib_depth * np.sin(TWO_PI * vib_rate * t))
    ph = TWO_PI * np.cumsum(f) / SR
    y = np.sin(ph) + 0.10 * np.sin(2 * ph) + 0.03 * np.sin(3 * ph)
    air = fft_filter(rng.standard_normal(n), chain(hp(800, 1), lp(5000, 2)), loop=False)
    return y + breath * air / (np.std(air) + 1e-9)


def blip(f0, f1, glide, decay, length=None, attack=0.0008, harm=()):
    """Sine blip gliding exponentially from f0 to f1 (bubbles, pops, thumps)."""
    length = length if length is not None else decay * 7 + attack
    n = nsamp(length)
    t = tvec(n)
    ph = TWO_PI * (f1 * t + (f0 - f1) * glide * (1.0 - np.exp(-t / glide)))
    y = np.sin(ph)
    for r, a in harm:
        y = y + a * np.sin(r * ph)
    return y * env_perc(n, attack, decay, release=min(0.01, length * 0.2))


def formant_voice(f0_curve, formants, rng, fmax=5000.0, tilt=1.0, nh_max=120):
    """Additive harmonic source shaped by (possibly moving) formant peaks.
    formants: [(centre Hz or per-sample array, bandwidth Hz, gain), ...]"""
    n = len(f0_curve)
    ph = TWO_PI * np.cumsum(f0_curve) / SR
    y = np.zeros(n)
    for h in range(1, nh_max + 1):
        fh = h * f0_curve
        if np.min(fh) > fmax:
            break
        g = 0.03
        for fc, bw, a in formants:
            g = g + a / (1.0 + ((fh - fc) / bw) ** 2)
        g = g / np.sqrt(1.0 + (fh / fmax) ** 8)
        y += g / h ** tilt * np.sin(h * ph + rng.uniform(0, TWO_PI))
    return y


def put(y, sig, t0, gain=1.0):
    """Add `sig` into mono array `y` at time t0 (clipped)."""
    i = nsamp(t0)
    j = min(len(y), i + len(sig))
    if j > i:
        y[i:j] += gain * sig[:j - i]


# =============================================================================
# Sequencing helpers
# =============================================================================
# name: (bass root MIDI, chord intervals, ukulele voicing in string order G C E A)
CH = {
    "C": (36, [0, 4, 7], ["G4", "C4", "E4", "C5"]),
    "G": (43, [0, 4, 7], ["G4", "D4", "G4", "B4"]),
    "Am": (45, [0, 3, 7], ["A4", "C4", "E4", "A4"]),
    "F": (41, [0, 4, 7], ["A4", "C4", "F4", "A4"]),
    "Em": (40, [0, 3, 7], ["G4", "E4", "G4", "B4"]),
    "Dm": (38, [0, 3, 7], ["A4", "D4", "F4", "A4"]),
    "G7": (43, [0, 4, 7, 10], ["G4", "D4", "F4", "B4"]),
    "Dm7": (38, [0, 3, 7, 10], ["A4", "D4", "F4", "C5"]),
    "Fm": (41, [0, 3, 7], ["Ab4", "C4", "F4", "Ab4"]),
    # night (D dorian)
    "Dm9": (38, [0, 3, 7, 10, 14], None),
    "G6": (43, [0, 4, 7, 9], None),
    "Fmaj7": (41, [0, 4, 7, 11], None),
    "Em7": (40, [0, 3, 7, 10], None),
    "Am7": (45, [0, 3, 7, 10], None),
    "Cmaj7": (36, [0, 4, 7, 11], None),
    "Asus4": (45, [0, 5, 7], None),
}
C_MAJOR = [0, 2, 4, 5, 7, 9, 11]


def parse_bars(bars, start_bar=0):
    """Bars of 'NOTE:len' tokens (len in 16ths, 'r' = rest) -> [(beat, beats, midi)]."""
    notes = []
    for bi, bar in enumerate(bars):
        pos = 0
        for tok in bar.split():
            name, d = tok.split(":")
            d = int(d)
            if name != "r":
                notes.append(((start_bar + bi) * 4 + pos / 4.0, d / 4.0, nm(name)))
            pos += d
        assert pos == 16, "bar %d has %d sixteenths: %s" % (start_bar + bi, pos, bar)
    return notes


def chord_timeline(bars):
    """['C', [('F', 0), ('G', 2)], ...] -> [(start_beat, beats, name)]."""
    segs = []
    for i, c in enumerate(bars):
        if isinstance(c, str):
            c = [(c, 0)]
        for j, (name, off) in enumerate(c):
            end = c[j + 1][1] if j + 1 < len(c) else 4
            segs.append((i * 4 + off, end - off, name))
    return segs


def chord_at(segs, beat, total=None):
    if total:
        beat = beat % total
    for s, length, name in segs:
        if s - 1e-9 <= beat < s + length - 1e-9:
            return name
    return segs[-1][2]


def close_voicing(name, lo):
    root, ivs, _ = CH[name]
    return sorted({lo + (root + iv - lo) % 12 for iv in ivs})


def dia(m, steps, scale=C_MAJOR):
    """Move a diatonic note by scale steps (e.g. -2 = a third below)."""
    idx = scale.index(m % 12) + steps
    return (m // 12 + idx // 7) * 12 + scale[idx % 7]


def approach(next_root, scale=C_MAJOR):
    for k in (1, 2):
        if (next_root - k) % 12 in scale:
            return next_root - k
    return next_root - 1


def bass_notes(segs, pattern_for):
    """pattern_for(seg_index, beats) -> [(pos16, len16, semitones | 'A')]."""
    out = []
    for i, (start, length, name) in enumerate(segs):
        root = CH[name][0]
        nroot = CH[segs[(i + 1) % len(segs)][2]][0]
        for pos, d, what in pattern_for(i, length):
            m = approach(nroot) if what == "A" else root + what
            out.append((start + pos / 4.0, d / 4.0, m))
    return out


def make_clock(bpm, swing=0.0):
    """beat -> seconds; odd 16ths are delayed by `swing` (fraction of a 16th)."""
    spb = 60.0 / bpm

    def T(beat):
        s16 = beat * 4.0
        r = round(s16)
        if abs(s16 - r) < 1e-6 and r % 2 == 1:
            s16 += swing
        return s16 / 4.0 * spb
    return T, spb


def tempo_map(bpm_fn, max_beat, res=64):
    beats = np.arange(0, max_beat * res + 1) / res
    spb = 60.0 / bpm_fn(beats)
    times = np.concatenate([[0.0], np.cumsum((spb[:-1] + spb[1:]) / 2.0 / res)])
    return lambda b: float(np.interp(b, beats, times))


def play_strums(bus, events, T, segs, total_beats, loop, rng, gain, pan=0.0, end_beat=None, **kw):
    """events: sorted [(beat, 'D'|'U', vel, mute_seconds|None)]; each strum rings
    until the next one (the last one until `end_beat` when not looping)."""
    for i, (b, d, v, mute) in enumerate(events):
        if i + 1 < len(events):
            nb = events[i + 1][0]
        elif loop:
            nb = events[0][0] + total_beats
        else:
            nb = end_beat if end_beat is not None else b + 4
        dur = T(nb) - T(b) + 0.03
        if mute:
            dur = min(dur, mute)
        voicing = [nm(x) for x in CH[chord_at(segs, b, total_beats)][2]]
        strum(bus, T(b) - 0.006, voicing, d, v, dur, rng, pan=pan, gain=gain, **kw)


ISLAND_STRUM = [(0, "D", 1.0), (1, "D", 0.72), (1.5, "U", 0.55), (2.5, "U", 0.6), (3, "D", 0.8), (3.5, "U", 0.5)]


# =============================================================================
# MUSIC: day  (C major, 105 BPM, 28 bars = 64.0 s)
# =============================================================================
DAY_A = [
    "G5:2 G5:2 A5:2 G5:2 E5:4 C5:4",       # C
    "D5:2 D5:2 E5:2 D5:2 B4:4 G4:4",       # G
    "C5:2 E5:2 A5:4 G5:2 A5:2 C6:4",       # Am
    "C6:3 A5:1 F5:4 r:2 F5:2 G5:2 A5:2",   # F
    "G5:2 G5:2 A5:2 G5:2 E5:4 C6:4",       # C
    "D6:2 C6:2 B5:2 A5:2 G5:4 D5:4",       # G
    "A5:2 C6:2 A5:2 F5:2 G5:2 B5:2 D6:4",  # F | G
    "C6:4 G5:2 E5:2 C5:4 r:4",             # C
]
DAY_B = [
    "A5:4 G5:2 F5:2 A5:4 C6:4",            # F
    "G5:6 E5:2 C5:8",                      # C
    "A5:4 G5:2 F5:2 A5:4 C6:4",            # F
    "D6:6 B5:2 G5:4 r:2 G5:1 A5:1",        # G
    "C6:4 B5:2 A5:2 E5:4 A5:4",            # Am
    "G5:4 E5:2 B4:2 E5:4 G5:4",            # Em
    "A5:2 G5:2 F5:2 A5:2 C6:4 A5:4",       # F
    "B5:4 D6:2 B5:2 G5:2 F5:2 D5:2 F5:2",  # G7
]
DAY_A2 = DAY_A[:7] + ["C6:4 E6:2 D6:2 C6:4 r:4"]
DAY_TAG = [
    "r:4 E5:1 r:1 A5:1 r:1 C6:2 r:2 A5:2 r:2",   # Am
    "r:4 F5:1 r:1 A5:1 r:1 C6:2 r:2 A5:2 r:2",   # F
    "r:4 D5:1 r:1 F5:1 r:1 A5:2 r:2 D6:2 r:2",   # Dm
    "B5:2 A5:2 G5:2 F5:2 E5:2 D5:2 B4:2 G4:2",   # G7
]
_A_CH = ["C", "G", "Am", "F", "C", "G", [("F", 0), ("G", 2)], "C"]
DAY_CHORDS = _A_CH + ["F", "C", "F", "G", "Am", "Em", "F", "G7"] + _A_CH + ["Am", "F", "Dm", "G7"]


def render_day():
    bpm, bars = 105.0, 28
    total = bars * 4
    T, spb = make_clock(bpm, swing=0.18)
    n = nsamp(total * spb)
    rng = np.random.default_rng(1001)
    song = Song(n, stereo=False, loop=True)
    segs = chord_timeline(DAY_CHORDS)

    mar = song.bus("marimba", 0.55, chain(hp(150, 1), lp(9000, 1)), 0.30)
    stl = song.bus("steel", 0.42, chain(hp(180, 1), lp(8000, 1)), 0.30)
    uke = song.bus("uke", 0.26, chain(hp(140, 2), bump(300, 2.0, 1.5), lp(5500, 2)), 0.22)
    bas = song.bus("bass", 0.40, chain(hp(35, 2), lp(1500, 2)), 0.03)
    shk = song.bus("shaker", 0.45, lp(12000, 1), 0.12)
    kik = song.bus("kick", 0.36, lp(2000, 2), 0.0)
    wdb = song.bus("wood", 0.22, None, 0.30)
    whs = song.bus("whistle", 0.20, lp(6000, 2), 0.35)

    def hv(b):  # humanised velocity with downbeat accent
        return (0.82 + 0.12 * rng.random()) + (0.08 if abs(b - round(b)) < 1e-6 else 0.0)

    # melody: A marimba, B steel lead, A' marimba + steel a third below, tag marimba
    for b, d, m in parse_bars(DAY_A, 0) + parse_bars(DAY_TAG, 24):
        mar.add(marimba(m, d * spb, rng, vel=hv(b), hard=0.55), T(b))
    for b, d, m in parse_bars(DAY_B, 8):
        stl.add(steelpan(m, d * spb, rng, vel=hv(b)), T(b))
    for b, d, m in parse_bars(DAY_A2, 16):
        mar.add(marimba(m, d * spb, rng, vel=hv(b), hard=0.55), T(b))
        stl.add(steelpan(dia(m, -2), d * spb, rng, vel=0.55 * hv(b)), T(b))

    # ukulele
    ev = []
    for bar in range(bars):
        if bar in (24, 25, 26):
            pat = [(0, "D", 0.85, 0.2), (1.5, "U", 0.5, 0.15), (3, "D", 0.6, 0.2)]
        elif bar == 27:
            pat = [(0, "D", 0.9, None), (2, "D", 0.7, None)]
        else:
            pat = [(o, d, v, None) for o, d, v in ISLAND_STRUM]
        ev += [(bar * 4 + o, d, v, mu) for o, d, v, mu in pat]
    play_strums(uke, ev, T, segs, total, True, rng, gain=1.0)

    # bass
    p4 = [(0, 5, 0), (6, 2, 7), (8, 4, 12), (12, 2, 7), (14, 2, "A")]
    p2 = [(0, 3, 0), (4, 2, 7), (6, 2, "A")]
    ptag = [(0, 3, 0), (4, 3, 7), (8, 3, 12), (12, 3, "A")]

    def pat_for(i, length):
        if segs[i][0] >= 96:
            return ptag
        return p4 if length == 4 else p2
    for b, d, m in bass_notes(segs, pat_for):
        bas.add(bass(m, d * spb * 0.85, vel=0.9 + 0.1 * rng.random(), bright=0.25, boing=0.02), T(b))

    # percussion
    shaker = NoisePool(rng, chain(hp(4500, 2), lp(11000, 2)))
    for s in range(total * 4):
        b = s / 4.0
        tag = b >= 96
        if tag and s % 2:
            continue
        acc = [0.9, 0.3, 0.55, 0.35][s % 4] * (0.8 if tag else 1.0)
        jit = rng.uniform(-0.002, 0.002)
        shk.add(shaker_hit(shaker, acc, 0.09 if s % 4 == 0 else 0.06), T(b) + jit)
    for bar in range(bars):
        for beat in ((0,) if bar >= 24 else (0, 2)):
            kik.add(kick(0.9 if beat == 0 else 0.7), T(bar * 4 + beat))
    for bar in range(8, 24, 2):   # son clave (3-2) in B and A'
        for off in (0, 1.5, 3, 5, 6):
            wdb.add(wood(2300, rng, 0.8, decay=0.05, click=0.2), T(bar * 4 + off) + rng.uniform(-0.002, 0.002))
    for bar in (24, 25, 26):      # tick-tock in the tag
        wdb.add(wood(1250, rng, 1.2, decay=0.04), T(bar * 4))
        wdb.add(wood(900, rng, 1.2, decay=0.04), T(bar * 4 + 0.5))

    # goofy slide whistle rising into the B section
    k = nsamp(spb * 1.1)
    fc = smooth_curve([(0, 700), (spb * 0.15, 760), (spb * 0.85, 1560), (spb * 1.1, 1600)], k, 20)
    w = slide_whistle(fc, rng) * gate_env(k, spb * 0.95, attack=0.03, release=spb * 0.15)
    whs.add(w, T(7 * 4 + 3))

    return song.mixdown(t60=1.4, damp=0.45, master_eq=lp(11000, 1), drive=1.4, seed=11)


# =============================================================================
# MUSIC: title  (C major, 90 BPM, 12 bars = 32.0 s) - slow, warm day-theme variation
# =============================================================================
TITLE_MELODY = DAY_A[:7] + [
    "C6:4 G5:2 E5:2 C5:8",                 # C
    "A5:6 G5:2 F5:4 A5:4",                 # F
    "G5:6 E5:2 C5:8",                      # C
    "F5:4 E5:2 D5:2 F5:4 A5:4",            # Dm7
    "G5:8 r:4 D5:2 F5:2",                  # G7
]
TITLE_CHORDS = _A_CH + ["F", "C", "Dm7", "G7"]


def render_title():
    bpm, bars = 90.0, 12
    total = bars * 4
    T, spb = make_clock(bpm, swing=0.12)
    n = nsamp(total * spb)
    rng = np.random.default_rng(1002)
    song = Song(n, stereo=True, loop=True)
    segs = chord_timeline(TITLE_CHORDS)

    vib = song.bus("vibes", 0.42, chain(hp(150, 1), lp(8000, 1)), 0.35)
    uke = song.bus("uke", 0.42, chain(hp(130, 2), bump(320, 1.5, 1.5), lp(5000, 2)), 0.30)
    bas = song.bus("bass", 0.42, chain(hp(35, 2), lp(1000, 2)), 0.04)
    pad = song.bus("pad", 0.17, chain(hp(120, 1), lp(3500, 2)), 0.45)

    for b, d, m in parse_bars(TITLE_MELODY):
        v = 0.8 + 0.12 * rng.random() + (0.08 if abs(b - round(b)) < 1e-6 else 0.0)
        vib.add(vibes(m, d * spb, rng, vel=v, trem=4.2, depth=0.28), T(b), pan=0.18)

    pick = [(0, 0, 0.9), (0.5, 1, 0.55), (1, 2, 0.65), (1.5, 3, 0.6),
            (2, 1, 0.7), (2.5, 2, 0.5), (3, 3, 0.6), (3.5, 2, 0.5)]
    for bar in range(bars):
        for off, idx, v in pick:
            b = bar * 4 + off
            voic = sorted(nm(x) for x in CH[chord_at(segs, b)][2])
            p = ks_pluck(hz(voic[idx]), 1.3, rng, t60=1.5, bright=0.45)
            uke.add(p, T(b), v * (0.9 + 0.2 * rng.random()), pan=-0.3)

    pats = {4: [(0, 7, 0), (8, 7, 7)], 2: [(0, 7, 0)]}
    for b, d, m in bass_notes(segs, lambda i, length: pats[length]):
        bas.add(bass(m, d * spb * 0.95, vel=0.85, bright=0.15, drive=1.1, boing=0.01), T(b))

    for start, length, name in segs:
        for m in close_voicing(name, 55):
            for side in (-0.6, 0.6):
                x = pad_note(m, length * spb, rng, vel=0.5, attack=0.6, release=0.9,
                             bright=0.35, voices=2, detune=6.0)
                pad.add(x, T(start), pan=side)

    return song.mixdown(t60=1.8, damp=0.45, master_eq=lp(10000, 1), drive=1.3, seed=21)


# =============================================================================
# MUSIC: night  (D dorian, 64 BPM, 16 bars = 60.0 s)
# =============================================================================
NIGHT_CHORDS = ["Dm9", "G6", "Dm9", "G6", "Fmaj7", "Em7", "Am7", "Am7",
                "Dm9", "G6", "Fmaj7", "Cmaj7", "Em7", "Fmaj7", "G6", "Asus4"]
NIGHT_VOICING = {
    "Dm9": ["D3", "F3", "C4", "E4", "A4"],
    "G6": ["D3", "G3", "B3", "E4", "G4"],
    "Fmaj7": ["F3", "A3", "C4", "E4", "G4"],
    "Em7": ["E3", "G3", "B3", "D4", "G4"],
    "Am7": ["E3", "A3", "C4", "E4", "G4"],
    "Cmaj7": ["C3", "G3", "B3", "E4", "G4"],
    "Asus4": ["D3", "A3", "D4", "E4", "A4"],
}
NIGHT_MELODY = [
    "r:4 A4:2 D5:2 E5:4 F5:4",             # Dm9      (marimba)
    "E5:4 D5:2 B4:2 D5:8",                 # G6
    "r:4 A4:2 D5:2 E5:4 A5:4",             # Dm9
    "G5:4 E5:2 D5:2 E5:8",                 # G6
    "r:4 C5:2 F5:2 A5:4 C6:4",             # Fmaj7
    "B5:6 G5:2 E5:8",                      # Em7
    "r:4 E5:2 A5:2 C6:4 B5:2 A5:2",        # Am7
    "G5:8 E5:8",                           # Am7
    "r:4 A5:2 D6:2 E6:4 F6:4",             # Dm9      (vibes)
    "E6:4 D6:2 B5:2 D6:8",                 # G6
    "C6:4 A5:2 F5:2 A5:4 C6:4",            # Fmaj7
    "B5:6 G5:2 E5:8",                      # Cmaj7
    "r:4 G5:2 B5:2 D6:4 B5:4",             # Em7
    "C6:4 A5:2 F5:2 E5:8",                 # Fmaj7
    "D5:4 E5:2 G5:2 B5:4 A5:4",            # G6
    "A5:16",                               # Asus4
]
NIGHT_ARP = [(0, 0, 0.9), (0.5, 2, 0.55), (1, 3, 0.6), (1.5, 4, 0.5),
             (2.5, 3, 0.45), (3, 1, 0.5), (3.5, 2, 0.4)]


def render_night():
    bpm, bars = 64.0, 16
    total = bars * 4
    T, spb = make_clock(bpm)
    n = nsamp(total * spb)
    L = n / SR
    rng = np.random.default_rng(1003)
    song = Song(n, stereo=False, loop=True)
    segs = chord_timeline(NIGHT_CHORDS)

    mar = song.bus("marimba", 0.50, chain(hp(120, 1), lp(6000, 1)), 0.45)
    vib = song.bus("vibes", 0.42, chain(hp(150, 1), lp(6500, 1)), 0.50)
    gtr = song.bus("guitar", 0.24, chain(hp(90, 2), lp(3500, 2)), 0.35)
    pad = song.bus("pad", 0.18, chain(hp(100, 1), lp(2500, 2)), 0.45)
    bas = song.bus("bass", 0.34, chain(hp(35, 2), lp(700, 2)), 0.05)
    drm = song.bus("drum", 0.30, lp(1500, 2), 0.20)
    crk = song.bus("crickets", 0.20, chain(hp(3000, 2), lp(7000, 2)), 0.30)

    for b, d, m in parse_bars(NIGHT_MELODY):
        v = 0.75 + 0.15 * rng.random()
        if b < 32:
            mar.add(marimba(m, d * spb, rng, vel=v, hard=0.25), T(b))
        else:
            vib.add(vibes(m, d * spb, rng, vel=v, trem=3.8, depth=0.25), T(b))

    for bar, name in enumerate(NIGHT_CHORDS):
        voic = [nm(x) for x in NIGHT_VOICING[name]]
        for m in voic:
            pad.add(pad_note(m, 4 * spb, rng, vel=0.5, attack=1.2, release=1.4,
                             bright=0.35, voices=3, detune=7.0), T(bar * 4))
        for off, idx, v in NIGHT_ARP:
            p = ks_pluck(hz(voic[idx]), 2.2, rng, t60=2.4, bright=0.3)
            gtr.add(p, T(bar * 4 + off), v * (0.85 + 0.2 * rng.random()))

    for b, d, m in bass_notes(segs, lambda i, length: [(0, 10, 0), (10, 6, 7)]):
        bas.add(bass(m, d * spb * 0.9, vel=0.8, bright=0.12, drive=1.0, boing=0.0, decay=2.5), T(b))

    for bar in range(bars):   # soft frame-drum heartbeat
        drm.add(tom(82, rng, vel=0.8, decay=0.35, bend=0.15, noise=0.1), T(bar * 4))
        if bar % 2:
            drm.add(tom(82, rng, vel=0.45, decay=0.3, bend=0.15, noise=0.1), T(bar * 4 + 2.5))

    swell = periodic_lfo(rng, L, kmax=4)
    for fq, period, pulses, rate, amp, jit in ((4700, 1.12, 3, 30.0, 1.0, 0.04),
                                               (4150, 1.63, 4, 24.0, 0.7, 0.06)):
        tt = rng.uniform(0, period)
        while tt < L:
            if rng.random() > 0.15:
                a = amp * (0.7 + 0.3 * rng.random()) * (0.6 + 0.4 * swell(tt))
                crk.add(cricket_chirp(fq * (1 + rng.uniform(-0.005, 0.005)), pulses, rate), tt, a)
            tt += period * (1 + rng.uniform(-jit, jit))

    return song.mixdown(t60=2.6, damp=0.4, master_eq=lp(9000, 1), drive=1.3, seed=31)


# =============================================================================
# MUSIC: danger  (E phrygian/chromatic, 150 BPM, 10 bars = 16.0 s)
# =============================================================================
def render_danger():
    bpm, bars = 150.0, 10
    T, spb = make_clock(bpm)
    n = nsamp(bars * 4 * spb)
    rng = np.random.default_rng(1004)
    song = Song(n, stereo=True, loop=True)

    bas = song.bus("bass", 0.50, chain(hp(35, 2), lp(1800, 2)), 0.03)
    sub = song.bus("sub", 0.30, lp(200, 2), 0.0)
    stb = song.bus("stab", 0.30, chain(hp(150, 1), lp(6000, 2)), 0.25)
    drm = song.bus("drums", 0.50, lp(12000, 1), 0.12)
    hat = song.bus("hats", 0.22, None, 0.10)
    stg = song.bus("strings", 0.22, chain(hp(300, 1), lp(7000, 2)), 0.35)
    xyl = song.bus("xylo", 0.14, lp(9000, 1), 0.25)

    pat_e = [40, 40, 40, 41, 40, 40, 46, 41]           # E E E F E E Bb F
    pat_g = [m + 3 for m in pat_e]
    plan = [pat_e] * 4 + [pat_g] * 2 + [pat_e] * 2 + [
        [40, 41, 40, 41, 42, 43, 42, 43], [44, 45, 44, 45, 46, 47, 46, 47]]

    # pulsing bass ostinato + sub on the downbeat
    for bar, pat in enumerate(plan):
        for i, m in enumerate(pat):
            acc = 1.0 if i in (0, 4) else 0.72
            bas.add(bass(m, 0.16, vel=acc, bright=0.45, drive=2.0, boing=0.0, decay=0.4), T(bar * 4 + i * 0.5))
        sub.add(bass(pat[0] - 12, spb * 1.8, vel=0.9, bright=0.0, drive=1.0, boing=0.0), T(bar * 4))

    # dissonant brass stabs (E3 E4 F4 Bb4 over the bass root)
    hits = []
    for bar in range(8):
        if bar < 4 and bar % 2 == 0:
            continue
        hits += [(bar * 4 + p, plan[bar][0]) for p in (0, 1.5, 3.0)]
    for bar in (8, 9):
        hits += [(bar * 4 + q, plan[bar][q * 2]) for q in range(4)]
    for k, (b, r) in enumerate(hits):
        for m in (r + 12, r + 24, r + 25, r + 30):
            x = brass(m, 0.13, rng, vel=0.9, b_peak=0.9, b_sus=0.4, b_tau=0.06, attack=0.006,
                      release=0.08, vib=0.0, voices=2, detune=9.0)
            stb.add(x, T(b), pan=-0.35 if k % 2 == 0 else 0.35)

    # drums
    sn_pool = NoisePool(rng, chain(hp(900, 2), lp(7000, 2)))
    hat_pool = NoisePool(rng, chain(hp(7000, 2), lp(14000, 1)))
    for bar in range(8):
        for beat in range(4):
            b = bar * 4 + beat
            if beat in (0, 2):
                drm.add(tom(68, rng, vel=1.0 if beat == 0 else 0.8, decay=0.28, bend=0.6), T(b))
            else:
                drm.add(snare(sn_pool, vel=0.55), T(b), pan=0.1)
    for bar in (0, 4):
        drm.add(tom(50, rng, vel=1.2, decay=0.8, bend=0.4, noise=0.4), T(bar * 4))
    for i in range(16):   # rising tom fill over the build
        f = 70.0 * 2.0 ** (i / 16.0)
        drm.add(tom(f, rng, vel=0.6 + 0.4 * i / 15, decay=0.2, bend=0.5), T(32 + i * 0.5), pan=0.4 * np.sin(i))
    for s in range(bars * 16):
        v = 0.6 if s % 2 == 0 else 0.35
        hat.add(noise_hit(hat_pool, v, decay=0.025), T(s / 4.0) + rng.uniform(-0.002, 0.002), pan=0.35)

    # tremolo string cluster (minor 2nd), crescendo, then climbing in the build
    trem_hz = bpm / 60.0 * 4.0
    for bar in range(4, 10):
        r = plan[bar][0]
        dur = 4 * spb
        k = nsamp(dur + 0.31)
        trem = 0.55 + 0.45 * np.cos(TWO_PI * trem_hz * tvec(k))
        vel = 0.4 + 0.2 * (bar - 4) if bar < 8 else 1.0
        for j, m in enumerate((r + 43, r + 44)):
            x = pad_note(m, dur, rng, vel=vel, attack=0.3, release=0.3, bright=0.55, voices=3,
                         detune=10.0, nh=10, slope=1.0)
            stg.add(x * trem[:len(x)], T(bar * 4), pan=-0.3 + 0.2 * j)

    # goofy crab-scuttle xylophone run leading back to the top
    for i in range(16):
        xyl.add(marimba(76 + i, 0.1, rng, vel=0.5 + 0.5 * i / 15, hard=0.9), T(36 + i * 0.25), pan=0.2)

    return song.mixdown(t60=1.1, damp=0.45, master_eq=lp(11000, 1), drive=1.6, seed=41)


# =============================================================================
# MUSIC: ending  (C major, 96 BPM with ritardando, ~21 s, not looping)
# =============================================================================
ENDING_MELODY = DAY_A[:3] + [
    "C6:4 A5:4 F5:4 G5:2 A5:2",            # F
    "A5:4 C6:4 B5:4 D6:4",                 # Dm7 | G7
    "A5:4 C6:4 Ab5:4 C6:4",                # F | Fm
    "C6:16",                               # C (fermata)
]
ENDING_CHORDS = ["C", "G", "Am", "F", [("Dm7", 0), ("G7", 2)], [("F", 0), ("Fm", 2)], "C"]


def render_ending():
    rng = np.random.default_rng(1005)

    def bpm_fn(b):
        return np.where(b < 16, 96.0, np.where(b < 24, 96.0 - 26.0 * (b - 16) / 8.0, 70.0))
    T = tempo_map(bpm_fn, 40)
    t_fin = T(24)
    n = nsamp(t_fin + 5.2)
    song = Song(n, stereo=True, loop=False)
    segs = chord_timeline(ENDING_CHORDS)

    stl = song.bus("steel", 0.48, chain(hp(180, 1), lp(8000, 1)), 0.35)
    mar = song.bus("marimba", 0.36, chain(hp(150, 1), lp(9000, 1)), 0.35)
    uke = song.bus("uke", 0.30, chain(hp(140, 2), bump(300, 2.0, 1.5), lp(5500, 2)), 0.25)
    bas = song.bus("bass", 0.40, chain(hp(35, 2), lp(1500, 2)), 0.04)
    brs = song.bus("brass", 0.16, chain(hp(150, 1), lp(4500, 2)), 0.35)
    prc = song.bus("perc", 0.40, lp(12000, 1), 0.15)
    glk = song.bus("glock", 0.16, lp(12000, 1), 0.40)

    def dur_s(b, d):
        return T(b + d) - T(b)

    # melody (steel) + harmony (marimba, a third below; explicit over F | Fm)
    mel = parse_bars(ENDING_MELODY)
    for b, d, m in mel:
        if b >= 24:
            stl.add(steelpan(m, 3.5, rng, vel=1.0), T(b))
            continue
        stl.add(steelpan(m, dur_s(b, d), rng, vel=0.85 + 0.1 * rng.random()), T(b))
        if b < 20:
            mar.add(marimba(dia(m, -2), dur_s(b, d), rng, vel=0.7, hard=0.5), T(b), pan=-0.2)
    for b, d, m in parse_bars(["F5:4 A5:4 F5:4 Ab5:4"], 5):
        mar.add(marimba(m, dur_s(b, d), rng, vel=0.75, hard=0.5), T(b), pan=-0.2)
    for i in range(24):   # final marimba roll on E5 + G5
        t = t_fin + i * 0.075
        a = np.sin(np.pi * (i + 1) / 25) * 0.6
        mar.add(marimba(nm("E5") if i % 2 else nm("G5"), 0.3, rng, vel=a, hard=0.35), t, pan=-0.2)

    # ukulele
    ev = []
    for bar in range(4):
        ev += [(bar * 4 + o, d, v, None) for o, d, v in ISLAND_STRUM]
    for bar in (4, 5):
        ev += [(bar * 4 + q, "D", 0.85 if q % 2 == 0 else 0.6, None) for q in range(4)]
    play_strums(uke, ev, T, segs, 28, False, rng, gain=1.0, end_beat=24)
    c_voic = [nm(x) for x in CH["C"][2]]
    strum(uke, t_fin - 0.006, c_voic, "D", 1.0, 4.5, rng, t60=2.2)
    strum(uke, T(25), c_voic, "D", 0.6, 3.5, rng, spread=0.07, t60=2.2)

    # bass
    for b, d, m in bass_notes(segs[:4], lambda i, length: [(0, 5, 0), (6, 2, 7), (8, 4, 12), (12, 2, 7), (14, 2, "A")]):
        bas.add(bass(m, dur_s(b, d) * 0.85, vel=0.9), T(b))
    for s, length, name in segs[4:8]:
        bas.add(bass(CH[name][0], dur_s(s, length) * 0.9, vel=0.9, bright=0.2), T(s))
    bas.add(bass(36, 4.2, vel=1.0, bright=0.2, decay=3.0, rel=0.8), t_fin)
    bas.add(bass(24, 4.0, vel=0.7, bright=0.0, decay=3.0, rel=0.8), t_fin)

    # brass pad swelling into the final chord
    for s, length, name in segs[4:]:
        long_ = s >= 24
        d = 4.5 if long_ else dur_s(s, length)
        for m in close_voicing(name, 55) + ([nm("C5")] if long_ else []):
            x = brass(m, d, rng, vel=0.8 if long_ else 0.6, b_peak=0.7, b_sus=0.55, b_tau=0.3,
                      attack=0.12, release=0.9 if long_ else 0.25, vib=0.004, voices=2, detune=6.0)
            brs.add(x, T(s))

    # percussion: shaker + kick in the groove, timpani roll into the last chord, soft crash
    shaker = NoisePool(rng, chain(hp(4500, 2), lp(11000, 2)))
    crash = NoisePool(rng, chain(hp(3000, 2), lp(12000, 1)), seconds=10.0)
    for s in range(16 * 4 + 8 * 2):
        b = s / 4.0 if s < 64 else 16 + (s - 64) / 2.0
        acc = [0.9, 0.3, 0.55, 0.35][s % 4] if s < 64 else 0.5
        prc.add(shaker_hit(shaker, acc * 0.2, 0.07), T(b), pan=0.3)
    for bar in range(4):
        prc.add(kick(0.8), T(bar * 4))
        prc.add(kick(0.6), T(bar * 4 + 2))
    t0, t1 = T(22), t_fin
    k = int((t1 - t0) / 0.065)
    for i in range(k):
        prc.add(tom(98, rng, vel=0.15 + 0.5 * i / k, decay=0.25, bend=0.05, noise=0.1), t0 + i * 0.065, pan=-0.3)
    prc.add(tom(65.4, rng, vel=1.0, decay=1.0, bend=0.05, noise=0.2), t_fin, pan=-0.2)
    prc.add(noise_hit(crash, 0.25, decay=1.3, attack=0.002), t_fin, pan=0.3)

    # glockenspiel sparkle on the final chord
    for i, m in enumerate(("C6", "E6", "G6", "C7", "E7", "G7")):
        glk.add(glock(nm(m), rng, vel=0.9 - 0.08 * i, dur=2.0), t_fin + 0.15 + 0.07 * i, pan=0.5 - 0.2 * i)

    return song.mixdown(t60=2.2, damp=0.45, master_eq=lp(11000, 1), drive=1.3, seed=51, fade_out=2.2)


# =============================================================================
# AMBIENCE (stereo, seamless loops)
# =============================================================================
def _circ(t, c, period):
    """Signed circular time difference t - c, wrapped into [-period/2, period/2)."""
    return (t - c + period / 2.0) % period - period / 2.0


def render_ocean():
    L = 30.0
    n = nsamp(L)
    rng = np.random.default_rng(2001)
    crashes = [3.0, 8.6, 15.0, 20.9, 27.2]         # 5.6/6.4/5.9/6.3/5.8 s apart
    strength = [1.0, 0.72, 0.9, 0.62, 0.84]
    pans = [-0.35, 0.3, -0.1, 0.4, -0.25]
    base_lfo = periodic_lfo(rng, L, kmax=3)

    def wash_env(t):
        tot = 0.0
        for c, s in zip(crashes, strength):
            d = _circ(t, c, L)
            dd = np.maximum(d, 0.0)
            tot = tot + s * np.where(d >= 0, (1 - np.exp(-dd / 0.3)) * np.exp(-dd / 2.3), 0.0)
        return tot

    out = np.zeros((2, n))
    for ch in range(2):
        side = -1.0 if ch == 0 else 1.0

        def mag(t, f):
            P = (0.22 * (1 + 0.2 * base_lfo(t)) * pink(f) * lp(420, 2)(f) * hp(35, 2)(f)) ** 2
            for c, s, p in zip(crashes, strength, pans):
                g = s * (1.0 + 0.35 * side * p)
                d = _circ(t, c, L)
                x = np.clip((d + 3.0) / 3.0, 0.0, 1.0)
                dd = np.maximum(d, 0.0)
                swell = np.where(d < 0, x * x * (3 - 2 * x), np.exp(-dd / 1.3))
                fc = 220.0 + 1100.0 * np.where(d < 0, x ** 2, np.exp(-dd / 0.8))
                P = P + (g * 0.7 * swell * pink(f) * lp(fc, 2)(f) * hp(40, 2)(f)) ** 2
                crash = np.clip((d + 0.06) / 0.12, 0.0, 1.0) * np.exp(-dd / 0.5)
                P = P + (g * 0.9 * crash * pink(f) * lp(6500, 1)(f) * hp(200, 1)(f)) ** 2
                wash = np.where(d >= 0, (1 - np.exp(-dd / 0.3)) * np.exp(-dd / 2.3), 0.0)
                fcw = 2500.0 + 6000.0 * np.exp(-dd / 1.6)
                P = P + (g * 0.35 * wash * hp(900, 2)(f) * lp(fcw, 2)(f)) ** 2
            return np.sqrt(P)
        out[ch] = spectral_noise(n, mag, rng, loop=True)

        # foam fizz: sparse bubble pops whose density follows the wash
        cand = rng.uniform(0, L, int(3000 * L))
        keep = rng.random(len(cand)) < np.clip(wash_env(cand) / 1.2, 0, 1)
        amps = np.minimum(rng.lognormal(0, 0.5, keep.sum()), 3.0) * rng.choice([-1, 1], keep.sum())
        imp = np.zeros(n)
        np.add.at(imp, (cand[keep] * SR).astype(int) % n, amps)
        fizz = fft_filter(imp, chain(hp(2500, 2), lp(9000, 2)), loop=True)
        out[ch] += 0.3 * fizz * np.std(out[ch]) / (np.std(fizz) + 1e-9)
    return master(out, drive=1.2, loop=True)


def render_rain():
    L = 20.0
    n = nsamp(L)
    rng = np.random.default_rng(3001)
    t = tvec(n)
    lfo = 1.0 + 0.12 * np.sin(TWO_PI * t / L + 0.5) + 0.06 * np.sin(TWO_PI * 3 * t / L + 1.7)
    out = np.zeros((2, n))
    for ch in range(2):
        k = rng.poisson(4000 * L)
        imp = np.zeros(n)
        np.add.at(imp, rng.integers(0, n, k), np.minimum(rng.lognormal(0, 0.5, k), 3.5) * rng.choice([-1, 1], k))
        crackle = fft_filter(imp, chain(hp(1200, 2), lp(9000, 1), bump(4000, 3.0, 1.5)), loop=True)
        bed = fft_filter(rng.standard_normal(n), chain(hp(350, 2), lp(5500, 1)), loop=True)
        low = fft_filter(rng.standard_normal(n), chain(hp(120, 2), lp(700, 2)), loop=True)
        mix = (crackle / np.std(crackle) + 0.35 * bed / np.std(bed) + 0.25 * low / np.std(low))
        out[ch] = mix * lfo
    level = np.std(out)
    drops = Bus(n, 2, loop=True)
    for _ in range(rng.poisson(5.5 * L)):          # little plinks
        f0 = rng.uniform(1300, 3800)
        d = rng.uniform(0.008, 0.02)
        drops.add(blip(f0, f0 * 1.5, 0.012, d), rng.uniform(0, L), rng.lognormal(0, 0.5) * 0.5, rng.uniform(-0.8, 0.8))
    for _ in range(rng.poisson(0.9 * L)):          # fat drips from leaves
        f0 = rng.uniform(600, 1400)
        drops.add(blip(f0, f0 * 1.7, 0.015, 0.04), rng.uniform(0, L), rng.uniform(0.8, 1.4), rng.uniform(-0.6, 0.6))
    out += drops.x * level * 0.9
    return master(out, drive=1.2, loop=True)


def render_wind():
    L = 20.0
    n = nsamp(L)
    rng = np.random.default_rng(4001)
    m_fc = periodic_lfo(rng, L, kmax=6)
    m_amp = periodic_lfo(rng, L, kmax=5, slope=0.8)
    out = np.zeros((2, n))
    for ch in range(2):
        shift = 0.0 if ch == 0 else 0.9

        def mag(t, f):
            tt = t + shift
            gust = np.clip(0.55 + 0.55 * m_amp(tt), 0.12, 1.2)
            fc = 480.0 * 2.0 ** (0.9 * m_fc(tt))
            lf = np.log2(np.maximum(f, 20.0) / fc)
            band = np.exp(-0.5 * (lf / 0.55) ** 2) * pink(f)
            whistle = 0.25 * gust ** 3 * np.exp(-0.5 * (np.log2(np.maximum(f, 20.0) / (2.4 * fc)) / 0.06) ** 2)
            air = 0.12 * hp(1500, 1)(f) * lp(6000, 2)(f)
            rumble = 0.35 * lp(180, 2)(f) * hp(25, 2)(f) * (0.6 + 0.4 * gust)
            return gust * (band + air) + rumble + whistle
        out[ch] = spectral_noise(n, mag, rng, loop=True)
    return master(out, drive=1.2, loop=True)


# =============================================================================
# SFX (mono, one-shot)
# =============================================================================
def finish_sfx(y, t60=None, wet=0.0, drive=1.2, seed=0, lp_hz=None):
    y = np.asarray(y, dtype=float)
    if lp_hz:
        y = fft_filter(y, lp(lp_hz, 2), loop=False)
    if t60:
        y = y + wet * convolve_ir(y, [make_ir(t60, seed=seed, damp=0.5, predelay=0.012)], loop=False)[0]
    return master(fade_edges(y, 0.0005, 0.03), drive=drive)


def wood_knock(rng, f, vel=1.0):
    n = nsamp(0.25)
    t = tvec(n)
    y = np.zeros(n)
    for r, a, d in ((1.0, 1.0, 0.05), (2.31, 0.55, 0.028), (3.93, 0.3, 0.016), (5.8, 0.15, 0.01)):
        y += a * np.sin(TWO_PI * f * r * t + rng.uniform(0, TWO_PI)) * np.exp(-t / d)
    k = nsamp(0.002)
    y[:k] += 0.6 * fft_filter(rng.standard_normal(k), hp(2000, 1), loop=False, pad=0.005) * np.linspace(1, 0, k)
    put(y, blip(190, 120, 0.02, 0.03), 0.0, 0.5)
    return vel * y * gate_env(n, 0.23, attack=0.0003, release=0.02)


def crunch(rng, length=0.11, vel=1.0, lo=900.0, hi=6000.0, grains=90):
    n = nsamp(length + 0.03)
    times = rng.exponential(length * 0.35, grains)
    times = times[times < length]
    amps = rng.lognormal(0, 0.6, len(times)) * np.exp(-times / (length * 0.5)) * rng.choice([-1, 1], len(times))
    imp = np.zeros(n)
    np.add.at(imp, (times * SR).astype(int), amps)
    kl = nsamp(0.0015)
    ker = rng.standard_normal(kl) * np.exp(-np.arange(kl) / (kl / 3.0))
    x = np.convolve(imp, ker)[:n]
    x = fft_filter(x, chain(hp(lo, 2), lp(hi, 2), bump(2500, 4.0, 1.2)), loop=False, pad=0.02)
    return vel * x / (np.max(np.abs(x)) + 1e-9) * gate_env(n, length + 0.02, attack=0.0003, release=0.01)


def sfx_splash(rng):
    n = nsamp(1.3)

    def mag(t, f):
        tt = np.maximum(t - 0.01, 0.0)
        on = np.clip((t - 0.005) / 0.01, 0.0, 1.0)
        body = on * np.exp(-tt / 0.16)
        fc = 700.0 + 6500.0 * np.exp(-tt / 0.09)
        spray = on * np.exp(-tt / 0.35) * (1.0 - np.exp(-tt / 0.05))
        P = (body * pink(f) * lp(fc, 2)(f) * hp(90, 2)(f)) ** 2
        P = P + (0.28 * spray * hp(1800, 2)(f) * lp(9000, 2)(f)) ** 2
        return np.sqrt(P)
    y = spectral_noise(n, mag, rng, loop=False, nfft=1024)
    put(y, blip(110, 45, 0.03, 0.09), 0.0, 0.9 * np.std(y) * 4)
    s = np.std(y)
    for _ in range(14):
        t0 = rng.uniform(0.04, 0.75)
        f0 = rng.uniform(300, 1000)
        put(y, blip(f0, f0 * 2.2, 0.012, rng.uniform(0.015, 0.03)), t0, s * 2.5 * np.exp(-t0 / 0.4) * rng.uniform(0.4, 1.0))
    for _ in range(9):
        t0 = rng.uniform(0.3, 1.1)
        f0 = rng.uniform(1600, 3600)
        put(y, blip(f0, f0 * 1.5, 0.008, 0.012), t0, s * 0.9 * rng.uniform(0.5, 1.0))
    return finish_sfx(y, t60=0.6, wet=0.15, seed=101)


def sfx_bell(rng):
    n = nsamp(4.2)
    t = tvec(n)
    f = 116.5
    y = np.zeros(n)
    for r, a, tau in ((0.5, 0.55, 3.8), (1.0, 0.6, 2.6), (1.183, 0.5, 2.2), (1.506, 0.28, 1.6),
                      (2.0, 0.65, 1.7), (2.51, 0.3, 1.1), (2.66, 0.28, 1.0), (3.01, 0.25, 0.8),
                      (4.1, 0.15, 0.55), (5.43, 0.08, 0.35), (6.8, 0.05, 0.25)):
        fr = f * r
        beat = rng.uniform(0.4, 1.6)
        y += a * (np.sin(TWO_PI * fr * t + rng.uniform(0, TWO_PI))
                  + 0.6 * np.sin(TWO_PI * (fr + beat) * t + rng.uniform(0, TWO_PI))) * np.exp(-t / tau)
    y *= gate_env(n, 5.0, attack=0.002)
    k = nsamp(0.15)
    clank = fft_filter(rng.standard_normal(k), chain(hp(1500, 2), lp(5000, 2)), loop=False, pad=0.02)
    put(y, clank / np.max(np.abs(clank)) * np.exp(-tvec(k) / 0.025), 0.0, 0.5)
    put(y, blip(90, 60, 0.03, 0.08), 0.0, 0.6)
    k = nsamp(1.0)
    y[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)
    return finish_sfx(y, t60=2.5, wet=0.25, seed=102)


def sfx_rumble(rng):
    dur = 3.0
    n = nsamp(dur)
    t = tvec(n)
    lo = fft_filter(rng.standard_normal(n), chain(hp(22, 2), lp(85, 3)), loop=False)
    mid = fft_filter(rng.standard_normal(n), chain(hp(70, 2), lp(260, 2)), loop=False)
    jit = 0.65 + 0.35 * smooth_random(n, 9.0, rng, 60.0)
    env = smooth_curve([(0, 0), (0.35, 1.0), (2.0, 0.9), (3.0, 0.0)], n, 150)
    y = (lo / np.std(lo) + 0.6 * mid / np.std(mid) * jit) * env * (0.7 + 0.3 * jit)
    for _ in range(45):
        t0 = rng.uniform(0.3, 2.5)
        put(y, wood(rng.uniform(500, 2200), rng, decay=rng.uniform(0.01, 0.03), click=0.5), t0,
            0.5 * np.interp(t0, t, env) * rng.uniform(0.3, 1.0))
    y = np.tanh(2.2 * y / np.max(np.abs(y)))
    return finish_sfx(y, drive=1.3)


def sfx_drink(rng):
    y = np.zeros(nsamp(0.9))
    for t0, f0, v in ((0.05, 170, 1.0), (0.33, 185, 0.9), (0.60, 160, 0.8)):
        put(y, blip(f0, f0 * 2.1, 0.035, 0.07, length=0.2, harm=((2, 0.35),)), t0, v)
        put(y, blip(f0 * 3.5, f0 * 6.0, 0.02, 0.018), t0 + 0.045, 0.35 * v)
        k = nsamp(0.005)
        put(y, fft_filter(rng.standard_normal(k), lp(1500, 2), loop=False, pad=0.005) * np.linspace(1, 0, k), t0, 0.2 * v)
    return finish_sfx(y, t60=0.4, wet=0.1, seed=103, lp_hz=6000)


def sfx_eat(rng):
    y = np.zeros(nsamp(0.75))
    for t0, v in ((0.02, 1.0), (0.24, 0.85), (0.47, 0.7)):
        put(y, crunch(rng, 0.11, v), t0)
        put(y, blip(170, 120, 0.02, 0.04), t0, 0.35 * v)
    return finish_sfx(y, drive=1.3)


def sfx_craft(rng):
    y = np.zeros(nsamp(0.5))
    put(y, wood_knock(rng, 520, 1.0), 0.02)
    put(y, wood_knock(rng, 551, 0.85), 0.2)
    return finish_sfx(y, t60=0.5, wet=0.12, seed=104)


def sfx_quest(rng):
    y = np.zeros(nsamp(1.5))
    for i, m in enumerate(("G5", "C6", "E6")):
        t0 = 0.02 + i * 0.11
        put(y, glock(nm(m), rng, 1.0, dur=1.3), t0, 0.5)
        put(y, steelpan(nm(m), 0.3, rng), t0, 0.35)
    put(y, glock(nm("C7"), rng, 1.0, dur=1.0), 0.36, 0.15)
    return finish_sfx(y, t60=1.4, wet=0.3, seed=105)


def sfx_hurt(rng):
    n = nsamp(0.6)
    t = tvec(n)
    y = np.zeros(n)
    put(y, blip(430, 170, 0.035, 0.06, harm=((2.1, 0.3),)), 0.0, 1.0)
    put(y, wood(900, rng, decay=0.015, click=0.6), 0.0, 0.4)
    put(y, blip(120, 60, 0.03, 0.08), 0.0, 0.7)
    f = 240.0 * (1.0 - 0.35 * t / 0.6) * (1.0 + 0.12 * np.sin(TWO_PI * 17.0 * t) * np.exp(-t / 0.3))
    ph = TWO_PI * np.cumsum(f) / SR
    boing = (np.sin(ph) + 0.3 * np.sin(2 * ph)) * env_perc(n, 0.005, 0.2, 0.02)
    put(y, boing, 0.02, 0.5)
    return finish_sfx(y, drive=1.3)


def sfx_bite(rng):
    y = np.zeros(nsamp(0.65))

    def mag(t, f):
        a = np.exp(-0.5 * ((t - 0.04) / 0.02) ** 2)
        fc = 300.0 + 1500.0 * np.clip(t / 0.08, 0, 1)
        return a * np.exp(-0.5 * (np.log2(np.maximum(f, 20.0) / fc) / 0.8) ** 2)
    pre = spectral_noise(nsamp(0.1), mag, rng, loop=False, nfft=512)
    put(y, pre / (np.max(np.abs(pre)) + 1e-9), 0.0, 0.25)
    for t0, v in ((0.08, 1.0), (0.36, 0.7)):
        put(y, wood(1500, rng, decay=0.012, click=1.0), t0, 0.8 * v)
        put(y, wood(1700, rng, decay=0.01, click=1.0), t0 + 0.012, 0.6 * v)
        put(y, blip(110, 50, 0.025, 0.05), t0, 0.45 * v)
        put(y, crunch(rng, 0.25, v, lo=500, hi=5000, grains=140), t0 + 0.02, 1.0)
    y = np.tanh(2.0 * y / np.max(np.abs(y)))
    return finish_sfx(y, drive=1.3)


def sfx_fish_bite(rng):
    n = nsamp(0.6)
    y = np.zeros(n)
    put(y, blip(260, 900, 0.012, 0.05), 0.0, 1.0)
    put(y, blip(1400, 2200, 0.008, 0.02), 0.06, 0.3)

    def mag(t, f):
        a = np.clip(t / 0.005, 0, 1) * np.exp(-np.maximum(t, 0) / 0.05)
        return a * lp(3000, 2)(f) * hp(300, 2)(f)
    sp = spectral_noise(nsamp(0.2), mag, rng, loop=False, nfft=512)
    put(y, sp / (np.max(np.abs(sp)) + 1e-9), 0.0, 0.25)
    put(y, blip(330, 1000, 0.012, 0.04), 0.25, 0.45)
    return finish_sfx(y, t60=0.5, wet=0.12, seed=106)


def claw_click(rng, f, vel=1.0):
    n = nsamp(0.05)
    t = tvec(n)
    y = np.zeros(n)
    for r, a, d in ((1.0, 1.0, 0.010), (1.47, 0.6, 0.007), (0.53, 0.5, 0.016), (2.3, 0.3, 0.004)):
        y += a * np.sin(TWO_PI * f * r * t + rng.uniform(0, TWO_PI)) * np.exp(-t / d)
    k = nsamp(0.0015)
    y[:k] += 0.8 * fft_filter(rng.standard_normal(k), hp(1500, 2), loop=False, pad=0.005)
    return vel * y * gate_env(n, 0.045, attack=0.0002, release=0.005)


def sfx_crab(rng):
    y = np.zeros(nsamp(0.6))
    for t0, f, v in ((0.0, 2600, 0.7), (0.07, 2900, 0.6), (0.14, 2500, 0.75), (0.36, 2200, 1.0), (0.375, 3100, 0.8)):
        put(y, claw_click(rng, f, v), t0)
    put(y, wood(750, rng, decay=0.02, click=0.4), 0.36, 0.5)
    return finish_sfx(y, t60=0.3, wet=0.1, seed=107)


def sfx_revive(rng):
    n = nsamp(1.7)
    y = np.zeros(n)
    for i, m in enumerate(("C5", "E5", "G5", "C6", "E6", "G6", "C7")):
        t0 = 0.05 + i * 0.07
        put(y, glock(nm(m), rng, 0.6 + 0.06 * i, dur=1.0), t0, 0.45)
        put(y, marimba(nm(m) - 12, 0.3, rng, hard=0.6), t0, 0.25)
    for _ in range(30):
        f = rng.uniform(5000, 9000)
        put(y, blip(f, f, 0.01, rng.uniform(0.03, 0.08)), rng.uniform(0.3, 1.4), rng.uniform(0.05, 0.12))

    def mag(t, f):
        a = np.clip(t / 0.5, 0, 1) * np.exp(-np.maximum(t - 0.5, 0) / 0.25)
        fc = 400.0 * 2.0 ** (3.6 * np.clip(t / 0.9, 0, 1))
        return a * np.exp(-0.5 * (np.log2(np.maximum(f, 20.0) / fc) / 0.6) ** 2)
    wh = spectral_noise(nsamp(1.3), mag, rng, loop=False, nfft=1024)
    put(y, wh / (np.max(np.abs(wh)) + 1e-9), 0.0, 0.2)
    for m in ("C4", "E4", "G4"):
        put(y, pad_note(nm(m), 0.8, rng, attack=0.4, release=0.5, bright=0.5), 0.05, 0.15)
    return finish_sfx(y, t60=1.8, wet=0.35, seed=108)


def sfx_levelup(rng):
    y = np.zeros(nsamp(1.75))
    for t0, d, notes, v in ((0.0, 0.1, ("E4", "G4"), 0.8), (0.12, 0.1, ("G4", "C5"), 0.8),
                            (0.24, 0.1, ("C5", "E5"), 0.85), (0.38, 0.95, ("E5", "G5", "C6"), 1.0)):
        for m in notes:
            put(y, brass(nm(m), d, rng, vel=v, b_peak=0.85, b_sus=0.65, attack=0.02,
                         release=0.12, vib=0.006 if d > 0.5 else 0.0), t0, 0.3)
    put(y, bass(48, 0.9, vel=0.7, bright=0.3), 0.38, 0.4)
    put(y, tom(65.4, rng, vel=0.8, decay=0.5, bend=0.05, noise=0.2), 0.38, 0.35)
    for i, m in enumerate(("C6", "E6", "G6", "C7")):
        put(y, glock(nm(m), rng, 0.8, dur=1.0), 0.40 + 0.05 * i, 0.12)
    return finish_sfx(y, t60=1.3, wet=0.25, seed=109)


def sfx_place(rng):
    y = np.zeros(nsamp(0.35))
    put(y, blip(160, 80, 0.03, 0.06, harm=((2.0, 0.2),)), 0.0, 0.9)
    put(y, wood_knock(rng, 300, 1.0), 0.0, 0.4)
    k = nsamp(0.01)
    put(y, fft_filter(rng.standard_normal(k), lp(2500, 2), loop=False, pad=0.005) * np.linspace(1, 0, k), 0.0, 0.15)
    return finish_sfx(y, lp_hz=3500)


def sfx_break(rng):
    n = nsamp(0.8)
    y = np.zeros(n)
    k = nsamp(0.02)
    crack = fft_filter(rng.standard_normal(k), chain(hp(400, 2), lp(7000, 2)), loop=False, pad=0.01)
    put(y, crack / np.max(np.abs(crack)) * np.exp(-tvec(k) / 0.008), 0.0, 0.8)
    put(y, blip(130, 60, 0.03, 0.09), 0.0, 0.8)
    for _ in range(40):
        t0 = 0.01 + rng.exponential(0.12)
        if t0 < 0.7:
            put(y, wood(rng.uniform(600, 2800), rng, decay=rng.uniform(0.008, 0.025), click=0.5), t0,
                0.35 * np.exp(-t0 / 0.25) * rng.uniform(0.4, 1.0))
    grit = fft_filter(rng.standard_normal(n), chain(hp(200, 2), lp(2500, 2)), loop=False)
    am = np.clip(smooth_random(n, 60.0, rng, 4.0), 0, None)
    put(y, grit / np.std(grit) * am * np.exp(-tvec(n) / 0.18), 0.0, 0.12)
    return finish_sfx(y, t60=0.4, wet=0.1, seed=110)


def sfx_whoosh(rng):
    def mag(t, f):
        a = np.exp(-0.5 * ((t - 0.19) / np.where(t < 0.19, 0.07, 0.11)) ** 2)
        fc = 350.0 + 2000.0 * np.exp(-0.5 * ((t - 0.2) / 0.09) ** 2)
        band = np.exp(-0.5 * (np.log2(np.maximum(f, 20.0) / fc) / 0.7) ** 2)
        return a * (band + 0.15 * lp(600, 1)(f))
    return finish_sfx(spectral_noise(nsamp(0.5), mag, rng, loop=False, nfft=512))


def sfx_pickup(rng):
    y = np.zeros(nsamp(0.3))
    put(y, blip(400, 1200, 0.015, 0.045, harm=((2, 0.15),)), 0.0, 1.0)
    put(y, glock(nm("E7"), rng, 1.0, dur=0.22), 0.055, 0.25)
    return finish_sfx(y)


def owl_hoot(dur, fa, fb, rng):
    n = nsamp(dur)
    t = tvec(n)
    f = smooth_curve([(0, fa * 0.97), (dur * 0.3, fa * 1.03), (dur, fb)], n, 20)
    ph = TWO_PI * np.cumsum(f) / SR
    y = np.sin(ph) + 0.08 * np.sin(2 * ph)
    breath = fft_filter(rng.standard_normal(n), chain(hp(250, 2), lp(900, 2)), loop=False)
    y += 0.15 * breath / np.std(breath)
    return y * np.sin(np.pi * t / dur) ** 0.7


def sfx_night(rng):
    n = nsamp(1.95)
    t = tvec(n)
    y = np.zeros(n)
    for r, a, tau in ((1.0, 1.0, 2.2), (1.47, 0.5, 1.6), (2.09, 0.4, 1.3), (2.56, 0.28, 1.0),
                      (2.95, 0.22, 0.8), (3.61, 0.14, 0.6), (4.3, 0.09, 0.45)):
        fr = 98.0 * r
        ph = TWO_PI * fr * (t + 0.012 * 0.25 * (1 - np.exp(-t / 0.25)))   # sinks ~1% (spooky bend)
        y += a * np.sin(ph + rng.uniform(0, TWO_PI)) * np.exp(-t / tau) * (1 + 0.15 * np.sin(TWO_PI * (0.9 + 0.5 * r) * t))
    y *= gate_env(n, 5.0, attack=0.012)
    for t0, d, fa, fb, g in ((0.55, 0.32, 390, 360, 0.55), (1.05, 0.22, 400, 370, 0.4), (1.33, 0.38, 395, 350, 0.45)):
        put(y, owl_hoot(d, fa, fb, rng), t0, g)
    k = nsamp(0.35)
    y[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)
    return finish_sfx(y, t60=2.2, wet=0.35, seed=111)


def sfx_morning(rng):
    n = nsamp(1.8)
    fpts = [(0.00, 700), (0.10, 1050), (0.14, 1050), (0.16, 1000), (0.26, 1250), (0.30, 1250),
            (0.32, 1200), (0.44, 1480), (0.50, 1480), (0.52, 1400), (0.80, 1900), (1.00, 1850),
            (1.25, 1350), (1.8, 1300)]
    apts = [(0, 0), (0.03, 0.8), (0.11, 0.9), (0.14, 0.25), (0.18, 0.85), (0.27, 0.9), (0.30, 0.25),
            (0.34, 0.9), (0.45, 0.95), (0.49, 0.3), (0.54, 1.0), (1.1, 0.9), (1.3, 0.4), (1.4, 0.0), (1.8, 0.0)]
    y = slide_whistle(smooth_curve(fpts, n, 15), rng, vib_depth=0.012) * smooth_curve(apts, n, 12)
    for i, m in enumerate(("E6", "G6", "C7")):
        put(y, glock(nm(m), rng, 1.0, dur=0.45), 1.3 + 0.06 * i, 0.3)
    return finish_sfx(y, t60=1.2, wet=0.2, seed=112)


def sfx_boat_horn(rng):
    n = nsamp(2.4)
    t = tvec(n)
    amp = smooth_curve([(0, 0), (0.15, 0.8), (0.3, 1.0), (1.75, 0.95), (2.05, 0.0), (2.4, 0.0)], n, 30)
    pitch = smooth_curve([(0, 0.965), (0.25, 1.0), (1.8, 1.0), (2.05, 0.975), (2.4, 0.97)], n, 30)
    y = np.zeros(n)
    for f, g in ((92.5, 1.0), (116.5, 0.8)):   # F#2 + A#2 (major third)
        f0 = f * pitch * (1.0 + 0.002 * np.sin(TWO_PI * 4.7 * t))
        y += g * formant_voice(f0, [(480, 160, 1.0), (1150, 260, 0.45), (2500, 400, 0.12)], rng, fmax=5000, tilt=0.55)
    y = np.tanh(1.8 * y * amp / np.max(np.abs(y)))
    return finish_sfx(y, t60=2.2, wet=0.35, seed=113, lp_hz=3500)


def sfx_turtle(rng):
    n = nsamp(3.0)
    f0 = smooth_curve([(0, 50), (0.4, 62), (1.1, 68), (1.9, 54), (2.45, 40), (2.62, 40), (2.75, 55), (3.0, 50)], n, 40)
    f0 = f0 * (1.0 + 0.02 * smooth_random(n, 12.0, rng, 20.0))
    F1 = smooth_curve([(0, 260), (0.5, 380), (1.2, 620), (1.9, 420), (2.5, 300), (3.0, 280)], n, 60)
    F2 = smooth_curve([(0, 650), (0.5, 800), (1.2, 1050), (1.9, 800), (2.5, 650), (3.0, 600)], n, 60)
    amp = smooth_curve([(0, 0), (0.25, 0.6), (0.9, 1.0), (2.1, 0.85), (2.45, 0.3), (2.6, 0.2),
                        (2.72, 0.9), (2.9, 0.3), (3.0, 0.0)], n, 20)
    y = formant_voice(f0, [(F1, 90, 1.0), (F2, 130, 0.5), (2400, 200, 0.12)], rng, fmax=4500, tilt=0.8)
    y *= 1.0 + 0.3 * np.sin(TWO_PI * np.cumsum(f0 / 2.0) / SR)       # creaky subharmonic
    breath = fft_filter(rng.standard_normal(n), chain(hp(100, 2), lp(800, 2)), loop=False)
    y = (y / np.std(y) + 0.15 * breath / np.std(breath)) * amp
    return finish_sfx(y, t60=1.6, wet=0.2, seed=114, drive=1.4)


# =============================================================================
# Driver
# =============================================================================
def _sfx(fn, seed):
    return lambda: fn(np.random.default_rng(seed))


JOBS = [  # (relative path, render function, is_loop)
    ("music/day.wav", render_day, True),
    ("music/night.wav", render_night, True),
    ("music/danger.wav", render_danger, True),
    ("music/title.wav", render_title, True),
    ("music/ending.wav", render_ending, False),
    ("amb/ocean.wav", render_ocean, True),
    ("amb/rain.wav", render_rain, True),
    ("amb/wind.wav", render_wind, True),
    ("sfx/splash.wav", _sfx(sfx_splash, 5001), False),
    ("sfx/bell.wav", _sfx(sfx_bell, 5002), False),
    ("sfx/rumble.wav", _sfx(sfx_rumble, 5003), False),
    ("sfx/drink.wav", _sfx(sfx_drink, 5004), False),
    ("sfx/eat.wav", _sfx(sfx_eat, 5005), False),
    ("sfx/craft.wav", _sfx(sfx_craft, 5006), False),
    ("sfx/quest.wav", _sfx(sfx_quest, 5007), False),
    ("sfx/hurt.wav", _sfx(sfx_hurt, 5008), False),
    ("sfx/bite.wav", _sfx(sfx_bite, 5009), False),
    ("sfx/fish_bite.wav", _sfx(sfx_fish_bite, 5010), False),
    ("sfx/crab.wav", _sfx(sfx_crab, 5011), False),
    ("sfx/revive.wav", _sfx(sfx_revive, 5012), False),
    ("sfx/levelup.wav", _sfx(sfx_levelup, 5013), False),
    ("sfx/place.wav", _sfx(sfx_place, 5014), False),
    ("sfx/break.wav", _sfx(sfx_break, 5015), False),
    ("sfx/whoosh.wav", _sfx(sfx_whoosh, 5016), False),
    ("sfx/pickup.wav", _sfx(sfx_pickup, 5017), False),
    ("sfx/night.wav", _sfx(sfx_night, 5018), False),
    ("sfx/morning.wav", _sfx(sfx_morning, 5019), False),
    ("sfx/boat_horn.wav", _sfx(sfx_boat_horn, 5020), False),
    ("sfx/turtle.wav", _sfx(sfx_turtle, 5021), False),
]


BAR_SECONDS = {  # 4/4 bar length of each music loop (seam = downbeat)
    "music/day.wav": 4 * 60.0 / 105.0,
    "music/night.wav": 4 * 60.0 / 64.0,
    "music/danger.wav": 4 * 60.0 / 150.0,
    "music/title.wav": 4 * 60.0 / 90.0,
}


def loop_check(x, bar=None):
    """Seam jump vs. the file's own sample steps, and the 10 ms RMS change
    across the seam vs. the same change measured inside the file: at every
    interior bar line for music (the seam is a downbeat), otherwise the 99th
    percentile over all adjacent 10 ms windows."""
    jump = float(np.max(np.abs(x[:, 0] - x[:, -1])))
    step = float(np.percentile(np.abs(np.diff(x, axis=1)), 99.9))
    w = nsamp(0.01)
    seam_db = db(rms(x[:, :w])) - db(rms(x[:, -w:]))
    if bar:
        cuts = [nsamp(k * bar) for k in range(1, int(round(x.shape[1] / SR / bar)))]
        typ_db = max(abs(db(rms(x[:, c:c + w])) - db(rms(x[:, c - w:c]))) for c in cuts)
    else:
        m = x.shape[1] // w
        r = np.sqrt(np.mean(x[:, :m * w].reshape(x.shape[0], m, w) ** 2, axis=(0, 2))) + 1e-9
        typ_db = float(np.percentile(np.abs(np.diff(20 * np.log10(r))), 99))
    ok = jump <= step and abs(seam_db) <= typ_db
    return jump, step, seam_db, typ_db, ok


def report(done):
    print()
    print("%-22s %3s %8s %9s %9s %9s  %s" % ("file", "ch", "dur s", "peak dB", "rms dB", "size KB", "loop seam check"))
    print("-" * 118)
    total = 0
    for rel, path, is_loop in done:
        x = read_wav(path)
        size = os.path.getsize(path)
        total += size
        seam = ""
        if is_loop:
            bar = BAR_SECONDS.get(rel)
            jump, step, sdb, tdb, ok = loop_check(x, bar)
            seam = "|last-first| %.4f (p99.9 step %.4f)  10ms RMS %+5.1f dB (%s %.1f)  %s" % (
                jump, step, sdb, "bar-line max" if bar else "p99", tdb, "OK" if ok else "CHECK")
        print("%-22s %3d %8.2f %9.2f %9.2f %9.0f  %s" % (
            rel, x.shape[0], x.shape[1] / SR, db(np.max(np.abs(x))), db(rms(x)), size / 1024.0, seam))
    print("-" * 118)
    print("%d files, total %.2f MB" % (len(done), total / 1024.0 / 1024.0))


def main(argv):
    only = set(argv)
    done = []
    t_all = time.time()
    for rel, fn, is_loop in JOBS:
        stem = os.path.splitext(rel)[0]
        if only and not ({rel, stem, os.path.basename(stem)} & only):
            continue
        t0 = time.time()
        x = fn()
        path = os.path.join(OUT_DIR, *rel.split("/"))
        write_wav(path, x, loop=is_loop)
        done.append((rel, path, is_loop))
        print("rendered %-22s %5.1f s" % (rel, time.time() - t0))
    print("total render time %.1f s" % (time.time() - t_all))
    report(done)


if __name__ == "__main__":
    main(sys.argv[1:])
