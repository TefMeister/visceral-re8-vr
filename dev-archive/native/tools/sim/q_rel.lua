-- q_rel.lua: TEST ONLY, READ ONLY (2026-11-23). The gun's magazine joint and the spare copy's magazine joint in the LEFT WRIST's
-- frame (L_Hand): position cm + quaternion, and the wrist in the gun's Body frame. One line each, for stages.py.
local sm = sdk.get_native_singleton("via.SceneManager")
local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local ptf = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject"):call("get_Transform")
local gun, spare
local c = ptf:call("get_Child")
while c do
  if c:call("get_GameObject"):call("get_Name"):find("^ri%d+") then gun = c
    local c2 = c:call("get_Child"); while c2 do if c2:call("get_GameObject"):call("get_Name") == "visceral_second_magazine" then spare = c2 end; c2 = c2:call("get_Next") end
  end
  c = c:call("get_Next")
end
local h = ptf:call("getJointByName", E.wrist or "L_Hand")
local hp, hr = h:call("get_Position"), h:call("get_Rotation")
local function rel(bp, br, p, r) local inv = br:inverse(); local d = inv * (p - bp); local q = inv * r; return string.format("%.2f %.2f %.2f | %.4f %.4f %.4f %.4f", d.x * 100, d.y * 100, d.z * 100, q.x, q.y, q.z, q.w) end
local out = {}
if gun then
  local m = gun:call("getJointByName", "Magazine"); local b = gun:call("getJointByName", "Body")
  out[#out+1] = "mag1 in wrist: " .. rel(hp, hr, m:call("get_Position"), m:call("get_Rotation"))
  out[#out+1] = "mag1 in gun: " .. rel(b:call("get_Position"), b:call("get_Rotation"), m:call("get_Position"), m:call("get_Rotation"))
  out[#out+1] = "wrist in gun: " .. rel(b:call("get_Position"), b:call("get_Rotation"), hp, hr)
end
if spare and spare:call("get_GameObject"):call("get_DrawSelf") then
  local sj = spare:call("getJointByName", "Magazine")
  if sj then out[#out+1] = "spare in wrist: " .. rel(hp, hr, sj:call("get_Position"), sj:call("get_Rotation")) end
end
return table.concat(out, "\n")
