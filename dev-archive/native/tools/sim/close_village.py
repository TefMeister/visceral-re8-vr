import ctypes, ctypes.wintypes as W
u=ctypes.windll.user32; found=[]
@ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
def cb(h,_):
    if u.IsWindowVisible(h):
        n=ctypes.create_unicode_buffer(256); u.GetWindowTextW(h,n,256)
        c=ctypes.create_unicode_buffer(64); u.GetClassNameW(h,c,64)
        if "VILLAGE" in n.value.upper() and c.value=="via": found.append(h)
    return True
u.EnumWindows(cb,0)
for h in found[:1]: u.PostMessageW(h,0x0010,0,0); print("Village asked to close")
