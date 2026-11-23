# re_pistol.sh <WeaponType> [slide joint=_01] [long]: RE2 / RE3, one magazine gun by robot (the headset on the desk; RV_GAME_DIR and
# HV_HEAD set, keep.py running): equip, the hand onto the seated magazine, B (long: LT) into the hand, down, back in with LT,
# rack; then B with the hand off (it falls), a spare from the pouch to the well, rack. Prints the mod's own lines per step. 2026-11-23.
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; export STEP_TAG="visceral-native"; T="$1"; SL="${2:-_01}"; LONG="$3"
K="magazine:\|rack:\|left hand:\|weapon:\|worked at\|not found\|ammo:"
st() { python step.py "$@" | grep "$K"; }
python keys.py $(cat pid.txt) >/dev/null
python step.py right=0.05,0.03,0.32,90,55 left=-0.25,-0.30,0.30,0,0 squeeze=0 trigger=0 rb=0 rtrigger=0 wait=0.5 >/dev/null
python rv.py "E.want=$T E.fill=nil return 1" >/dev/null; python rv.py -f q_re_equip.lua | cut -c1-60; sleep 5; python keys.py $(cat pid.txt) >/dev/null; st wait=1.0
python rv.py -f q_re_parts.lua | head -1
rack() { python re_go.py $SL | tail -1; st squeeze=1 wait=0.8; python step.py trigger=1 wait=0.6 >/dev/null; python re_move.py -9; st wait=0.6; st trigger=0 squeeze=0 wait=1.0; }
echo "-- 1 the slide / bolt"; rack
if [ -z "$RE_SKIP_HAND" ]; then
echo "-- 2 the hand onto the seated magazine (LG)"; python re_seek.py _04 "the left hand on it" 4 lg
if [ -z "$LONG" ]; then echo "-- 3 right B"; st rb=1 wait=0.4; st rb=0 wait=1.2; else echo "-- 3 LT pulls it"; st trigger=1 wait=0.5; st trigger=0 wait=1.0; fi
echo "-- 4 down 10 cm, then back to the well with LT held"; python re_move.py down 10; st wait=0.8; python step.py trigger=1 wait=0.4 >/dev/null; python re_seek.py _00 "going in" 3; st wait=1.5; st trigger=0 wait=0.3; st squeeze=0 wait=0.8
echo "-- 5 rack"; rack
fi   # RE_SKIP_HAND=1 leaves steps 2 to 5 out
echo "-- 6 out with the hand off (B; long: skipped)"; if [ -z "$LONG" ]; then python step.py left=-0.25,-0.30,0.30,0,0 wait=0.5 >/dev/null; st rb=1 wait=0.4; st rb=0 wait=2.5
echo "-- 7 a spare from the pouch to the well"; python re_go.py pouch >/dev/null; st squeeze=1 wait=1.2; python re_seek.py _00 "going in" 3; st wait=1.5; st squeeze=0 wait=0.8
echo "-- 8 rack"; rack; fi
python step.py left=-0.25,-0.30,0.30,0,0 squeeze=0 trigger=0 wait=0.3 >/dev/null
