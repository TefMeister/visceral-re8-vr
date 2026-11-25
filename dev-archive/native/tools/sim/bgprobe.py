"""bgprobe.py - does an RE Engine game keep running when it is NOT the window in front?

  bgprobe.py fg                      print the window in front now
  bgprobe.py give <hwnd>             put that window back in front (the person's own window)
  bgprobe.py state <pid>             is the game's window in front? minimized?
  bgprobe.py fake <pid>              post "you are active" messages to the game window (no focus change)
  bgprobe.py tick <secs>             ask the game (rv.py, no --front) twice <secs> apart: does its frame clock move?
"""
import ctypes, ctypes.wintypes as w, os, subprocess, sys, time

u = ctypes.windll.user32
RV = os.path.expanduser(r"~\github-backups\visceral-re8-vr\dev-archive\native\tools\sim\rv.py")


def game_hwnd(pid):
    found = []

    @ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
    def cb(h, _):
        p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p))
        c = ctypes.create_unicode_buffer(64); u.GetClassNameW(h, c, 64)
        if p.value == pid and c.value == "via" and u.IsWindowVisible(h):
            found.append(h)
        return True
    u.EnumWindows(cb, 0)
    return found[0] if found else None


def title(h):
    b = ctypes.create_unicode_buffer(256); u.GetWindowTextW(h, b, 256); return b.value


def give(h):
    # the usual trick: a zero-length Alt tap lets a background program hand the foreground over
    u.keybd_event(0x12, 0, 0, 0); ok = u.SetForegroundWindow(h); u.keybd_event(0x12, 0, 2, 0)
    time.sleep(0.4)
    return ok and u.GetForegroundWindow() == h


def rv(code):
    r = subprocess.run([sys.executable, RV, code], capture_output=True, text=True, timeout=20)
    return r.stdout.strip()


cmd = sys.argv[1]
if cmd == "fg":
    h = u.GetForegroundWindow(); print(int(h or 0), title(h) if h else "")
elif cmd == "give":
    print("given back" if give(int(sys.argv[2])) else "NOT given back")
elif cmd == "state":
    h = game_hwnd(int(sys.argv[2]))
    if not h: print("no game window"); sys.exit(1)
    print("game hwnd", int(h), "| in front:", u.GetForegroundWindow() == h, "| minimized:", bool(u.IsIconic(h)))
elif cmd == "fake":
    h = game_hwnd(int(sys.argv[2]))
    WM_ACTIVATEAPP, WM_ACTIVATE, WM_NCACTIVATE, WM_SETFOCUS = 0x001C, 0x0006, 0x0086, 0x0007
    u.PostMessageW(h, WM_NCACTIVATE, 1, 0)
    u.PostMessageW(h, WM_ACTIVATEAPP, 1, 0)
    u.PostMessageW(h, WM_ACTIVATE, 1, 0)      # WA_ACTIVE
    u.PostMessageW(h, WM_SETFOCUS, 0, 0)
    print("posted activate messages to", int(h))
elif cmd == "tick":
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 2
    # E persists between questions in zz_visceral_eval.lua; count frames with a callback the first time
    setup = ("if not E.bg_n then E.bg_n = 0; re.on_frame(function() E.bg_n = E.bg_n + 1 end) end; "
             "return E.bg_n")
    a = rv(setup); time.sleep(secs); b = rv("return E.bg_n")
    print("frames:", a, "->", b)
