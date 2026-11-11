-- visceral_re8_shell2.lua -- the second shotgun shell in the left hand (2026-11-11, Tefa: "can you get 2 shotgun shells to show
-- up for the shotgun in re8? and so they dissapear one after another when inserted into the gun. only one if it's the last one
-- in the pouch or if gun only needs one more").
--
-- The plugin already takes two shells per pouch grab (src/shells.cpp, 2026-11-02; one when one is carried or one fits) but a
-- pump shotgun has ONE loose shell joint (W870 ShotgunCartridge_FK_0, M1897 Bullet), so only one was drawn. This file draws
-- the other: a copy of the held gun's mesh showing ONLY its shell part (the way visceral_re8_magthrow.lua copies a
-- magazine), placed so the copy's shell lies beside the first one. The plugin says when (bridge slot 217: a second shell is
-- in the hand, this frame) and where the first shell is (218-225); when the first shell has gone in, the count drops to one,
-- the copy goes, and the gun's own shell joint is the one left in the hand.
-- WHICH mesh part holds the shell [measured 2026-11-11, flat, one part on at a time with the gun's body moved away]:
--   W870 (3021): part 50, the shell alone (as the LEMI's rounds are its part 50). The gun itself is part 0.
--   M1897 (3036): part 0, the SAME part as the whole gun: no part shows its shell alone.
-- So the copy never relies on the part alone: its Body joint (every gun piece hangs under it) is put 100 m under the floor and
-- its shell joint is written straight to where the second shell belongs. That works for both guns (seen on the real guns the
-- same day). shell2.json "guns" -> "<gun number>" -> "part" overrides the part; a gun not listed below draws no copy.
-- Test without a headset: reframework/data/visceral_re8/shell2_test.json {"front": true} floats the copy's shell 0.35 m in
-- front of the camera (read once a second); "part": N tries another part, "whole": true every part.

if reframework:get_game_name() ~= "re8" then return end

local TAG = "[visceral-re8-shell2]"
local function L(s) log.info(TAG .. " " .. s) end
local told = {}
local function once(key, s) if not told[key] then told[key] = true; L(s) end end
local function safe(f) local ok, v = pcall(f); if ok then return v end end

-- ===== settings (saved to reframework/data/visceral_re8/shell2.json) =====
local FILE, TEST_FILE = "visceral_re8/shell2.json", "visceral_re8/shell2_test.json"
local S_FRAME, S_CAM_POS, S_CAM_ROT, S_WEAPON_NUM = 0, 72, 75, 97
local S_ON, S_POS, S_ROT, S_SIZE = 217, 218, 221, 225
local STALE_FRAMES = 3         -- the plugin's "wanted" stamp older than this = no second shell
local PARTS_MAX = 256          -- a gun mesh has at most this many parts
local SHELL_JOINTS = { "Bullet", "ShotgunCartridge_FK_0" }   -- as src/reload.cpp looks for them
local BODY_JOINT, BODY_AWAY_M = "Body", 100.0
local KNOWN_PART = { [3021] = 50, [3085] = 50, [3036] = 0, [3084] = 0, [3147] = 0 }   -- W870 (+ Mercenaries), M1897 (+ Mercenaries, Rose); the two variants by likeness, not measured
local cfg = {
    enabled = true,
    guns = {},                 -- "<gun number>" -> { part = <mesh part>, x, y, z (cm, the first shell's own axes), rx, ry, rz (deg) }
}
local function gun_cfg(num)
    local key = tostring(num)
    local g = cfg.guns[key]
    if type(g) ~= "table" then g = {}; cfg.guns[key] = g end
    -- beside the first shell: one shell's width across (a first guess: which of its axes is "across" is not known yet)
    for k, v in pairs({ part = KNOWN_PART[num] or -1, x = 2.2, y = 0.0, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0 }) do if type(g[k]) ~= "number" then g[k] = v end end
    return g
end
local function load_cfg()
    local okf, fh = pcall(io.open, FILE, "r")
    if not okf or not fh then return end
    fh:close()
    local ok, d = pcall(json.load_file, FILE)
    if ok and type(d) == "table" then
        if d.enabled ~= nil then cfg.enabled = d.enabled == true end
        if type(d.guns) == "table" then cfg.guns = d.guns end
    end
end
local function save_cfg() pcall(json.dump_file, FILE, cfg) end
load_cfg()
local test = { front = false, whole = false, part = nil }
local test_t = 0
local function read_test()
    local okf, fh = pcall(io.open, TEST_FILE, "r")
    if not okf or not fh then test.front, test.whole, test.part = false, false, nil; return end
    fh:close()
    local ok, d = pcall(json.load_file, TEST_FILE)
    if ok and type(d) == "table" then
        local f, w, p = d.front == true, d.whole == true, tonumber(d.part)
        if f ~= test.front or w ~= test.whole or p ~= test.part then
            test.front, test.whole, test.part = f, w, p
            L("test switches: front " .. tostring(f) .. ", whole " .. tostring(w) .. ", part " .. tostring(p))
        end
    end
end

-- ===== small maths on plain numbers (x, y, z, w) =====
local function qmul(a, b)
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end
local function qinv(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end
local function qrot(q, v)
    local p = qmul(qmul(q, { x = v.x, y = v.y, z = v.z, w = 0 }), qinv(q))
    return { x = p.x, y = p.y, z = p.z }
end
local function qnorm(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-6 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end
local function q_ypr(yaw, pitch, roll)   -- the plugin's convention (reload_pose.cpp): about Z, then Y, then X, degrees
    local d = math.pi / 360.0
    local qz = { x = 0, y = 0, z = math.sin(yaw * d), w = math.cos(yaw * d) }
    local qy = { x = 0, y = math.sin(pitch * d), z = 0, w = math.cos(pitch * d) }
    local qx = { x = math.sin(roll * d), y = 0, z = 0, w = math.cos(roll * d) }
    return qnorm(qmul(qmul(qz, qy), qx))
end

-- ===== the game's pieces (as visceral_re8_magthrow.lua has them) =====
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
local function mesh_of(w)
    if w == nil then return nil, nil end
    local mesh = safe(function() return w:get_field("Mesh") end)
    local go = safe(function() return w:call("get_GameObject") end)
    if mesh == nil and go then mesh = safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh")) end) end
    return mesh, go
end
local function held_gun()   -- the held gun's mesh, its size, and the gun component itself
    local vr = rawget(_G, "re8vr")
    if vr == nil then return nil end
    local w = safe(function() return vr.weapon end)
    local mesh, go = mesh_of(w)
    if mesh == nil and vr.player then
        local em = safe(function() return vr.player:call("getComponent(System.Type)", sdk.typeof("app.EquipController")) end)
        w = em and (safe(function() return em:call("get_equipWeaponRight") end) or safe(function() return em:call("currentPlayerWeapon") end))
        mesh, go = mesh_of(w)
    end
    if mesh == nil then return nil end
    local scale = 1.0
    local xf = go and safe(function() return go:call("get_Transform") end)
    local sc = xf and safe(function() return xf:call("get_LocalScale") end)
    if sc and sc.x and sc.x > 0.01 then scale = sc.x end
    return mesh, scale, w
end
local function log_parts_fields(num, w, mesh)   -- once per gun: what the gun itself says about its parts
    if told["fields" .. num] then return end
    told["fields" .. num] = true
    local n = safe(function() return mesh:call("getPartsEnableCount") end)
    local on = ""
    for i = 0, math.min((tonumber(n) or 0), 64) - 1 do on = on .. ((safe(function() return mesh:call("getPartsEnable", i) end) == true) and "1" or "0") end
    L(string.format("gun %d: mesh parts %s, drawn now %s", num, tostring(n), on))
    local td = w and safe(function() return w:get_type_definition() end)
    local seen = 0
    while td ~= nil and seen < 8 do
        for _, f in ipairs(safe(function() return td:get_fields() end) or {}) do
            local name = safe(function() return f:get_name() end) or ""
            if name:find("Parts") or name:find("Bullet") or name:find("Shell") or name:find("Cartridge") then
                local v = safe(function() return w:get_field(name) end)
                L(string.format("gun %d: field %s = %s", num, name, tostring(v)))
            end
        end
        td = safe(function() return td:get_parent_type() end)
        seen = seen + 1
    end
end

-- ===== the copy =====
local copy = nil   -- { go, xf, mesh, num, part, whole, scale, body, shell, how }
local function destroy()
    if copy and copy.go then pcall(function() copy.go:call("destroy", copy.go) end) end
    copy = nil
end
local function show_parts(mc, part, whole)
    for i = 0, PARTS_MAX - 1 do pcall(function() mc:call("setPartsEnable", i, whole or i == part) end) end
end
local function make(b, num, part, whole)
    local mesh, scale, w = held_gun()
    if mesh == nil then once("nomesh", "no gun mesh found: no second shell"); return nil end
    log_parts_fields(num, w, mesh)
    local res = safe(function() return mesh:call("getMesh") end) or safe(function() return mesh:call("get_Mesh") end)
    local mat = safe(function() return mesh:call("get_Material") end)
    if res == nil or (mk_go == nil and mk_go_in == nil) then once("nores", "no mesh resource or no way to make objects"); return nil end
    local folder = spawn_folder()
    local go = safe(function()
        if folder and mk_go_in then return mk_go_in:call(nil, "visceral_second_shell", folder) end
        return mk_go:call(nil, "visceral_second_shell")
    end)
    if go == nil then once("nogo", "could not make the copy's object"); return nil end
    pcall(function() go = go:add_ref() end)
    pcall(function() go:call(".ctor") end)
    local mc = safe(function()
        local c = go:call("createComponent(System.Type)", sdk.typeof("via.render.Mesh"))
        if c then c = c:add_ref(); c:call(".ctor()") end
        return c
    end)
    if mc == nil or not pcall(function() mc:call("setMesh", res) end) then
        once("nomc", "the copy took no mesh"); pcall(function() go:call("destroy", go) end); return nil
    end
    if mat then pcall(function() mc:call("set_Material", mat) end) end
    show_parts(mc, part, whole)
    pcall(function() mc:call("set_Enabled", true) end)
    pcall(function() go:call("set_DrawSelf", true) end)
    pcall(function() go:call("setActive", true) end)
    local xf = safe(function() return go:call("get_Transform") end)
    if xf == nil then pcall(function() go:call("destroy", go) end); return nil end
    pcall(function() xf:call("set_LocalScale", Vector3f.new(scale, scale, scale)) end)
    local c = { go = go, xf = xf, mesh = mc, num = num, part = part, whole = whole, scale = scale }
    c.body = safe(function() return xf:call("getJointByName", BODY_JOINT) end)
    for _, name in ipairs(SHELL_JOINTS) do
        c.shell = safe(function() return xf:call("getJointByName", name) end)
        if c.shell then c.how = name; break end
    end
    if c.shell == nil then
        once("nojoint" .. num, string.format("gun %d: the copy has no shell joint: no second shell", num))
        pcall(function() go:call("destroy", go) end)
        return nil
    end
    L(string.format("copy made for gun %d (%s): shell joint %s, body joint %s, scale %.2f", num,
        whole and "WHOLE GUN, test" or ("part " .. tostring(part)), c.how, c.body and "found (moved away)" or "NOT FOUND (the gun's body may show)", scale))
    return c
end
-- the copy's shell at (p, q), size k against the game's; the rest of the gun far under the floor. The root rides along at
-- the shell, so the object's bounds stay where it is looked at
local function place(c, p, q, k)
    pcall(function()
        c.xf:call("set_Position", Vector3f.new(p.x, p.y, p.z))
        c.xf:call("set_Rotation", Quaternion.new(q.w, q.x, q.y, q.z))
        if c.body and not c.whole then c.body:call("set_Position", Vector3f.new(p.x, p.y - BODY_AWAY_M, p.z)) end
        c.shell:call("set_Position", Vector3f.new(p.x, p.y, p.z))
        c.shell:call("set_Rotation", Quaternion.new(q.w, q.x, q.y, q.z))
        c.shell:call("set_LocalScale", Vector3f.new(k, k, k))
    end)
end

local shown = false
local function update()
    local now = os.clock()
    if now - test_t > 1.0 then test_t = now; read_test() end
    local b = rawget(_G, "visceral_re8_bridge")
    local vr = rawget(_G, "re8vr")
    if b == nil or not b.ready() or vr == nil or vr.player == nil then if copy then destroy() end; return end
    local num = math.floor(b.r(S_WEAPON_NUM) + 0.5)
    local g = num > 0 and gun_cfg(num) or nil
    local wanted = cfg.enabled and g ~= nil and math.abs(b.r(S_ON) - 1.0 - b.r(S_FRAME)) <= STALE_FRAMES and b.r(S_ON) > 0.5
    local part, whole = g and math.floor(g.part + 0.5) or -1, false
    local front = test.front and num > 0
    if front then part, whole = (test.part and math.floor(test.part + 0.5) or part), test.whole end
    if not (wanted or front) then
        if copy and shown then pcall(function() copy.go:call("set_DrawSelf", false) end); shown = false; L("the second shell is gone (one or none left in the hand)") end
        if copy and copy.num ~= num then destroy() end
        return
    end
    if part < 0 and not whole then
        once("nopart" .. num, string.format("gun %d: which mesh part is its shell is not known yet (shell2.json guns.%d.part): no second shell drawn", num, num))
        if copy then destroy() end
        return
    end
    if copy and (copy.num ~= num or copy.part ~= part or copy.whole ~= whole) then destroy() end
    if copy == nil then
        local ok, c = pcall(make, b, num, part, whole)
        if not ok then once("makeerr", "copy failed: " .. tostring(c)); return end
        copy = c
        if copy == nil then return end
        shown = false
    end
    if not shown then pcall(function() copy.go:call("set_DrawSelf", true) end); shown = true; if wanted then L("the second shell is drawn beside the first") end end
    if front and not wanted then   -- TEST: 0.35 m in front of the game camera (the game's own camera: the bridge's is empty on the flat screen)
        local cx = safe(function() return sdk.get_primary_camera():call("get_GameObject"):call("get_Transform") end)
        local cp, cr = cx and safe(function() return cx:call("get_Position") end), cx and safe(function() return cx:call("get_Rotation") end)
        if cp and cr then
            local cq = qnorm({ x = cr.x, y = cr.y, z = cr.z, w = cr.w })
            local fwd = qrot(cq, { x = 0, y = 0, z = -1 })
            place(copy, { x = cp.x + fwd.x * 0.35, y = cp.y + fwd.y * 0.35, z = cp.z + fwd.z * 0.35 }, cq, 1.0)
        end
        return
    end
    local p1 = { x = b.r(S_POS), y = b.r(S_POS + 1), z = b.r(S_POS + 2) }
    local q1 = qnorm({ x = b.r(S_ROT), y = b.r(S_ROT + 1), z = b.r(S_ROT + 2), w = b.r(S_ROT + 3) })
    local k = b.r(S_SIZE)
    if not (k > 0.05 and k < 5.0) then k = 1.0 end
    local off = qrot(q1, { x = g.x * 0.01, y = g.y * 0.01, z = g.z * 0.01 })
    place(copy, { x = p1.x + off.x, y = p1.y + off.y, z = p1.z + off.z }, qnorm(qmul(q1, q_ypr(g.rz, g.ry, g.rx))), k)
end

-- after the plugin has placed the first shell (its late point and its render point), and once more just before drawing
re.on_application_entry("LateUpdateBehavior", function() local ok, e = pcall(update); if not ok then once("err", "update failed: " .. tostring(e)) end end)
re.on_pre_application_entry("BeginRendering", function() local ok, e = pcall(update); if not ok then once("err2", "update failed: " .. tostring(e)) end end)

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 second shell") then return end
    local c
    c, cfg.enabled = imgui.checkbox("Two shells in the hand", cfg.enabled == true); if c then save_cfg() end
    local b = rawget(_G, "visceral_re8_bridge")
    local num = (b and b.ready()) and math.floor(b.r(S_WEAPON_NUM) + 0.5) or 0
    if num > 0 then
        local g = gun_cfg(num)
        imgui.text("Gun " .. num .. (copy and (": the copy's shell joint is " .. tostring(copy.how)) or ": no copy now"))
        local ch
        ch, g.part = imgui.slider_int("The shell's mesh part (-1 = not known)", math.floor(g.part + 0.5), -1, 80); c = ch
        for _, k in ipairs({ "x", "y", "z" }) do ch, g[k] = imgui.slider_float("move " .. k .. ", cm", g[k], -8.0, 8.0); c = c or ch end
        for _, k in ipairs({ "rx", "ry", "rz" }) do ch, g[k] = imgui.slider_float("turn " .. k .. ", deg", g[k], -180.0, 180.0); c = c or ch end
        if c then save_cfg() end
    else
        imgui.text("No gun in hand")
    end
    imgui.tree_pop()
end)

L("loaded (two shells in the hand " .. (cfg.enabled and "on" or "off") .. ")")
