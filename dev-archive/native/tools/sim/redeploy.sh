# redeploy.sh [slot]: close Village (its own window close), install the build that tools/build.sh just made (--deploy builds again,
# same sources), start it again through the desk headset up to the Load Game list. Then LOOK at the slot picture and run enter_real.sh.
S="$(cd "$(dirname "$0")" && pwd)"; python "$S/keep.py" stop
if tasklist | grep -qi re8.exe; then python "$S/close_village.py" | tail -1; n=0; while tasklist | grep -qi re8.exe && [ $n -lt 30 ]; do sleep 2; n=$((n+1)); done; fi
tasklist | grep -qi re8.exe && { echo "Village did not close"; exit 2; }
bash "$S/../build.sh" --deploy 2>&1 | grep -E "error|^deployed" | cut -c1-160
G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"; H="$HOME/github-backups/hand-poser-vr/reframework/autorun/hand_poser.lua"
cmp -s "$H" "$G/reframework/autorun/hand_poser.lua" || { cp "$H" "$G/reframework/autorun/hand_poser.lua"; echo "hand_poser.lua put back (the repo's copy)"; }
bash "$S/drive_real_slot.sh" "${1:-6}" | tail -2
cmp -s "$H" "$G/reframework/autorun/hand_poser.lua" || echo "!! hand_poser.lua in the game is NOT the repo's copy after the launch (it was put back once on 2026-11-23, cause not found)"
