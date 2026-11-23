# gm79_latch.sh: Village's GM 79 by robot (b152, Tefa's design of 2026-11-23): the latch refused shut, right B (the thumb's flick),
# the barrel moved by the left hand with LG + LT and let go half way (it falls open), shut by hand (the latch shuts with it),
# B and a flick down, a flick up. Needs the save loaded, keep.py, HV_HEAD. Prints the mod's lines per step.
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
echo "equip ri3023" > "$G/reframework/data/finger_rec/command.txt"; sleep 7; python keys.py $(cat pid.txt)>/dev/null
FG="left=0.30,0.24,0.81,0,60"   # (the front grip spot kept on 2026-11-23 morning; re-kept from below that evening: use frame.py grip and the zone instead)
PK="left=-0.25,-0.30,0.30,0,0"; K="breech:\|hands:\|pairs:.*insert"
st() { python step.py "$@" | grep "$K"; }
python step.py right=0.30,0.0,0.70,90,90 $PK squeeze=0 trigger=0 rtrigger=0 rb=0 wait=1.2 >/dev/null
echo "--- 1 LG+LT at the front grip, latch shut"; python step.py $FG wait=0.8 >/dev/null; st squeeze=1 wait=0.8; st trigger=1 wait=0.5; st trigger=0 squeeze=0 wait=0.5
echo "--- 2 right B"; st rb=1 wait=0.3; st rb=0 wait=0.8
echo "--- 3 front grip LG, LT, hand 6 cm down, let go"; python step.py $FG wait=0.8 >/dev/null; st squeeze=1 wait=0.8; st trigger=1 wait=0.5; python step.py left=0.30,0.21,0.81,0,60 wait=0.2 >/dev/null; python step.py left=0.30,0.18,0.81,0,60 wait=0.4 >/dev/null; st squeeze=0 trigger=0 wait=1.2
echo "--- 4 shut by hand: LG+LT at the open barrel, 14 cm up"; python step.py left=0.30,0.12,0.81,0,60 wait=0.8 >/dev/null; st squeeze=1 wait=0.8; st trigger=1 wait=0.5; for u in 0.15 0.18 0.21 0.24 0.27; do python step.py left=0.30,$u,0.81,0,60 wait=0.15 >/dev/null; done; st wait=0.5; st squeeze=0 trigger=0 wait=1.0; python step.py $PK wait=0.4 >/dev/null
echo "--- 5 B, then a flick down"; st rb=1 wait=0.3; st rb=0 wait=0.8; python step.py right=0.30,0.0,0.70,90,50 wait=0.5 | grep "$K"; for p in 58 66 74 82 90; do python step.py right=0.30,0.0,0.70,90,$p wait=0.25 >/dev/null; done; st wait=0.8
echo "--- 6 a flick up"; for p in 82 74 66 58 50; do python step.py right=0.30,0.0,0.70,90,$p wait=0.25 >/dev/null; done; sleep 0.6; python step.py right=0.30,0.0,0.70,90,90 wait=0.8 | grep "$K"
