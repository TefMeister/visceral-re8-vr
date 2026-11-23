-- q_wrist.lua: TEST ONLY, READ ONLY (2026-11-23). The hand's joints (and fingertips, 2.5 cm past the last joint) in its own WRIST
-- frame, cm: the hand's shape as posed right now. E.side = "R_" for the right hand.
local side = E.side or "L_"
local sm = sdk.get_native_singleton("via.SceneManager")
local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local ptf = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject"):call("get_Transform")
local h = ptf:call("getJointByName", side .. "Hand"); local hp, inv = h:call("get_Position"), h:call("get_Rotation"):inverse()
local out, prev = {}, nil
for _, n in ipairs({ "Thumb1", "Thumb2", "Thumb3", "IndexF1", "IndexF2", "IndexF3", "MiddleF1", "MiddleF2", "MiddleF3", "RingF1", "RingF2", "RingF3", "PinkyF1", "PinkyF2", "PinkyF3" }) do
  local p = ptf:call("getJointByName", side .. n):call("get_Position"); local d = inv * (p - hp)
  local line = string.format("%-9s %6.1f %6.1f %6.1f", n, d.x * 100, d.y * 100, d.z * 100)
  if n:sub(-1) == "3" then local t = inv * (p + (p - prev):normalized() * 0.025 - hp); line = line .. string.format("  tip %6.1f %6.1f %6.1f", t.x * 100, t.y * 100, t.z * 100) end
  out[#out+1] = line; prev = p
end
return table.concat(out, "\n")
