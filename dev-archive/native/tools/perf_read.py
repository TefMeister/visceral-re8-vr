"""perf_read.py -- read one Village launch's performance recording, side by side with the PC's own sensors (2026-11-02).

The mod writes reframework/data/visceral_re8/perf/perf-<date>-<time>.csv (perfprobe.cpp, one line every 2 s); the
LibreHardwareMonitor logger writes temperatures, power and clocks every 2 s (claude-memory MACHINES.md). This puts the
two together and answers, in plain words:
  - how the launch ended: still running, closed, the GAME hung (lines kept coming with no frames), or the WHOLE PC went
    down (lines just stop; then Windows' own crash record from the minutes after is shown),
  - whether it got worse over time: first ten minutes against the last ten (frame rate, stutters, memory, video memory),
  - what everything looked like in the last 30 seconds.

    python perf_read.py                 the newest launch
    python perf_read.py <perf csv>      a given one
    python perf_read.py --list          every recorded launch, newest last
"""
import csv
import datetime as dt
import glob
import os
import subprocess
import sys

GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
PERF_DIR = os.path.join(GAME, "reframework", "data", "visceral_re8", "perf")
LHM_GLOB = os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\LibreHardwareMonitor.LibreHardwareMonitor_*")
WINDOW_S = 600          # "first / last ten minutes"
TAIL_S = 30             # the last seconds shown row by row
HUNG_ROWS = 3           # this many lines in a row with no game frames = the game was stuck
CLOSE_DROP = 0.8        # ...unless its memory fell under this share of where it was: then it was closing
SENSORS = {             # LibreHardwareMonitor ids -> short names
    "/intelcpu/0/temperature/16": "cpu_C", "/intelcpu/0/power/0": "cpu_W", "/intelcpu/0/voltage/0": "cpu_V",
    "/intelcpu/0/load/0": "cpu_load", "/gpu-nvidia/0/temperature/0": "gpu_C", "/gpu-nvidia/0/power/0": "gpu_W",
    "/gpu-nvidia/0/load/0": "gpu_load",
}


def read_perf(path):
    day = os.path.basename(path)[5:15]   # perf-YYYY-MM-DD-HHMMSS.csv
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        rows = [r for r in csv.DictReader(f) if r.get("time")]
    for r in rows:
        r["t"] = dt.datetime.strptime(f"{day} {r['time']}", "%Y-%m-%d %H:%M:%S")
        for k in list(r):
            if k not in ("time", "t"):
                try:
                    r[k] = float(r[k])
                except (TypeError, ValueError):
                    r[k] = None
    return rows


def read_sensors(t0, t1):
    out = {}
    for d in glob.glob(LHM_GLOB):
        for f in glob.glob(os.path.join(d, f"LibreHardwareMonitorLog-{t0:%Y-%m-%d}-*.csv")):
            with open(f, newline="", encoding="utf-8", errors="replace") as fh:
                rows = list(csv.reader(fh))
            if len(rows) < 3:
                continue
            ids = rows[0]
            cols = {SENSORS[i]: n for n, i in enumerate(ids) if i in SENSORS}
            for row in rows[2:]:
                try:
                    t = dt.datetime.strptime(row[0][:19], "%m/%d/%Y %H:%M:%S")
                except ValueError:
                    continue
                if t0 - dt.timedelta(seconds=5) <= t <= t1 + dt.timedelta(seconds=5):
                    out[t] = {k: _f(row[n]) for k, n in cols.items() if n < len(row)}
    return out


def _f(s):
    try:
        return float(s)
    except ValueError:
        return None


def near(sensors, t):
    best = min(sensors, key=lambda k: abs((k - t).total_seconds()), default=None)
    return sensors[best] if best is not None and abs((best - t).total_seconds()) <= 3 else {}


def crash_after(t_end):
    """Windows' own record of an unexpected restart or blue screen within 30 min after the last line."""
    since = t_end.strftime("%Y-%m-%dT%H:%M:%S")
    until = (t_end + dt.timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%S")
    ps = (f"Get-WinEvent -FilterHashtable @{{LogName='System'; Id=41,1001; StartTime='{since}'; EndTime='{until}'}} "
          "-ErrorAction SilentlyContinue | ForEach-Object { $_.TimeCreated.ToString('HH:mm:ss') + ' ' + "
          "(($_.Message -split \"`n\")[0]).Trim() }")
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True, timeout=60)
        return [l for l in r.stdout.splitlines() if l.strip()]
    except (OSError, subprocess.SubprocessError):
        return []


def game_running():
    try:
        r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq re8.exe"], capture_output=True, text=True, timeout=30)
        return "re8.exe" in r.stdout.lower()
    except (OSError, subprocess.SubprocessError):
        return True   # unknown: do not claim a close


