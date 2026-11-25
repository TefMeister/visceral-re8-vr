"""Materials for our GM 79 spent shell and round band (Tefa 2026-11-25): one .mdf2.19 per round type.

  py mdf_build_gm79_shells.py --template <it02_080_grenadelauncher_antique.mdf2.19> --container <it02_000_handgun_01.mdf2.19>
      --bands <shell_bands.json> --out <folder> [--game re8] [--remesh-dir <RE Mesh Editor folder>]

Starts from the launcher's own material (Weapon_Default.mmtr, the game's textures), so the case looks exactly like the
game's case; every file holds three materials named as the meshes name them:
  visceral_gm79_case   the template unchanged (the game's own case paint)
  visceral_gm79_soot   the same textures, BaseColor near black, rough: the scorched inside
  visceral_gm79_band   the same textures (the band's UVs sit on the base rim's bare metal), BaseColor = the round's colour
                       from shell_bands.json, not metal: worn factory paint over the game's scratched steel
Written as gm79_shell_<type>.mdf2.19 for each type the game lists under "<game>.ammo". Texture paths stay the game's (read
from its pak at run time); nothing of the game is copied into the output except the template's settings.
The writer is RE Mesh Editor's (NSACloud); the file is read back and checked before this says OK.
Why a container [measured 2026-11-25]: the writer can not change a file's material COUNT (the launcher's one material
copied to three wrote a file that does not read back; the same fault visceral-re2-vr's bracelets met), and even three
deep copies dropped into a three-material file failed. A three-material Weapon_Default file (the M1911's) rewritten in
place, its materials renamed and given the launcher's texture paths and settings, reads back whole. So the container's
three materials are kept as objects and only their names, texture paths and setting values change.
"""
import argparse, copy, json, os, sys

ap = argparse.ArgumentParser()
ap.add_argument("--template", required=True)
ap.add_argument("--container", required=True)
ap.add_argument("--bands", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--game", default="re8")
ap.add_argument("--remesh-dir", default=os.path.join(os.environ.get("APPDATA", ""), "Blender Foundation", "Blender", "5.3",
                                                     "scripts", "addons", "RE-Mesh-Editor"))
a = ap.parse_args()
sys.path.insert(0, a.remesh_dir)
from modules.mdf import file_re_mdf as M   # noqa: E402

bands = json.load(open(a.bands, encoding="utf-8"))
types = list(bands[a.game]["ammo"].keys())
soot = bands["scorched_inside"]

def fill(m, tmpl, name, base_color=None, roughness=None, metallic=None):
    """Turn the container's material m into ours: the template's textures and settings, then our changes."""
    m.materialName = name
    tt = {t.textureType: t.texturePath for t in tmpl.textureList}
    for t in m.textureList:
        if t.textureType in tt: t.texturePath = tt[t.textureType]
    tp = {p.propName: p.propValue for p in tmpl.propertyList}
    for p in m.propertyList:
        if p.propName in tp: p.propValue = list(tp[p.propName])
        if p.propName == "BaseColor" and base_color is not None: p.propValue = list(base_color) + [1.0]
        elif p.propName == "Roughness" and roughness is not None: p.propValue = [roughness]
        elif p.propName == "Metallic" and metallic is not None: p.propValue = [metallic]

os.makedirs(a.out, exist_ok=True)
bad = 0
for t in types:
    tmpl = M.readMDF(a.template).materialList[0]
    mdf = M.readMDF(a.container)
    if len(mdf.materialList) != 3 or any(m.mmtrPath != tmpl.mmtrPath for m in mdf.materialList):
        raise SystemExit("the container must hold exactly three %s materials" % tmpl.mmtrPath)
    col = bands["colours"][t]["base_color"]
    fill(mdf.materialList[0], tmpl, "visceral_gm79_case")
    fill(mdf.materialList[1], tmpl, "visceral_gm79_soot", soot["base_color"], soot["roughness"], soot["metallic"])
    fill(mdf.materialList[2], tmpl, "visceral_gm79_band", col, 1.0, 0.0)
    out = os.path.join(a.out, "gm79_shell_%s.mdf2.19" % t)
    M.writeMDF(mdf, out)
    back = M.readMDF(out)
    names = [m.materialName for m in back.materialList]
    got = {m.materialName: [p.propValue for p in m.propertyList if p.propName == "BaseColor"][0] for m in back.materialList}
    texs = [len(m.textureList) for m in back.materialList]
    ok = names == ["visceral_gm79_case", "visceral_gm79_soot", "visceral_gm79_band"] and \
        all(abs(x - y) < 1e-4 for x, y in zip(got["visceral_gm79_band"][:3], col)) and \
        all({tx.texturePath for tx in m.textureList} >= {tx.texturePath for tx in tmpl.textureList} for m in back.materialList)
    bad += not ok
    print("%s %s: %d bytes, materials %s, band BaseColor %s, textures %s" % ("OK  " if ok else "BAD ", out, os.path.getsize(out),
          names, [round(v, 3) for v in got.get("visceral_gm79_band", [])], texs))
sys.exit(1 if bad else 0)
