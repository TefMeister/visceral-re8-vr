"""shot.py <out.png> [fraction] - a picture of the middle of Village's own window (class 'via'), wherever it is on the desktop.
fraction (default 0.5) = how much of the window's width and height around its centre. Brings the game forward first (it
pauses when it is not in front) and closes REFramework's overlay if it is open (asked through rv.py), so nothing covers the view.
2026-11-11: whole-screen grabs caught the desktop once the window was not full width, and the overlay twice."""
import ctypes, ctypes.wintypes as w, os, subprocess, sys, time
from PIL import ImageGrab

HERE = os.path.dirname(os.path.abspath(__file__))
u = ctypes.windll.user32
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    pass
pid = int(open(os.path.join(HERE, "pid.txt")).read().strip())
found = []
@ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
def cb(h, _):
    p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p)); c = ctypes.create_unicode_buffer(64); u.GetClassNameW(h, c, 64)
    if p.value == pid and c.value == "via" and u.IsWindowVisible(h): found.append(h)
    return True
u.EnumWindows(cb, 0)
if not found:
    print("no game window"); sys.exit(1)
def rv(code):
    return subprocess.run([sys.executable, os.path.join(HERE, "rv.py"), "--front", code], capture_output=True, text=True).stdout.strip()
for attempt in range(3):   # (the first press did not always land: checked again after each)
    if not rv("return reframework:is_drawing_ui()").startswith("true"): break
    subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), str(pid), "insert"], capture_output=True)
    time.sleep(1.0)
    print("overlay was open: Insert pressed (try %d)" % (attempt + 1))
subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), str(pid)], capture_output=True)
time.sleep(0.6)
r = w.RECT(); u.GetClientRect(found[0], ctypes.byref(r))
pt = w.POINT(0, 0); u.ClientToScreen(found[0], ctypes.byref(pt))
frac = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
cw, ch = r.right, r.bottom
x0, y0 = pt.x + cw * (1 - frac) / 2, pt.y + ch * (1 - frac) / 2
ImageGrab.grab(bbox=(int(x0), int(y0), int(x0 + cw * frac), int(y0 + ch * frac))).save(sys.argv[1])
print("window %dx%d, saved the middle %.0f%%" % (cw, ch, frac * 100))
