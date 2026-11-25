-- visceral_re8_gl_rounds.lua -- the GM 79's spent shell as our own model, and a coloured band on every live and spent round
-- (2026-11-25, Tefa: "can you copy the shell from the game in blender and have it actually look spent so it's just a shell
-- without the live front part, and use that in game? ... i thought it would be great to have a coloured band over different
-- ammo types - red is explosive, blue is flash"; then the band "as a filler for the bases, on both spent and live shells",
-- worn factory paint; Village has two rounds: explosive gold, flash blue).
--
-- Our files (natives/stm/visceral/, built by tools/blender/build_gm79_spent_shell.py and tools/mdf_build_gm79_shells.py):
--   gm79_spent_shell.mesh   the game's own empty case, scorched inside, with the band in the groove at its base
--   gm79_round_band.mesh    the band alone, put on the gun's own live round
--   gm79_shell_<type>.mdf2  the materials, one file per round type (the band's colour)
-- Both meshes are in the gun's grenade joint's (Ammo01) own frame, so each is drawn by giving our object that joint's pose.
--
-- What is drawn when (the plugin says, breech.cpp; bridge slots 280-281 S_GL_ROUND, 217-225 S_SHELL2_*):
--   the joint shows a LIVE round (barrel or hand)      -> our band on it, in the loaded round's colour
--   the joint shows the SPENT case (barrel, pulled, in the empty hand) -> our spent shell on the joint, the game's hidden
--   a live round in the hand AND the spent case out    -> the spent shell where the plugin's S_SHELL2 slots put it (it was a
--                                                         copy of the gun, visceral_re8_shell2.lua, which never showed it)
-- The round's type is the gun's own bullet item (getBulletItemID), named by shell_bands.json "re8.ammo"; the spent shell
-- keeps the colour of the round that was fired.
-- Test with no gun: reframework/data/visceral_re8/gl_rounds_test.json {"front": true, "kind": "spent"|"band", "type": "flash"}
-- floats one 0.35 m in front of the camera (read once a second).

if reframework:get_game_name() ~= "re8" then return end

local TAG = "[visceral-re8-gl-rounds]"
local function L(s) log.info(TAG .. " " .. s) end
local told = {}
local function once(key, s) if not told[key] then told[key] = true; L(s) end end
local function safe(f) local ok, v = pcall(f); if ok then return v end end

local GUN = 3023                                  -- the GM 79
local S_FRAME, S_WEAPON_NUM = 0, 97
local S_SHELL2_ON, S_SHELL2_POS, S_SHELL2_ROT, S_SHELL2_SIZE = 217, 218, 221, 225
local S_GL_ROUND, S_GL_ROUND_ON = 280, 281
local STALE_FRAMES = 3
local JOINT = "Ammo01"
local HIDE_SCALE = 0.0005                         -- the game's own case while ours is drawn over it
local MESH_SPENT, MESH_BAND = "visceral/gm79_spent_shell.mesh", "visceral/gm79_round_band.mesh"
local function mdf_path(t) return "visceral/gm79_shell_" .. t .. ".mdf2" end
local BANDS_FILE, TEST_FILE = "visceral_re8/shell_bands.json", "visceral_re8/gl_rounds_test.json"

