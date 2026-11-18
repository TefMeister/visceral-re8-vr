-- q_muzzle_wall_re2.lua (RE2 / RE3; RV_GAME_DIR set): is the drawn gun's muzzle inside a wall? A ray from the hand as our
-- plugin handed it back (bridge 615-617) to the drawn muzzle (vfx_muzzle1 / 2 on the equipped gun) on the walls' layer, doors
-- left out; plus how far the hand moved and how much the gun is turned from where the controller holds it. 2026-11-18.
local NS = reframework:get_game_name() == "re3" and "offline." or "app.ropeway."
local LAYER = rawget(_G, "__visceral_wall_layer") or 2
local b = visceral_bridge
local pl = sdk.get_managed_singleton(NS .. "PlayerManager"):call("get_CurrentPlayer")
local w = pl:call("getComponent(System.Type)", sdk.typeof(NS .. "survivor.Equipment")):get_field("<EquipWeapon>k__BackingField")
local tf = w:call("get_GameObject"):call("get_Transform")
local h = sdk.find_type_definition("via.murmur_hash"):get_method("calc32")
local j = tf:call("getJointByHash", h:call(nil, "vfx_muzzle1")) or tf:call("getJointByHash", h:call(nil, "vfx_muzzle2"))
if j == nil then return "no muzzle joint" end
local m = j:call("get_Position")
local o = Vector3f.new(b.r(615), b.r(616), b.r(617))
local raw = Vector3f.new(b.r(608), b.r(609), b.r(610))
local cast = sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
local sys = sdk.get_native_singleton("via.physics.System")
local q = sdk.create_instance("via.physics.CastRayQuery"); local r = sdk.create_instance("via.physics.CastRayResult")
q:call("setRay(via.vec3, via.vec3)", o, m); q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
local fi = q:call("get_FilterInfo"); fi:call("set_Group", 0); fi:call("set_MaskBits", 0xFFFFFFFF & ~1); fi:call("set_Layer", LAYER); q:call("set_FilterInfo", fi)
cast:call(sys, q, r)
local walls = 0
for i = 0, r:call("get_NumContactPoints") - 1 do
  local col = r:call("getContactCollidable(System.UInt32)", i)
  local n = col and col:call("get_GameObject"):call("get_Name") or "?"
  if not n:lower():find("door") then walls = walls + 1 end
end
local q1 = { b.r(611), b.r(612), b.r(613), b.r(614) }
local q2 = { b.r(618), b.r(619), b.r(620), b.r(621) }
local d = math.abs(q1[1] * q2[1] + q1[2] * q2[2] + q1[3] * q2[3] + q1[4] * q2[4])
return string.format("muzzle in a wall: %s | hand moved %.2f m | gun turned %.0f deg | hand-to-muzzle %.2f m",
  walls > 0 and "YES" or "no", (o - raw):length(), math.deg(2 * math.acos(math.min(1, d))), (m - o):length())
