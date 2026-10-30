-- visceral_re8_sphere_probe.lua -- ONE-OFF PROBE (2026-10-30): which material variable makes the balloon see-through?
-- Tefa asked for the grip spheres to fade in (10 % at the edge, 80 % at the centre); the engine's Mesh has no model-wide
-- opacity, so it has to go through the balloon's own material. This makes one balloon in front of the camera as soon as a
-- scene exists (the title screen is enough: no gameplay needed), logs every material variable with its type and value, then
-- for each float / colour variable sets it and reads it back, and destroys the balloon. Archive this file once read.

local TAG = "[sphere-probe]"
local MESH = "_ge/environment/props/resource/sm5x/sm59_162_balloon/sm59_162_balloon_00.mesh"
local MAT = "_ge/environment/props/resource/sm5x/sm59_162_balloon/sm59_162_balloon_00.mdf2"
local WAIT_FRAMES = 1200

local go, comp, done, frames, mat_set = nil, nil, false, 0, false
local mesh_h, mat_h = nil, nil

local function holder(path, kind, holder_type)
    local h = nil
    pcall(function()
        local res = sdk.create_resource(kind, path)
        if res then res = res:add_ref(); h = res:create_holder(holder_type) end
        if h then h = h:add_ref() end
    end)
    return h
end

local function make()
    local td = sdk.find_type_definition("via.GameObject")
    local mk = td and td:get_method("create(System.String, via.Folder)")
    if not mk then return end
    local folder = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
        for _, name in ipairs({ "ModdedTemporaryObjects", "Debug", "Master" }) do
            if not folder then folder = scene:call("findFolder", name) end
        end
    end)
    log.info(TAG .. " folder: " .. tostring(folder ~= nil))
    pcall(function() go = mk:call(nil, "visceral_re8_sphere_probe", folder); go = go:add_ref(); go:call(".ctor") end)
    if not go then return end
    pcall(function()
        comp = go:call("createComponent(System.Type)", sdk.find_type_definition("via.render.Mesh"):get_runtime_type())
        comp = comp:add_ref(); comp:call(".ctor()")
        comp:call("set_Enabled", true); comp:call("set_DrawDefault", true)
        go:call("set_DrawSelf", true); go:call("set_UpdateSelf", true); go:call("setActive", true)
        local xf = go:call("get_Transform"); xf:call("set_Position", Vector3f.new(0, -1000, 0))
    end)
    pcall(function() log.info(TAG .. string.format(" mesh component at 0x%X", comp:get_address())) end)
    mesh_h = holder(MESH, "via.render.MeshResource", "via.render.MeshResourceHolder")
    mat_h = holder(MAT, "via.render.MeshMaterialResource", "via.render.MeshMaterialResourceHolder")
    log.info(TAG .. " made: holders mesh " .. tostring(mesh_h ~= nil) .. ", material " .. tostring(mat_h ~= nil))
end

local function probe()
    local n = 0
    pcall(function() n = comp:call("get_MaterialNum") end)
    if not n or n == 0 then return false end
    for m = 0, n - 1 do
        local mname, vn = "?", 0
        pcall(function() mname = comp:call("getMaterialName", m) end)
        pcall(function() vn = comp:call("getMaterialVariableNum", m) end)
        log.info(TAG .. string.format(" material %d %s: %d variables", m, tostring(mname), vn or 0))
        for v = 0, (vn or 1) - 1 do
            local name, ty, val = "?", "?", "?"
            pcall(function() name = comp:call("getMaterialVariableName", m, v) end)
            pcall(function() ty = tostring(comp:call("getMaterialVariableType", m, v)) end)
            local okf, f = pcall(function() return comp:call("getMaterialFloat", m, v) end)
            local ok4, c = pcall(function() return comp:call("getMaterialFloat4", m, v) end)
            if ok4 and c and c.x then val = string.format("float4 %.3f %.3f %.3f %.3f", c.x, c.y, c.z, c.w)
            elseif okf and f then val = string.format("float %.3f", f) end
            -- write test: a float set to 0.37, a float4's last number set to 0.37, read back
            local back = ""
            if ok4 and c and c.x then
                pcall(function() comp:call("setMaterialFloat4", m, v, Vector4f.new(c.x, c.y, c.z, 0.37)) end)
                local okb, cb = pcall(function() return comp:call("getMaterialFloat4", m, v) end)
                back = okb and cb and string.format(" -> w %.3f", cb.w) or " -> unreadable"
                pcall(function() comp:call("setMaterialFloat4", m, v, c) end)
            elseif okf and f then
                pcall(function() comp:call("setMaterialFloat", m, v, 0.37) end)
                local okb, fb = pcall(function() return comp:call("getMaterialFloat", m, v) end)
                back = okb and fb and string.format(" -> %.3f", fb) or " -> unreadable"
                pcall(function() comp:call("setMaterialFloat", m, v, f) end)
            end
            log.info(TAG .. string.format("   %d %s type %s = %s%s", v, tostring(name), ty, val, back))
        end
    end
    local ok, la = pcall(function() comp:call("updateBoundingBox"); return comp:call("get_ModelLocalAABB") end)
    if ok and la then
        local mn, mx = la:get_field("minpos"), la:get_field("maxpos")
        if mn and mx then log.info(TAG .. string.format(" box min %.3f %.3f %.3f max %.3f %.3f %.3f", mn.x, mn.y, mn.z, mx.x, mx.y, mx.z)) end
    end
    return true
end

re.on_application_entry("UpdateMotion", function()
    if done then return end
    frames = frames + 1
    if frames < 120 then return end   -- let the scene settle
    if not go then make(); if not go then done = true; log.info(TAG .. " could not make the object"); return end end
    local back = nil
    pcall(function() back = comp:call("getMesh") end)
    if not back and mesh_h and frames % 60 == 0 then pcall(function() comp:call("setMesh", mesh_h) end); pcall(function() back = comp:call("getMesh") end) end
    if back and mat_h and frames % 60 == 0 then
        local n, mr, rd = nil, nil, nil
        pcall(function() n = comp:call("get_MaterialNum") end)
        if (n or 0) == 0 then pcall(function() comp:call("set_Material", mat_h) end); mat_set = true end
        pcall(function() n = comp:call("get_MaterialNum") end)
        pcall(function() mr = comp:call("get_MaterialReady") end)
        pcall(function() rd = comp:call("get_ReadyToDraw") end)
        log.info(TAG .. string.format(" frame %d: materials %s, material ready %s, ready to draw %s", frames, tostring(n), tostring(mr), tostring(rd)))
    end
    if back and probe() then
        done = true
    elseif frames > WAIT_FRAMES then
        done = true
        log.info(TAG .. " gave up: mesh " .. tostring(back ~= nil))
    end
    if done and go then pcall(function() go:call("destroy", go) end); log.info(TAG .. " done") end
end)
log.info(TAG .. " loaded")
