-- q_re_maghand.lua: TEST ONLY, READ ONLY (2026-11-23), RE2 / RE3: where the gun's magazine joint (_04) and the left hand's
-- middle finger joints are in the LEFT WRIST's own frame (cm): is a magazine carried in the hand really in the fingers?
local pl = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager")):call("get_CurrentPlayer")
local tf = pl:call("get_Transform")
local eq = pl:call("getComponent(System.Type)", sdk.typeof(sdk.game_namespace("survivor.Equipment")))
local g = eq:get_field("<EquipWeapon>k__BackingField"):call("get_GameObject"):call("get_Transform")
local w = tf:call("getJointByName", "l_arm_wrist"); local wp, inv = w:call("get_Position"), w:call("get_Rotation"):inverse()
local o = {}
local function add(n, p) local d = inv * (p - wp); o[#o + 1] = string.format("%-18s %6.1f %6.1f %6.1f", n, d.x * 100, d.y * 100, d.z * 100) end
add("magazine _04", g:call("getJointByName", E.mag or "_04"):call("get_Position"))
for _, n in ipairs({ "l_hand_middle_0", "l_hand_middle_1", "l_hand_middle_2", "l_hand_thumb_2", "l_hand_little_1" }) do add(n, tf:call("getJointByName", n):call("get_Position")) end
return table.concat(o, "\n")
