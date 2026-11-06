"""keys.py <pid> <key> [<key> ...] - bring the game's 'via' window forward and tap keys by scancode (0.15 s held, 0.6 s apart)."""
import ctypes, ctypes.wintypes as w, sys, time
u = ctypes.windll.user32
SC = {"up": (0x48, True), "down": (0x50, True), "left": (0x4B, True), "right": (0x4D, True), "enter": (0x1C, False),
      "f": (0x21, False), "esc": (0x01, False), "insert": (0x52, True), "space": (0x39, False), "x": (0x2D, False), "1": (0x02, False), "2": (0x03, False), "3": (0x04, False), "4": (0x05, False), "5": (0x06, False), "6": (0x07, False),
      # the numpad (2026-11-06): the scope plugin's hotkeys; without the extended flag these scancodes are the NUMPAD keys, not the arrows
      "num+": (0x4E, False), "num-": (0x4A, False), "num*": (0x37, False), "num/": (0x35, True), "num.": (0x53, False),
      "num0": (0x52, False), "num2": (0x50, False), "num4": (0x4B, False), "num5": (0x4C, False), "num6": (0x4D, False), "num8": (0x48, False), "num9": (0x49, False)}
class KI(ctypes.Structure): _fields_ = [("wVk", w.WORD), ("wScan", w.WORD), ("dwFlags", w.DWORD), ("time", w.DWORD), ("dwExtraInfo", ctypes.c_size_t)]
class MI(ctypes.Structure): _fields_ = [("dx", w.LONG), ("dy", w.LONG), ("mouseData", w.DWORD), ("dwFlags", w.DWORD), ("time", w.DWORD), ("dwExtraInfo", ctypes.c_size_t)]
class U(ctypes.Union): _fields_ = [("ki", KI), ("mi", MI)]
class INP(ctypes.Structure): _fields_ = [("type", w.DWORD), ("u", U)]
def send(sc, ext, up):
    f = 0x0008 | (0x0001 if ext else 0) | (0x0002 if up else 0)
    i = INP(1, U(ki=KI(0, sc, f, 0, 0))); u.SendInput(1, ctypes.byref(i), ctypes.sizeof(INP))
pid = int(sys.argv[1]); target = []
P = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
def cb(h, l):
    p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p)); c = ctypes.create_unicode_buffer(64); u.GetClassNameW(h, c, 64)
    if p.value == pid and c.value == "via" and u.IsWindowVisible(h): target.append(h)
    return True
u.EnumWindows(P(cb), 0)
if not target: print("no game window"); sys.exit(1)
u.keybd_event(0x12, 0, 0, 0); u.SetForegroundWindow(target[0]); u.keybd_event(0x12, 0, 2, 0); time.sleep(0.5)
print("foreground ok" if u.GetForegroundWindow() == target[0] else "foreground NOT taken")
for k in sys.argv[2:]:
    sc, ext = SC[k]; send(sc, ext, False); time.sleep(0.15); send(sc, ext, True); time.sleep(0.6)
print("sent", sys.argv[2:])
