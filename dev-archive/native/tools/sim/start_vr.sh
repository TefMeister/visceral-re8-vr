# start_vr.sh [slot=6]: drive_real_slot.sh with a retry (2026-11-23). Twice in one evening Village came up FLAT right after
# the game before it had closed (the loader: XR_ERROR_FORM_FACTOR_UNAVAILABLE; the desk headset's link was gone while the flat
# game ran and back within seconds of closing it). So: wait for the headset, let it settle, launch, ask the game whether it has
# the headset; if not, close it and try again (three tries). Then LOOK at the slot picture and run enter_real.sh as before.
S="$(cd "$(dirname "$0")" && pwd)"; N="${1:-6}"
for try in 1 2 3; do
  python "$S/headset_up.py" 300 || { echo "HEADSET NOT STREAMING after 5 minutes: nothing launched"; exit 4; }
  sleep 15
  bash "$S/drive_real_slot.sh" "$N" | tail -2
  H=$(python "$S/rv.py" "return tostring(vrmod:is_hmd_active())" 2>/dev/null | tail -1)
  [ "$H" = "true" ] && { echo "in VR (try $try)"; exit 0; }
  echo "STARTED FLAT (try $try): closing it and trying again"
  python "$S/keep.py" stop; python "$S/close_village.py" | tail -1
  n=0; while tasklist | grep -qi re8.exe && [ $n -lt 30 ]; do sleep 2; n=$((n+1)); done; sleep 20
done
echo "STILL FLAT after three tries"; exit 5
