-- q_gate_leaves.lua: the drawn angle of every door leaf within 3 m (the "_00" joint's local turn), 2026-11-18
local pp = re8vr.player:call("get_Transform"):call("get_Position")
local sm = sdk.get_native_singleton("via.SceneManager"); local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local list = scene:call("findComponents(System.Type)", sdk.typeof("app.DoorBehavior"))
local out = {}
for i = 0, list:call("get_Count") - 1 do
  local tf = list:call("get_Item", i):call("get_GameObject"):call("get_Transform"); local p = tf:call("get_Position")
  if (p.x - pp.x)^2 + (p.z - pp.z)^2 < 9 then
    local j = tf:call("getJointByName", "_00"); local q = j:call("get_LocalRotation"); local jp = j:call("get_Position")
    out[#out + 1] = string.format("leaf at %.2f %.2f: %.1f deg", jp.x, jp.z, math.deg(2 * math.atan(q.y, q.w)))
  end
end
return table.concat(out, " | ")
