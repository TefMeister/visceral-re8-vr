"""close_re.py [pid] -- close RE2 / RE3 (or any RE Engine game) by its OWN window close: WM_CLOSE posted to the visible `via` window of
that process (default: the pid in pid.txt), as close_village.py does for Village (2026-11-23). Never a force-kill."""
import ctypes, ctypes.wintypes as W, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
pid = int(sys.argv[1]) if len(sys.argv) > 1 else int(open(os.path.join(HERE, "pid.txt")).read().strip())
u = ctypes.windll.user32; found = []
@ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
def cb(h, _):
    if u.IsWindowVisible(h):
        c = ctypes.create_unicode_buffer(64); u.GetClassNameW(h, c, 64)
        p = W.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p))
        if c.value == "via" and p.value == pid: found.append(h)
    return True
u.EnumWindows(cb, 0)
for h in found[:1]: u.PostMessageW(h, 0x0010, 0, 0); print("pid %d asked to close" % pid)
if not found: print("no visible via window for pid %d" % pid)
