# viewtest.sh <out sheet> <right pose> [...]: the spare docked under the seated magazine, pictured for each right-hand pose (hv numbers)
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; OUT="$1"; shift; i=0; F=""
for R in "$@"; do i=$((i+1))
python step.py right=$R left=-0.25,-0.30,0.30,0,0 squeeze=0 trigger=0 wait=1.0 >/dev/null; python walk.py mag >/dev/null; A=$(python -c "import json;print(','.join(str(v) for v in json.load(open('pose_now.json'))['left']))")
python step.py left=-0.20,-0.62,0.02,0,0 wait=0.9 >/dev/null; python step.py squeeze=1 wait=0.9 >/dev/null; python step.py raw:left=$A wait=1.5 pic=$(cygpath -w $TEMP/vt$i.png) | tail -1 | cut -c1-40; python step.py squeeze=0 wait=0.8 >/dev/null; F="$F $(cygpath -w $TEMP/vt$i.png)"; done
python sheet.py "$OUT" 2 $F
