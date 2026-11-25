# stormrun.sh <tag>: Village flat, on screen, the latest save loaded, LEFT RUNNING (for the request-storm test, RE8-080).
# The same start as liftrun.sh; it does not close the game. Needs nothing running; starts the kept pad and the
# window-away watcher itself. Prints "READY <pid>" or "NOT READY". Only an /lm session runs it.
S="$(cd "$(dirname "$0")" && pwd)"
SP=${SP:-$S/out}; mkdir -p "$SP"
G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
T=${1:-storm}
if tasklist | grep -qi re8.exe; then echo "NOT READY (the game is already running)"; exit 1; fi
python "$S/bgpadd.py" serve >/dev/null 2>&1 &
python "$S/bgaway.py" watch re8.exe 300 --on-screen >/dev/null 2>&1 &
sleep 2
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; \$env:XR_RUNTIME_JSON='C:\no-such-runtime.json'; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 50
P=$(tasklist | grep -i "re8.exe" | awk '{print $2}' | head -1); echo $P > "$S/pid.txt"
echo "pid $P susp $(grep -a -c Suspending "$G/re2_framework_log.txt")/$(grep -a -c Resuming "$G/re2_framework_log.txt")"
python "$S/bgkey.py" $P insert >/dev/null; sleep 1
python "$S/bgpadd.py" send a; sleep 3; python "$S/bgpadd.py" send a; sleep 2; python "$S/bgpadd.py" send up; sleep 1.5
python "$S/bgpadd.py" send a; sleep 42; python "$S/bgpadd.py" send a; sleep 7
timeout 20 python "$S/bgshot.py" $P "$SP/${T}_in.png" >/dev/null
A=$(python "$S/rv.py" "return 1+1" 2>&1)
if [ "$A" = "2" ]; then echo "READY $P"; else echo "NOT READY (the question line says: $A)"; fi
