# carry.sh <from ri id> <to ri id> ...: the spare-swap stage poses of one pistol sent again THROUGH the Hand Poser window on each
# other pistol at the same stage (far 19, docked 17, pulled 18, out 16), then one sheet of pictures per gun. 2026-11-23.
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; FROM="$1"; shift; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
for gun in "$@"; do
  echo "== $gun"; echo "equip $gun" > "$G/reframework/data/finger_rec/command.txt"; sleep 6
  for st in "far|spare in hand, magazine still in the gun" "docked|spare in hand, docked on the magazine" "pull92|spare in hand, pulling the magazine out" "out|two magazines in hand"; do
    python hold_at.py "${st%%|*}" view=right >/dev/null; python pose.py $(python posefile.py "$FROM" "${st##*|}") | cut -c1-110
  done
  python stages.py "$gun" "$(cygpath -w "$TEMP/sheets/${gun}_swap.png")" view=right | grep -c "spot" 
done
