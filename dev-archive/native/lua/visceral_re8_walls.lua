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
local cfg = {
    enabled = true,
    with_gun = true,        -- the hand holding a gun stops too (the gun with it)
    hand_r = 0.05,          -- the hand's radius: it stops this far off the wall (m)
    shoulder_down = 0.18,   -- the ray starts this far below the camera
    shoulder_side = 0.17,   -- and this far out to the hand's own side
    min_reach = 0.20,       -- a hand nearer the shoulder than this is never checked
    max_reach = 1.50,       -- nor one further than this (2026-11-18, simulator: while a save loads the hand sits 130 m away)
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

-- ===== each frame =====
local hit_log_t = { 0, 0 }
local function update()
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
    local gun = b.r(S_WEAPON_NUM) > 0.5
    for side = 1, 2 do
        local hp = side == 1 and re8vr.last_left_hand_position or re8vr.last_right_hand_position
        local skip = hp == nil or type(hp.x) ~= "number"
            or (not cfg.with_gun and gun and side == 2)
            or (side == 1 and b.r(S_GRIPPING_WEAPON) > 0.5)   -- the left hand on the gun goes with the gun
        if not skip then
            local hand = v(hp.x, hp.y, hp.z)
            local shoulder = add(add(cam, v(0, -cfg.shoulder_down, 0)), mul(right, (side == 1 and -1 or 1) * cfg.shoulder_side))
            local d = sub(hand, shoulder)
            local dl = len(d)
            if dl >= cfg.min_reach and dl <= cfg.max_reach then
                local dir = mul(d, 1 / dl)
                local h = ray(shoulder, add(hand, mul(dir, cfg.hand_r)))
                if h then
                    local n = h.n
                    if n == nil or len(n) < 0.5 then n = mul(dir, -1) end
                    n = mul(n, 1 / len(n))
                    if dot(n, dir) > 0 then n = mul(n, -1) end   -- the side facing the player
                    local stop = add(h.p, mul(n, cfg.hand_r))
                    local s = SLOTS[side]
                    b.w(s.p, stop.x); b.w(s.p + 1, stop.y); b.w(s.p + 2, stop.z)
                    b.w(s.n, n.x); b.w(s.n + 1, n.y); b.w(s.n + 2, n.z)
                    b.w(s.on, b.r(S_FRAME) + 1.0)   -- LAST, after the numbers
                    if os.clock() - hit_log_t[side] > 2.0 then
                        hit_log_t[side] = os.clock()
                        L(string.format("the %s hand meets a wall %.2f m from the shoulder (the hand is %.2f m out)", side == 1 and "left" or "right", len(sub(h.p, shoulder)), dl))
                    end
                end
            end
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
