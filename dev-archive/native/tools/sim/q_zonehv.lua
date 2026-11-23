-- q_zonehv.lua: TEST ONLY, READ ONLY (2026-11-23). Every grip zone that is on, in the CAMERA's frame (cm: right, up, forward), so
-- the robot can bring the part being worked to the middle of the picture (frame.py). E.joint = a gun joint name adds that joint.
local cam = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local cp, inv = cam:call("get_Position"), cam:call("get_Rotation"):inverse()
local d = json.load_file("visceral_re8/zones_state.json")
local out = {}
for _, z in ipairs(d and d.zones or {}) do
  if z.on then
    local l = inv * (Vector3f.new(z.x, z.y, z.z) - cp)
    out[#out+1] = string.format("%s %.1f %.1f %.1f", z.key, l.x * 100, l.y * 100, -l.z * 100)
  end
end
return table.concat(out, "\n")
