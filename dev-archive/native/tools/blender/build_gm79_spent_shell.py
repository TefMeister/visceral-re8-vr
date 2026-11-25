"""GM 79 spent shell and round band: our own models, built from the game's own case (Tefa 2026-11-25).

Tefa: "can you copy the shell from the game in blender and have it actually look spent so it's just a shell without the
live front part, and use that in game? ... a coloured band over different ammo types". Agreed over five renders the same
afternoon: the game's own case, scorched dark inside; the groove at its base filled by a flush, worn paint band with a
narrow groove left on each side; nothing in the middle of the shell.

Run (Blender 5.3, RE Mesh Editor enabled):
  blender -b -noaudio --python build_gm79_spent_shell.py -- <launcher .mesh.2101050001> <out folder> [--preview <png>]

The launcher mesh (it02_080_grenadelauncher_antique) is the game's: it is read from the extracted pak folder and never
committed. Its part 9 (RE Mesh Editor "Group_9") is the empty case, weighted to the Ammo01 joint; parts 6 / 7 / 8 are the
three warhead fronts. Writes into <out>:
  gm79_spent_shell.mesh.2101050001   three submeshes: visceral_gm79_case (the case outside), visceral_gm79_soot (inside),
                                     visceral_gm79_band (the band)
  gm79_round_band.mesh.2101050001    the band alone, for the live rounds (drawn on the gun's own Ammo01 joint)
  gm79_spent_shell.blend             the parts, for looking at
Both meshes are in the Ammo01 joint's LOCAL bind frame, so the runtime only has to give our object that joint's pose
(the conversion is visceral-re2-vr's build_bracelets.py export_re_mesh, [verified-numerically 2026-09-06] there).
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PREVIEW = args[args.index("--preview") + 1] if "--preview" in args else None
os.makedirs(OUT, exist_ok=True)

# ---- measured on the game's case (gun space, Blender axes; 2026-11-25)
CX, CZ = 0.0001, 0.0229                  # the case's axis
Y_MOUTH, Y_BODY_BACK, Y_FLOOR = -0.1304, -0.0863, -0.1043
Y_RIM_FRONT = -0.0823                    # the groove runs from the body's back edge to the base rim
GROOVE_GAP = 0.0005                      # Tefa: "a narrow groove on both sides of the coloured band"
BAND_R_IN = 0.0178                       # below the groove's floor (r 0.0180), so the band fills it
CASE_PART, JOINT = "Group_9_Sub_0", "Ammo01"
MAT_CASE, MAT_SOOT, MAT_BAND = "visceral_gm79_case", "visceral_gm79_soot", "visceral_gm79_band"

import addon_utils
addon_utils.enable("RE-Mesh-Editor", default_set=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
r = bpy.ops.re_mesh.importfile(filepath=SRC, directory=os.path.dirname(SRC), files=[{"name": os.path.basename(SRC)}],
                               clearScene=False, loadMaterials=False, loadMDFData=False)
print("IMPORT", r)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
src = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith(CASE_PART))
print("case part:", src.name, "verts", len(src.data.vertices), "| armature", arm.name, "| joint", JOINT, JOINT in arm.data.bones)

work = bpy.data.collections.new("gm79_parts"); bpy.context.scene.collection.children.link(work)

# ---- 1. the case, split into outside and inside (the inside gets the soot)
me = src.data.copy()
me.transform(src.matrix_world)
bm = bmesh.new(); bm.from_mesh(me)
inner = []
for f in bm.faces:
    c = f.calc_center_median(); n = f.normal
    rad = Vector((c.x - CX, 0, c.z - CZ)); rr = rad.length
    wall = rr > 1e-5 and n.dot(rad.normalized()) < -0.3 and Y_MOUTH - 1e-4 <= c.y <= Y_FLOOR + 0.001
    floor = n.y < -0.7 and c.y > Y_MOUTH + 0.001 and c.y <= Y_FLOOR + 0.001 and rr < 0.0186
    if wall or floor:
        inner.append(f)
inner_idx = set(f.index for f in inner)
me_in = me.copy()
bm2 = bmesh.new(); bm2.from_mesh(me_in)
bm2.faces.ensure_lookup_table()
bmesh.ops.delete(bm2, geom=[f for f in bm2.faces if f.index not in inner_idx], context="FACES")
bm2.to_mesh(me_in); bm2.free()
bmesh.ops.delete(bm, geom=inner, context="FACES")
bm.to_mesh(me); bm.free()
print("case: %d faces outside, %d inside" % (len(me.polygons), len(me_in.polygons)))

# the band's UVs sample the base rim's bare metal (the case's own UVs there), so the game's metal texture, tinted, is the
# worn paint: every scratch in it shows through the colour
rim_uv = {}
for p in me.polygons:
    vy = [me.vertices[me.loops[li].vertex_index].co.y for li in p.loop_indices]
    if min(vy) >= Y_RIM_FRONT - 2e-4 and max(vy) <= -0.0813 + 2e-4:
        for li in p.loop_indices:
            for lay in me.uv_layers:
                rim_uv.setdefault(lay.name, []).append(tuple(lay.data[li].uv))
uv_box = {n: (min(u for u, v in l), max(u for u, v in l), min(v for u, v in l), max(v for u, v in l)) for n, l in rim_uv.items()}
print("rim UV boxes:", {n: tuple(round(x, 4) for x in b) for n, b in uv_box.items()})

# ---- 2. the band: flush with the body (its 24 sides and radii), filling the groove, a narrow groove left each side
body = {}
for v in me.vertices:
    if abs(v.co.y - Y_BODY_BACK) < 2e-4:
        a = math.atan2(v.co.z - CZ, v.co.x - CX)
        body[round(math.degrees(a), 1)] = (a, math.hypot(v.co.x - CX, v.co.z - CZ))
angles = sorted(body.values())
y0, y1 = Y_BODY_BACK + GROOVE_GAP, Y_RIM_FRONT - GROOVE_GAP

def band_mesh(name):
    bm = bmesh.new()
    def ring(y, outer):
        return [bm.verts.new((CX + (rr if outer else BAND_R_IN) * math.cos(a), y, CZ + (rr if outer else BAND_R_IN) * math.sin(a)))
                for a, rr in angles]
    o0, o1 = ring(y0, True), ring(y1, True)
    c0o, c0i, c1o, c1i = ring(y0, True), ring(y0, False), ring(y1, True), ring(y1, False)
    i0, i1 = ring(y0, False), ring(y1, False)
    N = len(angles); smooth = []
    for i in range(N):
        j = (i + 1) % N
        smooth.append(bm.faces.new((o0[i], o0[j], o1[j], o1[i])))
        bm.faces.new((c0o[i], c0i[i], c0i[j], c0o[j]))
        bm.faces.new((c1o[i], c1o[j], c1i[j], c1i[i]))
        bm.faces.new((i0[i], i1[i], i1[j], i0[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = f in smooth
    for n, (u0, u1, v0, v1) in uv_box.items():
        lay = bm.loops.layers.uv.new(n)
        for f in bm.faces:
            for l in f.loops:
                co = l.vert.co
                t = (math.atan2(co.z - CZ, co.x - CX) / (2 * math.pi)) % 1.0
                s = (co.y - y0) / (y1 - y0)
                l[lay].uv = (u0 + (u1 - u0) * t, v0 + (v1 - v0) * s)
    m = bpy.data.meshes.new(name); bm.to_mesh(m); bm.free()
    return m

parts = {MAT_CASE: me, MAT_SOOT: me_in, MAT_BAND: band_mesh("band")}
for mat, m in parts.items():
    m.materials.clear(); m.materials.append(bpy.data.materials.get(mat) or bpy.data.materials.new(mat))
    o = bpy.data.objects.new(mat, m); work.objects.link(o)
print("band: y %.4f..%.4f, %d sides, r_in %.4f" % (y0, y1, len(angles), BAND_R_IN))

# ---- 3. into the Ammo01 joint's local bind frame, and out as Village meshes
b = arm.data.bones[JOINT]
Mb = arm.matrix_world @ b.matrix_local
def to_re(v): return (v[0], v[2], -v[1])
rows = [to_re((Mb[0][c], Mb[1][c], Mb[2][c])) for c in range(3)]
T = to_re((Mb[0][3], Mb[1][3], Mb[2][3]))
def to_local_blender(p):
    w = to_re(p); d = (w[0] - T[0], w[1] - T[1], w[2] - T[2])
    l = [sum(d[j] * rows[i][j] for j in range(3)) for i in range(3)]
    return (l[0], -l[2], l[1])
print("Ammo01 bind T (RE) = (%.4f, %.4f, %.4f)" % T)

def export(name, mats):
    # mats: material names (their mesh from `parts`), or (material, mesh) pairs (b176: the live rounds' warhead submesh)
    coll = bpy.data.collections.new(name + ".mesh"); bpy.context.scene.collection.children.link(coll)
    coll["~TYPE"] = "RE_MESH_COLLECTION"
    for slot, entry in enumerate(mats):
        mat, src_me = (entry, parts[entry]) if isinstance(entry, str) else entry
        m = src_me.copy()
        # our object has no skeleton: drop the game's joint weights (the exporter refuses weights without an armature)
        bmw = bmesh.new(); bmw.from_mesh(m)
        for lay in list(bmw.verts.layers.deform):
            bmw.verts.layers.deform.remove(lay)
        bmw.to_mesh(m); bmw.free()
        for v in m.vertices:
            v.co = Vector(to_local_blender(v.co))
        # custom normals (the game's) are turned with the vertices: re-aim them by the same rotation
        if m.has_custom_normals:
            R = [[rows[i][j] for j in range(3)] for i in range(3)]
            def rot(n):
                w = to_re(n); l = [sum(w[j] * R[i][j] for j in range(3)) for i in range(3)]
                return (l[0], -l[2], l[1])
            src_n = [tuple(cn.vector) for cn in src_me.corner_normals]
            m.normals_split_custom_set([rot(n) for n in src_n])
        nm = "LOD_0_Group_0_Sub_%d__%s" % (slot, mat)
        m.name = nm
        o = bpy.data.objects.new(nm, m); coll.objects.link(o)
        o.vertex_groups.clear()   # (Blender keeps the joint's group name with the mesh data)
        print("   %s sub %d %-22s %d verts %d faces" % (name, slot, mat, len(m.vertices), len(m.polygons)))
    out = os.path.join(OUT, name + ".mesh.2101050001")
    r = bpy.ops.re_mesh.exportfile(filepath=out, filename_ext=".2101050001", targetCollection=name + ".mesh", selectedOnly=False)
    print("EXPORT %s -> %s (%s bytes)" % (r, out, os.path.getsize(out) if os.path.exists(out) else "MISSING"))
    return out

export("gm79_spent_shell", [MAT_CASE, MAT_SOOT, MAT_BAND])
export("gm79_round_band", [MAT_BAND])

# ---- 4. b176 (Tefa 2026-11-25, wearing b175: "when there already is a live round in the chamber, taking a new one from the pouch
# makes the one in the barrel invisible ... create our own replicas of live rounds in blender?"): the gun shows ONE round (its
# Ammo01 joint, and the fronts on Ammo02-04), so while that one is in the hand, the one in the barrel is ours: the game's own case
# (outside and inside, plain metal, no soot), its own warhead part for the kind (6 the explosive's, 7 the flash's: the pickups
# it03_500 / it03_501 match them, 2026-11-25 note) and the band; same materials as the spent shell (gm79_shell_<kind>.mdf2: the
# warhead's UVs sit on the launcher's own texture, which the case material is). Both in Ammo01's frame, the warhead where it sits
# in front of the case in the gun.
def part_mesh(group):
    o = next((x for x in bpy.data.objects if x.type == "MESH" and x.name.startswith(group)), None)
    if o is None:
        print("NOT FOUND:", group); return None
    m = o.data.copy(); m.transform(o.matrix_world)
    m.materials.clear(); m.materials.append(bpy.data.materials.get(MAT_CASE) or bpy.data.materials.new(MAT_CASE))
    print("warhead part:", o.name, len(m.vertices), "verts")
    return m
for kind, group in (("explosive", "Group_6_Sub_0"), ("flash", "Group_7_Sub_0")):
    head = part_mesh(group)
    if head is not None:
        # the inside keeps the soot material (hidden behind the warhead): the mesh must name the same three materials, in the same
        # order, as gm79_shell_<kind>.mdf2, or the engine takes none (measured flat 2026-11-25: case + band only drew the checker)
        export("gm79_live_" + kind, [MAT_CASE, MAT_SOOT, (MAT_CASE, head), MAT_BAND])
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "gm79_spent_shell.blend"))
print("DONE")
