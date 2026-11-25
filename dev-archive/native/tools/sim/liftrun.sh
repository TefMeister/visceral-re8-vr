# liftrun.sh <tag>: one lift test run, flat, on screen: launch, overlay off, the kept pad loads the latest save, five pictures
# of Duke 1.5 s apart, the pixel change in his part of the frame, then the game's own close. Needs bgpadd.py serve running.
S=~/github-backups/visceral-re8-vr/dev-archive/native/tools/sim
SP=${SP:-$(cd "$(dirname "$0")" && pwd)/out}; mkdir -p $SP
G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
T=$1
powershell -NoProfile -Command "\$env:SteamAppId='1196590'; \$env:XR_RUNTIME_JSON='C:\no-such-runtime.json'; Start-Process -FilePath '$(cygpath -w "$G")\re8.exe' -WorkingDirectory '$(cygpath -w "$G")'"
sleep 50
P=$(tasklist | grep -i "re8.exe" | awk '{print $2}' | head -1); echo $P > $S/pid.txt
echo "pid $P susp $(grep -a -c Suspending "$G/re2_framework_log.txt")/$(grep -a -c Resuming "$G/re2_framework_log.txt")"
python $S/bgkey.py $P insert >/dev/null; sleep 1
python $S/bgpadd.py send a; sleep 3; python $S/bgpadd.py send a; sleep 2; python $S/bgpadd.py send up; sleep 1.5
timeout 20 python $S/bgshot.py $P $SP/${T}_q.png >/dev/null
python $S/bgpadd.py send a; sleep 42; python $S/bgpadd.py send a; sleep 7
for i in 1 2 3 4 5; do timeout 20 python $S/bgshot.py $P $SP/${T}$i.png >/dev/null; sleep 1.5; done
cd $SP && python -W ignore $S/regiondiff.py 0 0 280 350 ${T}1.png ${T}3.png ${T}2.png ${T}4.png ${T}1.png ${T}5.png
cp "$G/re2_framework_log.txt" "$G/re2_framework_log.2026-11-25-lift-ab-$T.txt"
python $S/close_village.py >/dev/null; for i in $(seq 1 25); do tasklist | grep -qi re8.exe || break; sleep 2; done
tasklist | grep -qi re8.exe && echo "STILL RUNNING" || echo closed
