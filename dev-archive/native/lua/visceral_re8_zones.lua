-- visceral_re8_zones.lua -- the grab zones, seen and set from the menu (2026-10-25, Tefa: "is there any way I can visibly set
-- them, how big they are, where they are on the gun ... a helper program that translates numbers into actual sliders and
-- movable areas that ride the gun all the time").
--
-- The plugin (src/zones.cpp) tells this file, every frame, where each zone is RIGHT NOW in the world and how big it is
-- (bridge slots 116-135): the magazine grab, the well (where the magazine goes in), the slide / pump / bolt, and the point the
-- hand is measured from. This file draws a ball at each one (a game mesh scaled to the zone's size, riding the gun), and shows
-- sliders in the REFramework menu ("Visceral RE8 grab zones") that move and resize them. The sliders write
-- reframework/data/visceral_re8/zones.json; the plugin re-reads it at once, so the ball and the real test move together.
--
-- zones.json: { "default": { "mag": {x,y,z,r}, "well": {...}, "slide": {...}, "pump": {...}, "bolt": {...} },
--               "3042": { ... the same, for one gun (its number) ... }, "_visual": { "half_m": 0.05 } }
-- x, y, z: metres from the zone's own joint, in the gun's axes; r: the radius in metres. A missing number keeps the plugin's own.
-- "_visual": { "half_m": the ball model's half size, "show": true = draw the balls }.
--
-- The same numbers can be set from outside the game with the Grab Zones window (zones-app/, a desktop window Window View can
-- hang in the headset, Tefa 2026-10-25: "a separate thing just like you did with the hand poser"). For it this file writes
-- visceral_re8/zones_state.json four times a second (the gun in hand, each zone's size and how far the hand is from it), and
-- re-reads zones.json twice a second, so a save from the window shows here at once.

local TAG = "[visceral-re8-zones]"
local FILE = "visceral_re8/zones.json"
local STATE_FILE = "visceral_re8/zones_state.json"
local STATE_EVERY_S, RELOAD_EVERY_S, EDIT_QUIET_S = 0.25, 0.5, 0.6
local S_WEAPON_NUM, S_ZONE_SHOW, S_ZONE_SEQ, S_ZONES = 97, 114, 115, 116
local ZONES = {
    { i = 0, key = "mag",  label = "Grab the magazine (left grip on it)" },
    { i = 1, key = "well", label = "The well: where a magazine goes in" },
    { i = 2, key = "part", label = "The slide / pump / bolt (left grip on it)" },
    { i = 3, key = "hand", label = "The point the hand is measured from" },
    { i = 4, key = "grip", label = "The front grip: this gun's kept grip spot (left grip in it takes the gun two-handed)" },
    -- the hand pair picked in the Grab Zones window (src/pairs.h, 2026-10-25): the big sphere = where the left grip activates it,
    -- the small dot = where the hand lands, and a dotted line from one to the other. Not in this menu (the window edits them)
    { i = 5, key = "pair-act", pair = true },
    { i = 6, key = "pair-land", pair = true },
    { i = 7, key = "pair-dot", pair = true }, { i = 8, key = "pair-dot", pair = true },
    { i = 9, key = "pair-dot", pair = true }, { i = 10, key = "pair-dot", pair = true },
}
local S_PAIR_ACT, S_PAIR_LAND = 142, 147   -- written by the plugin: {x, y, z, r, on} each
local PAIR_DOTS, PAIR_DOT_R = 4, 0.008     -- the dotted line: this many beads, this big (m)
-- 23:20 (Tefa: "the start sphere did not grow or shrink with size change ... when i did move one the other sphere moved with it
-- as well, just a different amount and i could not see the dotted line"): the log had every size right (start r 0.14,
-- scale 1.34; dots scale 0.075), so the drawn spheres do not follow their scale; the beads then drew as big as the ends and
-- looked like a second sphere sliding. Off until the drawn size follows the number
local PAIR_DOTS_SHOWN = false
local PART_NAMES = { [1] = "slide", [2] = "pump", [3] = "bolt" }
local AXES = { { k = "z", label = "forward (+) / back (-), cm" }, { k = "y", label = "up (+) / down (-), cm" }, { k = "x", label = "right (+) / left (-), cm" } }
-- the sphere: a primitive sphere that ships with Village (its file list, RE8_STM_Release.list), the first that really loads.
-- 2026-10-25 first wear: "i can't actually see any points on the gun": the first version asked for our own sphere mesh, which
-- was never made; create_resource still handed back an object, setMesh threw inside the game, and every sphere was empty.
-- Now a mesh only counts once getMesh gives it back. Its material comes from Village's shared effect materials
-- (vfx/mesh/mesh_common_mtr, made for these primitive shapes); which one shows is not known yet, so "SPHERE LOOK" cycles them.
-- 12:15 (third wear, Tefa: "i went through all the sphere designs and nothing showed"): the log had every sphere SHOWN at the
-- gun, at the right size (half 0.566 m measured), so they existed but drew nothing: an RE Engine mesh only draws with a material
-- whose names match its own slots, and the shared effect materials did not. Village ships a development "test ball" WITH its
-- own material (environment/props/resource/sm0x/sm00_111_testball), so that is the sphere now, in its own material ("its
-- own" look, the first); two balloons with their own materials are the fall-backs; the bare primitives come last.
-- 13:50 (fifth wear, the test ball switched on fully, still nothing): Andyalpa's holster visuals, which DO draw, copy the held
-- weapon's own mesh and material holders, already loaded by the game; every mesh loaded fresh from a path has drawn nothing in
-- five tries. So first choice is now "GUN": each zone is a small copy of the gun in hand, in its own material. It is made only
-- once a gun is in hand. If even that draws nothing, the fault is not the mesh.
-- 14:23 (Tefa: "yessss!!! guns everywhere"): the gun copies SHOWED once the spheres were made in the update step, so the
-- mesh was never the fault. The round test ball is first again; zones.json "_visual": { "shape": "gun" } brings the guns back.
local MESHES = { "environment/props/resource/sm0x/sm00_111_testball/sm00_111_testball_00.mesh", "GUN",
                 "_ge/environment/props/resource/sm5x/sm59_162_balloon/sm59_162_balloon_00.mesh",
                 "_ge/environment/props/resource/sm5x/sm59_169_balloon/sm59_169_balloon_00.mesh",
                 "vfx/mesh/mesh_primitive/sphere_mediumpolygon.mesh", "vfx/mesh/mesh_primitive/sphere.mesh" }
-- 2026-10-25 (Tefa: "can you just have the one look and not be able to choose anything else?"): the spheres always wear the
-- "axis" material, the one seen drawing; the look buttons (here and in the Grab Zones window) are gone
local MATS = { "systems/effect/vfx_default_axis.mdf2" }
local MAT_NAMES = { "axis" }
-- 2026-10-25 22:06 (Tefa: "when i clicked on the next one, no solid shape it was i think, the game crashed"): "no material"
-- is gone from the cycle. Picking it threw every sphere away and made them again, and the remake's setMesh threw inside the
-- game five times (the log, 22:06:26) and then the game crashed (re8.exe+0x415879c). Kept log and dump: D:/RE Village
-- REFramework builds/logs/*2026-10-25-2206*. A saved look past the end falls back to the first (mat_index).
local cfg = nil
local seq = 0
local last_state_t, last_reload_t, last_edit_t = 0, 0, -10
local edit_defaults = false
local balls = {}          -- i -> { go, xform, on }
local mesh_holders, mesh_failed = {}, {}  -- path -> its holder; paths that failed once (never retried)
-- 14:40 (Tefa: "handguns were showing instead of spheres"): on a fresh game start the ball's model was not loaded yet the first
-- time it was asked for (create_resource starts the loading; the mesh only comes back once it is in), so it counted as "did
-- not load" and the gun copy (the pistol in hand) stood in. A mesh is now waited for, MESH_WAIT_S, before the next one is tried
local MESH_WAIT_S = 10.0
local mesh_first_try = {}                -- path -> when it was first asked for
local mesh_used, mesh_half = nil, nil     -- the sphere mesh that loaded, and its measured half size (m)
local mat_res, mat_applied = {}, {}      -- material index -> resource; ball index -> the material it wears
local spawn_tried = false
local last_respawn_t, last_where_t = -10, -10
local UNMEASURED_HALF_M = 0.5   -- until the model is measured: a 1 m primitive (the usual size) is drawn at its zone's size
local status = "not drawn yet"

local function bridge() local b = rawget(_G, "visceral_re8_bridge"); if b ~= nil and b.ready() then return b end; return nil end
local function load()
    cfg = nil
    pcall(function() cfg = json.load_file(FILE) end)
    if type(cfg) ~= "table" then cfg = {} end
    if type(cfg["_visual"]) ~= "table" then cfg["_visual"] = {} end
end
local function show_on() return cfg and type(cfg["_visual"]) == "table" and cfg["_visual"].show == true end
local function save()
    last_edit_t = os.clock()
    pcall(function() json.dump_file(FILE, cfg) end)
    seq = seq + 1
    local b = bridge()
    if b then b.w(S_ZONE_SEQ, seq) end
end
load()

-- ---- the numbers of one zone, as the plugin resolves them: gun over default (nil = the plugin's built-in) -------------------
local function gun_num(b) local n = b and b.r(S_WEAPON_NUM) or 0; return math.floor((n or 0) + 0.5) end
local function group_name(b) if edit_defaults then return "default" end; local n = gun_num(b); return n > 0 and tostring(n) or "default" end
local function entry(group, key, make)
    if type(cfg[group]) ~= "table" then if not make then return nil end; cfg[group] = {} end
    if type(cfg[group][key]) ~= "table" then if not make then return nil end; cfg[group][key] = {} end
    return cfg[group][key]
end
local function zone_key(z, b)
    if z.key ~= "part" then return z.key end
    local on = b and b.r(S_ZONES + 2 * 5 + 4) or 0
    return PART_NAMES[math.floor((on or 0) + 0.5)] or "slide"
end
local function raw5(b, s) return b.r(s), b.r(s + 1), b.r(s + 2), b.r(s + 3), b.r(s + 4) end
local function live(b, i)   -- x, y, z, r, on of zone i from the plugin (5 and up: the shown hand pair)
    if i < 5 then return raw5(b, S_ZONES + i * 5) end
    if i == 5 then return raw5(b, S_PAIR_ACT) end
    if i == 6 then return raw5(b, S_PAIR_LAND) end
    if not PAIR_DOTS_SHOWN then return nil, nil, nil, 0, 0 end
    local ax, ay, az, _, aon = raw5(b, S_PAIR_ACT)
    local lx, ly, lz, _, lon = raw5(b, S_PAIR_LAND)
    if not (ax and lx and aon and lon) then return nil, nil, nil, 0, 0 end
    local t = (i - 6) / (PAIR_DOTS + 1)
    return ax + (lx - ax) * t, ay + (ly - ay) * t, az + (lz - az) * t, PAIR_DOT_R, math.min(aon, lon)
end

-- ---- the balls --------------------------------------------------------------------------------------------------------------
local function alive(o)
    if not o then return false end
    local ok, v = pcall(function() return sdk.is_valid_obj and sdk.is_valid_obj(o) end)
    if ok and v == false then return false end
    local ok2, addr = pcall(function() return o:get_address() end)
    return ok2 and addr ~= nil and addr ~= 0
end
-- a resource wrapped in the holder the game's setters take. 11:39 (second try): setMesh was handed the bare resource and the
-- game read garbage inside setMesh (access violation, caught by REFramework, 30 times); Mesh.setMesh / set_Material take a
-- via.render.MeshResourceHolder / MeshMaterialResourceHolder (REFramework: resource:create_holder)
local function holder(path, kind, holder_type)
    local h = nil
    pcall(function()
        local res = sdk.create_resource(kind, path)
        if res then res = res:add_ref(); h = res:create_holder(holder_type) end
        if h then h = h:add_ref() end
    end)
    return h
end
local function find_folder()
    local scene = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        if sm then scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene") end
    end)
    if not scene then return nil end
    for _, name in ipairs({ "ModdedTemporaryObjects", "Debug", "Master" }) do
        local f = nil
        pcall(function() f = scene:call("findFolder", name) end)
        if f then return f end
    end
    return nil
end
local function mat_index() return 0 end   -- one look only (2026-10-25)
local function apply_mat(i, ball)
    if ball.gun_copy then return end
    local m = mat_index()
    if mat_applied[i] == m then return end
    mat_applied[i] = m
    local path = MATS[m + 1]
    if path == "" then return end      -- "no material": the mesh's own (none) stays; respawning clears a set one
    if path == "OWN" then path = (mesh_used or ""):gsub("%.mesh$", ".mdf2") end   -- the material made for this very mesh
    if mat_res[m] == nil then mat_res[m] = holder(path, "via.render.MeshMaterialResource", "via.render.MeshMaterialResourceHolder") or false end
    if mat_res[m] then pcall(function() ball.comp:call("set_Material", mat_res[m]) end) end
end
-- the mesh's half size, from its own bounding box, so a sphere is drawn exactly as big as its zone
local function measure(comp)
    local half = nil
    pcall(function()
        comp:call("updateBoundingBox")
        local la = comp:call("get_ModelLocalAABB")
        if la then
            local mn, mx = la:get_field("minpos"), la:get_field("maxpos")
            if mn and mx then half = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) / 2 end
        end
    end)
    if half and half > 0.0005 and half < 100 then return half end
    return nil
end
-- the held weapon's own via.render.Mesh component (the holster visuals' H.get_weapon_mesh_component, in short)
local function weapon_mesh()
    local w = rawget(_G, "re8vr"); w = w and w.weapon or nil
    if not w then return nil end
    local mesh = nil
    pcall(function() mesh = w:get_field("Mesh") end)
    if mesh then return mesh end
    local go = nil
    pcall(function() go = w:call("get_GameObject") end)
    if not go then return nil end
    pcall(function() mesh = go:call("getComponent(System.Type)", sdk.find_type_definition("via.render.Mesh"):get_runtime_type()) end)
    return mesh
end
local function spawn(i)
    local td = sdk.find_type_definition("via.GameObject")
    local mk2 = td and td:get_method("create(System.String, via.Folder)") or nil
    local mk1 = td and td:get_method("create(System.String)") or nil
    if not mk1 and not mk2 then status = "no GameObject.create"; return nil end
    local folder = find_folder()
    local go = nil
    pcall(function()
        if folder and mk2 then go = mk2:call(nil, "visceral_re8_zone_" .. i, folder) elseif mk1 then go = mk1:call(nil, "visceral_re8_zone_" .. i) end
    end)
    if not go then status = "GameObject.create failed"; return nil end
    pcall(function() go = go:add_ref() end)
    pcall(function() go:call(".ctor") end)   -- as the holster visuals do
    local mesh_td = sdk.find_type_definition("via.render.Mesh")
    local comp = nil
    pcall(function()
        comp = go:call("createComponent(System.Type)", mesh_td:get_runtime_type())
        if comp then comp = comp:add_ref(); comp:call(".ctor()") end
    end)
    if not comp then status = "no mesh component"; pcall(function() go:call("destroy", go) end); return nil end
    local tries = mesh_used and { mesh_used } or MESHES
    if not mesh_used and cfg and type(cfg["_visual"]) == "table" and cfg["_visual"].shape == "gun" then tries = { "GUN" } end
    local got, gun_copy, waiting = nil, false, nil
    for _, path in ipairs(tries) do
        if path == "GUN" then
            local wm = weapon_mesh()
            local h, m = nil, nil
            if wm then pcall(function() h = wm:call("getMesh") end); pcall(function() m = wm:call("get_Material") end) end
            if h then
                pcall(function() comp:call("setMesh", h) end)
                if m then pcall(function() comp:call("set_Material", m) end) end
                local back = nil
                pcall(function() back = comp:call("getMesh") end)
                if back ~= nil then got = path; gun_copy = true; break end
            end
            if i == 0 then log.info(TAG .. " sphere from the gun in hand: " .. (wm and (h and "setMesh gave nothing back" or "no mesh holder on the weapon") or "no weapon mesh") .. ", trying the sphere files") end
        elseif not mesh_failed[path] then
            -- 14:32 (Tefa changed the look, the spheres were made again and none came back: "sphere mesh ...testball...: did
            -- not load", then nothing): the holder kept from the first making had gone stale. The kept one is tried, then a
            -- fresh one, and a mesh that ever loaded is never written off
            local fresh = holder(path, "via.render.MeshResource", "via.render.MeshResourceHolder")
            local tries_h = { mesh_holders[path], fresh }
            for _, h in ipairs(tries_h) do
                if h and not got then
                    pcall(function() comp:call("setMesh", h) end)
                    local back = nil
                    pcall(function() back = comp:call("getMesh") end)
                    if back ~= nil then got = path; mesh_holders[path] = h end
                end
            end
            if got then break end
            if not mesh_holders[path] then mesh_holders[path] = fresh end   -- kept, so the loading goes on
            mesh_first_try[path] = mesh_first_try[path] or os.clock()
            if os.clock() - mesh_first_try[path] < MESH_WAIT_S then waiting = path; break end   -- still loading: ask again in a second
            if path ~= mesh_used then mesh_failed[path] = true end   -- never asked again: a failed setMesh is an error inside the game
            log.info(TAG .. " sphere mesh " .. path .. ": did not load in " .. MESH_WAIT_S .. " s")
        end
    end
    if not got and waiting then status = "the sphere model is still loading"; pcall(function() go:call("destroy", go) end); return nil end
    if not got then status = "no sphere mesh would load (see the log)"; pcall(function() go:call("destroy", go) end); mesh_used = nil; return nil end
    if not mesh_used then
        mesh_used = got
        mesh_half = measure(comp)
        log.info(TAG .. " sphere mesh: " .. got .. ", half size " .. tostring(mesh_half))
    end
    -- 13:12 (fourth wear: SHOWN at the gun, the right size, every look, still nothing seen): a Mesh component made from
    -- script draws only once it is enabled, set to draw by default, and sent to every render output; Andyalpa's holster
    -- visuals (re8_vr_holster_visuals.lua clear_mesh_depth_ignore, set_output_all) switch all three on, this never did
    pcall(function() comp:call("set_Enabled", true) end)
    pcall(function() comp:call("set_DrawDefault", true) end)
    pcall(function()
        local et = sdk.find_type_definition("via.render.RenderOutputID")
        local f = et and et:get_field("All")
        comp:call("set_RenderOutputID", f and f:get_data(nil) or 31)
    end)
    pcall(function() comp:call("set_IgnoreDepth", false) end)
    pcall(function() go:call("set_DrawSelf", true) end)
    pcall(function() go:call("set_UpdateSelf", true) end)
    if i == 0 then
        local e, dd, out, ds, act = "?", "?", "?", "?", "?"
        pcall(function() e = tostring(comp:call("get_Enabled")) end)
        pcall(function() dd = tostring(comp:call("get_DrawDefault")) end)
        pcall(function() out = tostring(comp:call("get_RenderOutputID")) end)
        pcall(function() ds = tostring(go:call("get_DrawSelf")) end)
        pcall(function() act = tostring(go:call("get_Active")) end)
        log.info(TAG .. " sphere 0 made: mesh enabled " .. e .. ", draw default " .. dd .. ", render output " .. out .. ", object draws " .. ds .. ", active " .. act)
    end
    local xform = nil
    pcall(function() xform = go:call("get_Transform") end)
    status = "drawn: " .. got:match("[^/]+$") .. ", look: " .. MAT_NAMES[mat_index() + 1]
    local ball = { go = go, comp = comp, xform = xform, on = false, gun_copy = gun_copy }
    if not gun_copy then apply_mat(i, ball) end   -- a gun copy wears the gun's own material
    return ball
end
local function set_on(ball, on)
    if ball.on == on or not alive(ball.go) then return end
    ball.on = on
    pcall(function() ball.go:call("setActive", on) end)
    pcall(function() ball.go:call("set_DrawSelf", on) end)
    if on and ball.comp then pcall(function() ball.comp:call("set_Enabled", true) end); pcall(function() ball.comp:call("set_DrawDefault", true) end) end
end
local function destroy_all()
    for i, ball in pairs(balls) do
        if alive(ball.go) then
            pcall(function() ball.go:call("setActive", false) end)
            pcall(function() ball.go:call("destroy", ball.go) end)
        end
        balls[i] = nil
        mat_applied[i] = nil
    end
    spawn_tried = false
end

-- 14:26 (Tefa, a screenshot: copies of the rifle and spheres hanging in the air where the gun had been): "Reset scripts" throws
-- this script's memory away but not the objects it made, so every reset left its spheres behind, frozen. They are destroyed
-- at a reset now, and any left by an older run (same names) are found and destroyed before the first making
local function sweep_leftovers()
    local scene = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        if sm then scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene") end
    end)
    if not scene then return end
    local n = 0
    for _, z in ipairs(ZONES) do
        for _ = 1, 20 do   -- several resets: several with one name
            local go = nil
            pcall(function() go = scene:call("findGameObject(System.String)", "visceral_re8_zone_" .. z.i) end)
            if not go then break end
            pcall(function() go:call("setActive", false) end)
            pcall(function() go:call("destroy", go) end)
            n = n + 1
        end
    end
    if n > 0 then log.info(TAG .. " " .. n .. " sphere(s) left by an earlier run destroyed") end
end
local swept = false
re.on_script_reset(function() destroy_all() end)

-- ---- THE GUN IN THE RIGHT HAND (2026-10-25, Tefa: "can i still tweak where the gun is pointing", then "all please") -------
-- praydog's VR mode places the right hand (and so the gun) at the controller turned by re8vr.right_hand_rotation_offset and
-- moved by re8vr.right_hand_position_offset (the controller's own axes: x right, y up, z back). zones.json "aim" (per gun over
-- "default", from the Grab Zones window's GUN IN THE RIGHT HAND box) turns and moves it further: pitch / yaw / roll in degrees
-- about the controller's axes, x / y / z in cm (z forward). The offsets as the VR mode set them are kept at load and are what
-- every adjustment is laid over, so nothing piles up; an all-zero aim puts them back exactly.
local aim_base_rot, aim_base_pos, aim_applied = nil, nil, nil
local function aim_capture()
    if aim_base_rot then return true end
    local v = rawget(_G, "re8vr")
    if not v then return false end
    pcall(function()
        local q, p = v.right_hand_rotation_offset, v.right_hand_position_offset
        if q and p then aim_base_rot = Quaternion.new(q.w, q.x, q.y, q.z); aim_base_pos = Vector4f.new(p.x, p.y, p.z, p.w) end
    end)
    return aim_base_rot ~= nil
end
local function axis_q(ax, ay, az, deg)
    local h = math.rad(deg or 0) / 2
    local s = math.sin(h)
    return Quaternion.new(math.cos(h), ax * s, ay * s, az * s)
end
local function aim_for(gun)
    local g = cfg and cfg[tostring(gun)]
    local a = type(g) == "table" and g.aim or nil
    if type(a) ~= "table" then local d = cfg and cfg["default"]; a = type(d) == "table" and d.aim or nil end
    return type(a) == "table" and a or nil
end
local function aim_tick(b)
    if not aim_capture() then return end
    local a = aim_for(gun_num(b)) or {}
    local p, y, r = tonumber(a.pitch) or 0, tonumber(a.yaw) or 0, tonumber(a.roll) or 0
    local x, u, f = tonumber(a.x) or 0, tonumber(a.y) or 0, tonumber(a.z) or 0
    local key = string.format("%.2f %.2f %.2f %.2f %.2f %.2f", p, y, r, x, u, f)
    if key == aim_applied then return end
    aim_applied = key
    local v = rawget(_G, "re8vr")
    pcall(function()
        local extra = (axis_q(0, 1, 0, y) * axis_q(1, 0, 0, p) * axis_q(0, 0, 1, r)):normalized()
        v.right_hand_rotation_offset = (extra * aim_base_rot):normalized()
        v.right_hand_position_offset = Vector4f.new(aim_base_pos.x + x / 100, aim_base_pos.y + u / 100, aim_base_pos.z - f / 100, aim_base_pos.w)
    end)
    log.info(TAG .. " the gun in the right hand: turned " .. string.format("%.1f / %.1f / %.1f deg, moved %.1f / %.1f / %.1f cm", p, y, r, x, u, f))
end
re.on_script_reset(function()   -- the VR mode's own offsets back, so a reset never leaves the gun turned
    local v = rawget(_G, "re8vr")
    if v and aim_base_rot then pcall(function() v.right_hand_rotation_offset = aim_base_rot; v.right_hand_position_offset = aim_base_pos end) end
end)

local function write_state(b)
    local st = { t = os.time(), gun = gun_num(b), zones = {} }
    local hx, hy, hz, _, hon = live(b, 3)
    for _, z in ipairs(ZONES) do
        if z.key ~= "hand" and not z.pair then
            local x, y, zz, r, on = live(b, z.i)
            local e = { key = zone_key(z, b), on = (on or 0) > 0.5, r_cm = (r or 0) * 100 }
            if e.on and (hon or 0) > 0.5 then e.hand_cm = math.sqrt((hx - x) ^ 2 + (hy - y) ^ 2 + (hz - zz) ^ 2) * 100 end
            st.zones[#st.zones + 1] = e
        end
    end
    pcall(function() json.dump_file(STATE_FILE, st) end)
end

-- 14:30 (sixth wear: even a copy of the held gun, switched fully on, SHOWN at the gun, was never seen): every sphere was made,
-- moved and switched in re.on_frame, the PRESENT step, after the game has gathered what to draw. Andyalpa's holster visuals,
-- which do draw, make and move theirs in the game's own update (on_application_entry "UpdateMotion"). So this runs there now
re.on_application_entry("UpdateMotion", function()
    local b = bridge()
    if not b then return end
    local now = os.clock()
    if now - last_reload_t > RELOAD_EVERY_S and now - last_edit_t > EDIT_QUIET_S then last_reload_t = now; load() end
    if now - last_state_t > STATE_EVERY_S then last_state_t = now; write_state(b) end
    aim_tick(b)
    local show = show_on()
    b.w(S_ZONE_SHOW, show and 1 or 0)
    if not show then
        if next(balls) ~= nil then destroy_all() end
        return
    end
    -- 11:50 (Tefa: "i still don't see any spheres"): the spheres were made at the title screen and the save's scene change
    -- destroyed them (findGameObject found none); now a dead sphere has them all made again, at most once a second
    if spawn_tried then
        for _, ball in pairs(balls) do
            if ball and not alive(ball.go) and now - last_respawn_t > 1.0 then
                last_respawn_t = now
                log.info(TAG .. " a sphere was destroyed (scene change): making them again")
                destroy_all()
                return
            end
        end
    end
    -- made once a gun is in hand (the gun copy needs one), at most once a second until one is made
    if not spawn_tried and gun_num(b) > 0 and now - last_respawn_t > 1.0 then
        last_respawn_t = now
        if not swept then swept = true; sweep_leftovers() end
        local any = false
        for _, z in ipairs(ZONES) do balls[z.i] = spawn(z.i); any = any or balls[z.i] ~= nil end
        spawn_tried = any
    end
    -- a new look picked: "no material" needs fresh spheres (a set material cannot be taken off), any other is put on
    local m = mat_index()
    if MATS[m + 1] == "" then
        for i, _ in pairs(balls) do if mat_applied[i] ~= nil and mat_applied[i] ~= m then destroy_all(); return end end
    end
    for i, ball in pairs(balls) do if ball then apply_mat(i, ball); status = "drawn: " .. (mesh_used or "?"):match("[^/]+$") .. ", look: " .. MAT_NAMES[m + 1] end end
    -- the measured size, unless the size fix in the menu was set by hand. The model's own box could not be read at spawn
    -- (11:48: "half size nil"), so it is measured from the drawn sphere's world box once it stands in the world
    if not mesh_half then
        for _, ball in pairs(balls) do
            if ball and ball.on and ball.scale then
                local w = nil
                pcall(function()
                    ball.comp:call("updateBoundingBox")
                    local wa = ball.comp:call("get_WorldAABB")
                    if wa then local mn, mx = wa:get_field("minpos"), wa:get_field("maxpos"); if mn and mx then w = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) / 2 end end
                end)
                if not w then w = measure(ball.comp) and measure(ball.comp) * ball.scale end
                if w and w > 0.0005 and w < 1000 then
                    mesh_half = w / ball.scale
                    log.info(TAG .. string.format(" sphere model measured in the world: half size %.4f m", mesh_half))
                    break
                end
            end
        end
    end
    local half = (cfg["_visual"].half_set and tonumber(cfg["_visual"].half_m)) or mesh_half or UNMEASURED_HALF_M
    if half < 0.005 then half = 0.005 end
    for _, z in ipairs(ZONES) do
        local ball = balls[z.i]
        if ball and alive(ball.go) and ball.xform then
            local x, y, zz, r, on = live(b, z.i)
            local ok = on and on > 0.5 and x ~= nil and math.abs(x) < 1.0e5
            set_on(ball, ok)
            if ok then
                local s = (r or 0.05) / half
                ball.scale = s
                pcall(function()
                    ball.xform:call("set_Position", Vector3f.new(x, y, zz))
                    ball.xform:call("set_Scale", Vector3f.new(s, s, s))
                end)
            end
        end
    end
    -- every 5 s while shown: where each sphere is, how big, and whether it is on, so a headset run can be read from the log
    if now - last_where_t > 5.0 then
        last_where_t = now
        local parts = {}
        for _, z in ipairs(ZONES) do
            local ball = balls[z.i]
            local x, y, zz, r, on = live(b, z.i)
            parts[#parts + 1] = string.format("%s %s r %.2f at %.2f %.2f %.2f scale %.3f", z.key, ball and (alive(ball.go) and (ball.on and "SHOWN" or "hidden") or "DEAD") or "none",
                r or 0, x or 0, y or 0, zz or 0, ball and ball.scale or 0)
        end
        log.info(TAG .. " spheres (half " .. string.format("%.3f", half) .. (mesh_half and " measured" or " guessed") .. ", look " .. MAT_NAMES[mat_index() + 1] .. "): " .. table.concat(parts, " | "))
    end
end)

-- ---- the menu ---------------------------------------------------------------------------------------------------------------
re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 grab zones") then return end
    local b = bridge()
    local c, v = imgui.checkbox("Show the zones on the gun (spheres that ride it)", show_on())
    if c then cfg["_visual"].show = v; save() end
    imgui.text("Also in the Grab Zones window on the desktop (for Window View in the headset).")
    imgui.text("Spheres: " .. status)
    if not b then imgui.text("(the bridge is not up: no gun readings)"); imgui.tree_pop(); return end
    local n = gun_num(b)
    imgui.text(n > 0 and ("Gun in hand: " .. tostring(n) .. (edit_defaults and "  (editing the DEFAULTS for every gun)" or "  (editing this gun's own zones)")) or "No gun in hand: the sliders edit the defaults")
    local cd, vd = imgui.checkbox("Edit the defaults for every gun instead of this gun", edit_defaults)
    if cd then edit_defaults = vd end
    local hx, hy, hz, _, hon = live(b, 3)
    for _, z in ipairs(ZONES) do
        if z.key ~= "hand" then
            local x, y, zz, r, on = live(b, z.i)
            local key = zone_key(z, b)
            local head = z.label .. (z.key == "part" and (" [" .. key .. "]") or "")
            if on and on > 0.5 then
                if hon and hon > 0.5 then
                    local d = math.sqrt((hx - x) ^ 2 + (hy - y) ^ 2 + (hz - zz) ^ 2)
                    head = head .. string.format("  -  hand %.0f cm away, needs %.0f", d * 100, (r or 0) * 100)
                else
                    head = head .. string.format("  -  size %.0f cm", (r or 0) * 100)
                end
            else
                head = head .. "  -  (not on this gun right now)"
            end
            if imgui.tree_node(head .. "##zone_" .. z.key) then
                local grp = group_name(b)
                local e = entry(grp, key, false) or {}
                local changed = false
                for _, ax in ipairs(AXES) do
                    local cur = (tonumber(e[ax.k]) or 0) * 100
                    local ca, va = imgui.slider_float(ax.label .. "##" .. z.key .. ax.k, cur, -30.0, 30.0, "%.1f")
                    if ca then e = entry(grp, key, true); e[ax.k] = va / 100; changed = true end
                end
                local cur_r = tonumber(e.r) and e.r * 100 or ((r or 0) * 100)
                local cr, vr = imgui.slider_float("size (radius), cm##" .. z.key .. "r", cur_r, 2.0, 40.0, "%.1f")
                if cr then e = entry(grp, key, true); e.r = vr / 100; changed = true end
                if changed then save() end
                if imgui.button("Forget this zone's numbers (back to the plugin's own)##" .. z.key) then
                    if type(cfg[grp]) == "table" then cfg[grp][key] = nil end
                    save()
                end
                imgui.tree_pop()
            end
        end
    end
    imgui.spacing()
    local ch, vh = imgui.slider_float("Sphere model size fix (if the spheres look too big or small for their numbers)", (tonumber(cfg["_visual"].half_m) or mesh_half or 0.05) * 100, 0.5, 100.0, "%.1f cm")
    if ch then cfg["_visual"].half_m = vh / 100; cfg["_visual"].half_set = true; save() end
    if cfg["_visual"].half_set and imgui.button("Measure the size again (forget the fix)") then cfg["_visual"].half_set = nil; save() end
    -- (2026-10-25, Tefa: "i'm afraid to accidentally press it, i'll just ask you if i ever need to clear all of it": the
    -- "Forget everything" button is gone, as in the Grab Zones window)
    imgui.tree_pop()
end)

log.info(TAG .. " loaded")
