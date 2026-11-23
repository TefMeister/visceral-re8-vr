"""key.py <scancode hex> [hold_s] -- one keyboard key to the window in front, by scancode (SendInput): 01 Esc, 1C Enter, 39 Space,
D2 Insert (extended keys: add 100, e.g. 152). Bring the game forward first (keys.py <pid>). 2026-11-23."""
import ctypes, sys, time
from ctypes import wintypes as w
sc = int(sys.argv[1], 16); hold = float(sys.argv[2]) if len(sys.argv) > 2 else 0.08
ext = 0x0001 if sc >= 0x100 else 0; sc &= 0xFF
class KI(ctypes.Structure): _fields_ = [("wVk", w.WORD), ("wScan", w.WORD), ("dwFlags", w.DWORD), ("time", w.DWORD), ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong))]
class U(ctypes.Union): _fields_ = [("ki", KI), ("pad", ctypes.c_byte * 32)]
class INPUT(ctypes.Structure): _fields_ = [("type", w.DWORD), ("u", U)]
def send(flags):
    i = INPUT(type=1); i.u.ki = KI(0, sc, 0x0008 | ext | flags, 0, None); ctypes.windll.user32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INPUT))
send(0); time.sleep(hold); send(0x0002)
