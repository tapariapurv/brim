#!/usr/bin/env python3
"""Brim score. Everything is synthesised, timed from assets/cues.js.
Idea: the melody is water drops, and the music's filter follows the film's water level."""
import json, pathlib, wave
import numpy as np
from scipy.signal import butter, fftconvolve, lfilter, lfilter_zi

ROOT = pathlib.Path(__file__).resolve().parent.parent
C = json.loads((ROOT / "assets/cues.js").read_text().split("=", 1)[1].rstrip(";\n"))
SR, DUR, B = 48000, C["DUR"], C["B"]
N = int(DUR * SR); BAR = B * 4
rng = np.random.default_rng(11)
mk = lambda: np.zeros((N, 2))
music, drums, wet, sfx = mk(), mk(), mk(), mk()   # music is filtered by the water; wet is the reverb send

def put(bus, sig, t, gain=1., pan=0.):
    i = int(t * SR)
    if i >= N or i < 0: return
    sig = sig[:N - i] * gain
    bus[i:i + len(sig), 0] += sig * np.sqrt((1 - pan) / 2) * 1.414
    bus[i:i + len(sig), 1] += sig * np.sqrt((1 + pan) / 2) * 1.414
hz = lambda m: 440 * 2 ** ((m - 69) / 12)
T = lambda d: np.arange(int(d * SR)) / SR
def lp(x, f): b, a = butter(2, min(f, SR * .45) / (SR / 2)); return lfilter(b, a, x)
def hp(x, f): b, a = butter(2, f / (SR / 2), "high"); return lfilter(b, a, x)
noise = lambda d: rng.standard_normal(int(d * SR))

# ---- instruments
def drop(m, d=.32):           # a tuned water drop: fast upward chirp, quick decay
    t = T(d); f = hz(m) * (1 + .38 * (1 - np.exp(-t * 60))); ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + .22 * np.sin(2 * ph)) * np.minimum(t / .0015, 1) * np.exp(-t * 15)
def bloop(m):                 # rising underwater bubble
    t = T(.28); f = hz(m) * (.72 + .55 * t / .28); return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / .28) ** 1.4
def pad(ms, d):               # detuned triangles, soft swell
    t = T(d); x = np.zeros(len(t))
    for m in ms:
        for det in (-.07, 0, .06):
            ph = 2 * np.pi * hz(m + det) * t + rng.uniform(0, 6)
            x += (2 / np.pi) * np.arcsin(np.sin(ph)) + .25 * np.sin(2 * ph)
    return x / (len(ms) * 3) * np.minimum(t / .5, 1) * np.minimum((d - t) / .35, 1)
def pluck(m, d=.5):
    t = T(d); return (np.sin(2 * np.pi * hz(m) * t) + .35 * np.sin(4 * np.pi * hz(m) * t) + .12 * np.sin(6 * np.pi * hz(m) * t)) * np.minimum(t / .002, 1) * np.exp(-t * 7)
def bass(m, d):
    t = T(d); x = np.sin(2 * np.pi * hz(m) * t) + .3 * np.sin(4 * np.pi * hz(m) * t)
    return np.tanh(x * 1.5) * np.minimum(t / .006, 1) * np.minimum((d - t) / .03, 1)
def kick(g=1.):
    t = T(.36); f = 46 + 95 * np.exp(-t * 38); return np.tanh(np.sin(2 * np.pi * np.cumsum(f) / SR) * 1.6) * np.exp(-t * 9) * g
def clap():
    x = hp(noise(.22), 900); t = T(.22); e = np.exp(-t * 26) + .6 * np.exp(-((t - .012) * 300) ** 2) + .5 * np.exp(-((t - .024) * 300) ** 2)
    return lp(x, 6500) * e
def shake(g=1.): t = T(.07); return hp(noise(.07), 6500) * np.exp(-t * 70) * g
def tick(): t = T(.03); return lp(noise(.03), rng.uniform(3000, 4600)) * np.exp(-t * 170)
def thock(): t = T(.1); return lp(noise(.1), 1700) * np.exp(-t * 80) + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 55) * .7
def whoosh(d, up=True):
    t = T(d); x = noise(d); e = (t / d) ** 2.4 if up else (1 - t / d) ** 2.4
    a = lp(x, 500 + (6500 if up else 2500) * (t.mean())); return (a - lp(x, 180)) * e
