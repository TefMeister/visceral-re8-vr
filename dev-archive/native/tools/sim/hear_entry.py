"""hear_entry.py <label> <squeeze 0|1> -- (2026-11-08, the LEMI slide-sphere click) record what the PC plays for 3 s while the
left controller jumps from 30 cm outside into the slide sphere at 1.0 s (the pose walk.py found, pose_now.json), LG held or not;
prints the loudness per 40 ms (dBFS) and saves hear-<label>.wav beside this script."""
import sys, os, time, threading, wave
import numpy as np, soundcard as sc
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk, vb_input as I, vb_settings as S
label, sq = sys.argv[1], float(sys.argv[2])
RATE = 48000
sp = sc.default_speaker(); mic = sc.get_microphone(id=str(sp.name), include_loopback=True)
p = walk.load()
inside = p["left"]; outside = [inside[0] - 0.30, inside[1] - 0.05, inside[2] + 0.05, inside[3], inside[4]]
def put(lp):
    inp = I.Input().mode(poses="set", buttons="set")
    r = I.pose_from_ypr(p["right"][0:3], p["right"][3], p["right"][4]); inp.hand(S.HAND_RIGHT, grip=r, aim=r)
    l = I.pose_from_ypr(lp[0:3], lp[3], lp[4]); inp.hand(S.HAND_LEFT, grip=l, aim=l, squeeze=sq)
    I.write(inp)
put(outside); time.sleep(1.5)
def move(): time.sleep(1.0); put(inside)
threading.Thread(target=move).start()
with mic.recorder(samplerate=RATE) as rec: data = rec.record(numframes=RATE * 3)
mono = np.abs(data).max(axis=1)
w = int(RATE * 0.04)
peaks = [20 * np.log10(max(mono[i:i + w].max(), 1e-6)) for i in range(0, len(mono) - w, w)]
print(label, "dBFS per 40 ms from 0.8 s:", " ".join(f"{v:.0f}" for v in peaks[20:45]))
with wave.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), f"hear-{label}.wav"), "wb") as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE); f.writeframes((np.clip(data[:, 0], -1, 1) * 32767).astype(np.int16).tobytes())
put(outside)
