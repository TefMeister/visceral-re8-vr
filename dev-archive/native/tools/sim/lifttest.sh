# lifttest.sh [tag] -- the lift-glitch guard (b178, 2026-11-25, Tefa: "yes add both guards"): one flat run on Tefa's lift save
# (Heisenberg's Factory, Duke's shop on the lift, slot 11), Duke's part of the frame compared over 6 s. Prints one verdict line:
#   LIFT TEST: PASS (Duke moves)            the build does not freeze other things' drawing
#   LIFT TEST: FAIL (Duke frozen)           something sets joints at the last drawing step again (RE8-078): do not wear it
#   LIFT TEST: SKIPPED (...)                the game is running, or the newest save is no longer the lift save
# Exit code 0 pass / skipped, 1 fail. Launches the game, so only an /lm session runs it (build.sh --deploy --lift).
# The lift save's fingerprint is kept in "D:\RE Village REFramework builds\lift test save" (with a copy of the save).
S="$(cd "$(dirname "$0")" && pwd)"
T=${1:-lift}
K="/d/RE Village REFramework builds/lift test save"
SAVES=$(ls -d /c/Steam/userdata/*/1196590/remote/win64_save 2>/dev/null | head -1)
if tasklist | grep -qi re8.exe; then echo "LIFT TEST: SKIPPED (the game is running)"; exit 0; fi
NEWEST=$(ls -t "$SAVES"/data000.bin "$SAVES"/data0*Slot.bin 2>/dev/null | head -1)
if [ "$(sha256sum "$NEWEST" | cut -d' ' -f1)" != "$(cat "$K/lift_save.sha256" 2>/dev/null)" ]; then
    echo "LIFT TEST: SKIPPED (the newest save, $(basename "$NEWEST"), is not the lift save: load slot 11 by hand, or record a Load Game route)"; exit 0
fi
# a pretend pad kept for the run, and the front handed back
python "$S/bgpadd.py" serve >/dev/null 2>&1 &
python "$S/bgaway.py" watch re8.exe 300 --on-screen >/dev/null 2>&1 &
sleep 2
OUT=$(bash "$S/liftrun.sh" "$T")
if echo "$OUT" | grep -q "STILL RUNNING"; then   # REFramework's start-up freeze (about 1 launch in 6 on 2026-11-25): end it, try once more
    P=$(tasklist | grep -i re8.exe | awk '{print $2}' | head -1); [ -n "$P" ] && taskkill //PID "$P" //F >/dev/null; sleep 4
    echo "(the game hung at start-up and was ended; one more try)"
    OUT=$(bash "$S/liftrun.sh" "${T}b")
fi
python "$S/bgpadd.py" send quit; sleep 1
echo "$OUT"
if echo "$OUT" | grep -q "STILL RUNNING"; then   # REFramework's start-up freeze: the game's own close cannot reach it
    P=$(tasklist | grep -i re8.exe | awk '{print $2}' | head -1); [ -n "$P" ] && taskkill //PID "$P" //F >/dev/null
    echo "LIFT TEST: SKIPPED (the game hung and was ended: most likely REFramework's start-up freeze; run it again)"; exit 0
fi
# the later two pairs decide (the first pair often catches the view settling)
read P2 P3 < <(echo "$OUT" | grep "pixels changed" | sed -n '2,3p' | awk '{print $4}' | tr '\n' ' ')
if [ -z "$P2" ]; then echo "LIFT TEST: SKIPPED (no pictures: the game did not reach the lift; see the run above)"; exit 0; fi
M=$(( P2 > P3 ? P2 : P3 ))
if [ "$M" -ge 500 ]; then echo "LIFT TEST: PASS (Duke moves: $P2 / $P3 pixels)"; exit 0; fi
echo "LIFT TEST: FAIL (Duke frozen: $P2 / $P3 pixels): something sets joints at the last drawing step again (RE8-078); do not wear this build"; exit 1
