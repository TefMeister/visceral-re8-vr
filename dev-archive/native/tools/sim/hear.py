"""hear.py [label]: record what the PC plays for 2 s, pressing the right trigger (VR Bench) at 0.6 s; prints the loudness
around the press (peak per 40 ms, dBFS) and saves the clip as hear-<label>.wav beside this script"""
import sys, os, time, threading, wave
import numpy as np, soundcard as sc
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk, vb_input as I, vb_settings as S
label = sys.argv[1] if len(sys.argv) > 1 else "clip"
RATE = 48000
sp = sc.default_speaker(); mic = sc.get_microphone(id=str(sp.name), include_loopback=True)
p = walk.load()
def put(rt):
    inp = I.Input().mode(poses="set", buttons="set")
    r = I.pose_from_ypr(p["right"][0:3], p["right"][3], p["right"][4]); inp.hand(S.HAND_RIGHT, grip=r, aim=r, trigger=rt)
    l = I.pose_from_ypr(p["left"][0:3], p["left"][3], p["left"][4]); inp.hand(S.HAND_LEFT, grip=l, aim=l, squeeze=p.get("squeeze", 0.0), trigger=p.get("trigger", 0.0))
    I.write(inp)
def press():
    time.sleep(0.6); put(1.0); time.sleep(0.15); put(0.0)
threading.Thread(target=press).start()
with mic.recorder(samplerate=RATE) as rec: data = rec.record(numframes=RATE * 2)
mono = np.abs(data).max(axis=1)
w = int(RATE * 0.04)
peaks = [20 * np.log10(max(mono[i:i + w].max(), 1e-6)) for i in range(0, len(mono) - w, w)]
seg = peaks[14:35]; k = max(range(len(seg)), key=lambda i: seg[i])
print("%-8s peak %4.0f dB at %.2f s | %s" % (label, seg[k], 0.56 + 0.04 * k, " ".join("%.0f" % v for v in seg)))
pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
with wave.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "hear-%s.wav" % label), "wb") as f:
    f.setnchannels(pcm.shape[1]); f.setsampwidth(2); f.setframerate(RATE); f.writeframes(pcm.tobytes())
