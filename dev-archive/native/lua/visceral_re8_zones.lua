-- visceral_re8_zones.lua -- the grip zones: the sphere of the zone being tuned in the Grip Zones window, and the zone sliders
-- in the REFramework menu (2026-10-25, Tefa: "is there any way I can visibly set them, how big they are, where they are on the gun").
--
-- The plugin (src/zones.cpp, reload.cpp, rack.cpp, pairs.cpp) tells this file, every frame, where each zone is RIGHT NOW in the
-- world and how big it is (bridge slots 116-135, 154-173): the magazine grab, the well, the slide / pump / bolt, the point the
-- hand is measured from, the front grip, the grip handle, the drum, the insert point, the slide's left side. A zone the gun
-- does not have is off. The sliders in the menu ("Visceral RE8 grip zones") write reframework/data/visceral_re8/zones.json;
-- the plugin re-reads it at once.
--
-- THE SPHERE (2026-10-30, Tefa, in the headset: "Grip zones needs a system where only the dropped down menu shows the spheres,
-- collapsed ones don't, this simplifies things"): only the zone whose row is open in the Grip Zones window is drawn, at its
-- full size, so it can be placed and sized; with no row open (or the window closed) nothing is drawn. When the left hand goes
-- inside it, it shrinks in STEPS toward the middle (Tefa: "it has to go in reverse, from starting out big to smaller in the
-- middle"). The window writes visceral_re8/zones_open.json { key, t } about once a second. The look: Village's test ball in
-- the "axis" look, the orange and white squares (Tefa: "the spheres with orange and white squares are the best to use"); it
-- cannot be see-through (the engine's no-material pattern: get_MaterialNum 0 on a drawn sphere, checked live 2026-10-30).
--
-- zones.json: { "default": { "mag": {x,y,z,r,on}, "well": {...}, "slide": {...}, "pump": {...}, "bolt": {...}, ... },
--               "3042": { ... the same, for one gun (its number) ... } }
-- "on": true / false switches a zone on or off for every gun ("default") or one gun, over the plugin's own choice (zones.cpp
-- builtin_on: the front grip only on long guns that are not pump shotguns; 2026-10-30, Tefa: "make it customizable so we
-- can add things if needed").
-- x, y, z: metres from the zone's own joint, in the gun's axes; r: the radius in metres. A missing number keeps the plugin's own.
--
-- The same numbers are set from outside the game with the Grip Zones window (github.com/TefMeister/grip-zones-vr, a desktop
-- window Window View can hang in the headset). For it this file writes visceral_re8/zones_state.json four times a second (the
-- gun in hand, each zone's size and how far the hand is from it), and re-reads zones.json twice a second.

local TAG = "[visceral-re8-zones]"
local FILE = "visceral_re8/zones.json"
local STATE_FILE = "visceral_re8/zones_state.json"
local STATE_EVERY_S, RELOAD_EVERY_S, EDIT_QUIET_S = 0.25, 0.5, 0.6
local S_WEAPON_NUM, S_ZONE_SEQ, S_ZONES = 97, 115, 116
local S_ZONES2 = 154   -- written by the plugin: handle, drum, insert, slide-left {x, y, z, r, on} each
local HAND_I = 3
local OPEN_FILE = "visceral_re8/zones_open.json"   -- the Grip Zones window's open row { key, t }
local OPEN_EVERY_S, OPEN_STALE_S = 0.25, 3
-- act = a grip zone with a sphere (every zone but the hand point); key = its row in the Grip Zones window
local ZONES = {
    { i = 0, key = "mag",  act = true, label = "Grab the magazine (left grip on it)" },
    { i = 1, key = "well", act = true, label = "The well: where a magazine goes in" },
    { i = 2, key = "part", act = true, label = "The slide / pump / bolt (left grip on it)" },
    { i = 3, key = "hand", label = "The point the hand is measured from" },
    { i = 4, key = "grip", act = true, label = "The front grip: this gun's kept grip spot (left grip in it takes the gun two-handed)" },
    { i = 20, key = "handle", act = true, label = "The grip handle (handguns: left grip cups it)" },
    { i = 21, key = "drum",   act = true, label = "The drum (revolvers: left grip opens it, LT loads a round, LT when full closes it)" },
    { i = 22, key = "insert", act = true, label = "The insert point (GM 79: a grenade goes in here; left grip + LT takes one out)" },
    { i = 23, key = "slide-left", act = true, label = "The slide from the left side (pistols: left grip in it takes the slide with the left-side hold)" },
}
local PART_NAMES = { [1] = "slide", [2] = "pump", [3] = "bolt" }
local AXES = { { k = "z", label = "forward (+) / back (-), cm" }, { k = "y", label = "up (+) / down (-), cm" }, { k = "x", label = "right (+) / left (-), cm" } }

-- the size cue: the hand inside the open zone shrinks its sphere in STEPS (the ball cannot fade, see the top)
local STEPS = 3

-- the sphere: Village's development test ball (its file list), the orange and white squares seen since 2026-10-25; the plain
-- primitive sphere if the test ball will not load.
-- ⚠️ set_Material ONCE per sphere: a second call on a balloon crashed the game (2026-10-30 20:20, a probe at the title
-- screen; kept dump D:/RE Village REFramework builds/logs/reframework_crash-2026-10-30-2020.dmp)
local MESHES = { "environment/props/resource/sm0x/sm00_111_testball/sm00_111_testball_00.mesh",
                 "vfx/mesh/mesh_primitive/sphere_mediumpolygon.mesh" }
local MATERIAL = "systems/effect/vfx_default_axis.mdf2"   -- the orange and white squares
-- ⚠️ THE SPHERES ARE NEVER MEASURED (2026-10-30, Tefa: "crashes straight away"): with no material set (tried 22:2x) the game
-- crashed a second after the spheres were made, INSIDE via.render.Mesh.get_ModelLocalAABB (re8.exe+0x4bdfcb4), the call that
-- read each new sphere's own size every frame until it answered. So the material is back (the 20:41-21:55 build) and the size
-- is the test ball's known one. ⚠️ The crash after the spheres were remade (2026-10-30 21:55, re8.exe+0x415879c, the same
-- place as 2026-10-25 22:06) is NOT explained by this: the measure had finished two minutes before it. Cause unknown. Logs and dumps: D:/RE Village REFramework builds/logs/*2026-10-30-2155*, *2026-10-30-2231*
local MESH_WAIT_S = 10.0        -- a model is waited for this long (it loads in the background) before the next is tried
local SPHERE_HALF_M = 0.030     -- the test ball's half size by its own box, 0.033 by a ruler [measured 2026-10-29]
local RESPAWN_EVERY_S = 1.0

local cfg = nil
local seq = 0
local last_state_t, last_reload_t, last_edit_t = 0, 0, -10
local edit_defaults = false
local balls = {}          -- i -> { go, comp, xform, on, step }
local mat_res = {}        -- material path -> its holder (false = would not load)
local mesh_holders, mesh_failed, mesh_first_try = {}, {}, {}
local mesh_used = nil
local open_key, last_open_t = nil, -10
local spawn_tried, swept = false, false
local last_respawn_t, last_where_t = -10, -10
local status = "not drawn yet"

local function bridge() local b = rawget(_G, "visceral_re8_bridge"); if b ~= nil and b.ready() then return b end; return nil end
local function load()
    cfg = nil
    pcall(function() cfg = json.load_file(FILE) end)
    if type(cfg) ~= "table" then cfg = {} end
end
local function save()
    last_edit_t = os.clock()
    pcall(function() json.dump_file(FILE, cfg) end)
    seq = seq + 1
    local b = bridge()
    if b then b.w(S_ZONE_SEQ, seq) end
end
-- the row open in the Grip Zones window, if the window is running (it rewrites the file about once a second)
local function read_open()
    local o = nil
    pcall(function() o = json.load_file(OPEN_FILE) end)
    if type(o) == "table" and type(o.key) == "string" and o.key ~= "" and tonumber(o.t) and os.time() - tonumber(o.t) <= OPEN_STALE_S then
        open_key = o.key
    else
        open_key = nil
    end
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
local function live(b, i)   -- x, y, z, r, on of zone i from the plugin
    if i < 5 then return raw5(b, S_ZONES + i * 5) end
    if i >= 20 then return raw5(b, S_ZONES2 + (i - 20) * 5) end
    return nil, nil, nil, 0, 0
end

-- ---- the spheres ------------------------------------------------------------------------------------------------------------
local function alive(o)
    if not o then return false end
    local ok, v = pcall(function() return sdk.is_valid_obj and sdk.is_valid_obj(o) end)
    if ok and v == false then return false end
    local ok2, addr = pcall(function() return o:get_address() end)
    return ok2 and addr ~= nil and addr ~= 0
end
-- a resource wrapped in the holder the game's setters take (Mesh.setMesh / set_Material take holders, not bare resources:
-- a bare one made the game read garbage inside setMesh, 2026-10-25)
local function holder(path, kind, holder_type)
    local h = nil
    pcall(function()
        local res = sdk.create_resource(kind, path)
        if res then res = res:add_ref(); h = res:create_holder(holder_type) end
        if h then h = h:add_ref() end
    end)
    return h
end
local function current_scene()
    local scene = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        if sm then scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene") end
    end)
    return scene
end
local function find_folder()
    local scene = current_scene()
    if not scene then return nil end
    for _, name in ipairs({ "ModdedTemporaryObjects", "Debug", "Master" }) do
        local f = nil
        pcall(function() f = scene:call("findFolder", name) end)
        if f then return f end
    end
    return nil
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
    local comp = nil
    pcall(function()
        comp = go:call("createComponent(System.Type)", sdk.find_type_definition("via.render.Mesh"):get_runtime_type())
        if comp then comp = comp:add_ref(); comp:call(".ctor()") end
    end)
    if not comp then status = "no mesh component"; pcall(function() go:call("destroy", go) end); return nil end
    local got, waiting = nil, false
    for _, path in ipairs(mesh_used and { mesh_used } or MESHES) do
        if not mesh_failed[path] then
            -- the kept holder is tried, then a fresh one (a kept one went stale once, 2026-10-25)
            local fresh = holder(path, "via.render.MeshResource", "via.render.MeshResourceHolder")
            for _, h in ipairs({ mesh_holders[path], fresh }) do
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
            if os.clock() - mesh_first_try[path] < MESH_WAIT_S then waiting = true; break end   -- still loading
            mesh_failed[path] = true   -- never asked again: a failed setMesh is an error inside the game
            log.info(TAG .. " sphere model " .. path .. ": did not load in " .. MESH_WAIT_S .. " s")
        end
    end
    if not got then
        status = waiting and "the sphere model is still loading" or "no sphere model would load (see the log)"
        pcall(function() go:call("destroy", go) end)
        return nil
    end
    if not mesh_used then mesh_used = got; log.info(TAG .. " the sphere: " .. got) end
    if mat_res[MATERIAL] == nil then mat_res[MATERIAL] = holder(MATERIAL, "via.render.MeshMaterialResource", "via.render.MeshMaterialResourceHolder") or false end
    if mat_res[MATERIAL] then pcall(function() comp:call("set_Material", mat_res[MATERIAL]) end) end   -- once, at the making
    -- a mesh made from script draws only once enabled, set to draw by default and sent to every render output
    -- (Andyalpa's holster visuals, re8_vr_holster_visuals.lua)
    pcall(function() comp:call("set_Enabled", true) end)
    pcall(function() comp:call("set_DrawDefault", true) end)
    pcall(function()
        local et = sdk.find_type_definition("via.render.RenderOutputID")
        local f = et and et:get_field("All")
        comp:call("set_RenderOutputID", f and f:get_data(nil) or 31)
    end)
    pcall(function() comp:call("set_IgnoreDepth", false) end)
    pcall(function() comp:call("set_DrawShadowCast", false) end)
    pcall(function() go:call("set_DrawSelf", true) end)
    pcall(function() go:call("set_UpdateSelf", true) end)
    local xform = nil
    pcall(function() xform = go:call("get_Transform") end)
    status = "drawn: " .. got:match("[^/]+$")
    return { go = go, comp = comp, xform = xform, on = false }
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
    end
    spawn_tried = false
end

-- "Reset scripts" throws this script's memory away but not the objects it made (2026-10-25, Tefa: spheres left hanging in the
-- air): they are destroyed at a reset, and any left by an older run (same names, any zone number used before) before the first
local function sweep_leftovers()
    local scene = current_scene()
    if not scene then return end
    local n = 0
    for i = 0, 23 do
        for _ = 1, 20 do   -- several resets: several with one name
            local go = nil
            pcall(function() go = scene:call("findGameObject(System.String)", "visceral_re8_zone_" .. i) end)
            if not go then break end
            pcall(function() go:call("setActive", false) end)
            pcall(function() go:call("destroy", go) end)
            n = n + 1
        end
    end
    if n > 0 then log.info(TAG .. " " .. n .. " sphere(s) left by an earlier run destroyed") end
end
re.on_script_reset(function() destroy_all() end)

-- ---- THE GUN IN THE RIGHT HAND (2026-10-25, Tefa: "can i still tweak where the gun is pointing", then "all please") -------
-- praydog's VR mode places the right hand (and so the gun) at the controller turned by re8vr.right_hand_rotation_offset and
-- moved by re8vr.right_hand_position_offset (the controller's own axes: x right, y up, z back). zones.json "aim" (per gun over
-- "default", from the Grip Zones window's GUN IN THE RIGHT HAND box) turns and moves it further: pitch / yaw / roll in degrees
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
local aim_generation = nil
local function aim_tick(b)
    -- 2026-10-30: re8_vr.lua may put the OpenXR offsets in AFTER load (OpenXR came up late); then the base captured here
    -- was the wrong (OpenVR) one and would be laid back over the fix. A new generation number means: capture again.
    local gen = rawget(_G, "__re8_vr_hand_offsets_generation")
    if gen ~= aim_generation then aim_generation = gen; aim_base_rot, aim_base_pos, aim_applied = nil, nil, nil end
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
    local st = { t = os.time(), gun = gun_num(b), zones = {}, spot = math.floor((b.r(153) or 0) + 0.5) }   -- 153: the left hand's spot (Dock Poser)
    local hx, hy, hz, _, hon = live(b, 3)
    for _, z in ipairs(ZONES) do
        if z.key ~= "hand" then
            local x, y, zz, r, on = live(b, z.i)
            local e = { key = zone_key(z, b), on = (on or 0) > 0.5, r_cm = (r or 0) * 100 }
            if e.on and (hon or 0) > 0.5 then e.hand_cm = math.sqrt((hx - x) ^ 2 + (hy - y) ^ 2 + (hz - zz) ^ 2) * 100 end
            st.zones[#st.zones + 1] = e
        end
    end
    pcall(function() json.dump_file(STATE_FILE, st) end)
end

-- how deep the left hand is in zone z: 0 at the centre, 1 on the edge, nil = outside
local function hand_k(b, z)
    local x, y, zz, r = live(b, z.i)
    local hx, hy, hz, _, hon = live(b, HAND_I)
    if not (hon and hon > 0.5 and x and hx and r and r > 0) then return nil end
    local k = math.sqrt((hx - x) ^ 2 + (hy - y) ^ 2 + (hz - zz) ^ 2) / r
    return k <= 1.0 and k or nil
end

-- made, moved and switched in the game's own update (on_application_entry "UpdateMotion"), as the holster visuals do: made in
-- the present step (re.on_frame) they were never drawn (2026-10-25)
re.on_application_entry("UpdateMotion", function()
    local b = bridge()
    if not b then return end
    local now = os.clock()
    if now - last_reload_t > RELOAD_EVERY_S and now - last_edit_t > EDIT_QUIET_S then last_reload_t = now; load() end
    if now - last_state_t > STATE_EVERY_S then last_state_t = now; write_state(b) end
    aim_tick(b)
    if now - last_open_t > OPEN_EVERY_S then last_open_t = now; read_open() end
    -- a scene change destroys them: all made again, at most once a second
    if spawn_tried then
        for _, ball in pairs(balls) do
            if not alive(ball.go) and now - last_respawn_t > RESPAWN_EVERY_S then
                last_respawn_t = now
                log.info(TAG .. " a sphere was destroyed (scene change): making them again")
                destroy_all()
                return
            end
        end
    end
    -- made once a gun is in hand; any still missing (its model was loading) asked again once a second (2026-10-30: the
    -- magazine's sphere, asked first while the model loaded, was never made)
    -- 2026-10-31: made ONLY while a row is open in the Grip Zones window. Making them at every draw crashed Village: taking the
    -- shotgun out, setMesh threw inside the game a second after the first sphere was made, then re8.exe+0x415879c (log
    -- 2026-10-31 12:08; the same address and the same setMesh as the 10-25 22:06 and 10-30 21:55 crashes). In play nothing
    -- here touches a mesh now; with the window's row open the risk stays (a Grip Zones session, not play).
    if gun_num(b) > 0 and open_key ~= nil and now - last_respawn_t > RESPAWN_EVERY_S then
        local missing = false
        for _, z in ipairs(ZONES) do if z.act and balls[z.i] == nil then missing = true end end
        if missing then
            last_respawn_t = now
            if not swept then swept = true; sweep_leftovers() end
            for _, z in ipairs(ZONES) do
                if z.act and balls[z.i] == nil then balls[z.i] = spawn(z.i); spawn_tried = spawn_tried or balls[z.i] ~= nil end
            end
        end
    end
    -- the one zone to show: the row open in the Grip Zones window, when the gun in hand has that zone
    local show_i, show_k = nil, nil
    for _, z in ipairs(ZONES) do
        local _, _, _, r, on = live(b, z.i)
        if z.act and z.key == open_key and on and on > 0.5 and r and r > 0 then show_i, show_k = z.i, hand_k(b, z) end
    end
    for _, z in ipairs(ZONES) do
        local ball = balls[z.i]
        if ball and alive(ball.go) and ball.xform then
            local show = z.i == show_i
            set_on(ball, show)
            if show then
                local x, y, zz, r = live(b, z.i)
                local step = show_k and math.max(1, math.min(STEPS, math.ceil((1.0 - show_k) * STEPS))) or 1   -- 1 outside or at the edge .. STEPS at the middle
                local s = r * (STEPS - step + 1) / STEPS / SPHERE_HALF_M   -- full size at the edge, a third at the middle
                ball.scale, ball.step = s, step
                pcall(function()
                    ball.xform:call("set_Position", Vector3f.new(x, y, zz))
                    -- set_LocalScale as well as set_Scale, as praydog's holster visuals do
                    ball.xform:call("set_LocalScale", Vector3f.new(s, s, s))
                    ball.xform:call("set_Scale", Vector3f.new(s, s, s))
                end)
                if not ball.shown_logged then
                    ball.shown_logged = true
                    log.info(TAG .. string.format(" sphere %s first shown: r %.3f m, step %d of %d", z.key, r, step, STEPS))
                end
            end
        end
    end
    -- every 5 s: which spheres show, how big and how solid, so a headset run can be read from the log
    if now - last_where_t > 5.0 then
        last_where_t = now
        local parts = {}
        for _, z in ipairs(ZONES) do
            local ball = balls[z.i]
            if ball then
                local _, _, _, r, on = live(b, z.i)
                parts[#parts + 1] = string.format("%s %s r %.2f%s", z.key, alive(ball.go) and (ball.on and "SHOWN" or (on and on > 0.5 and "near-off" or "not on gun")) or "DEAD",
                    r or 0, ball.on and (" step " .. tostring(ball.step)) or "")
            end
        end
        if #parts > 0 then log.info(TAG .. " spheres (open in Grip Zones: " .. tostring(open_key) .. "): " .. table.concat(parts, " | ")) end
    end
end)

-- ---- the menu ---------------------------------------------------------------------------------------------------------------
re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 grip zones") then return end
    local b = bridge()
    imgui.text("A zone's sphere shows while its row is open in the Grip Zones window (open now: " .. tostring(open_key) .. ").")
    imgui.text("Also in the Grip Zones window on the desktop (for Window View in the headset).")
    imgui.text("Spheres: " .. status)
    if not b then imgui.text("(the bridge is not up: no gun readings)"); imgui.tree_pop(); return end
    local n = gun_num(b)
    imgui.text(n > 0 and ("Gun in hand: " .. tostring(n) .. (edit_defaults and "  (editing the DEFAULTS for every gun)" or "  (editing this gun's own zones)")) or "No gun in hand: the sliders edit the defaults")
    local cd, vd = imgui.checkbox("Edit the defaults for every gun instead of this gun", edit_defaults)
    if cd then edit_defaults = vd end
    local hx, hy, hz, _, hon = live(b, HAND_I)
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
    -- (2026-10-25, Tefa: "i'm afraid to accidentally press it": no "Forget everything" button, as in the Grip Zones window)
    imgui.tree_pop()
end)

log.info(TAG .. " loaded")
