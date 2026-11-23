-- q_hand.lua: TEST ONLY, READ ONLY (2026-11-23). Where the left hand's joints are, in cm, in the frame of (a) the gun's seated
-- magazine joint and (b) the spare magazine's object (visceral_second_magazine), so a finger pose can be judged by numbers:
-- rv.py -f q_hand.lua. E.side = "R_" for the right hand; E.ref = a gun joint name to use instead of the magazine's.
local side = E.side or "L_"
local sm = sdk.get_native_singleton("via.SceneManager")
local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local pgo = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject")
local ptf = pgo:call("get_Transform")
local gun, spare
local c = ptf:call("get_Child")
while c do
  local n = c:call("get_GameObject"):call("get_Name")
  if n:find("^ri%d+") then gun = c
    local c2 = c:call("get_Child"); while c2 do if c2:call("get_GameObject"):call("get_Name") == "visceral_second_magazine" then spare = c2 end; c2 = c2:call("get_Next") end
  end
  c = c:call("get_Next")
end
local out = {}
local function joint(tf, name) return tf:call("getJointByName", name) end
local refname = E.ref
local ref
if gun then
  if not refname then
    local js = gun:call("get_Joints"):get_elements()
    for _, j in ipairs(js) do local n = j:call("get_Name"); if n:lower():find("mag") and not ref then ref = j; refname = n end end
    if E.list then local t = {}; for _, j in ipairs(js) do t[#t+1] = j:call("get_Name") end; out[#out+1] = "gun joints: " .. table.concat(t, " ") end
  else ref = joint(gun, refname) end
end
local function frame(pos, rot) local inv = rot:inverse(); return function(p) local d = inv * (p - pos); return d end end
local frames = {}
if ref then frames[#frames+1] = { "in " .. refname, frame(ref:call("get_Position"), ref:call("get_Rotation")) } end
if spare and spare:call("get_GameObject"):call("get_DrawSelf") then
  local sj = joint(spare, "Magazine") or spare   -- the spare is a copy of the gun's mesh: its own Magazine joint is where it is drawn
  frames[#frames+1] = { "in spare", frame(sj:call("get_Position"), sj:call("get_Rotation")) }
end
if E.list and ref then
  local f = frame(ref:call("get_Position"), ref:call("get_Rotation"))
  for _, n in ipairs({ "Trigger", "vfx_muzzle", "Hammer", "Slide", "Body" }) do
    local j = joint(gun, n); if j then local d = f(j:call("get_Position")); out[#out+1] = string.format("gun %-10s in %s: %6.1f %6.1f %6.1f", n, refname, d.x * 100, d.y * 100, d.z * 100) end
  end
  local rh = joint(ptf, "R_Hand"); if rh then local d = f(rh:call("get_Position")); out[#out+1] = string.format("R_Hand in %s: %6.1f %6.1f %6.1f", refname, d.x * 100, d.y * 100, d.z * 100) end
end
local names = { "Hand", "Thumb1", "Thumb2", "Thumb3", "IndexF1", "IndexF2", "IndexF3", "MiddleF1", "MiddleF2", "MiddleF3", "RingF1", "RingF2", "RingF3", "PinkyF1", "PinkyF2", "PinkyF3" }
for _, fr in ipairs(frames) do
  out[#out+1] = fr[1] .. " (cm):"
  local prev
  for _, n in ipairs(names) do
    local j = joint(ptf, side .. n)
    if j then
      local p = j:call("get_Position"); local d = fr[2](p)
      local line = string.format("  %-9s %6.1f %6.1f %6.1f", n, d.x * 100, d.y * 100, d.z * 100)
      if n:sub(-1) == "3" and prev then local t = p + (p - prev):normalized() * 0.025; local dt = fr[2](t); line = line .. string.format("   tip %6.1f %6.1f %6.1f", dt.x * 100, dt.y * 100, dt.z * 100) end
      out[#out+1] = line; prev = p
    end
  end
end
if #frames == 0 then out[#out+1] = "no gun / no magazine joint found" end
return table.concat(out, "\n")
