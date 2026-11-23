-- q_gunframe.lua: TEST ONLY, READ ONLY (2026-11-23). Village: every joint of the gun in hand, and the RIGHT hand's wrist, thumb and
-- index joints with their fingertips, all in the gun's own root frame (cm; +x the gun's left, +y up, +z the muzzle): where the
-- thumb is against a part of the gun (a latch, a hammer). E.side = "L_" for the left hand.
local side = E.side or "R_"
local sm = sdk.get_native_singleton("via.SceneManager")
local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local ptf = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject"):call("get_Transform")
-- the gun in hand: the player keeps other guns' objects as children too, so it is picked by the number the zones script reports
local want = "ri" .. tostring((json.load_file("visceral_re8/zones_state.json") or {}).gun or "")
local gun; local c = ptf:call("get_Child")
while c do if c:call("get_GameObject"):call("get_Name"):find(want, 1, true) then gun = c end; c = c:call("get_Next") end
if not gun then return "no gun" end
local gp, inv = gun:call("get_Position"), gun:call("get_Rotation"):inverse()
local out = {}
for _, j in ipairs(gun:call("get_Joints"):get_elements()) do local l = inv * (j:call("get_Position") - gp); out[#out+1] = string.format("gun %-14s %6.1f %6.1f %6.1f", j:call("get_Name"), l.x * 100, l.y * 100, l.z * 100) end
local prev
for _, n in ipairs({ "Hand", "Thumb1", "Thumb2", "Thumb3", "IndexF1", "IndexF2", "IndexF3" }) do
  local p = ptf:call("getJointByName", side .. n):call("get_Position"); local l = inv * (p - gp)
  local line = string.format("%-9s %6.1f %6.1f %6.1f", n, l.x * 100, l.y * 100, l.z * 100)
  if n:sub(-1) == "3" then local t = inv * (p + (p - prev):normalized() * 0.025 - gp); line = line .. string.format("  tip %6.1f %6.1f %6.1f", t.x * 100, t.y * 100, t.z * 100) end
  out[#out+1] = line; prev = p
end
return table.concat(out, "\n")
