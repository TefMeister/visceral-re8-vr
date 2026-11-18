-- visceral_re8_walls.lua -- the hands stop at walls (2026-11-18, Tefa: "see if you can get the hand to collide with walls").
--
-- Each frame, for each hand: one ray from about that shoulder (the camera, 18 cm down and 17 cm out to the side) to where
-- praydog's VR layer puts the hand (re8vr.last_left / right_hand_position), a hand's radius further. A hit means a wall is
-- between the shoulder and the hand: its plane goes to the plugin (bridge slots 252-265, src/bridge.h S_WALL_*), which keeps
-- the hand's IK target on the player's side of it right before the arm is solved (src/walls.cpp). The ray is the one
-- visceral_re8_magthrow.lua uses to land the thrown magazine on the floor (proven on the simulator 2026-11-05).
-- Doors and gates are never walls: anything hit whose name (or its parents' names) says door or gate is skipped, so the
-- hand can still push them (src/doors.cpp).
-- The first 20 different things a ray hits are written to the log by name, and the game's collision layers once, so the
-- first run says what the rays see [the layer choice is a first guess, hypothesis].
-- Settings: reframework/data/visceral_re8/walls.json, and the Emporium's Comfort tab.

if reframework:get_game_name() ~= "re8" then return end

local TAG = "[visceral-re8-walls]"
local function L(s) log.info(TAG .. " " .. s) end
local told = {}
local function once(key, s) if not told[key] then told[key] = true; L(s) end end
local function safe(f) local ok, v = pcall(f); if ok then return v end end

local FILE = "visceral_re8/walls.json"
local S_FRAME, S_GRIPPING_WEAPON, S_WEAPON_NUM = 0, 36, 97
local SLOTS = { { on = 252, p = 253, n = 256 }, { on = 259, p = 260, n = 263 } }   -- left, right
local S_TILT_Q, S_TILT_ON = 267, 271        -- the gun's turn at the wrist (world x y z w), its stamp (src/bridge.h S_WALL_TILT_*)
local S_MUZZLE_W, S_MUZZLE_ON = 272, 275    -- the drawn muzzle (world), its stamp, for doors.cpp (S_MUZZLE_W)
local cfg = {
    enabled = true,
    with_gun = true,        -- the hand holding a gun stops too (the gun with it)
    hand_r = 0.05,          -- the hand's radius: it stops this far off the wall (m)
    shoulder_down = 0.18,   -- the ray starts this far below the camera
    shoulder_side = 0.17,   -- and this far out to the hand's own side
    min_reach = 0.20,       -- a hand nearer the shoulder than this is never checked
    max_reach = 1.50,       -- nor one further than this (2026-11-18, simulator: while a save loads the hand sits 130 m away)
    muzzle = true,          -- the gun's muzzle stops at the wall too, the hand giving way (Tefa 2026-11-18)
    muzzle_r = 0.03,        -- the muzzle stops this far off the wall (m)
    muzzle_tilt = true,     -- the gun turns at the wrist away from the wall (Tefa 2026-11-18); false = the hand slides back
    tilt_max = 80,          -- the steepest turn (deg); past it the hand also slides back
    tilt_up = 0.5,          -- how much "up" is mixed into the way the gun turns away (a head-on wall: straight up)
    tilt_in_dps = 720,      -- how fast the gun turns away (deg/s)
    tilt_out_dps = 240,     -- and comes back
    max_push = 1.20,        -- the furthest a hand is ever sent back (walls.cpp WALLS_MAX_PUSH_M, the same number)
}
local function load_cfg()
    local okf, fh = pcall(io.open, FILE, "r")
    if not okf or not fh then return end
    fh:close()
    local ok, d = pcall(json.load_file, FILE)
    if ok and type(d) == "table" then
        for k, v in pairs(cfg) do
            if type(v) == "boolean" and type(d[k]) == "boolean" then cfg[k] = d[k] end
            if type(v) == "number" and type(d[k]) == "number" then cfg[k] = d[k] end
        end
    end
end
local function save_cfg() pcall(json.dump_file, FILE, cfg) end
load_cfg()

-- ===== the ray (visceral_re8_magthrow.lua's) =====
local cast_ray = safe(function() return sdk.find_type_definition("via.physics.System"):get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)") end)
local LAYER, LAYER_NAME = nil, "?"
pcall(function()
    local layers = require("utility/Statics").generate("app.CollisionManager.Layer")
    local names = {}
    for k, v in pairs(layers) do names[#names + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(names)
    L("the game's collision layers: " .. table.concat(names, ", "))
    -- 2026-11-18, simulator: a ray from the head straight down hit the floor on Bullet (12) and Default (0, 8 hits), and
    -- NOTHING on Terrain (1) `[verified-live 2026-11-18, simulator, n=1]`: Bullet, the thrown magazine's layer
    for _, want in ipairs({ "Bullet" }) do
        if layers[want] ~= nil then LAYER, LAYER_NAME = layers[want], want; break end
    end
    L("the hands' rays use the layer " .. LAYER_NAME)
end)

local seen_names, seen_count = {}, 0
local function names_up(go)   -- the hit's own name and its parents', for the door check and the log
    local out = {}
    local tf = go and safe(function() return go:call("get_Transform") end)
    for _ = 1, 4 do
        if tf == nil then break end
        local g = safe(function() return tf:call("get_GameObject") end)
        local n = g and safe(function() return g:call("get_Name") end)
        if n then out[#out + 1] = tostring(n) end
        tf = safe(function() return tf:call("get_Parent") end)
    end
    return out
end
local function is_door(names)
    for _, n in ipairs(names) do
        local l = string.lower(n)
        if l:find("door", 1, true) or l:find("gate", 1, true) then return true end
    end
    return false
end

-- one ray from a to b: the nearest hit that is not a door, { p, n }, or nil
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
        if LAYER then fi:call("set_Layer", LAYER) end
        q:call("set_FilterInfo", fi)
        cast_ray:call(sys, q, r)
        local count = r:call("get_NumContactPoints") or 0
        for i = 0, math.min(count, 4) - 1 do
            local cp = r:call("getContactPoint(System.UInt32)", i)
            local col = safe(function() return r:call("getContactCollidable(System.UInt32)", i) end)
            local go = col and safe(function() return col:call("get_GameObject") end)
            local names = go and names_up(go) or {}
            if go == nil then once("nocol", "a ray hit has no readable owner (getContactCollidable): doors cannot be told from walls") end
            local key = names[1] or "?"
            if seen_count < 20 and not seen_names[key] then
                seen_names[key] = true; seen_count = seen_count + 1
                L("a hand's ray hit: " .. table.concat(names, " < ") .. (is_door(names) and "  (a door: skipped)" or ""))
            end
            if not is_door(names) and cp then
                local p, n = cp:get_field("Position"), cp:get_field("Normal")
                if p then return { p = { x = p.x, y = p.y, z = p.z }, n = n and { x = n.x, y = n.y, z = n.z } or nil } end
            end
        end
        return nil
    end)
end

-- ===== small maths =====
local function v(x, y, z) return { x = x, y = y, z = z } end
local function sub(a, b) return v(a.x - b.x, a.y - b.y, a.z - b.z) end
local function add(a, b) return v(a.x + b.x, a.y + b.y, a.z + b.z) end
local function mul(a, s) return v(a.x * s, a.y * s, a.z * s) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function len(a) return math.sqrt(dot(a, a)) end
local function qrot(q, p)   -- rotate p by the unit quaternion q
    local ux, uy, uz, w = q.x, q.y, q.z, q.w
    local tx, ty, tz = 2 * (uy * p.z - uz * p.y), 2 * (uz * p.x - ux * p.z), 2 * (ux * p.y - uy * p.x)
    return v(p.x + w * tx + (uy * tz - uz * ty), p.y + w * ty + (uz * tx - ux * tz), p.z + w * tz + (ux * ty - uy * tx))
end

local function qconj(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end
local function qmul(a, b)   -- a * b: b first, then a
    return { x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w, w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z }
end
local function cross(a, b) return v(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function facing(n, dir)   -- the hit's normal, unit length, on the player's side (against the ray)
    if n == nil or len(n) < 0.5 then n = mul(dir, -1) end
    n = mul(n, 1 / len(n))
    if dot(n, dir) > 0 then n = mul(n, -1) end
    return n
end

-- ===== each frame =====
local hit_log_t = { 0, 0 }
local GEN = (rawget(_G, "__visceral_walls_gen") or 0) + 1   -- a copy loaded again by hand (dofile) takes over; the old one stops
rawset(_G, "__visceral_walls_gen", GEN)
local muz = { gun = -1, local_ = nil, prev_hand = nil, prev_q = nil, prev_plane = nil, tilt = 0.0, axis = nil, prev_tilt_q = nil }   -- the gun's muzzle in the hand's frame
local function update()
    if rawget(_G, "__visceral_walls_gen") ~= GEN then return end
    local b = rawget(_G, "visceral_re8_bridge")
    if not cfg.enabled or b == nil or not b.ready() then return end
    local re8vr = rawget(_G, "re8vr")
    if re8vr == nil or re8vr.can_use_hands == false or re8vr.is_in_cutscene == true then return end
    local cx = safe(function() return sdk.get_primary_camera():call("get_GameObject"):call("get_Transform") end)
    local cp, cr = cx and safe(function() return cx:call("get_Position") end), cx and safe(function() return cx:call("get_Rotation") end)
    if not (cp and cr) then return end
    local cam = v(cp.x, cp.y, cp.z)
    local right = qrot({ x = cr.x, y = cr.y, z = cr.z, w = cr.w }, v(1, 0, 0))
    right.y = 0
    local rl = len(right)
    if rl < 1e-3 then return end
    right = mul(right, 1 / rl)
    local gun_num = b.r(S_WEAPON_NUM)
    local gun = gun_num > 0.5
    if gun_num ~= muz.gun then muz.gun, muz.local_, muz.tilt, muz.prev_tilt_q = gun_num, nil, 0.0, nil end   -- a new gun: its muzzle is learned again
    for side = 1, 2 do
        local hp = side == 1 and re8vr.last_left_hand_position or re8vr.last_right_hand_position
        local skip = hp == nil or type(hp.x) ~= "number"
            or (not cfg.with_gun and gun and side == 2)
            or (side == 1 and b.r(S_GRIPPING_WEAPON) > 0.5)   -- the left hand on the gun goes with the gun
        if not skip then
            local hand = v(hp.x, hp.y, hp.z)
            local best = nil   -- { p, n, d, why }: the plane that needs the hand furthest back
            local function offer(p, n, why)
                local d = dot(sub(hand, p), n)
                if best == nil or d < best.d then best = { p = p, n = n, d = d, why = why } end
            end
            -- (1) the hand itself: a ray from about the shoulder to the hand
            local shoulder = add(add(cam, v(0, -cfg.shoulder_down, 0)), mul(right, (side == 1 and -1 or 1) * cfg.shoulder_side))
            local d = sub(hand, shoulder)
            local dl = len(d)
            if dl >= cfg.min_reach and dl <= cfg.max_reach then
                local dir = mul(d, 1 / dl)
                local h = ray(shoulder, add(hand, mul(dir, cfg.hand_r)))
                if h then
                    local n = facing(h.n, dir)
                    offer(add(h.p, mul(n, cfg.hand_r)), n, "hand")
                end
            end
            -- (2) the gun in the right hand. 2026-11-18, Tefa: "see if long guns also stop at the wall, i mean that even the tip
            -- of the gun doesn't go in the wall"; then (b141): "instead of pushing the hand back, can right hand stay put and the
            -- weapon angle away from the wall and the hand at the wrist just follows". So: where the muzzle WOULD be with the hand
            -- where the player holds it; a ray from the hand to there; on a hit the gun turns at the wrist, away from the wall
            -- and a little up, just far enough for the muzzle to stay off it (eased in and out). Only when even tilt_max is not
            -- enough does the hand also slide back for the rest.
            if side == 2 and gun and cfg.with_gun and cfg.muzzle then
                local hr = re8vr.last_right_hand_rotation
                local mp = re8vr.last_muzzle_pos
                local q = hr and type(hr.w) == "number" and { x = hr.x, y = hr.y, z = hr.z, w = hr.w } or nil
                -- (2026-11-18, simulator: re8vr.last_right_hand_rotation is NOT unit length, e.g. -0.36 -0.63 -0.48 1.00;
                -- the turns below assume a unit one, so it is made one)
                if q then
                    local ql = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
                    if ql > 1e-6 then q = { x = q.x / ql, y = q.y / ql, z = q.z / ql, w = q.w / ql } else q = nil end
                end
                local now = os.clock()
                local dt = math.min(0.1, math.max(0.0, now - (muz.t or now)))
                muz.t = now
                -- learn where the muzzle sits in the hand's own frame, from last frame's drawn muzzle and last frame's hand
                -- as it was drawn (moved by last frame's plane and turned by last frame's tilt, as walls.cpp did)
                if q and mp and type(mp.x) == "number" and muz.prev_hand and muz.prev_q then
                    local drawn = muz.prev_hand
                    if muz.prev_plane then
                        local pd = dot(sub(drawn, muz.prev_plane.p), muz.prev_plane.n)
                        if pd < 0 and pd > -cfg.max_push then drawn = sub(drawn, mul(muz.prev_plane.n, pd)) end
                    end
                    local drawn_q = muz.prev_tilt_q and qmul(muz.prev_tilt_q, muz.prev_q) or muz.prev_q
                    local l = qrot(qconj(drawn_q), sub(v(mp.x, mp.y, mp.z), drawn))
                    local ll = len(l)
                    if ll > 0.05 and ll < 1.3 then
                        muz.local_ = muz.local_ and add(mul(muz.local_, 0.8), mul(l, 0.2)) or l   -- eased: the drawn arm lags a frame
                    end
                end
                local want = 0.0   -- the tilt wanted this frame (radians)
                if q and muz.local_ then
                    local barrel = qrot(q, muz.local_)
                    local bl = len(barrel)
                    if bl > 0.05 then
                        local bdir = mul(barrel, 1 / bl)
                        local h = ray(hand, add(add(hand, barrel), mul(bdir, cfg.muzzle_r)))
                        if h then
                            local n = facing(h.n, bdir)
                            if cfg.muzzle_tilt then
                                -- away from the wall, and a little up (a head-on wall: up)
                                local up = v(0, 1, 0)
                                local nperp = sub(n, mul(bdir, dot(n, bdir)))
                                local uperp = sub(up, mul(bdir, dot(up, bdir)))
                                local u = add(nperp, mul(uperp, cfg.tilt_up))
                                if len(u) < 1e-3 then u = uperp end
                                if len(u) > 1e-3 then
                                    u = mul(u, 1 / len(u))
                                    local need = cfg.muzzle_r - dot(sub(hand, h.p), n)   -- dot(turned barrel, n) must reach this
                                    local found = nil
                                    for deg = 0, cfg.tilt_max, 2 do
                                        local t = math.rad(deg)
                                        if dot(add(mul(barrel, math.cos(t)), mul(u, bl * math.sin(t))), n) >= need then found = t; break end
                                    end
                                    want = found or math.rad(cfg.tilt_max)
                                    local ax = cross(bdir, u)
                                    if len(ax) > 1e-3 then muz.axis = mul(ax, 1 / len(ax)) end
                                    if found == nil then   -- even the steepest tilt is not enough: the hand gives way for the rest
                                        local t = want
                                        local bt = add(mul(barrel, math.cos(t)), mul(u, bl * math.sin(t)))
                                        offer(sub(add(h.p, mul(n, cfg.muzzle_r)), bt), n, "muzzle")
                                    end
                                    muz.why = "tilt"
                                end
                            else
                                offer(sub(add(h.p, mul(n, cfg.muzzle_r)), barrel), n, "muzzle")
                            end
                        end
                    end
                end
                -- ease the tilt toward what is wanted (fast in, slower out), and hand it to walls.cpp
                local rate = math.rad(want > (muz.tilt or 0) and cfg.tilt_in_dps or cfg.tilt_out_dps)
                muz.tilt = muz.tilt or 0.0
                if want > muz.tilt then muz.tilt = math.min(want, muz.tilt + rate * dt) else muz.tilt = math.max(want, muz.tilt - rate * dt) end
                muz.prev_tilt_q = nil
                if muz.tilt > 1e-3 and muz.axis then
                    local hs = math.sin(muz.tilt * 0.5)
                    local tq = { x = muz.axis.x * hs, y = muz.axis.y * hs, z = muz.axis.z * hs, w = math.cos(muz.tilt * 0.5) }
                    b.w(S_TILT_Q, tq.x); b.w(S_TILT_Q + 1, tq.y); b.w(S_TILT_Q + 2, tq.z); b.w(S_TILT_Q + 3, tq.w)
                    b.w(S_TILT_ON, b.r(S_FRAME) + 1.0)   -- LAST
                    muz.prev_tilt_q = tq
                    if now - (muz.log_t or 0) > 2.0 then
                        muz.log_t = now
                        L(string.format("the gun's muzzle meets a wall: the gun turns %.0f deg at the wrist", math.deg(muz.tilt)))
                    end
                end
                muz.prev_hand, muz.prev_q = hand, q
                -- the drawn muzzle for doors.cpp: a gun pushes doors too (Tefa 2026-11-18)
                if mp and type(mp.x) == "number" then
                    b.w(S_MUZZLE_W, mp.x); b.w(S_MUZZLE_W + 1, mp.y); b.w(S_MUZZLE_W + 2, mp.z)
                    b.w(S_MUZZLE_ON, b.r(S_FRAME) + 1.0)
                end
            end
            local s = SLOTS[side]
            if best then
                b.w(s.p, best.p.x); b.w(s.p + 1, best.p.y); b.w(s.p + 2, best.p.z)
                b.w(s.n, best.n.x); b.w(s.n + 1, best.n.y); b.w(s.n + 2, best.n.z)
                b.w(s.on, b.r(S_FRAME) + 1.0)   -- LAST, after the numbers
                if os.clock() - hit_log_t[side] > 2.0 and best.d < 0 then
                    hit_log_t[side] = os.clock()
                    L(string.format("the %s %s meets a wall: the hand goes %.0f cm back", side == 1 and "left" or "right",
                        best.why == "muzzle" and "gun's muzzle" or "hand", -best.d * 100))
                end
            end
            if side == 2 then muz.prev_plane = best and { p = best.p, n = best.n } or nil end
        end
    end
end

-- after praydog's layer has placed the hands for this frame, before the game's own motion solves the arms again
re.on_application_entry("LateUpdateBehavior", function() local ok, e = pcall(update); if not ok then once("err", "update failed: " .. tostring(e)) end end)

_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 50, kind = "check", label = "Hands stop at walls",
    help = "Your hands slide along walls instead of going through them. Doors and gates still open by hand.",
    get = function() return cfg.enabled end, set = function(x) cfg.enabled = x == true; save_cfg() end })
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 51, kind = "check", label = "...with a gun in the hand too",
    help = "Off: the hand holding a gun goes through walls as before.",
    get = function() return cfg.with_gun end, set = function(x) cfg.with_gun = x == true; save_cfg() end })

L("loaded: hands stop at walls " .. (cfg.enabled and "ON" or "off") .. ", with a gun " .. (cfg.with_gun and "too" or "no"))
