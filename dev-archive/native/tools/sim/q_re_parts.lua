-- q_re_parts.lua: TEST ONLY, READ ONLY (2026-11-23), RE2 / RE3 (rv.py with RV_GAME_DIR). The gun in hand: its name, and where its
-- joints (_00.._12, vfx) and both wrists are in the CAMERA's frame (cm: right, up, forward), so the robot hand can be sent to a
-- part (RE2 / RE3 have no zones file). Also the inventory's main weapons by slot.
local out = {}
local pm = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
local pl = pm and pm:call("get_CurrentPlayer")
if not pl then return "no player" end
local ptf = pl:call("get_Transform")
local cam = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local cp, inv = cam:call("get_Position"), cam:call("get_Rotation"):inverse()
local function hvs(p) local l = inv * (p - cp); return string.format("%.1f %.1f %.1f", l.x * 100, l.y * 100, -l.z * 100) end
local eq = pl:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("survivor.Equipment")))
local w = eq and eq:get_field("<EquipWeapon>k__BackingField")
if w then
  local g = w:call("get_GameObject"); local t = g:call("get_Transform")
  out[#out+1] = "gun " .. g:call("get_Name")
  for _, j in ipairs(t:call("get_Joints"):get_elements()) do local n = j:call("get_Name"); if n:find("^_%d+$") or n:find("muzzle1") then out[#out+1] = n .. " " .. hvs(j:call("get_Position")) end end
  local f = inv * (t:call("get_Rotation") * Vector3f.new(0, 0, 1)); out[#out+1] = string.format("fwd %.1f %.1f %.1f", f.x * 100, f.y * 100, -f.z * 100)
else out[#out+1] = "gun none" end
for _, n in ipairs({ "l_arm_wrist", "r_arm_wrist" }) do local j = ptf:call("getJointByName", n); if j then out[#out+1] = n .. " " .. hvs(j:call("get_Position")) end end
return table.concat(out, "\n")