def closing(rows, stuck):
    """A normal close also stops the frames (about 12 s on 2026-11-02), but the game lets go of its memory as it goes:
    the last line's video memory or private memory well under what it was when the frames stopped."""
    start, last = rows[-stuck], rows[-1]
    for k in ("vram_mb", "private_mb"):
        a, b = start.get(k), last.get(k)
        if a and b is not None and b < a * CLOSE_DROP:
            return True
    return False


def avg(rows, k):
    v = [r[k] for r in rows if r.get(k) is not None]
    return sum(v) / len(v) if v else None


def fmt(x, unit="", nd=0):
    return "-" if x is None else f"{x:.{nd}f}{unit}"


def main():
    files = sorted(glob.glob(os.path.join(PERF_DIR, "perf-*.csv")))
    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        for f in files:
            print(os.path.basename(f), os.path.getsize(f) // 1024, "KB")
        return
    path = sys.argv[1] if len(sys.argv) > 1 else (files[-1] if files else None)
    if not path:
        print("no recordings yet: the mod writes one per launch (perfprobe.cpp)")
        return
    rows = read_perf(path)
    if len(rows) < 2:
        print(os.path.basename(path), ": fewer than two lines, nothing to read")
        return
    t0, t1 = rows[0]["t"], rows[-1]["t"]
    mins = (t1 - t0).total_seconds() / 60
    print(f"{os.path.basename(path)}: {t0:%H:%M:%S} to {t1:%H:%M:%S}, {mins:.0f} min")

    # how it ended
    stuck = 0
    for r in reversed(rows):
        if (r.get("game_fps") or 0) > 0:
            break
        stuck += 1
    age = (dt.datetime.now() - t1).total_seconds()
    crashes = crash_after(t1)
    if crashes:
        print("ENDED: THE WHOLE PC WENT DOWN. Windows' record after the last line:")
        for c in crashes:
            print("   ", c[:160])
    elif stuck >= HUNG_ROWS and not game_running():
        print(f"ended: the game closed. It drew nothing for its last {stuck * 2} s, which a normal close does too "
              "(about 8-12 s); a freeze that someone then closed by hand would look the same")
    elif stuck >= HUNG_ROWS and closing(rows, stuck):
        print(f"ended: the game closed (it stopped drawing for its last {stuck * 2} s while it let go of its memory, "
              "which is a normal shutdown)")
    elif stuck >= HUNG_ROWS:
        print(f"ENDED: THE GAME WAS STUCK for its last {stuck * 2} s (no frames while the recorder kept writing)")
    elif age < 10:
        print("still running")
    else:
        print("ended: the game closed (no crash on record)")

    # first ten minutes against the last ten
    first = [r for r in rows if (r["t"] - t0).total_seconds() <= WINDOW_S]
    last = [r for r in rows if (t1 - r["t"]).total_seconds() <= WINDOW_S]
    if mins >= 2 * WINDOW_S / 60:
        print(f"\nfirst {WINDOW_S // 60} min -> last {WINDOW_S // 60} min:")
        for k, label, unit in (("present_fps", "frames shown /s", ""), ("present_stutters", "stutters /2 s", ""),
                               ("game_fps", "game updates /s", ""), ("ram_mb", "game memory", " MB"),
                               ("private_mb", "game private memory", " MB"), ("vram_mb", "video memory", " MB"),
                               ("handles", "handles", ""), ("threads", "threads", ""), ("cpu_pct", "game CPU", " %")):
            a, b = avg(first, k), avg(last, k)
            print(f"  {label:22s} {fmt(a, unit, 1):>10s} -> {fmt(b, unit, 1):>10s}")
        hours = mins / 60
        grow = (rows[-1]["private_mb"] - rows[0]["private_mb"]) / hours if hours > 0 else 0
        print(f"  game private memory grew {grow:+.0f} MB an hour over the whole launch")
    else:
        print(f"\n(shorter than {2 * WINDOW_S // 60} min: no first-against-last comparison)")

    # the last seconds, with the PC's sensors beside them
    sensors = read_sensors(t1 - dt.timedelta(seconds=TAIL_S), t1)
    print(f"\nlast {TAIL_S} s (sensors from the temperature logger):")
    print("  time     shown/s stut  game/s  mem MB  vram MB  cpu C  cpu W  cpu V  gpu C  gpu W")
    for r in [r for r in rows if (t1 - r["t"]).total_seconds() <= TAIL_S]:
        s = near(sensors, r["t"])
        print(f"  {r['time']}  {fmt(r['present_fps'], '', 0):>6s} {fmt(r['present_stutters']):>4s} "
              f"{fmt(r['game_fps']):>6s} {fmt(r['private_mb']):>7s} {fmt(r['vram_mb']):>8s} "
              f"{fmt(s.get('cpu_C')):>6s} {fmt(s.get('cpu_W')):>6s} {fmt(s.get('cpu_V'), '', 2):>6s} "
              f"{fmt(s.get('gpu_C')):>6s} {fmt(s.get('gpu_W')):>6s}")


if __name__ == "__main__":
    main()
