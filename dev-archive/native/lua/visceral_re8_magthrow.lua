-- visceral_re8_magthrow.lua -- the thrown magazine (2026-11-05, Tefa: "throwing away a used mag, the ammo count should not
-- change if it is even partially full as that messes with game's systems and changes the actual game, but for show, and
-- that sound would also play from where it lands").
--
-- The plugin (src/reload_throw.cpp) hands over every magazine that leaves the gun (let go of, or out of the magwell):
-- where the gun's root would be with the magazine seated where it is now, the magazine's own point, the hand's speed,
-- and the mesh's magazine part number (bridge slots 187-201). This file makes a copy of the held gun's mesh showing ONLY
-- that part (the way Andyalpa's holster visuals copy a gun), flies it with gravity, stops it on the floor (a ray cast, as
-- praydog's re8_vr.lua casts for the crosshair), plays the landing sound on the copy, and leaves it lying there a while.
-- It writes the number back (slot 202), and the plugin then hides the gun's own falling magazine.
-- Nothing here touches the ammo: the dropped magazine's rounds already stay counted (the plugin, 2026-10-25).
-- Everything is [hypothesis] until seen: the copy's look, where it lies, the sound.

if reframework:get_game_name() ~= "re8" then return end

local TAG = "[visceral-re8-magthrow]"
local function L(s) log.info(TAG .. " " .. s) end
local told = {}
local function once(key, s) if not told[key] then told[key] = true; L(s) end end

-- ===== settings (one table; saved to reframework/data/visceral_re8/magthrow.json) =====
local FILE = "visceral_re8/magthrow.json"
local S_SEQ, S_ROOT_POS, S_ROOT_ROT, S_PIVOT, S_VEL, S_PART, S_ACK = 187, 188, 191, 195, 198, 201, 202
local GRAVITY = 9.81           -- m/s2
local MAX_DT = 0.05            -- s, one step at most this long (a hitch never tunnels it through the floor)
local REST_SPEED = 0.6         -- m/s, landing slower than this = it stays down (no bounce)
local MAX_FLIGHT_S = 4.0       -- s, a magazine that never finds a floor is taken away after this
local PARTS_MAX = 64           -- every other mesh part up to this number is switched off on the copy
local cfg = {
    enabled = true,            -- off = the old way: the magazine falls half a second and vanishes
    stay_s = 60.0,             -- how long a magazine lies on the floor
    keep_max = 6,              -- most magazines lying around at once (the oldest goes first)
    bounce = 0.25,             -- how much of its speed it keeps on a bounce
    spin = 4.0,                -- rad/s, the tumble a thrown magazine gets from the hand
    lift = 0.02,               -- m, it rests this far above the hit point (half a magazine's thickness)
    land_sound = "",           -- "wwise:<trigger id>": the game sound for a magazine hitting the floor (not picked yet)
}
local function load_cfg()
    local ok, d = pcall(json.load_file, FILE)
    if ok and type(d) == "table" then for k, v in pairs(d) do if cfg[k] ~= nil then cfg[k] = v end end end
end
local function save_cfg() pcall(json.dump_file, FILE, cfg) end
load_cfg()
-- TEST switches (reframework/data/visceral_re8/magthrow_test.json, read once a second, not saved): {"float": true} = the
-- copy hangs where it was let go (no gravity), {"whole": true} = the copy shows the whole gun, not only the magazine
local TEST_FILE = "visceral_re8/magthrow_test.json"
local test = { float = false, whole = false, nofolder = false, lift = 0.0, front = false }
local test_t = 0
local function read_test()
    -- 2026-11-05: look before loading: json.load_file logs an error every second when the test file is missing
    local okf, fh = pcall(io.open, TEST_FILE, "r")
    if not okf or not fh then return end
    fh:close()
    local ok, d = pcall(json.load_file, TEST_FILE)
    if ok and type(d) == "table" then
        local f, w, nf, lf, fr = d.float == true, d.whole == true, d.nofolder == true, tonumber(d.lift) or 0.0, d.front == true
        if f ~= test.float or w ~= test.whole or nf ~= test.nofolder or lf ~= test.lift or fr ~= test.front then
            test.float, test.whole, test.nofolder, test.lift, test.front = f, w, nf, lf, fr
            log.info("[visceral-re8-magthrow] test switches: float " .. tostring(f) .. ", whole " .. tostring(w) ..
                ", no folder " .. tostring(nf) .. ", lift " .. tostring(lf))
        end
    end
end

-- ===== small maths on plain numbers (x, y, z, w) =====
local function qmul(a, b)
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end
local function qrot(q, v)   -- v turned by q
    local p = qmul(qmul(q, { x = v.x, y = v.y, z = v.z, w = 0 }), { x = -q.x, y = -q.y, z = -q.z, w = q.w })
    return { x = p.x, y = p.y, z = p.z }
end
local function qaxis(ax, ay, az, ang)
    local s = math.sin(ang * 0.5)
    return { x = ax * s, y = ay * s, z = az * s, w = math.cos(ang * 0.5) }
end
local function qnorm(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-6 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end

-- ===== the game's pieces =====
local function safe(f) local ok, v = pcall(f); if ok then return v end end
local mk_go = safe(function() return sdk.find_type_definition("via.GameObject"):get_method("create(System.String)") end)
local mk_go_in = safe(function() return sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)") end)
local cast_ray = safe(function() return sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)") end)
local BULLET_LAYER = nil
pcall(function() BULLET_LAYER = require("utility/Statics").generate("app.CollisionManager.Layer").Bullet end)

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

-- the gun in the right hand and its mesh. re8vr.weapon is the held gun's component (Andyalpa's holster visuals call
-- get_GameObject on it); EquipController.equipWeaponRight is the second way. The first that answers is logged once.
local function mesh_of(w)
    if w == nil then return nil, nil end
    local mesh = safe(function() return w:get_field("Mesh") end)
    local go = safe(function() return w:call("get_GameObject") end)
    if mesh == nil and go then mesh = safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh")) end) end
    return mesh, go
end
local function held_gun_mesh()
    local vr = rawget(_G, "re8vr")
    if vr == nil then once("novr", "no re8vr (the VR layer) yet"); return nil end
    local mesh, go, way = nil, nil, nil
    mesh, go = mesh_of(safe(function() return vr.weapon end))
    if mesh then way = "re8vr.weapon" end
    if mesh == nil and vr.player then
        local em = safe(function() return vr.player:call("getComponent(System.Type)", sdk.typeof("app.EquipController")) end)
        if em == nil then
            pcall(function() em = require("utility/GameObject").get_component(vr.player, "app.EquipController") end)
        end
        local w = em and (safe(function() return em:call("get_equipWeaponRight") end) or safe(function() return em:call("currentPlayerWeapon") end))
        mesh, go = mesh_of(w)
        if mesh then way = "EquipController" end
    end
    if mesh == nil then return nil end
    once("way" .. way, "the held gun's mesh found through " .. way .. " (" .. tostring((go and safe(function() return go:call("get_Name") end)) or "?") .. ")")
    local scale = 1.0
    local xf = go and safe(function() return go:call("get_Transform") end)
    local sc = xf and safe(function() return xf:call("get_LocalScale") end)
    if sc and sc.x and sc.x > 0.01 then scale = sc.x end
    return mesh, scale
end

-- one ray from a to b against the world (not the player); { p = the hit point, n = its normal }, or nil
local function ray(a, b)
    if cast_ray == nil then return nil end
    return safe(function()
        local sys = sdk.get_native_singleton("via.physics.System")
        local q = sdk.create_instance("via.physics.CastRayQuery")
        local r = sdk.create_instance("via.physics.CastRayResult")
        q:call("setRay(via.vec3, via.vec3)", Vector3f.new(a.x, a.y, a.z), Vector3f.new(b.x, b.y, b.z))
        q:call("clearOptions")
        q:call("enableAllHits")
        q:call("enableNearSort")
        local fi = q:call("get_FilterInfo")
        fi:call("set_Group", 0)
        fi:call("set_MaskBits", 0xFFFFFFFF & ~1)   -- everything except the player
        if BULLET_LAYER then fi:call("set_Layer", BULLET_LAYER) end
        q:call("set_FilterInfo", fi)
        cast_ray:call(sys, q, r)
        if (r:call("get_NumContactPoints") or 0) < 1 then return nil end
        local cp = r:call("getContactPoint(System.UInt32)", 0)
        local p, n = cp:get_field("Position"), cp:get_field("Normal")
        return { p = { x = p.x, y = p.y, z = p.z }, n = (n and { x = n.x, y = n.y, z = n.z } or { x = 0, y = 1, z = 0 }) }
    end)
end

-- ===== the copies =====
local mags = {}        -- { go, xf, mesh, root_off (pivot -> root, in the copy's turn), rot, pivot, vel, spin_q, landed_at, born }
local last_seq = nil   -- the plugin's count when this script started (so an old number is not taken for a new one)

local function destroy(m)
    if m and m.go then pcall(function() m.go:call("destroy", m.go) end) end
    if m then m.go = nil end
end

local function place(m)
    local root = { x = m.pivot.x, y = m.pivot.y, z = m.pivot.z }
    local off = qrot(m.rot, m.root_off)
    root.x, root.y, root.z = root.x + off.x, root.y + off.y, root.z + off.z
    pcall(function()
        m.xf:call("set_Position", Vector3f.new(root.x, root.y, root.z))
        m.xf:call("set_Rotation", Quaternion.new(m.rot.w, m.rot.x, m.rot.y, m.rot.z))
    end)
end

local function play_land_sound(m)
    if cfg.land_sound == nil or cfg.land_sound == "" then
        once("nosound", "landed; no landing sound picked yet (magthrow.json land_sound = \"wwise:<id>\")")
        return
    end
    local id = tonumber(tostring(cfg.land_sound):match("(%d+)$"))
    if id == nil then return end
    if m.wwise == nil then
        m.wwise = safe(function()
            local c = m.go:call("createComponent(System.Type)", sdk.typeof("via.wwise.WwiseContainer"))
            if c then c = c:add_ref() end
            return c
        end)
    end
    local ok = m.wwise and pcall(function() m.wwise:call("trigger(System.UInt32)", id) end)
    once("sound" .. tostring(ok), ok and ("landing sound played on the copy (" .. cfg.land_sound .. ")")
        or "landing sound: no sound player on the copy (the sound needs another way)")
end

local function make_copy(b)
    -- a gun whose magazine is not a mesh part of its own (the F2 rifle, the V61 read -1 on 2026-11-05) would give an
    -- empty copy: those keep the plugin's old short fall until a magazine-only copy is found for them
    local part0 = math.floor(b.r(S_PART) + 0.5)
    if part0 < 0 and not test.whole then
        L("this gun's magazine is not a part of its own (part " .. part0 .. "): no copy, the old fall stays")
        return false
    end
    local mesh, scale = held_gun_mesh()
    if mesh == nil then once("nomesh", "no gun mesh found: no copy, the plugin's own fall stays"); return false end
    local res = safe(function() return mesh:call("getMesh") end) or safe(function() return mesh:call("get_Mesh") end)
    local mat = safe(function() return mesh:call("get_Material") end)
    if res == nil or (mk_go == nil and mk_go_in == nil) then once("nores", "no mesh resource or no way to make objects"); return false end
    local folder = (not test.nofolder) and spawn_folder() or nil
    local go = safe(function()
        if folder and mk_go_in then return mk_go_in:call(nil, "visceral_thrown_mag", folder) end
        return mk_go:call(nil, "visceral_thrown_mag")
    end)
    if go == nil then once("nogo", "could not make the copy's object"); return false end
    pcall(function() go = go:add_ref() end)
    pcall(function() go:call(".ctor") end)   -- Andyalpa's holster copies do this on a new object
    local mc = safe(function()
        local c = go:call("createComponent(System.Type)", sdk.typeof("via.render.Mesh"))
        if c then c = c:add_ref(); c:call(".ctor()") end
        return c
    end)
    if mc == nil or not pcall(function() mc:call("setMesh", res) end) then
        once("nomc", "the copy took no mesh"); pcall(function() go:call("destroy", go) end); return false
    end
    if mat then pcall(function() mc:call("set_Material", mat) end) end
    local part = math.floor(b.r(S_PART) + 0.5)
    if not test.whole then
        for i = 0, PARTS_MAX - 1 do pcall(function() mc:call("setPartsEnable", i, i == part) end) end
    end
    pcall(function() mc:call("set_Enabled", true) end)
    pcall(function() go:call("set_DrawSelf", true) end)
    pcall(function() go:call("setActive", true) end)
    local xf = safe(function() return go:call("get_Transform") end)
    if xf == nil then pcall(function() go:call("destroy", go) end); return false end
    pcall(function() xf:call("set_LocalScale", Vector3f.new(scale, scale, scale)) end)
    once("drawcheck", string.format("the copy: folder %s, mesh %s, material %s (%s), enabled %s, draw self %s, parts %s",
        tostring(folder ~= nil), tostring(safe(function() return mc:call("getMesh") end) ~= nil), tostring(mat ~= nil),
        tostring(safe(function() return mc:call("get_MaterialNum") end) or "?"), tostring(safe(function() return mc:call("get_Enabled") end)),
        tostring(safe(function() return go:call("get_DrawSelf") end)), tostring(safe(function() return mc:call("get_PartsCount") end) or "?")))

    local rp = { x = b.r(S_ROOT_POS), y = b.r(S_ROOT_POS + 1), z = b.r(S_ROOT_POS + 2) }
    local rot = qnorm({ x = b.r(S_ROOT_ROT), y = b.r(S_ROOT_ROT + 1), z = b.r(S_ROOT_ROT + 2), w = b.r(S_ROOT_ROT + 3) })
    local pv = { x = b.r(S_PIVOT), y = b.r(S_PIVOT + 1) + test.lift, z = b.r(S_PIVOT + 2) }
    rp.y = rp.y + test.lift
    if test.front then   -- TEST: 0.6 m in front of the game camera, floating, so it cannot be missed
        local cq = { x = b.r(75), y = b.r(76), z = b.r(77), w = b.r(78) }
        local fwd = qrot(qnorm(cq), { x = 0, y = 0, z = -1 })
        local np = { x = b.r(72) + fwd.x * 0.6, y = b.r(73) + fwd.y * 0.6, z = b.r(74) + fwd.z * 0.6 }
        rp = { x = rp.x + np.x - pv.x, y = rp.y + np.y - pv.y, z = rp.z + np.z - pv.z }
        pv = np
    end
    local vel = { x = b.r(S_VEL), y = b.r(S_VEL + 1), z = b.r(S_VEL + 2) }
    -- the root's place seen from the magazine, in the copy's own turn (so the copy turns about the magazine)
    local inv = { x = -rot.x, y = -rot.y, z = -rot.z, w = rot.w }
    local root_off = qrot(inv, { x = rp.x - pv.x, y = rp.y - pv.y, z = rp.z - pv.z })
    -- a tumble about the axis across the throw, as fast as the throw is
    local sp = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
    local ax = { x = vel.z, y = 0, z = -vel.x }
    local al = math.sqrt(ax.x * ax.x + ax.z * ax.z)
    local spin = (al > 1e-4) and { x = ax.x / al, y = 0, z = ax.z / al, rate = cfg.spin * math.min(1.0, sp / 3.0) } or { x = 1, y = 0, z = 0, rate = 0 }
    local m = { go = go, xf = xf, mesh = mc, root_off = root_off, rot = rot, pivot = pv, vel = vel, spin = spin,
                born = os.clock(), landed_at = nil, part = part }
    place(m)
    local back = safe(function() return xf:call("get_Position") end)
    once("readback" .. tostring(test.nofolder), string.format("the copy reads back at %s (folder %s)",
        back and string.format("%.2f %.2f %.2f", back.x, back.y, back.z) or "?",
        tostring(folder and (safe(function() return folder:call("get_Name") end) or "?") or "none")))
    mags[#mags + 1] = m
    while #mags > math.max(1, cfg.keep_max) do destroy(table.remove(mags, 1)) end
    L(string.format("copy made (part %d, speed %.2f m/s, %d lying around) root %.2f %.2f %.2f, magazine at %.2f %.2f %.2f, scale %.2f%s",
        part, sp, #mags, rp.x, rp.y, rp.z, pv.x, pv.y, pv.z, scale, test.whole and ", WHOLE GUN (test)" or ""))
    return true
end

local function step(m, dt)
    if m.landed_at then return end
    if test.float then place(m); return end
    local v = m.vel
    v.y = v.y - GRAVITY * dt
    local a = m.pivot
    local nb = { x = a.x + v.x * dt, y = a.y + v.y * dt, z = a.z + v.z * dt }
    local below = { x = nb.x, y = nb.y - cfg.lift, z = nb.z }
    local h = ray({ x = a.x, y = a.y + 0.01, z = a.z }, below)
    local hit, n = h and h.p, h and h.n
    if m.spin.rate > 0 then m.rot = qnorm(qmul(qaxis(m.spin.x, m.spin.y, m.spin.z, m.spin.rate * dt), m.rot)) end
    if hit then
        m.pivot = { x = hit.x + n.x * cfg.lift, y = hit.y + n.y * cfg.lift, z = hit.z + n.z * cfg.lift }
        local vn = v.x * n.x + v.y * n.y + v.z * n.z
        if vn < 0 then
            v.x, v.y, v.z = v.x - (1 + cfg.bounce) * vn * n.x, v.y - (1 + cfg.bounce) * vn * n.y, v.z - (1 + cfg.bounce) * vn * n.z
            v.x, v.z = v.x * 0.6, v.z * 0.6   -- the floor's grip
            m.spin.rate = m.spin.rate * 0.4
        end
        if not m.sounded then m.sounded = true; play_land_sound(m) end
        if math.abs(vn) < REST_SPEED or (v.x * v.x + v.y * v.y + v.z * v.z) < REST_SPEED * REST_SPEED then
            m.landed_at = os.clock()
            L(string.format("a magazine came to rest at %.2f %.2f %.2f (%.1f s after it left)", m.pivot.x, m.pivot.y, m.pivot.z, os.clock() - m.born))
        end
    else
        m.pivot = nb
    end
    place(m)
end

local last_t = os.clock()
re.on_application_entry("LateUpdateBehavior", function()
    local now = os.clock()
    local dt = math.min(MAX_DT, math.max(0.0, now - last_t))
    last_t = now
    if now - test_t > 1.0 then test_t = now; read_test() end
    local b = rawget(_G, "visceral_re8_bridge")
    if b and b.ready() then
        local seq = b.r(S_SEQ)
        if last_seq == nil then last_seq = seq
        elseif seq ~= last_seq then
            last_seq = seq
            if cfg.enabled then
                local ok, made = pcall(make_copy, b)
                if ok and made then b.w(S_ACK, seq) elseif not ok then L("copy failed: " .. tostring(made)) end
            end
        end
    end
    local vr = rawget(_G, "re8vr")
    if vr and vr.player == nil and #mags > 0 then   -- a load or a menu: the copies go
        for _, m in ipairs(mags) do destroy(m) end
        mags = {}
        return
    end
    for i = #mags, 1, -1 do
        local m = mags[i]
        local gone = m.go == nil or (m.landed_at and now - m.landed_at > cfg.stay_s) or (not m.landed_at and not test.float and now - m.born > MAX_FLIGHT_S)
        if gone then destroy(m); table.remove(mags, i)
        else
            local ok, err = pcall(step, m, dt)
            if not ok then once("steperr", "step failed: " .. tostring(err)); destroy(m); table.remove(mags, i) end
        end
    end
end)

-- ===== the Emporium's options (visceral_re8_emporium.lua reads _G.VISCERAL_OPTIONS) =====
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
table.insert(_G.VISCERAL_OPTIONS, { tab = "settings", order = 70, kind = "check", label = "Thrown magazines lie on the floor",
    help = "A magazine you let go of flies, lands and stays a while. The ammo count never changes.",
    get = function() return cfg.enabled == true end, set = function(v) cfg.enabled = v == true; save_cfg() end })
table.insert(_G.VISCERAL_OPTIONS, { tab = "settings", order = 71, kind = "slider", label = "How long they lie there (s)",
    min = 10.0, max = 120.0, fmt = "%.0f",
    get = function() return tonumber(cfg.stay_s) or 60.0 end, set = function(v) cfg.stay_s = v; save_cfg() end })

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 thrown magazines") then return end
    local c
    c, cfg.enabled = imgui.checkbox("Thrown magazines lie on the floor", cfg.enabled == true); if c then save_cfg() end
    c, cfg.stay_s = imgui.slider_float("Seconds on the floor", tonumber(cfg.stay_s) or 60.0, 10.0, 120.0); if c then save_cfg() end
    c, cfg.keep_max = imgui.slider_int("Most at once", math.floor(tonumber(cfg.keep_max) or 6), 1, 20); if c then save_cfg() end
    c, cfg.bounce = imgui.slider_float("Bounce", tonumber(cfg.bounce) or 0.25, 0.0, 0.8); if c then save_cfg() end
    c, cfg.spin = imgui.slider_float("Tumble", tonumber(cfg.spin) or 4.0, 0.0, 15.0); if c then save_cfg() end
    c, cfg.lift = imgui.slider_float("Rests above the floor (m)", tonumber(cfg.lift) or 0.02, 0.0, 0.1); if c then save_cfg() end
    c, cfg.land_sound = imgui.input_text("Landing sound (wwise:<id>)", tostring(cfg.land_sound or "")); if c then save_cfg() end
    imgui.text(string.format("Lying around: %d", #mags))
    if imgui.button("Take them all away") then for _, m in ipairs(mags) do destroy(m) end; mags = {} end
    imgui.tree_pop()
end)

L("loaded (thrown magazines " .. (cfg.enabled and "on" or "off") .. ")")
