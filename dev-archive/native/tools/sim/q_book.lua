-- q_book.lua (rv.py -f): hang one of the game's own models in front of the camera. E.book_mesh / E.book_mdf pick it.
local MESH = E.book_mesh or "objectroot/setmodel/sm6x_event/sm60/sm60_035_pocketbook01a/sm60_035_pocketbook01a_00md.mesh"
local MDF = E.book_mdf or "objectroot/setmodel/sm6x_event/sm60/sm60_035_pocketbook01a/sm60_035_pocketbook01a_00md_mat.mdf2"
local log_ = {}
local function note(s) log_[#log_ + 1] = tostring(s) end

if E.book ~= nil then pcall(function() E.book:call("destroy", E.book) end); E.book = nil; note("old one removed") end

local go_td = sdk.find_type_definition("via.GameObject")
local folder = nil
pcall(function() folder = sdk.get_primary_camera():call("get_GameObject"):call("get_Folder") end)
note("folder " .. tostring(folder ~= nil))
local go = folder and go_td:get_method("create(System.String, via.Folder)"):call(nil, "VisceralOptionsBook", folder)
          or go_td:get_method("create(System.String)"):call(nil, "VisceralOptionsBook")
if go == nil then return "no GameObject" end
go = go:add_ref()
pcall(function() go:call(".ctor") end)
local mesh = go:call("createComponent(System.Type)", sdk.typeof("via.render.Mesh"))
if mesh == nil then return "no mesh component" end
mesh = mesh:add_ref()
pcall(function() mesh:call(".ctor()") end)

local mres = sdk.create_resource("via.render.MeshResource", MESH)
note("mesh resource " .. tostring(mres ~= nil))
if mres == nil then return table.concat(log_, "; ") end
mres = mres:add_ref()
local ok1, e1 = pcall(function() mesh:call("setMesh", mres:create_holder("via.render.MeshResourceHolder"):add_ref()) end)
note("setMesh(holder) " .. tostring(ok1) .. " " .. tostring(e1 or ""))
local dres = sdk.create_resource("via.render.MeshMaterialResource", MDF)
note("material resource " .. tostring(dres ~= nil))
if dres ~= nil then
    dres = dres:add_ref()
    local ok2, e2 = pcall(function() mesh:call("set_Material", dres:create_holder("via.render.MeshMaterialResourceHolder"):add_ref()) end)
    note("set_Material(holder) " .. tostring(ok2) .. " " .. tostring(e2 or ""))
end
pcall(function() mesh:call("set_DrawShadowCast", false) end)

-- in front of the camera, facing it
local cam = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
local cp, cq = cam:call("get_Position"), cam:call("get_Rotation")
local f = cq * Vector3f.new(0, 0, -1)
f.y = 0; f = f:normalized()
if E.book_side ~= nil then   -- nudge sideways (metres to the camera's right)
    local r = cq * Vector3f.new(1, 0, 0)
    cp = Vector3f.new(cp.x + r.x * E.book_side, cp.y, cp.z + r.z * E.book_side)
end
local dist = E.book_dist or 0.6
local pos = Vector3f.new(cp.x + f.x * dist, cp.y + (E.book_up or -0.1), cp.z + f.z * dist)
local tf = go:call("get_Transform")
tf:call("set_Position", pos)
local yaw = math.atan(f.x, f.z)
local q = Quaternion.new(math.cos(yaw * 0.5), 0, math.sin(yaw * 0.5), 0)
if E.book_yaw ~= nil then local a = math.rad(E.book_yaw); q = q * Quaternion.new(math.cos(a * 0.5), 0, math.sin(a * 0.5), 0) end
if E.book_pitch ~= nil then local a = math.rad(E.book_pitch); q = q * Quaternion.new(math.cos(a * 0.5), math.sin(a * 0.5), 0, 0) end
tf:call("set_Rotation", q)
local s = E.book_scale or 1.0
tf:call("set_LocalScale", Vector3f.new(s, s, s))
E.book, E.book_meshc = go, mesh
note(string.format("placed at (%.2f %.2f %.2f), camera (%.2f %.2f %.2f)", pos.x, pos.y, pos.z, cp.x, cp.y, cp.z))
local okb, bb = pcall(function() return mesh:call("get_WorldAABB") end)
if okb and bb then pcall(function() note("box " .. show(bb:call("get_Size") or bb)) end) end
return table.concat(log_, "; ")
