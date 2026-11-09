local function yaw(q) local f = q * Vector3f.new(0, 0, 1); return math.deg(math.atan(f.x, f.z)) end
local tf = re8vr.player:call("get_Transform")
local cam = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local V = VISCERAL_BODY_TURN
return string.format("body %.1f  camera %.1f  hmd %.1f | kept body %.1f  head off body %.1f  turning %s  turns %d  err %s", yaw(tf:call("get_Rotation")), yaw(cam:call("get_Rotation")), yaw(vrmod:get_rotation(0):to_quat()), V.body_deg or -999, V.rel, tostring(V.turning), V.count, tostring(V.last_error))
