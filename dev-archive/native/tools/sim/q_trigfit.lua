-- q_trigfit.lua: TEST ONLY, READ ONLY (2026-11-23). trigfit.py's question: the gun in hand's Trigger joint and the RIGHT index
-- finger's pad in the gun's root frame (cm; +x the gun's left, +y up, +z the muzzle), and how closed the middle, ring and little
-- fingers are (wrist to their last joint, cm; about 7-8 curled round a grip, 10+ straight). One line.
local sm = sdk.get_native_singleton("via.SceneManager")
local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local ptf = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject"):call("get_Transform")
local want = "ri" .. tostring((json.load_file("visceral_re8/zones_state.json") or {}).gun or "")
local gun; local c = ptf:call("get_Child")
while c do if c:call("get_GameObject"):call("get_Name"):find(want, 1, true) then gun = c end; c = c:call("get_Next") end
if not gun then return "no gun" end
local gp, inv = gun:call("get_Position"), gun:call("get_Rotation"):inverse()
local function L(p) local l = inv * (p - gp); return l.x * 100, l.y * 100, l.z * 100 end
local trig
for _, j in ipairs(gun:call("get_Joints"):get_elements()) do if j:call("get_Name"):lower():find("trigger", 1, true) then trig = j:call("get_Position") end end
local function J(n) return ptf:call("getJointByName", "R_" .. n):call("get_Position") end
local f2, f3 = J("IndexF2"), J("IndexF3")
local pad = f3 + (f3 - f2):normalized() * 0.012
local px, py, pz = L(pad)
local h = J("Hand")
local curl = string.format("middle %.1f ring %.1f pinky %.1f", (J("MiddleF3") - h):length() * 100, (J("RingF3") - h):length() * 100, (J("PinkyF3") - h):length() * 100)
if not trig then return string.format("NO Trigger joint | pad %.1f %.1f %.1f | %s", px, py, pz, curl) end
local tx, ty, tz = L(trig)
return string.format("trigger %.1f %.1f %.1f | pad %.1f %.1f %.1f | pad - trigger %+.1f %+.1f %+.1f | %s", tx, ty, tz, px, py, pz, px - tx, py - ty, pz - tz, curl)