def sub_hit(): t = T(1.3); f = 34 + 70 * np.exp(-t * 16); return np.tanh(np.sin(2 * np.pi * np.cumsum(f) / SR) * 2.2) * np.exp(-t * 3.2)

CH = [[50, 62, 66, 69, 73, 76], [47, 62, 66, 69, 73, 74], [43, 62, 67, 71, 74, 78], [45, 62, 64, 67, 69, 76]]  # D, Bm, G, Asus
barof = lambda t: int(t // BAR)

# ---- act 1: muffled, tense, heartbeat under the typing
for k in range(8):
    put(drums, kick(.55 if k % 4 == 0 else .36), k * B, .7)
put(music, pad([38, 57, 62, 65], 4.9), 0, .32)              # D minor colour until the product arrives
for i, k in enumerate(C["keys"]): put(sfx, tick(), k, .55, rng.uniform(-.2, .2))
for i, t in enumerate(C["lines"]): put(sfx, thock(), t, .35); put(music, pluck(62 + [0, 3, 7, 10, 12, 15, 19][i], .3), t, .25); put(wet, pluck(62 + [0, 3, 7, 10, 12, 15, 19][i], .3), t, .05)
for k in range(8, 16): put(drums, shake(.5), 2.4 + k * B / 4 - 1.2, .4)
for t in np.arange(3.6, 4.8, B / 4): put(music, pluck(50, .12), t, .22)

# tape stop on everything so far, ending dead on the hit
def tape_stop(bus, a, b):
    ia, ib = int(a * SR), int(b * SR)
    n = ib - ia; sp = (1 - np.arange(n) / n) ** 1.5
    pos = ia + np.cumsum(sp)
    for ch in (0, 1):
        bus[ia:ib, ch] = np.interp(pos, np.arange(N), bus[:, ch]) * (1 - np.arange(n) / n) ** .4
        bus[ib:int(6.55 * SR), ch] = 0

# ---- act 2: the product. Pads per bar from the impact on.
start = C["impact"]
for b in range(barof(start), barof(DUR) + 1):
    t = b * BAR
    if t >= 41.9: break
    put(music, pad(CH[(b - 3) % 4], BAR + .35), t - .1, .5)
put(music, pad(CH[0] + [81], 4.8), 41.9, .42)

# droplet melody: the hook
HOOK = [(0, 74), (.75, 81), (1.5, 78), (2.5, 83), (3.25, 81), (4, 76), (4.75, 78), (5.5, 73), (6.5, 69), (7.25, 74)]
def melody(t0, g=1., pan=.25):
    for i, (bt, m) in enumerate(HOOK):
        s = drop(m); p = pan * (1 if i % 2 else -1)
        put(sfx, s, t0 + bt * B, .36 * g, p); put(wet, s, t0 + bt * B, .3 * g, p)
melody(start + BAR * .5, 1.1); melody(14.4, .8); melody(19.2, .7); melody(36, 1.)
for bt, m in [(0, 74), (1, 81), (2, 78), (3, 86)]:
    put(sfx, drop(m), 40.2 + bt * B, .42, (bt - 1.5) * .25); put(wet, drop(m), 40.2 + bt * B, .42)

# groove
def groove(a, b, full=True):
    for i in range(int(round((b - a) / (B / 4)))):
        t = a + i * B / 4; s = i % 16
        swing = .012 if i % 2 else 0
        if s in (0, 7, 10) or (full and s == 8): put(drums, kick(), t, .82)
        if s in (4, 12): put(drums, clap(), t, .3); put(wet, clap(), t, .05)
        put(drums, shake(.9 if i % 4 == 2 else .45), t + swing, .3, .2 if i % 2 else -.15)
        root = CH[(barof(t + 1e-6) - 3) % 4][0] - 12 + (12 if CH[(barof(t + 1e-6) - 3) % 4][0] < 44 else 0)
        if s in (0, 3, 6, 10, 13) or (full and s == 14):
            put(music, bass(root + (12 if s == 13 else 0), B / 4 * (1.6 if s != 6 else 2.4)), t, .42)
        if full and s in (2, 5, 9, 11, 14):
            m = CH[(barof(t + 1e-6) - 3) % 4][1 + (s % 5)]
            put(music, pluck(m + 12, .34), t + swing, .15, .3 if i % 2 else -.3); put(wet, pluck(m + 12, .34), t, .05)
groove(14.4, 21.6); groove(33.6, 38.4); groove(27.6, 28.8, False); groove(28.8, 31.2, True)
for i in range(16): put(drums, shake(.25 + i * .03), 9.6 + i * B / 2 - 0, .24)

# ---- moments
put(sfx, whoosh(.6), 6.6, .22)                                # the drop falling
put(sfx, drop(62, .8), start, 1.0); put(wet, drop(62, .8), start, 1.1); put(sfx, sub_hit(), start, .75)
put(wet, drop(74, .4), start + .16, .5); put(wet, drop(81, .4), start + .34, .3)
put(sfx, whoosh(1.2), 10.8 + .0, .16)                         # riser into the menu bar
put(sfx, whoosh(.7, False), 11.4, .18)
for t in C["rows"]: put(sfx, thock(), t, .22)
for i, t in enumerate(C["rows"]): s = drop([74, 76, 78, 81, 83, 85, 86, 88][i], .2); put(sfx, s, t, .2, -.3 + i * .08); put(wet, s, t, .14)
for t in (C["click1"], C["click2"]): put(sfx, thock(), t, .9); put(sfx, tick(), t, .9)
put(sfx, whoosh(.6), 16.2, .2)                                # camera push
t = T(.95); sw = np.sin(2 * np.pi * np.cumsum(420 + 700 * (t / .95) ** 1.6) / SR) * np.minimum(t / .1, 1) * np.minimum((.95 - t) / .06, 1)
put(sfx, sw, 16.85, .06); put(wet, sw, 16.85, .07)            # Session bar filling
put(sfx, drop(90, .25), 18.3, .4); put(wet, drop(90, .25), 18.3, .3)  # pace mark
put(sfx, whoosh(.5, False), 19.2, .22)
t = T(1.); put(sfx, np.sin(2 * np.pi * np.cumsum(500 + 900 * (1 - (1 - t) ** 3)) / SR) * np.exp(-t * 2) * .5, 19.9, .12)  # ring sweep
put(sfx, whoosh(1.6), 21.6, .5); put(sfx, sub_hit(), 23.2, .55)   # the flood
PENT = [62, 66, 69, 74, 76, 78, 81, 86, 88, 90, 93, 98]
for i, tb in enumerate(C["bubbles"]):
    s = bloop(PENT[i] - 5); pn = -.6 + i * .11
    put(sfx, s, tb, .26, pn); put(wet, s, tb, .28, pn)
for t in np.arange(23.4, 26, .3): put(sfx, bloop(rng.choice([55, 57, 62, 64])), t + rng.uniform(0, .1), .08, rng.uniform(-.7, .7))
put(sfx, whoosh(.9, False), 26.3, .5)                         # the drain
n = 18
for i in range(n):                                            # cost counter clicks, accelerating
    t = 26.9 + 1.2 * (1 - (1 - i / n) ** 2.5) * .9; put(sfx, tick(), t, .4); put(sfx, drop(74 + i // 2, .08), t, .05)
put(sfx, drop(86, .5), 28.1, .45); put(wet, drop(86, .5), 28.1, .5)
for i, t in enumerate(C["swaps"]):
    stab = sum(pluck(m + 12, .8) for m in CH[i + 1 if i else 0][1:]) * .3
    put(sfx, stab, t, .32); put(wet, stab, t, .4); put(sfx, whoosh(.4), t - .4, .12)
for i, t in enumerate(C["privacy"]):
    put(drums, kick(1.2), t, 1.0); put(sfx, sub_hit(), t, .3)
    stab = sum(pluck(m + 12, .6) for m in CH[[2, 3, 0][i]][1:]) * .3
    put(sfx, stab, t, .4); put(wet, stab, t, .5)
for t in C["cc"]: put(sfx, thock(), t, .8); put(sfx, tick(), t, .8)
put(sfx, drop(81, .3), C["rc"], .5); put(wet, drop(81, .3), C["rc"], .4); put(sfx, whoosh(.4), C["rc"] - .4, .14)
for i, t in enumerate(C["ok"]): put(sfx, drop([86, 90][i], .4), t, .5); put(wet, drop([86, 90][i], .4), t, .5)
put(sfx, whoosh(1.9), 38.3, .55); put(drums, kick(1.2), 40.2, 1.); put(sfx, sub_hit(), 40.2, .6)
put(sfx, drop(62, 1.), C["impact2"], .85); put(wet, drop(62, 1.), C["impact2"], 1.); put(wet, drop(74, .5), C["impact2"] + .2, .4); put(wet, drop(81, .5), C["impact2"] + .42, .25)

# ---- the water drives the mix
def kf(k, t):
    k = np.array(k); x = np.searchsorted(k[:, 0], t, side="left").clip(1, len(k) - 1)
    a, b = k[x - 1], k[x]; u = ((t - a[:, 0]) / np.maximum(b[:, 0] - a[:, 0], 1e-6)).clip(0, 1); return a[:, 1] + (b[:, 1] - a[:, 1]) * u * u * (3 - 2 * u)
tt = np.arange(N) / SR
level = kf(C["level"], tt)
# cutoff: closed in the dark, opening as water rises, muffled when the frame is under
cut = np.where(tt < C["impact"], 900, 900 + 11000 * np.clip(level / .4, 0, 1) ** 2)
cut = np.where(level > .95, 420, cut); cut = np.where((tt > 33.6) & (level < .3), 11000, cut)
cut = np.where(tt >= 39.6, np.minimum(420 + 11000 * ((tt - 39.6) / 1.2).clip(0, 1) ** 2, 12000), cut)
cut = np.where((tt >= 12) & (tt < 13.2), 2200, cut)
cut = lfilter([.0004], [1, -.9996], cut, zi=[cut[0] * .9996])[0]
under = np.clip((level - .95) / .1, 0, 1)
under = np.where(tt >= 39.6, 0, under)
for bus in (music, drums):
    for ch in (0, 1):
        x = bus[:, ch]; out = np.zeros(N); zi = None; BL = 480
        for i in range(0, N, BL):
            b, a = butter(2, min(cut[i], 16000) / (SR / 2))
            if zi is None: zi = lfilter_zi(b, a) * x[i]
            out[i:i + BL], zi = lfilter(b, a, x[i:i + BL], zi=zi)
        bus[:, ch] = out
drums *= (1 - .75 * under)[:, None]
# sidechain the music to the kick pattern from the groove
env = lp(np.abs(drums.sum(1)), 18); env = (env / (env.max() + 1e-9)).clip(0, 1)
music *= (1 - .5 * env)[:, None]

# act 1 ends with the tape stop into silence
tape_stop(music, 4.3, C["hit"]); tape_stop(drums, 4.3, C["hit"]); tape_stop(sfx, 4.5, C["hit"])
# the hit, then almost nothing but room and the tail of the reverb
t = T(.6); alert = (np.sin(2 * np.pi * 880 * t) + np.sin(2 * np.pi * 932 * t)) * np.exp(-t * 9)
put(sfx, sub_hit(), C["hit"], 1.); put(sfx, alert, C["hit"], .14); put(wet, alert, C["hit"], .3); put(sfx, lp(noise(.14), 2500) * np.exp(-T(.14) * 30), C["hit"], .5)
room = lp(noise(DUR), 240); room *= np.where((tt > C["hit"]) & (tt < start), 1, 0) * .012
sfx += np.stack([room, room], 1)

# ---- reverb and master
def ir(d=3.2, seed=0):
    g = np.random.default_rng(seed); n = int(d * SR); t = np.arange(n) / SR
    x = g.standard_normal(n) * np.exp(-t * 2.1); x = lp(x, 5200); x[:int(.018 * SR)] = 0; return x / np.sqrt((x ** 2).sum())
rev = np.stack([fftconvolve(wet[:, c], ir(seed=c))[:N] for c in (0, 1)], 1)
mix = music * .9 + drums * .95 + sfx * .95 + rev * 1.0
mix -= lfilter([1], [1, -.999], mix, axis=0) * .001                    # dc
mix = np.tanh(mix * 1.15)
mix *= np.minimum((DUR - tt) / .9, 1)[:, None].clip(0, 1) ** 1.3
mix *= np.minimum(tt / .02, 1)[:, None]
mix /= np.abs(mix).max() / .62
pcm = (mix * 32767).astype(np.int16)
with wave.open(str(ROOT / "assets/score.wav"), "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
assert np.abs(mix[int(5.6 * SR):int(6.4 * SR)]).max() < .25, "the silence after the hit must stay quiet"
for a, b in [(0, 4.8), (5, 7), (7.2, 14), (14.4, 21.6), (23.5, 26), (28.8, 33.6), (33.6, 38.4), (40.2, 44)]:
    seg = mix[int(a * SR):int(b * SR)]; print(a, b, "rms %.3f peak %.3f" % (np.sqrt((seg ** 2).mean()), np.abs(seg).max()))
