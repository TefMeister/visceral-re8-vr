import ctypes, ctypes.wintypes as w, sys
u = ctypes.windll.user32
pid = int(sys.argv[1]); close = sys.argv[2] if len(sys.argv) > 2 else None
P = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
def cb(h, l):
    p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p))
    if p.value == pid and u.IsWindowVisible(h):
        t = ctypes.create_unicode_buffer(256); c = ctypes.create_unicode_buffer(256)
        u.GetWindowTextW(h, t, 256); u.GetClassNameW(h, c, 256)
        print(h, "|", t.value, "|", c.value)
        if close and close == c.value:
            u.PostMessageW(h, 0x10, 0, 0); print("  WM_CLOSE sent")
    return True
u.EnumWindows(P(cb), 0)
