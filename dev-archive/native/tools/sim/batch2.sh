cd "$(dirname "$0")"
for g in "ri3124" "ri3008" "ri3116" "ri3042 long" "ri3049 long" "ri3125 long" "ri3048 long" "ri3021 long" "ri3036 long" "ri3023 long" "ri3115"; do
  n=${g%% *}; python guncheck.py $g > "$GUNCHECK_OUT/$n.out" 2>&1; echo "done $n"
done
