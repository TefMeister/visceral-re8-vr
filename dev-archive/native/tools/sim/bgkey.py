"""bgkey.py <pid> <key> [<key> ...] - keys sent as window messages (WM_KEYDOWN / WM_KEYUP) to the game's own window:
no real key, no focus change, the window stays where it is (2026-11-25; KNOWN.md "driving it from behind other windows":
REFramework's overlay closes with Insert this way).
Keys: insert, enter, esc, space, up, down, left, right, 0-9, num0-num9, numplus, numminus, a letter, or a hex virtual-key (0x2D).
Optional class as --class=via (default via)."""
import ctypes, ctypes.wintypes as w, sys, time

u = ctypes.windll.user32
VK = {"insert": 0x2D, "enter": 0x0D, "esc": 0x1B, "space": 0x20, "up": 0x26, "down": 0x28, "left": 0x25, "right": 0x27,
      "numplus": 0x6B, "numminus": 0x6D}
VK.update({str(i): 0x30 + i for i in range(10)})
VK.update({"num%d" % i: 0x60 + i for i in range(10)})
EXT = {0x2D, 0x26, 0x28, 0x25, 0x27}
args = [a for a in sys.argv[1:] if not a.startswith("--class=")]
cls = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--class=")), "via")
pid, keys = int(args[0]), args[1:]
found = []


@ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
def cb(h, _):
    p = w.DWORD(); u.GetWindowThreadProcessId(h, ctypes.byref(p))
    c = ctypes.create_unicode_buffer(64); u.GetClassNameW(h, c, 64)
    if p.value == pid and c.value == cls and u.IsWindowVisible(h):
        found.append(h)
    return True


u.EnumWindows(cb, 0)
if not found:
    sys.exit("no visible '%s' window for pid %d" % (cls, pid))
h = found[0]
for k in keys:
    kl = k.lower()
    vk = VK[kl] if kl in VK else (ord(k.upper()) if len(k) == 1 else int(k, 16))
    sc = u.MapVirtualKeyW(vk, 0)
    lp = 1 | (sc << 16) | ((1 << 24) if vk in EXT else 0)
    u.PostMessageW(h, 0x0100, vk, lp); time.sleep(0.08)
    u.PostMessageW(h, 0x0101, vk, lp | (1 << 30) | (1 << 31)); time.sleep(0.4)
    print("sent", k)
