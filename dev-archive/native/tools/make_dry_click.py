"""Makes sfx/dry_click.wav: the empty-gun click Visceral RE8 plays when RT is pressed on an empty gun or one that needs
racking (2026-10-30, Tefa: "a quick short click, so that on repeated presses the sound doesn't cut out anywhere").
Made from scratch here, so it is ours: a sharp metal tick (a very short noise burst) and two quickly fading rings.
40 ms long, so even fast repeated presses each get a whole click. Re-run to change it: python tools/make_dry_click.py"""
import math, random, struct, wave, os

RATE = 44100
LENGTH_S = 0.040        # the whole click
TICK_DECAY_S = 0.0015   # the hammer's tick
RINGS = ((2900.0, 0.008, 0.45), (1300.0, 0.012, 0.30))   # (pitch Hz, fade s, loudness)
FADE_OUT_S = 0.005
PEAK = 0.70             # loudest point, of full scale

random.seed(8)
n = int(RATE * LENGTH_S)
out, lp = [], 0.0
for i in range(n):
    t = i / RATE
    lp += 0.55 * (random.uniform(-1, 1) - lp)            # the tick, a little softened
    v = 0.9 * lp * math.exp(-t / TICK_DECAY_S)
    for hz, fade, amp in RINGS:
        v += amp * math.sin(2 * math.pi * hz * t) * math.exp(-t / fade)
    tail = (LENGTH_S - t) / FADE_OUT_S
    if tail < 1.0: v *= max(tail, 0.0)
    out.append(v)
top = max(abs(v) for v in out)
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sfx", "dry_click.wav")
with wave.open(path, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<h", int(v / top * PEAK * 32767)) for v in out))
print(f"{os.path.normpath(path)}: {n} samples, {LENGTH_S * 1000:.0f} ms")
