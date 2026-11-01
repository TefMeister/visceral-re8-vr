"""waitchain.py <pid> - what each thread of a hung program waits on (Windows Wait Chain Traversal).
Prints one line per thread whose wait chain is longer than itself, and flags deadlocks (a cycle)."""
import ctypes, ctypes.wintypes as w, sys

advapi = ctypes.WinDLL("advapi32", use_last_error=True)
k32 = ctypes.WinDLL("kernel32", use_last_error=True)

WCT_MAX_NODE_COUNT = 16
WCT_OBJNAME_LENGTH = 128
TYPES = {1: "CriticalSection", 2: "SendMessage", 3: "Mutex", 4: "Alpc", 5: "Com", 6: "ThreadWait",
         7: "ProcessWait", 8: "Thread", 9: "ComActivation", 10: "Unknown", 11: "SocketIo", 12: "SmbIo"}
STATUS = {1: "NoAccess", 2: "Running", 3: "Blocked", 4: "PidOnly", 5: "PidOnlyRpcss", 6: "Owned", 7: "NotOwned",
          8: "Abandoned", 9: "Unknown", 10: "Error"}


class LOCK(ctypes.Structure):
    _fields_ = [("ObjectName", w.WCHAR * WCT_OBJNAME_LENGTH), ("Timeout", ctypes.c_longlong), ("Alertable", w.BOOL)]


class THREAD(ctypes.Structure):
    _fields_ = [("ProcessId", w.DWORD), ("ThreadId", w.DWORD), ("WaitTime", w.DWORD), ("ContextSwitches", w.DWORD)]


class U(ctypes.Union):
    _fields_ = [("LockObject", LOCK), ("ThreadObject", THREAD)]


class NODE(ctypes.Structure):
    _fields_ = [("ObjectType", ctypes.c_int), ("ObjectStatus", ctypes.c_int), ("u", U)]


def threads_of(pid):
    TH32CS_SNAPTHREAD = 4

    class TE(ctypes.Structure):
        _fields_ = [("dwSize", w.DWORD), ("cntUsage", w.DWORD), ("th32ThreadID", w.DWORD),
                    ("th32OwnerProcessID", w.DWORD), ("tpBasePri", w.LONG), ("tpDeltaPri", w.LONG), ("dwFlags", w.DWORD)]
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
    te = TE(); te.dwSize = ctypes.sizeof(TE)
    out = []
    ok = k32.Thread32First(snap, ctypes.byref(te))
    while ok:
        if te.th32OwnerProcessID == pid:
            out.append(te.th32ThreadID)
        ok = k32.Thread32Next(snap, ctypes.byref(te))
    k32.CloseHandle(snap)
    return out


def main():
    pid = int(sys.argv[1])
    advapi.OpenThreadWaitChainSession.restype = ctypes.c_void_p
    sess = advapi.OpenThreadWaitChainSession(0, None)
    if not sess:
        print("OpenThreadWaitChainSession failed", ctypes.get_last_error()); return 1
    shown = 0
    for tid in threads_of(pid):
        nodes = (NODE * WCT_MAX_NODE_COUNT)()
        count = w.DWORD(WCT_MAX_NODE_COUNT)
        cycle = w.BOOL(False)
        if not advapi.GetThreadWaitChain(ctypes.c_void_p(sess), None, 1, tid, ctypes.byref(count), nodes, ctypes.byref(cycle)):
            continue
        parts = []
        for i in range(count.value):
            n = nodes[i]
            t = TYPES.get(n.ObjectType, str(n.ObjectType)); s = STATUS.get(n.ObjectStatus, str(n.ObjectStatus))
            if n.ObjectType == 8:
                th = n.u.ThreadObject
                parts.append(f"thread {th.ThreadId}(pid {th.ProcessId}) {s} wait {th.WaitTime}ms")
            else:
                parts.append(f"{t} {s} '{n.u.LockObject.ObjectName}'")
        if count.value > 1 or cycle.value:
            shown += 1
            print(("DEADLOCK " if cycle.value else "") + " -> ".join(parts))
    print(f"{shown} thread(s) with a wait chain")
    advapi.CloseThreadWaitChainSession(ctypes.c_void_p(sess))


if __name__ == "__main__":
    sys.exit(main() or 0)
