-- q_doors_near.lua (rv.py -f): every door leaf within 45 m: distance, height difference, locked, state, its object's name
-- (walk_to.py takes the name). 2026-11-19.
local sm = sdk.get_native_singleton("via.SceneManager"); local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local l = scene:call("findComponents(System.Type)", sdk.typeof("app.DoorBehavior")); local pp = re8vr.player:call("get_Transform"):call("get_Position")
local rows = {}
for i = 0, l:call("get_Count") - 1 do
  local c = l:call("get_Item", i); local go = c:call("get_GameObject"); local tf = go:call("get_Transform"); local p = tf:call("get_Position")
  local d = math.sqrt((p.x - pp.x) ^ 2 + (p.z - pp.z) ^ 2)
  if d < 45 then
    local par = tf:call("get_Parent"); local nm = go:call("get_Name"); if nm == "Door" and par then nm = par:call("get_GameObject"):call("get_Name") .. "/Door" end
    rows[#rows + 1] = { d, string.format("%.1f m dy %+.1f %s st=%d %s", d, p.y - pp.y, c:call("IsLocked") and "LOCKED" or "open-able", c:call("get_doorState"), nm) }
  end
end
table.sort(rows, function(a, b) return a[1] < b[1] end)
local out = {} for i = 1, math.min(#rows, 25) do out[i] = rows[i][2] end
return table.concat(out, "\n")
