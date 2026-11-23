-- q_re_local.lua: TEST ONLY, READ ONLY (2026-11-23), RE2 / RE3: the held gun's joints in the GUN's own frame (cm), plus both wrists
-- there: which side of the gun a part is on does not depend on how the gun is held. In these games' gun frame +z is the muzzle;
-- the LEFT wrist's x tells which sign is the gun's left when the left hand is held out to the gun's left.
local pm = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager")); local pl = pm:call("get_CurrentPlayer")
local eq = pl:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("survivor.Equipment")))
local t = eq:get_field("<EquipWeapon>k__BackingField"):call("get_GameObject"):call("get_Transform")
local gp, inv = t:call("get_Position"), t:call("get_Rotation"):inverse()
local out = {}
for _, j in ipairs(t:call("get_Joints"):get_elements()) do local n = j:call("get_Name"); if n:find("^_%d+$") or n:find("muzzle1") then local l = inv * (j:call("get_Position") - gp); out[#out+1] = string.format("%s %.1f %.1f %.1f", n, l.x * 100, l.y * 100, l.z * 100) end end
for _, n in ipairs({ "l_arm_wrist", "r_arm_wrist" }) do local l = inv * (pl:call("get_Transform"):call("getJointByName", n):call("get_Position") - gp); out[#out+1] = string.format("%s %.1f %.1f %.1f", n, l.x * 100, l.y * 100, l.z * 100) end
return table.concat(out, "\n")