-- ===== round types (shell_bands.json "re8.ammo": type -> bullet item ids) =====
local by_id, types = {}, { "explosive" }
do
    local ok, d = pcall(json.load_file, BANDS_FILE)
    if ok and type(d) == "table" and type(d.re8) == "table" and type(d.re8.ammo) == "table" then
        types = {}
        for t, ids in pairs(d.re8.ammo) do
            types[#types + 1] = t
            for _, id in ipairs(ids) do by_id[math.floor(id)] = t end
        end
        L("round types: " .. table.concat(types, ", "))
    else
        once("nobands", "shell_bands.json not found: every round gets the explosive band")
    end
end
local function type_of(id)
    if id == nil then return "explosive" end
    local t = by_id[math.floor(id)]
    if t == nil then once("unknown" .. tostring(id), "bullet item " .. tostring(id) .. " is not in shell_bands.json: the explosive band (add it under re8.ammo)"); return "explosive" end
    return t
end

-- ===== small maths (x, y, z, w) =====
local function qmul(a, b)
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end
local function qinv(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end
local function qrot(q, v) local p = qmul(qmul(q, { x = v.x, y = v.y, z = v.z, w = 0 }), qinv(q)); return { x = p.x, y = p.y, z = p.z } end
local function qnorm(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-6 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end

-- ===== the game's pieces =====
local mk_go = safe(function() return sdk.find_type_definition("via.GameObject"):get_method("create(System.String)") end)
local mk_go_in = safe(function() return sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)") end)
local function spawn_folder()
    local scene = safe(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        return sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    end)
    if scene == nil then return nil end
    for _, name in ipairs({ "ModdedTemporaryObjects", "Debug", "Master" }) do
        local f = safe(function() return scene:call("findFolder", name) end)
        if f then return f end
    end
end
local res_cache = {}
local function resource(kind, path)
    local key = kind .. "|" .. path
    if res_cache[key] == nil then
        local r = safe(function() local x = sdk.create_resource(kind, path); return x and x:add_ref() end)
        res_cache[key] = r or false
        L(string.format("%s %s: %s", kind, path, r and "loaded" or "NOT FOUND (is the loose-file loader on, and the file in natives/stm/visceral?)"))
    end
    return res_cache[key] or nil
end
local function the_gun()   -- the held gun (as visceral_re8_shell2.lua finds it): its Mesh, Transform and component
    local vr = rawget(_G, "re8vr")
    local w = vr and safe(function() return vr.weapon end)
    if w == nil then return nil end
    local mesh = safe(function() return w:get_field("Mesh") end)
    local go = safe(function() return w:call("get_GameObject") end) or safe(function() return w:call("get_owner") end)
    if mesh == nil and go then mesh = safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh")) end) end
    local xf = go and safe(function() return go:call("get_Transform") end)
    return { w = w, mesh = mesh, xf = xf }
end
local function bullet_type(gun)
    local id = gun and (safe(function() return gun.w:call("getBulletItemID()") end) or safe(function() return gun.w:call("getBulletItemID") end))
    if id ~= nil and told["id" .. tostring(id)] == nil then told["id" .. tostring(id)] = true; L("the GM 79's bullet item id is " .. tostring(id) .. " -> " .. type_of(id)) end
    return type_of(id)
end
local function copy_render_settings(src, dst)   -- as visceral_re8_shell2.lua: drawn in the arms' and gun's own layer
    local td = safe(function() return sdk.find_type_definition("via.render.Mesh") end)
    if td == nil or src == nil or dst == nil then return end
    local skip = { Mesh = true, Material = true, Enabled = true, PartsEnable = true, GameObject = true, Owner = true, Transform = true }
    for _, m in ipairs(safe(function() return td:get_methods() end) or {}) do
        local name = safe(function() return m:get_name() end) or ""
        local prop = name:match("^get_(.+)$")
        if prop and not skip[prop] and safe(function() return m:get_num_params() end) == 0 then
            local rt = safe(function() return m:get_return_type() end)
            if rt ~= nil and safe(function() return rt:is_value_type() end) == true and safe(function() return td:get_method("set_" .. prop) end) then
                local a = safe(function() return src:call(name) end)
                if type(a) == "boolean" or type(a) == "number" then pcall(function() dst:call("set_" .. prop, a) end) end
            end
        end
    end
end

-- ===== our two objects =====
local objs = {}   -- kind ("spent" / "band") -> { go, xf, mesh, rtype, parent, shown }
local function destroy(kind)
    local o = objs[kind]
    if o and o.go then pcall(function() o.go:call("destroy", o.go) end) end
    objs[kind] = nil
end
local function make(kind, gun)
    local res = resource("via.render.MeshResource", kind == "spent" and MESH_SPENT or MESH_BAND)
    if res == nil or (mk_go == nil and mk_go_in == nil) then return nil end
    local folder = spawn_folder()
    local go = safe(function()
        if folder and mk_go_in then return mk_go_in:call(nil, "visceral_gm79_" .. kind, folder) end
        return mk_go:call(nil, "visceral_gm79_" .. kind)
    end)
    if go == nil then once("nogo", "could not make an object"); return nil end
    pcall(function() go = go:add_ref() end)
    pcall(function() go:call(".ctor") end)
    local mc = safe(function()
        local c = go:call("createComponent(System.Type)", sdk.typeof("via.render.Mesh"))
        if c then c = c:add_ref(); c:call(".ctor()") end
        return c
    end)
    if mc == nil or not pcall(function() mc:call("setMesh", res) end) then
        once("nomesh" .. kind, kind .. ": the object took no mesh"); pcall(function() go:call("destroy", go) end); return nil
    end
    if gun and gun.mesh then copy_render_settings(gun.mesh, mc) end
    pcall(function() mc:call("set_Enabled", true) end)
    pcall(function() go:call("setActive", true) end)
    local o = { go = go, xf = safe(function() return go:call("get_Transform") end), mesh = mc, shown = false }
    if o.xf == nil then pcall(function() go:call("destroy", go) end); return nil end
    L(kind .. ": our object made")
    return o
end
local function get(kind, gun)
    local o = objs[kind]
    if o and safe(function() return o.go:call("get_Valid") end) == false then objs[kind] = nil; o = nil end
    if o == nil then o = make(kind, gun); objs[kind] = o end
    return o
end
local function paint(o, kind, t)
    if o.rtype == t then return end
    local mdf = resource("via.render.MeshMaterialResource", mdf_path(t))
    if mdf and pcall(function() o.mesh:call("set_Material", mdf) end) then o.rtype = t; L(kind .. ": the " .. t .. " band") end
end
local function show(o, on)
    if o == nil or o.shown == on then return end
    pcall(function() o.go:call("set_DrawSelf", on) end)
    o.shown = on
end
-- hang it under the gun (so it goes wherever the gun is drawn later, as the shell copy learned on 2026-11-13), at (p, q)
-- in the gun's space
local function place_in_gun(o, gun, p, q, k)
    if o.parent ~= gun.xf then
        if pcall(function() o.xf:call("set_Parent", gun.xf) end) then o.parent = gun.xf end
    end
    pcall(function()
        o.xf:call("set_LocalPosition", Vector3f.new(p.x, p.y, p.z))
        o.xf:call("set_LocalRotation", Quaternion.new(q.w, q.x, q.y, q.z))
        o.xf:call("set_LocalScale", Vector3f.new(k, k, k))
    end)
end
-- the gun's grenade joint, in the gun's space
local joint, joint_of = nil, nil
local function joint_in_gun(gun)
    if joint_of ~= gun.xf then joint = safe(function() return gun.xf:call("getJointByName", JOINT) end); joint_of = gun.xf end
    if joint == nil then once("nojoint", "the GM 79 has no " .. JOINT .. " joint"); return nil end
    local jp, jr = safe(function() return joint:call("get_Position") end), safe(function() return joint:call("get_Rotation") end)
    local gp, gr = safe(function() return gun.xf:call("get_Position") end), safe(function() return gun.xf:call("get_Rotation") end)
    if not (jp and jr and gp and gr) then return nil end
    local giq = qinv(qnorm({ x = gr.x, y = gr.y, z = gr.z, w = gr.w }))
    local p = qrot(giq, { x = jp.x - gp.x, y = jp.y - gp.y, z = jp.z - gp.z })
    local q = qnorm(qmul(giq, { x = jr.x, y = jr.y, z = jr.z, w = jr.w }))
    return p, q
end
local hidden = false
local function hide_game_round(on)
    if joint == nil or hidden == on then return end
    local s = on and HIDE_SCALE or 1.0
    if pcall(function() joint:call("set_LocalScale", Vector3f.new(s, s, s)) end) then hidden = on end
end

-- ===== every frame =====
local test = { front = false, kind = "spent", type = "explosive" }
local test_t, live_t, spent_t, last_shows = 0, "explosive", "explosive", 0
local function read_test()
    local okf, fh = pcall(io.open, TEST_FILE, "r")
    if not okf or not fh then test.front = false; return end
    fh:close()
    local ok, d = pcall(json.load_file, TEST_FILE)
    if ok and type(d) == "table" then
        local f, k, t = d.front == true, d.kind == "band" and "band" or "spent", type(d.type) == "string" and d.type or "explosive"
        if f ~= test.front or k ~= test.kind or t ~= test.type then L("test: front " .. tostring(f) .. ", " .. k .. ", " .. t) end
        test.front, test.kind, test.type = f, k, t
    end
end
local function all_off()
    show(objs.spent, false); show(objs.band, false); hide_game_round(false)
end

local function update(point)
    local now = os.clock()
    if now - test_t > 1.0 then test_t = now; read_test() end
    if test.front then   -- TEST: one of ours in front of the game camera
        local cx = safe(function() return sdk.get_primary_camera():call("get_GameObject"):call("get_Transform") end)
        local cp, cr = cx and safe(function() return cx:call("get_Position") end), cx and safe(function() return cx:call("get_Rotation") end)
        local o = get(test.kind, the_gun())
        if o and cp and cr then
            if o.parent ~= nil then pcall(function() o.xf:call("set_Parent", nil) end); o.parent = nil end
            paint(o, test.kind, test.type)
            local cq = qnorm({ x = cr.x, y = cr.y, z = cr.z, w = cr.w })
            local f = qrot(cq, { x = 0, y = 0, z = -1 })
            pcall(function()
                o.xf:call("set_Position", Vector3f.new(cp.x + f.x * 0.35, cp.y + f.y * 0.35, cp.z + f.z * 0.35))
                o.xf:call("set_Rotation", Quaternion.new(cr.w, cr.x, cr.y, cr.z))
                o.xf:call("set_LocalScale", Vector3f.new(1, 1, 1))
            end)
            show(o, true)
        end
        return
    end
    local b = rawget(_G, "visceral_re8_bridge")
    if b == nil or not b.ready() then all_off(); return end
    local frame = b.r(S_FRAME)
    local fresh = math.abs(b.r(S_GL_ROUND_ON) - 1.0 - frame) <= STALE_FRAMES and b.r(S_GL_ROUND_ON) > 0.5
    if math.floor(b.r(S_WEAPON_NUM) + 0.5) ~= GUN or not fresh then
        all_off()
        if objs.spent or objs.band then destroy("spent"); destroy("band"); joint, joint_of, hidden = nil, nil, false end
        return
    end
    if point == "late" then return end   -- after the plugin has placed the joint (as the shell copy: never before the arms)
    local gun = the_gun()
    if gun == nil or gun.xf == nil then all_off(); return end
    local shows = math.floor(b.r(S_GL_ROUND) + 0.5)
    if shows == 1 then live_t = bullet_type(gun) end
    if shows == 2 and last_shows == 1 then spent_t = live_t; L("fired (or the spent case is out): the spent shell keeps the " .. spent_t .. " band") end
    last_shows = shows
    local jp, jq = joint_in_gun(gun)
    -- the spent shell: on the joint (the game's case hidden under it), or where the plugin puts it beside a live one in the hand
    local copy_on = math.abs(b.r(S_SHELL2_ON) - 1.0 - frame) <= STALE_FRAMES and b.r(S_SHELL2_ON) > 0.5
    local sp, sq, sk = nil, nil, 1.0
    if shows == 2 and jp then sp, sq = jp, jq
    elseif copy_on then
        sp = { x = b.r(S_SHELL2_POS), y = b.r(S_SHELL2_POS + 1), z = b.r(S_SHELL2_POS + 2) }
        sq = qnorm({ x = b.r(S_SHELL2_ROT), y = b.r(S_SHELL2_ROT + 1), z = b.r(S_SHELL2_ROT + 2), w = b.r(S_SHELL2_ROT + 3) })
        local k = b.r(S_SHELL2_SIZE); if k > 0.05 and k < 5.0 then sk = k end
    end
    if sp then
        local o = get("spent", gun)
        if o then paint(o, "spent", spent_t); place_in_gun(o, gun, sp, sq, sk); show(o, true) end
    else
        show(objs.spent, false)
    end
    hide_game_round(shows == 2 and objs.spent ~= nil and objs.spent.shown)
    -- the band on the live round
    if shows == 1 and jp then
        local o = get("band", gun)
        if o then paint(o, "band", live_t); place_in_gun(o, gun, jp, jq, 1.0); show(o, true) end
    else
        show(objs.band, false)
    end
end

re.on_application_entry("LateUpdateBehavior", function() local ok, e = pcall(update, "late"); if not ok then once("err", "update failed: " .. tostring(e)) end end)
re.on_application_entry("PrepareRendering", function() local ok, e = pcall(update, "prep"); if not ok then once("err2", "update failed: " .. tostring(e)) end end)
re.on_pre_application_entry("BeginRendering", function() local ok, e = pcall(update, "begin"); if not ok then once("err3", "update failed: " .. tostring(e)) end end)

L("loaded")
