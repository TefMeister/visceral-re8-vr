-- q_hand_wall.lua (rv.py -f): how far the drawn wrists and middle fingertips are from the wall straight ahead of the view
-- (a level ray 40 cm under the camera, the walls script's layer). Negative = inside the wall. 2026-11-19.
local LAYER = rawget(_G, "__visceral_wall_layer") or 2
local cast = sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
local cx = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local cp = cx:call("get_Position"); local f = cx:call("get_Rotation") * Vector3f.new(0, 0, -1)
local fl = math.sqrt(f.x * f.x + f.z * f.z); local fx, fz = f.x / fl, f.z / fl
local a = Vector3f.new(cp.x, cp.y - 0.4, cp.z); local b = Vector3f.new(cp.x + fx * 3, cp.y - 0.4, cp.z + fz * 3)
local q = sdk.create_instance("via.physics.CastRayQuery"); local r = sdk.create_instance("via.physics.CastRayResult")
q:call("setRay(via.vec3, via.vec3)", a, b); q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
local fi = q:call("get_FilterInfo"); fi:call("set_Group", 0); fi:call("set_MaskBits", 0xFFFFFFFF & ~1); fi:call("set_Layer", LAYER); q:call("set_FilterInfo", fi)
cast:call(sdk.get_native_singleton("via.physics.System"), q, r)
if (r:call("get_NumContactPoints") or 0) < 1 then return "no wall ahead" end
local c = r:call("getContactPoint(System.UInt32)", 0); local p, n = c:get_field("Position"), c:get_field("Normal")
local tf = re8vr.player:call("get_Transform")
local out = { string.format("wall %.2f m ahead", math.sqrt((p.x - a.x) ^ 2 + (p.z - a.z) ^ 2)) }
-- per joint its OWN distance to the surface: a ray along the wall's normal from 60 cm outside the joint to 60 cm inside
-- (a rough rock wall is not the plane of the one ray above)
for _, j in ipairs({ "L_Hand", "L_MiddleF3", "R_Hand", "R_MiddleF3" }) do
  local jp = tf:call("getJointByName", j):call("get_Position")
  local s0 = Vector3f.new(jp.x + n.x * 0.6, jp.y + n.y * 0.6, jp.z + n.z * 0.6); local s1 = Vector3f.new(jp.x - n.x * 0.6, jp.y - n.y * 0.6, jp.z - n.z * 0.6)
  q:call("setRay(via.vec3, via.vec3)", s0, s1); cast:call(sdk.get_native_singleton("via.physics.System"), q, r)
  if (r:call("get_NumContactPoints") or 0) < 1 then out[#out + 1] = j .. " no wall within 60 cm"
  else local hp = r:call("getContactPoint(System.UInt32)", 0):get_field("Position")
    out[#out + 1] = string.format("%s %+.1f cm", j, ((jp.x - hp.x) * n.x + (jp.y - hp.y) * n.y + (jp.z - hp.z) * n.z) * 100) end
end
return table.concat(out, " | ")
