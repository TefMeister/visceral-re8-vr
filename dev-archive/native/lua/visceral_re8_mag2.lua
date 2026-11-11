-- visceral_re8_mag2.lua -- the second magazine in the left hand (2026-11-11; the plugin's side and Tefa's words: src/twomag.h).
--
-- A handgun has ONE magazine joint, which the plugin moves. While the hand holds an extra magazine (a spare from the pouch
-- with the gun's still seated, or the old one after the two were swapped), this file draws it: a copy of the held gun's mesh
-- (visceral_re8_shell2.lua's way) with its Body joint 100 m under the floor and its Magazine joint written into the hand.
-- The plugin says when and where (bridge slots 226-235): the hand's magazine hold, and the role:
--   1 = a spare: drawn in the hand's SECOND place (mag2.json "spare": move cm / turn deg from the hold), so the first place
--       stays free for the gun's own magazine coming out;
--   2 = the old magazine after the swap: drawn in the first place ("old": zero by default).
-- It writes back where it drew it (236-243): the plugin starts the spare's way into the gun from there.
-- The copy looks as full as its own rounds: the gun's "vanish when empty" parts are on only when it holds any.
-- Test without a headset: reframework/data/visceral_re8/mag2_test.json {"front": true} floats the copy's magazine 0.35 m in
-- front of the camera; "rounds": 0 shows the empty look.
-- The second place is a first guess [hypothesis]; nothing here has been worn.
-- (The maths and the copy-making below are the same as in visceral_re8_shell2.lua: two copies of that code for now.)

if reframework:get_game_name() ~= "re8" then return end

local TAG = "[visceral-re8-mag2]"
local function L(s) log.info(TAG .. " " .. s) end
local told = {}
local function once(key, s) if not told[key] then told[key] = true; L(s) end end
local function safe(f) local ok, v = pcall(f); if ok then return v end end

local FILE, TEST_FILE = "visceral_re8/mag2.json", "visceral_re8/mag2_test.json"
local S_FRAME, S_WEAPON_NUM = 0, 97
local S_ON, S_ROLE, S_POS, S_ROT, S_ROUNDS, S_DRAWN_POS, S_DRAWN_ROT, S_DRAWN_ON = 226, 227, 228, 231, 235, 236, 239, 243
local STALE_FRAMES = 3
local PARTS_MAX = 256
local MAG_JOINT, MAG_JOINT2, BODY_JOINT, BODY_AWAY_M = "Magazine", "Magazine_second", "Body", 100.0
local cfg = {
    enabled = true,
    spare = { x = 3.0, y = 0.0, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0 },   -- the second place, from the hold (cm, deg; the magazine's own axes)
    old = { x = 0.0, y = 0.0, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0 },     -- the first place
}
local function load_cfg()
    local okf, fh = pcall(io.open, FILE, "r")
    if not okf or not fh then return end
    fh:close()
    local ok, d = pcall(json.load_file, FILE)
    if ok and type(d) == "table" then
        if d.enabled ~= nil then cfg.enabled = d.enabled == true end
        for _, role in ipairs({ "spare", "old" }) do
            if type(d[role]) == "table" then for k, _ in pairs(cfg[role]) do if type(d[role][k]) == "number" then cfg[role][k] = d[role][k] end end end
        end
    end
end
local function save_cfg() pcall(json.dump_file, FILE, cfg) end
load_cfg()
local test = { front = false, rounds = nil }
local test_t = 0
local function read_test()
    local okf, fh = pcall(io.open, TEST_FILE, "r")
    if not okf or not fh then test.front, test.rounds = false, nil; return end
    fh:close()
    local ok, d = pcall(json.load_file, TEST_FILE)
    if ok and type(d) == "table" then
        local f, r = d.front == true, tonumber(d.rounds)
        if f ~= test.front or r ~= test.rounds then test.front, test.rounds = f, r; L("test switches: front " .. tostring(f) .. ", rounds " .. tostring(r)) end
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

-- ===== the copy =====
local copy = nil   -- { go, xf, mesh, num, scale, body, mag, mag2, rel2_p, rel2_q, gun, gun_mesh, look, role }
local function destroy()
    if copy and copy.go then pcall(function() copy.go:call("destroy", copy.go) end) end
    copy = nil
end
local function int_list(w, name)   -- a List<int> field of the gun, as a Lua list
    local out = {}
    local v = safe(function() return w:get_field(name) end)
    local n = v and safe(function() return v:call("get_Count") end) or 0
    for i = 0, (tonumber(n) or 0) - 1 do out[#out + 1] = safe(function() return v:call("get_Item", i) end) end
    return out
end
-- the copy's parts. A gun that names its magazine part (the LEMI: 1): only that part, the second magazine part when the gun
-- shows it, and the parts that vanish with an empty magazine, those only when THIS magazine holds rounds. (Mirroring every
-- part the gun shows drew the LEMI's suppressor too, which does not hang under Body: seen flat 2026-11-11.) A gun that names
-- none (-1): as the gun's parts are now, which may show such an add-on [hypothesis].
local function set_look(c, rounds)
    local look = rounds > 0 and 1 or 0
    if c.look == look then return end
    c.look = look
    local custom = safe(function() return c.gun:call("get_customizeMagazine") end) == true
    local part = safe(function() return c.gun:get_field(custom and "NormalMagazinePartsNoCustomized" or "NormalMagazinePartsNo") end)
    local second = safe(function() return c.gun:get_field(custom and "SecondMagazinePartsNoCustomized" or "SecondMagazinePartsNo") end)
    local named = type(part) == "number" and part >= 0
    local on = {}
    for i = 0, PARTS_MAX - 1 do on[i] = (not named) and safe(function() return c.gun_mesh:call("getPartsEnable", i) end) == true end
    if named then
        on[part] = true
        if type(second) == "number" and second >= 0 then on[second] = safe(function() return c.gun_mesh:call("getPartsEnable", second) end) == true end
    end
    local vanish = int_list(c.gun, "switchVanishEmptyPartsDisp")
    if safe(function() return c.gun:get_field("IsEnableVanishEmptyPartsDisp") end) == true then
        for _, p in ipairs(vanish) do if type(p) == "number" and p >= 0 then on[p] = look == 1 end end
    end
    for i = 0, PARTS_MAX - 1 do pcall(function() c.mesh:call("setPartsEnable", i, on[i]) end) end
    L(string.format("gun %d: the copy looks %s (magazine part %s, second %s, %d part(s) that vanish when empty; %s)", c.num, look == 1 and "loaded" or "empty",
        tostring(part), tostring(second), #vanish, named and "only those parts" or "no magazine part named: the gun's own parts"))
end
local function make(num)
    local mesh, scale, w = held_gun()
    if mesh == nil then once("nomesh", "no gun mesh found: no second magazine"); return nil end
    local res = safe(function() return mesh:call("getMesh") end) or safe(function() return mesh:call("get_Mesh") end)
    local mat = safe(function() return mesh:call("get_Material") end)
    if res == nil or (mk_go == nil and mk_go_in == nil) then once("nores", "no mesh resource or no way to make objects"); return nil end
    local folder = spawn_folder()
    local go = safe(function()
        if folder and mk_go_in then return mk_go_in:call(nil, "visceral_second_magazine", folder) end
        return mk_go:call(nil, "visceral_second_magazine")
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
    pcall(function() mc:call("set_Enabled", true) end)
    pcall(function() go:call("set_DrawSelf", true) end)
    pcall(function() go:call("setActive", true) end)
    local xf = safe(function() return go:call("get_Transform") end)
    if xf == nil then pcall(function() go:call("destroy", go) end); return nil end
    pcall(function() xf:call("set_LocalScale", Vector3f.new(scale, scale, scale)) end)
    local c = { go = go, xf = xf, mesh = mc, num = num, scale = scale, gun = w, gun_mesh = mesh }
    c.body = safe(function() return xf:call("getJointByName", BODY_JOINT) end)
    c.mag = safe(function() return xf:call("getJointByName", MAG_JOINT) end)
    c.mag2 = safe(function() return xf:call("getJointByName", MAG_JOINT2) end)
    if c.mag == nil then
        once("nojoint" .. num, string.format("gun %d: the copy has no Magazine joint: no second magazine", num))
        pcall(function() go:call("destroy", go) end)
        return nil
    end
    if c.mag2 then   -- where the second magazine joint sits against the first, as the copy was made (nothing moves it)
        local p1, q1 = safe(function() return c.mag:call("get_Position") end), safe(function() return c.mag:call("get_Rotation") end)
        local p2, q2 = safe(function() return c.mag2:call("get_Position") end), safe(function() return c.mag2:call("get_Rotation") end)
        if p1 and q1 and p2 and q2 then
            local inv = qinv(qnorm({ x = q1.x, y = q1.y, z = q1.z, w = q1.w }))
            c.rel2_p = qrot(inv, { x = p2.x - p1.x, y = p2.y - p1.y, z = p2.z - p1.z })
            c.rel2_q = qnorm(qmul(inv, qnorm({ x = q2.x, y = q2.y, z = q2.z, w = q2.w })))
        else
            c.mag2 = nil
        end
    end
    L(string.format("copy made for gun %d: Magazine joint found, Magazine_second %s, body joint %s, scale %.2f", num,
        c.mag2 and "rides along" or "none", c.body and "found (moved away)" or "NOT FOUND (the gun's body may show)", scale))
    return c
end
-- the copy's magazine at (p, q); the rest of the gun far under the floor; the root rides along at the magazine
local function place(c, p, q)
    pcall(function()
        c.xf:call("set_Position", Vector3f.new(p.x, p.y, p.z))
        c.xf:call("set_Rotation", Quaternion.new(q.w, q.x, q.y, q.z))
        if c.body then c.body:call("set_Position", Vector3f.new(p.x, p.y - BODY_AWAY_M, p.z)) end
        c.mag:call("set_Position", Vector3f.new(p.x, p.y, p.z))
        c.mag:call("set_Rotation", Quaternion.new(q.w, q.x, q.y, q.z))
        if c.mag2 then
            local o = qrot(q, c.rel2_p)
            local q2 = qnorm(qmul(q, c.rel2_q))
            c.mag2:call("set_Position", Vector3f.new(p.x + o.x, p.y + o.y, p.z + o.z))
            c.mag2:call("set_Rotation", Quaternion.new(q2.w, q2.x, q2.y, q2.z))
        end
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
    local wanted = cfg.enabled and num > 0 and b.r(S_ON) > 0.5 and math.abs(b.r(S_ON) - 1.0 - b.r(S_FRAME)) <= STALE_FRAMES
    local front = test.front and num > 0
    if not (wanted or front) then
        if copy and shown then pcall(function() copy.go:call("set_DrawSelf", false) end); shown = false; L("the second magazine is gone from the hand") end
        if copy and copy.num ~= num then destroy() end
        return
    end
    if copy and copy.num ~= num then destroy() end
    if copy == nil then
        local ok, c = pcall(make, num)
        if not ok then once("makeerr", "copy failed: " .. tostring(c)); return end
        copy = c
        if copy == nil then return end
        shown = false
    end
    if front and not wanted then   -- TEST: 0.35 m in front of the game's camera
        set_look(copy, test.rounds or 1)
        if not shown then pcall(function() copy.go:call("set_DrawSelf", true) end); shown = true end
        local cx = safe(function() return sdk.get_primary_camera():call("get_GameObject"):call("get_Transform") end)
        local cp, cr = cx and safe(function() return cx:call("get_Position") end), cx and safe(function() return cx:call("get_Rotation") end)
        if cp and cr then
            local cq = qnorm({ x = cr.x, y = cr.y, z = cr.z, w = cr.w })
            local fwd = qrot(cq, { x = 0, y = 0, z = -1 })
            place(copy, { x = cp.x + fwd.x * 0.35, y = cp.y + fwd.y * 0.35, z = cp.z + fwd.z * 0.35 }, cq)
        end
        return
    end
    local role = math.floor(b.r(S_ROLE) + 0.5)
    local g = role == 1 and cfg.spare or cfg.old
    set_look(copy, math.floor(b.r(S_ROUNDS) + 0.5))
    if not shown then
        pcall(function() copy.go:call("set_DrawSelf", true) end); shown = true
        L(role == 1 and "a spare magazine is drawn in the hand's second place" or "the old magazine is drawn in the hand")
    end
    if copy.role ~= role then copy.role = role; L(role == 1 and "role: the spare" or "role: the old magazine, after the swap") end
    local p1 = { x = b.r(S_POS), y = b.r(S_POS + 1), z = b.r(S_POS + 2) }
    local q1 = qnorm({ x = b.r(S_ROT), y = b.r(S_ROT + 1), z = b.r(S_ROT + 2), w = b.r(S_ROT + 3) })
    local off = qrot(q1, { x = g.x * 0.01, y = g.y * 0.01, z = g.z * 0.01 })
    local p = { x = p1.x + off.x, y = p1.y + off.y, z = p1.z + off.z }
    local q = qnorm(qmul(q1, q_ypr(g.rz, g.ry, g.rx)))
    place(copy, p, q)
    b.w(S_DRAWN_POS, p.x); b.w(S_DRAWN_POS + 1, p.y); b.w(S_DRAWN_POS + 2, p.z)
    b.w(S_DRAWN_ROT, q.x); b.w(S_DRAWN_ROT + 1, q.y); b.w(S_DRAWN_ROT + 2, q.z); b.w(S_DRAWN_ROT + 3, q.w)
    b.w(S_DRAWN_ON, b.r(S_FRAME) + 1.0)
end

re.on_application_entry("LateUpdateBehavior", function() local ok, e = pcall(update); if not ok then once("err", "update failed: " .. tostring(e)) end end)
re.on_pre_application_entry("BeginRendering", function() local ok, e = pcall(update); if not ok then once("err2", "update failed: " .. tostring(e)) end end)

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 second magazine") then return end
    local c
    c, cfg.enabled = imgui.checkbox("Two magazines in the hand", cfg.enabled == true); if c then save_cfg() end
    for _, role in ipairs({ "spare", "old" }) do
        imgui.text(role == "spare" and "The spare (the hand's second place)" or "The old magazine after the swap (the first place)")
        local g, ch = cfg[role], false
        for _, k in ipairs({ "x", "y", "z" }) do c, g[k] = imgui.slider_float("move " .. k .. ", cm##" .. role, g[k], -10.0, 10.0); ch = ch or c end
        for _, k in ipairs({ "rx", "ry", "rz" }) do c, g[k] = imgui.slider_float("turn " .. k .. ", deg##" .. role, g[k], -180.0, 180.0); ch = ch or c end
        if ch then save_cfg() end
    end
    imgui.tree_pop()
end)

L("loaded (two magazines in the hand " .. (cfg.enabled and "on" or "off") .. ")")
