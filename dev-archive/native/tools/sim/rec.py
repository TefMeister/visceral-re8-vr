"""rec.py <label> <secs> <wwise id>: record what the PC plays for <secs>, asking zz_test_trigger.lua to play that game sound
on the gun in hand 0.5 s in; saves rec-<label>.wav beside this script and prints the loudness per 20 ms"""
import sys, os, time, threading, json, wave
import numpy as np, soundcard as sc
label, secs, wid = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
REQ = os.path.join(r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE", "reframework", "data", "visceral_re8", "test_trigger.json")
RATE = 48000
sp = sc.default_speaker()
mic = sc.get_microphone(id=str(sp.name), include_loopback=True)


def fire():
    time.sleep(0.5)
    json.dump({"seq": int(time.time() * 1000), "id": wid}, open(REQ, "w"))


threading.Thread(target=fire).start()
with mic.recorder(samplerate=RATE) as rec:
    data = rec.record(numframes=int(RATE * secs))
pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rec-%s.wav" % label)
with wave.open(out, "wb") as f:
    f.setnchannels(pcm.shape[1]); f.setsampwidth(2); f.setframerate(RATE); f.writeframes(pcm.tobytes())
m = np.abs(data).max(axis=1)
w = int(RATE * 0.02)
print(label, " ".join("%.0f" % (20 * np.log10(max(m[i:i + w].max(), 1e-6))) for i in range(0, len(m) - w, w)))
