# pass360.sh <ri id> <long|short> <views> <zone> [zone ...]: the 360 view for the robot, one gun: for each grip zone named, the left
# hand taken onto it with LG and pictured from the views given (e.g. right,bottom,front); one row per zone, one sheet
# (%TEMP%/sheets/pass_<gun>.jpg). A zone written zone:lt is held with LG + LT. Needs keep.py, HV_HEAD, the jacket off.
S="$(cd "$(dirname "$0")" && pwd)"; cd "$S"; g="$1"; L="$2"; V="$3"; shift 3; [ "$L" = long ] || L=""
F=""; for z in "$@"; do lt=""; case "$z" in *:lt) lt=lt; z="${z%:lt}";; esac
  python turntable.py "$g" "$z" "$(cygpath -w "$TEMP/sheets/_p_${g}_$z$lt.png")" $lt $L views=$V | cut -c1-100; [ -f "$TEMP/sheets/_p_${g}_$z$lt.png" ] && F="$F $TEMP/sheets/_p_${g}_$z$lt.png"; done
python - $F <<'PY'
import sys, os
from PIL import Image
ims=[Image.open(f).convert("RGB") for f in sys.argv[1:]]
if ims:
    w=max(i.size[0] for i in ims); s=Image.new("RGB",(w,sum(i.size[1] for i in ims))); y=0
    for i in ims: s.paste(i,(0,y)); y+=i.size[1]
    k=min(1.0,1900.0/w); s=s.resize((int(w*k),int(s.size[1]*k)),Image.LANCZOS)
    out=os.path.join(os.path.dirname(sys.argv[1]),"pass_"+os.path.basename(sys.argv[1]).split("_")[2]+".jpg"); s.save(out,quality=82); print(out.replace(os.path.expanduser("~"),"~"), s.size)
PY
