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
}
local PART_NAMES = { [1] = "slide", [2] = "pump", [3] = "bolt" }
local AXES = { { k = "z", label = "forward (+) / back (-), cm" }, { k = "y", label = "up (+) / down (-), cm" }, { k = "x", label = "right (+) / left (-), cm" } }
-- the ball: our own sphere when it ships (natives/stm/visceral_re8/zone_sphere.mesh), else a game item Andyalpa's visuals
-- already spawn in Village (the First Aid Med); half_m is the model's half size, so scale = radius / half_m
local MESHES = { "visceral_re8/zone_sphere.mesh", "objectroot/setmodel/sm_item/sm_ri10/sm_ri1020/sm_ri1020.mesh",
                 "objectroot/setmodel/sm_item/sm_ri1020/sm_ri1020.mesh", "item/ri1020/ri1020.mesh" }

local cfg = nil
local seq = 0
local last_state_t, last_reload_t, last_edit_t = 0, 0, -10
local edit_defaults = false
local balls = {}          -- i -> { go, xform, on }
local mesh_res, mdf_res, mesh_used = nil, nil, ""
local spawn_tried = false
local status = "not drawn yet"

local function bridge() local b = rawget(_G, "visceral_re8_bridge"); if b ~= nil and b.ready() then return b end; return nil end
local function load()
    cfg = nil
    pcall(function() cfg = json.load_file(FILE) end)
    if type(cfg) ~= "table" then cfg = {} end
    if type(cfg["_visual"]) ~= "table" then cfg["_visual"] = { half_m = 0.05 } end
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
local function live(b, i)   -- x, y, z, r, on of zone i from the plugin
    local s = S_ZONES + i * 5
    return b.r(s), b.r(s + 1), b.r(s + 2), b.r(s + 3), b.r(s + 4)
end

-- ---- the balls --------------------------------------------------------------------------------------------------------------
local function alive(o)
    if not o then return false end
    local ok, v = pcall(function() return sdk.is_valid_obj and sdk.is_valid_obj(o) end)
    if ok and v == false then return false end
    local ok2, addr = pcall(function() return o:get_address() end)
    return ok2 and addr ~= nil and addr ~= 0
end
local function resource(path, kind)
    local res = nil
    pcall(function() res = sdk.create_resource(kind, path); if res then res = res:add_ref() end end)
    return res
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
local function resolve_mesh()
    if mesh_res then return true end
    for _, p in ipairs(MESHES) do
        local m = resource(p, "via.render.MeshResource")
        if m then
            mesh_res, mesh_used = m, p
            mdf_res = resource((p:gsub("%.mesh$", ".mdf2")), "via.render.MeshMaterialResource")
            log.info(TAG .. " ball mesh: " .. p .. (mdf_res and " (with its material)" or " (NO material found: it may be invisible)"))
            return true
        end
    end
    status = "no mesh for the balls could be loaded"
    return false
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
    local mesh_td = sdk.find_type_definition("via.render.Mesh")
    local comp = nil
    pcall(function()
        comp = go:call("createComponent(System.Type)", mesh_td:get_runtime_type())
        if comp then comp = comp:add_ref(); comp:call(".ctor()") end
    end)
    if not comp then status = "no mesh component"; pcall(function() go:call("destroy", go) end); return nil end
    local ok = pcall(function() comp:call("setMesh", mesh_res) end)
    if not ok then status = "setMesh failed"; pcall(function() go:call("destroy", go) end); return nil end
    if mdf_res then pcall(function() comp:call("set_Material", mdf_res) end) end
    local xform = nil
    pcall(function() xform = go:call("get_Transform") end)
    status = "drawn (" .. mesh_used .. ")"
    return { go = go, xform = xform, on = false }
end
local function set_on(ball, on)
    if ball.on == on or not alive(ball.go) then return end
    ball.on = on
    pcall(function() ball.go:call("setActive", on) end)
    pcall(function() ball.go:call("set_DrawSelf", on) end)
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

local function write_state(b)
    local st = { t = os.time(), gun = gun_num(b), zones = {} }
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

re.on_frame(function()
    local b = bridge()
    if not b then return end
    local now = os.clock()
    if now - last_reload_t > RELOAD_EVERY_S and now - last_edit_t > EDIT_QUIET_S then last_reload_t = now; load() end
    if now - last_state_t > STATE_EVERY_S then last_state_t = now; write_state(b) end
    local show = show_on()
    b.w(S_ZONE_SHOW, show and 1 or 0)
    if not show then
        if next(balls) ~= nil then destroy_all() end
        return
    end
    if not spawn_tried then
        spawn_tried = true
        if resolve_mesh() then for _, z in ipairs(ZONES) do balls[z.i] = spawn(z.i) end end
    end
    local half = tonumber(cfg["_visual"].half_m) or 0.05
    if half < 0.005 then half = 0.005 end
    for _, z in ipairs(ZONES) do
        local ball = balls[z.i]
        if ball and alive(ball.go) and ball.xform then
            local x, y, zz, r, on = live(b, z.i)
            local ok = on and on > 0.5 and x ~= nil and math.abs(x) < 1.0e5
            set_on(ball, ok)
            if ok then
                local s = (r or 0.05) / half
                pcall(function()
                    ball.xform:call("set_Position", Vector3f.new(x, y, zz))
                    ball.xform:call("set_Scale", Vector3f.new(s, s, s))
                end)
            end
        end
    end
end)

-- ---- the menu ---------------------------------------------------------------------------------------------------------------
re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 grab zones") then return end
    local b = bridge()
    local c, v = imgui.checkbox("Show the zones on the gun (balls that ride it)", show_on())
    if c then cfg["_visual"].show = v; save() end
    imgui.text("Also in the Grab Zones window on the desktop (for Window View in the headset).")
    imgui.text("Balls: " .. status)
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
    local ch, vh = imgui.slider_float("Ball model size fix (if the balls look too big or small for their numbers)", (tonumber(cfg["_visual"].half_m) or 0.05) * 100, 0.5, 30.0, "%.1f cm")
    if ch then cfg["_visual"].half_m = vh / 100; save() end
    if imgui.button("Forget everything (all guns back to the plugin's own zones)") then cfg = { _visual = cfg["_visual"] }; save() end
    imgui.tree_pop()
end)

log.info(TAG .. " loaded")
