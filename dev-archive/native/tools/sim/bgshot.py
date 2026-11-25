"""bgshot.py <pid> <out.png> [class] - a picture of the game's own window WITHOUT bringing it forward
(PrintWindow with PW_RENDERFULLCONTENT: works for DirectX windows behind others; not for a minimized one).
Prints the mean brightness so a black grab is easy to spot."""
import ctypes, ctypes.wintypes as w, sys
from PIL import Image, ImageStat

u = ctypes.windll.user32; g = ctypes.windll.gdi32
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    pass
pid, out = int(sys.argv[1]), sys.argv[2]
cls = sys.argv[3] if len(sys.argv) > 3 else "via"
found = []


@ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
def cb(h, _):
    p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p))
    c = ctypes.create_unicode_buffer(64); u.GetClassNameW(h, c, 64)
    if p.value == pid and (cls == "*" or c.value == cls) and u.IsWindowVisible(h):
        found.append(h)
    return True


u.EnumWindows(cb, 0)
if not found:
    print("no game window"); sys.exit(1)
h = found[0]
if u.IsIconic(h):
    print("window is minimized: nothing to grab"); sys.exit(2)
r = w.RECT(); u.GetClientRect(h, ctypes.byref(r)); W, H = r.right, r.bottom
hdc = u.GetDC(h); mdc = g.CreateCompatibleDC(hdc); bmp = g.CreateCompatibleBitmap(hdc, W, H); g.SelectObject(mdc, bmp)
ok = u.PrintWindow(h, mdc, 1 | 2)   # PW_CLIENTONLY | PW_RENDERFULLCONTENT


class BIH(ctypes.Structure):
    _fields_ = [("biSize", w.DWORD), ("biWidth", w.LONG), ("biHeight", w.LONG), ("biPlanes", w.WORD), ("biBitCount", w.WORD),
                ("biCompression", w.DWORD), ("biSizeImage", w.DWORD), ("biXPelsPerMeter", w.LONG), ("biYPelsPerMeter", w.LONG),
                ("biClrUsed", w.DWORD), ("biClrImportant", w.DWORD)]


bi = BIH(ctypes.sizeof(BIH), W, -H, 1, 32, 0, 0, 0, 0, 0, 0)
buf = ctypes.create_string_buffer(W * H * 4)
g.GetDIBits(mdc, bmp, 0, H, buf, ctypes.byref(bi), 0)
g.DeleteObject(bmp); g.DeleteDC(mdc); u.ReleaseDC(h, hdc)
img = Image.frombuffer("RGB", (W, H), buf, "raw", "BGRX", 0, 1)
img.save(out)
print("printwindow=%d %dx%d brightness=%d -> %s" % (ok, W, H, sum(ImageStat.Stat(img).mean) / 3, out))
