-- q_wall_scan.lua (rv.py --front "$(cat q_wall_scan.lua)"; RV_GAME_DIR for RE2 / RE3): the nearest wall round the head, in
-- 24 level rays 40 cm under the camera on the layer the walls script found (__visceral_wall_layer, else 2), doors left out.
-- Prints each hit as "<deg off the view>: <distance> <name>" (positive deg = to the left), nearest first. 2026-11-18.
local LAYER = rawget(_G, "__visceral_wall_layer") or 2
local cast = sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
local function ray(a, b)
  local sys = sdk.get_native_singleton("via.physics.System")
  local q = sdk.create_instance("via.physics.CastRayQuery"); local r = sdk.create_instance("via.physics.CastRayResult")
  q:call("setRay(via.vec3, via.vec3)", a, b); q:call("clearOptions"); q:call("enableAllHits"); q:call("enableNearSort")
  local fi = q:call("get_FilterInfo"); fi:call("set_Group", 0); fi:call("set_MaskBits", 0xFFFFFFFF & ~1); fi:call("set_Layer", LAYER); q:call("set_FilterInfo", fi)
  cast:call(sys, q, r)
  for i = 0, r:call("get_NumContactPoints") - 1 do
    local c = r:call("getContactPoint(System.UInt32)", i); local col = r:call("getContactCollidable(System.UInt32)", i)
    local n = col and col:call("get_GameObject"):call("get_Name") or "?"
    if not n:lower():find("door") then return c:get_field("Distance"), n end
  end
end
local ct = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform"); local cp = ct:call("get_Position")
local f = ct:call("get_Rotation") * Vector3f.new(0, 0, -1); local cy = math.atan(f.x, f.z)
local hits = {}
for k = 0, 23 do
  local a = cy + math.rad(k * 15); local b = Vector3f.new(cp.x + math.sin(a) * 3, cp.y - 0.4, cp.z + math.cos(a) * 3)
  local d, n = ray(Vector3f.new(cp.x, cp.y - 0.4, cp.z), b)
  if d then local deg = k * 15; if deg > 180 then deg = deg - 360 end; hits[#hits + 1] = { d = d, s = string.format("%d: %.2f %s", deg, d, n) } end
end
table.sort(hits, function(x, y) return x.d < y.d end)
local out = {}
for i = 1, math.min(#hits, 6) do out[#out + 1] = hits[i].s end
return "layer " .. LAYER .. " | " .. table.concat(out, "; ")
