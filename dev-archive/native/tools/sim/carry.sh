# carry.sh <from ri id> <to ri id> ...: one pistol's reload stage poses sent again THROUGH the Hand Poser window on each other
# pistol at the same stage (far 19, docked 17, pulled 18, out 16; and without a spare: the hand on the seated magazine, the
# magazine pulled), then one sheet of pictures per gun. CARRY_STAGES="far docked" picks stages; CARRY_SHEET=0 skips the sheet. 2026-11-23.
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; FROM="$1"; shift; G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"
WANT="${CARRY_STAGES:-far docked pull92 out mag magpull92}"
for gun in "$@"; do
  echo "== $gun"; echo "equip $gun" > "$G/reframework/data/finger_rec/command.txt"; sleep 6
  for st in "far|spare in hand, magazine still in the gun" "docked|spare in hand, docked on the magazine" "pull92|spare in hand, pulling the magazine out" "out|two magazines in hand" "mag|ready on magazine" "magpull92|magazine in hand"; do
    case " $WANT " in *" ${st%%|*} "*) ;; *) continue;; esac
    python hold_at.py "${st%%|*}" view=right >/dev/null; python pose.py $(python posefile.py "$FROM" "${st##*|}") | cut -c1-110
  done
  [ "${CARRY_SHEET:-1}" = 1 ] && python stages.py "$gun" "$(cygpath -w "$TEMP/sheets/${gun}_swap.png")" view=right | grep -c "spot"
done
