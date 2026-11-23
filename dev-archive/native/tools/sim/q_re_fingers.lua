-- q_re_fingers.lua: TEST ONLY, READ ONLY (2026-11-23), RE2 / RE3: every finger joint's local Euler angles (degrees) of one hand
-- (E.side = "l" or "r"), as pose.py arguments, so a pose can be read, changed and sent back through the Hand Poser window.
local side = E.side or "l"
local pl = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager")):call("get_CurrentPlayer")
local tf = pl:call("get_Transform"); local o = {}
for _, f in ipairs({ "thumb", "index", "middle", "ring", "little" }) do
  for i = 0, 3 do
    local j = tf:call("getJointByName", side .. "_hand_" .. f .. "_" .. i)
    if j then local e = j:call("get_LocalEulerAngle"); o[#o + 1] = string.format("%s_hand_%s_%d=%.1f,%.1f,%.1f", side, f, i, math.deg(e.x), math.deg(e.y), math.deg(e.z)) end
  end
end
return table.concat(o, " ")
