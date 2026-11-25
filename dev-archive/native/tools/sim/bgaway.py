"""bgaway.py - keep a game window out of sight without minimizing it (minimized windows stop drawing).

  bgaway.py away <pid> [class]      move the game's window past the left edge of all screens, no focus change
  bgaway.py back <pid> [class]      bring it back on screen (top-left of the main screen), still no focus change
  bgaway.py watch <pid|exe> [secs] [--on-screen]  from launch: every 20 ms, any new visible window of that program is moved away at once
                                    (--on-screen, 2026-11-25, Tefa: "i do prefer if you have the games running on the screen, so i can
                                    see what you are doing, i just need to be able to use the pc at the same time": the window stays
                                    where it is, only the front is handed back to the person's window whenever the game takes it)
                                    (give the exe name, e.g. re3.exe, to start watching before the process exists)
"""
import ctypes, ctypes.wintypes as w, subprocess, sys, time

u = ctypes.windll.user32
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    pass
SWP_NOSIZE, SWP_NOZORDER, SWP_NOACTIVATE, SWP_NOOWNERZORDER = 0x1, 0x4, 0x10, 0x200
SWP_ASYNC = 0x4000   # 2026-11-25: never wait on the game's window thread (a hung game froze `back`)
HWND_BOTTOM = 1


def windows_of(pid, cls=None):
    out = []

    @ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
    def cb(h, _):
        p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p))
        if p.value == pid and u.IsWindowVisible(h):
            if cls:
                c = ctypes.create_unicode_buffer(64); u.GetClassNameW(h, c, 64)
                if c.value != cls:
                    return True
            out.append(h)
        return True
    u.EnumWindows(cb, 0)
    return out


def away_x(h):
    r = w.RECT(); u.GetWindowRect(h, ctypes.byref(r))
    left = u.GetSystemMetrics(76)            # SM_XVIRTUALSCREEN: the left edge of all screens together
    return left - (r.right - r.left) - 200, r


def move_away(h):
    x, r = away_x(h)
    if r.left <= x:
        return False
    u.SetWindowPos(h, HWND_BOTTOM, x, r.top, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNC)
    return True


def pid_of(exe):
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + exe, "/FO", "CSV", "/NH"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) > 1 and parts[0].lower() == exe.lower():
            return int(parts[1])
    return None


cmd = sys.argv[1]
if cmd in ("away", "back"):
    pid = int(sys.argv[2]); cls = sys.argv[3] if len(sys.argv) > 3 else None
    for h in windows_of(pid, cls):
        if cmd == "away":
            print("moved away" if move_away(h) else "already away", int(h))
        else:
            r = w.RECT(); u.GetWindowRect(h, ctypes.byref(r))
            u.SetWindowPos(h, HWND_BOTTOM, 40, 40, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNC); print("back", int(h))
elif cmd == "watch":
    on_screen = '--on-screen' in sys.argv
    rest = [a for a in sys.argv if a != '--on-screen']
    target = rest[2]; secs = float(rest[3]) if len(rest) > 3 else 180
    t0 = time.time(); pid = int(target) if target.isdigit() else None; moved = set(); last_lookup = 0
    owner = u.GetForegroundWindow()          # the person's window: it gets the front back whenever the game takes it
    given = 0
    while time.time() - t0 < secs:
        if pid is None and time.time() - last_lookup > 0.25:
            pid = pid_of(target); last_lookup = time.time()
        if pid:
            mine = windows_of(pid)
            for h in mine:
                if not on_screen and move_away(h) and int(h) not in moved:
                    moved.add(int(h)); print("%.2f s: window %d moved away" % (time.time() - t0, int(h)), flush=True)
            fg = u.GetForegroundWindow()
            p = w.DWORD(); u.GetWindowThreadProcessId(fg, ctypes.byref(p))
            if fg and p.value == pid and owner and u.IsWindow(owner):
                u.keybd_event(0x12, 0, 0, 0); u.SetForegroundWindow(owner); u.keybd_event(0x12, 0, 2, 0)
                given += 1; print("%.2f s: the game took the front; given back" % (time.time() - t0), flush=True)
        time.sleep(0.02)
    print("watch ended; windows moved:", len(moved), "| front given back:", given)
