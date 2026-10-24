"""gun_listen.py - flat, nobody at the PC: while visceral_re8_gun_cycle.lua puts each gun in hand, make it fire once and
reload once through the virtual pad (re-village-scope-vr/dev-archive/tools/re8pad.py serve must be running), so
visceral_re8_sounds.lua hears and learns each gun's own after-shot and reload sounds by name.

    python gun_listen.py [timeout_s]

It follows the game log: on every "[visceral-re8-cycle] gun K of N" line it queues, for that gun: wait for the swap and
any reload of an empty gun, one hip shot (RT), wait for the after-shot motion, then X (reload). It stops at "cycle done".
2026-10-24 (Tefa: "can you do all the other guns in the game as well, or do you need me to equip them one by one?").
"""
import os, re, sys, time

GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
LOG = os.path.join(GAME, "re2_framework_log.txt")
PAD_CMD = os.path.expanduser(r"~\github-backups\re-village-scope-vr\dev-archive\tools\re8pad_cmd.txt")
# per gun, in milliseconds: let the swap (and an empty gun's own reload) finish, fire, let the pump / bolt play, reload
STEPS = "wait 4500\nrt 200\nwait 3000\ntap x\n"

def main():
    timeout = float(sys.argv[1]) if len(sys.argv) > 1 else 900
    f = open(LOG, "r", encoding="utf-8", errors="replace")
    f.seek(0, os.SEEK_END)
    t0, n = time.time(), 0
    while time.time() - t0 < timeout:
        line = f.readline()
        if not line:
            time.sleep(0.2)
            continue
        m = re.search(r"\[visceral-re8-cycle\] gun (\d+) of (\d+)", line)
        if m:
            with open(PAD_CMD, "a") as p:
                p.write(STEPS)
            n += 1
            print("gun %s of %s: fire + reload queued" % (m.group(1), m.group(2)), flush=True)
        if "[visceral-re8-cycle] cycle done" in line:
            print("cycle done, %d gun(s) driven" % n, flush=True)
            return
    print("timed out after %d gun(s)" % n, flush=True)

if __name__ == "__main__":
    main()
