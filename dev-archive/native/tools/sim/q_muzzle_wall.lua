-- q_muzzle_wall.lua (rv.py --front "$(cat q_muzzle_wall.lua)"): is the drawn gun's muzzle inside a wall? A ray from the
-- drawn hand (the right IK target) to the muzzle on the Bullet layer, doors left out; plus how far the hand was moved and
-- how much the gun is turned from where the player holds it (2026-11-18, the wall tilt, b141).
local cast = sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
local h = re8vr.last_right_hand_position
local tf = re8vr.right_hand_ik:get_field("Target")
local tp, tr = tf:call("get_Position"), tf:call("get_Rotation")
local hr = re8vr.last_right_hand_rotation
local m = re8vr.last_muzzle_pos
local sys = sdk.get_native_singleton("via.physics.System")
local q = sdk.create_instance("via.physics.CastRayQuery"); local r = sdk.create_instance("via.physics.CastRayResult")
q:call("setRay(via.vec3, via.vec3)", tp, m); q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
local fi = q:call("get_FilterInfo"); fi:call("set_Group", 0); fi:call("set_MaskBits", 0xFFFFFFFF & ~1); fi:call("set_Layer", 12); q:call("set_FilterInfo", fi)
cast:call(sys, q, r)
local walls = 0
for i = 0, r:call("get_NumContactPoints") - 1 do
    local col = r:call("getContactCollidable(System.UInt32)", i)
    local n = col and col:call("get_GameObject"):call("get_Name") or "?"
    if not n:lower():find("door") then walls = walls + 1 end
end
local ql = math.sqrt(hr.x * hr.x + hr.y * hr.y + hr.z * hr.z + hr.w * hr.w)
local dotq = math.abs((tr.x * hr.x + tr.y * hr.y + tr.z * hr.z + tr.w * hr.w) / ql)
local d = m - tp
return string.format("muzzle in a wall: %s | hand moved %.2f m | gun turned %.0f deg | gun yaw %.0f pitch %.0f | barrel %.2f m",
    walls > 0 and "YES" or "no", (tp - h):length(), math.deg(2 * math.acos(math.min(1, dotq))), math.deg(math.atan(d.x, d.z)),
    math.deg(math.atan(d.y, math.sqrt(d.x * d.x + d.z * d.z))), d:length())
