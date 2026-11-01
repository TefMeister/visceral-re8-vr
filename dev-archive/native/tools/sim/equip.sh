# equip.sh <item id>: ask the test script to equip that gun, wait, print the result and the gun
G="/c/Steam/steamapps/common/Resident Evil Village BIOHAZARD VILLAGE"; S="$(cd "$(dirname "$0")" && pwd)"
python "$S/keys.py" $(cat "$S/pid.txt") >/dev/null
echo "{\"id\": $1, \"seq\": $(date +%s%N | cut -c1-13)}" > "$G/reframework/data/visceral_re8/test_equip.json"
sleep 4; python "$S/keys.py" $(cat "$S/pid.txt") >/dev/null
grep -a "test-equip\] $1\|\] weapon: ri" "$G/re2_framework_log.txt" | tail -2 | cut -c60-200
