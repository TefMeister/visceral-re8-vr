-- zz_test_axes.lua -- TEST ONLY (2026-11-08, Tefa: "go over all the sliders and how they move hands. left side must always be
-- down, inwards, rotate left, bend left ... right must always be up, outwards, rotate right"). Copy into reframework/autorun,
-- take it out after. When reframework/data/axes_go.json holds a new {"go": n}, at one BeginRendering it turns every hand joint
-- by +10 degrees on each of its local Euler axes in turn (set_LocalEulerAngle, the same call hand_poser.lua uses), reads which
-- way that turned it in the world, puts the joint back, and writes everything to reframework/data/axes_out.json for
-- tools/sim/axes_read.py. Nothing stays changed: each joint is put back the same frame.
local FINGERS = { "Thumb1", "Thumb2", "Thumb3", "IndexF1", "IndexF2", "IndexF3", "MiddleF1", "MiddleF2", "MiddleF3",
                  "RingF1", "RingF2", "RingF3", "PinkyF1", "PinkyF2", "PinkyF3" }
local STEP = math.rad(10)
local done, tf, byname = nil, nil, nil

local function player_tf()
    local sm = sdk.get_native_singleton("via.SceneManager")
    local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local arr = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase"))
    local els = arr and arr:get_elements()
    local c = els and els[1]
    return c and c:call("get_GameObject"):call("get_Transform")
end
local function q(t) return { x = t.x, y = t.y, z = t.z, w = t.w } end
local function v(t) return { t.x, t.y, t.z } end
local function qmul(a, b)
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end
local function qinv(a) return { x = -a.x, y = -a.y, z = -a.z, w = a.w } end
local function rot(a, p)   -- rotate vector p {1,2,3} by quaternion a
    local r = qmul(qmul(a, { x = p[1], y = p[2], z = p[3], w = 0 }), qinv(a))
    return { r.x, r.y, r.z }
end
local function rotvec(d)   -- a quaternion's rotation as axis * angle (radians), the short way
    if d.w < 0 then d = { x = -d.x, y = -d.y, z = -d.z, w = -d.w } end
    local s = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
    if s < 1e-9 then return { 0, 0, 0 } end
    local ang = 2 * math.atan(s, d.w)
    return { d.x / s * ang, d.y / s * ang, d.z / s * ang }
end
local function pos(nm) local j = byname[nm]; return j and v(j:call("get_Position")) or nil end

local function measure()
    local out = { joints = {}, points = {} }
    for _, side in ipairs({ "L_", "R_" }) do
        for _, nm in ipairs({ "Hand", "IndexF1", "MiddleF1", "MiddleF3", "PinkyF1", "Thumb1", "Thumb3", "Forearm" }) do out.points[side .. nm] = pos(side .. nm) end
        local list = { "Hand" }
        for _, f in ipairs(FINGERS) do list[#list + 1] = f end
        for _, f in ipairs(list) do
            local j = byname[side .. f]
            if j then
                local e0 = j:call("get_LocalEulerAngle")
                local l0, w0 = q(j:call("get_LocalRotation")), q(j:call("get_Rotation"))
                local parent = qmul(w0, qinv(l0))
                local rec = { pos = v(j:call("get_Position")), euler = { math.deg(e0.x), math.deg(e0.y), math.deg(e0.z) }, axes = {},
                              own = { rot(w0, { 1, 0, 0 }), rot(w0, { 0, 1, 0 }), rot(w0, { 0, 0, 1 }) } }   -- its own axes (Animation & Timing's nudges turn about these)
                for k, ax in ipairs({ "x", "y", "z" }) do
                    local e = Vector3f.new(e0.x, e0.y, e0.z)
                    if ax == "x" then e.x = e.x + STEP elseif ax == "y" then e.y = e.y + STEP else e.z = e.z + STEP end
                    j:call("set_LocalEulerAngle", e)
                    local l1 = q(j:call("get_LocalRotation"))
                    rec.axes[k] = rot(parent, rotvec(qmul(l1, qinv(l0))))   -- the world turn of +10 degrees on this axis
                    j:call("set_LocalEulerAngle", e0)
                end
                out.joints[side .. f] = rec
            end
        end
    end
    -- the held gun's axes (the plugin's "gun axes": its Transform, zones.cpp gun_rot): the first *_Inventory under the player
    local function find_gun(t, depth)
        if t == nil or depth > 6 then return nil end
        local c = t:call("get_Child")
        while c do
            local nm = c:call("get_GameObject"):call("get_Name")
            if nm and nm:find("_Inventory") and c:call("get_GameObject"):call("get_DrawSelf") then return c, nm end
            local f, fn = find_gun(c, depth + 1)
            if f then return f, fn end
            c = c:call("get_Next")
        end
        return nil
    end
    local gt, gname = find_gun(tf, 0)
    if gt then
        local gq = q(gt:call("get_Rotation"))
        out.gun = { name = gname, pos = v(gt:call("get_Position")), x = rot(gq, { 1, 0, 0 }), y = rot(gq, { 0, 1, 0 }), z = rot(gq, { 0, 0, 1 }) }
    end
    local cam = sdk.get_primary_camera()
    local ct = cam and cam:call("get_GameObject"):call("get_Transform")
    if ct then out.camera = { pos = v(ct:call("get_Position")), rot = q(ct:call("get_Rotation")) } end
    return out
end

re.on_pre_application_entry("BeginRendering", function()
    local ok, err = pcall(function()
        local go = json.load_file("axes_go.json")
        if go == nil or go.go == nil or go.go == done then return end
        done = go.go
        tf = tf or player_tf()
        if not tf then log.info("[test-axes] no player"); return end
        if not byname then
            byname = {}
            local arr = tf:call("get_Joints"); local els = arr and arr:get_elements() or {}
            for _, jj in ipairs(els) do local nn = jj:call("get_Name"); if nn then byname[nn] = jj end end
        end
        local out = measure()
        out.go = done
        json.dump_file("axes_out.json", out)
        log.info("[test-axes] measured, run " .. tostring(done))
    end)
    if not ok then log.info("[test-axes] error: " .. tostring(err)) end
end)
log.info("[test-axes] loaded: write reframework/data/axes_go.json {\"go\": n} to measure")
