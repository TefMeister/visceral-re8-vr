"""check_begin_joints.py <autorun folder> -- guard 1 of 2 against the lift glitch (RE8-078), run by build.sh --deploy (b178).

A joint set at BeginRendering, the last step before the game draws, stops the engine drawing other things anew (Duke frozen on
his lift while his animation runs, moving platforms wrong, guns coming out wrong; measured 2026-11-25). The plugin refuses its own
joint writes there (joints.h drop_on). This names every script that hooks BeginRendering AND touches joints, so a change that sets
one there is seen at install time. It cannot tell a read from a write: the lift test (tools/sim/lifttest.sh, guard 2) is the proof.

Why outside the game: the same scan run inside the plugin, at the first frame, came with the lift test failing 2 of 2 (off: passing
2 of 2), and a live watch hooking via.Joint's setters froze Duke by itself (2026-11-25). Nothing extra runs in the game.
Exit code 0 always: a warning, not a stop.
"""
import os
import re
import sys

KNOWN_READERS = {   # scripts seen at BeginRendering that only READ joints there, or set them only elsewhere (checked 2026-11-25)
    "re8_vr_holster_visuals.lua": "reads joints for the holster markers",
    "visceral_re8_gl_rounds.lua": "moves its own objects; the game's case is shrunk only at the earlier points (b178)",
    "visceral_re8_mag2.lua": "moves its own copy of the magazine",
    "visceral_re8_shell2.lua": "moves its own copy of the shell",
    "re2_vr_grenade.lua": "an RE2 script (it stops itself in Village)",
    "re2_vr_melee.lua": "an RE2 script (it stops itself in Village)",
}
HOOK = re.compile(r"application_entry\s*\(\s*[\"']BeginRendering")
JOINTS = re.compile(r"getJointByName|via\.Joint|get_Joints")

folder = sys.argv[1]
named = []
for name in sorted(os.listdir(folder)):
    if not name.endswith(".lua"):
        continue
    text = open(os.path.join(folder, name), encoding="utf-8", errors="replace").read()
    hooked = any(HOOK.search(line) and not line.lstrip().startswith("--") and "--[[" not in line.split("BeginRendering")[0]
                 for line in text.splitlines())
    if hooked and JOINTS.search(text):
        named.append(name)
new = [n for n in named if n not in KNOWN_READERS]
for n in named:
    print("  begin-joints: %-34s %s" % (n, "known: " + KNOWN_READERS[n] if n in KNOWN_READERS else "NEW: check that it never SETS a joint at BeginRendering"))
print("begin-joints: %d script(s) hook BeginRendering and touch joints, %d not yet checked%s" %
      (len(named), len(new), " -> run the lift test (build.sh --deploy --lift) before wearing" if new else ""))
